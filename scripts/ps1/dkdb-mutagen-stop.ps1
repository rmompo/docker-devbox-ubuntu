# Stop the Mutagen daemon if it is running (it only checks when it is not).
# Version: 0.1.3
# It is one daemon per user: stopping it stops ALL Mutagen sessions, not only dkdb-* ones.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Stops the Mutagen daemon if it is running, after flushing the running Mutagen containers.' `
        -Usage 'dkdb-mutagen-stop [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-mutagen-stop'; Description = 'Checks the daemon and stops it if it is running.' }
        ) `
        -Notes @(
            'There is one daemon per user: it stops ALL your Mutagen sessions, not only the dkdb- ones.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath

if (-not (Test-DevboxMutagen)) {
    Write-DevboxWarning 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).'
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
                $session = Get-DevboxSyncSessionName -Container $container
                if ($session) {
                    Write-Host "Flushing '$session' ..."
                    & $mutagen sync flush $session *> $null
                }
            }
        }
    }
}

& $mutagen daemon stop | Out-Null
if (Test-DevboxMutagenDaemon) {
    Write-DevboxWarning 'Error: the Mutagen daemon is still running.'
    exit 1
}
Write-DevboxSuccess 'The Mutagen daemon is stopped.'
Write-DevboxNext 'Next: nothing is synchronized until dkdb-mutagen-start, dkdb-container-start or dkdb-container-connect.'
