# Show how everything is set up and in which state: folders, PATH, Docker, images, containers,
# Version: 0.2.0
# volumes and Mutagen. For the versions, see dkdb-version.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Shows how everything is set up: folders, PATH, Docker, images, containers, volumes and Mutagen.' `
        -Usage 'dkdb-info [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-info'; Description = 'Prints the installation, Docker, containers and Mutagen sessions.' }
        ) `
        -Notes @(
            'For the versions see dkdb-version.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Shows how everything is set up.' `
        -Needs @(
            'Nothing for the first sections; Docker for images and containers.'
        ) `
        -Steps @(
            'Prints the shared root and its folders and the PATH.',
            'Prints Docker.',
            'Lists images and containers with their state, user, volume type and mounts.',
            'Prints the Mutagen daemon and, per container, its sessions with their progress, the overlaps of active sessions and the host folders shared by several containers.'
        ) `
        -Changes @(
            'Nothing: it only reads.'
        ) `
        -Never @(
            'Changes anything.'
        ) `
        -Next 'dkdb-version shows the versions.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath

function Show-InfoPath {
    param([string]$Label, [string]$Path, [string]$Note = '')
    $text = '  {0,-16} {1}' -f $Label, $Path
    if ($Note) { $text += "  ($Note)" }
    if (Test-Path -LiteralPath $Path) { Write-Host $text } else { Write-DevboxWarning ($text + '  [does not exist]') }
}

# --- Installation ---
$devbox = Get-DevboxBase
$root = Split-Path -Parent $devbox
Write-Host ''
Write-Host 'Installation'
Show-InfoPath -Label 'Shared root' -Path $root
Show-InfoPath -Label 'devbox' -Path $devbox
Show-InfoPath -Label 'Scripts (ps1)' -Path (Join-Path $devbox 'scripts\ps1')
Show-InfoPath -Label 'Bash volume' -Path (Join-Path $devbox 'scripts\bash') -Note 'mounted read-only in ~/devbox/bash'
Show-InfoPath -Label 'Tools default' -Path (Join-Path $root 'tools') -Note 'mounted in ~/devbox/tools'
Show-InfoPath -Label 'Projects default' -Path $DevboxDefaultProjectsPath -Note 'mounted or synchronized in ~/devbox/projects'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @()
if ($userPath) { $entries = @($userPath -split ';' | Where-Object { $_ -ne '' } | ForEach-Object { $_.TrimEnd('\') }) }
$ps1Folder = (Join-Path $devbox 'scripts\ps1').TrimEnd('\')
if ($entries -contains $ps1Folder) { Write-Host '  User PATH        contains the scripts folder' }
else { Write-DevboxWarning '  User PATH        does not contain the scripts folder (run install.ps1 again)' }
Write-Host "  Default names    image, container and user: $DevboxPrefix-$DevboxDefaultName"

# --- Docker, images and containers ---
Write-Host ''
Write-Host 'Docker'
$dockerReachable = $false
if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker info *> $null
    if ($LASTEXITCODE -eq 0) { $dockerReachable = $true; Write-Host '  Docker engine    running' }
    else { Write-DevboxWarning '  Docker engine    not reachable (start Docker Desktop)' }
} else {
    Write-DevboxWarning '  Docker           not found in the PATH'
}

$mutagenContainers = @()
if ($dockerReachable) {
    Write-Host ''
    Write-Host "Images (prefix $DevboxPrefix-)"
    $images = @(Get-DevboxImages)
    if ($images.Count -eq 0) { Write-Host '  none (dkdb-image-create builds one)' }
    foreach ($image in $images) { Write-Host "  $image" }

    Write-Host ''
    Write-Host "Containers (prefix $DevboxPrefix-)"
    $running = @(Get-DevboxContainers -Running $true)
    $stopped = @(Get-DevboxContainers -Running $false)
    if (($running.Count + $stopped.Count) -eq 0) { Write-Host '  none (dkdb-container-create creates one)' }
    foreach ($container in ($running + $stopped)) {
        $state = 'stopped'
        if ($running -contains $container) { $state = 'running' }
        $user = Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_USER'
        $sync = Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_SYNC'
        $volume = 'bind mount'
        if ($sync -eq 'mutagen') { $volume = 'Mutagen sync'; $mutagenContainers += $container }
        $line = '  {0} [{1}] user: {2}; projects: {3}' -f $container, $state, $user, $volume
        if ($state -eq 'running') { Write-DevboxSuccess $line } else { Write-Host $line }
        if ($sync -eq 'mutagen') {
            Write-Host ("    projects: {0} <-> ~/devbox/projects (Mutagen)" -f (Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_SYNC_PATH'))
        }
        $mounts = docker inspect --format '{{range .Mounts}}{{.Source}}|{{.Destination}}|{{.RW}}{{println}}{{end}}' $container
        foreach ($mount in @($mounts | Where-Object { $_ })) {
            $parts = $mount -split '\|'
            $mode = 'read/write'
            if ($parts[2] -eq 'false') { $mode = 'read-only' }
            Write-Host ('    {0} -> {1} ({2})' -f $parts[0], $parts[1], $mode)
        }
    }
}

# --- Mutagen ---
Write-Host ''
Write-Host 'Mutagen'
if (-not (Test-DevboxMutagen)) {
    Write-Host '  not installed (optional; dkdb-container-create installs it on demand)'
} else {
    Write-Host "  Executable       $(Get-DevboxMutagenExe)"
    if (-not (Test-DevboxMutagenDaemon)) {
        Write-Host '  Daemon           stopped (dkdb-mutagen-start, dkdb-mutagen-sync, or starting or connecting a Mutagen container, start it)'
    } else {
        Write-DevboxSuccess '  Daemon           running'
        $sessions = @(Get-DevboxMutagenSessions)
        if ($mutagenContainers.Count -eq 0 -and $sessions.Count -eq 0) { Write-Host '  Sessions         none' }
        $byHostFolder = @{}
        foreach ($container in $mutagenContainers) {
            $mine = @(Get-DevboxContainerSyncSessions -Container $container)
            if ($mine.Count -eq 0) { Write-Host "  ${container}: no session yet (dkdb-mutagen-sync creates it)" }
            foreach ($session in $mine) {
                $counts = ''
                if ($null -ne $session.Total -and $session.Total -gt 0) { $counts = ", $($session.Done) of $($session.Total) files" }
                $state = $session.Status
                if ($session.Paused) { $state = "$state (paused)" }
                $text = "  ${container}: $($session.AlphaPath) <-> $($session.BetaPath) [$state$counts]"
                if ($session.LastError -or $session.Conflicts -gt 0) {
                    Write-DevboxWarning "$text [conflicts: $($session.Conflicts); last error: $($session.LastError)]"
                } else {
                    Write-Host $text
                }
                $key = $session.AlphaPath.TrimEnd('\', '/').ToLowerInvariant()
                if (-not $byHostFolder.ContainsKey($key)) { $byHostFolder[$key] = @() }
                $byHostFolder[$key] += $container
            }
            # The sessions of one container must never overlap.
            $null = Show-DevboxSessionOverlaps -Container $container -Sessions $mine
        }
        # Host folders that several containers synchronize (allowed: the host is the common repository).
        $shared = @($byHostFolder.GetEnumerator() | Where-Object { @($_.Value | Select-Object -Unique).Count -gt 1 })
        foreach ($entry in $shared) { Write-Host "  Shared host folder $($entry.Key): $((@($entry.Value | Select-Object -Unique)) -join ', ')" }
    }
}

Write-Host ''
Write-DevboxNext 'Next: dkdb-version shows every version; dkdb-mutagen-status shows the details of a session.'
