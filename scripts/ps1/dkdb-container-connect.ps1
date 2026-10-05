# Open a bash shell, as the container's user, in a running devbox container.
# Version: 0.1.1
. "$PSScriptRoot\dkdb-common.ps1"
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity
Assert-DevboxDocker

$containers = Get-DevboxContainers -Running $true
if ($containers.Count -eq 0) {
    Write-Host "No running containers starting with '$DevboxPrefix-' were found."
    exit 0
}

$selected = Select-DevboxItem -Title 'Select the container to connect to:' -Items $containers
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

$userName = Get-DevboxContainerUser -Container $selected
if (-not $userName) {
    Write-DevboxWarning "Error: '$selected' has no DEVBOX_USER variable; it was not created by dkdb-container-create."
    exit 1
}

# Stop when the image the container was created from is not compatible with the scripts.
Assert-DevboxContainerVersion -Container $selected

# Mutagen container: make sure the daemon is running and the sync session is active
# (nothing does it when the container was started with plain docker).
# The shell opens even if this fails.
if ((Get-DevboxContainerEnv -Container $selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
    if (-not (Start-DevboxSync -Container $selected)) {
        Write-DevboxWarning 'Opening the shell anyway, but the projects are NOT synchronized.'
    }
}

# TERM is set explicitly: without it, docker exec may give a plain "xterm" and
# the default Ubuntu .bashrc then shows no colored prompt.
docker exec -it -u $userName -w "/home/$userName" -e TERM=xterm-256color -e COLORTERM=truecolor $selected bash
