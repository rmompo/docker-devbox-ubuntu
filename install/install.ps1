# Installer for docker-devbox-ubuntu. Download only this file and run it.
# It downloads scripts/bash, scripts/ps1 and scripts/docker from the repository
# into <root>\devbox, creates <root>\tools and adds devbox\scripts\ps1 to the user PATH.
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# --- Settings ---
$RepoUrl = 'https://github.com/rmompo/docker-devbox-ubuntu'
$Branch = 'main'
# Shared root: <root>\devbox holds the scripts, <root>\tools the shared tools (spec 07).
$DefaultRootPath = 'C:\shared\'

# Every file to download, relative to the repository root. Keep it in sync with
# the repository: a file missing from this list is NOT installed (spec 07).
$Files = @(
    'scripts/bash/dkdb-install-claudecode.sh'
    'scripts/bash/dkdb-install-ghcopilot-cli.sh'
    'scripts/docker/Dockerfile'
    'scripts/docker/entrypoint.sh'
    'scripts/ps1/dkdb-common.ps1'
    'scripts/ps1/dkdb-container-connect.ps1'
    'scripts/ps1/dkdb-container-create.ps1'
    'scripts/ps1/dkdb-container-delete.ps1'
    'scripts/ps1/dkdb-container-start.ps1'
    'scripts/ps1/dkdb-container-stop.ps1'
    'scripts/ps1/dkdb-image-create.ps1'
    'scripts/ps1/dkdb-image-delete.ps1'
    'scripts/ps1/dkdb-mutagen-start.ps1'
    'scripts/ps1/dkdb-mutagen-stop.ps1'
)

# Files installed by earlier versions under their old names (before the dkdb-
# prefix). They are offered for removal after the download; nothing else is deleted.
$OldFiles = @(
    'scripts/bash/install-claudecode.sh'
    'scripts/bash/install-ghcopilot-cli.sh'
    'scripts/ps1/common.ps1'
    'scripts/ps1/container-connect.ps1'
    'scripts/ps1/container-create.ps1'
    'scripts/ps1/container-delete.ps1'
    'scripts/ps1/container-start.ps1'
    'scripts/ps1/container-stop.ps1'
    'scripts/ps1/image-create.ps1'
    'scripts/ps1/image-delete.ps1'
    'scripts/ps1/scripts-update.ps1'
)

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

# Raw URL of the repository: https://github.com/<user>/<repo> -> raw.githubusercontent.com/<user>/<repo>
if ($RepoUrl.TrimEnd('/') -notmatch '^https://github\.com/([^/]+/[^/]+)$') {
    Stop-Install "RepoUrl is not a valid GitHub repository URL: $RepoUrl"
}
$rawBase = "https://raw.githubusercontent.com/$($Matches[1])/$Branch"

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

# --- Download ---
Write-Host "Downloading from $RepoUrl ($Branch) ..."
foreach ($file in $Files) {
    $target = Join-Path $devboxPath ($file.Replace('/', '\'))
    $targetDir = Split-Path -Parent $target
    try {
        if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
            New-Item -ItemType Directory -Path $targetDir | Out-Null
        }
        # Bytes are saved as they are, so LF line endings are preserved.
        Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/$file" -OutFile $target
    } catch {
        Stop-Install "Could not download $file ($($_.Exception.Message)). Is the repository public?"
    }
    if (-not (Test-Path -LiteralPath $target) -or (Get-Item -LiteralPath $target).Length -eq 0) {
        Stop-Install "The downloaded file is missing or empty: $file"
    }
    if ($target -like '*.ps1') { Unblock-File -LiteralPath $target }
    Write-Host "  $file"
}

# --- Old files from earlier versions (removed only after confirmation) ---
$oldFound = @($OldFiles | ForEach-Object { Join-Path $devboxPath ($_.Replace('/', '\')) } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($oldFound.Count -gt 0) {
    Write-Host 'Files from an earlier version were found (now replaced by dkdb-* files):' -ForegroundColor Yellow
    $oldFound | ForEach-Object { Write-Host "  $_" }
    if (Confirm-Install 'Delete them?') {
        $oldFound | ForEach-Object { Remove-Item -LiteralPath $_ -Force }
        Write-Host 'Old files deleted.'
    } else {
        Write-Host 'Old files kept (delete them by hand to avoid duplicated commands).' -ForegroundColor Yellow
    }
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
Write-Host "Installed in $devboxPath (shared tools folder: $toolsPath)" -ForegroundColor Green
Write-Host 'Open a new terminal (so the PATH is refreshed) and run: dkdb-image-create'
