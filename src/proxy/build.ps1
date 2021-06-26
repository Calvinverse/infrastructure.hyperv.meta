[CmdletBinding()]
param(
    [string] $artefactDirectory,
    [string] $isoDirectory,
    [string] $buildDirectory,
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
    if (Test-Path $unzipDirectory)
    {
        Remove-Item -Recurse -Force $unzipDirectory
    }

    New-DirectoryIfNotExists -path $unzipDirectory

    Expand-Archive -Path $artefact.FullName -DestinationPath $unzipDirectory
}

function New-DirectoryIfNotExists
{
    [CmdletBinding()]
    param(
        [string] $path
    )

    if (-not (Test-Path $path))
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
        [string] $groupName,
        [string[]] $artefactNames,
        [string] $artefactDirectory,
        [string] $isoDirectory,
        [string] $adDomainName,
        [string] $adHost,
        [string] $hypervHost,
        [string] $userName,
        [string] $userPassword,
        [string] $hypervDirectory,
        [string] $planPath,
        [string] $srcDirectory,
        [string] $tempDirectory,
        [string] $tempArtefactDirectory
    )

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

        & terraform validate
        if ($LASTEXITCODE -ne 0)
        {
            throw 'Validation failed'
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
        [string] $groupName,
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
    'resource.proxy.edge'
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
