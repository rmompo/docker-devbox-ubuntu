# Open a bash shell, as the container's user, in a running devbox container.
# Version: 0.8.1
# For a Mutagen container it starts the daemon and leaves the sessions as they are (dkdb-mutagen-manage changes them).
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
        -Description 'Opens a bash shell, as the container''s user, in one running devbox container, given with -Container or chosen from a menu. For a container that uses Mutagen it starts the daemon too and leaves the sessions as they are; dkdb-mutagen-manage changes what is synchronized.' `
        -Usage 'dkdb-container-connect [-Container <name>] [-Help] [-Man]' `
        -Parameters @(
            @{ Name = '-Container'; Description = 'Name of the container (with or without the dkdb- prefix); skips the container menu. It must be a running container.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-container-connect'; Description = 'Connects; for a Mutagen container it first makes sure the daemon runs.' },
            @{ Command = 'dkdb-container-connect -Container dkdb-dev'; Description = 'Connects to that container without the menu.' }
        ) `
        -Notes @(
            'The menu comes back after every action (with its list read again) until you press Esc (Up/Down move, Enter selects, Esc goes back); an action that prints something waits for a key before the screen is cleared. With -Container it runs once, without a menu.',
            'For a container that uses Mutagen it starts the daemon and leaves the sessions exactly as they are: nothing is created, resumed, paused or terminated. To choose what is synchronized use dkdb-mutagen-manage.',
            'The shell opens even if the Mutagen check fails.',
            'If the container has no AI client yet, it suggests how to install one.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Opens a bash shell, as the container user, in one running devbox container chosen from a menu.' `
        -Needs @(
            'Docker Engine running and a running dkdb- container.'
        ) `
        -Steps @(
            'Warns, never stops, when the package or the image of the container have another version.',
            'Uses the container given with -Container, or shows the menu of running containers.',
            'If the container uses Mutagen, runs the checks (variables, mutagen, container ID, host path, container ready, active overlaps), starts the Mutagen daemon if needed and lists the registered sessions with their state; the sessions stay as they are (use dkdb-mutagen-manage to change them).',
            'The shell opens even if the Mutagen check fails.',
            'If the container has no AI client yet, suggests how to install one.',
            'Runs docker exec -it as the container user, with TERM=xterm-256color so the prompt shows colors.'
        ) `
        -Changes @(
            'With Mutagen, the daemon may be started; no session is changed.'
        ) `
        -Never @(
            'Is blocked by versions.',
            'Terminates sessions or touches files.'
        ) `
        -Next 'Inside the container, install one AI client (dkdb-install-claudecode.sh or dkdb-install-ghcopilot-cli.sh) if you have none.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity -WarnOnly
Assert-DevboxDocker

$DevboxMenuScript = $PSCommandPath

function Invoke-ConnectAction {
    param([Parameter(Mandatory)][string]$Selected)
    $userName = Get-DevboxContainerUser -Container $Selected
    if (-not $userName) {
        Write-DevboxWarning "Error: '$Selected' has no DEVBOX_USER variable; it was not created by dkdb-container-create."
        Wait-DevboxKey
        Set-DevboxActionResult 1
        return
    }

    # Only warns when the image the container was created from is not compatible with the scripts.
    $null = Test-DevboxContainerVersion -Container $Selected

    # Mutagen container: the daemon is started and the sessions stay as they are (dkdb-mutagen-manage changes them).
    # The shell opens even if this fails.
    if ((Get-DevboxContainerEnv -Container $Selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
        $pick = Invoke-DevboxSyncPick -Container $Selected -KeepOnly
        if (-not $pick.Ok) {
            Write-DevboxWarning 'Opening the shell anyway, but the projects are NOT synchronized.'
        } elseif (-not $pick.Active) {
            Write-DevboxNext 'Next: dkdb-mutagen-manage.ps1 chooses what to synchronize (Add or Modify).'
        }
    } else {
        # No Mutagen: the state file of the container (versions) is refreshed for dkdb-info.sh and dkdb-version.sh.
        $null = Update-DevboxContainerState -Container $Selected
    }

    # Next step: the AI client (one per container) is installed from inside the container.
    docker exec -u $userName $Selected bash -c 'test -e ~/.local/bin/claude || test -e ~/.local/bin/copilot' *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-DevboxNext 'Next: inside the container, install one AI client: bash ~/devbox/bash/dkdb-install-claudecode.sh (Claude Code) or bash ~/devbox/bash/dkdb-install-ghcopilot-cli.sh (GitHub Copilot CLI).'
    }

    # TERM is set explicitly: without it, docker exec may give a plain "xterm" and
    # the default Ubuntu .bashrc then shows no colored prompt.
    docker exec -it -u $userName -w "/home/$userName" -e TERM=xterm-256color -e COLORTERM=truecolor $Selected bash
    # Back from the shell: the menu is shown again (the exit code of the shell is not the one of the script).
    return
}

# NoWait: the shell was the last thing on the screen, so the menu comes back at once.
Invoke-DevboxItemMenu -Path 'Containers > Connect' -Title 'Select the container to connect to:' -Name $Container -NoWait `
    -Kind "a running '$DevboxPrefix-' container" -EmptyMessage "No running containers starting with '$DevboxPrefix-' were found." `
    -GetItems { Get-DevboxContainers -Running $true } -Action { param($item) Invoke-ConnectAction -Selected $item }
exit $script:DevboxItemMenuCode
