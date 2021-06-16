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
    )
}

function Publish-TerraformPlan
{
    [CmdletBinding()]
    param(
    )
}

function Remove-TerraformPlan
{
    [CmdletBinding()]
    param()
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

$orderedGroups = @(
    'service-discovery'
    #'secrets'
    #'proxy'
    #'queue'
    #'metrics`
    #'documents'
    #'orchestration`
)


if ($destroy)
{
    # Reverse foreach
    Remove-TerraformPlan
}
else
{
    foreach ($group in $orderedGroups)
    {
        if ($apply)
        {
            "Applying terraform plan at: $planPath"
            Publish-TerraformPlan
        }
        else
        {
            "Creating terraform plan at: $planPath"
            New-TerraformPlan
        }
    }
}
