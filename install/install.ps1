# Installer for docker-devbox-ubuntu. Download only this file and run it.
# It downloads scripts/bash, scripts/ps1 and scripts/docker from the repository
# into a local folder and adds scripts\ps1 to the user PATH.
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# --- Settings ---
$RepoUrl = 'https://github.com/rmompo/docker-devbox-ubuntu'
$Branch = 'main'
$DefaultInstallPath = 'C:\DataDocker\docker-devbox-ubuntu\'

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

# Raw URL of the repository: https://github.com/<user>/<repo> -> raw.githubusercontent.com/<user>/<repo>
if ($RepoUrl.TrimEnd('/') -notmatch '^https://github\.com/([^/]+/[^/]+)$') {
    Stop-Install "RepoUrl is not a valid GitHub repository URL: $RepoUrl"
}
$rawBase = "https://raw.githubusercontent.com/$($Matches[1])/$Branch"

# --- Ask for the install path and check it ---
$installPath = Read-Host "Install path [$DefaultInstallPath]"
if ([string]::IsNullOrWhiteSpace($installPath)) { $installPath = $DefaultInstallPath }
$installPath = $installPath.Trim().Replace('/', '\').TrimEnd('\')

if ($installPath.Contains(',')) { Stop-Install "The path must not contain commas: $installPath" }
if (-not [System.IO.Path]::IsPathRooted($installPath)) { Stop-Install "The path must be absolute (for example C:\DataDocker): $installPath" }

if (-not (Test-Path -LiteralPath $installPath -PathType Container)) {
    if (-not (Confirm-Install "The path does not exist: $installPath. Create it?")) {
        Stop-Install 'The install path does not exist and was not created.'
    }
    try {
        New-Item -ItemType Directory -Path $installPath | Out-Null
    } catch {
        Stop-Install "Could not create the path $installPath ($($_.Exception.Message))"
    }
}
$installPath = (Resolve-Path -LiteralPath $installPath).Path

# --- Previous installation ---
$scriptsPath = Join-Path $installPath 'scripts'
if (Test-Path -LiteralPath $scriptsPath) {
    Write-Host "An installation already exists in $scriptsPath." -ForegroundColor Yellow
    Write-Host 'Files will be overwritten (manual edits are lost); files that no longer exist in the repository are not deleted.' -ForegroundColor Yellow
    if (-not (Confirm-Install 'Continue?')) { Stop-Install 'Cancelled by the user.' }
}

# --- Download ---
Write-Host "Downloading from $RepoUrl ($Branch) ..."
foreach ($file in $Files) {
    $target = Join-Path $installPath ($file.Replace('/', '\'))
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
$oldFound = @($OldFiles | ForEach-Object { Join-Path $installPath ($_.Replace('/', '\')) } |
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

# --- User PATH ---
$ps1Path = Join-Path $scriptsPath 'ps1'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @()
if (-not [string]::IsNullOrEmpty($userPath)) {
    $entries = @($userPath -split ';' | Where-Object { $_ -ne '' })
}
$alreadyInPath = $entries | Where-Object { $_.TrimEnd('\') -ieq $ps1Path.TrimEnd('\') }
if ($alreadyInPath) {
    Write-Host "PATH (user) already contains $ps1Path"
} else {
    [Environment]::SetEnvironmentVariable('Path', (($entries + $ps1Path) -join ';'), 'User')
    Write-Host "Added to the user PATH: $ps1Path"
}
# Also make it available in this session.
$sessionEntries = @($env:Path -split ';' | Where-Object { $_ -ne '' })
if (-not ($sessionEntries | Where-Object { $_.TrimEnd('\') -ieq $ps1Path.TrimEnd('\') })) {
    $env:Path = "$env:Path;$ps1Path"
}

# --- Execution policy (warn only, never change it) ---
$policy = Get-ExecutionPolicy
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Host "Warning: the execution policy is '$policy' and the scripts will not run." -ForegroundColor Yellow
    Write-Host 'Fix (current user only): Set-ExecutionPolicy RemoteSigned -Scope CurrentUser' -ForegroundColor Yellow
}

Write-Host ''
Write-Host "Installed in $installPath" -ForegroundColor Green
Write-Host 'Open a new terminal (so the PATH is refreshed) and run: dkdb-image-create'
