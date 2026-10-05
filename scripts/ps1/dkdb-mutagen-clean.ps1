# Terminate the orphan Mutagen sessions: dkdb- sessions whose container no longer exists
# Version: 0.1.3
# (left by containers deleted outside dkdb-container-delete, or while the Mutagen daemon was
# stopped). The host folders are not touched.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Terminates leftover Mutagen sessions (dkdb-*) whose container no longer exists. It asks before terminating anything; the host folders are not touched.' `
        -Usage 'dkdb-mutagen-clean [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-mutagen-clean'; Description = 'Lists the leftover sessions and terminates the ones you choose.' }
        ) `
        -Notes @(
            'Sessions of folders of a living container are not leftovers.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxDocker

if (-not (Test-DevboxMutagen)) {
    Write-DevboxWarning 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).'
    exit 1
}
if (-not (Test-DevboxMutagenDaemon)) {
    Write-Host 'The Mutagen daemon is stopped: nothing to clean (start it with dkdb-mutagen-start).'
    exit 0
}

$sessions = Get-DevboxMutagenSessionNames
if ($null -eq $sessions) {
    Write-DevboxWarning 'Error: the Mutagen sessions could not be listed.'
    exit 1
}

# Sessions of the containers that still exist are not orphans.
$alive = @(Get-DevboxMutagenContainers | ForEach-Object { Get-DevboxSyncSessionName -Container $_ } | Where-Object { $_ })
# A session belongs to a living container when it is its session or one of its folders (<session>-f...).
$orphans = @($sessions | Where-Object {
    $name = $_
    $_ -like "$DevboxPrefix-*" -and -not ($alive | Where-Object { $name -eq $_ -or $name -like "$_-f*" })
})
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
        Write-DevboxSuccess "Terminated: $target"
    } else {
        Write-DevboxWarning "Error: could not terminate '$target'."
    }
}

Write-DevboxNext 'Next: dkdb-mutagen-status checks the remaining sessions.'
