# Installer for docker-devbox-ubuntu. Download only this file and run it.
# Version: 0.1.0
# It downloads manifest.json and every file it lists (scripts and uninstall.ps1) from the
# repository into <root>\devbox, creates <root>\tools and adds devbox\scripts\ps1 to the user PATH.
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# --- Settings ---
$RepoUrl = 'https://github.com/rmompo/docker-devbox-ubuntu'
$DefaultBranch = 'main'
# Shared root: <root>\devbox holds the scripts, <root>\tools the shared tools (spec 07).
$DefaultRootPath = 'C:\shared\'

$ErrorActionPreference = 'Stop'

function Stop-Install {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "Error: $Message" -ForegroundColor Red
    Write-Host 'Installation stopped.' -ForegroundColor Red
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
        Write-Host "Added to the user PATH: $Folder"
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

$selfVersion = Get-InstallFileVersion -Path $PSCommandPath
if (-not $selfVersion) { $selfVersion = 'unknown' }
Write-Host "install $selfVersion (docker-devbox-ubuntu installer)" -ForegroundColor DarkGray

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
    Write-Host "An installation already exists in $scriptsPath." -ForegroundColor Yellow
    Write-Host 'Files will be overwritten (manual edits are lost); files that no longer exist in the repository are not deleted.' -ForegroundColor Yellow
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
Write-Host "Version: $version" -ForegroundColor Cyan

foreach ($entry in $entries) {
    $relative = $entry.Name
    # The installer itself was downloaded by hand: only its version is compared.
    if ($relative -eq 'install/install.ps1') {
        if ($selfVersion -ne [string]$entry.Value) {
            Write-Host "Warning: this installer is version $selfVersion but $Branch expects $($entry.Value). Download install.ps1 again from that branch." -ForegroundColor Yellow
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
        Write-Host "Created $toolsPath"
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
        Write-Host 'The user PATH has entries of a previous installation:' -ForegroundColor Yellow
        $stale | ForEach-Object { Write-Host "  $_" }
        if (Confirm-Install 'Remove them from the user PATH? (the files are not deleted)') {
            $kept = @($userEntries | Where-Object { $stale -notcontains $_ })
            [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
            $env:Path = (@($env:Path -split ';' | Where-Object { $_ -ne '' -and $stale -notcontains $_ }) -join ';')
            Write-Host 'Removed from the user PATH.'
        } else {
            Write-Host 'Kept. Two installations on the PATH may run the wrong scripts.' -ForegroundColor Yellow
        }
    }
}

# --- Execution policy (warn only, never change it) ---
$policy = Get-ExecutionPolicy
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Host "Warning: the execution policy is '$policy' and the scripts will not run." -ForegroundColor Yellow
    Write-Host 'Fix (current user only): Set-ExecutionPolicy RemoteSigned -Scope CurrentUser' -ForegroundColor Yellow
}

Write-Host ''
Write-Host "Installed in $devboxPath (shared tools folder: $toolsPath), version $version" -ForegroundColor Green
if ($previousVersion -and -not (Test-InstallVersionCompatible -Left $previousVersion -Right $version)) {
    Write-Host "Updated from ${previousVersion} to ${version}: rebuild the images (dkdb-image-create) and recreate the containers." -ForegroundColor Yellow
}
Write-Host 'Make sure Docker Engine is running (start Docker Desktop and wait until it is ready).' -ForegroundColor Red
Write-Host 'Then open a new terminal (so the PATH is refreshed) and run: dkdb-image-create'
