[CmdletBinding()]
param(
    [string] $artefactDirectory,
    [string] $configDirectory,
    [string] $userName,
    [string] $userPassword
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

# ---------------------------------- Functions ---------------------------------

$buildDirectory = Join-Path $PSScriptRoot 'build'
New-DirectoryIfNotExists -path $buildDirectory

$hypervDirectory = Join-Path $buildDirectory 'hyperv'
New-DirectoryIfNotExists -path $hypervDirectory

$tempDirectory = Join-Path $buildDirectory 'temp'
New-DirectoryIfNotExists -path $tempDirectory

$isoDirectory = Join-Path $tempDirectory 'iso'
New-DirectoryIfNotExists -path $isoDirectory

$tempArtefactDirectory = Join-Path $tempDirectory 'artefacts'
New-DirectoryIfNotExists -path $tempArtefactDirectory

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

foreach ($name in $artefactNames) {
    Expand-Artefact `
        -name $name `
        -targetDirectory $tempArtefactDirectory `
        -artefactDirectory $artefactDirectory
}

$isoConfigDirectory = Join-Path $configDirectory 'iso'
New-ProvisionIso -path (Join-Path $isoConfigDirectory 'consul-server-01') -isoFile (Join-Path $isoDirectory 'server-1.iso')
New-ProvisionIso -path (Join-Path $isoConfigDirectory 'consul-server-02') -isoFile (Join-Path $isoDirectory 'server-2.iso')
New-ProvisionIso -path (Join-Path $isoConfigDirectory 'consul-server-02') -isoFile (Join-Path $isoDirectory 'server-3.iso')
New-ProvisionIso -path (Join-Path $isoConfigDirectory 'linux-client') -isoFile (Join-Path $isoDirectory 'linux-client.iso')
New-ProvisionIso -path (Join-Path $isoConfigDirectory 'windows-client') -isoFile (Join-Path $isoDirectory 'windows-client.iso')

Push-Location -Path $srcDirectory
try {
    $env:TF_IN_AUTOMATION = 'true'
    $env:TF_LOG = 'trace'
    $env:TF_LOG_PATH = (Join-Path $tempDirectory 'tf.log')

    $planPath = Join-Path $buildDirectory 'hyperv-meta.plan'
    #& terraform validate
    if ($LASTEXITCODE -ne 0)
    {
        throw 'Validation failed'
    }

    & terraform init
    if ($LASTEXITCODE -ne 0)
    {
        throw 'Terraform init failed'
    }

    $varPathArtefacts = "'path_artefacts=$tempArtefactDirectory'"
    $varPathHypervTemp = "'path_hyperv_temp=$hypervDirectory'"
    $varPathHypervVhd = "'path_hyperv_vhd=$hypervDirectory'"
    $varProvisioningIso = "'path_provisioning_iso=$isoDirectory'"
    $varHypervUser = "'hyperv_administrator_user=$userName'"
    $varHypervPassword = "'hyperv_administrator_password=$userPassword'"
    $varAdUser = "'ad_administrator_user=$userName'"
    $varAdPassword = "'ad_administrator_password=$userPassword'"
    & terraform plan -out="$planPath" -var $varPathArtefacts -var $varPathHypervTemp -var $varPathHypervVhd -var $varProvisioningIso  -var $varHypervUser -var $varHypervPassword -var $varAdUser -var $varAdPassword
}
finally {
    Pop-Location
}

# Return plan + diff
