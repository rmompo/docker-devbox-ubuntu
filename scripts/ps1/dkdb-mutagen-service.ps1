# Control the Mutagen service: start or stop the daemon, see its state, clean the orphan sessions.
# Version: 0.1.0
# One menu of actions. It acts on Mutagen as a whole (one daemon per user), not on a container: the sessions of a
# container are managed with dkdb-mutagen-manage. dkdb-container-start and dkdb-container-connect already start
# the daemon for a Mutagen container.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Controls the Mutagen service from a menu of actions: start the daemon, stop it, show its state, or terminate the orphan sessions (those whose container no longer exists). It acts on Mutagen as a whole, not on one container; the sessions of a container are managed with dkdb-mutagen-manage.' `
        -Usage 'dkdb-mutagen-service [-Help] [-Man]' `
        -Examples @(
            @{ Command = 'dkdb-mutagen-service'; Description = 'Shows the menu: Start, Stop, State or Clean (orphan sessions).' }
        ) `
        -Notes @(
            'Start checks the daemon and starts it if it is not running. dkdb-container-start and dkdb-container-connect start it by themselves for a container that uses Mutagen.',
            'Stop flushes the running Mutagen containers and stops the daemon. There is one daemon per user: it stops ALL your Mutagen sessions, not only the dkdb- ones; they are kept and come back when the daemon starts.',
            'State shows the Mutagen executable and version, whether the daemon is running and how many sessions it has.',
            'Clean lists the sessions whose container (the docker endpoint of the session) no longer exists and terminates the ones you choose, after asking. Sessions of folders of a living container are not leftovers; the host folders are not touched.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Controls the Mutagen service (the daemon of your user) and cleans the leftover sessions.' `
        -Needs @(
            'mutagen.exe (dkdb-container-create installs it on demand). Clean also needs Docker Engine running and the daemon running.'
        ) `
        -Steps @(
            'Shows the menu of actions: Start the daemon, Stop the daemon, State of the daemon or Clean orphan sessions.',
            'Start: if the daemon is running says so and stops; otherwise starts it and waits for it (it can take a few seconds).',
            'Stop: if the daemon is stopped says so and stops; otherwise flushes the pending changes of the running Mutagen containers, stops the daemon, checks that it is stopped and refreshes the state file of those containers.',
            'State: prints the executable, the version (against the minimum) and whether the daemon is running, with its number of sessions.',
            'Clean: lists all the Mutagen sessions; an orphan is a session whose container endpoint points to a Docker container that does not exist (any session name; a dkdb- session without a readable endpoint is one when it matches no container). Shows the orphans in a menu, with an option for all of them, asks [y/N] and terminates the chosen ones.'
        ) `
        -Changes @(
            'Start: the daemon of your user is running.',
            'Stop: the daemon and all its sessions are stopped (the sessions are kept).',
            'Clean: the chosen orphan sessions are terminated.'
        ) `
        -Never @(
            'Creates, resumes or pauses sessions of a container (that is dkdb-mutagen-manage).',
            'Touches the host folders or the sessions of living containers.'
        ) `
        -Next 'dkdb-mutagen-manage.ps1 lets you choose what to synchronize.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity -WarnOnly

if (-not (Test-DevboxMutagen)) {
    Write-DevboxWarning 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).'
    exit 1
}

# True when Docker answers (Stop and Clean use it, but Start and State do not need it).
function Test-ServiceDocker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
    docker info *> $null
    return ($LASTEXITCODE -eq 0)
}

function Invoke-ServiceStart {
    if (Test-DevboxMutagenDaemon) {
        Write-Host 'The Mutagen daemon is already running.'
        return
    }
    if (Start-DevboxMutagenDaemon) {
        Write-DevboxSuccess 'The Mutagen daemon is running.'
        Write-DevboxNext 'Next: dkdb-mutagen-manage.ps1 lets you choose what to synchronize.'
    } else {
        Write-DevboxWarning 'Error: the Mutagen daemon could not be started.'
        exit 1
    }
}

function Invoke-ServiceStop {
    if (-not (Test-DevboxMutagenDaemon)) {
        Write-Host 'The Mutagen daemon is already stopped.'
        return
    }
    $mutagen = Get-DevboxMutagenExe
    $docker = Test-ServiceDocker
    # Flush the pending changes of the running Mutagen containers before stopping.
    if ($docker) {
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
    & $mutagen daemon stop | Out-Null
    if (Test-DevboxMutagenDaemon) {
        Write-DevboxWarning 'Error: the Mutagen daemon is still running.'
        exit 1
    }
    Write-DevboxSuccess 'The Mutagen daemon is stopped.'
    if ($docker) {
        foreach ($container in (Get-DevboxContainers -Running $true)) {
            if ((Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_SYNC') -eq 'mutagen') { $null = Update-DevboxContainerState -Container $container }
        }
    }
    Write-DevboxNext 'Next: nothing is synchronized until you run dkdb-mutagen-manage.ps1 (modify) or choose it in the menu of dkdb-container-start.ps1 or dkdb-container-connect.ps1.'
}

function Invoke-ServiceState {
    $version = Get-DevboxMutagenVersion
    if ($version) { Write-Host "Mutagen $version" } else { Write-Host 'Mutagen (version unknown)' }
    Write-Host 'Executable: ' -NoNewline
    Write-Host (Get-DevboxMutagenExe) -ForegroundColor $DevboxHostColor
    if (Test-DevboxMutagenDaemon) {
        Write-Host 'Daemon: ' -NoNewline
        Write-Host 'running' -ForegroundColor $DevboxRunningColor
        $count = @(Get-DevboxMutagenSessions).Count
        Write-Host "Sessions: $count (every Mutagen session of your user, not only the dkdb- ones)"
        Write-DevboxNext 'Next: dkdb-mutagen-manage.ps1 shows and changes the sessions of a container.'
    } else {
        Write-Host 'Daemon: ' -NoNewline
        Write-Host 'stopped' -ForegroundColor $DevboxStoppedColor
        Write-DevboxNext 'Next: start it with this script (Start), or with dkdb-container-start.ps1 or dkdb-container-connect.ps1 for a Mutagen container.'
    }
}

function Invoke-ServiceClean {
    Assert-DevboxDocker
    if (-not (Test-DevboxMutagenDaemon)) {
        Write-Host 'The Mutagen daemon is stopped: nothing to clean (start it with the Start action of this script).'
        return
    }
    $allSessions = @(Get-DevboxMutagenSessions)
    if ($allSessions.Count -eq 0) {
        Write-Host 'There are no Mutagen sessions: nothing to clean.'
        return
    }
    # An orphan is a session whose beta points to a Docker container that no longer exists, whatever its
    # name (it works even when no container exists at all, running or stopped).
    $refs = @(Get-DevboxAllContainerRefs)
    $alive = @(Get-DevboxMutagenContainers | ForEach-Object { Get-DevboxSyncSessionName -Container $_ } | Where-Object { $_ })
    $orphans = @($allSessions | Where-Object { Test-DevboxSessionOrphan -Session $_ -ContainerRefs $refs -AliveMainSessions $alive })
    if ($orphans.Count -eq 0) {
        Write-Host 'No orphan Mutagen sessions were found.'
        return
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
        return
    }
    $targets = @($labels.Values | Sort-Object)
    if ($selected -ne $allItem) { $targets = @($labels[$selected]) }

    Write-Host 'Sessions to terminate:'
    $targets | ForEach-Object { Write-Host "  $_" }
    $answer = Read-Host 'Terminate them? The host folders are not touched. [y/N]'
    if ($answer -notmatch '^[yY]$') {
        Write-Host 'Cancelled.'
        return
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
    Write-DevboxNext 'Next: dkdb-mutagen-manage.ps1 (status) checks the remaining sessions.'
}

$startItem = 'Start the daemon'
$stopItem = 'Stop the daemon'
$stateItem = 'State of the daemon'
$cleanItem = 'Clean orphan sessions'
$action = Select-DevboxItem -Title 'Select what to do with the Mutagen service:' -Items @($stateItem, $startItem, $stopItem, $cleanItem)
if (-not $action) {
    Write-Host 'Cancelled.'
    exit 0
}
switch ($action) {
    $startItem { Invoke-ServiceStart }
    $stopItem { Invoke-ServiceStop }
    $stateItem { Invoke-ServiceState }
    $cleanItem { Invoke-ServiceClean }
}
