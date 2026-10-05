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

# --- Create the container ---
$mountBase = "/home/$userName/devbox"
docker create `
    --name $containerName `
    --hostname $containerName `
    -e "DEVBOX_USER=$userName" `
    --mount "type=bind,source=$projectsPath,target=$mountBase/proyectos" `
    --mount "type=bind,source=$bashPath,target=$mountBase/bash,readonly" `
    $imageName | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Error: docker create failed.' -ForegroundColor Red
    exit 1
}
Write-Host "Container '$containerName' created (user '$userName', password equal to the user name)." -ForegroundColor Green
Write-Host 'Next: dkdb-container-start, then dkdb-container-connect.'
