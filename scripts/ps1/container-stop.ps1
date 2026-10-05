# Stop one running devbox container chosen from a menu.
. "$PSScriptRoot\common.ps1"
Assert-DevboxDocker

$containers = Get-DevboxContainers -Running $true
if ($containers.Count -eq 0) {
    Write-Host "No running containers starting with '$DevboxPrefix-' were found."
    exit 0
}

$selected = Select-DevboxItem -Title 'Select the container to stop:' -Items $containers
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

docker stop $selected | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: could not stop '$selected'." -ForegroundColor Red
    exit 1
}
Write-Host "Container '$selected' stopped." -ForegroundColor Green
