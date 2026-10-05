# Start one stopped devbox container chosen from a menu.
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
        -Description 'Starts one stopped devbox container chosen from a menu. For a container that uses Mutagen it starts the daemon too, but by default nothing is synchronized: ask for it, from the most to the least conservative, with -SyncFolder (some folders) or -SyncAll (everything).' `
        -Usage 'dkdb-container-start [-SyncFolder <path>[,<path>...] | -SyncAll | -SyncOff] [-Help]' `
        -Parameters @(
            @{ Name = '-SyncFolder <path>[,<path>...]'; Description = 'Level 2: synchronize only these folders. Each path is relative to the host projects folder (or absolute inside it) and must exist. Run it again with other folders to add them; other existing sessions are left as they are.' },
            @{ Name = '-SyncAll'; Description = 'Level 3: synchronize the whole projects folder; it can take very long. If only some folders are synchronized, it asks before replacing those sessions.' },
            @{ Name = '-SyncOff'; Description = 'Level 1, the default: the Mutagen daemon is started and the existing sessions of the container are paused; nothing is synchronized. Only needed to say it explicitly.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-container-start'; Description = 'Starts the container and the Mutagen daemon; nothing is synchronized.' },
            @{ Command = 'dkdb-container-start -SyncFolder repo1'; Description = 'Also synchronizes only repo1.' },
            @{ Command = 'dkdb-container-start -SyncFolder repo1,repo2'; Description = 'Synchronizes repo1 and repo2.' },
            @{ Command = 'dkdb-container-start -SyncAll'; Description = 'Synchronizes the whole projects folder.' }
        ) `
        -Notes @(
            'The sync parameters go from the most to the least conservative: nothing (default), some folders, everything. They exclude each other and only affect a container that uses Mutagen.',
            'For a container that uses Mutagen the daemon is always started; what is synchronized depends on the level.',
            'An image older than the scripts only produces a warning: the container keeps working.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
$syncOptions = Get-DevboxSyncOptions -SyncOff $SyncOff.IsPresent -SyncAll $SyncAll.IsPresent -SyncFolder $SyncFolder
if ($syncOptions.Error) {
    Write-DevboxWarning "Error: $($syncOptions.Error)"
    Write-DevboxNext 'Usage: dkdb-container-start [-SyncAll | -SyncFolder <path>[,<path>...] | -SyncOff]'
    exit 1
}
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
    if ($syncOptions.Mode -eq 'Off') {
        # Level 1: the daemon is started and the sessions that exist are paused; nothing is synchronized.
        $null = Suspend-DevboxSyncSessions -Container $selected
        Write-DevboxNext 'Next: dkdb-container-start -SyncAll synchronizes everything, or -SyncFolder <path> only some folders (dkdb-mutagen-sync does it for a running container).'
    } elseif (Start-DevboxSync -Container $selected -Flush -All:$syncOptions.SyncAll -Folders $syncOptions.Folders) {
        Write-DevboxSuccess "Mutagen sync for '$selected' is active."
    } else {
        Write-DevboxWarning 'The container is running, but the projects are NOT synchronized.'
        exit 1
    }
} elseif ($syncOptions.Mode -ne 'Off') {
    Write-DevboxWarning "Warning: '$selected' does not use Mutagen: the sync parameters were ignored."
}

Write-DevboxNext 'Next: dkdb-container-connect.'
