# Terminate the orphan Mutagen sessions: dkdb- sessions whose container no longer exists
# Version: 0.1.4
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
        -Description 'Terminates leftover Mutagen sessions whose container (the docker endpoint of the session) no longer exists. It does not need any running container, only Mutagen and Docker. It asks before terminating anything; the host folders are not touched.' `
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

$allSessions = @(Get-DevboxMutagenSessions)
if ($allSessions.Count -eq 0) {
    Write-Host 'There are no Mutagen sessions: nothing to clean.'
    exit 0
}

# An orphan is a session whose beta points to a Docker container that no longer exists, whatever its
# name (it works even when no container exists at all, running or stopped).
$refs = @(Get-DevboxAllContainerRefs)
$alive = @(Get-DevboxMutagenContainers | ForEach-Object { Get-DevboxSyncSessionName -Container $_ } | Where-Object { $_ })
$orphans = @($allSessions | Where-Object { Test-DevboxSessionOrphan -Session $_ -ContainerRefs $refs -AliveMainSessions $alive })
if ($orphans.Count -eq 0) {
    Write-Host 'No orphan Mutagen sessions were found.'
    exit 0
}

# The menu shows where each orphan pointed to.
$labels = @{}
foreach ($orphan in $orphans) {
    $target = $orphan.BetaHost
    if ($target) { $target = "$target`:$($orphan.BetaPath)" } else { $target = 'unknown target' }
    $labels["$($orphan.Name)  [$target]"] = $orphan.Name
}
$allItem = '(all orphan sessions)'
$selected = Select-DevboxItem -Title 'Select the orphan Mutagen session to terminate:' -Items (@($labels.Keys | Sort-Object) + $allItem)
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}
$targets = @($labels.Values | Sort-Object)
if ($selected -ne $allItem) { $targets = @($labels[$selected]) }

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
