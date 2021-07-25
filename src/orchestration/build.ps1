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

. (Join-Path (Split-Path -Parent -Path (Split-Path -Parent -Path $PSScriptRoot)) 'helpers.ps1')

# ---------------------------------- Functions ---------------------------------

# ---------------------------------- Functions ---------------------------------

 $groupName = 'orchestration'

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
    'resource.hashi.orchestrator'
)

$planPath = Join-Path $groupBuildDirectory 'hyperv-meta.plan'

if ($apply)
{
    "Applying terraform plan at: $planPath"
    Publish-TerraformPlan `
        -planPath $planPath `
        -srcDirectory $srcDirectory
}
else
{
    # read the config file
    $json = Get-Config -configFile $configFile

    $adDomainName = $json.active_directory.domain_name
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
