# Show every version: the project, each file, the tools, the images and the containers.
# Version: 0.4.1
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
            'Layout (same as dkdb-info): SECTIONS in capitals, PROPERTIES in capitals followed by dots. Files: the name is orange, the version of the manifest green, and the version of the file green when it matches and red when it does not; the columns line up whatever the length of the names. COMPATIBLE (green) and NOT-COMPATIBLE (red) are shown in reverse video.'
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

# Short names for the pieces of a value (same layout and colors as dkdb-info: sections in capitals, properties in
# capitals followed by dots, host paths cyan, special words in reverse video).
function Get-InfoHost { param([string]$Text) New-DevboxInfoText $Text $DevboxHostColor }
function Get-InfoPlain { param([string]$Text) New-DevboxInfoText $Text $null }
function Show-InfoText {
    param([string]$Label, [string]$Text, [string]$Color, [int]$LabelWidth = 13)
    Write-DevboxInfoField -Label $Label -Value @((New-DevboxInfoText $Text $Color)) -LabelWidth $LabelWidth
}
# Reverse-video word that says whether a version is compatible.
function Write-InfoCompatible {
    param([bool]$Compatible)
    if ($Compatible) { Write-Host ' COMPATIBLE ' -NoNewline -ForegroundColor Black -BackgroundColor $DevboxBadgeCompatibleColor }
    else { Write-Host ' NOT-COMPATIBLE ' -NoNewline -ForegroundColor Black -BackgroundColor $DevboxBadgeIncompatibleColor }
}

$scripts = Get-DevboxVersion
$expectedImage = Get-DevboxImageVersion
$base = Get-DevboxBase
$problems = 0

# --- Project ---
Write-DevboxInfoSection -Title 'Project'
Write-DevboxInfoField -Label 'Version' -LabelWidth 7 -Value @((New-DevboxInfoText "$scripts" $DevboxSuccessColor), (Get-InfoPlain ' (docker-devbox-ubuntu, manifest.json)'))
Write-DevboxInfoField -Label 'Image' -LabelWidth 7 -Value @((New-DevboxInfoText "$expectedImage" $DevboxSuccessColor), (Get-InfoPlain ' (the image version that the scripts build and expect)'))

# --- Files: the version in manifest.json against the version in the file header ---
# Name in orange, version of the manifest in green, version of the file green when it matches and red when not.
Write-Host ''
Write-Host 'FILES' -NoNewline -ForegroundColor $DevboxSectionColor
Write-Host ' (' -NoNewline -ForegroundColor $DevboxNoteColor
Write-Host 'manifest' -NoNewline -ForegroundColor $DevboxSuccessColor
Write-Host ' / file)' -ForegroundColor $DevboxNoteColor
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
            Write-Host ('  {0} ' -f $entry.Name.PadRight($nameWidth)) -NoNewline -ForegroundColor $DevboxNameColor
            Write-Host ('{0} ' -f ([string]$entry.Value).PadRight($versionWidth)) -NoNewline -ForegroundColor $DevboxSuccessColor
            if ($actual -eq [string]$entry.Value) { Write-Host $shownActual -ForegroundColor $DevboxSuccessColor }
            elseif ($entry.Name -eq 'install/dkdb-install.ps1' -and -not $actual) { Write-Host "$shownActual (downloaded by hand)" }
            else { Write-Host $shownActual -ForegroundColor $DevboxErrorColor; $mismatches++ }
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
Write-DevboxInfoSection -Title 'Tools'
Show-InfoText -Label 'PowerShell' -Text "$($PSVersionTable.PSVersion)"
$dockerReachable = $false
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $clientVersion = (docker version --format '{{.Client.Version}}' 2>$null | Out-String).Trim()
    Show-InfoText -Label 'Docker client' -Text $clientVersion
    docker info *> $null
    if ($LASTEXITCODE -eq 0) {
        $dockerReachable = $true
        $serverVersion = (docker version --format '{{.Server.Version}}' 2>$null | Out-String).Trim()
        Show-InfoText -Label 'Docker engine' -Text $serverVersion
        $engineKind = switch (Get-DevboxDockerEngineKind) { 'DockerDesktop' { 'Docker Desktop' } 'LinuxEngine' { 'Linux engine (WSL): bind mounts use /mnt/<drive>/' } default { 'unknown' } }
        Show-InfoText -Label 'Engine type' -Text $engineKind
    } else {
        Show-InfoText -Label 'Docker engine' -Text 'not reachable (start Docker Desktop, or the Docker engine in WSL): images and containers are not listed' -Color $DevboxErrorColor
        $problems++
    }
} else {
    Show-InfoText -Label 'Docker client' -Text 'not found in the PATH' -Color $DevboxErrorColor
    $problems++
}
$mutagenExe = Get-DevboxMutagenExe
if ($mutagenExe) {
    $mutagenFound = Get-DevboxMutagenVersion
    if (-not $mutagenFound) {
        Write-DevboxInfoField -Label 'Mutagen' -LabelWidth 13 -Value @((Get-InfoPlain 'version unknown '), (Get-InfoHost "($mutagenExe)"))
    } elseif ($mutagenFound -lt [version]$DevboxMutagenVersion) {
        Write-DevboxInfoField -Label 'Mutagen' -LabelWidth 13 -Value @((New-DevboxInfoText "$mutagenFound " $DevboxErrorColor), (Get-InfoHost "($mutagenExe)"), (New-DevboxInfoText " is older than the required $DevboxMutagenVersion" $DevboxErrorColor))
        $problems++
    } else {
        Write-DevboxInfoField -Label 'Mutagen' -LabelWidth 13 -Value @((New-DevboxInfoText "$mutagenFound " $DevboxSuccessColor), (Get-InfoHost "($mutagenExe)"), (Get-InfoPlain " required $DevboxMutagenVersion or newer"))
    }
} else {
    Show-InfoText -Label 'Mutagen' -Text 'not installed (optional; dkdb-container-create installs it on demand)'
}

# --- Images and containers ---
if ($dockerReachable) {
    Write-DevboxInfoSection -Title 'Images' -Note "(compatible with the image version ${expectedImage}: same major.minor in 0.x, same major from 1.0)"
    $images = @(Get-DevboxImages)
    if ($images.Count -eq 0) { Write-Host '  none' }
    $imageWidth = 0
    foreach ($image in $images) { if ($image.Length -gt $imageWidth) { $imageWidth = $image.Length } }
    foreach ($image in $images) {
        $tag = $image.Substring($image.LastIndexOf(':') + 1)
        $compatible = [bool](Test-DevboxVersionCompatible -Left $tag -Right $expectedImage)
        Write-Host ('  {0} ' -f $image.PadRight($imageWidth)) -NoNewline -ForegroundColor $DevboxNameColor
        Write-InfoCompatible -Compatible $compatible
        if (-not $compatible) { Write-Host ' (or not a version tag)' -ForegroundColor $DevboxErrorColor; $problems++ } else { Write-Host '' }
    }

    Write-DevboxInfoSection -Title 'Containers' -Note '(version of the image they were created from)'
    $containers = @(Get-DevboxContainers -Running $true) + @(Get-DevboxContainers -Running $false)
    if ($containers.Count -eq 0) { Write-Host '  none' }
    $containerWidth = 0
    foreach ($container in $containers) { if ($container.Length -gt $containerWidth) { $containerWidth = $container.Length } }
    foreach ($container in $containers) {
        $imageVersion = Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_IMAGE_VERSION'
        $shown = $imageVersion
        if (-not $shown) { $shown = 'unknown' }
        $compatible = [bool]($imageVersion -and (Test-DevboxVersionCompatible -Left $imageVersion -Right $expectedImage))
        $versionColor = $DevboxErrorColor
        if ($compatible) { $versionColor = $DevboxSuccessColor }
        Write-Host ('  {0} ' -f $container.PadRight($containerWidth)) -NoNewline -ForegroundColor $DevboxNameColor
        Write-Host ('{0,-9} ' -f $shown) -NoNewline -ForegroundColor $versionColor
        Write-InfoCompatible -Compatible $compatible
        if (-not $compatible) { Write-Host ' (it keeps working; newer features may be missing)' -ForegroundColor $DevboxErrorColor; $problems++ } else { Write-Host '' }
    }
}

Write-Host ''
if ($problems -gt 0) {
    Write-DevboxNext 'Next: to update a container, rebuild the image (dkdb-image-create) and recreate it; dkdb-info shows how everything is set up.'
} else {
    Write-DevboxNext 'Next: dkdb-info shows how everything is set up.'
}
