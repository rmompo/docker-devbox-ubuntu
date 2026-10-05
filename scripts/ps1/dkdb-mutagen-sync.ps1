# Synchronize the projects of a running Mutagen container chosen from a menu.
# Version: 0.3.0
# A menu chooses what to synchronize: No sync, a registered folder, All or Add.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Chooses, from menus, a running Mutagen container and what to synchronize in it.' `
        -Usage 'dkdb-mutagen-sync [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-mutagen-sync'; Description = 'Choose the container, then No sync, a registered folder, All registered or Add...' }
        ) `
        -Notes @(
            'For a container that uses Mutagen a menu asks what to synchronize: No sync (the first option, the default: the daemon is started and the existing sessions are paused), a folder already registered as a session, All registered, or Add... (a new folder). Registering projects separately is the recommended way. A folder is added to what is active; it pauses the active sessions it covers, and changes nothing when an active session already covers it (somebody may be using it). All registered activates the sessions that are not inside another one. Nothing is ever terminated.',
            'Sessions are paused, never terminated; the files are not touched.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
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

$pick = Invoke-DevboxSyncPick -Container $selected -Flush
if (-not $pick.Ok) {
    Write-DevboxWarning 'The projects are NOT synchronized.'
    exit 1
}
if ($pick.Active) {
    Write-DevboxSuccess "Mutagen sync for '$selected' is active."
    Write-DevboxNext 'Next: dkdb-mutagen-status shows the progress; run dkdb-mutagen-sync again to change the folder.'
} else {
    Write-DevboxNext 'Next: run dkdb-mutagen-sync again and choose a folder (or Add...) to synchronize.'
}
