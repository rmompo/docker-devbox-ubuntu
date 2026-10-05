# Create a devbox container (it is not started; use dkdb-container-start).
# Version: 0.1.2
. "$PSScriptRoot\dkdb-common.ps1"
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity
Assert-DevboxDocker

# --- Ask for everything ---
# The default image is shown with the version that will be used (the highest compatible tag).
$defaultImageName = Get-DevboxFullName $DevboxDefaultName
$defaultImageRef = Get-DevboxCompatibleImage -ImageName $defaultImageName
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
$imageRef = Get-DevboxCompatibleImage -ImageName $imageName
if (-not $imageRef) { $errors += "No image '$imageName' with a version compatible with the scripts ($(Get-DevboxVersion)) was found. Run dkdb-image-create first." }
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
    Write-Host "Projects: Mutagen will synchronize '$projectsPath' with the container when it is started."
}
Write-DevboxNext 'Next: dkdb-container-start, then dkdb-container-connect.'
