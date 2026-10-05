# Uninstaller for docker-devbox-ubuntu. Run it from <root>\devbox\install\.
# Version: 0.1.3
# It removes <root>\devbox\scripts and <root>\devbox\mutagen and their user PATH entries.
# It never touches <root>\tools, your projects, containers, images or Docker.
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Message colors (spec 01): success (something was done correctly) in green, warnings and errors in red,
# the natural next step in yellow. Other messages keep the default color.
function Write-UninstallSuccess {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Green
}
function Write-UninstallWarning {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Red
}
function Write-UninstallNext {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Yellow
}

# Project version from <root>\devbox\manifest.json ('unknown' when it cannot be read).
function Get-UninstallVersion {
    param([Parameter(Mandatory)][string]$ManifestPath)
    try {
        $version = (Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json).version
        if ($version) { return [string]$version }
    } catch { $version = $null }
    return 'unknown'
}

function Stop-Uninstall {
    param([Parameter(Mandatory)][string]$Message)
    Write-UninstallWarning "Error: $Message"
    Write-UninstallWarning 'Uninstall stopped.'
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
            Write-UninstallSuccess "Removed from the user PATH: $Folder"
        }
    }
    $env:Path = (@($env:Path -split ';' | Where-Object { $_ -ne '' -and $_.TrimEnd('\') -ine $Folder.TrimEnd('\') }) -join ';')
}

# --- Help (-Help): same layout as the dkdb-* scripts (spec 01) ---
function Get-UninstallWrappedLines {
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

function Show-UninstallHelp {
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
    $parameters = @(@{ Name = '-Help'; Description = 'Show this help and exit.' })
    if ($VersionLine) { Write-Host $VersionLine -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host 'NAME' -ForegroundColor Cyan
    Write-Host "    $Name" -ForegroundColor Green
    Write-Host ''
    Write-Host 'DESCRIPTION' -ForegroundColor Cyan
    foreach ($line in (Get-UninstallWrappedLines -Text $Description -Width ($width - 4))) { Write-Host "    $line" }
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
            foreach ($line in (Get-UninstallWrappedLines -Text $example.Description -Width ($width - 8))) { Write-Host "        $line" }
        }
    }
    if ($Notes.Count -gt 0) {
        Write-Host ''
        Write-Host 'NOTES' -ForegroundColor Cyan
        foreach ($note in $Notes) {
            $lines = @(Get-UninstallWrappedLines -Text $note -Width ($width - 6))
            Write-Host "    - $($lines[0])"
            foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host "      $line" }
        }
    }
    Write-Host ''
}

if ($Help) {
    $helpVersion = 'unknown'
    foreach ($line in (Get-Content -LiteralPath $PSCommandPath -TotalCount 15)) {
        if ($line -match '^#\s*Version:\s*(\d+\.\d+\.\d+)\s*$') { $helpVersion = $Matches[1]; break }
    }
    Show-UninstallHelp -Name 'uninstall.ps1' `
        -VersionLine "uninstall $helpVersion (docker-devbox-ubuntu uninstaller)" `
        -Description 'Removes the scripts and Mutagen of this installation (<root>\devbox\scripts and <root>\devbox\mutagen) and their user PATH entries, after asking for confirmation. It keeps this install folder, the tools folder, your projects, containers and images.' `
        -Usage 'uninstall.ps1 [-Help]' `
        -Examples @(
            @{ Command = '& "C:\shared\devbox\install\uninstall.ps1"'; Description = 'Lists what will be removed and asks before doing it.' }
        ) `
        -Notes @(
            'Run it from <root>\devbox\install.',
            'If the Mutagen daemon is running it asks before stopping it (that stops all your Mutagen sessions).'
        )
    exit 0
}

# This script lives in <root>\devbox\install.
$installDir = $PSScriptRoot
$devboxPath = Split-Path -Parent $installDir
if ((Split-Path -Leaf $installDir) -ine 'install' -or (Split-Path -Leaf $devboxPath) -ine 'devbox') {
    Stop-Uninstall "Run this script from <root>\devbox\install (found: $installDir)."
}
$scriptsPath = Join-Path $devboxPath 'scripts'
$ownVersion = 'unknown'
foreach ($line in (Get-Content -LiteralPath $PSCommandPath -TotalCount 15)) {
    if ($line -match '^#\s*Version:\s*(\d+\.\d+\.\d+)\s*$') { $ownVersion = $Matches[1]; break }
}
Write-Host "uninstall $ownVersion (docker-devbox-ubuntu $(Get-UninstallVersion -ManifestPath (Join-Path $devboxPath 'manifest.json')))" -ForegroundColor DarkGray
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
        Write-UninstallWarning 'The Mutagen daemon is running and must stop to remove Mutagen. This stops ALL your Mutagen sessions.'
        if (Confirm-Uninstall 'Stop the Mutagen daemon?') {
            & $mutagenExe daemon stop | Out-Null
        } else {
            $removeMutagen = $false
            Write-UninstallWarning 'Mutagen is kept.'
        }
    }
}

Remove-UninstallUserPath -Folder $ps1Path
if ($removeMutagen) { Remove-UninstallUserPath -Folder $mutagenPath }

foreach ($folder in @($scriptsPath, $(if ($removeMutagen) { $mutagenPath }))) {
    if ($folder -and (Test-Path -LiteralPath $folder)) {
        try {
            Remove-Item -LiteralPath $folder -Recurse -Force
            Write-UninstallSuccess "Removed $folder"
        } catch {
            Stop-Uninstall "Could not remove $folder ($($_.Exception.Message))"
        }
    }
}

Write-Host ''
Write-UninstallSuccess 'Uninstalled.'
Write-Host "Kept: $installDir (delete $devboxPath by hand to remove it completely), the tools folder and your projects."
Write-UninstallNext 'Next: open a new terminal so that the PATH is refreshed. To install again, download install.ps1 as the README says.'
