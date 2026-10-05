# Uninstaller for docker-devbox-ubuntu. Run it from <root>\devbox\install\.
# It removes <root>\devbox\scripts and <root>\devbox\mutagen and their user PATH entries.
# It never touches <root>\tools, your projects, containers, images or Docker.
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

$ErrorActionPreference = 'Stop'

function Stop-Uninstall {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "Error: $Message" -ForegroundColor Red
    Write-Host 'Uninstall stopped.' -ForegroundColor Red
    exit 1
}

function Confirm-Uninstall {
    param([Parameter(Mandatory)][string]$Question)
    $answer = Read-Host "$Question [y/N]"
    return ($answer.Trim() -match '^(y|yes)$')
}

# Remove a folder from the user PATH (registry) and from this session.
function Remove-UninstallUserPath {
    param([Parameter(Mandatory)][string]$Folder)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not [string]::IsNullOrEmpty($userPath)) {
        $entries = @($userPath -split ';' | Where-Object { $_ -ne '' })
        $kept = @($entries | Where-Object { $_.TrimEnd('\') -ine $Folder.TrimEnd('\') })
        if ($kept.Count -ne $entries.Count) {
            [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
            Write-Host "Removed from the user PATH: $Folder"
        }
    }
    $env:Path = (@($env:Path -split ';' | Where-Object { $_ -ne '' -and $_.TrimEnd('\') -ine $Folder.TrimEnd('\') }) -join ';')
}

# This script lives in <root>\devbox\install.
$installDir = $PSScriptRoot
$devboxPath = Split-Path -Parent $installDir
if ((Split-Path -Leaf $installDir) -ine 'install' -or (Split-Path -Leaf $devboxPath) -ine 'devbox') {
    Stop-Uninstall "Run this script from <root>\devbox\install (found: $installDir)."
}
$scriptsPath = Join-Path $devboxPath 'scripts'
$ps1Path = Join-Path $scriptsPath 'ps1'
$mutagenPath = Join-Path $devboxPath 'mutagen'
$mutagenExe = Join-Path $mutagenPath 'mutagen.exe'

Write-Host 'This will remove:'
Write-Host "  - the user PATH entries $ps1Path and $mutagenPath (if present)"
if (Test-Path -LiteralPath $scriptsPath) { Write-Host "  - the folder $scriptsPath" }
if (Test-Path -LiteralPath $mutagenPath) { Write-Host "  - the folder $mutagenPath (Mutagen)" }
Write-Host 'It keeps: this install folder, the tools folder, your projects, containers and images.'
if (-not (Confirm-Uninstall 'Uninstall?')) { Stop-Uninstall 'Cancelled by the user.' }

# A running Mutagen daemon locks mutagen.exe.
$removeMutagen = Test-Path -LiteralPath $mutagenPath
if (Test-Path -LiteralPath $mutagenExe) {
    $previous = $env:MUTAGEN_DISABLE_AUTOSTART
    $env:MUTAGEN_DISABLE_AUTOSTART = '1'
    try {
        & $mutagenExe sync list *> $null
        $daemonRunning = ($LASTEXITCODE -eq 0)
    } finally {
        if ($null -eq $previous) { Remove-Item Env:MUTAGEN_DISABLE_AUTOSTART -ErrorAction SilentlyContinue }
        else { $env:MUTAGEN_DISABLE_AUTOSTART = $previous }
    }
    if ($daemonRunning) {
        Write-Host 'The Mutagen daemon is running and must stop to remove Mutagen. This stops ALL your Mutagen sessions.' -ForegroundColor Yellow
        if (Confirm-Uninstall 'Stop the Mutagen daemon?') {
            & $mutagenExe daemon stop | Out-Null
        } else {
            $removeMutagen = $false
            Write-Host 'Mutagen is kept.' -ForegroundColor Yellow
        }
    }
}

Remove-UninstallUserPath -Folder $ps1Path
if ($removeMutagen) { Remove-UninstallUserPath -Folder $mutagenPath }

foreach ($folder in @($scriptsPath, $(if ($removeMutagen) { $mutagenPath }))) {
    if ($folder -and (Test-Path -LiteralPath $folder)) {
        try {
            Remove-Item -LiteralPath $folder -Recurse -Force
            Write-Host "Removed $folder"
        } catch {
            Stop-Uninstall "Could not remove $folder ($($_.Exception.Message))"
        }
    }
}

Write-Host ''
Write-Host 'Uninstalled.' -ForegroundColor Green
Write-Host "Kept: $installDir (delete $devboxPath by hand to remove it completely), the tools folder and your projects."
