[CmdletBinding()]
param(
    [string] $artefactDirectory,
    [string] $configDirectory,
    [string] $configFile,
    [switch] $apply,
    [switch] $destroy
)

$ErrorActionPreference = 'Stop'

# ---------------------------------- Functions ---------------------------------

function New-ProvisionIso
{
    [CmdletBinding()]
    param(
        [string] $path,
        [string] $isoFile
    )

    $directory = Split-Path -Parent -Path $isoFile
    Write-Output "Putting ISO file in $directory"
    if (-not (Test-Path $directory))
    {
        New-Item -ItemType Directory -Path $directory
    }

    & mkisofs.exe -r -iso-level 4 -UDF -o $isoFile $path
}

function New-TerraformPlan
{
    [CmdletBinding()]
    param(
        [string] $group,
        [string] $srcDirectory,
        [string] $artefactDirectory,
        [string] $isoDirectory,
        [string] $buildDirectory,
        [string] $adDomainName,
        [string] $configFile
    )

    Write-Output "Planning resource changes for $group ..."
    $script = Join-Path (Join-Path $srcDirectory $group) 'build.ps1'

    & $script `
        -artefactDirectory $artefactDirectory `
        -isoDirectory $isoDirectory `
        -buildDirectory $buildDirectory `
        -configFile $configFile `
}

function Publish-TerraformPlan
{
    [CmdletBinding()]
    param(
        [string] $group,
        [string] $srcDirectory,
        [string] $buildDirectory
    )

    Write-Output "Creating resources for $group ..."
    $script = Join-Path (Join-Path $srcDirectory $group) 'build.ps1'

    & $script `
        -buildDirectory $buildDirectory `
        -apply
}

function Remove-TerraformPlan
{
    [CmdletBinding()]
    param(
        [string] $group,
        [string] $srcDirectory,
        [string] $artefactDirectory,
        [string] $isoDirectory,
        [string] $buildDirectory,
        [string] $configFile
    )

    Write-Output "Removing resources for $group ..."
    $script = Join-Path (Join-Path $srcDirectory $group) 'build.ps1'

    & $script `
        -artefactDirectory $artefactDirectory `
        -isoDirectory $isoDirectory `
        -buildDirectory $buildDirectory `
        -configFile $configFile `
        -destroy
}

# ---------------------------------- Functions ---------------------------------

$buildDirectory = Join-Path $PSScriptRoot 'build'
$tempDirectory = Join-Path $buildDirectory 'temp'
$isoDirectory = Join-Path $tempDirectory 'iso'
$srcDirectory = Join-Path $PSScriptRoot 'src'

if (-not $apply)
{
    $isoConfigDirectory = Join-Path $configDirectory 'iso'
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'consul-server-01') -isoFile (Join-Path $isoDirectory 'server-0.iso')
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'consul-server-02') -isoFile (Join-Path $isoDirectory 'server-1.iso')
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'consul-server-02') -isoFile (Join-Path $isoDirectory 'server-2.iso')
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'linux-client') -isoFile (Join-Path $isoDirectory 'linux-client.iso')
    New-ProvisionIso -path (Join-Path $isoConfigDirectory 'windows-client') -isoFile (Join-Path $isoDirectory 'windows-client.iso')
}

$orderedGroups = @(
    'service-discovery',
    'proxy'
    'secrets'
    #'queue'
    #'metrics`
    #'documents'
    #'orchestration`
)

if ($destroy)
{
    # Reverse foreach
    #Remove-TerraformPlan
}
else
{
    foreach ($group in $orderedGroups)
    {
        if ($apply)
        {
            Publish-TerraformPlan `
                -group $group `
                -srcDirectory $srcDirectory `
                -buildDirectory $buildDirectory
        }
        else
        {
            New-TerraformPlan `
                -group $group `
                -srcDirectory $srcDirectory `
                -artefactDirectory $artefactDirectory `
                -isoDirectory $isoDirectory `
                -buildDirectory $buildDirectory `
                -configFile $configFile
        }
    }
}
