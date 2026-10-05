# Create a devbox container (it is not started; use dkdb-container-start).
. "$PSScriptRoot\dkdb-common.ps1"
Assert-DevboxDocker

# --- Ask for everything ---
$imageInput = Read-DevboxName -Prompt 'Image name' -Default $DevboxDefaultName
$imageName = Get-DevboxFullName $imageInput

$containerInput = Read-DevboxName -Prompt 'Container name' -Default $DevboxDefaultName
$containerName = Get-DevboxFullName $containerInput

# The default user is the same as the container (full name, prefix included).
$userInput = Read-DevboxName -Prompt 'User name' -Default $containerInput
$userName = Get-DevboxFullName $userInput

$projectsPath = Read-Host "Host projects path [$DevboxDefaultProjectsPath]"
if ([string]::IsNullOrWhiteSpace($projectsPath)) { $projectsPath = $DevboxDefaultProjectsPath }

# Volume type for the projects folder (Mutagen is downloaded later if needed).
$syncMode = Select-DevboxItem -Title 'Projects volume type:' -Items @($DevboxSyncModeBind, $DevboxSyncModeMutagen)
if (-not $syncMode) {
    Write-Host 'Cancelled. Nothing was created.'
    exit 0
}
$useMutagen = ($syncMode -eq $DevboxSyncModeMutagen)

# Docker mount sources must not end with a backslash.
$projectsPath = $projectsPath.Trim().TrimEnd('\')
$bashPath = (Get-DevboxBashPath).TrimEnd('\')

# --- Validate everything before doing anything ---
$errors = @()
docker image inspect $imageName *> $null
if ($LASTEXITCODE -ne 0) { $errors += "Image '$imageName' does not exist. Run dkdb-image-create first." }
docker container inspect $containerName *> $null
if ($LASTEXITCODE -eq 0) { $errors += "A container named '$containerName' already exists." }
foreach ($path in @($projectsPath, $bashPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $errors += "Host path does not exist (nothing is created): $path"
    }
    if ($path.Contains(',')) { $errors += "Host path must not contain commas: $path" }
}
if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Host "Error: $e" -ForegroundColor Red }
    Write-Host 'Aborted. Nothing was created.' -ForegroundColor Red
    exit 1
}

# --- Install Mutagen on demand (only when chosen and missing) ---
if ($useMutagen -and -not (Test-DevboxMutagen)) {
    if (-not (Install-DevboxMutagen)) {
        Write-Host 'Mutagen is not available. Aborted. Nothing was created.' -ForegroundColor Red
        exit 1
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
    $createArgs += @('--mount', "type=bind,source=$projectsPath,target=$mountBase/proyectos")
}
$createArgs += @('--mount', "type=bind,source=$bashPath,target=$mountBase/bash,readonly", $imageName)
docker @createArgs | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Error: docker create failed.' -ForegroundColor Red
    exit 1
}
Write-Host "Container '$containerName' created (user '$userName', password equal to the user name)." -ForegroundColor Green
if ($useMutagen) {
    Write-Host "Projects: Mutagen will synchronize '$projectsPath' with the container when it is started."
}
Write-Host 'Next: dkdb-container-start, then dkdb-container-connect.'
