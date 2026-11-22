# Start one stopped devbox container, given with -Container or chosen from a menu.
# Version: 0.7.0
# For a Mutagen container it starts the daemon and leaves the sessions as they are (dkdb-mutagen-manage changes them).
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
        -Description 'Starts one stopped devbox container, given with -Container or chosen from a menu. For a container that uses Mutagen it starts the daemon too and leaves the sessions as they are; dkdb-mutagen-manage changes what is synchronized.' `
        -Usage 'dkdb-container-start [-Container <name>] [-Help] [-Man]' `
        -Parameters @(
            @{ Name = '-Container'; Description = 'Name of the container (with or without the dkdb- prefix); skips the container menu. It must be a stopped container.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-container-start'; Description = 'Starts the container; for a Mutagen container it also makes sure the daemon runs.' },
            @{ Command = 'dkdb-container-start -Container dkdb-dev'; Description = 'Starts that container without the menu.' }
        ) `
        -Notes @(
            'For a container that uses Mutagen it starts the daemon and leaves the sessions exactly as they are: nothing is created, resumed, paused or terminated. To choose what is synchronized use dkdb-mutagen-manage.',
            'An image older than the scripts only produces a warning: the container keeps working.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Starts one stopped devbox container chosen from a menu.' `
        -Needs @(
            'Docker Engine running and a stopped dkdb- container.'
        ) `
        -Steps @(
            'Warns, never stops, when the package or the image of the container have another version.',
            'Uses the container given with -Container, or shows the menu of stopped containers, and runs docker start.',
            'If the container uses Mutagen, runs the checks (variables, mutagen, container ID, host path, container ready, active overlaps), starts the Mutagen daemon if needed and lists the registered sessions with their state; the sessions stay as they are (use dkdb-mutagen-manage to change them).'
        ) `
        -Changes @(
            'The container is running.',
            'With Mutagen, the daemon may be started; no session is changed.'
        ) `
        -Never @(
            'Is blocked by versions.',
            'Terminates sessions or touches files.'
        ) `
        -Next 'dkdb-container-connect.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity -WarnOnly
Assert-DevboxDocker

$containers = Get-DevboxContainers -Running $false
if ($containers.Count -eq 0) {
    Write-Host "No stopped containers starting with '$DevboxPrefix-' were found."
    exit 0
}

if ($Container) {
    $selected = Resolve-DevboxContainerName -Name $Container -Candidates $containers -Kind "a stopped '$DevboxPrefix-' container"
    if (-not $selected) { exit 1 }
} else {
    $selected = Select-DevboxItem -Title 'Select the container to start:' -Items $containers
    if (-not $selected) {
        Write-Host 'Cancelled.'
        exit 0
    }
}

$null = Test-DevboxContainerVersion -Container $selected

docker start $selected | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxWarning "Error: could not start '$selected'."
    exit 1
}
Write-DevboxSuccess "Container '$selected' started."

if ((Get-DevboxContainerEnv -Container $selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
    # The daemon is started and the sessions stay as they are (dkdb-mutagen-manage changes them).
    $pick = Invoke-DevboxSyncPick -Container $selected -KeepOnly
    if (-not $pick.Ok) {
        Write-DevboxWarning 'The container is running, but the projects are NOT synchronized.'
        exit 1
    }
    if ($pick.Active) { Write-DevboxSuccess "Mutagen sync for '$selected' is active." }
    else { Write-DevboxNext 'Next: dkdb-mutagen-manage.ps1 chooses what to synchronize (Add or Modify), then dkdb-container-connect.ps1.'; exit 0 }
}

Write-DevboxNext 'Next: dkdb-container-connect.ps1.'
