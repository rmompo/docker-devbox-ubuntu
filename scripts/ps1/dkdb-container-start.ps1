# Start one stopped devbox container, given with -Container or chosen from a menu.
# Version: 0.8.1
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
            'The menu comes back after every action (with its list read again) until you press Esc (Up/Down move, Enter selects, Esc goes back); an action that prints something waits for a key before the screen is cleared. With -Container it runs once, without a menu.',
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

$DevboxMenuScript = $PSCommandPath

function Invoke-StartAction {
    param([Parameter(Mandatory)][string]$Selected)
    $null = Test-DevboxContainerVersion -Container $Selected
    docker start $Selected | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-DevboxWarning "Error: could not start '$Selected'."
        Set-DevboxActionResult 1
        return
    }
    Write-DevboxSuccess "Container '$Selected' started."
    if ((Get-DevboxContainerEnv -Container $Selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
        # The daemon is started and the sessions stay as they are (dkdb-mutagen-manage changes them).
        $pick = Invoke-DevboxSyncPick -Container $Selected -KeepOnly
        if (-not $pick.Ok) {
            Write-DevboxWarning 'The container is running, but the projects are NOT synchronized.'
            Set-DevboxActionResult 1
            return
        }
        if ($pick.Active) { Write-DevboxSuccess "Mutagen sync for '$Selected' is active." }
        else {
            Write-DevboxNext 'Next: dkdb-mutagen-manage.ps1 chooses what to synchronize (Add or Modify), then dkdb-container-connect.ps1.'
            return
        }
    }
    Write-DevboxNext 'Next: dkdb-container-connect.ps1.'
    return
}

Invoke-DevboxItemMenu -Path 'Containers > Start' -Title 'Select the container to start:' -Name $Container `
    -Kind "a stopped '$DevboxPrefix-' container" -EmptyMessage "No stopped containers starting with '$DevboxPrefix-' were found." `
    -GetItems { Get-DevboxContainers -Running $false } -Action { param($item) Invoke-StartAction -Selected $item }
exit $script:DevboxItemMenuCode
