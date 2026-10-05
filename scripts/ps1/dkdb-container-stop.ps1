# Stop one running devbox container chosen from a menu.
# Version: 0.2.0
# It never touches Mutagen (daemon or session): see dkdb-mutagen-stop for that.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Stops one running devbox container chosen from a menu.' `
        -Usage 'dkdb-container-stop [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-container-stop'; Description = 'Shows the running containers and stops the one you pick.' }
        ) `
        -Notes @(
            'It never touches Mutagen.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Stops one running devbox container chosen from a menu.' `
        -Needs @(
            'Docker Engine running and a running dkdb- container.'
        ) `
        -Steps @(
            'Shows the menu of running containers.',
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

$containers = Get-DevboxContainers -Running $true
if ($containers.Count -eq 0) {
    Write-Host "No running containers starting with '$DevboxPrefix-' were found."
    exit 0
}

$selected = Select-DevboxItem -Title 'Select the container to stop:' -Items $containers
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

docker stop $selected | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxWarning "Error: could not stop '$selected'."
    exit 1
}
Write-DevboxSuccess "Container '$selected' stopped."
Write-DevboxNext 'Next: dkdb-container-start starts it again, or dkdb-container-delete removes it.'
