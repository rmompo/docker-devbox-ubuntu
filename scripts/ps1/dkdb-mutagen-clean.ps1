# Terminate the orphan Mutagen sessions: dkdb- sessions whose container no longer exists
# (left by containers deleted outside dkdb-container-delete, or while the Mutagen daemon was
# stopped). The host folders are not touched.
. "$PSScriptRoot\dkdb-common.ps1"
Assert-DevboxDocker

if (-not (Test-DevboxMutagen)) {
    Write-Host 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).' -ForegroundColor Red
    exit 1
}
if (-not (Test-DevboxMutagenDaemon)) {
    Write-Host 'The Mutagen daemon is stopped: nothing to clean (start it with dkdb-mutagen-start).'
    exit 0
}

$sessions = Get-DevboxMutagenSessionNames
if ($null -eq $sessions) {
    Write-Host 'Error: the Mutagen sessions could not be listed.' -ForegroundColor Red
    exit 1
}

# Sessions of the containers that still exist are not orphans.
$alive = @(Get-DevboxMutagenContainers | ForEach-Object { Get-DevboxSyncSessionName -Container $_ } | Where-Object { $_ })
$orphans = @($sessions | Where-Object { $_ -like "$DevboxPrefix-*" -and $alive -notcontains $_ })
if ($orphans.Count -eq 0) {
    Write-Host 'No orphan Mutagen sessions were found.'
    exit 0
}

$allItem = '(all orphan sessions)'
$selected = Select-DevboxItem -Title 'Select the orphan Mutagen session to terminate:' -Items (@($orphans) + $allItem)
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}
$targets = @($selected)
if ($selected -eq $allItem) { $targets = $orphans }

Write-Host 'Sessions to terminate:'
$targets | ForEach-Object { Write-Host "  $_" }
$answer = Read-Host 'Terminate them? The host folders are not touched. [y/N]'
if ($answer -notmatch '^[yY]$') {
    Write-Host 'Cancelled.'
    exit 0
}

$mutagen = Get-DevboxMutagenExe
foreach ($target in $targets) {
    & $mutagen sync terminate $target | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Terminated: $target" -ForegroundColor Green
    } else {
        Write-Host "Error: could not terminate '$target'." -ForegroundColor Red
    }
}
