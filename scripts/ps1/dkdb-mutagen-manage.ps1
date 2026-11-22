# Manage the Mutagen sessions of a devbox container: add a folder, activate or pause sessions, remove one, see the status.
# Version: 0.3.0
# The container first (given with -Container, or chosen from a menu), then a menu of what to do with it. The Mutagen service itself
# (the daemon, the orphan sessions) is controlled with dkdb-mutagen-service.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Container,
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Manages the Mutagen sessions of a container that uses Mutagen. First the container (given with -Container, or chosen from a menu), then a menu of what to do with it: Add a folder (a new session), Modify (activate or pause sessions), Remove a session and Status (state, conflicts and progress).' `
        -Usage 'dkdb-mutagen-manage [-Container <name>] [-Help] [-Man]' `
        -Parameters @(
            @{ Name = '-Container'; Description = 'Name of the container (with or without the dkdb- prefix); skips the container menu. It must be a container that uses Mutagen; Add and Modify are only offered when it is running.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-mutagen-manage'; Description = 'Pick the container, then the action.' },
            @{ Command = 'dkdb-mutagen-manage -Container dkdb-dev'; Description = 'Skip the container menu: pick the action for that container.' }
        ) `
        -Notes @(
            'Both menus come back after every action until you press Esc (Up/Down move, Enter selects, Esc goes back; in the actions it returns to the containers); an action that prints something waits for a key before the screen is cleared.',
            'Add: Add (relative) asks for a folder relative to the host projects folder (or absolute inside it); it is mirrored at the same path inside the container. Add (absolute) asks for a host folder and a folder of the container, which can be anywhere; %VAR% and ~ are accepted for the host folder and $HOME and ~ for the folder of the container. Both folders are checked: a missing host folder aborts the operation; a missing folder of the container is created after asking. The new session is added to the active ones: it pauses the active sessions it covers, and changes nothing when an active session already covers it.',
            'Modify: a menu with Keep (no changes) (the first option, the default), Custom (a checklist of the registered sessions: checked ones are active, the others paused), All (registered) and None (pause all). Sessions are only paused, never terminated. A session cannot change its folders: to change one, Remove it and Add the new one.',
            'Remove: lists the sessions of the container with their state, stops the one you choose and terminates it, after a [y/N] confirmation. The host and container folders are not touched.',
            'Status: for every session a card (name, identifier, endpoints, state) and a summary of how many files are done and whether it moved since the previous query. With no -Container the container menu starts with (all containers), which shows the status of every Mutagen container (it is the only action that applies to all).',
            'Orphan sessions (their container no longer exists) are removed with dkdb-mutagen-service (Clean).'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Manages the Mutagen sessions of a container: adds a folder, activates or pauses sessions, removes one, shows the status.' `
        -Needs @(
            'Docker Engine running, mutagen.exe and a container that uses Mutagen (running for Add and Modify; Remove and Status also work with a stopped one).'
        ) `
        -Steps @(
            'Uses the container given with -Container, or shows the menu of the containers that use Mutagen (running or stopped), starting with (all containers), which goes straight to Status.',
            'Shows the menu of what to do with that container: Status, Add a folder, Modify and Remove a session (Add and Modify only when the container is running). Add and Modify warn about versions and never stop because of them.',
            'Add: runs the checks (variables, mutagen, container ID, host path, container ready, daemon, active overlaps), starts the Mutagen daemon if needed and shows Add (relative) and Add (absolute); both folders are checked (the host folder must exist; the folder of the container is created after asking). The session is created (or the one of the same folder reused) and activated, pausing the active sessions it covers.',
            'Modify: runs the same checks and shows Keep (no changes) (the first option and the default), Custom, All (registered) and None (pause all).',
            'Remove: lists the registered sessions with [active] or [paused], asks [y/N] (Esc cancels), pauses the chosen one and terminates it.',
            'Status: for every session prints a card and a progress summary (so far X of Y files) compared with the previous query, and checks that no two active sessions of the container overlap.',
            'Refreshes the state file of the container, which dkdb-info.sh shows inside it.'
        ) `
        -Changes @(
            'Add: creates (or resumes) one session; it can pause the active sessions that the new folder covers.',
            'Modify: sessions are resumed or paused.',
            'Remove: terminates one session.',
            'Status: nothing, apart from the state file of the container.'
        ) `
        -Never @(
            'Terminates a session without asking, or touches the host or container folders.',
            'Creates a session of the whole projects folder.',
            'Stops the daemon or cleans orphan sessions (that is dkdb-mutagen-service).'
        ) `
        -Next 'dkdb-mutagen-manage.ps1 (Status) shows the progress; dkdb-container-connect.ps1 works in the container.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity -WarnOnly
Assert-DevboxDocker

if (-not (Test-DevboxMutagen)) {
    Write-DevboxWarning 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).'
    exit 1
}

$allContainersItem = '(all containers)'

function Invoke-ManageAdd {
    param([Parameter(Mandatory)][string]$Selected)
    $null = Test-DevboxContainerVersion -Container $selected
    $pick = Invoke-DevboxSyncPick -Container $selected -Flush -AddOnly
    if ($pick.Cancelled) { return }
    if (-not $pick.Ok) {
        Write-DevboxWarning 'The folder was NOT added.'
        return
    }
    Write-DevboxSuccess "Folder added to '$selected'."
    Write-DevboxNext 'Next: dkdb-mutagen-manage.ps1 (Status) shows the progress; Remove removes a session.'
}

function Invoke-ManageModify {
    param([Parameter(Mandatory)][string]$Selected)
    $null = Test-DevboxContainerVersion -Container $selected
    $pick = Invoke-DevboxSyncPick -Container $selected -Flush -NoAdd
    if ($pick.Cancelled) { return }
    if (-not $pick.Ok) {
        Write-DevboxWarning 'The sessions were NOT changed.'
        return
    }
    if ($pick.Active) {
        Write-DevboxSuccess "Mutagen sync for '$selected' is active."
        Write-DevboxNext 'Next: dkdb-mutagen-manage.ps1 (Status) shows the progress; run it again to change the sessions.'
    } else {
        Write-DevboxNext 'Next: run dkdb-mutagen-manage.ps1 again (Modify or Add) to synchronize a folder.'
    }
}

function Invoke-ManageRemove {
    param([Parameter(Mandatory)][string]$Selected)
    if (-not (Test-DevboxMutagenDaemon)) {
        Write-Host 'The Mutagen daemon is stopped (start it with dkdb-mutagen-service.ps1, dkdb-container-start.ps1 or dkdb-container-connect.ps1).'
        return
    }
    $user = Get-DevboxContainerUser -Container $selected
    if (-not $user) {
        Write-DevboxWarning "Error: '$selected' has no DEVBOX_USER variable; it was not created by dkdb-container-create.ps1."
        return
    }
    $sessions = @(Get-DevboxPickSessions -Container $selected -User $user)
    if ($sessions.Count -eq 0) {
        Write-Host "There are no Mutagen sessions registered in '$selected': nothing to remove."
        return
    }
    # The menu shows the state before each session.
    $labels = @{}
    foreach ($item in ($sessions | Sort-Object { $_.Label })) {
        $state = if ($item.Paused) { 'paused' } else { 'active' }
        $labels["[$state] $($item.Label)"] = $item
    }
    $choice = Select-DevboxItem -Title "Select the session to remove from '$selected':" -Items @($labels.Keys | Sort-Object { $labels[$_].Label }) -EscapeAction back
    if (-not $choice) {
        Write-Host 'Cancelled: nothing was changed.'
        return
    }
    $target = $labels[$choice]

    Write-Host "Session to remove: $($target.Label) ($($target.Name))"
    $answer = Read-DevboxLine 'Stop and terminate it? The folders are not touched. [y/N] (Esc cancels)'
    if ($null -eq $answer -or $answer -notmatch '^\s*(y|yes)\s*$') {
        Write-Host 'Cancelled: nothing was changed.'
        return
    }
    $mutagen = Get-DevboxMutagenExe
    if (-not $target.Paused) {
        & $mutagen sync pause $target.Name *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host "Session '$($target.Name)' stopped." }
        else { Write-DevboxWarning "Warning: could not pause '$($target.Name)'; terminating it anyway." }
    }
    & $mutagen sync terminate $target.Name *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-DevboxWarning "Error: could not terminate the Mutagen session '$($target.Name)'. Check it with the Status action of dkdb-mutagen-manage.ps1."
        return
    }
    Write-DevboxSuccess "Mutagen session removed: $($target.Label) ($($target.Name))"
    $null = Update-DevboxContainerState -Container $selected
    Write-DevboxNext 'Next: dkdb-mutagen-manage.ps1 (Status) shows the remaining sessions; Add registers a folder again.'
}

# The status of the sessions of one container. It leaves in $script:StatusComplete: $true when everything is complete
# and nothing overlaps, $false otherwise, $null when the container has no session yet.
function Show-ManageStatus {
    param([Parameter(Mandatory)][string]$Selected)
    $script:StatusComplete = $null
    $mutagen = Get-DevboxMutagenExe
    $sessions = @(Get-DevboxContainerSyncSessions -Container $Selected)
    if ($sessions.Count -eq 0) {
        Write-Host "There is no Mutagen session for '$Selected' yet (Add or Modify of dkdb-mutagen-manage.ps1, or the menu of dkdb-container-start.ps1 or dkdb-container-connect.ps1, creates it)."
        return
    }
    # One block per session: the whole projects folder, or each synchronized folder. Each one shows
    # a progress summary and compares it with the previous query of that session.
    $allComplete = $true
    foreach ($sessionInfo in $sessions) {
        $session = $sessionInfo.Name
        Write-Host ''
        $json = (Invoke-DevboxNative -Path $mutagen -Arguments @('sync', 'list', '--template', '{{json .}}', $session)).Output
        $raw = @(ConvertFrom-DevboxJsonList -Json $json) | Select-Object -First 1
        if ($raw) {
            Show-DevboxSyncCard -Session $raw
        } else {
            $listing = Invoke-DevboxNative -Path $mutagen -Arguments @('sync', 'list', $session)
            if ($listing.Output) { Write-Host $listing.Output.TrimEnd() }
            if ($listing.Error) { Write-DevboxWarning $listing.Error.TrimEnd() }
        }
        Write-Host ''
        $progress = Get-DevboxSyncProgress -Json $json
        $complete = $false
        if ($progress) { $complete = Show-DevboxSyncProgress -Session $session -Progress $progress }
        if (-not $complete) { $allComplete = $false }
    }
    # The state file of the container (what dkdb-info.sh shows inside it) is refreshed with what was just read.
    $null = Update-DevboxContainerState -Container $Selected
    # Rule: the sessions of one container never overlap (several containers may share a host folder).
    Write-Host ''
    $overlapCount = Show-DevboxSessionOverlaps -Container $Selected -Sessions $sessions
    if ($overlapCount -gt 0) { $allComplete = $false }
    else { Write-Host 'No overlapping sessions in this container.' }
    $script:StatusComplete = $allComplete
}

function Invoke-ManageStatus {
    param([Parameter(Mandatory)][string]$Selected)
    if (-not (Test-DevboxMutagenDaemon)) {
        Write-Host 'The Mutagen daemon is stopped (start it with dkdb-mutagen-service.ps1, dkdb-container-start.ps1 or dkdb-container-connect.ps1).'
        return
    }
    $targets = @($selected)
    if ($selected -eq $allContainersItem) { $targets = @(Get-DevboxMutagenContainers) }
    $allComplete = $true
    $missing = $false
    foreach ($target in $targets) {
        if ($targets.Count -gt 1) {
            Write-Host ''
            Write-Host $target -ForegroundColor $DevboxContainerColor
        }
        Show-ManageStatus -Selected $target
        if ($null -eq $script:StatusComplete) { $missing = $true; $allComplete = $false }
        elseif (-not $script:StatusComplete) { $allComplete = $false }
    }
    Write-Host ''
    if ($missing -and $targets.Count -eq 1) { return }
    if ($allComplete) {
        Write-DevboxNext 'Next: dkdb-container-connect.ps1 to work in the container; change the synchronized folders with dkdb-mutagen-manage.ps1 (Modify, Add or Remove); if there are conflicts, see TROUBLESHOOTING.md.'
    } else {
        Write-DevboxNext 'Next: run dkdb-mutagen-manage.ps1 (Status) again to see the progress; dkdb-container-connect.ps1 works meanwhile (the container may have only part of the files).'
    }
}

# 1. The container: -Container, or a menu (with (all containers), which only has the Status action). 2. The action,
# from a menu that only offers what applies to that container (Add and Modify need it running). Both menus come
# back after every action, with the screen drawn again, until Esc: Esc in the actions goes back to the containers
# (the script ends instead when the container was given with -Container) and Esc in the containers ends the script.
$DevboxMenuScript = $PSCommandPath
$addItem = 'Add a folder (a new session)'
$modifyItem = 'Modify (activate or pause sessions)'
$removeItem = 'Remove a session'
$statusItem = 'Status of the sessions'
$exitCode = 0
while ($true) {
    $candidates = @(Get-DevboxMutagenContainers)
    if ($candidates.Count -eq 0) {
        Write-Host "No containers starting with '$DevboxPrefix-' use Mutagen."
        break
    }
    if ($Container) {
        $selected = Resolve-DevboxContainerName -Name $Container -Candidates $candidates -Kind "a '$DevboxPrefix-' container that uses Mutagen"
        if (-not $selected) { $exitCode = 1; break }
    } else {
        $DevboxMenuPath = 'Mutagen sessions'
        $selected = Select-DevboxItem -Title 'Select the container whose Mutagen sessions you want to manage:' -Items (@($allContainersItem) + $candidates) -Clear -EscapeAction exit
        if (-not $selected) { break }
    }
    if ($selected -eq $allContainersItem) {
        $DevboxMenuPath = "Mutagen sessions > $allContainersItem > Status"
        Show-DevboxMenuHeader
        Invoke-ManageStatus -Selected $selected
        Wait-DevboxKey
        continue
    }
    while ($true) {
        $running = @(Get-DevboxContainers -Running $true) -contains $selected
        $actions = @($statusItem)
        if ($running) { $actions += @($addItem, $modifyItem) }
        $actions += @($removeItem)
        $DevboxMenuPath = "Mutagen sessions > $selected"
        $action = Select-DevboxItem -Title "Select what to do with the Mutagen sessions of '$selected':" -Items $actions -Clear -EscapeAction $(if ($Container) { 'exit' } else { 'back' })
        if (-not $action) { break }
        $actionName = ($action -split ' ')[0]
        $DevboxMenuPath = "Mutagen sessions > $selected > $actionName"
        Show-DevboxMenuHeader
        switch ($action) {
            $addItem { Invoke-ManageAdd -Selected $selected }
            $modifyItem { Invoke-ManageModify -Selected $selected }
            $removeItem { Invoke-ManageRemove -Selected $selected }
            $statusItem { Invoke-ManageStatus -Selected $selected }
        }
        Wait-DevboxKey
    }
    if ($Container) { break }
}
exit $exitCode
