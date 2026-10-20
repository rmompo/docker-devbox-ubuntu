# Remove one Mutagen session of a devbox container: choose it in a menu, stop (pause) it and terminate it.
# Version: 0.1.0
# The host and container folders are not touched. PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Container,
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Removes one registered Mutagen session of a container (given with -Container, or chosen from a menu): lists the sessions with their state, stops the one you choose and terminates it, after a [y/N] confirmation. The host and container folders are not touched.' `
        -Usage 'dkdb-mutagen-remove [-Container <name>] [-Help] [-Man]' `
        -Parameters @(
            @{ Name = '-Container'; Description = 'Name of the container (with or without the dkdb- prefix); skips the container menu. It must be a container that uses Mutagen.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-mutagen-remove'; Description = 'Pick a container, then the session to remove.' },
            @{ Command = 'dkdb-mutagen-remove -Container dkdb-dev'; Description = 'Pick the session to remove from that container.' }
        ) `
        -Notes @(
            'A removed session is registered again with Add (relative) or Add (absolute) of the synchronization menu.',
            'Orphan sessions (their container no longer exists) are removed with dkdb-mutagen-clean.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Removes one Mutagen session of a container that is no longer wanted.' `
        -Needs @(
            'Docker Engine running, mutagen.exe and the Mutagen daemon running.'
        ) `
        -Steps @(
            'Uses the container given with -Container, or shows the menu of the dkdb- containers that use Mutagen (running or stopped).',
            'Lists the registered sessions of the container, with their state ([active] or [paused]), in a menu.',
            'Shows the chosen session and asks [y/N] (Esc cancels).',
            'Stops (pauses) the session and terminates it.',
            'Refreshes the state file of the container.'
        ) `
        -Changes @(
            'Terminates the chosen Mutagen session; it disappears from the registered syncs.'
        ) `
        -Never @(
            'Touches the host or container folders, or the other sessions.',
            'Creates, resumes or removes anything without asking.'
        ) `
        -Next 'dkdb-mutagen-sync registers folders again; dkdb-mutagen-status shows the remaining sessions.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxDocker

if (-not (Test-DevboxMutagen)) {
    Write-DevboxWarning 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).'
    exit 1
}

$containers = @(Get-DevboxMutagenContainers)
if ($containers.Count -eq 0) {
    Write-Host "No containers starting with '$DevboxPrefix-' use Mutagen."
    exit 0
}

if ($Container) {
    $selected = @($containers | Where-Object { $_ -eq $Container -or $_ -eq "$DevboxPrefix-$Container" }) | Select-Object -First 1
    if (-not $selected) {
        Write-DevboxWarning "Error: '$Container' is not a '$DevboxPrefix-' container that uses Mutagen. Available: $($containers -join ', ')"
        exit 1
    }
} else {
    $selected = Select-DevboxItem -Title 'Select the container whose session you want to remove:' -Items $containers
    if (-not $selected) {
        Write-Host 'Cancelled.'
        exit 0
    }
}

if (-not (Test-DevboxMutagenDaemon)) {
    Write-Host 'The Mutagen daemon is stopped (start it with dkdb-mutagen-start, dkdb-container-start or dkdb-container-connect).'
    exit 0
}

$user = Get-DevboxContainerUser -Container $selected
if (-not $user) {
    Write-DevboxWarning "Error: '$selected' has no DEVBOX_USER variable; it was not created by dkdb-container-create."
    exit 1
}
$sessions = @(Get-DevboxPickSessions -Container $selected -User $user)
if ($sessions.Count -eq 0) {
    Write-Host "There are no Mutagen sessions registered in '$selected': nothing to remove."
    exit 0
}

# The menu shows the state before each session.
$labels = @{}
foreach ($item in ($sessions | Sort-Object { $_.Label })) {
    $state = if ($item.Paused) { 'paused' } else { 'active' }
    $labels["[$state] $($item.Label)"] = $item
}
$choice = Select-DevboxItem -Title "Select the session to remove from '$selected':" -Items @($labels.Keys | Sort-Object { $labels[$_].Label })
if (-not $choice) {
    Write-Host 'Cancelled: nothing was changed.'
    exit 0
}
$target = $labels[$choice]

Write-Host "Session to remove: $($target.Label) ($($target.Name))"
$answer = Read-DevboxLine 'Stop and terminate it? The folders are not touched. [y/N] (Esc cancels)'
if ($null -eq $answer -or $answer -notmatch '^\s*(y|yes)\s*$') {
    Write-Host 'Cancelled: nothing was changed.'
    exit 0
}

$mutagen = Get-DevboxMutagenExe
if (-not $target.Paused) {
    & $mutagen sync pause $target.Name *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "Session '$($target.Name)' stopped." }
    else { Write-DevboxWarning "Warning: could not pause '$($target.Name)'; terminating it anyway." }
}
& $mutagen sync terminate $target.Name *> $null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxWarning "Error: could not terminate the Mutagen session '$($target.Name)'. Check it with: dkdb-mutagen-status"
    exit 1
}
Write-DevboxSuccess "Mutagen session removed: $($target.Label) ($($target.Name))"
$null = Update-DevboxContainerState -Container $selected
Write-DevboxNext 'Next: dkdb-mutagen-status shows the remaining sessions; dkdb-mutagen-sync registers a folder again.'
