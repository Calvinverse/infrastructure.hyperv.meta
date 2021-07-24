[CmdletBinding()]
param(
    [string] $artefactDirectory,
    [string] $isoDirectory,
    [string] $buildDirectory,
    [string] $configFile,
    [switch] $apply,
    [switch] $destroy,
    [switch] $useExistingServer
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent -Path (Split-Path -Parent -Path $PSScriptRoot)) 'helpers.ps1')

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
            $key = $line.Substring($line.IndexOf(':') + 1).Trim()
            $keys += $key
        }

        if ($line.StartsWith('Initial Root Token:') )
        {
            $rootToken = $line.Substring($line.IndexOf(':') + 1).Trim()
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
        [string] $vaultServerAddress,
        [string] $certificateServerAddress,
        [string] $caName,
        [string] $tempDir
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

    # Set the location of the server
    $setUrls = @(
        "$($name)/config/urls",
        "issuing_certificates=`"http://$($vaultServerAddress):8200/v1/$($name)/ca`"",
        "crl_distribution_points=`"http://$($vaultServerAddress):8200/v1/$($name)/crl`""
    )
    $output = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $setUrls

    $getCsr = @(
        "$($name)/intermediate/generate/internal",
        "common_name=`"secrets.infrastructure.$adDomain intermediate`"",
        "ttl=43800h",
        "add_basic_constraints=true"
    )
    $output = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $getCsr

    $singleLine = $output | Out-String

    $csr = $singleLine.Substring($singleLine.Indexof('csr') + 3).Trim()

    # Write the csr to file and push it to the certificate authority for signing
    # sign it with
    $csrPath = Join-Path $tempDir 'vault.req'
    Out-File -FilePath $csrPath -InputObject $csr

    $certPath = Join-Path $tempDir 'vault.cer'
    if (Test-Path $certPath)
    {
        Remove-Item -Path $certPath
    }

    $intermediatePath = Join-Path $tempDir 'vault.rsp'
    if (Test-Path $intermediatePath)
    {
        Remove-Item -Path $intermediatePath
    }

    & certreq -submit -attrib "CertificateTemplate:SubCA" -config "$($certificateServerAddress)\$($caName)" $csrPath $certPath

    # Import the signed vault.cer file with
    $setCsr = @(
        "$($name)/intermediate/set-signed",
        "certificate=@$($certPath)"
    )
    $output = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $setCsr
}

function New-VaultSshMount
{
    [CmdletBinding()]
    param(
        [string] $name,
        [string] $vaultPath,
        [string] $vaultServerAddress,
        [string] $consulServerAddress
    )

    Set-VaultSshClientCertificate `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -consulHostName $consulServerAddress

    Set-VaultSshHostCertificate `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -consulHostName $consulServerAddress

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

    $url = "http://$($consulHostName):$($consulPort)/v1/kv/$($key)"
    Write-Output "Writing k-v with key: $($key) - value: $($value) to $($url)... "

    $webClient = New-Object System.Net.WebClient
    try
    {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)

        $responseBytes = $webClient.UploadData($url, "PUT", $bytes)
        $response = [System.Text.Encoding]::ASCII.GetString($responseBytes)
        Write-Output "Wrote k-v with key: $($key) - value: $($value). Response: $($response)"
    }
    finally
    {
        $webClient.Dispose()
    }
}

function Set-VaultPolicy
{
    [CmdletBinding()]
    param(
        [string] $vaultPath = 'vault',
        [string] $vaultServerAddress,
        [string] $path
    )

    $ErrorActionPreference = 'Stop'

    $file = Get-Item -Path $path
    $fileName = $file.Name
    $policyName = $file.BaseName

    $arguments = @(
        "sys/policy/$($policyName)",
        "policy=@$($path)"
    )

    Write-Output "Writing policy $($policyName) from $($fileName)"
    Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command 'write' `
        -arguments $arguments
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

    Write-Verbose "unsealKey: $unsealKey"

    $ErrorActionPreference = 'Stop'

    $returnValue = Invoke-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultServerAddress `
        -command "operator unseal" `
        -arguments @( '-format', 'json', $unsealKey )

    $singleLine = $returnValue | Out-String
    $json = ConvertFrom-Json -InputObject $singleLine

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

$groupName = 'secrets'

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
$adDomainName = $json.active_directory.domain_name

$consulHostName = "hashiserver-0.infrastructure.$($adDomainName)"
$vaultHostNames = @(
    "secrets-0.infrastructure.$($adDomainName)"
)

$vaultCname = "secrets.infrastructure.$($adDomainName)"
if ($apply)
{
    if (-not $useExistingServer)
    {
        "Applying terraform plan at: $planPath"
        Publish-TerraformPlan `
            -planPath $planPath `
            -srcDirectory $srcDirectory

        # Wait for the VM to restart
        Start-Sleep -Seconds 120
    }

    # init secrets-0.infrastructure.ad.calvinverse.net -> Store secrets in text file somewhere
    $keys = Init-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultHostNames[0]

    Write-Output -InputObject $keys

    Out-File -FilePath 'd:\temp\vault.keys' -InputObject $keys[0]

    # Unseal each of the servers
    foreach($vaultServer in $vaultHostNames)
    {
        Step-VaultUnseal `
            -vaultPath $vaultPath `
            -vaultServerAddress $vaultServer `
            -unsealKey $keys[0][0]

        Step-VaultUnseal `
            -vaultPath $vaultPath `
            -vaultServerAddress $vaultServer `
            -unsealKey $keys[0][1]

        Step-VaultUnseal `
            -vaultPath $vaultPath `
            -vaultServerAddress $vaultServer `
            -unsealKey $keys[0][2]
    }

    # Use the root password to log in
    Connect-Vault `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname `
        -token $keys[1]

    # Create the LDAP mount
    New-VaultLdapMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname `
        -ldapServerNameOrIp "$($json.active_directory.host).$($adDomainName)" `
        -userDn $json.active_directory.user_dn `
        -groupDn $json.active_directory.group_dn `
        -bindDn $json.active_directory.bind_user_dn `
        -bindPassword $json.active_directory.bind_user_password

    # Set the admin policy
    Set-VaultPolicy `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname `
        -path (Join-Path (Join-Path $PSScriptRoot 'policies') 'admin.hcl')

    # Run creation of all the mounts and policies
    New-VaultKvMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname

    New-VaultAppRoleMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname

    New-VaultConsulMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname

    New-VaultSshMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname `
        -consulServerAddress $consulHostName

    Set-VaultPolicy `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname `
        -path (Join-Path (Join-Path $PSScriptRoot 'policies') 'admin.hcl')

    $certificateServerName = $json.certificates.host
    $caName = $json.certificates.ca_name
    New-VaultPkiMount `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname `
        -certificateServerAddress "$($certificateServerName).$($adDomainName)" `
        -caName $caName `
        -tempDir $tempDirectory `


    # Remove the root token
    Revoke-VaultToken `
        -vaultPath $vaultPath `
        -vaultServerAddress $vaultCname `
        -token $keys[1]
}
else
{
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
