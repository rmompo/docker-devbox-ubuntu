# Start one stopped devbox container chosen from a menu.
# Version: 0.4.0
# For a Mutagen container a menu chooses what to synchronize (No sync is the first option and the default).
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Starts one stopped devbox container chosen from a menu. For a container that uses Mutagen it starts the daemon too and then asks what to synchronize; by default (No sync) nothing is.' `
        -Usage 'dkdb-container-start [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-container-start'; Description = 'Starts the container; for a Mutagen container it then shows the synchronization menu.' }
        ) `
        -Notes @(
            'For a container that uses Mutagen a menu asks what to synchronize: No sync (the first option, the default: the daemon is started and the existing sessions are paused), a folder already registered as a session, All registered, or Add... (a new folder). Registering projects separately is the recommended way. A folder is added to what is active; it pauses the active sessions it covers, and changes nothing when an active session already covers it (somebody may be using it). All registered activates the sessions that are not inside another one. Nothing is ever terminated.',
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
        -Steps (@(
            'Warns, never stops, when the package or the image of the container have another version.',
            'Shows the menu of stopped containers and runs docker start.'
        ) + $DevboxSyncMenuMan) `
        -Changes @(
            'The container is running.',
            'With Mutagen, sessions may be created, resumed or paused according to the choice.'
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

$selected = Select-DevboxItem -Title 'Select the container to start:' -Items $containers
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

$null = Test-DevboxContainerVersion -Container $selected

docker start $selected | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxWarning "Error: could not start '$selected'."
    exit 1
}
Write-DevboxSuccess "Container '$selected' started."

if ((Get-DevboxContainerEnv -Container $selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
    # The menu decides what is synchronized; the first option, No sync, is the default.
    $pick = Invoke-DevboxSyncPick -Container $selected -Flush
    if (-not $pick.Ok) {
        Write-DevboxWarning 'The container is running, but the projects are NOT synchronized.'
        exit 1
    }
    if ($pick.Active) { Write-DevboxSuccess "Mutagen sync for '$selected' is active." }
}

Write-DevboxNext 'Next: dkdb-container-connect.'
