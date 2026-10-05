# Stop the Mutagen daemon if it is running (it only checks when it is not).
# Version: 0.2.0
# It is one daemon per user: stopping it stops ALL Mutagen sessions, not only dkdb-* ones.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
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
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Stops the Mutagen daemon. There is one daemon per user, so every Mutagen session stops.' `
        -Needs @(
            'mutagen.exe.'
        ) `
        -Steps @(
            'Checks whether the daemon is running; if it is not, says so and stops.',
            'With Docker reachable, flushes the pending changes of the running Mutagen containers.',
            'Stops the daemon and checks that it is stopped.'
        ) `
        -Changes @(
            'The daemon and all its sessions are stopped (the sessions are kept; they come back when the daemon starts).'
        ) `
        -Never @(
            'Terminates sessions or deletes files.'
        ) `
        -Next 'Nothing is synchronized until you run dkdb-mutagen-sync or choose it in the menu of dkdb-container-start or dkdb-container-connect.'
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
if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker info *> $null
    if ($LASTEXITCODE -eq 0) {
        foreach ($container in (Get-DevboxContainers -Running $true)) {
            if ((Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_SYNC') -eq 'mutagen') { $null = Update-DevboxContainerState -Container $container }
        }
    }
}
Write-DevboxNext 'Next: nothing is synchronized until you run dkdb-mutagen-sync or choose it in the menu of dkdb-container-start or dkdb-container-connect.'
