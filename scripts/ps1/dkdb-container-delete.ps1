# Delete one stopped devbox container chosen from a menu.
# The host folders (projects, bash) are bind mounts and are NOT touched,
# but everything stored only inside the container (its home, installed AI
# client, login) is lost.
. "$PSScriptRoot\dkdb-common.ps1"
Assert-DevboxDocker

$containers = Get-DevboxContainers -Running $false
if ($containers.Count -eq 0) {
    Write-Host "No stopped containers starting with '$DevboxPrefix-' were found (stop it first with dkdb-container-stop)."
    exit 0
}

$selected = Select-DevboxItem -Title 'Select the container to delete:' -Items $containers
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

$answer = Read-Host "Delete '$selected'? Its home and installed AI client are lost. [y/N]"
if ($answer -notmatch '^[yY]$') {
    Write-Host 'Cancelled.'
    exit 0
}

docker rm $selected | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: could not delete '$selected'." -ForegroundColor Red
    exit 1
}
Write-Host "Container '$selected' deleted." -ForegroundColor Green
