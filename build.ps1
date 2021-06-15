[CmdletBinding()]
param(
    [string] $artefactDirectory,
    [string] $configDirectory,
    [string] $adDomainName,
    [string] $adHost,
    [string] $hypervHost,
    [string] $userName,
    [string] $userPassword,
    [switch] $apply,
    [switch] $destroy
)

$ErrorActionPreference = 'Stop'

# ---------------------------------- Functions ---------------------------------

function Expand-Artefact
{
    [CmdletBinding()]
    param(
        [string] $name,
        [string] $targetDirectory,
        [string] $artefactDirectory
    )

    $artefact = Get-ChildItem -Path "$artefactDirectory\*" -Filter "$($name)-*.zip" |
        Sort-Object LastWriteTime |
        Select-Object -Last 1

    $unzipDirectory = Join-Path $targetDirectory $name
    New-DirectoryIfNotExists -path $unzipDirectory

    Expand-Archive -Path $artefact.FullName -DestinationPath $unzipDirectory
}

function New-DirectoryIfNotExists
{
    [CmdletBinding()]
    param(
        [string] $path
    )

    if (Test-Path $path)
    {
        Remove-Item -Path "$path\*" -Recurse -Force
    }
    else
    {
        New-Item -Path $path -ItemType Directory | Out-Null
    }
}

function New-ProvisionIso
{
    [CmdletBinding()]
    param(
        [string] $path,
        [string] $isoFile
    )

    & mkisofs.exe -r -iso-level 4 -UDF -o $isoFile $path
}

function New-TerraformPlan
{
    [CmdletBinding()]
    param(
        [string[]] $artefactNames,
        [string] $artefactDirectory,
        [string] $configDirectory,
        [string] $adDomainName,
        [string] $adHost,
        [string] $hypervHost,
        [string] $userName,
        [string] $userPassword,
        [string] $hypervDirectory,
        [string] $isoDirectory,
        [string] $planPath,
        [string] $srcDirectory,
        [string] $tempDirectory,
        [string] $tempArtefactDirectory
    )

    New-DirectoryIfNotExists -path $buildDirectory
    New-DirectoryIfNotExists -path $hypervDirectory
    New-DirectoryIfNotExists -path $tempDirectory
    New-DirectoryIfNotExists -path $isoDirectory
    New-DirectoryIfNotExists -path $tempArtefactDirectory

    foreach ($name in $artefactNames)
    {
        Expand-Artefact `
            -name $name `
            -targetDirectory $tempArtefactDirectory `
            -artefactDirectory $artefactDirectory
    }

    $isoConfigDirectory = Join-Path $configDirectory 'iso'
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'consul-server-01') -isoFile (Join-Path $isoDirectory 'server-0.iso')
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'consul-server-02') -isoFile (Join-Path $isoDirectory 'server-1.iso')
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'consul-server-02') -isoFile (Join-Path $isoDirectory 'server-2.iso')
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'linux-client') -isoFile (Join-Path $isoDirectory 'linux-client.iso')
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'windows-client') -isoFile (Join-Path $isoDirectory 'windows-client.iso')

    Push-Location -Path $srcDirectory
    try
    {
        $env:TF_IN_AUTOMATION = 'true'
        $env:TF_LOG = 'trace'
        $env:TF_LOG_PATH = (Join-Path $tempDirectory 'tf-plan.log')
        $env:WINRMCP_DEBUG = 1

        & terraform validate
        if ($LASTEXITCODE -ne 0)
        {
            throw 'Validation failed'
        }

        & terraform init
        if ($LASTEXITCODE -ne 0)
        {
            throw 'Terraform init failed'
        }

        $command = '& terraform plan'
        $command += " -out $planPath"
        $command += " -var ad_domain=$adDomainName"
        $command += " -var ad_host=$adHost"
        $command += " -var 'path_artefacts=$tempArtefactDirectory'"
        $command += " -var 'path_hyperv_temp=$hypervDirectory'"
        $command += " -var 'path_hyperv_vhd=$hypervDirectory'"
        $command += " -var 'path_provisioning_iso=$isoDirectory'"
        $command += " -var 'hyperv_administrator_user=$userName'"
        $command += " -var 'hyperv_administrator_password=$userPassword'"
        $command += " -var 'hyperv_server_address=$hypervHost'"
        $command += " -var 'ad_administrator_user=$userName'"
        $command += " -var 'ad_administrator_password=$userPassword'"

        Invoke-Expression -Command $command
    }
    finally
    {
        Pop-Location
    }
}

function Publish-TerraformPlan
{
    [CmdletBinding()]
    param(
        [string] $planPath,
        [string] $srcDirectory
    )

    if (-not (Test-Path $planPath))
    {
        throw "Expected plan at: $planPath. No file found."
    }

    Push-Location -Path $srcDirectory
    try
    {
        $env:TF_IN_AUTOMATION = 'true'
        $env:TF_LOG = 'trace'
        $env:TF_LOG_PATH = (Join-Path $tempDirectory 'tf-apply.log')
        $env:WINRMCP_DEBUG = 1

        & terraform init
        if ($LASTEXITCODE -ne 0)
        {
            throw 'Terraform init failed'
        }

        $command = '& terraform apply'
        $command += " $planPath"

        Invoke-Expression -Command $command
    }
    finally
    {
        Pop-Location
    }
}

function Remove-TerraformPlan
{
    [CmdletBinding()]
    param(
        [string] $adDomainName,
        [string] $adHost,
        [string] $hypervHost,
        [string] $userName,
        [string] $userPassword,
        [string] $hypervDirectory,
        [string] $isoDirectory,
        [string] $planPath,
        [string] $srcDirectory,
        [string] $tempDirectory,
        [string] $tempArtefactDirectory
    )

    Push-Location -Path $srcDirectory
    try
    {
        $env:TF_IN_AUTOMATION = 'true'
        $env:TF_LOG = 'trace'
        $env:TF_LOG_PATH = (Join-Path $tempDirectory 'tf-plan.log')
        $env:WINRMCP_DEBUG = 1

        & terraform init
        if ($LASTEXITCODE -ne 0)
        {
            throw 'Terraform init failed'
        }

        $command = '& terraform destroy'
        $command += " -var ad_domain=$adDomainName"
        $command += " -var ad_host=$adHost"
        $command += " -var 'path_artefacts=$tempArtefactDirectory'"
        $command += " -var 'path_hyperv_temp=$hypervDirectory'"
        $command += " -var 'path_hyperv_vhd=$hypervDirectory'"
        $command += " -var 'path_provisioning_iso=$isoDirectory'"
        $command += " -var 'hyperv_administrator_user=$userName'"
        $command += " -var 'hyperv_administrator_password=$userPassword'"
        $command += " -var 'hyperv_server_address=$hypervHost'"
        $command += " -var 'ad_administrator_user=$userName'"
        $command += " -var 'ad_administrator_password=$userPassword'"

        Invoke-Expression -Command $command
    }
    finally
    {
        Pop-Location
    }
}

# ---------------------------------- Functions ---------------------------------

$buildDirectory = Join-Path $PSScriptRoot 'build'
$hypervDirectory = Join-Path $buildDirectory 'hyperv'
$tempDirectory = Join-Path $buildDirectory 'temp'
$isoDirectory = Join-Path $tempDirectory 'iso'
$tempArtefactDirectory = Join-Path $tempDirectory 'artefacts'
$srcDirectory = Join-Path $PSScriptRoot 'src'

# Get the resource archives
$artefactNames = @(
    'resource.hashi.server',
    'resource.hashi.ui'
    #'resource.hashi.orchestrator',
    #'resource.secrets',
    #'resource.proxy.edge',
    #'resource.queue',
    #'resource.metrics.storage',
    #'resource.metrics.dashboard',
    #'resource.documents.storage',
    #'resource.documents.dashboard',
    #'resource.logs.processor'
)

$planPath = Join-Path $buildDirectory 'hyperv-meta.plan'

if ($apply)
{
    "Applying terraform plan at: $planPath"
    Publish-TerraformPlan `
        -planPath $planPath `
        -srcDirectory $srcDirectory
}
else
{
    if ($destroy)
    {
        Remove-TerraformPlan `
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
            -artefactNames $artefactNames `
            -artefactDirectory $artefactDirectory `
            -configDirectory $configDirectory `
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
}
