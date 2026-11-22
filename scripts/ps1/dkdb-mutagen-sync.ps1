# Synchronize the projects of a running Mutagen container, given with -Container or chosen from a menu.
# Version: 0.6.1
# A menu chooses what to synchronize: Keep (no changes), Custom, All, None (pause all), Add (relative) or Add (absolute).
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Container,
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Chooses a running Mutagen container (given with -Container or from a menu) and, from a menu, what to synchronize in it.' `
        -Usage 'dkdb-mutagen-sync [-Container <name>] [-Help] [-Man]' `
        -Parameters @(
            @{ Name = '-Container'; Description = 'Name of the container (with or without the dkdb- prefix); skips the container menu. It must be a running container that uses Mutagen.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-mutagen-sync'; Description = 'Choose the container, then Keep (no changes), Custom, All (registered), None (pause all), Add (relative) or Add (absolute)' },
            @{ Command = 'dkdb-mutagen-sync -Container dkdb-dev'; Description = 'Same, for that container without the container menu.' }
        ) `
        -Notes @(
            'For a container that uses Mutagen a menu asks what to synchronize: Keep (no changes) (the first option, the default: continue with the sessions exactly as they are; nothing is created, resumed or paused), Custom (a checklist of the registered sessions: checked ones are active, the others paused), All (registered), None (pause all: the daemon is started and the existing sessions are paused), Add (relative) (a folder relative to the host projects folder), or Add (absolute) (a host folder and a folder of the container). Every Add and activation checks both folders: a missing host folder aborts the operation; a missing folder of the container is created after asking. A new folder is added to what is active; it pauses the active sessions it covers, and changes nothing when an active session already covers it (somebody may be using it). Custom refuses overlapping folders. Nothing is ever terminated.',
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
            'Uses the container given with -Container, or shows the menu of the running containers that use Mutagen, and warns about versions.'
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

if ($Container) {
    $selected = Resolve-DevboxContainerName -Name $Container -Candidates $candidates -Kind "a running '$DevboxPrefix-' container that uses Mutagen"
    if (-not $selected) { exit 1 }
} else {
    $selected = Select-DevboxItem -Title 'Select the container to synchronize:' -Items $candidates
    if (-not $selected) {
        Write-Host 'Cancelled.'
        exit 0
    }
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
    Write-DevboxNext 'Next: dkdb-mutagen-status.ps1 shows the progress; run dkdb-mutagen-sync.ps1 again to change the folder.'
} else {
    Write-DevboxNext 'Next: run dkdb-mutagen-sync.ps1 again and choose a folder (Add) to synchronize.'
}
