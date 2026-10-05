# Common definitions for the devbox PowerShell scripts.
# Load it with:  . "$PSScriptRoot\dkdb-common.ps1"
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# Prefix shared by every image, container and user name. Change it here only.
$DevboxPrefix = 'dkdb'
$DevboxDefaultName = 'ubuntu'
$DevboxDefaultProjectsPath = 'C:\Localfiles\proyectos\'
# Shared tools (Maven, JDKs, ...): one installation for every container.
$DevboxDefaultResourcesPath = 'C:\shared\'

# Optional Mutagen (file sync, spec 08), downloaded on demand by dkdb-container-create.
$DevboxMutagenVersion = '0.18.1'

# Linux limits user names to 32 characters; the prefix and the hyphen use some.
$DevboxMaxInputLength = 32 - ($DevboxPrefix.Length + 1)

function Assert-DevboxDocker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host 'Error: docker was not found in the PATH.' -ForegroundColor Red
        exit 1
    }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Error: the Docker daemon is not reachable. Is Docker Desktop running?' -ForegroundColor Red
        exit 1
    }
}

function Get-DevboxFullName {
    param([Parameter(Mandatory)][string]$Name)
    return "$DevboxPrefix-$Name"
}

# Ask for a name, using a default; returns the validated text (without prefix).
function Read-DevboxName {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Default
    )
    while ($true) {
        # The default is shown with the prefix; the typed text never includes it.
        $value = Read-Host "$Prompt [$DevboxPrefix-$Default]"
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        $value = $value.Trim()
        if ($value -cnotmatch '^[a-z][a-z0-9_-]*$') {
            Write-Host 'Use lowercase letters, digits, "-" or "_", starting with a letter.' -ForegroundColor Yellow
            continue
        }
        if ($value.Length -gt $DevboxMaxInputLength) {
            Write-Host "Maximum $DevboxMaxInputLength characters (the prefix '$DevboxPrefix-' is added)." -ForegroundColor Yellow
            continue
        }
        return $value
    }
}

# Interactive menu: Up/Down to move, Enter to select, Esc to cancel.
# Returns the selected item, or $null when cancelled or when there are no items.
function Select-DevboxItem {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string[]]$Items
    )
    if (-not $Items -or $Items.Count -eq 0) { return $null }
    if ([Console]::IsInputRedirected) {
        throw 'Select-DevboxItem needs an interactive console.'
    }

    Write-Host $Title
    Write-Host '(Up/Down: move, Enter: select, Esc: cancel)' -ForegroundColor DarkGray
    foreach ($item in $Items) { Write-Host '' }
    $top = [Console]::CursorTop - $Items.Count
    $width = [Console]::WindowWidth - 1
    $index = 0
    $previousCursor = [Console]::CursorVisible
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            for ($i = 0; $i -lt $Items.Count; $i++) {
                [Console]::SetCursorPosition(0, $top + $i)
                if ($i -eq $index) {
                    Write-Host ('> ' + $Items[$i]).PadRight($width) -NoNewline -ForegroundColor Cyan
                } else {
                    Write-Host ('  ' + $Items[$i]).PadRight($width) -NoNewline
                }
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { if ($index -gt 0) { $index-- } }
                'DownArrow' { if ($index -lt $Items.Count - 1) { $index++ } }
                'Enter'     { [Console]::SetCursorPosition(0, $top + $Items.Count); return $Items[$index] }
                'Escape'    { [Console]::SetCursorPosition(0, $top + $Items.Count); return $null }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $previousCursor
    }
}

# Images whose repository name starts with "<prefix>-" (format: name:tag).
function Get-DevboxImages {
    $lines = docker images --format '{{.Repository}}:{{.Tag}}'
    return @($lines | Where-Object { $_ -like "$DevboxPrefix-*" })
}

# Containers whose name starts with "<prefix>-", filtered by running state.
function Get-DevboxContainers {
    param([Parameter(Mandatory)][bool]$Running)
    $lines = docker ps -a --format '{{.Names}}|{{.State}}'
    $names = foreach ($line in $lines) {
        $parts = $line -split '\|'
        if ($parts[0] -like "$DevboxPrefix-*") {
            $isRunning = ($parts[1] -eq 'running')
            if ($isRunning -eq $Running) { $parts[0] }
        }
    }
    return @($names)
}

# Read an environment variable stored in a container (DEVBOX_USER, DEVBOX_SYNC, ...).
function Get-DevboxContainerEnv {
    param(
        [Parameter(Mandatory)][string]$Container,
        [Parameter(Mandatory)][string]$Name
    )
    $envLines = docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $Container
    foreach ($line in $envLines) {
        if ($line -like "$Name=*") { return $line.Substring($Name.Length + 1) }
    }
    return $null
}

# Read the user configured for a container (stored in the DEVBOX_USER variable).
function Get-DevboxContainerUser {
    param([Parameter(Mandatory)][string]$Container)
    return Get-DevboxContainerEnv -Container $Container -Name 'DEVBOX_USER'
}

# Host folder with the AI client installers (scripts\bash next to scripts\ps1).
# It is bind-mounted read-only into the container; nothing is copied.
function Get-DevboxBashPath {
    $path = Join-Path $PSScriptRoot '..\bash'
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Write-Host "Error: bash folder not found: $path" -ForegroundColor Red
        exit 1
    }
    return (Resolve-Path -LiteralPath $path).Path
}

# --- Mutagen sync (optional; spec 08) ---
# The session is named like the container. Everything is synchronized, .git
# included (VCS folders are not ignored); only symbolic links are ignored.
$DevboxSyncModeBind = 'Docker bind mount (traditional)'
$DevboxSyncModeMutagen = 'Mutagen sync (copy inside the container, faster)'

# Mutagen is installed next to the scripts: <install path>\mutagen.
function Get-DevboxMutagenDir {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\mutagen'))
}

# Path of mutagen.exe: the PATH first, then the folder used by Install-DevboxMutagen.
# Returns $null when it is not installed.
function Get-DevboxMutagenExe {
    $command = Get-Command mutagen -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $local = Join-Path (Get-DevboxMutagenDir) 'mutagen.exe'
    if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }
    return $null
}

function Test-DevboxMutagen {
    return [bool](Get-DevboxMutagenExe)
}

# Add a folder to the user PATH (registry) and to this session, without duplicates.
function Add-DevboxUserPath {
    param([Parameter(Mandatory)][string]$Folder)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if (-not [string]::IsNullOrEmpty($userPath)) {
        $entries = @($userPath -split ';' | Where-Object { $_ -ne '' })
    }
    if (-not ($entries | Where-Object { $_.TrimEnd('\') -ieq $Folder.TrimEnd('\') })) {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $Folder) -join ';'), 'User')
        Write-Host "Added to the user PATH: $Folder (open a new terminal to use it by hand)"
    }
    $sessionEntries = @($env:Path -split ';' | Where-Object { $_ -ne '' })
    if (-not ($sessionEntries | Where-Object { $_.TrimEnd('\') -ieq $Folder.TrimEnd('\') })) {
        $env:Path = "$env:Path;$Folder"
    }
}

# Ask and install Mutagen (official release, checksum verified) into Get-DevboxMutagenDir.
# Returns $true when Mutagen is available afterwards, $false when declined or failed.
function Install-DevboxMutagen {
    Write-Host ''
    Write-Host "Mutagen $DevboxMutagenVersion is not installed." -ForegroundColor Cyan
    Write-Host 'It synchronizes the projects folder with a copy inside the container, avoiding the slow' -ForegroundColor Cyan
    Write-Host 'Docker Desktop mounts. Download: about 100 MB from github.com/mutagen-io/mutagen.' -ForegroundColor Cyan
    Write-Host 'License: MIT, plus SSPL for part of the official builds; it is a separate third-party tool (spec 08).' -ForegroundColor Cyan
    $answer = Read-Host 'Download and install it? [y/N]'
    if ($answer.Trim() -notmatch '^(y|yes)$') { return $false }

    $tag = "v$DevboxMutagenVersion"
    $asset = "mutagen_windows_amd64_$tag.zip"
    $releaseUrl = "https://github.com/mutagen-io/mutagen/releases/download/$tag"
    $target = Get-DevboxMutagenDir
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "devbox-mutagen-$([guid]::NewGuid().ToString('N'))"
    $previousProgress = $ProgressPreference
    try {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $zip = Join-Path $tempDir $asset
        Write-Host "Downloading $asset ..."
        $ProgressPreference = 'SilentlyContinue'  # much faster in Windows PowerShell 5.1
        Invoke-WebRequest -UseBasicParsing -Uri "$releaseUrl/$asset" -OutFile $zip
        $sums = Join-Path $tempDir 'SHA256SUMS'
        Invoke-WebRequest -UseBasicParsing -Uri "$releaseUrl/SHA256SUMS" -OutFile $sums
        $expected = $null
        foreach ($line in (Get-Content -LiteralPath $sums)) {
            if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$' -and $Matches[2].Trim() -eq $asset) { $expected = $Matches[1] }
        }
        if (-not $expected) { throw "no checksum found for $asset in SHA256SUMS" }
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if ($actual -ine $expected) { throw "checksum mismatch for $asset (expected $expected, got $actual)" }
        Write-Host 'Checksum OK.'
        if (-not (Test-Path -LiteralPath $target -PathType Container)) {
            New-Item -ItemType Directory -Path $target | Out-Null
        }
        Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
    } catch {
        Write-Host "Error: could not install Mutagen ($($_.Exception.Message))." -ForegroundColor Red
        return $false
    } finally {
        $ProgressPreference = $previousProgress
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'mutagen.exe') -PathType Leaf)) {
        Write-Host "Error: mutagen.exe was not found after extracting into $target" -ForegroundColor Red
        return $false
    }
    Add-DevboxUserPath -Folder $target
    Write-Host "Mutagen installed in $target" -ForegroundColor Green
    return $true
}

# Is the Mutagen daemon running? Autostart is disabled for the check, otherwise any
# mutagen command would start the daemon and the answer would always be yes.
function Test-DevboxMutagenDaemon {
    $mutagen = Get-DevboxMutagenExe
    if (-not $mutagen) { return $false }
    $previous = $env:MUTAGEN_DISABLE_AUTOSTART
    $env:MUTAGEN_DISABLE_AUTOSTART = '1'
    try {
        & $mutagen sync list *> $null
        return ($LASTEXITCODE -eq 0)
    } finally {
        if ($null -eq $previous) { Remove-Item Env:MUTAGEN_DISABLE_AUTOSTART -ErrorAction SilentlyContinue }
        else { $env:MUTAGEN_DISABLE_AUTOSTART = $previous }
    }
}

# Make sure the daemon is running: nothing to do when it is, start it otherwise.
function Start-DevboxMutagenDaemon {
    if (Test-DevboxMutagenDaemon) { return $true }
    $mutagen = Get-DevboxMutagenExe
    if (-not $mutagen) { return $false }
    Write-Host 'Starting the Mutagen daemon ...'
    & $mutagen daemon start | Out-Null
    return (Test-DevboxMutagenDaemon)
}

# Wait until the container entrypoint has created the user (marker file in /dev/shm,
# a tmpfs that Docker recreates at every container start).
function Wait-DevboxContainerReady {
    param(
        [Parameter(Mandatory)][string]$Container,
        [int]$TimeoutSeconds = 60
    )
    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        docker exec $Container test -f /dev/shm/devbox-ready *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

# Full ID of a container ($null when it cannot be read).
function Get-DevboxContainerId {
    param([Parameter(Mandatory)][string]$Container)
    $id = (docker inspect --format '{{.Id}}' $Container)
    if ($LASTEXITCODE -ne 0 -or -not $id) { return $null }
    return $id
}

# Mutagen session name of a container: <container>-<first 12 characters of its ID>.
# Single place for the naming rule (see Start-DevboxSync). $null when the ID is unknown.
function Get-DevboxSyncSessionName {
    param([Parameter(Mandatory)][string]$Container)
    $id = Get-DevboxContainerId -Container $Container
    if (-not $id) { return $null }
    return "$Container-$($id.Substring(0, 12))"
}

# Create the session, or resume it when it already exists, then flush it.
# Returns $true on success; prints the reason and returns $false otherwise.
function Start-DevboxSync {
    param([Parameter(Mandatory)][string]$Container)
    $user = Get-DevboxContainerUser -Container $Container
    $hostPath = Get-DevboxContainerEnv -Container $Container -Name 'DEVBOX_SYNC_PATH'
    # The session and its docker endpoint use the container ID, not the name: a recreated
    # container with the same name must not reuse a leftover session (its root would
    # look emptied and Mutagen would halt). Leftover sessions are never touched here.
    $containerId = Get-DevboxContainerId -Container $Container
    if (-not $containerId) {
        Write-Host "Error: could not read the ID of '$Container'." -ForegroundColor Red
        return $false
    }
    $session = Get-DevboxSyncSessionName -Container $Container
    if (-not $user -or -not $hostPath) {
        Write-Host "Error: '$Container' has no DEVBOX_USER or DEVBOX_SYNC_PATH variable." -ForegroundColor Red
        return $false
    }
    if (-not (Test-DevboxMutagen)) {
        Write-Host 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).' -ForegroundColor Red
        return $false
    }
    if (-not (Test-Path -LiteralPath $hostPath -PathType Container)) {
        Write-Host "Error: the host projects path does not exist: $hostPath" -ForegroundColor Red
        return $false
    }
    if (-not (Wait-DevboxContainerReady -Container $Container)) {
        Write-Host "Error: the container '$Container' did not become ready in time." -ForegroundColor Red
        return $false
    }
    $mutagen = Get-DevboxMutagenExe
    if (-not (Start-DevboxMutagenDaemon)) {
        Write-Host 'Error: the Mutagen daemon could not be started.' -ForegroundColor Red
        return $false
    }
    & $mutagen sync list $session *> $null
    if ($LASTEXITCODE -eq 0) {
        & $mutagen sync resume $session | Out-Null
    } else {
        $syncArgs = @(
            'sync', 'create',
            '--name', $session,
            '--sync-mode', 'two-way-safe',
            '--no-ignore-vcs',
            '--symlink-mode', 'ignore',
            '--default-file-mode', '0644',
            '--default-directory-mode', '0755',
            '--default-owner-beta', $user,
            '--default-group-beta', $user,
            $hostPath,
            "docker://$user@$containerId/home/$user/devbox/projects"
        )
        & $mutagen @syncArgs | Out-Null
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: could not create or resume the Mutagen session '$session'." -ForegroundColor Red
        return $false
    }
    Write-Host 'Synchronizing (first flush) ...'
    & $mutagen sync flush $session | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: the first flush failed. Check it with: mutagen sync list $session" -ForegroundColor Yellow
    }
    return $true
}
