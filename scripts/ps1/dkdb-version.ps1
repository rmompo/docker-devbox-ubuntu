# Show every version: the project, each file, the tools, the images and the containers.
# Version: 0.1.1
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Shows every version: the project and the image version, each file (manifest against its header), the tools (PowerShell, Docker, Mutagen), and the images and containers with their compatibility.' `
        -Usage 'dkdb-version [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-version'; Description = 'Prints all the versions; it works without Docker for the first sections.' }
        ) `
        -Notes @(
            'An image or container older than the scripts is only reported; it keeps working.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath

$scripts = Get-DevboxVersion
$expectedImage = Get-DevboxImageVersion
$base = Get-DevboxBase
$problems = 0

# --- Project ---
Write-Host ''
Write-Host 'Project'
Write-Host "  docker-devbox-ubuntu $scripts (manifest.json)"
Write-Host "  image version that the scripts build and expect: $expectedImage"

# --- Files: the version in manifest.json against the version in the file header ---
Write-Host ''
Write-Host 'Files (manifest / file)'
$manifestPath = Join-Path $base 'manifest.json'
$mismatches = 0
$listed = 0
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try { $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json } catch { $manifest = $null }
    if ($manifest -and $manifest.files) {
        foreach ($entry in ($manifest.files.PSObject.Properties | Sort-Object Name)) {
            $listed++
            $path = Join-Path $base ($entry.Name -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $actual = Get-DevboxFileVersion -Path $path
            $shownActual = $actual
            if (-not $actual) { $shownActual = 'missing' }
            $line = '  {0,-46} {1,-9} {2}' -f $entry.Name, $entry.Value, $shownActual
            if ($actual -eq [string]$entry.Value) { Write-Host $line }
            elseif ($entry.Name -eq 'install/install.ps1' -and -not $actual) { Write-Host ($line + ' (downloaded by hand)') }
            else { Write-DevboxWarning $line; $mismatches++ }
        }
    }
}
if ($listed -eq 0) {
    Write-DevboxWarning '  manifest.json is missing or lists no file'
    $problems++
} elseif ($mismatches -gt 0) {
    Write-DevboxWarning "  $mismatches of $listed files differ from the manifest: run install.ps1 again (dkdb-verify shows the details)."
    $problems++
} else {
    Write-DevboxSuccess "  All $listed files match the manifest."
}

# --- Tools ---
Write-Host ''
Write-Host 'Tools'
Write-Host "  PowerShell      $($PSVersionTable.PSVersion)"
$dockerReachable = $false
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $clientVersion = (docker version --format '{{.Client.Version}}' 2>$null | Out-String).Trim()
    Write-Host "  Docker client   $clientVersion"
    docker info *> $null
    if ($LASTEXITCODE -eq 0) {
        $dockerReachable = $true
        $serverVersion = (docker version --format '{{.Server.Version}}' 2>$null | Out-String).Trim()
        Write-Host "  Docker engine   $serverVersion"
    } else {
        Write-DevboxWarning '  Docker engine   not reachable (start Docker Desktop): images and containers are not listed'
        $problems++
    }
} else {
    Write-DevboxWarning '  Docker          not found in the PATH'
    $problems++
}
$mutagenExe = Get-DevboxMutagenExe
if ($mutagenExe) {
    $mutagenFound = Get-DevboxMutagenVersion
    if (-not $mutagenFound) { Write-Host "  Mutagen         version unknown ($mutagenExe)" }
    elseif ($mutagenFound -lt [version]$DevboxMutagenVersion) {
        Write-DevboxWarning "  Mutagen         $mutagenFound ($mutagenExe) is older than the required $DevboxMutagenVersion"
        $problems++
    } else {
        Write-Host "  Mutagen         $mutagenFound ($mutagenExe; required $DevboxMutagenVersion or newer)"
    }
} else {
    Write-Host '  Mutagen         not installed (optional; dkdb-container-create installs it on demand)'
}

# --- Images and containers ---
if ($dockerReachable) {
    Write-Host ''
    Write-Host "Images (compatible with the image version ${expectedImage}: same major.minor in 0.x, same major from 1.0)"
    $images = @(Get-DevboxImages)
    if ($images.Count -eq 0) { Write-Host '  none' }
    foreach ($image in $images) {
        $tag = $image.Substring($image.LastIndexOf(':') + 1)
        if (Test-DevboxVersionCompatible -Left $tag -Right $expectedImage) { Write-Host "  $image  compatible" }
        else { Write-DevboxWarning "  $image  not compatible (or not a version tag)"; $problems++ }
    }

    Write-Host ''
    Write-Host 'Containers (version of the image they were created from)'
    $containers = @(Get-DevboxContainers -Running $true) + @(Get-DevboxContainers -Running $false)
    if ($containers.Count -eq 0) { Write-Host '  none' }
    foreach ($container in $containers) {
        $imageVersion = Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_IMAGE_VERSION'
        $shown = $imageVersion
        if (-not $shown) { $shown = 'unknown' }
        if ($imageVersion -and (Test-DevboxVersionCompatible -Left $imageVersion -Right $expectedImage)) { Write-Host ('  {0,-30} {1,-9} compatible' -f $container, $shown) }
        else { Write-DevboxWarning ('  {0,-30} {1,-9} not compatible (it keeps working; newer features may be missing)' -f $container, $shown); $problems++ }
    }
}

Write-Host ''
if ($problems -gt 0) {
    Write-DevboxNext 'Next: to update a container, rebuild the image (dkdb-image-create) and recreate it; dkdb-info shows how everything is set up.'
} else {
    Write-DevboxNext 'Next: dkdb-info shows how everything is set up.'
}
