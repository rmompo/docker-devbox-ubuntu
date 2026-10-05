# Start one stopped devbox container chosen from a menu.
. "$PSScriptRoot\dkdb-common.ps1"
Assert-DevboxDocker

$containers = Get-DevboxContainers -Running $false
if ($containers.Count -eq 0) {
    Write-Host "No stopped containers starting with '$DevboxPrefix-' were found."
    exit 0
}

$selected = Select-DevboxItem -Title 'Select the container to start:' -Items $containers
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

docker start $selected | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: could not start '$selected'." -ForegroundColor Red
    exit 1
}
Write-Host "Container '$selected' started." -ForegroundColor Green

if ((Get-DevboxContainerEnv -Container $selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
    if (Start-DevboxSync -Container $selected) {
        Write-Host "Mutagen sync for '$selected' is active." -ForegroundColor Green
    } else {
        Write-Host 'The container is running, but the projects are NOT synchronized.' -ForegroundColor Yellow
        exit 1
    }
}
