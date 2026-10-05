# Open a bash shell, as the container's user, in a running devbox container.
# Version: 0.3.0
# For a Mutagen container a menu chooses what to synchronize (No sync is the first option and the default).
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Opens a bash shell, as the container''s user, in one running devbox container chosen from a menu. For a container that uses Mutagen it starts the daemon too and then asks what to synchronize; by default (No sync) nothing is.' `
        -Usage 'dkdb-container-connect [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-container-connect'; Description = 'Connects; for a Mutagen container it first shows the synchronization menu.' }
        ) `
        -Notes @(
            'For a container that uses Mutagen a menu asks what to synchronize: No sync (the first option, the default: the daemon is started and the existing sessions are paused), a folder already registered as a session, All registered, or Add... (a new folder). Registering projects separately is the recommended way. A folder is added to what is active; it pauses the active sessions it covers, and changes nothing when an active session already covers it (somebody may be using it). All registered activates the sessions that are not inside another one. Nothing is ever terminated.',
            'The shell opens even if the synchronization fails.',
            'If the container has no AI client yet, it suggests how to install one.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity -WarnOnly
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
$null = Test-DevboxContainerVersion -Container $selected

# Mutagen container: a menu decides what is synchronized (No sync, the first option, is the default).
# The shell opens even if this fails.
if ((Get-DevboxContainerEnv -Container $selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
    $pick = Invoke-DevboxSyncPick -Container $selected
    if (-not $pick.Ok) {
        Write-DevboxWarning 'Opening the shell anyway, but the projects are NOT synchronized.'
    }
}

# Next step: the AI client (one per container) is installed from inside the container.
docker exec -u $userName $selected bash -c 'test -e ~/.local/bin/claude || test -e ~/.local/bin/copilot' *> $null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxNext 'Next: inside the container, install one AI client: bash ~/devbox/bash/dkdb-install-claudecode.sh (Claude Code) or bash ~/devbox/bash/dkdb-install-ghcopilot-cli.sh (GitHub Copilot CLI).'
}

# TERM is set explicitly: without it, docker exec may give a plain "xterm" and
# the default Ubuntu .bashrc then shows no colored prompt.
docker exec -it -u $userName -w "/home/$userName" -e TERM=xterm-256color -e COLORTERM=truecolor $selected bash
