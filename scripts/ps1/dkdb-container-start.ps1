# Start one stopped devbox container chosen from a menu.
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
        -Description 'Starts one stopped devbox container chosen from a menu. For a container that uses Mutagen it also starts the daemon and synchronizes the projects: everything by default.' `
        -Usage 'dkdb-container-start [-SyncOff | -SyncFolder <path>[,<path>...]] [-Help]' `
        -Parameters @(
            @{ Name = '-SyncOff'; Description = 'Do not touch Mutagen in this run (no daemon, no sessions, no flush). It cannot be combined with -SyncFolder.' },
            @{ Name = '-SyncFolder <path>[,<path>...]'; Description = 'Synchronize only these folders instead of everything. Each path is relative to the host projects folder (or absolute inside it) and must exist. Run it again with other folders to add them.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-container-start'; Description = 'Starts the container and synchronizes the whole projects folder.' },
            @{ Command = 'dkdb-container-start -SyncFolder repo1'; Description = 'Starts it and synchronizes only repo1.' },
            @{ Command = 'dkdb-container-start -SyncFolder repo1,repo2'; Description = 'Synchronizes repo1 and repo2.' },
            @{ Command = 'dkdb-container-start -SyncOff'; Description = 'Starts it without touching Mutagen.' }
        ) `
        -Notes @(
            'Only a Mutagen container is affected by the sync parameters.',
            'An image older than the scripts only produces a warning: the container keeps working.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
$syncOptions = Get-DevboxSyncOptions -SyncOff $SyncOff.IsPresent -SyncFolder $SyncFolder
if ($syncOptions.Error) {
    Write-DevboxWarning "Error: $($syncOptions.Error)"
    Write-DevboxNext 'Usage: dkdb-container-start [-SyncOff | -SyncFolder <path>[,<path>...]]'
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
    if ($syncOptions.SyncOff) {
        Write-Host 'Mutagen synchronization skipped (-SyncOff).'
        Write-DevboxNext 'Next: dkdb-mutagen-sync synchronizes everything, or only some folders with -SyncFolder <path>.'
    } elseif (Start-DevboxSync -Container $selected -Flush -Folders $syncOptions.Folders) {
        Write-DevboxSuccess "Mutagen sync for '$selected' is active."
    } else {
        Write-DevboxWarning 'The container is running, but the projects are NOT synchronized.'
        exit 1
    }
} elseif ($syncOptions.SyncOff -or $syncOptions.Folders.Count -gt 0) {
    Write-DevboxWarning "Warning: '$selected' does not use Mutagen: the sync switches were ignored."
}

Write-DevboxNext 'Next: dkdb-container-connect.'
