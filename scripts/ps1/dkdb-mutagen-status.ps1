# Show the Mutagen sync status (state and conflicts) of a devbox container chosen from a menu.
# Version: 0.1.0
. "$PSScriptRoot\dkdb-common.ps1"
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxDocker

if (-not (Test-DevboxMutagen)) {
    Write-Host 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).' -ForegroundColor Red
    exit 1
}

$containers = @(Get-DevboxMutagenContainers)
if ($containers.Count -eq 0) {
    Write-Host "No containers starting with '$DevboxPrefix-' use Mutagen."
    exit 0
}

$selected = Select-DevboxItem -Title 'Select the container to check:' -Items $containers
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

if (-not (Test-DevboxMutagenDaemon)) {
    Write-Host 'The Mutagen daemon is stopped (start it with dkdb-mutagen-start, dkdb-container-start or dkdb-container-connect).'
    exit 0
}

$session = Get-DevboxSyncSessionName -Container $selected
$mutagen = Get-DevboxMutagenExe
& $mutagen sync list $session
if ($LASTEXITCODE -ne 0) {
    Write-Host "There is no Mutagen session for '$selected' yet: dkdb-container-start or dkdb-container-connect create it." -ForegroundColor Yellow
    exit 1
}
