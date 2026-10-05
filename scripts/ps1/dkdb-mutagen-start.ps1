# Start the Mutagen daemon if it is not running (it only checks when it is).
# Version: 0.1.2
# dkdb-container-start and dkdb-container-connect already do this for Mutagen containers.
. "$PSScriptRoot\dkdb-common.ps1"
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
    Write-DevboxNext 'Next: dkdb-container-start or dkdb-container-connect resume the sessions.'
} else {
    Write-DevboxWarning 'Error: the Mutagen daemon could not be started.'
    exit 1
}
