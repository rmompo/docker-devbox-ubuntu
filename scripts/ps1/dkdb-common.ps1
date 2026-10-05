# Common definitions for the devbox PowerShell scripts.
# Version: 0.1.1
# Load it with:  . "$PSScriptRoot\dkdb-common.ps1"
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# Prefix shared by every image, container and user name. Change it here only.
$DevboxPrefix = 'dkdb'
# Default name of the image, the container and the user (typed without the prefix): dkdb-devbox-ubuntu.
$DevboxDefaultName = 'devbox-ubuntu'
$DevboxDefaultProjectsPath = 'C:\LocalFiles\proyectos\'

# Optional Mutagen (file sync, spec 08), downloaded on demand by dkdb-container-create.
# It is also the minimum accepted version (0.18.1 fixed the compatibility with Docker Engine 28+).
$DevboxMutagenVersion = '0.18.1'

# --- Version and integrity (spec 01) ---
# <root>\devbox (the installed package) or the repository root: both have the same layout.
function Get-DevboxBase {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

# Project version, read from <root>\devbox\manifest.json (downloaded by install.ps1).
# 'unknown' when the manifest is missing or unreadable.
function Get-DevboxVersion {
    $manifest = Join-Path (Get-DevboxBase) 'manifest.json'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        try {
            $version = (Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json).version
            if ($version) { return [string]$version }
        } catch {
            return 'unknown'
        }
    }
    return 'unknown'
}

# Version of a file: the '# Version: x.y.z' line in its first lines ($null when absent).
function Get-DevboxFileVersion {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $Path -TotalCount 15)) {
        if ($line -match '^#\s*Version:\s*(\d+\.\d+\.\d+)\s*$') { return $Matches[1] }
    }
    return $null
}

# One line with the version of the calling script and of the project; every dkdb-*
# script calls it when it starts: Show-DevboxVersion -Script $PSCommandPath
function Show-DevboxVersion {
    param([string]$Script)
    $package = Get-DevboxVersion
    if (-not $Script) {
        Write-Host "docker-devbox-ubuntu $package" -ForegroundColor DarkGray
        return
    }
    $own = Get-DevboxFileVersion -Path $Script
    if (-not $own) { $own = 'unknown' }
    Write-Host "$([System.IO.Path]::GetFileNameWithoutExtension($Script)) $own (docker-devbox-ubuntu $package)" -ForegroundColor DarkGray
}

# Compare the files under $Base with manifest.json: every listed file must exist and its
# '# Version:' header must equal the manifest entry. Returns Errors (the package is
# inconsistent) and Notes (files under scripts/ or install/ that the manifest does not list).
function Get-DevboxIntegrity {
    param([Parameter(Mandatory)][string]$Base)
    $Base = [System.IO.Path]::GetFullPath($Base).TrimEnd('\', '/')
    $errors = @()
    $notes = @()
    $manifestPath = Join-Path $Base 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return [pscustomobject]@{ Errors = @('manifest.json is missing'); Notes = @(); Checked = 0 }
    }
    try {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{ Errors = @('manifest.json is not valid JSON'); Notes = @(); Checked = 0 }
    }
    if (-not $manifest.files) {
        return [pscustomobject]@{ Errors = @('manifest.json has no files list'); Notes = @(); Checked = 0 }
    }
    $listed = @{}
    foreach ($entry in $manifest.files.PSObject.Properties) {
        $relative = $entry.Name
        $listed[$relative] = $true
        $path = Join-Path $Base ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            # install.ps1 is downloaded by hand: it may legitimately be elsewhere.
            if ($relative -eq 'install/install.ps1') { $notes += "not found (downloaded by hand): $relative" }
            else { $errors += "missing: $relative" }
            continue
        }
        $actual = Get-DevboxFileVersion -Path $path
        if (-not $actual) { $errors += "no '# Version:' header: $relative" }
        elseif ($actual -ne [string]$entry.Value) { $errors += "version $actual in the file, $($entry.Value) in manifest.json: $relative" }
    }
    foreach ($file in (Get-ChildItem -Path (Join-Path $Base 'scripts'), (Join-Path $Base 'install') -Recurse -File -ErrorAction SilentlyContinue)) {
        $relative = ($file.FullName.Substring($Base.Length).TrimStart('\', '/')) -replace '\\', '/'
        if (-not $listed.ContainsKey($relative)) { $notes += "not listed in manifest.json: $relative" }
    }
    return [pscustomobject]@{ Errors = @($errors); Notes = @($notes); Checked = $listed.Count }
}

# Stop when the installed package is inconsistent with manifest.json.
function Assert-DevboxIntegrity {
    $result = Get-DevboxIntegrity -Base (Get-DevboxBase)
    if ($result.Errors.Count -eq 0) { return }
    Write-Host 'Error: the installed package is inconsistent with manifest.json:' -ForegroundColor Red
    foreach ($problem in $result.Errors) { Write-Host "  - $problem" -ForegroundColor Red }
    Write-Host 'Run install.ps1 again (dkdb-verify shows the details).' -ForegroundColor Red
    exit 1
}

# Two versions are compatible when they share major.minor (0.x) or major (1.0 and later).
function Test-DevboxVersionCompatible {
    param([string]$Left, [string]$Right)
    $a = $null
    $b = $null
    if (-not [version]::TryParse($Left, [ref]$a) -or -not [version]::TryParse($Right, [ref]$b)) { return $false }
    if ($a.Major -eq 0 -and $b.Major -eq 0) { return ($a.Minor -eq $b.Minor) }
    return ($a.Major -eq $b.Major)
}

# Highest tag of the image $ImageName (with prefix) compatible with the scripts, as
# name:tag; $null when there is none. Images are tagged with a version, never latest.
function Get-DevboxCompatibleImage {
    param([Parameter(Mandatory)][string]$ImageName)
    $scripts = Get-DevboxVersion
    $best = $null
    foreach ($line in (docker images --format '{{.Repository}}:{{.Tag}}')) {
        $separator = $line.LastIndexOf(':')
        if ($separator -lt 1) { continue }
        if ($line.Substring(0, $separator) -cne $ImageName) { continue }
        $tag = $line.Substring($separator + 1)
        $parsed = $null
        if (-not [version]::TryParse($tag, [ref]$parsed)) { continue }
        if (-not (Test-DevboxVersionCompatible -Left $tag -Right $scripts)) { continue }
        if ($null -eq $best -or $parsed -gt $best) { $best = $parsed }
    }
    if ($null -eq $best) { return $null }
    return "${ImageName}:$best"
}

# Stop when the container was created from an image that is not compatible with the scripts.
function Assert-DevboxContainerVersion {
    param([Parameter(Mandatory)][string]$Container)
    $imageVersion = Get-DevboxContainerEnv -Container $Container -Name 'DEVBOX_VERSION'
    $scripts = Get-DevboxVersion
    if ($imageVersion) { Write-Host "Container image version: $imageVersion" }
    if (-not $imageVersion -or -not (Test-DevboxVersionCompatible -Left $imageVersion -Right $scripts)) {
        $shown = $imageVersion
        if (-not $shown) { $shown = 'unknown' }
        Write-Host "Error: '$Container' was created from an image with version $shown, not compatible with the scripts ($scripts)." -ForegroundColor Red
        Write-Host 'Rebuild the image (dkdb-image-create) and recreate the container. Your data stays reachable with docker: docker start, docker exec -it -u <user> <container> bash, docker cp.' -ForegroundColor Red
        exit 1
    }
}

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
        [Parameter(Mandatory)][string]$Default,
        [string]$DefaultSuffix = ''
    )
    while ($true) {
        # The default is shown with the prefix (and, for images, with its version, for example
        # ':0.1.0'); the typed text never includes either of them.
        $value = Read-Host "$Prompt [$DevboxPrefix-$Default$DefaultSuffix]"
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

# Shared root of the installation (default C:\shared). It is never stored: it is deduced
# from where the scripts are, <root>\devbox\scripts\ps1 (chosen once by install.ps1).
function Get-DevboxRoot {
    $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
    $expected = Join-Path $root 'devbox\scripts\ps1'
    if ($PSScriptRoot.TrimEnd('\') -ine $expected.TrimEnd('\')) {
        Write-Host "Error: the scripts must be in <root>\devbox\scripts\ps1 (found: $PSScriptRoot). Run install.ps1 again." -ForegroundColor Red
        exit 1
    }
    return $root
}

# Default host folder for the shared tools (Maven, JDKs, ...): <root>\tools.
# One installation for every container; mounted in ~/devbox/tools.
function Get-DevboxDefaultToolsPath {
    return (Join-Path (Get-DevboxRoot) 'tools')
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

# Mutagen is installed next to the scripts: <root>\devbox\mutagen (never inside tools,
# which is mounted read/write in the containers).
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

# Version of the installed Mutagen ([version]), or $null when it cannot be read.
function Get-DevboxMutagenVersion {
    $mutagen = Get-DevboxMutagenExe
    if (-not $mutagen) { return $null }
    $text = (& $mutagen version 2>&1 | Out-String)
    if ($text -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return $null
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

# Dkdb- containers (running or stopped) created with the Mutagen volume type.
function Get-DevboxMutagenContainers {
    $names = @()
    foreach ($running in @($true, $false)) {
        foreach ($container in (Get-DevboxContainers -Running $running)) {
            if ((Get-DevboxContainerEnv -Container $container -Name 'DEVBOX_SYNC') -eq 'mutagen') { $names += $container }
        }
    }
    return @($names)
}

# Names of every Mutagen session known by the daemon; $null when they cannot be listed.
function Get-DevboxMutagenSessionNames {
    $mutagen = Get-DevboxMutagenExe
    if (-not $mutagen) { return $null }
    $lines = & $mutagen sync list --template '{{range .}}{{println .Name}}{{end}}'
    if ($LASTEXITCODE -ne 0) { return $null }
    return @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}

# Create the session, or resume it when it already exists. The session is flushed when it
# was just created or when -Flush is given. Returns $true on success; prints the reason
# and returns $false otherwise.
function Start-DevboxSync {
    param(
        [Parameter(Mandatory)][string]$Container,
        [switch]$Flush
    )
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
    $created = $false
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
        $created = $true
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: could not create or resume the Mutagen session '$session'." -ForegroundColor Red
        return $false
    }
    if ($created -or $Flush) {
        Write-Host 'Synchronizing ...'
        & $mutagen sync flush $session | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Warning: the flush failed. Check it with: dkdb-mutagen-status" -ForegroundColor Yellow
        }
    }
    return $true
}

# Terminate one Mutagen session (the host folder is not touched). It never starts the daemon:
# when Mutagen or its daemon is not running, the session is left for dkdb-mutagen-clean.
function Remove-DevboxSyncSession {
    param([string]$SessionName)
    if (-not $SessionName) {
        Write-Host 'Warning: the Mutagen session name is unknown; run dkdb-mutagen-clean to look for leftover sessions.' -ForegroundColor Yellow
        return
    }
    if (-not (Test-DevboxMutagen) -or -not (Test-DevboxMutagenDaemon)) {
        Write-Host "Warning: the Mutagen daemon is not running, so the session '$SessionName' was not terminated. Run dkdb-mutagen-clean later." -ForegroundColor Yellow
        return
    }
    & (Get-DevboxMutagenExe) sync terminate $SessionName *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: could not terminate the Mutagen session '$SessionName'. Run dkdb-mutagen-clean later." -ForegroundColor Yellow
        return
    }
    Write-Host "Mutagen session terminated: $SessionName"
}
