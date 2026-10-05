# Installer for docker-devbox-ubuntu. Download only this file and run it.
# Version: 0.2.0
# It downloads manifest.json and every file it lists (scripts and uninstall.ps1) from the
# repository into <root>\devbox, creates <root>\tools and adds devbox\scripts\ps1 to the user PATH.
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)

# --- Settings ---
$RepoUrl = 'https://github.com/rmompo/docker-devbox-ubuntu'
$DefaultBranch = 'main'
# Shared root: <root>\devbox holds the scripts, <root>\tools the shared tools (spec 07).
$DefaultRootPath = 'C:\shared\'

$ErrorActionPreference = 'Stop'

# Message colors (spec 01): success (something was done correctly) in green, warnings and errors in red,
# the natural next step in yellow. Other messages keep the default color.
function Write-InstallSuccess {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Green
}
function Write-InstallWarning {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Red
}
function Write-InstallNext {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Yellow
}

function Stop-Install {
    param([Parameter(Mandatory)][string]$Message)
    Write-InstallWarning "Error: $Message"
    Write-InstallWarning 'Installation stopped.'
    exit 1
}

function Confirm-Install {
    param([Parameter(Mandatory)][string]$Question)
    $answer = Read-Host "$Question [y/N]"
    return ($answer.Trim() -match '^(y|yes)$')
}

# Add a folder to the user PATH (registry) and to this session, without duplicates.
function Add-InstallUserPath {
    param([Parameter(Mandatory)][string]$Folder)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if (-not [string]::IsNullOrEmpty($userPath)) {
        $entries = @($userPath -split ';' | Where-Object { $_ -ne '' })
    }
    if ($entries | Where-Object { $_.TrimEnd('\') -ieq $Folder.TrimEnd('\') }) {
        Write-Host "PATH (user) already contains $Folder"
    } else {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $Folder) -join ';'), 'User')
        Write-InstallSuccess "Added to the user PATH: $Folder"
    }
    $sessionEntries = @($env:Path -split ';' | Where-Object { $_ -ne '' })
    if (-not ($sessionEntries | Where-Object { $_.TrimEnd('\') -ieq $Folder.TrimEnd('\') })) {
        $env:Path = "$env:Path;$Folder"
    }
}

# Version of a file: the '# Version: x.y.z' line in its first lines ($null when absent).
function Get-InstallFileVersion {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $Path -TotalCount 15)) {
        if ($line -match '^#\s*Version:\s*(\d+\.\d+\.\d+)\s*$') { return $Matches[1] }
    }
    return $null
}

# Project version from a manifest.json ('unknown' when it cannot be read).
function Get-InstallVersion {
    param([Parameter(Mandatory)][string]$ManifestPath)
    try {
        $version = (Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json).version
        if ($version) { return [string]$version }
    } catch { $version = $null }
    return 'unknown'
}

# Compatible versions share major.minor (0.x) or major (1.0 and later); same rule as dkdb-common.ps1.
function Test-InstallVersionCompatible {
    param([string]$Left, [string]$Right)
    $a = $null
    $b = $null
    if (-not [version]::TryParse($Left, [ref]$a) -or -not [version]::TryParse($Right, [ref]$b)) { return $false }
    if ($a.Major -eq 0 -and $b.Major -eq 0) { return ($a.Minor -eq $b.Minor) }
    return ($a.Major -eq $b.Major)
}

# --- Help (-Help): same layout as the dkdb-* scripts (spec 01) ---
function Get-InstallWrappedLines {
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

function Show-InstallHelp {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Usage,
        [object[]]$Examples = @(),
        [string[]]$Notes = @(),
        [string]$VersionLine = ''
    )
    $width = 100
    try {
        $window = $Host.UI.RawUI.WindowSize.Width
        if ($window -ge 60) { $width = [math]::Min($window - 1, 110) }
    } catch { $width = 100 }
    $parameters = @(@{ Name = '-Help'; Description = 'Show this help and exit.' }, @{ Name = '-Man'; Description = 'Show the manual (what the script does, step by step) and exit.' })
    if ($VersionLine) { Write-Host $VersionLine -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host 'NAME' -ForegroundColor Cyan
    Write-Host "    $Name" -ForegroundColor Green
    Write-Host ''
    Write-Host 'DESCRIPTION' -ForegroundColor Cyan
    foreach ($line in (Get-InstallWrappedLines -Text $Description -Width ($width - 4))) { Write-Host "    $line" }
    Write-Host ''
    Write-Host 'USAGE' -ForegroundColor Cyan
    Write-Host "    $Usage" -ForegroundColor Green
    Write-Host ''
    Write-Host 'PARAMETERS' -ForegroundColor Cyan
    $nameWidth = ($parameters | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 3
    foreach ($parameter in $parameters) {
        Write-Host ('    ' + $parameter.Name.PadRight($nameWidth)) -NoNewline -ForegroundColor Green
        Write-Host $parameter.Description
    }
    if ($Examples.Count -gt 0) {
        Write-Host ''
        Write-Host 'EXAMPLES' -ForegroundColor Cyan
        foreach ($example in $Examples) {
            Write-Host "    $($example.Command)" -ForegroundColor Green
            foreach ($line in (Get-InstallWrappedLines -Text $example.Description -Width ($width - 8))) { Write-Host "        $line" }
        }
    }
    if ($Notes.Count -gt 0) {
        Write-Host ''
        Write-Host 'NOTES' -ForegroundColor Cyan
        foreach ($note in $Notes) {
            $lines = @(Get-InstallWrappedLines -Text $note -Width ($width - 6))
            Write-Host "    - $($lines[0])"
            foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host "      $line" }
        }
    }
    Write-Host ''
}

# Manual (-Man): what the script does, in colors (same layout as the dkdb-* scripts, spec 01).
function Show-InstallMan {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Purpose,
        [string[]]$Needs = @(),
        [string[]]$Steps = @(),
        [string[]]$Changes = @(),
        [string[]]$Never = @(),
        [string]$Next = ''
    )
    $width = 100
    try {
        $window = $Host.UI.RawUI.WindowSize.Width
        if ($window -ge 60) { $width = [math]::Min($window - 1, 110) }
    } catch { $width = 100 }
    Write-Host ''
    Write-Host 'MANUAL' -ForegroundColor Cyan
    Write-Host "    $Name" -ForegroundColor Green
    Write-Host ''
    Write-Host 'PURPOSE' -ForegroundColor Cyan
    foreach ($line in (Get-InstallWrappedLines -Text $Purpose -Width ($width - 4))) { Write-Host "    $line" }
    $sections = @(
        @{ Title = 'REQUIREMENTS'; Items = $Needs; Numbered = $false },
        @{ Title = 'WHAT IT DOES'; Items = $Steps; Numbered = $true },
        @{ Title = 'WHAT IT CHANGES'; Items = $Changes; Numbered = $false },
        @{ Title = 'WHAT IT NEVER DOES'; Items = $Never; Numbered = $false }
    )
    foreach ($section in $sections) {
        if (@($section.Items).Count -eq 0) { continue }
        Write-Host ''
        Write-Host $section.Title -ForegroundColor Cyan
        $number = 0
        foreach ($item in $section.Items) {
            $number++
            $marker = if ($section.Numbered) { ('{0,2}. ' -f $number) } else { '  - ' }
            $lines = @(Get-InstallWrappedLines -Text $item -Width ($width - 8))
            Write-Host '    ' -NoNewline
            Write-Host $marker -NoNewline -ForegroundColor Green
            Write-Host $lines[0]
            foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host ('        ' + $line) }
        }
    }
    if ($Next) {
        Write-Host ''
        Write-Host 'NEXT STEP' -ForegroundColor Cyan
        foreach ($line in (Get-InstallWrappedLines -Text $Next -Width ($width - 4))) { Write-Host "    $line" -ForegroundColor Yellow }
    }
    Write-Host ''
}

$selfVersion = Get-InstallFileVersion -Path $PSCommandPath
if (-not $selfVersion) { $selfVersion = 'unknown' }
Write-Host "install $selfVersion (docker-devbox-ubuntu installer)" -ForegroundColor DarkGray
if ($Help) {
    Show-InstallHelp -Name 'install.ps1' `
        -Description 'Installs docker-devbox-ubuntu: downloads manifest.json and every file it lists into <root>\devbox, creates <root>\tools and adds <root>\devbox\scripts\ps1 to the user PATH. It asks for the shared root and for the branch or tag to download.' `
        -Usage 'install.ps1 [-Help]' `
        -Examples @(
            @{ Command = '& "C:\shared\devbox\install\install.ps1"'; Description = 'Installs from the console where you run it (the PATH is already updated there).' },
            @{ Command = 'powershell -ExecutionPolicy Bypass -File "C:\shared\devbox\install\install.ps1"'; Description = 'Same, from a console where scripts are blocked by the execution policy.' }
        ) `
        -Notes @(
            'The default shared root is C:\shared\ and the default branch is main; both are asked.',
            'Run it again to update: it asks before overwriting an existing installation.',
            'Nothing needs administrator rights: only the user PATH is changed.'
        )
    exit 0
}
if ($Man) {
    Show-InstallMan -Name 'install.ps1' `
        -Purpose 'Installs docker-devbox-ubuntu from its GitHub repository without cloning it: you only download this file.' `
        -Needs @(
            'Internet access to raw.githubusercontent.com (the repository is public).',
            'Windows PowerShell 5.1 or PowerShell 7. No administrator rights.'
        ) `
        -Steps @(
            'Asks for the shared root (default C:\shared\): it must be absolute and without commas; when it does not exist it asks before creating it, and stops if it cannot.',
            'Asks for the branch or tag to download (default main).',
            'Downloads manifest.json first and prints the version; when the major.minor of the previous installation changed, it says to rebuild the images and recreate the containers.',
            'If there is an installation, warns that its files are overwritten and asks [y/N].',
            'Downloads every file listed in the manifest into <root>\devbox, checks that the Version header of each equals the manifest (otherwise it stops) and unblocks the .ps1 files.',
            'Creates <root>\tools when it is missing.',
            'Adds <root>\devbox\scripts\ps1 to the user PATH without duplicates; other entries from a previous installation are removed only after you confirm.',
            'Warns, without changing it, when the execution policy is Restricted or AllSigned.'
        ) `
        -Changes @(
            'The files under <root>\devbox.',
            'The folder <root>\tools, when it was missing.',
            'The user PATH.'
        ) `
        -Never @(
            'Needs administrator rights.',
            'Installs Docker or Mutagen (dkdb-container-create installs Mutagen on demand).',
            'Changes the execution policy or stores the root path (the scripts deduce it from their location).',
            'Deletes your projects, containers or images.'
        ) `
        -Next 'Make sure Docker Engine is running, open a new terminal and run dkdb-image-create.'
    exit 0
}

# The repository URL must be a GitHub one (the files are downloaded from raw.githubusercontent.com).
if ($RepoUrl.TrimEnd('/') -match '^https://github\.com/([^/]+/[^/]+)$') {
    $repoSlug = $Matches[1]
} else {
    Stop-Install "RepoUrl is not a valid GitHub repository URL: $RepoUrl"
}

# --- Ask for the shared root and check it ---
$rootPath = Read-Host "Shared root path [$DefaultRootPath]"
if ([string]::IsNullOrWhiteSpace($rootPath)) { $rootPath = $DefaultRootPath }
$rootPath = $rootPath.Trim().Replace('/', '\').TrimEnd('\')

if ($rootPath.Contains(',')) { Stop-Install "The path must not contain commas: $rootPath" }
if (-not [System.IO.Path]::IsPathRooted($rootPath)) { Stop-Install "The path must be absolute (for example C:\shared): $rootPath" }

if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    if (-not (Confirm-Install "The path does not exist: $rootPath. Create it?")) {
        Stop-Install 'The shared root does not exist and was not created.'
    }
    try {
        New-Item -ItemType Directory -Path $rootPath | Out-Null
    } catch {
        Stop-Install "Could not create the path $rootPath ($($_.Exception.Message))"
    }
}
$rootPath = (Resolve-Path -LiteralPath $rootPath).Path
$devboxPath = Join-Path $rootPath 'devbox'
$scriptsPath = Join-Path $devboxPath 'scripts'
$toolsPath = Join-Path $rootPath 'tools'

# --- Previous installation ---
if (Test-Path -LiteralPath $scriptsPath) {
    Write-InstallWarning "An installation already exists in $scriptsPath."
    Write-InstallWarning 'Files will be overwritten (manual edits are lost); files that no longer exist in the repository are not deleted.'
    if (-not (Confirm-Install 'Continue?')) { Stop-Install 'Cancelled by the user.' }
}

# --- Branch or tag ---
$Branch = Read-Host "Branch or tag to download [$DefaultBranch]"
if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = $DefaultBranch }
$Branch = $Branch.Trim()
if ($Branch -notmatch '^[A-Za-z0-9._/-]+$') { Stop-Install "Invalid branch or tag name: $Branch" }
$rawBase = "https://raw.githubusercontent.com/$repoSlug/$Branch"

# --- Previous version (to tell whether images and containers must be rebuilt) ---
$manifestPath = Join-Path $devboxPath 'manifest.json'
$previousVersion = $null
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $previousVersion = Get-InstallVersion -ManifestPath $manifestPath
    if ($previousVersion -eq 'unknown') { $previousVersion = $null }
}

# Download one repository file into <root>\devbox, keeping its relative path.
function Save-InstallFile {
    param([Parameter(Mandatory)][string]$Relative)
    $target = Join-Path $devboxPath ($Relative.Replace('/', '\'))
    $targetDir = Split-Path -Parent $target
    try {
        if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
            New-Item -ItemType Directory -Path $targetDir | Out-Null
        }
        # Bytes are saved as they are, so LF line endings are preserved.
        Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/$Relative" -OutFile $target
    } catch {
        Stop-Install "Could not download $Relative ($($_.Exception.Message)). Is the repository public?"
    }
    if (-not (Test-Path -LiteralPath $target) -or (Get-Item -LiteralPath $target).Length -eq 0) {
        Stop-Install "The downloaded file is missing or empty: $Relative"
    }
    if ($target -like '*.ps1') { Unblock-File -LiteralPath $target }
    return $target
}

# --- Download: manifest.json first, then every file it lists ---
Write-Host "Downloading from $RepoUrl ($Branch) ..."
$manifestFile = Save-InstallFile -Relative 'manifest.json'
try {
    $manifest = Get-Content -Raw -LiteralPath $manifestFile | ConvertFrom-Json
} catch {
    Stop-Install 'manifest.json is not valid JSON.'
}
$entries = @()
if ($manifest.files) { $entries = @($manifest.files.PSObject.Properties) }
if ($entries.Count -eq 0) { Stop-Install 'manifest.json does not list any file.' }
$version = Get-InstallVersion -ManifestPath $manifestFile
Write-Host "Version: $version"

foreach ($entry in $entries) {
    $relative = $entry.Name
    # The installer itself was downloaded by hand: only its version is compared.
    if ($relative -eq 'install/install.ps1') {
        if ($selfVersion -ne [string]$entry.Value) {
            Write-InstallWarning "Warning: this installer is version $selfVersion but $Branch expects $($entry.Value). Download install.ps1 again from that branch."
        }
        continue
    }
    $target = Save-InstallFile -Relative $relative
    # Integrity: the version in the file must be the one in the manifest (a mixed or partial download fails here).
    $actual = Get-InstallFileVersion -Path $target
    if ($actual -ne [string]$entry.Value) {
        Stop-Install "Inconsistent download: $relative is version '$actual' but manifest.json says $($entry.Value). Try again in a few minutes (GitHub caches raw files)."
    }
    Write-Host "  $relative ($actual)"
}

# --- Shared tools folder (the default tools path of dkdb-container-create) ---
if (-not (Test-Path -LiteralPath $toolsPath -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $toolsPath | Out-Null
        Write-InstallSuccess "Created $toolsPath"
    } catch {
        Stop-Install "Could not create the tools folder $toolsPath ($($_.Exception.Message))"
    }
}

# --- User PATH ---
$ps1Path = Join-Path $scriptsPath 'ps1'
Add-InstallUserPath -Folder $ps1Path

# User PATH entries of a previous installation (they contain dkdb-common.ps1): offer to remove them.
$currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not [string]::IsNullOrEmpty($currentUserPath)) {
    $userEntries = @($currentUserPath -split ';' | Where-Object { $_ -ne '' })
    $stale = @($userEntries | Where-Object {
        $_.TrimEnd('\') -ine $ps1Path.TrimEnd('\') -and (Test-Path -LiteralPath (Join-Path $_ 'dkdb-common.ps1') -PathType Leaf)
    })
    if ($stale.Count -gt 0) {
        Write-InstallWarning 'The user PATH has entries of a previous installation:'
        $stale | ForEach-Object { Write-Host "  $_" }
        if (Confirm-Install 'Remove them from the user PATH? (the files are not deleted)') {
            $kept = @($userEntries | Where-Object { $stale -notcontains $_ })
            [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
            $env:Path = (@($env:Path -split ';' | Where-Object { $_ -ne '' -and $stale -notcontains $_ }) -join ';')
            Write-InstallSuccess 'Removed from the user PATH.'
        } else {
            Write-InstallWarning 'Kept. Two installations on the PATH may run the wrong scripts.'
        }
    }
}

# --- Execution policy (warn only, never change it) ---
$policy = Get-ExecutionPolicy
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-InstallWarning "Warning: the execution policy is '$policy' and the scripts will not run."
    Write-InstallNext 'Fix (current user only): Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
}

Write-Host ''
Write-InstallSuccess "Installed in $devboxPath (shared tools folder: $toolsPath), version $version"
if ($previousVersion -and -not (Test-InstallVersionCompatible -Left $previousVersion -Right $version)) {
    Write-InstallNext "Updated from ${previousVersion} to ${version}: rebuild the images (dkdb-image-create) and recreate the containers."
}
Write-InstallWarning 'Make sure Docker Engine is running (start Docker Desktop and wait until it is ready).'
Write-InstallNext 'Next: open a new terminal (so the PATH is refreshed) and run: dkdb-image-create'
