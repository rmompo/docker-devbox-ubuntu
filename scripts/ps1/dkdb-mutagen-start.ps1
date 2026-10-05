# Start the Mutagen daemon if it is not running (it only checks when it is).
# Version: 0.1.5
# dkdb-container-start and dkdb-container-connect already do this for Mutagen containers.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Starts the Mutagen daemon if it is not running.' `
        -Usage 'dkdb-mutagen-start [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-mutagen-start'; Description = 'Checks the daemon and starts it if needed.' }
        ) `
        -Notes @(
            'dkdb-container-start and dkdb-container-connect start it by themselves for a container that uses Mutagen, and then pause its existing sessions unless you ask to synchronize.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath

if (-not (Test-DevboxMutagen)) {
    Write-DevboxWarning 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).'
    exit 1
}
if (Test-DevboxMutagenDaemon) {
    Write-Host 'The Mutagen daemon is already running.'
    exit 0
}
if (Start-DevboxMutagenDaemon) {
    Write-DevboxSuccess 'The Mutagen daemon is running.'
    Write-DevboxNext 'Next: dkdb-mutagen-sync lets you choose what to synchronize.'
} else {
    Write-DevboxWarning 'Error: the Mutagen daemon could not be started.'
    exit 1
}
