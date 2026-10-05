# Synchronize the projects of a running Mutagen container chosen from a menu.
# Version: 0.1.1
# Everything with -SyncAll, or only some folders with -SyncFolder, added one by one.
# Parameters: -SyncAll (the whole projects folder) or -SyncFolder <path>[,<path>...] (only those folders,
# added to the ones already synchronized; run it again to add more). One of them is required.
# PositionalBinding is off so that a stray argument is an error and not a folder.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SyncAll,
    [string[]]$SyncFolder,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Synchronizes the projects of a running Mutagen container chosen from a menu: everything with -SyncAll, or only the folders given with -SyncFolder, added to the ones already synchronized. One of them is required.' `
        -Usage 'dkdb-mutagen-sync -SyncAll | -SyncFolder <path>[,<path>...] [-Help]' `
        -Parameters @(
            @{ Name = '-SyncAll'; Description = 'Synchronize the whole projects folder. If only some folders are synchronized, it asks before replacing those sessions.' },
            @{ Name = '-SyncFolder <path>[,<path>...]'; Description = 'Synchronize only these folders. Each path is relative to the host projects folder (or absolute inside it) and must exist. Run it again with other folders to add them.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-mutagen-sync -SyncAll'; Description = 'Synchronizes the whole projects folder.' },
            @{ Command = 'dkdb-mutagen-sync -SyncFolder repo2'; Description = 'Adds repo2 to the synchronized folders.' },
            @{ Command = 'dkdb-mutagen-sync -SyncFolder repo3,repo4'; Description = 'Adds repo3 and repo4.' }
        ) `
        -Notes @(
            'Without parameters it only shows this usage: nothing is synchronized by accident.',
            '-SyncAll and -SyncFolder exclude each other.',
            'A folder inside a synchronized one is skipped; one that contains synchronized folders is refused.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
$syncOptions = Get-DevboxSyncOptions -SyncAll $SyncAll.IsPresent -SyncFolder $SyncFolder
if ($syncOptions.Error) {
    Write-DevboxWarning "Error: $($syncOptions.Error)"
    Write-DevboxNext 'Usage: dkdb-mutagen-sync -SyncAll | -SyncFolder <path>[,<path>...]'
    exit 1
}
if ($syncOptions.Mode -eq 'Off') {
    Write-DevboxWarning 'Choose what to synchronize: -SyncAll (everything) or -SyncFolder <path>[,<path>...] (only those folders).'
    & $PSCommandPath -Help
    exit 1
}
Assert-DevboxIntegrity -WarnOnly
Assert-DevboxDocker

if (-not (Test-DevboxMutagen)) {
    Write-DevboxWarning 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).'
    exit 1
}

$candidates = @(Get-DevboxContainers -Running $true | Where-Object { (Get-DevboxContainerEnv -Container $_ -Name 'DEVBOX_SYNC') -eq 'mutagen' })
if ($candidates.Count -eq 0) {
    Write-Host "No running containers starting with '$DevboxPrefix-' use Mutagen (start one with dkdb-container-start)."
    exit 0
}

$selected = Select-DevboxItem -Title 'Select the container to synchronize:' -Items $candidates
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

$null = Test-DevboxContainerVersion -Container $selected

if (Start-DevboxSync -Container $selected -Flush -All:$syncOptions.SyncAll -Folders $syncOptions.Folders) {
    Write-DevboxSuccess "Mutagen sync for '$selected' is active."
    Write-DevboxNext 'Next: dkdb-mutagen-status shows the progress; add more folders with dkdb-mutagen-sync -SyncFolder <path>.'
} else {
    Write-DevboxWarning 'The projects are NOT synchronized.'
    exit 1
}
