# Start one stopped devbox container chosen from a menu.
# Version: 0.1.2
. "$PSScriptRoot\dkdb-common.ps1"
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity -WarnOnly
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

$null = Test-DevboxContainerVersion -Container $selected

docker start $selected | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxWarning "Error: could not start '$selected'."
    exit 1
}
Write-DevboxSuccess "Container '$selected' started."

if ((Get-DevboxContainerEnv -Container $selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
    if (Start-DevboxSync -Container $selected -Flush) {
        Write-DevboxSuccess "Mutagen sync for '$selected' is active."
    } else {
        Write-DevboxWarning 'The container is running, but the projects are NOT synchronized.'
        exit 1
    }
}

Write-DevboxNext 'Next: dkdb-container-connect.'
