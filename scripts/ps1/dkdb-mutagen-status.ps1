# Show the Mutagen sync status (state and conflicts) of a devbox container chosen from a menu.
# Version: 0.1.2
. "$PSScriptRoot\dkdb-common.ps1"
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
$output = & $mutagen sync list $session 2>&1
$code = $LASTEXITCODE
$output | Out-Host
if ($code -ne 0) {
    Write-DevboxNext "There is no Mutagen session for '$selected' yet: dkdb-container-start or dkdb-container-connect create it."
    exit 1
}

# Progress summary and comparison with the previous query of this session.
Write-Host ''
$complete = $false
$json = (& $mutagen sync list --template '{{json .}}' $session 2>&1 | Out-String)
$progress = Get-DevboxSyncProgress -Json $json
if ($progress) {
    $complete = Show-DevboxSyncProgress -Session $session -Progress $progress
}

if ($complete) {
    Write-DevboxNext 'Next: dkdb-container-connect to work in the container; if there are conflicts, see TROUBLESHOOTING.md.'
} else {
    Write-DevboxNext 'Next: run dkdb-mutagen-status again to see the progress; dkdb-container-connect works meanwhile (the container may have only part of the files).'
}
