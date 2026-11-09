# Uninstaller for docker-devbox-ubuntu. Run it from <root>\devbox\install\.
# Version: 0.2.3
# It removes <root>\devbox\scripts and <root>\devbox\mutagen and their user PATH entries.
# It never touches <root>\tools, your projects, containers, images or Docker.
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Colors of the output (spec 01; the same table as dkdb-common.ps1, repeated because this file is downloaded
# on its own): green success, red warnings and errors, yellow the next step, white titles, orange names
# (scripts, commands, parameters), dark gray the version line.
$ColorSuccess = 'Green'
$ColorError = 'Red'
$ColorNext = 'Yellow'
$ColorTitle = 'White'
$ColorName = 'DarkYellow'
$ColorNote = 'DarkGray'
function Write-UninstallSuccess {
    param([string]$Text)
    Write-Host $Text -ForegroundColor $ColorSuccess
}
function Write-UninstallWarning {
    param([string]$Text)
    Write-Host $Text -ForegroundColor $ColorError
}
function Write-UninstallNext {
    param([string]$Text)
    Write-Host $Text -ForegroundColor $ColorNext
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
    $parameters = @(@{ Name = '-Help'; Description = 'Show this help and exit.' }, @{ Name = '-Man'; Description = 'Show the manual (what the script does, step by step) and exit.' })
    if ($VersionLine) { Write-Host $VersionLine -ForegroundColor $ColorNote }
    Write-Host ''
    Write-Host 'NAME' -ForegroundColor $ColorTitle
    Write-Host "    $Name" -ForegroundColor $ColorName
    Write-Host ''
    Write-Host 'DESCRIPTION' -ForegroundColor $ColorTitle
    foreach ($line in (Get-UninstallWrappedLines -Text $Description -Width ($width - 4))) { Write-Host "    $line" }
    Write-Host ''
    Write-Host 'USAGE' -ForegroundColor $ColorTitle
    Write-Host "    $Usage" -ForegroundColor $ColorName
    Write-Host ''
    Write-Host 'PARAMETERS' -ForegroundColor $ColorTitle
    $nameWidth = ($parameters | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 3
    foreach ($parameter in $parameters) {
        Write-Host ('    ' + $parameter.Name.PadRight($nameWidth)) -NoNewline -ForegroundColor $ColorName
        Write-Host $parameter.Description
    }
    if ($Examples.Count -gt 0) {
        Write-Host ''
        Write-Host 'EXAMPLES' -ForegroundColor $ColorTitle
        foreach ($example in $Examples) {
            Write-Host "    $($example.Command)" -ForegroundColor $ColorName
            foreach ($line in (Get-UninstallWrappedLines -Text $example.Description -Width ($width - 8))) { Write-Host "        $line" }
        }
    }
    if ($Notes.Count -gt 0) {
        Write-Host ''
        Write-Host 'NOTES' -ForegroundColor $ColorTitle
        foreach ($note in $Notes) {
            $lines = @(Get-UninstallWrappedLines -Text $note -Width ($width - 6))
            Write-Host "    - $($lines[0])"
            foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host "      $line" }
        }
    }
    Write-Host ''
}

# Manual (-Man): what the script does, in colors (same layout as the dkdb-* scripts, spec 01).
function Show-UninstallMan {
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
    Write-Host 'MANUAL' -ForegroundColor $ColorTitle
    Write-Host "    $Name" -ForegroundColor $ColorName
    Write-Host ''
    Write-Host 'PURPOSE' -ForegroundColor $ColorTitle
    foreach ($line in (Get-UninstallWrappedLines -Text $Purpose -Width ($width - 4))) { Write-Host "    $line" }
    $sections = @(
        @{ Title = 'REQUIREMENTS'; Items = $Needs; Numbered = $false },
        @{ Title = 'WHAT IT DOES'; Items = $Steps; Numbered = $true },
        @{ Title = 'WHAT IT CHANGES'; Items = $Changes; Numbered = $false },
        @{ Title = 'WHAT IT NEVER DOES'; Items = $Never; Numbered = $false }
    )
    foreach ($section in $sections) {
        if (@($section.Items).Count -eq 0) { continue }
        Write-Host ''
        Write-Host $section.Title -ForegroundColor $ColorTitle
        $number = 0
        foreach ($item in $section.Items) {
            $number++
            $marker = if ($section.Numbered) { ('{0,2}. ' -f $number) } else { '  - ' }
            $lines = @(Get-UninstallWrappedLines -Text $item -Width ($width - 8))
            Write-Host '    ' -NoNewline
            Write-Host $marker -NoNewline -ForegroundColor $ColorName
            Write-Host $lines[0]
            foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host ('        ' + $line) }
        }
    }
    if ($Next) {
        Write-Host ''
        Write-Host 'NEXT STEP' -ForegroundColor $ColorTitle
        foreach ($line in (Get-UninstallWrappedLines -Text $Next -Width ($width - 4))) { Write-Host "    $line" -ForegroundColor $ColorNext }
    }
    Write-Host ''
}

if ($Help) {
    $helpVersion = 'unknown'
    foreach ($line in (Get-Content -LiteralPath $PSCommandPath -TotalCount 15)) {
        if ($line -match '^#\s*Version:\s*(\d+\.\d+\.\d+)\s*$') { $helpVersion = $Matches[1]; break }
    }
    Show-UninstallHelp -Name 'dkdb-uninstall.ps1' `
        -VersionLine "uninstall $helpVersion (docker-devbox-ubuntu uninstaller)" `
        -Description 'Removes the scripts and Mutagen of this installation (<root>\devbox\scripts and <root>\devbox\mutagen) and their user PATH entries, after asking for confirmation. It keeps this install folder, the tools folder, your projects, containers and images.' `
        -Usage 'dkdb-uninstall.ps1 [-Help]' `
        -Examples @(
            @{ Command = '& "C:\shared\devbox\install\dkdb-uninstall.ps1"'; Description = 'Lists what will be removed and asks before doing it.' }
        ) `
        -Notes @(
            'Run it from <root>\devbox\install.',
            'If the Mutagen daemon is running it asks before stopping it (that stops all your Mutagen sessions).'
        )
    exit 0
}
if ($Man) {
    $manVersion = 'unknown'
    foreach ($line in (Get-Content -LiteralPath $PSCommandPath -TotalCount 15)) {
        if ($line -match '^#\s*Version:\s*(\d+\.\d+\.\d+)\s*$') { $manVersion = $Matches[1]; break }
    }
    Write-Host "uninstall $manVersion (docker-devbox-ubuntu uninstaller)" -ForegroundColor $ColorNote
    Show-UninstallMan -Name 'dkdb-uninstall.ps1' `
        -Purpose 'Removes the scripts and Mutagen of this installation and their user PATH entries.' `
        -Needs @(
            'Run it from <root>\devbox\install.'
        ) `
        -Steps @(
            'Checks that it runs from <root>\devbox\install.',
            'Lists what will be removed and asks for confirmation.',
            'If the Mutagen daemon is running, asks before stopping it (that stops all your Mutagen sessions).',
            'Removes the PATH entries of the scripts and of Mutagen.',
            'Removes <root>\devbox\scripts and <root>\devbox\mutagen.'
        ) `
        -Changes @(
            'The two folders above and the user PATH.'
        ) `
        -Never @(
            'Removes the install folder, the tools folder, your projects, containers or images.',
            'Stops the Mutagen daemon without asking.'
        ) `
        -Next 'To install again, run dkdb-install.ps1.'
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
Write-Host "uninstall $ownVersion (docker-devbox-ubuntu $(Get-UninstallVersion -ManifestPath (Join-Path $devboxPath 'manifest.json')))" -ForegroundColor $ColorNote
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
    # Windows PowerShell 5.1 turns the error output of a native program into a script-stopping
    # error when ErrorActionPreference is Stop: it is Continue around the native calls.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $mutagenExe sync list *> $null
        $daemonRunning = ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $previousPreference
        if ($null -eq $previous) { Remove-Item Env:MUTAGEN_DISABLE_AUTOSTART -ErrorAction SilentlyContinue }
        else { $env:MUTAGEN_DISABLE_AUTOSTART = $previous }
    }
    if ($daemonRunning) {
        Write-UninstallWarning 'The Mutagen daemon is running and must stop to remove Mutagen. This stops ALL your Mutagen sessions.'
        if (Confirm-Uninstall 'Stop the Mutagen daemon?') {
            $ErrorActionPreference = 'Continue'
            & $mutagenExe daemon stop *> $null
            $ErrorActionPreference = 'Stop'
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
Write-UninstallNext 'Next: open a new terminal so that the PATH is refreshed. To install again, download dkdb-install.ps1 as the README says.'
