# Stop one running devbox container, given with -Container or chosen from a menu.
# Version: 0.4.0
# It never touches Mutagen (daemon or session): see dkdb-mutagen-service for that.
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
        -Description 'Stops one running devbox container, given with -Container or chosen from a menu.' `
        -Usage 'dkdb-container-stop [-Container <name>] [-Help] [-Man]' `
        -Parameters @(
            @{ Name = '-Container'; Description = 'Name of the container (with or without the dkdb- prefix); skips the container menu. It must be a running container.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-container-stop'; Description = 'Shows the running containers and stops the one you pick.' },
            @{ Command = 'dkdb-container-stop -Container dkdb-dev'; Description = 'Stops that container without the menu.' }
        ) `
        -Notes @(
            'The menu comes back after every action (with its list read again) until you press Esc (Up/Down move, Enter selects, Esc goes back); an action that prints something waits for a key before the screen is cleared. With -Container it runs once, without a menu.',
            'It never touches Mutagen.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Stops one running devbox container, given with -Container or chosen from a menu.' `
        -Needs @(
            'Docker Engine running and a running dkdb- container.'
        ) `
        -Steps @(
            'Uses the container given with -Container, or shows the menu of running containers.',
            'Runs docker stop.'
        ) `
        -Changes @(
            'The container is stopped (its data is kept).'
        ) `
        -Never @(
            'Touches Mutagen (the daemon or any session): their sessions stay and reconnect by themselves when the container is up.',
            'Deletes anything.'
        ) `
        -Next 'dkdb-container-start starts it again, or dkdb-container-delete removes it.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxDocker

$DevboxMenuScript = $PSCommandPath

function Invoke-StopAction {
    param([Parameter(Mandatory)][string]$Selected)
    docker stop $Selected | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-DevboxWarning "Error: could not stop '$Selected'."
        return 1
    }
    Write-DevboxSuccess "Container '$Selected' stopped."
    Write-DevboxNext 'Next: dkdb-container-start.ps1 starts it again, or dkdb-container-delete.ps1 removes it.'
    return 0
}

Invoke-DevboxItemMenu -Path 'Containers > Stop' -Title 'Select the container to stop:' -Name $Container `
    -Kind "a running '$DevboxPrefix-' container" -EmptyMessage "No running containers starting with '$DevboxPrefix-' were found." `
    -GetItems { Get-DevboxContainers -Running $true } -Action { param($item) Invoke-StopAction -Selected $item }
exit $script:DevboxItemMenuCode
