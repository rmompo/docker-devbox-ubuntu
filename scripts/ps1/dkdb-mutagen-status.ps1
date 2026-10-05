# Show the Mutagen sync status (state and conflicts) of a devbox container chosen from a menu.
# Version: 0.1.3
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
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
    Write-DevboxNext "There is no Mutagen session for '$selected' yet: dkdb-container-start, dkdb-container-connect or dkdb-mutagen-sync create it."
    exit 1
}

# One block per session: the whole projects folder, or each synchronized folder. Each one shows
# a progress summary and compares it with the previous query of that session.
$allComplete = $true
foreach ($sessionInfo in $sessions) {
    $session = $sessionInfo.Name
    $label = 'the whole projects folder'
    if ($session -ne $main) { $label = "folder $($sessionInfo.AlphaPath)" }
    Write-Host ''
    Write-Host "=== $session ($label)"
    $output = & $mutagen sync list $session 2>&1
    $output | Out-Host
    Write-Host ''
    $json = (& $mutagen sync list --template '{{json .}}' $session 2>&1 | Out-String)
    $progress = Get-DevboxSyncProgress -Json $json
    $complete = $false
    if ($progress) { $complete = Show-DevboxSyncProgress -Session $session -Progress $progress }
    if (-not $complete) { $allComplete = $false }
}

Write-Host ''
if ($allComplete) {
    Write-DevboxNext 'Next: dkdb-container-connect to work in the container; add folders with dkdb-mutagen-sync -SyncFolder <path>; if there are conflicts, see TROUBLESHOOTING.md.'
} else {
    Write-DevboxNext 'Next: run dkdb-mutagen-status again to see the progress; dkdb-container-connect works meanwhile (the container may have only part of the files).'
}
