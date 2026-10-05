# Stop the Mutagen daemon if it is running (it only checks when it is not).
# It is one daemon per user: stopping it stops ALL Mutagen sessions, not only dkdb-* ones.
. "$PSScriptRoot\dkdb-common.ps1"

if (-not (Test-DevboxMutagen)) {
    Write-Host 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).' -ForegroundColor Red
    exit 1
}
if (-not (Test-DevboxMutagenDaemon)) {
    Write-Host 'The Mutagen daemon is already stopped.'
    exit 0
}

$mutagen = Get-DevboxMutagenExe

# Flush the pending changes of the running Mutagen containers before stopping.
if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker info *> $null
    if ($LASTEXITCODE -eq 0) {
        foreach ($container in (Get-DevboxContainers -Running $true)) {
            if ((Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_SYNC') -eq 'mutagen') {
                Write-Host "Flushing '$container' ..."
                & $mutagen sync flush $container *> $null
            }
        }
    }
}

& $mutagen daemon stop | Out-Null
if (Test-DevboxMutagenDaemon) {
    Write-Host 'Error: the Mutagen daemon is still running.' -ForegroundColor Red
    exit 1
}
Write-Host 'The Mutagen daemon is stopped.' -ForegroundColor Green
Write-Host 'Nothing is synchronized until dkdb-mutagen-start, dkdb-container-start or dkdb-container-connect.'
