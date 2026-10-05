# Start one stopped devbox container chosen from a menu.
. "$PSScriptRoot\common.ps1"
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
