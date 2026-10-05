# Open a bash shell, as the container's user, in a running devbox container.
# Version: 0.1.3
# Switches: -SyncOff (do not touch Mutagen) or -SyncFolder <path>[,<path>...] (synchronize only those
# folders, adding them to the ones already synchronized; run it again to add more).
# PositionalBinding is off so that a stray argument is an error and not a folder.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SyncOff,
    [string[]]$SyncFolder,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Opens a bash shell, as the container''s user, in one running devbox container chosen from a menu. For a container that uses Mutagen it first makes sure the synchronization is active.' `
        -Usage 'dkdb-container-connect [-SyncOff | -SyncFolder <path>[,<path>...]] [-Help]' `
        -Parameters @(
            @{ Name = '-SyncOff'; Description = 'Do not touch Mutagen in this run (no daemon, no sessions, no flush). It cannot be combined with -SyncFolder.' },
            @{ Name = '-SyncFolder <path>[,<path>...]'; Description = 'Synchronize only these folders instead of everything. Each path is relative to the host projects folder (or absolute inside it) and must exist. Run it again with other folders to add them.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-container-connect'; Description = 'Connects and makes sure the synchronization is active.' },
            @{ Command = 'dkdb-container-connect -SyncFolder repo3'; Description = 'Adds repo3 to the synchronized folders and connects.' },
            @{ Command = 'dkdb-container-connect -SyncOff'; Description = 'Connects without touching Mutagen.' }
        ) `
        -Notes @(
            'The shell opens even if the synchronization fails.',
            'If the container has no AI client yet, it suggests how to install one.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
$syncOptions = Get-DevboxSyncOptions -SyncOff $SyncOff.IsPresent -SyncFolder $SyncFolder
if ($syncOptions.Error) {
    Write-DevboxWarning "Error: $($syncOptions.Error)"
    Write-DevboxNext 'Usage: dkdb-container-connect [-SyncOff | -SyncFolder <path>[,<path>...]]'
    exit 1
}
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

# Mutagen container: make sure the daemon is running and the sync sessions are active (nothing does
# it when the container was started with plain docker). -SyncOff skips it; -SyncFolder adds
# folders. The shell opens even if this fails.
if ((Get-DevboxContainerEnv -Container $selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
    if ($syncOptions.SyncOff) {
        Write-Host 'Mutagen synchronization skipped (-SyncOff).'
    } elseif (-not (Start-DevboxSync -Container $selected -Folders $syncOptions.Folders)) {
        Write-DevboxWarning 'Opening the shell anyway, but the projects are NOT synchronized.'
    }
} elseif ($syncOptions.SyncOff -or $syncOptions.Folders.Count -gt 0) {
    Write-DevboxWarning "Warning: '$selected' does not use Mutagen: the sync switches were ignored."
}

# Next step: the AI client (one per container) is installed from inside the container.
docker exec -u $userName $selected bash -c 'test -e ~/.local/bin/claude || test -e ~/.local/bin/copilot' *> $null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxNext 'Next: inside the container, install one AI client: bash ~/devbox/bash/dkdb-install-claudecode.sh (Claude Code) or bash ~/devbox/bash/dkdb-install-ghcopilot-cli.sh (GitHub Copilot CLI).'
}

# TERM is set explicitly: without it, docker exec may give a plain "xterm" and
# the default Ubuntu .bashrc then shows no colored prompt.
docker exec -it -u $userName -w "/home/$userName" -e TERM=xterm-256color -e COLORTERM=truecolor $selected bash
