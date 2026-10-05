# Stop one running devbox container chosen from a menu.
# Version: 0.1.2
# It never touches Mutagen (daemon or session): see dkdb-mutagen-stop for that.
. "$PSScriptRoot\dkdb-common.ps1"
Show-DevboxVersion -Script $PSCommandPath
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
    Write-DevboxWarning "Error: could not stop '$selected'."
    exit 1
}
Write-DevboxSuccess "Container '$selected' stopped."
Write-DevboxNext 'Next: dkdb-container-start starts it again, or dkdb-container-delete removes it.'
