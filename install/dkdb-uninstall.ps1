# Uninstaller for docker-devbox-ubuntu. Run it from <root>\devbox\install\.
# Version: 0.2.6
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
$ColorScript = 'White'
# --- Width of the console (the same rules as dkdb-common.ps1, spec 01) ---
# Width usable on a line (one less than the window; 80 when it cannot be known).
function Get-UninstallConsoleWidth {
    $width = 0
    try { $width = [int]$Host.UI.RawUI.WindowSize.Width } catch { $width = 0 }
    if ($width -lt 40) { $width = 80 }
    return ($width - 1)
}

# A text cut into lines of at most $Room characters, after a space, / or \ when it can.
function Get-UninstallValueLines {
    param([string]$Text, [int]$Room)
    $lines = @()
    $rest = $Text
    while ($rest.Length -gt $Room) {
        $cut = 0
        for ($i = $Room; ($i -gt [math]::Floor($Room / 3)) -and ($i -gt 0); $i--) {
            if (' /\'.IndexOf($rest[$i - 1]) -ge 0) { $cut = $i; break }
        }
        if ($cut -eq 0) { $cut = $Room }
        $lines += $rest.Substring(0, $cut).TrimEnd(' ')
        $rest = $rest.Substring($cut).TrimStart(' ')
    }
    $lines += $rest
    return $lines
}

# A text wrapped at the words; a word longer than the line (a path) is cut after a / or \.
function Get-UninstallWrappedLines {
    param([string]$Text, [int]$Width)
    $lines = @()
    $line = ''
    foreach ($word in ($Text -split '\s+' | Where-Object { $_ })) {
        if ($word.Length -gt $Width -and $Width -ge 10) {
            $pieces = @(Get-UninstallValueLines -Text $word -Room $Width)
            if ($line) { $lines += $line; $line = '' }
            for ($k = 0; $k -lt ($pieces.Count - 1); $k++) { $lines += $pieces[$k] }
            $word = $pieces[$pieces.Count - 1]
        }
        if ($line -and (($line.Length + 1 + $word.Length) -gt $Width)) { $lines += $line; $line = $word }
        elseif ($line) { $line = "$line $word" }
        else { $line = $word }
    }
    if ($line) { $lines += $line }
    return $lines
}

# The width of the help and the manual: the console, up to 110 (never fewer than 30).
function Get-UninstallTextWidth {
    return [math]::Max(30, [math]::Min((Get-UninstallConsoleWidth), 110))
}

# Write-Host that wraps a long line at the words to the width of the console, keeping its indentation (a line written
# in pieces, a short one and any output that is not a console go through as they are).
function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)][object[]]$Object,
        [switch]$NoNewline,
        [object]$Separator = ' ',
        [System.ConsoleColor]$ForegroundColor,
        [System.ConsoleColor]$BackgroundColor
    )
    $text = ''
    if ($null -ne $Object) { $text = (@($Object | ForEach-Object { [string]$_ }) -join [string]$Separator) }
    $redirected = $false
    try { $redirected = [Console]::IsOutputRedirected } catch { $redirected = $false }
    $width = Get-UninstallConsoleWidth
    if ($NoNewline -or $redirected -or (($text.Length -le $width) -and ($text.IndexOf("`n") -lt 0))) {
        Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
        return
    }
    foreach ($raw in ($text -split "\r?\n")) {
        $indent = [regex]::Match($raw, '^\s*').Value
        $lines = @(Get-UninstallWrappedLines -Text $raw.Substring($indent.Length) -Width ([math]::Max(20, $width - $indent.Length)))
        if ($lines.Count -eq 0) { $lines = @('') }
        foreach ($line in $lines) {
            $params = @{ Object = ($indent + $line) }
            if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $params.ForegroundColor = $ForegroundColor }
            if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $params.BackgroundColor = $BackgroundColor }
            Microsoft.PowerShell.Utility\Write-Host @params
        }
    }
}

function Write-UninstallSuccess {
    param([string]$Text)
    Write-Host $Text -ForegroundColor $ColorSuccess
}
function Write-UninstallWarning {
    param([string]$Text)
    Write-Host $Text -ForegroundColor $ColorError
}
# The natural next step. A script named in it (dkdb-<name>.ps1 or .sh) is written in white, and in bold when the
# terminal supports ANSI (Windows Terminal, PowerShell 7 or later, VS Code); the same helper as dkdb-common.ps1.
function Write-UninstallNext {
    param([string]$Text)
    $ansi = (-not $env:NO_COLOR) -and (($PSVersionTable.PSVersion.Major -ge 7) -or [bool]$env:WT_SESSION -or ($env:TERM_PROGRAM -eq 'vscode'))
    try { if ([Console]::IsOutputRedirected) { $ansi = $false } } catch { $ansi = $false }
    $esc = [char]27
    # On a console the text is wrapped at the words first (the bold codes would count as characters).
    $lines = @($Text)
    $redirected = $false
    try { $redirected = [Console]::IsOutputRedirected } catch { $redirected = $false }
    if (-not $redirected) {
        $lines = @(Get-UninstallWrappedLines -Text $Text -Width (Get-UninstallConsoleWidth))
        if ($lines.Count -eq 0) { $lines = @('') }
    }
    foreach ($lineText in $lines) {
        foreach ($part in [regex]::Split($lineText, '(dkdb-[a-z0-9-]+\.(?:ps1|sh))')) {
            if (-not $part) { continue }
            $color = $ColorNext
            if ($part -match '^dkdb-[a-z0-9-]+\.(?:ps1|sh)$') {
                $color = $ColorScript
                if ($ansi) { $part = "$esc[1m$part$esc[22m" }
            }
            Write-Host $part -NoNewline -ForegroundColor $color
        }
        Write-Host ''
    }
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

function Show-UninstallHelp {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Usage,
        [object[]]$Examples = @(),
        [string[]]$Notes = @(),
        [string]$VersionLine = ''
    )
    $width = Get-UninstallTextWidth
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
    $usageLines = @(Get-UninstallWrappedLines -Text $Usage -Width ($width - 4))
    Write-Host "    $($usageLines[0])" -ForegroundColor $ColorName
    foreach ($line in ($usageLines | Select-Object -Skip 1)) { Write-Host "        $line" -ForegroundColor $ColorName }
    Write-Host ''
    Write-Host 'PARAMETERS' -ForegroundColor $ColorTitle
    $nameWidth = ($parameters | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 3
    foreach ($parameter in $parameters) {
        $lines = @(Get-UninstallWrappedLines -Text $parameter.Description -Width ([math]::Max(15, $width - 4 - $nameWidth)))
        Write-Host ('    ' + $parameter.Name.PadRight($nameWidth)) -NoNewline -ForegroundColor $ColorName
        Write-Host $lines[0]
        foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host ((' ' * (4 + $nameWidth)) + $line) }
    }
    if ($Examples.Count -gt 0) {
        Write-Host ''
        Write-Host 'EXAMPLES' -ForegroundColor $ColorTitle
        foreach ($example in $Examples) {
            $commandLines = @(Get-UninstallWrappedLines -Text $example.Command -Width ($width - 4))
            Write-Host "    $($commandLines[0])" -ForegroundColor $ColorName
            foreach ($line in ($commandLines | Select-Object -Skip 1)) { Write-Host "        $line" -ForegroundColor $ColorName }
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
    $width = Get-UninstallTextWidth
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
