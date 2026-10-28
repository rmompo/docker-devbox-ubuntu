# Show how everything is set up and in which state: folders, PATH, Docker, images, containers,
# Version: 0.4.0
# volumes, published ports and Mutagen. For the versions, see dkdb-version.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Shows how everything is set up: folders, PATH, Docker, images, containers, volumes, published ports and Mutagen.' `
        -Usage 'dkdb-info [-Help] [-Man]' `
        -Examples @(
            @{ Command = 'dkdb-info'; Description = 'Prints the installation, Docker, containers (with their published ports) and Mutagen sessions.' }
        ) `
        -Notes @(
            'For the versions see dkdb-version.',
            'Layout: SECTIONS in capitals, PROPERTIES in capitals followed by dots up to the values, and the values wrapped to the width of the console. Host paths are cyan and container paths magenta, as in the rest of the scripts. Special words are shown in reverse video: MUTAGEN (red), MUTAGEN-SYNC (yellow), VOLUME-P9 (red, a Docker bind mount), READ-ONLY (green) and READ-WRITE (red). [running] is green and [stopped] red.'
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
            'Lists images and containers with their state, user, volume type, mounts and published ports (host ip:port -> container port).',
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

# Short names for the pieces of a value (the colors are the ones of the rest of the scripts: host cyan,
# container magenta).
function Get-InfoHost { param([string]$Text) New-DevboxInfoText $Text $DevboxHostColor }
function Get-InfoContainer { param([string]$Text) New-DevboxInfoText $Text $DevboxContainerColor }
function Get-InfoPlain { param([string]$Text) New-DevboxInfoText $Text $null }
function Get-InfoModeBadge {
    param([bool]$ReadOnly)
    if ($ReadOnly) { return (New-DevboxInfoBadge 'READ-ONLY' 'Green') }
    return (New-DevboxInfoBadge 'READ-WRITE' 'Red')
}

# A host folder, optionally with the container folder it is mounted at and its mode; red note when it is missing.
function Show-InfoPath {
    param([string]$Label, [string]$Path, [string]$Target = '', [object]$Mode = $null, [int]$LabelWidth = 16)
    $value = @((Get-InfoHost $Path))
    if ($Target) { $value += @((Get-InfoPlain ' -> '), (Get-InfoContainer $Target)) }
    if ($null -ne $Mode) { $value += @((Get-InfoModeBadge -ReadOnly $Mode)) }
    if (-not (Test-Path -LiteralPath $Path)) { $value += @((New-DevboxInfoText ' [does not exist]' 'Red')) }
    Write-DevboxInfoField -Label $Label -Value $value -LabelWidth $LabelWidth
}

function Show-InfoText {
    param([string]$Label, [string]$Text, [string]$Color, [int]$LabelWidth = 16, [int]$Indent = 2)
    Write-DevboxInfoField -Label $Label -Value @((New-DevboxInfoText $Text $Color)) -LabelWidth $LabelWidth -Indent $Indent
}

# --- Installation ---
$devbox = Get-DevboxBase
$root = Split-Path -Parent $devbox
Write-DevboxInfoSection -Title 'Installation'
Show-InfoPath -Label 'Shared root' -Path $root
Show-InfoPath -Label 'devbox' -Path $devbox
Show-InfoPath -Label 'Scripts (ps1)' -Path (Join-Path $devbox 'scripts\ps1')
Show-InfoPath -Label 'Bash volume' -Path (Join-Path $devbox 'scripts\bash') -Target '~/devbox/bash' -Mode $true
Show-InfoPath -Label 'Tools default' -Path (Join-Path $root 'tools') -Target '~/devbox/tools' -Mode $false
Show-InfoPath -Label 'Projects default' -Path $DevboxDefaultProjectsPath -Target '~/devbox/projects'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @()
if ($userPath) { $entries = @($userPath -split ';' | Where-Object { $_ -ne '' } | ForEach-Object { $_.TrimEnd('\') }) }
$ps1Folder = (Join-Path $devbox 'scripts\ps1').TrimEnd('\')
if ($entries -contains $ps1Folder) { Show-InfoText -Label 'User PATH' -Text 'contains the scripts folder' }
else { Show-InfoText -Label 'User PATH' -Text 'does not contain the scripts folder (run install.ps1 again)' -Color 'Red' }
Show-InfoText -Label 'Default names' -Text "image, container and user: $DevboxPrefix-$DevboxDefaultName"

# --- Docker, images and containers ---
Write-DevboxInfoSection -Title 'Docker'
$dockerReachable = $false
if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker info *> $null
    if ($LASTEXITCODE -eq 0) { $dockerReachable = $true; Show-InfoText -Label 'Engine' -Text 'running' -Color 'Green' -LabelWidth 6 }
    else { Show-InfoText -Label 'Engine' -Text 'not reachable (start Docker Desktop)' -Color 'Red' -LabelWidth 6 }
} else {
    Show-InfoText -Label 'Engine' -Text 'docker was not found in the PATH' -Color 'Red' -LabelWidth 6
}

$mutagenContainers = @()
if ($dockerReachable) {
    Write-DevboxInfoSection -Title 'Images' -Note "(prefix $DevboxPrefix-)"
    $images = @(Get-DevboxImages)
    if ($images.Count -eq 0) { Show-InfoText -Label 'Image' -Text 'none (dkdb-image-create builds one)' -LabelWidth 5 }
    foreach ($image in $images) { Show-InfoText -Label 'Image' -Text $image -LabelWidth 5 }

    Write-DevboxInfoSection -Title 'Containers' -Note "(prefix $DevboxPrefix-)"
    $running = @(Get-DevboxContainers -Running $true)
    $stopped = @(Get-DevboxContainers -Running $false)
    if (($running.Count + $stopped.Count) -eq 0) { Write-Host '  none (dkdb-container-create creates one)' }
    foreach ($container in ($running + $stopped)) {
        $isRunning = ($running -contains $container)
        $user = Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_USER'
        $sync = Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_SYNC'
        Write-Host "  $container " -NoNewline
        if ($isRunning) { Write-DevboxColored -Text '[running]' -Color 'Green' } else { Write-DevboxColored -Text '[stopped]' -Color 'Red' }
        Write-Host ''
        Show-InfoText -Label 'User' -Text $user -LabelWidth 8 -Indent 4
        if ($sync -eq 'mutagen') {
            $mutagenContainers += $container
            Write-DevboxInfoField -Label 'Volume' -Value @((New-DevboxInfoBadge 'MUTAGEN-SYNC' 'Yellow')) -LabelWidth 8 -Indent 4
            Write-DevboxInfoField -Label 'Projects' -LabelWidth 8 -Indent 4 -Value @(
                (Get-InfoHost (Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_SYNC_PATH')),
                (Get-InfoPlain ' <-> '), (Get-InfoContainer '~/devbox/projects'), (New-DevboxInfoBadge 'MUTAGEN' 'Red'))
        } else {
            Write-DevboxInfoField -Label 'Volume' -Value @((New-DevboxInfoBadge 'VOLUME-P9' 'Red')) -LabelWidth 8 -Indent 4
        }
        $mounts = docker inspect --format '{{range .Mounts}}{{.Source}}|{{.Destination}}|{{.RW}}{{println}}{{end}}' $container
        foreach ($mount in @($mounts | Where-Object { $_ })) {
            $parts = $mount -split '\|'
            Write-DevboxInfoField -Label 'Mount' -LabelWidth 8 -Indent 4 -Value @(
                (Get-InfoHost $parts[0]), (Get-InfoPlain ' -> '), (Get-InfoContainer $parts[1]), (Get-InfoModeBadge -ReadOnly ($parts[2] -eq 'false')))
        }
        # Published ports (spec 09): fixed when the container was created.
        $published = @(Get-DevboxContainerPorts -Container $container)
        if ($published.Count -eq 0) { Show-InfoText -Label 'Ports' -Text 'none published' -LabelWidth 8 -Indent 4 }
        foreach ($port in $published) {
            Write-DevboxInfoField -Label 'Port' -LabelWidth 8 -Indent 4 -Value @(
                (Get-InfoHost ('{0}:{1}' -f $port.BindIp, $port.HostPort)), (Get-InfoPlain ' -> '), (Get-InfoContainer ('{0}/{1}' -f $port.ContainerPort, $port.Protocol)))
        }
    }
}

# --- Mutagen ---
Write-DevboxInfoSection -Title 'Mutagen'
if (-not (Test-DevboxMutagen)) {
    Write-Host '  not installed (optional; dkdb-container-create installs it on demand)'
} else {
    Write-DevboxInfoField -Label 'Executable' -Value @((Get-InfoHost (Get-DevboxMutagenExe))) -LabelWidth 10
    if (-not (Test-DevboxMutagenDaemon)) {
        Show-InfoText -Label 'Daemon' -Text 'stopped (dkdb-mutagen-start, dkdb-mutagen-sync, or starting or connecting a Mutagen container, start it)' -Color 'Red' -LabelWidth 10
    } else {
        Show-InfoText -Label 'Daemon' -Text 'running' -Color 'Green' -LabelWidth 10
        $sessions = @(Get-DevboxMutagenSessions)
        if ($mutagenContainers.Count -eq 0 -and $sessions.Count -eq 0) { Show-InfoText -Label 'Sessions' -Text 'none' -LabelWidth 10 }
        $byHostFolder = @{}
        foreach ($container in $mutagenContainers) {
            $mine = @(Get-DevboxContainerSyncSessions -Container $container)
            Write-Host "  $container"
            if ($mine.Count -eq 0) { Show-InfoText -Label 'Session' -Text 'none yet (dkdb-mutagen-sync creates it)' -LabelWidth 10 -Indent 4 }
            foreach ($session in $mine) {
                $counts = ''
                if ($null -ne $session.Total -and $session.Total -gt 0) { $counts = ", $($session.Done) of $($session.Total) files" }
                $state = $session.Status
                if ($session.Paused) { $state = "$state (paused)" }
                $value = @((Get-InfoHost $session.AlphaPath), (Get-InfoPlain ' <-> '), (Get-InfoContainer $session.BetaPath), (Get-InfoPlain " [$state$counts]"))
                if ($session.LastError -or $session.Conflicts -gt 0) {
                    $value += @((New-DevboxInfoText " [conflicts: $($session.Conflicts); last error: $($session.LastError)]" 'Red'))
                }
                Write-DevboxInfoField -Label 'Session' -Value $value -LabelWidth 10 -Indent 4
                $key = $session.AlphaPath.TrimEnd('\', '/').ToLowerInvariant()
                if (-not $byHostFolder.ContainsKey($key)) { $byHostFolder[$key] = @() }
                $byHostFolder[$key] += $container
            }
            # The sessions of one container must never overlap.
            $null = Show-DevboxSessionOverlaps -Container $container -Sessions $mine
        }
        # Host folders that several containers synchronize (allowed: the host is the common repository).
        $shared = @($byHostFolder.GetEnumerator() | Where-Object { @($_.Value | Select-Object -Unique).Count -gt 1 })
        foreach ($entry in $shared) {
            Write-DevboxInfoField -Label 'Shared' -LabelWidth 10 -Value @((Get-InfoHost $entry.Key), (Get-InfoPlain ": $((@($entry.Value | Select-Object -Unique)) -join ', ')"))
        }
    }
}

Write-Host ''
Write-DevboxNext 'Next: dkdb-version shows every version; dkdb-mutagen-status shows the details of a session.'
