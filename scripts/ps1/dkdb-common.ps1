# Common definitions for the devbox PowerShell scripts.
# Version: 0.3.0
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

# --- Help (-Help): one layout for every script (spec 01) ---
# Words of $Text wrapped in lines of at most $Width characters.
function Get-DevboxWrappedLines {
    param([string]$Text, [int]$Width)
    $lines = @()
    $line = ''
    foreach ($word in ($Text -split '\s+' | Where-Object { $_ })) {
        if ($line -and (($line.Length + 1 + $word.Length) -gt $Width)) { $lines += $line; $line = $word }
        elseif ($line) { $line = "$line $word" }
        else { $line = $word }
    }
    if ($line) { $lines += $line }
    return $lines
}

# Print the help of a script: NAME, DESCRIPTION, USAGE, PARAMETERS, EXAMPLES and NOTES. Headings in
# cyan, names, usage and example commands in green, the text in the default color; columns aligned.
# Parameters: @{ Name = '-Help'; Description = '...' }; Examples: @{ Command = '...'; Description = '...' }.
function Show-DevboxHelp {
    param(
        [string]$Name = '',
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Usage,
        [object[]]$Parameters = @(),
        [object[]]$Examples = @(),
        [string[]]$Notes = @(),
        [string]$Script = ''
    )
    $width = 100
    try {
        $window = $Host.UI.RawUI.WindowSize.Width
        if ($window -ge 60) { $width = [math]::Min($window - 1, 110) }
    } catch { $width = 100 }
    if (-not $Name -and $Script) { $Name = [System.IO.Path]::GetFileNameWithoutExtension($Script) }
    $Parameters = @($Parameters) + @(@{ Name = '-Help'; Description = 'Show this help and exit.' })
    if ($Script) { Show-DevboxVersion -Script $Script }
    Write-Host ''
    Write-Host 'NAME' -ForegroundColor Cyan
    Write-Host "    $Name" -ForegroundColor Green
    Write-Host ''
    Write-Host 'DESCRIPTION' -ForegroundColor Cyan
    foreach ($line in (Get-DevboxWrappedLines -Text $Description -Width ($width - 4))) { Write-Host "    $line" }
    Write-Host ''
    Write-Host 'USAGE' -ForegroundColor Cyan
    Write-Host "    $Usage" -ForegroundColor Green
    Write-Host ''
    Write-Host 'PARAMETERS' -ForegroundColor Cyan
    $nameWidth = ($Parameters | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 3
    foreach ($parameter in $Parameters) {
        $lines = @(Get-DevboxWrappedLines -Text $parameter.Description -Width ($width - 4 - $nameWidth))
        Write-Host ('    ' + $parameter.Name.PadRight($nameWidth)) -NoNewline -ForegroundColor Green
        Write-Host $lines[0]
        foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host ((' ' * (4 + $nameWidth)) + $line) }
    }
    if ($Examples.Count -gt 0) {
        Write-Host ''
        Write-Host 'EXAMPLES' -ForegroundColor Cyan
        foreach ($example in $Examples) {
            Write-Host "    $($example.Command)" -ForegroundColor Green
            foreach ($line in (Get-DevboxWrappedLines -Text $example.Description -Width ($width - 8))) { Write-Host "        $line" }
        }
    }
    if ($Notes.Count -gt 0) {
        Write-Host ''
        Write-Host 'NOTES' -ForegroundColor Cyan
        foreach ($note in $Notes) {
            $lines = @(Get-DevboxWrappedLines -Text $note -Width ($width - 6))
            Write-Host "    - $($lines[0])"
            foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host "      $line" }
        }
    }
    Write-Host ''
}

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

# Version of the image that these scripts build and expect ("image" in manifest.json). It changes
# only when the Dockerfile or the entrypoint change; a new project version does not touch it.
# 'unknown' when the manifest is missing or unreadable.
function Get-DevboxImageVersion {
    $manifest = Join-Path (Get-DevboxBase) 'manifest.json'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        try {
            $version = (Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json).image
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
    if (-not $manifest.image) { $errors += "manifest.json has no 'image' version" }
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

# Stop when the installed package is inconsistent with manifest.json. With -WarnOnly it only
# warns and returns: scripts that use an existing container (start, connect) must never be
# blocked by versions.
function Assert-DevboxIntegrity {
    param([switch]$WarnOnly)
    $result = Get-DevboxIntegrity -Base (Get-DevboxBase)
    if ($result.Errors.Count -eq 0) { return }
    if ($WarnOnly) {
        Write-DevboxWarning 'Warning: the installed package is inconsistent with manifest.json (continuing anyway):'
        foreach ($problem in $result.Errors) { Write-DevboxWarning "  - $problem" }
        Write-DevboxNext 'Next: run install.ps1 again (dkdb-verify shows the details).'
        return
    }
    Write-DevboxWarning 'Error: the installed package is inconsistent with manifest.json:'
    foreach ($problem in $result.Errors) { Write-DevboxWarning "  - $problem" }
    Write-DevboxNext 'Run install.ps1 again (dkdb-verify shows the details).'
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

# Highest tag of the image $ImageName (with prefix) compatible with the image version that the scripts expect, as
# name:tag; $null when there is none. With -AnyVersion, the highest version tag whatever its
# version (an older image still works). Images are tagged with a version, never latest.
function Get-DevboxCompatibleImage {
    param(
        [Parameter(Mandatory)][string]$ImageName,
        [switch]$AnyVersion
    )
    $expected = Get-DevboxImageVersion
    $best = $null
    foreach ($line in (docker images --format '{{.Repository}}:{{.Tag}}')) {
        $separator = $line.LastIndexOf(':')
        if ($separator -lt 1) { continue }
        if ($line.Substring(0, $separator) -cne $ImageName) { continue }
        $tag = $line.Substring($separator + 1)
        $parsed = $null
        if (-not [version]::TryParse($tag, [ref]$parsed)) { continue }
        if (-not $AnyVersion -and -not (Test-DevboxVersionCompatible -Left $tag -Right $expected)) { continue }
        if ($null -eq $best -or $parsed -gt $best) { $best = $parsed }
    }
    if ($null -eq $best) { return $null }
    return "${ImageName}:$best"
}

# Tell whether the container was created from an image compatible with the image version that the
# scripts expect (same major.minor in 0.x, same major from 1.0; a new project version does not
# matter). It only warns and never blocks: an update must not stop anybody from using an existing
# container, which keeps working with the image it was created from. Returns $true when compatible.
function Test-DevboxContainerVersion {
    param([Parameter(Mandatory)][string]$Container)
    $imageVersion = Get-DevboxContainerEnv -Container $Container -Name 'DEVBOX_IMAGE_VERSION'
    $expected = Get-DevboxImageVersion
    $shown = $imageVersion
    if (-not $shown) { $shown = 'unknown' }
    Write-Host "Container image version: $shown"
    if ($imageVersion -and (Test-DevboxVersionCompatible -Left $imageVersion -Right $expected)) { return $true }
    Write-DevboxWarning "Warning: '$Container' was created from an image with version $shown, not compatible with the image version that the scripts expect ($expected). It keeps working, but newer features may be missing."
    Write-DevboxNext 'Next: to update, rebuild the image (dkdb-image-create) and recreate the container (copy your data out first, for example with docker cp).'
    return $false
}

# Linux limits user names to 32 characters; the prefix and the hyphen use some.
$DevboxMaxInputLength = 32 - ($DevboxPrefix.Length + 1)

# --- Message colors (spec 01): success (something was done correctly) in green, warnings and
# errors in red, the natural next step in yellow. Other messages keep the default color.
# The menu (Select-DevboxItem) keeps its own colors.
function Write-DevboxSuccess {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Green
}
function Write-DevboxWarning {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Red
}
function Write-DevboxNext {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Yellow
}

function Assert-DevboxDocker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-DevboxWarning 'Error: docker was not found in the PATH.'
        exit 1
    }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-DevboxWarning 'Error: the Docker daemon is not reachable. Is Docker Desktop running?'
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
            Write-DevboxWarning 'Use lowercase letters, digits, "-" or "_", starting with a letter.'
            continue
        }
        if ($value.Length -gt $DevboxMaxInputLength) {
            Write-DevboxWarning "Maximum $DevboxMaxInputLength characters (the prefix '$DevboxPrefix-' is added)."
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
        Write-DevboxWarning "Error: the scripts must be in <root>\devbox\scripts\ps1 (found: $PSScriptRoot). Run install.ps1 again."
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
        Write-DevboxWarning "Error: bash folder not found: $path"
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

# --- Native programs (Windows PowerShell 5.1 and 7) ---
# One argument quoted for a Windows command line (spaces, quotes and trailing backslashes).
function ConvertTo-DevboxNativeArgument {
    param([AllowEmptyString()][string]$Argument)
    if ($Argument -ne '' -and $Argument -notmatch '[\s"]') { return $Argument }
    $escaped = $Argument -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

# Run a program and capture its standard output and its error output SEPARATELY, with its exit
# code. In Windows PowerShell 5.1 the error lines of a program become verbose error records when
# they are mixed in with 2>&1, and they can even stop a script that sets ErrorActionPreference to
# Stop; reading both streams directly avoids all of that. Do not use it for a program that leaves
# a background process holding the streams (mutagen daemon start).
function Invoke-DevboxNative {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Arguments = @()
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Path
    $startInfo.Arguments = (@($Arguments | ForEach-Object { ConvertTo-DevboxNativeArgument -Argument $_ })) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
    } catch {
        return [pscustomobject]@{ ExitCode = -1; Output = ''; Error = $_.Exception.Message }
    }
    # Both streams are read at the same time so that a full pipe cannot block the program.
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $result = [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $outputTask.Result; Error = $errorTask.Result }
    $process.Dispose()
    return $result
}

# Version of the installed Mutagen ([version]), or $null when it cannot be read.
function Get-DevboxMutagenVersion {
    $mutagen = Get-DevboxMutagenExe
    if (-not $mutagen) { return $null }
    $run = Invoke-DevboxNative -Path $mutagen -Arguments @('version')
    $text = $run.Output + ' ' + $run.Error
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
        Write-DevboxSuccess "Added to the user PATH: $Folder (open a new terminal to use it by hand)"
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
    Write-Host "Mutagen $DevboxMutagenVersion is not installed."
    Write-Host 'It synchronizes the projects folder with a copy inside the container, avoiding the slow'
    Write-Host 'Docker Desktop mounts. Download: about 100 MB from github.com/mutagen-io/mutagen.'
    Write-Host 'License: MIT, plus SSPL for part of the official builds; it is a separate third-party tool (spec 08).'
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
        Write-DevboxSuccess 'Checksum OK.'
        if (-not (Test-Path -LiteralPath $target -PathType Container)) {
            New-Item -ItemType Directory -Path $target | Out-Null
        }
        Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
    } catch {
        Write-DevboxWarning "Error: could not install Mutagen ($($_.Exception.Message))."
        return $false
    } finally {
        $ProgressPreference = $previousProgress
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'mutagen.exe') -PathType Leaf)) {
        Write-DevboxWarning "Error: mutagen.exe was not found after extracting into $target"
        return $false
    }
    Add-DevboxUserPath -Folder $target
    Write-DevboxSuccess "Mutagen installed in $target"
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

# What 'mutagen sync list' answers with autostart disabled: the reason why the daemon does not
# respond (not running, version mismatch with the executable, ...). Empty when it responds.
function Get-DevboxMutagenDaemonError {
    $mutagen = Get-DevboxMutagenExe
    if (-not $mutagen) { return 'mutagen.exe was not found' }
    $previous = $env:MUTAGEN_DISABLE_AUTOSTART
    $env:MUTAGEN_DISABLE_AUTOSTART = '1'
    try {
        $run = Invoke-DevboxNative -Path $mutagen -Arguments @('sync', 'list')
        if ($run.ExitCode -eq 0) { return '' }
        return ($run.Error + ' ' + $run.Output).Trim()
    } finally {
        if ($null -eq $previous) { Remove-Item Env:MUTAGEN_DISABLE_AUTOSTART -ErrorAction SilentlyContinue }
        else { $env:MUTAGEN_DISABLE_AUTOSTART = $previous }
    }
}

# Make sure the daemon is running: nothing to do when it is, start it otherwise.
# 'mutagen daemon start' only launches the daemon in the background and returns at once,
# so this waits (up to about 10 seconds) until the daemon answers.
function Start-DevboxMutagenDaemon {
    if (Test-DevboxMutagenDaemon) { return $true }
    $mutagen = Get-DevboxMutagenExe
    if (-not $mutagen) { return $false }
    Write-Host 'Starting the Mutagen daemon ...'
    & $mutagen daemon start *> $null
    $startCode = $LASTEXITCODE
    for ($i = 0; $i -lt 20; $i++) {
        if (Test-DevboxMutagenDaemon) { return $true }
        Start-Sleep -Milliseconds 500
    }
    Write-DevboxWarning "Mutagen: 'daemon start' exited with code $startCode."
    Write-DevboxWarning "Mutagen: the daemon does not answer: $(Get-DevboxMutagenDaemonError)"
    Write-DevboxNext 'If it mentions a version mismatch, another Mutagen daemon is running: stop it with dkdb-mutagen-stop (or mutagen daemon stop) and try again.'
    return $false
}

# Wait until the container entrypoint has created the user: marker file in /dev/shm (a tmpfs that
# Docker recreates at every container start). Images built before the version support
# (no DEVBOX_IMAGE_VERSION) do not create the marker: for them it waits until the user exists, so an
# old image is never left waiting for something it cannot provide.
function Wait-DevboxContainerReady {
    param(
        [Parameter(Mandatory)][string]$Container,
        [string]$User,
        [int]$TimeoutSeconds = 60
    )
    $hasMarker = [bool](Get-DevboxContainerEnv -Container $Container -Name 'DEVBOX_IMAGE_VERSION')
    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        if ($hasMarker -or -not $User) { docker exec $Container test -f /dev/shm/devbox-ready *> $null }
        else { docker exec $Container id -u $User *> $null }
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
# Single place for the naming rule (see New-DevboxFolderSession). $null when the ID is unknown.
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

# Progress of one session object of 'mutagen sync list --template "{{json .}}"' (the field names
# are those of Mutagen's public session model, checked in the 0.18.1 source). Done/Total are
# files: while files are being transferred (stagingProgress) they are the received and expected
# files; otherwise they are the files of the beta and of the alpha endpoint.
# A count from the JSON of Mutagen as [int64]; $null when it is missing or not a single number.
function ConvertTo-DevboxCount {
    param($Value)
    $number = [int64]0
    if ($null -ne $Value -and $Value -isnot [System.Array] -and [int64]::TryParse([string]$Value, [ref]$number)) { return $number }
    return $null
}

function ConvertTo-DevboxSyncProgress {
    param([Parameter(Mandatory)]$Session)
    # Defensive: a list must never reach this point (see ConvertFrom-DevboxJsonList).
    if ($Session -is [System.Array]) { $Session = $Session | Select-Object -First 1 }
    $done = $null
    $total = $null
    $staging = $Session.beta.stagingProgress
    if (-not $staging) { $staging = $Session.alpha.stagingProgress }
    if ($staging -and $staging.expectedFiles -gt 0) {
        $done = ConvertTo-DevboxCount -Value $staging.receivedFiles
        $total = ConvertTo-DevboxCount -Value $staging.expectedFiles
    } elseif ($Session.alpha.scanned -and $Session.beta.scanned) {
        $done = ConvertTo-DevboxCount -Value $Session.beta.files
        $total = ConvertTo-DevboxCount -Value $Session.alpha.files
    }
    # Mutagen omits 'conflicts' when there are none: @($null).Count would be 1.
    $conflictCount = 0
    if ($Session.conflicts) { $conflictCount = @($Session.conflicts).Count }
    return [pscustomobject]@{
        Name      = [string]$Session.name
        AlphaPath = [string]$Session.alpha.path
        BetaProtocol = [string]$Session.beta.protocol
        BetaHost  = [string]$Session.beta.host
        BetaPath  = [string]$Session.beta.path
        Status    = [string]$Session.status
        Done      = $done
        Total     = $total
        Paused    = [bool]$Session.paused
        LastError = [string]$Session.lastError
        Conflicts = $conflictCount
    }
}

# Items of a JSON array (the sessions of 'mutagen sync list --template "{{json .}}"'), the same in
# Windows PowerShell 5.1 and in PowerShell 7: ConvertFrom-Json emits a JSON array as ONE object in
# 5.1 and element by element in 7, so the result is flattened. Returns @() when the text is not JSON.
function ConvertFrom-DevboxJsonList {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { return @() }
    try { $parsed = $Json | ConvertFrom-Json } catch { return @() }
    $items = @()
    foreach ($item in @($parsed)) {
        if ($item -is [System.Array]) { $items += @($item) } elseif ($null -ne $item) { $items += $item }
    }
    return @($items)
}

# Progress of the first session of a JSON (an array of sessions); $null when there is none.
function Get-DevboxSyncProgress {
    param([Parameter(Mandatory)][string]$Json)
    $sessions = @(ConvertFrom-DevboxJsonList -Json $Json)
    $session = $sessions | Select-Object -First 1
    if (-not $session) { return $null }
    return ConvertTo-DevboxSyncProgress -Session $session
}

# Progress of every session known by the daemon (it must be running); empty when there are none.
function Get-DevboxMutagenSessions {
    $mutagen = Get-DevboxMutagenExe
    if (-not $mutagen) { return @() }
    $run = Invoke-DevboxNative -Path $mutagen -Arguments @('sync', 'list', '--template', '{{json .}}')
    if ($run.ExitCode -ne 0) { return @() }
    $json = $run.Output
    $sessions = @(ConvertFrom-DevboxJsonList -Json $json)
    return @($sessions | Where-Object { $_ } | ForEach-Object { ConvertTo-DevboxSyncProgress -Session $_ })
}

# Show where the synchronization is and whether it moved since the previous query. The previous
# query is kept in a small file in the temp folder, one per session.
function Show-DevboxSyncProgress {
    param(
        [Parameter(Mandatory)][string]$Session,
        [Parameter(Mandatory)]$Progress
    )
    $statePath = Join-Path ([System.IO.Path]::GetTempPath()) "dkdb-mutagen-status-$Session.json"
    $now = Get-Date
    $complete = ($null -ne $Progress.Total -and $Progress.Total -gt 0 -and $Progress.Done -ge $Progress.Total -and $Progress.Status -eq 'watching' -and -not $Progress.Paused)
    if ($null -ne $Progress.Total -and $Progress.Total -gt 0 -and $null -ne $Progress.Done) {
        $percent = [math]::Min(100, [int][math]::Floor(100 * $Progress.Done / $Progress.Total))
        Write-Host "So far $($Progress.Done) of $($Progress.Total) files ($percent%) - status: $($Progress.Status)"
    } else {
        Write-Host "No file counts yet - status: $($Progress.Status)"
    }
    if ($Progress.Paused) { Write-DevboxWarning 'The session is paused: dkdb-container-start or dkdb-container-connect resume it.' }
    if ($Progress.LastError) { Write-DevboxWarning "Mutagen reports an error: $($Progress.LastError)" }
    if ($Progress.Conflicts -gt 0) { Write-DevboxWarning "$($Progress.Conflicts) conflicts: see TROUBLESHOOTING.md." }
    $previous = $null
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        try { $previous = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json } catch { $previous = $null }
    }
    if ($previous) {
        $seconds = [int](($now - [datetime]$previous.Time).TotalSeconds)
        $ago = "$seconds s ago"
        if ($seconds -ge 120) { $ago = "$([int]($seconds / 60)) min ago" }
        if ($complete) {
            Write-DevboxSuccess "The synchronization is up to date (previous query: $ago)."
        } elseif ($null -ne $Progress.Done -and $null -ne $previous.Done -and $Progress.Done -gt $previous.Done) {
            Write-DevboxSuccess "Progress: +$($Progress.Done - $previous.Done) files since the previous query ($ago)."
        } elseif ($null -ne $Progress.Done -and $null -ne $previous.Done -and $Progress.Done -lt $previous.Done) {
            Write-Host "The counters restarted since the previous query ($ago): a new synchronization cycle began."
        } elseif ($Progress.Status -ne $previous.Status) {
            Write-Host "The status changed since the previous query ($ago): $($previous.Status) -> $($Progress.Status)"
        } else {
            Write-DevboxWarning "No progress since the previous query ($ago)."
        }
    } elseif ($complete) {
        Write-DevboxSuccess 'The synchronization is up to date.'
    } else {
        Write-Host 'First query of this session: run it again to see the progress.'
    }
    $snapshot = [pscustomobject]@{ Time = $now.ToString('o'); Status = $Progress.Status; Done = $Progress.Done; Total = $Progress.Total }
    try { $snapshot | ConvertTo-Json | Set-Content -LiteralPath $statePath } catch { $statePath = $null }
    return $complete
}

# After a failed flush, show why: the status of the session and its last error (the flush message
# only says that the synchronization failed while waiting).
function Show-DevboxSyncFailure {
    param([Parameter(Mandatory)][string]$Session)
    $mutagen = Get-DevboxMutagenExe
    $json = (Invoke-DevboxNative -Path $mutagen -Arguments @('sync', 'list', '--template', '{{json .}}', $Session)).Output
    $info = Get-DevboxSyncProgress -Json $json
    if (-not $info) {
        Write-DevboxWarning "The session '$Session' could not be read. Check it with: dkdb-mutagen-status"
        return
    }
    Write-DevboxWarning "Mutagen status: $($info.Status)"
    if ($info.LastError) { Write-DevboxWarning "Mutagen last error: $($info.LastError)" }
    else { Write-Host 'Mutagen reports no error for the session (it may be reconnecting).' }
    Write-DevboxNext 'Next: dkdb-mutagen-status shows the details and the progress; run it again to see whether it moves.'
}

# --- Incremental synchronization (menu of Invoke-DevboxSyncPick, spec 08) ---
# A folder of the projects path: relative to it, or absolute inside it. Returns Relative (with
# '/'), Full and Error (empty when the folder is valid: it exists and is inside the projects path).
function Resolve-DevboxSyncFolder {
    param([Parameter(Mandatory)][string]$HostPath, [Parameter(Mandatory)][string]$Folder)
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $base = [System.IO.Path]::GetFullPath($HostPath).TrimEnd('\', '/')
    $candidate = $Folder.Trim().Trim('"')
    if (-not [System.IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $base $candidate }
    $full = [System.IO.Path]::GetFullPath($candidate).TrimEnd('\', '/')
    $result = [pscustomobject]@{ Relative = $null; Full = $full; Error = $null }
    # Windows paths are case-insensitive.
    if ($full.Length -le $base.Length -or -not $full.StartsWith($base + $separator, [System.StringComparison]::OrdinalIgnoreCase)) {
        $result.Error = "it must be a folder inside the projects folder ($base); choose All in the menu to synchronize everything"
        return $result
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        $result.Error = "the folder does not exist: $full"
        return $result
    }
    $result.Relative = ($full.Substring($base.Length + 1)) -replace '\\', '/'
    return $result
}

# Name of the session of a folder: <session of the container>-f<8 hex of the lowercase path>.
function Get-DevboxFolderSessionName {
    param([Parameter(Mandatory)][string]$MainSession, [Parameter(Mandatory)][string]$Relative)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Relative.ToLowerInvariant()))
    $hex = -join ($bytes[0..3] | ForEach-Object { $_.ToString('x2') })
    return "$MainSession-f$hex"
}

# Create a synchronization session (two-way-safe, everything including .git, symbolic links ignored).
function New-DevboxSyncSession {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Alpha,
        [Parameter(Mandatory)][string]$Beta,
        [Parameter(Mandatory)][string]$User
    )
    $mutagen = Get-DevboxMutagenExe
    $syncArgs = @(
        'sync', 'create',
        '--name', $Name,
        '--sync-mode', 'two-way-safe',
        '--no-ignore-vcs',
        '--symlink-mode', 'ignore',
        '--default-file-mode', '0644',
        '--default-directory-mode', '0755',
        '--default-owner-beta', $User,
        '--default-group-beta', $User,
        $Alpha,
        $Beta
    )
    & $mutagen @syncArgs | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Flush a session and wait for the cycle to end; on failure show why.
function Invoke-DevboxSyncFlush {
    param([Parameter(Mandatory)][string]$Session)
    $mutagen = Get-DevboxMutagenExe
    Write-Host "Synchronizing $Session ..."
    Write-DevboxNext 'A large folder can take a while: follow it from another terminal with dkdb-mutagen-status.'
    & $mutagen sync flush $Session | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-DevboxWarning 'Warning: the flush failed. Mutagen retries the connection by itself; the synchronization may still progress.'
        Show-DevboxSyncFailure -Session $Session
    }
}

# Resume sessions that already exist (and flush them when asked). Returns $false if one fails.
function Resume-DevboxSyncSessions {
    param([Parameter(Mandatory)][string[]]$Names, [switch]$Flush)
    $mutagen = Get-DevboxMutagenExe
    $ok = $true
    foreach ($name in $Names) {
        & $mutagen sync resume $name | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-DevboxWarning "Error: could not resume the Mutagen session '$name'."
            $ok = $false
            continue
        }
        if ($Flush) { Invoke-DevboxSyncFlush -Session $name }
    }
    return $ok
}

# --- Which sessions belong to a container, and overlaps between them (spec 08) ---
# A session belongs to a container when its beta endpoint points to it: protocol docker and the
# container written in the URL (its name, its ID or a prefix of the ID). That also covers the
# sessions created by hand with any name. Only when the endpoint is unknown (no protocol or no
# host) the name of the session (<session of the container> and <session>-f...) is used.
function Test-DevboxSessionOfContainer {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ContainerId,
        [Parameter(Mandatory)][string]$ContainerName,
        [string]$MainSession = ''
    )
    if ($Session.BetaProtocol -and $Session.BetaHost) {
        if ($Session.BetaProtocol -ne 'docker') { return $false }
        $target = $Session.BetaHost
        if ($target -ieq $ContainerName) { return $true }
        if ($target.Length -ge 6 -and $ContainerId.StartsWith($target, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        return $false
    }
    return ($MainSession -ne '' -and ($Session.Name -eq $MainSession -or $Session.Name -like "$MainSession-f*"))
}

# Sessions of a container: the one of the whole projects folder and those of its folders, whatever
# their names.
function Get-DevboxContainerSyncSessions {
    param([Parameter(Mandatory)][string]$Container)
    $containerId = Get-DevboxContainerId -Container $Container
    if (-not $containerId) { return @() }
    $main = Get-DevboxSyncSessionName -Container $Container
    return @(Get-DevboxMutagenSessions | Where-Object {
        Test-DevboxSessionOfContainer -Session $_ -ContainerId $containerId -ContainerName $Container -MainSession $main
    })
}

# Every container of Docker (any name, any state) as @{ Id; Name }.
function Get-DevboxAllContainerRefs {
    $refs = @()
    foreach ($line in (docker ps -a --no-trunc --format '{{.ID}}|{{.Names}}')) {
        $parts = $line -split '\|'
        if ($parts.Count -ge 2 -and $parts[0]) { $refs += [pscustomobject]@{ Id = $parts[0]; Name = $parts[1] } }
    }
    return @($refs)
}

# A session is an orphan when its beta endpoint points to a Docker container that no longer exists
# (it can never connect again), whatever the name of the session. Only when the endpoint is unknown,
# a session named <prefix>-* that is not the session of a living Mutagen container (or one of its
# folders) is taken as an orphan. Sessions of other protocols are never orphans.
function Test-DevboxSessionOrphan {
    param(
        [Parameter(Mandatory)]$Session,
        [object[]]$ContainerRefs = @(),
        [string[]]$AliveMainSessions = @()
    )
    if ($Session.BetaProtocol -and $Session.BetaHost) {
        if ($Session.BetaProtocol -ne 'docker') { return $false }
        $target = $Session.BetaHost
        foreach ($ref in $ContainerRefs) {
            if ($target -ieq $ref.Name) { return $false }
            if ($target.Length -ge 6 -and $ref.Id.StartsWith($target, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
            if ($ref.Id.Length -ge 6 -and $target.StartsWith($ref.Id, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        return $true
    }
    if ($Session.Name -notlike "$DevboxPrefix-*") { return $false }
    return (-not ($AliveMainSessions | Where-Object { $Session.Name -eq $_ -or $Session.Name -like "$_-f*" }))
}

# A folder of the container, normalized to compare: slashes, no trailing slash.
function ConvertTo-DevboxBetaPath {
    param([AllowEmptyString()][string]$Path)
    $normalized = ($Path -replace '\\', '/') -replace '/+', '/'
    if ($normalized.Length -gt 1) { $normalized = $normalized.TrimEnd('/') }
    return $normalized
}

# Pairs of sessions of ONE container whose folders in the container overlap: the same folder, or one
# inside the other. Sessions of different containers may overlap (several containers can share a
# host folder), so only the sessions of a single container are given. Case is ignored (the host is).
# Returns objects with First, Second and Reason; empty when there is no overlap.
function Get-DevboxSessionOverlaps {
    param([object[]]$Sessions)
    $items = @($Sessions | Where-Object { $_ -and $_.BetaPath } | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Path = (ConvertTo-DevboxBetaPath -Path $_.BetaPath) }
    })
    $overlaps = @()
    for ($i = 0; $i -lt $items.Count; $i++) {
        for ($j = $i + 1; $j -lt $items.Count; $j++) {
            $first = $items[$i]
            $second = $items[$j]
            $comparison = [System.StringComparison]::OrdinalIgnoreCase
            $reason = $null
            if ($first.Path.Equals($second.Path, $comparison)) { $reason = "both synchronize $($first.Path)" }
            elseif ($second.Path.StartsWith($first.Path.TrimEnd('/') + '/', $comparison)) { $reason = "$($second.Path) is inside $($first.Path)" }
            elseif ($first.Path.StartsWith($second.Path.TrimEnd('/') + '/', $comparison)) { $reason = "$($first.Path) is inside $($second.Path)" }
            if ($reason) { $overlaps += [pscustomobject]@{ First = $first.Name; Second = $second.Name; Reason = $reason } }
        }
    }
    return @($overlaps)
}

# Print, in red, the overlaps among the sessions of a container (see Get-DevboxSessionOverlaps).
# Returns how many there are.
function Show-DevboxSessionOverlaps {
    param([Parameter(Mandatory)][string]$Container, [object[]]$Sessions)
    $overlaps = @(Get-DevboxSessionOverlaps -Sessions @($Sessions | Where-Object { -not $_.Paused }))
    if ($overlaps.Count -eq 0) { return 0 }
    Write-DevboxWarning "Error: '$Container' has overlapping ACTIVE Mutagen sessions (two active sessions of one container must not overlap):"
    foreach ($overlap in $overlaps) { Write-DevboxWarning "  - $($overlap.First) and $($overlap.Second): $($overlap.Reason)" }
    Write-DevboxNext "Next: pause the one you do not want (mutagen sync pause <name>) or terminate it (mutagen sync terminate <name>); the files are not touched."
    return $overlaps.Count
}

# Names of the sessions to terminate when a container is deleted. The daemon is not started for it:
# when it is stopped, only the main name is returned.
function Get-DevboxContainerSessionNames {
    param([Parameter(Mandatory)][string]$Container)
    $main = Get-DevboxSyncSessionName -Container $Container
    if (-not $main) { return @() }
    if (-not (Test-DevboxMutagen) -or -not (Test-DevboxMutagenDaemon)) { return @($main) }
    $names = @(Get-DevboxContainerSyncSessions -Container $Container | ForEach-Object { $_.Name })
    if ($names.Count -eq 0) { return @($main) }
    return $names
}

# Level 1 of the synchronization ladder (nothing is synchronized): for a Mutagen container the
# daemon is started, so that it is available, and the sessions that already exist are PAUSED (an
# active session reconnects by itself when its container is up). Nothing is created, resumed or
# flushed. Returns $true on success; prints the reason and returns $false otherwise.
function Suspend-DevboxSyncSessions {
    param([Parameter(Mandatory)][string]$Container)
    if (-not (Test-DevboxMutagen)) {
        Write-DevboxWarning 'Warning: mutagen.exe was not found (dkdb-container-create installs it on demand): nothing is synchronized.'
        return $false
    }
    if (-not (Start-DevboxMutagenDaemon)) {
        Write-DevboxWarning 'Error: the Mutagen daemon could not be started.'
        return $false
    }
    $mutagen = Get-DevboxMutagenExe
    $paused = 0
    foreach ($session in @(Get-DevboxContainerSyncSessions -Container $Container)) {
        if ($session.Paused) { continue }
        & $mutagen sync pause $session.Name *> $null
        if ($LASTEXITCODE -eq 0) { $paused++ }
        else { Write-DevboxWarning "Warning: could not pause the Mutagen session '$($session.Name)'." }
    }
    if ($paused -gt 0) { Write-Host "The Mutagen daemon is running; $paused session(s) of '$Container' paused: nothing is synchronized." }
    else { Write-Host 'The Mutagen daemon is running; nothing is synchronized.' }
    return $true
}

# The sessions of a container that synchronize the projects folder or a folder inside it, as
# Name, Relative ('' = the whole projects folder, 'a/b' = a folder) and Paused. Sessions outside
# the projects folder are not ours to judge and are left out.
function Get-DevboxProjectSessions {
    param([Parameter(Mandatory)][string]$Container, [Parameter(Mandatory)][string]$User)
    $rootBeta = "/home/$User/devbox/projects"
    $known = @()
    foreach ($item in @(Get-DevboxContainerSyncSessions -Container $Container)) {
        $path = ConvertTo-DevboxBetaPath -Path $item.BetaPath
        if ($path.Equals($rootBeta, [System.StringComparison]::OrdinalIgnoreCase)) { $known += [pscustomobject]@{ Name = $item.Name; Relative = ''; Paused = $item.Paused } }
        elseif ($path.StartsWith($rootBeta + '/', [System.StringComparison]::OrdinalIgnoreCase)) { $known += [pscustomobject]@{ Name = $item.Name; Relative = $path.Substring($rootBeta.Length + 1); Paused = $item.Paused } }
    }
    return $known
}

# $true when the folder Outer covers the folder Inner: the same one or one that contains it
# ('' is the whole projects folder, which covers everything).
function Test-DevboxFolderCovers {
    param([string]$Outer, [string]$Inner)
    $o = $Outer.ToLowerInvariant()
    $i = $Inner.ToLowerInvariant()
    return (($o -eq '') -or ($o -eq $i) -or $i.StartsWith($o + '/'))
}

# Pause sessions (never terminate them; the files are not touched). Returns $false if one fails.
function Suspend-DevboxSessionList {
    param([object[]]$Sessions, [string]$Reason)
    $mutagen = Get-DevboxMutagenExe
    $ok = $true
    foreach ($item in @($Sessions)) {
        & $mutagen sync pause $item.Name *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host "Session '$($item.Name)' ($(if ($item.Relative) { $item.Relative } else { 'whole projects folder' })) paused: $Reason." }
        else { Write-DevboxWarning "Warning: could not pause the Mutagen session '$($item.Name)'."; $ok = $false }
    }
    return $ok
}

# Create the session of a folder of the projects path (docker exec mkdir -p, New-DevboxSyncSession,
# flush). Returns the session object (Name, Relative, Paused) or $null on failure.
function New-DevboxFolderSession {
    param([Parameter(Mandatory)][string]$Container, [Parameter(Mandatory)][string]$User, [Parameter(Mandatory)][string]$Relative, [Parameter(Mandatory)][string]$Full)
    $containerId = Get-DevboxContainerId -Container $Container
    $main = Get-DevboxSyncSessionName -Container $Container
    if (-not $containerId -or -not $main) {
        Write-DevboxWarning "Error: could not read the ID of '$Container'."
        return $null
    }
    $name = Get-DevboxFolderSessionName -MainSession $main -Relative $Relative
    docker exec -u $User $Container mkdir -p "/home/$User/devbox/projects/$Relative" *> $null
    if (-not (New-DevboxSyncSession -Name $name -Alpha $Full -Beta "docker://$User@$containerId/home/$User/devbox/projects/$Relative" -User $User)) {
        Write-DevboxWarning "Error: could not create the Mutagen session for the folder '$Relative'."
        return $null
    }
    Write-DevboxSuccess "Folder '$Relative' added to the synchronization."
    Invoke-DevboxSyncFlush -Session $name
    return [pscustomobject]@{ Name = $name; Relative = $Relative; Paused = $false }
}

# Activate one session: resume it (flushing when asked) and pause the ACTIVE sessions it covers (they
# stay registered and can be activated again). When another active session already covers it, nothing
# changes: somebody may be using that one. Returns $false on failure.
function Enable-DevboxFolderSession {
    param([Parameter(Mandatory)][object]$Target, [object[]]$Sessions, [switch]$Flush)
    $others = @($Sessions | Where-Object { $_.Name -ne $Target.Name })
    $coveringActive = @($others | Where-Object { -not $_.Paused -and (Test-DevboxFolderCovers -Outer $_.Relative -Inner $Target.Relative) })
    if ($coveringActive.Count -gt 0) {
        Write-Host "'$($Target.Relative)' is already synchronized by the active session '$($coveringActive[0].Name)': nothing changed."
        return $true
    }
    if ($Target.Paused) {
        if (-not (Resume-DevboxSyncSessions -Names @($Target.Name) -Flush:$Flush)) { return $false }
    }
    $covered = @($others | Where-Object { -not $_.Paused -and (Test-DevboxFolderCovers -Outer $Target.Relative -Inner $_.Relative) })
    return (Suspend-DevboxSessionList -Sessions $covered -Reason "it is inside '$(if ($Target.Relative) { $Target.Relative } else { 'the whole projects folder' })'")
}

# The synchronization menu: No sync, the folders already registered as sessions of the container,
# All registered and Add (a new folder). The rules, from the intersection of the folders:
#   - a session that covers active ones is activated and pauses them;
#   - one that is not inside any other and covers none is just activated (nothing else is paused);
#   - one that is inside an active session changes nothing (somebody may be using that one);
#   - All registered activates the sessions that are not inside another registered one;
#   - only No sync pauses everything. Nothing is ever terminated and no file is touched.
# A session of the whole projects folder is never created here, it only appears when it exists.
# Returns Ok ($false on failure; the reason is printed) and Active ($true when something is synchronized).
function Invoke-DevboxSyncPick {
    param([Parameter(Mandatory)][string]$Container, [switch]$Flush)
    $result = [pscustomobject]@{ Ok = $true; Active = $false }
    $fail = { $result.Ok = $false; return $result }
    $user = Get-DevboxContainerUser -Container $Container
    $hostPath = Get-DevboxContainerEnv -Container $Container -Name 'DEVBOX_SYNC_PATH'
    if (-not $user -or -not $hostPath) {
        Write-DevboxWarning "Error: '$Container' has no DEVBOX_USER or DEVBOX_SYNC_PATH variable."
        return (& $fail)
    }
    if (-not (Test-DevboxMutagen)) {
        Write-DevboxWarning 'Error: mutagen.exe was not found (dkdb-container-create installs it on demand).'
        return (& $fail)
    }
    # All the checks, always, before anything is shown or touched.
    if (-not (Get-DevboxContainerId -Container $Container) -or -not (Get-DevboxSyncSessionName -Container $Container)) {
        Write-DevboxWarning "Error: could not read the ID of '$Container'."
        return (& $fail)
    }
    if (-not (Test-Path -LiteralPath $hostPath -PathType Container)) {
        Write-DevboxWarning "Error: the host projects path does not exist: $hostPath"
        return (& $fail)
    }
    if (-not (Wait-DevboxContainerReady -Container $Container -User $user)) {
        Write-DevboxWarning "Error: the container '$Container' did not become ready in time."
        return (& $fail)
    }
    if (-not (Start-DevboxMutagenDaemon)) {
        Write-DevboxWarning 'Error: the Mutagen daemon could not be started.'
        return (& $fail)
    }
    $sessions = @(Get-DevboxProjectSessions -Container $Container -User $user)
    # Two ACTIVE sessions that overlap must not exist (a paused one does no harm).
    if ((Show-DevboxSessionOverlaps -Container $Container -Sessions @(Get-DevboxContainerSyncSessions -Container $Container)) -gt 0) { return (& $fail) }
    $state = { param($item) if ($item.Paused) { 'paused' } else { 'active' } }
    $noSync = 'No sync'
    $allItem = 'All registered'
    $addItem = 'Add...'
    $labels = @($noSync)
    $byLabel = @{}
    foreach ($item in @($sessions | Sort-Object { $_.Relative })) {
        $name = if ($item.Relative) { $item.Relative } else { '(the whole projects folder)' }
        $label = "$name  [$(& $state $item)]"
        $labels += $label
        $byLabel[$label] = $item
    }
    if ($sessions.Count -gt 0) { $labels += $allItem }
    $labels += $addItem
    $choice = Select-DevboxItem -Title "Select what to synchronize in '$Container':" -Items $labels
    if (-not $choice) {
        Write-Host 'Cancelled: nothing was changed.'
        return $result
    }
    if ($choice -eq $noSync) {
        $result.Ok = [bool](Suspend-DevboxSyncSessions -Container $Container)
        return $result
    }
    $ok = $true
    if ($choice -eq $allItem) {
        # The sessions that are not inside another registered one.
        $top = @($sessions | Where-Object { $item = $_; -not @($sessions | Where-Object { $_.Name -ne $item.Name -and (Test-DevboxFolderCovers -Outer $_.Relative -Inner $item.Relative) -and -not (Test-DevboxFolderCovers -Outer $item.Relative -Inner $_.Relative) }) })
        foreach ($item in $top) {
            $current = @(Get-DevboxProjectSessions -Container $Container -User $user)
            $fresh = @($current | Where-Object { $_.Name -eq $item.Name })[0]
            if (-not (Enable-DevboxFolderSession -Target $fresh -Sessions $current -Flush:$Flush)) { $ok = $false }
        }
        $result.Ok = $ok
        $result.Active = $ok
        return $result
    }

    if ($choice -eq $addItem) {
        $typed = Read-Host 'Folder to add (relative to the host projects folder, or absolute inside it; empty cancels)'
        if (-not $typed -or -not $typed.Trim()) {
            Write-Host 'Cancelled: nothing was changed.'
            return $result
        }
        $resolved = Resolve-DevboxSyncFolder -HostPath $hostPath -Folder $typed
        if ($resolved.Error) {
            Write-DevboxWarning "Error: '$typed': $($resolved.Error)"
            return (& $fail)
        }
        $existing = @($sessions | Where-Object { $_.Relative.ToLowerInvariant() -eq $resolved.Relative.ToLowerInvariant() })
        if ($existing.Count -gt 0) { $target = $existing[0] }
        else {
            $activeCover = @($sessions | Where-Object { -not $_.Paused -and (Test-DevboxFolderCovers -Outer $_.Relative -Inner $resolved.Relative) })
            if ($activeCover.Count -gt 0) {
                Write-Host "'$($resolved.Relative)' is already synchronized by the active session '$($activeCover[0].Name)': nothing was created."
                $result.Active = $true
                return $result
            }
            $target = New-DevboxFolderSession -Container $Container -User $user -Relative $resolved.Relative -Full $resolved.Full
            if (-not $target) { return (& $fail) }
        }
    } else {
        $target = $byLabel[$choice]
    }
    $current = @(Get-DevboxProjectSessions -Container $Container -User $user)
    $fresh = @($current | Where-Object { $_.Name -eq $target.Name })
    if ($fresh.Count -gt 0) { $target = $fresh[0] }
    if (-not (Enable-DevboxFolderSession -Target $target -Sessions $current -Flush:$Flush)) { return (& $fail) }
    $result.Active = $true
    return $result
}

# Terminate one Mutagen session (the host folder is not touched). It never starts the daemon:
# when Mutagen or its daemon is not running, the session is left for dkdb-mutagen-clean.
function Remove-DevboxSyncSession {
    param([string]$SessionName)
    if (-not $SessionName) {
        Write-DevboxWarning 'Warning: the Mutagen session name is unknown; run dkdb-mutagen-clean to look for leftover sessions.'
        return
    }
    if (-not (Test-DevboxMutagen) -or -not (Test-DevboxMutagenDaemon)) {
        Write-DevboxWarning "Warning: the Mutagen daemon is not running, so the session '$SessionName' was not terminated. Run dkdb-mutagen-clean later."
        return
    }
    & (Get-DevboxMutagenExe) sync terminate $SessionName *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-DevboxWarning "Warning: could not terminate the Mutagen session '$SessionName'. Run dkdb-mutagen-clean later."
        return
    }
    Write-DevboxSuccess "Mutagen session terminated: $SessionName"
}
