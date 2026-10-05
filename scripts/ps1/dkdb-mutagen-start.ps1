# Start the Mutagen daemon if it is not running (it only checks when it is).
# dkdb-container-start and dkdb-container-connect already do this for Mutagen containers.
. "$PSScriptRoot\dkdb-common.ps1"

if (-not (Test-DevboxMutagen)) {
    Write-Host 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).' -ForegroundColor Red
    exit 1
}
if (Test-DevboxMutagenDaemon) {
    Write-Host 'The Mutagen daemon is already running.'
    exit 0
}
if (Start-DevboxMutagenDaemon) {
    Write-Host 'The Mutagen daemon is running.' -ForegroundColor Green
    Write-Host 'Sessions are resumed by dkdb-container-start or dkdb-container-connect.'
} else {
    Write-Host 'Error: the Mutagen daemon could not be started.' -ForegroundColor Red
    exit 1
}
