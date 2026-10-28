# Add a folder (a new Mutagen session) to a running Mutagen container.
# Version: 0.1.1
# Same Add (relative) / Add (absolute) flow as the synchronization menu, without the other options.
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
        -Description 'Adds a folder to synchronize (a new Mutagen session) to a running container that uses Mutagen. The container is given with -Container or chosen from a menu.' `
        -Usage 'dkdb-mutagen-add [-Container <name>] [-Help] [-Man]' `
        -Parameters @(
            @{ Name = '-Container'; Description = 'Name of the container (with or without the dkdb- prefix); skips the container menu. It must be a running container that uses Mutagen.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-mutagen-add'; Description = 'Pick a container, then Add (relative) or Add (absolute).' },
            @{ Command = 'dkdb-mutagen-add -Container dkdb-dev'; Description = 'Add a folder to that container.' }
        ) `
        -Notes @(
            'Add (relative) asks for a folder relative to the host projects folder (or absolute inside it); it is mirrored at the same path inside the container. Add (absolute) asks for a host folder and a folder of the container, which can be anywhere; %VAR% and ~ are accepted for the host folder and $HOME and ~ for the folder of the container.',
            'Both folders are checked: a missing host folder aborts the operation; a missing folder of the container is created after asking. The new session is added to the active ones: it pauses the active sessions it covers, and changes nothing when an active session already covers it.',
            'Sessions are never terminated; use dkdb-mutagen-remove for that. The other options of the synchronization menu (Keep (no changes), Custom, All (registered), None (pause all)) are in dkdb-mutagen-sync.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Registers a new folder of a Mutagen container as a synchronization session and activates it.' `
        -Needs @(
            'Docker Engine running, mutagen.exe and a running container that uses Mutagen.'
        ) `
        -Steps @(
            'Uses the container given with -Container, or shows the menu of the running containers that use Mutagen, and warns about versions.',
            'Runs all the checks (variables, mutagen, container ID, host path, container ready, daemon, active overlaps) and starts the Mutagen daemon if needed.',
            'Lists the registered syncs and shows the menu with Add (relative) and Add (absolute).',
            'Checks both folders: the host folder must exist; the folder of the container is created after asking.',
            'Creates the session (or reuses the one of the same folder) and activates it, pausing the active sessions it covers.',
            'Refreshes the state file of the container.'
        ) `
        -Changes @(
            'Creates (or resumes) one Mutagen session; it can pause the active sessions that the new folder covers.',
            'May create the folder of the container after asking.'
        ) `
        -Never @(
            'Terminates sessions or touches the files of the host.',
            'Creates a session of the whole projects folder.',
            'Changes anything without both folders being valid.'
        ) `
        -Next 'dkdb-mutagen-status shows the progress; dkdb-mutagen-remove removes a session; dkdb-mutagen-sync chooses what is active.'
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
    $selected = @($candidates | Where-Object { $_ -eq $Container -or $_ -eq "$DevboxPrefix-$Container" }) | Select-Object -First 1
    if (-not $selected) {
        Write-DevboxWarning "Error: '$Container' is not a running '$DevboxPrefix-' container that uses Mutagen. Available: $($candidates -join ', ')"
        exit 1
    }
} else {
    $selected = Select-DevboxItem -Title 'Select the container to add a folder to:' -Items $candidates
    if (-not $selected) {
        Write-Host 'Cancelled.'
        exit 0
    }
}

$null = Test-DevboxContainerVersion -Container $selected

$pick = Invoke-DevboxSyncPick -Container $selected -Flush -AddOnly
if ($pick.Cancelled) { exit 0 }
if (-not $pick.Ok) {
    Write-DevboxWarning 'The folder was NOT added.'
    exit 1
}
Write-DevboxSuccess "Folder added to '$selected'."
Write-DevboxNext 'Next: dkdb-mutagen-status shows the progress; dkdb-mutagen-remove removes a session.'
