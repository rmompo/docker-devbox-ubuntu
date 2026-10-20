# Synchronize the projects of a running Mutagen container chosen from a menu.
# Version: 0.5.1
# A menu chooses what to synchronize: None, Add (relative), Add (absolute), All or Custom.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Chooses, from menus, a running Mutagen container and what to synchronize in it.' `
        -Usage 'dkdb-mutagen-sync [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-mutagen-sync'; Description = 'Choose the container, then None, Add (relative), Add (absolute), All registered or Custom' }
        ) `
        -Notes @(
            'For a container that uses Mutagen a menu asks what to synchronize: None (the first option, the default: the daemon is started and the existing sessions are paused), Add (relative) (a folder relative to the host projects folder), Add (absolute) (a host folder and a folder of the container), All registered, or Custom (a checklist of the registered sessions: checked ones are active, the others paused). Every Add and activation checks both folders: a missing host folder aborts the operation; a missing folder of the container is created after asking. A new folder is added to what is active; it pauses the active sessions it covers, and changes nothing when an active session already covers it (somebody may be using it). Custom refuses overlapping folders. Nothing is ever terminated.',
            'Sessions are paused, never terminated; the files are not touched.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Chooses a running Mutagen container and what to synchronize in it.' `
        -Needs @(
            'Docker Engine running, mutagen.exe and a running container that uses Mutagen.'
        ) `
        -Steps (@(
            'Shows the menu of the running containers that use Mutagen and warns about versions.'
        ) + $DevboxSyncMenuMan) `
        -Changes @(
            'Sessions are created, resumed or paused according to the choice.'
        ) `
        -Never @(
            'Terminates sessions or touches files.',
            'Creates a session of the whole projects folder.'
        ) `
        -Next 'dkdb-mutagen-status shows the progress; run it again to change the folder.'
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
if ($pick.Cancelled) { exit 0 }
if (-not $pick.Ok) {
    Write-DevboxWarning 'The projects are NOT synchronized.'
    exit 1
}
if ($pick.Active) {
    Write-DevboxSuccess "Mutagen sync for '$selected' is active."
    Write-DevboxNext 'Next: dkdb-mutagen-status shows the progress; run dkdb-mutagen-sync again to change the folder.'
} else {
    Write-DevboxNext 'Next: run dkdb-mutagen-sync again and choose a folder (Add) to synchronize.'
}
