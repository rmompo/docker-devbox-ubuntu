# Open a bash shell, as the container's user, in a running devbox container.
# Version: 0.1.4
# Sync ladder for a Mutagen container, from the most to the least conservative: nothing (the default
# or -SyncOff: the daemon is started, existing sessions are paused), -SyncFolder <path>[,<path>...]
# (only those folders, added to the ones already synchronized) and -SyncAll (the whole projects folder).
# PositionalBinding is off so that a stray argument is an error and not a folder.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SyncOff,
    [switch]$SyncAll,
    [string[]]$SyncFolder,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Opens a bash shell, as the container''s user, in one running devbox container chosen from a menu. For a container that uses Mutagen it starts the daemon too, but by default nothing is synchronized: ask for it with -SyncFolder (some folders) or -SyncAll (everything).' `
        -Usage 'dkdb-container-connect [-SyncFolder <path>[,<path>...] | -SyncAll | -SyncOff] [-Help]' `
        -Parameters @(
            @{ Name = '-SyncFolder <path>[,<path>...]'; Description = 'Level 2: synchronize only these folders. Each path is relative to the host projects folder (or absolute inside it) and must exist. Run it again with other folders to add them; other existing sessions are left as they are.' },
            @{ Name = '-SyncAll'; Description = 'Level 3: synchronize the whole projects folder; it can take very long. If only some folders are synchronized, it asks before replacing those sessions.' },
            @{ Name = '-SyncOff'; Description = 'Level 1, the default: the Mutagen daemon is started and the existing sessions of the container are paused; nothing is synchronized. Only needed to say it explicitly.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-container-connect'; Description = 'Connects and starts the Mutagen daemon; nothing is synchronized.' },
            @{ Command = 'dkdb-container-connect -SyncFolder repo3'; Description = 'Adds repo3 to the synchronized folders and connects.' },
            @{ Command = 'dkdb-container-connect -SyncAll'; Description = 'Synchronizes everything and connects.' }
        ) `
        -Notes @(
            'The sync parameters go from the most to the least conservative: nothing (default), some folders, everything. They exclude each other and only affect a container that uses Mutagen.',
            'For a container that uses Mutagen the daemon is always started; what is synchronized depends on the level.',
            'The shell opens even if the synchronization fails.',
            'If the container has no AI client yet, it suggests how to install one.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
$syncOptions = Get-DevboxSyncOptions -SyncOff $SyncOff.IsPresent -SyncAll $SyncAll.IsPresent -SyncFolder $SyncFolder
if ($syncOptions.Error) {
    Write-DevboxWarning "Error: $($syncOptions.Error)"
    Write-DevboxNext 'Usage: dkdb-container-connect [-SyncAll | -SyncFolder <path>[,<path>...] | -SyncOff]'
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

# Mutagen container: by default Mutagen is not touched; -SyncAll or -SyncFolder start the synchronization
# (the daemon and the sessions). The shell opens even if this fails.
if ((Get-DevboxContainerEnv -Container $selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
    if ($syncOptions.Mode -eq 'Off') {
        # Level 1: the daemon is started and the sessions that exist are paused; nothing is synchronized.
        $null = Suspend-DevboxSyncSessions -Container $selected
        Write-Host 'Use -SyncFolder <path> or -SyncAll to synchronize the projects.'
    } elseif (-not (Start-DevboxSync -Container $selected -All:$syncOptions.SyncAll -Folders $syncOptions.Folders)) {
        Write-DevboxWarning 'Opening the shell anyway, but the projects are NOT synchronized.'
    }
} elseif ($syncOptions.Mode -ne 'Off') {
    Write-DevboxWarning "Warning: '$selected' does not use Mutagen: the sync parameters were ignored."
}

# Next step: the AI client (one per container) is installed from inside the container.
docker exec -u $userName $selected bash -c 'test -e ~/.local/bin/claude || test -e ~/.local/bin/copilot' *> $null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxNext 'Next: inside the container, install one AI client: bash ~/devbox/bash/dkdb-install-claudecode.sh (Claude Code) or bash ~/devbox/bash/dkdb-install-ghcopilot-cli.sh (GitHub Copilot CLI).'
}

# TERM is set explicitly: without it, docker exec may give a plain "xterm" and
# the default Ubuntu .bashrc then shows no colored prompt.
docker exec -it -u $userName -w "/home/$userName" -e TERM=xterm-256color -e COLORTERM=truecolor $selected bash
