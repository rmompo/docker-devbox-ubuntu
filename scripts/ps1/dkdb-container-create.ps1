# Create a devbox container (it is not started; use dkdb-container-start).
# Version: 0.2.0
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Creates a devbox container from a devbox image; it is not started. It asks for the image, the container name, the user, the host projects path, the host tools path and the projects volume type (Docker bind mount or Mutagen sync).' `
        -Usage 'dkdb-container-create [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-container-create'; Description = 'Asks for everything, with defaults, and creates the container.' }
        ) `
        -Notes @(
            'Folders inside the container: ~/devbox/projects (bind mount, or a copy synchronized by Mutagen), ~/devbox/tools (read/write) and ~/devbox/bash (read-only).',
            'The host paths must exist: nothing is created for you.',
            'The password of the user is its name (weak by design: local development only).',
            'Mutagen is downloaded on demand if you choose it and it is not installed (about 100 MB, checksum verified).'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Creates a devbox container from an image. It is created, not started.' `
        -Needs @(
            'Docker Engine running and an image built with dkdb-image-create.',
            'The host projects and tools folders exist (nothing is created for you).',
            'With Mutagen: version 0.18.1 or newer (downloaded on demand when missing).'
        ) `
        -Steps @(
            'Checks the package against manifest.json and checks Docker.',
            'Asks for the image, the container name, the user (default: the container name), the host projects path, the host tools path and the projects volume type (Docker bind mount or Mutagen).',
            'Validates everything before creating: the image exists (the highest compatible tag; an older one only warns), the container name is free, the host paths exist and have no commas.',
            'If Mutagen was chosen: installs it when missing and checks its version.',
            'Runs docker create with DEVBOX_USER, tools mounted at ~/devbox/tools, scripts\bash at ~/devbox/bash (read-only) and, for a bind mount, the projects at ~/devbox/projects. With Mutagen there is no projects mount: the container only gets DEVBOX_SYNC and DEVBOX_SYNC_PATH.'
        ) `
        -Changes @(
            'Adds a stopped container.',
            'With Mutagen, may download it into <root>\devbox\mutagen.'
        ) `
        -Never @(
            'Starts the container.',
            'Creates host folders.',
            'Starts the Mutagen daemon or creates any Mutagen session.'
        ) `
        -Next 'dkdb-container-start (with Mutagen its menu lets you choose what to synchronize), then dkdb-container-connect.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity
Assert-DevboxDocker

# --- Ask for everything ---
# The default image is shown with the version that will be used (the highest compatible tag).
$defaultImageName = Get-DevboxFullName $DevboxDefaultName
$defaultImageRef = Get-DevboxCompatibleImage -ImageName $defaultImageName
if (-not $defaultImageRef) { $defaultImageRef = Get-DevboxCompatibleImage -ImageName $defaultImageName -AnyVersion }
$defaultImageSuffix = ''
if ($defaultImageRef) { $defaultImageSuffix = $defaultImageRef.Substring($defaultImageName.Length) }
$imageInput = Read-DevboxName -Prompt 'Image name' -Default $DevboxDefaultName -DefaultSuffix $defaultImageSuffix
$imageName = Get-DevboxFullName $imageInput

$containerInput = Read-DevboxName -Prompt 'Container name' -Default $DevboxDefaultName
$containerName = Get-DevboxFullName $containerInput

# The default user is the same as the container (full name, prefix included).
$userInput = Read-DevboxName -Prompt 'User name' -Default $containerInput
$userName = Get-DevboxFullName $userInput

$projectsPath = Read-Host "Host projects path [$DevboxDefaultProjectsPath]"
if ([string]::IsNullOrWhiteSpace($projectsPath)) { $projectsPath = $DevboxDefaultProjectsPath }
$defaultToolsPath = Get-DevboxDefaultToolsPath
$toolsPath = Read-Host "Host tools path [$defaultToolsPath]"
if ([string]::IsNullOrWhiteSpace($toolsPath)) { $toolsPath = $defaultToolsPath }

# Volume type for the projects folder (Mutagen is downloaded later if needed).
$syncMode = Select-DevboxItem -Title 'Projects volume type:' -Items @($DevboxSyncModeBind, $DevboxSyncModeMutagen)
if (-not $syncMode) {
    Write-Host 'Cancelled. Nothing was created.'
    exit 0
}
$useMutagen = ($syncMode -eq $DevboxSyncModeMutagen)

# Docker mount sources must not end with a backslash.
$projectsPath = $projectsPath.Trim().TrimEnd('\')
$toolsPath = $toolsPath.Trim().TrimEnd('\')
$bashPath = (Get-DevboxBashPath).TrimEnd('\')

# --- Validate everything before doing anything ---
$errors = @()
# The highest compatible tag; when only older images exist, the highest of them (an update of
# the scripts must not stop anybody from creating a container): it only warns.
$imageRef = Get-DevboxCompatibleImage -ImageName $imageName
$imageIsOlder = $false
if (-not $imageRef) {
    $imageRef = Get-DevboxCompatibleImage -ImageName $imageName -AnyVersion
    $imageIsOlder = [bool]$imageRef
}
if (-not $imageRef) { $errors += "No image '$imageName' was found. Run dkdb-image-create first." }
docker container inspect $containerName *> $null
if ($LASTEXITCODE -eq 0) { $errors += "A container named '$containerName' already exists." }
foreach ($path in @($projectsPath, $toolsPath, $bashPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $errors += "Host path does not exist (nothing is created): $path"
    }
    if ($path.Contains(',')) { $errors += "Host path must not contain commas: $path" }
}
if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-DevboxWarning "Error: $e" }
    Write-DevboxWarning 'Aborted. Nothing was created.'
    exit 1
}

if ($imageIsOlder) {
    Write-DevboxWarning "Warning: '$imageRef' is not compatible with the image version that the scripts expect ($(Get-DevboxImageVersion)). The container is created from it anyway and works, but newer features may be missing."
}

# --- Install Mutagen on demand (only when chosen and missing) ---
if ($useMutagen -and -not (Test-DevboxMutagen)) {
    if (-not (Install-DevboxMutagen)) {
        Write-DevboxWarning 'Mutagen is not available. Aborted. Nothing was created.'
        exit 1
    }
}

# --- Mutagen minimum version ---
if ($useMutagen) {
    $mutagenFound = Get-DevboxMutagenVersion
    if ($mutagenFound -and $mutagenFound -lt [version]$DevboxMutagenVersion) {
        Write-DevboxWarning "Error: Mutagen $mutagenFound ($(Get-DevboxMutagenExe)) is older than $DevboxMutagenVersion, which Docker Engine 28+ needs."
        Write-DevboxWarning 'Update it, or remove it from the PATH so that this script installs its own. Aborted. Nothing was created.'
        exit 1
    }
    if (-not $mutagenFound) {
        Write-DevboxWarning "Warning: could not read the Mutagen version; $DevboxMutagenVersion or newer is required."
    }
}

# --- Create the container ---
$mountBase = "/home/$userName/devbox"
$createArgs = @(
    'create',
    '--name', $containerName,
    '--hostname', $containerName,
    '-e', "DEVBOX_USER=$userName"
)
if ($useMutagen) {
    # No bind mount for projects: the folder lives in the container and Mutagen
    # synchronizes it with the host path when the container is started.
    $createArgs += @('-e', 'DEVBOX_SYNC=mutagen', '-e', "DEVBOX_SYNC_PATH=$projectsPath")
} else {
    $createArgs += @('--mount', "type=bind,source=$projectsPath,target=$mountBase/projects")
}
$createArgs += @(
    '--mount', "type=bind,source=$toolsPath,target=$mountBase/tools",
    '--mount', "type=bind,source=$bashPath,target=$mountBase/bash,readonly",
    $imageRef
)
docker @createArgs | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxWarning 'Error: docker create failed.'
    exit 1
}
Write-DevboxSuccess "Container '$containerName' created from image '$imageRef' (user '$userName', password equal to the user name)."
if ($useMutagen) {
    Write-Host "Projects: with Mutagen, '$projectsPath' is synchronized only when you choose it in the menu of dkdb-container-start, dkdb-container-connect or dkdb-mutagen-sync."
}
if ($useMutagen) {
    Write-DevboxNext 'Next: dkdb-container-start to start it (its menu lets you choose what to synchronize), then dkdb-container-connect.'
} else {
    Write-DevboxNext 'Next: dkdb-container-start, then dkdb-container-connect.'
}
if ($imageIsOlder) {
    Write-DevboxNext 'Next (optional): dkdb-image-create builds an image for the current scripts; recreate the container from it when you want the newer features.'
}
