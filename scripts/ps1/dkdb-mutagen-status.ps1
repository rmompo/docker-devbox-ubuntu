# Show the Mutagen sync status (state and conflicts) of a devbox container chosen from a menu.
# Version: 0.2.0
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Shows the synchronization state of a Mutagen container chosen from a menu: for every session (the whole projects folder or each synchronized folder) Mutagen''s own output, plus a summary of how many files are done and whether it moved since the previous query.' `
        -Usage 'dkdb-mutagen-status [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-mutagen-status'; Description = 'Pick a container and read its sessions; run it again to see the progress.' }
        ) `
        -Notes @(
            'It also shows paused sessions, the last error and conflicts.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Shows the state of the Mutagen sessions of one container and whether they are progressing.' `
        -Needs @(
            'Docker Engine running, mutagen.exe and the Mutagen daemon running.'
        ) `
        -Steps @(
            'Shows the menu of the dkdb- containers that use Mutagen (running or stopped).',
            'For every session of the container prints its host and container folder, its state and conflicts, and a progress summary (so far X of Y files) compared with the previous query.',
            'Checks that no two active sessions of the container overlap and shows them in red if they do.'
        ) `
        -Changes @(
            'Nothing: it only reads.'
        ) `
        -Never @(
            'Creates, resumes, pauses or terminates sessions.'
        ) `
        -Next 'Run it again to see whether it moves; dkdb-container-connect works meanwhile.'
    exit 0
}
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

$main = Get-DevboxSyncSessionName -Container $selected
$mutagen = Get-DevboxMutagenExe
$sessions = @(Get-DevboxContainerSyncSessions -Container $selected)
if ($sessions.Count -eq 0) {
    Write-DevboxNext "There is no Mutagen session for '$selected' yet: dkdb-mutagen-sync (or the menu of dkdb-container-start or dkdb-container-connect) creates it."
    exit 1
}

# One block per session: the whole projects folder, or each synchronized folder. Each one shows
# a progress summary and compares it with the previous query of that session.
$allComplete = $true
foreach ($sessionInfo in $sessions) {
    $session = $sessionInfo.Name
    $label = "host $($sessionInfo.AlphaPath) <-> container $($sessionInfo.BetaPath)"
    Write-Host ''
    Write-Host "=== $session ($label)"
    $listing = Invoke-DevboxNative -Path $mutagen -Arguments @('sync', 'list', $session)
    if ($listing.Output) { Write-Host $listing.Output.TrimEnd() }
    if ($listing.Error) { Write-DevboxWarning $listing.Error.TrimEnd() }
    Write-Host ''
    $json = (Invoke-DevboxNative -Path $mutagen -Arguments @('sync', 'list', '--template', '{{json .}}', $session)).Output
    $progress = Get-DevboxSyncProgress -Json $json
    $complete = $false
    if ($progress) { $complete = Show-DevboxSyncProgress -Session $session -Progress $progress }
    if (-not $complete) { $allComplete = $false }
}

# The state file of the container (what dkdb-info.sh shows inside it) is refreshed with what was just read.
$null = Update-DevboxContainerState -Container $selected

# Rule: the sessions of one container never overlap (several containers may share a host folder).
Write-Host ''
$overlapCount = Show-DevboxSessionOverlaps -Container $selected -Sessions $sessions
if ($overlapCount -gt 0) { $allComplete = $false }
else { Write-Host 'No overlapping sessions in this container.' }

Write-Host ''
if ($allComplete) {
    Write-DevboxNext 'Next: dkdb-container-connect to work in the container; change the synchronized folder with dkdb-mutagen-sync; if there are conflicts, see TROUBLESHOOTING.md.'
} else {
    Write-DevboxNext 'Next: run dkdb-mutagen-status again to see the progress; dkdb-container-connect works meanwhile (the container may have only part of the files).'
}
