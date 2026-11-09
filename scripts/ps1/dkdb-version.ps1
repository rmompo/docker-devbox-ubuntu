# Show every version: the project, each file, the tools, the images and the containers.
# Version: 0.3.0
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
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
            'An image or container older than the scripts is only reported; it keeps working.',
            'Files: the name is orange, the version of the manifest green, and the version of the file green when it matches and red when it does not. The columns line up whatever the length of the names.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Shows every version of the package and what it is running on.' `
        -Needs @(
            'Nothing for the first sections; Docker for images and containers.'
        ) `
        -Steps @(
            'Prints the project version and the image version of the manifest.',
            'Compares each file (manifest against its Version header).',
            'Prints PowerShell, Docker and Mutagen (against the minimum).',
            'Lists each image and container with its compatibility.'
        ) `
        -Changes @(
            'Nothing: it only reads.'
        ) `
        -Never @(
            'Blocks anything: an image or container older than the scripts is only reported.'
        ) `
        -Next 'Run dkdb-verify if a file does not match.'
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
Write-Host 'Files' -NoNewline -ForegroundColor DarkYellow
Write-Host ' (' -NoNewline
Write-Host 'manifest' -NoNewline -ForegroundColor Green
Write-Host ' / file)'
$manifestPath = Join-Path $base 'manifest.json'
$mismatches = 0
$listed = 0
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try { $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json } catch { $manifest = $null }
    if ($manifest -and $manifest.files) {
        $entries = @($manifest.files.PSObject.Properties | Sort-Object Name)
        # The columns are as wide as the longest name and version, so that they always line up.
        $nameWidth = ($entries | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
        $versionWidth = ($entries | ForEach-Object { ([string]$_.Value).Length } | Measure-Object -Maximum).Maximum
        foreach ($entry in $entries) {
            $listed++
            $path = Join-Path $base ($entry.Name -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $actual = Get-DevboxFileVersion -Path $path
            $shownActual = $actual
            if (-not $actual) { $shownActual = 'missing' }
            # Name in orange, version of the manifest in green, version of the file green when it matches and red when not.
            Write-Host ('  {0} ' -f $entry.Name.PadRight($nameWidth)) -NoNewline -ForegroundColor DarkYellow
            Write-Host ('{0} ' -f ([string]$entry.Value).PadRight($versionWidth)) -NoNewline -ForegroundColor Green
            if ($actual -eq [string]$entry.Value) { Write-Host $shownActual -ForegroundColor Green }
            elseif ($entry.Name -eq 'install/dkdb-install.ps1' -and -not $actual) { Write-Host "$shownActual (downloaded by hand)" }
            else { Write-Host $shownActual -ForegroundColor Red; $mismatches++ }
        }
    }
}
if ($listed -eq 0) {
    Write-DevboxWarning '  manifest.json is missing or lists no file'
    $problems++
} elseif ($mismatches -gt 0) {
    Write-DevboxWarning "  $mismatches of $listed files differ from the manifest: run dkdb-install.ps1 again (dkdb-verify shows the details)."
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
        $engineKind = switch (Get-DevboxDockerEngineKind) { 'DockerDesktop' { 'Docker Desktop' } 'LinuxEngine' { 'Linux engine (WSL): bind mounts use /mnt/<drive>/' } default { 'unknown' } }
        Write-Host "  Engine type     $engineKind"
    } else {
        Write-DevboxWarning '  Docker engine   not reachable (start Docker Desktop, or the Docker engine in WSL): images and containers are not listed'
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
    $imageWidth = 0
    foreach ($image in $images) { if ($image.Length -gt $imageWidth) { $imageWidth = $image.Length } }
    foreach ($image in $images) {
        $tag = $image.Substring($image.LastIndexOf(':') + 1)
        if (Test-DevboxVersionCompatible -Left $tag -Right $expectedImage) { Write-Host "  $($image.PadRight($imageWidth))  compatible" }
        else { Write-DevboxWarning "  $($image.PadRight($imageWidth))  not compatible (or not a version tag)"; $problems++ }
    }

    Write-Host ''
    Write-Host 'Containers (version of the image they were created from)'
    $containers = @(Get-DevboxContainers -Running $true) + @(Get-DevboxContainers -Running $false)
    if ($containers.Count -eq 0) { Write-Host '  none' }
    $containerWidth = 0
    foreach ($container in $containers) { if ($container.Length -gt $containerWidth) { $containerWidth = $container.Length } }
    foreach ($container in $containers) {
        $imageVersion = Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_IMAGE_VERSION'
        $shown = $imageVersion
        if (-not $shown) { $shown = 'unknown' }
        if ($imageVersion -and (Test-DevboxVersionCompatible -Left $imageVersion -Right $expectedImage)) { Write-Host ("  {0} {1,-9} compatible" -f $container.PadRight($containerWidth), $shown) }
        else { Write-DevboxWarning ("  {0} {1,-9} not compatible (it keeps working; newer features may be missing)" -f $container.PadRight($containerWidth), $shown); $problems++ }
    }
}

Write-Host ''
if ($problems -gt 0) {
    Write-DevboxNext 'Next: to update a container, rebuild the image (dkdb-image-create) and recreate it; dkdb-info shows how everything is set up.'
} else {
    Write-DevboxNext 'Next: dkdb-info shows how everything is set up.'
}
