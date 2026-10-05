# Synchronize the projects of a running Mutagen container chosen from a menu: everything (no
# Version: 0.1.0
# switch) or only some folders, added one by one.
# Switch: -SyncFolder <path>[,<path>...] (relative to the projects path or absolute inside it; run
# it again to add more folders).
# PositionalBinding is off so that a stray argument is an error and not a folder.
[CmdletBinding(PositionalBinding = $false)]
param(
    [string[]]$SyncFolder,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Synchronizes the projects of a running Mutagen container chosen from a menu: everything by default, or only the folders given with -SyncFolder, added to the ones already synchronized.' `
        -Usage 'dkdb-mutagen-sync [-SyncFolder <path>[,<path>...]] [-Help]' `
        -Parameters @(
            @{ Name = '-SyncFolder <path>[,<path>...]'; Description = 'Synchronize only these folders instead of everything. Each path is relative to the host projects folder (or absolute inside it) and must exist. Run it again with other folders to add them.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-mutagen-sync'; Description = 'Synchronizes the whole projects folder.' },
            @{ Command = 'dkdb-mutagen-sync -SyncFolder repo2'; Description = 'Adds repo2 to the synchronized folders.' },
            @{ Command = 'dkdb-mutagen-sync -SyncFolder repo3,repo4'; Description = 'Adds repo3 and repo4.' }
        ) `
        -Notes @(
            'Without -SyncFolder, if only some folders are synchronized, it asks before replacing those sessions with the whole-folder session.',
            'A folder inside a synchronized one is skipped; one that contains synchronized folders is refused.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
$syncOptions = Get-DevboxSyncOptions -SyncFolder $SyncFolder
if ($syncOptions.Error) {
    Write-DevboxWarning "Error: $($syncOptions.Error)"
    Write-DevboxNext 'Usage: dkdb-mutagen-sync [-SyncFolder <path>[,<path>...]]'
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

if ($syncOptions.Folders.Count -eq 0) {
    # The whole projects folder replaces the sessions of folders, if there are any.
    if (-not (Start-DevboxMutagenDaemon)) {
        Write-DevboxWarning 'Error: the Mutagen daemon could not be started.'
        exit 1
    }
    $main = Get-DevboxSyncSessionName -Container $selected
    $folderSessions = @(Get-DevboxContainerSyncSessions -Container $selected | Where-Object { $_.Name -ne $main })
    $hasMain = (@(Get-DevboxContainerSyncSessions -Container $selected | Where-Object { $_.Name -eq $main }).Count -gt 0)
    if ($folderSessions.Count -gt 0 -and -not $hasMain) {
        Write-DevboxWarning "'$selected' synchronizes only these folders:"
        $folderSessions | ForEach-Object { Write-Host "  $($_.AlphaPath)" }
        $answer = Read-Host 'Synchronizing everything replaces them (the files are not touched). Terminate those sessions and continue? [y/N]'
        if ($answer -notmatch '^[yY]$') {
            Write-Host 'Cancelled.'
            exit 0
        }
        $mutagen = Get-DevboxMutagenExe
        foreach ($folderSession in $folderSessions) { & $mutagen sync terminate $folderSession.Name *> $null }
    }
}

if (Start-DevboxSync -Container $selected -Flush -Folders $syncOptions.Folders) {
    Write-DevboxSuccess "Mutagen sync for '$selected' is active."
    Write-DevboxNext 'Next: dkdb-mutagen-status shows the progress; add more folders with dkdb-mutagen-sync -SyncFolder <path>.'
} else {
    Write-DevboxWarning 'The projects are NOT synchronized.'
    exit 1
}
