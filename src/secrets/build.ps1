[CmdletBinding()]
param(
    [string] $artefactDirectory,
    [string] $isoDirectory,
    [string] $buildDirectory,
    [string] $configFile,
    [switch] $apply,
    [switch] $destroy
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent -Path $PSScriptRoot) 'helpers.ps1')

# ---------------------------------- Functions ---------------------------------

function Connect-Vault
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress,
        [string] $token
    )

    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'login' `
        -arguments @("token=$token")
}

function Init-Vault
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress
    )

    $ErrorActionPreference = 'Stop'

    $returnValue = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'operator init'

    # Expecting returnValue to be an array of strings looking like this
    #
    # Unseal Key 1: sP/4C/fwIDjJmHEC2bi/1Pa43uKhsUQMmiB31GRzFc0R
    # Unseal Key 2: kHkw2xTBelbDFIMEgEC8NVX7NDSAZ+rdgBJ/HuJwxOX+
    # Unseal Key 3: +1+1ZnkQDfJFHDZPRq0wjFxEuEEHxDDOQxa8JJ/AYWcb
    # Unseal Key 4: cewseNJTLovmFrgpyY+9Hi5OgJlJgGGCg7PZyiVdPwN0
    # Unseal Key 5: wyd7rMGWX5fi0k36X4e+C4myt5CoTmJsHJ0rdYT7BQcF
    #
    # Initial Root Token: 6662bb4a-afd0-4b6b-faad-e237fb564568

    $keys = @()
    foreach ($line in $returnValue)
    {
        if ($line.StartsWith('Unseal Key '))
        {
            $key = $line.Substring($line.IndexOf(':')).Trim()
            $keys += $key
        }

        if ($line.StartsWith('Initial Root Token:'))
        {
            $rootToken = $line.Substring($line.IndexOf(':')).Trim()
        }
    }

    return @( $keys, $rootToken)
}

function New-VaultAppRoleMount
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress
    )

    $ErrorActionPreference = 'Stop'

    $arguments = @(
        'approle'
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'auth enable' `
        -arguments $arguments
}

function New-VaultConsulMount
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress
    )

    $ErrorActionPreference = 'Stop'

    $arguments = @(
        'consul'
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'secrets enable' `
        -arguments $arguments
}

function New-VaultKvMount
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress
    )

    $ErrorActionPreference = 'Stop'

    $enableKv = @(
        '-version=1',
        '-path=secret',
        'kv'
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'secrets enable' `
        -arguments $enableKv
}

function New-VaultLdapMount
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress,
        [string] $ldapServerNameOrIp,
        [string] $userDn,
        [string] $groupDn,
        [string] $bindDn,
        [string] $bindPassword
    )

    $ErrorActionPreference = 'Stop'

    $enableLdap = @(
        'ldap'
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'auth enable' `
        -arguments $enableLdap

    $ldapConfigArguments = @(
        'auth/ldap/config',
        'userattr=sAMAccountName',
        "url=ldap://$($ldapServerNameOrIp)",
        "userdn=`"$($userDn)`"",
        "groupdn=`"$($groupDn)`"",
        'groupfilter="(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))"',
        'groupattr=cn',
        "binddn=`"$($bindDn)`"",
        "bindpass=`"$($bindPassword)`"",
        'insecure_tls=true',
        'starttls=false'
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $ldapConfigArguments

    $ldapAdminArguments = @(
        'auth/ldap/groups/"Infrastructure Administrators"',
        'policies=admin'
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $ldapAdminArguments
}

function New-VaultPkiMount
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress
    )

    $ErrorActionPreference = 'Stop'

    $name = 'pki-ca'
    $enablePki = @(
        "-path=$($name)",
        'pki'
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'secrets enable' `
        -arguments $enablePki

    # Max lease period is five years
    $setPki = @(
        "-max-lease-ttl=43800h",
        $name
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'secrets tune' `
        -arguments $setPki

    $getCsr = @(
        "$($name)/intermediate/generate/internal",
        "common_name=`"secrets.$adDomain intermediate`"",
        "ttl=43800h",
        "add_basic_constraints=true"
    )
    $output = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $getCsr

    $csr = $output[2].Substring($output[2].Indexof('csr'))

    # Write the csr to file and push it to the certificate authority for signing
    # sign it with
    #
    # certreq -submit -attrib "CertificateTemplate:SubCA" vault.req vault.cer

    #
    # Import the signed vault.cer file with
    # vault write pki-ca/intermediate/set-signed certificate=@<CERT_FILE_PATH>
}

function New-VaultSshMount
{
    [CmdletBinding()]
    param(
        [string] $name,
        [string] $vaultPath,
        [string] $vaultServerAddress
    )

    Set-VaultSshClientCertificate `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -consulHostName $consulHostName

    Set-VaultSshHostCertificate `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -consulHostName $consulHostName

    $mountCategory = 'client'
    $name = 'ssh.client.linux.admin'
    Set-VaultSshRole `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -category $mountCategory `
        -name $name `
        -rulePath (Join-Path (Join-Path (Join-Path $PSScriptRoot 'roles') 'ssh') "$($name).json")

    $mountCategory = 'host'
    $name = 'ssh.host.linux'
    Set-VaultSshRole `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -category $mountCategory `
        -name $name `
        -rulePath (Join-Path (Join-Path (Join-Path $PSScriptRoot 'roles') 'ssh') "$($name).json")
}

function Revoke-VaultToken
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress,
        [string] $token
    )

    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'token revoke' `
        -arguments @( $token)
}

function Set-VaultSshClientCertificate
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress,
        [string] $consulPort = 8500,
        [string] $consulHostName
    )

    $mount = 'ssh'
    $category = 'client'
    $name = "$($mount)-$($category)"
    $enableSshClientSigning = @(
        "-path=$($name)",
        'ssh'
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'secrets enable' `
        -arguments $enableSshClientSigning

    New-SshMount `
        -name $name `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress

    # Generate the key
    $setSshCA = @(
        "$($name)/config/ca",
        "generate_signing_key=true"
    )
    $output = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $setSshCA

    $publicKey = $output[2].Substring($output[2].Indexof('ssh-rsa'))

    # Write token for machine to consul kv
    # auth/services/templates/<MACHINE_NAME>/secrets
    $key = "auth/$($mount)/$($category)/ca/public"
    $value = $publicKey

    # Set the public key in Consul
    Set-ConsulKey `
        -key $key `
        -value $value `
        -consulPort $consulPort `
        -consulHostName $consulHostName
}

function Set-ConsulKey
{
    [CmdletBinding()]
    param(
        [string] $key,
        [string] $value,
        [string] $consulPort = 8500,
        [string] $consulHostName
    )

    Write-Output "Writing k-v with key: $($key) - value: $($value) ... "

    $webClient = New-Object System.Net.WebClient
    try
    {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)

        $url = "http://$($consulHostName):$($consulPort)/v1/kv/$($key)"
        $responseBytes = $webClient.UploadData($url, "PUT", $bytes)
        $response = [System.Text.Encoding]::ASCII.GetString($responseBytes)
        Write-Output "Wrote k-v with key: $($key) - value: $($value). Response: $($response)"
    }
    finally
    {
        $webClient.Dispose()
    }
}

function Set-VaultSshHostCertificate
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress,
        [string] $consulPort = 8500,
        [string] $consulHostName
    )

    $mount = 'ssh'
    $category = 'host'
    $name = "$($mount)-$($category)"
    $enableSshClientSigning = @(
        "-path=$($name)",
        'ssh'
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'secrets enable' `
        -arguments $enableSshClientSigning

    # Generate the key
    $setSshCA = @(
        "$($name)/config/ca",
        "generate_signing_key=true"
    )
    $output = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $setSshCA

    # Generate the key
    $tuneSshCA = @(
        "-max-lease-ttl=87600h",
        $name
    )
    $output = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'secrets tune' `
        -arguments $tuneSshCA

    $publicKey = $output[2].Substring($output[2].Indexof('ssh-rsa'))

    # Write token for machine to consul kv
    # auth/services/templates/<MACHINE_NAME>/secrets
    $key = "auth/$($mount)/$($category)/ca/public"
    $value = $publicKey

    # Set the public key in Consul
    Set-ConsulKey `
        -key $key `
        -value $value `
        -consulPort $consulPort `
        -consulHostName $consulHostName
}

function Set-VaultSshRole
{
    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress,
        [string] $category,
        [string] $name,
        [string] $rulePath
    )

    $mountName = 'ssh'
    $url = "$($vaultServerAddress)/v1/$($mountName)-$($category)/roles/$($name)"
    Write-Output "Writing SSH role with name: $($name) - role: $($roleJson) to $($url) ... "

    $setRole = @(
        "$($mountName)-$($category)/roles/$($name)",
        "@$($rulePath)"
    )
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $setRole
}

function Step-VaultUnseal
{

    [CmdletBinding()]
    param(
        [string] $vaultPath,
        [string] $vaultServerAddress,
        [string] $unsealKey
    )

    $ErrorActionPreference = 'Stop'

    $returnValue = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command "operator unseal" `
        -arguments @( $unsealKey, '-format', 'json' )

    $singleLine = $returnValue | Out-String
    $json = ConvertFrom-Json -InputObject $singleLine
    json.sealed

    $out = $null
    if ([bool]::TryParse($json.sealed, [ref]$out))
    {
        return $out
    }
    else
    {
        return $false
    }
}

# ---------------------------------- Functions ---------------------------------

 $groupName = 'proxy'

$relativeBuildDirectory = $buildDirectory
if (-not [System.IO.Path]::IsPathRooted($relativeBuildDirectory))
{
    $path = Join-Path $PSScriptRoot $relativeBuildDirectory
    $relativeBuildDirectory = [System.IO.Path]::GetFullPath($path)
}

$groupBuildDirectory = Join-Path $relativeBuildDirectory $groupName
$hypervDirectory = Join-Path (Join-Path $groupBuildDirectory 'hyperv') $groupName
$tempDirectory = Join-Path (Join-Path $groupBuildDirectory 'temp') $groupName
$tempArtefactDirectory = Join-Path (Join-Path $tempDirectory 'artefacts') $groupName
$srcDirectory = $PSScriptRoot

# Get the resource archives
$artefactNames = @(
    'resource.secrets'
)

$planPath = Join-Path $groupBuildDirectory 'hyperv-meta.plan'
$vaultPath = 'vault'

# read the config file
$json = Get-Config -configFile $configFile

$consulHostName = "hashiserver-0.$($adDomainName)"
$vaultHostName = "secrets.infrastructure.$($adDomainName)"
if ($apply)
{
    "Applying terraform plan at: $planPath"
    Publish-TerraformPlan `
        -planPath $planPath `
        -srcDirectory $srcDirectory

    # init secrets-0.infrastructure.ad.calvinverse.net -> Store secrets in text file somewhere
    $keys = Init-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName

    Out-File -FilePath 'd:\temp\vault.keys' -InputObject $keys[0]

    # Unseal
    Step-VaultUnseal `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName `
        -unsealKey $keys[0][0]

    Step-VaultUnseal `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName `
        -unsealKey $keys[0][1]

    Step-VaultUnseal `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName `
        -unsealKey $keys[0][2]

    # Use the root password to log in
    Connect-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName `
        -token $keys[1]

    # Create the LDAP mount
    New-VaultLdapMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName `
        -ldapServerNameOrIp $json.active_directory.host `
        -userDn $json.active_directory.user_dn `
        -groupDn $json.active_directory.group_dn `
        -bindDn $json.active_directory.bind_user_dn `
        -bindPassword $json.active_directory.bind_user_password

    # Run creation of all the mounts and policies
    New-VaultKvMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName

    New-VaultAppRoleMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName

    New-VaultConsulMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName

    New-VaultSshMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName

    New-VaultPkiMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName

    # Remove the root token
    Revoke-VaultToken `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostName `
        -token $keys[1]
}
else
{
    $adDomainName = $json.active_directory.domain_name,
    $adHost = $json.active_directory.host
    $hypervHost = $json.hyperv.host
    $userName = $json.active_directory.user_name
    $userPassword = $json.active_directory.password

    if ($destroy)
    {
        Remove-TerraformPlan `
            -groupName $groupName `
            -adDomainName $adDomainName `
            -adHost $adHost `
            -hypervHost $hypervHost `
            -userName $userName `
            -userPassword $userPassword `
            -hypervDirectory $hypervDirectory `
            -isoDirectory $isoDirectory `
            -planPath $planPath `
            -srcDirectory $srcDirectory `
            -tempDirectory $tempDirectory `
            -tempArtefactDirectory $tempArtefactDirectory
    }
    else
    {
        "Creating terraform plan at: $planPath"
        New-TerraformPlan `
            -groupName $groupName `
            -artefactNames $artefactNames `
            -artefactDirectory $artefactDirectory `
            -isoDirectory $isoDirectory `
            -adDomainName $adDomainName `
            -adHost $adHost `
            -hypervHost $hypervHost `
            -userName $userName `
            -userPassword $userPassword `
            -hypervDirectory $hypervDirectory `
            -planPath $planPath `
            -srcDirectory $srcDirectory `
            -tempDirectory $tempDirectory `
            -tempArtefactDirectory $tempArtefactDirectory
    }
}
