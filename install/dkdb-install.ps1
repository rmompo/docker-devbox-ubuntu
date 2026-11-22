# Installer for docker-devbox-ubuntu. Download only this file and run it.
# Version: 0.3.6
# It downloads manifest.json and every file it lists (scripts and dkdb-uninstall.ps1) from the
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
function Get-InstallConsoleWidth {
    $width = 0
    try { $width = [int]$Host.UI.RawUI.WindowSize.Width } catch { $width = 0 }
    if ($width -lt 40) { $width = 80 }
    return ($width - 1)
}

# A text cut into lines of at most $Room characters, after a space, / or \ when it can.
function Get-InstallValueLines {
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
function Get-InstallWrappedLines {
    param([string]$Text, [int]$Width)
    $lines = @()
    $line = ''
    foreach ($word in ($Text -split '\s+' | Where-Object { $_ })) {
        if ($word.Length -gt $Width -and $Width -ge 10) {
            $pieces = @(Get-InstallValueLines -Text $word -Room $Width)
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
function Get-InstallTextWidth {
    return [math]::Max(30, [math]::Min((Get-InstallConsoleWidth), 110))
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
    $width = Get-InstallConsoleWidth
    if ($NoNewline -or $redirected -or (($text.Length -le $width) -and ($text.IndexOf("`n") -lt 0))) {
        Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
        return
    }
    foreach ($raw in ($text -split "\r?\n")) {
        $indent = [regex]::Match($raw, '^\s*').Value
        $lines = @(Get-InstallWrappedLines -Text $raw.Substring($indent.Length) -Width ([math]::Max(20, $width - $indent.Length)))
        if ($lines.Count -eq 0) { $lines = @('') }
        foreach ($line in $lines) {
            $params = @{ Object = ($indent + $line) }
            if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $params.ForegroundColor = $ForegroundColor }
            if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $params.BackgroundColor = $BackgroundColor }
            Microsoft.PowerShell.Utility\Write-Host @params
        }
    }
}

function Write-InstallSuccess {
    param([string]$Text)
    Write-Host $Text -ForegroundColor $ColorSuccess
}
function Write-InstallWarning {
    param([string]$Text)
    Write-Host $Text -ForegroundColor $ColorError
}
# The natural next step. A script named in it (dkdb-<name>.ps1 or .sh) is written in white, and in bold when the
# terminal supports ANSI (Windows Terminal, PowerShell 7 or later, VS Code); the same helper as dkdb-common.ps1.
function Write-InstallNext {
    param([string]$Text)
    $ansi = (-not $env:NO_COLOR) -and (($PSVersionTable.PSVersion.Major -ge 7) -or [bool]$env:WT_SESSION -or ($env:TERM_PROGRAM -eq 'vscode'))
    try { if ([Console]::IsOutputRedirected) { $ansi = $false } } catch { $ansi = $false }
    $esc = [char]27
    # On a console the text is wrapped at the words first (the bold codes would count as characters).
    $lines = @($Text)
    $redirected = $false
    try { $redirected = [Console]::IsOutputRedirected } catch { $redirected = $false }
    if (-not $redirected) {
        $lines = @(Get-InstallWrappedLines -Text $Text -Width (Get-InstallConsoleWidth))
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

function Stop-Install {
    param([Parameter(Mandatory)][string]$Message)
    Write-InstallWarning "Error: $Message"
    Write-InstallWarning 'Installation stopped.'
    exit 1
}

# Like Read-Host, but Esc cancels: returns $null on Esc, the typed text (maybe empty) on Enter. The same helper as
# Read-DevboxLine of dkdb-common.ps1 (spec 01); without a keyboard (redirected input) it is Read-Host.
function Read-InstallLine {
    param([Parameter(Mandatory)][string]$Prompt)
    if ([Console]::IsInputRedirected) { return (Read-Host $Prompt) }
    Write-Host "${Prompt}: " -NoNewline
    $buffer = New-Object System.Text.StringBuilder
    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Enter' { Write-Host ''; return $buffer.ToString() }
            'Escape' { Write-Host ''; return $null }
            'Backspace' {
                if ($buffer.Length -gt 0) {
                    $null = $buffer.Remove($buffer.Length - 1, 1)
                    Write-Host "`b `b" -NoNewline
                }
            }
            default {
                if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) {
                    $null = $buffer.Append($key.KeyChar)
                    Write-Host $key.KeyChar -NoNewline
                }
            }
        }
    }
}

function Confirm-Install {
    param([Parameter(Mandatory)][string]$Question)
    $answer = Read-InstallLine "$Question [y/N] (Esc cancels)"
    return ($null -ne $answer -and $answer.Trim() -match '^(y|yes)$')
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

function Show-InstallHelp {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Usage,
        [object[]]$Examples = @(),
        [string[]]$Notes = @(),
        [string]$VersionLine = ''
    )
    $width = Get-InstallTextWidth
    $parameters = @(@{ Name = '-Help'; Description = 'Show this help and exit.' }, @{ Name = '-Man'; Description = 'Show the manual (what the script does, step by step) and exit.' })
    if ($VersionLine) { Write-Host $VersionLine -ForegroundColor $ColorNote }
    Write-Host ''
    Write-Host 'NAME' -ForegroundColor $ColorTitle
    Write-Host "    $Name" -ForegroundColor $ColorName
    Write-Host ''
    Write-Host 'DESCRIPTION' -ForegroundColor $ColorTitle
    foreach ($line in (Get-InstallWrappedLines -Text $Description -Width ($width - 4))) { Write-Host "    $line" }
    Write-Host ''
    Write-Host 'USAGE' -ForegroundColor $ColorTitle
    $usageLines = @(Get-InstallWrappedLines -Text $Usage -Width ($width - 4))
    Write-Host "    $($usageLines[0])" -ForegroundColor $ColorName
    foreach ($line in ($usageLines | Select-Object -Skip 1)) { Write-Host "        $line" -ForegroundColor $ColorName }
    Write-Host ''
    Write-Host 'PARAMETERS' -ForegroundColor $ColorTitle
    $nameWidth = ($parameters | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 3
    foreach ($parameter in $parameters) {
        $lines = @(Get-InstallWrappedLines -Text $parameter.Description -Width ([math]::Max(15, $width - 4 - $nameWidth)))
        Write-Host ('    ' + $parameter.Name.PadRight($nameWidth)) -NoNewline -ForegroundColor $ColorName
        Write-Host $lines[0]
        foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host ((' ' * (4 + $nameWidth)) + $line) }
    }
    if ($Examples.Count -gt 0) {
        Write-Host ''
        Write-Host 'EXAMPLES' -ForegroundColor $ColorTitle
        foreach ($example in $Examples) {
            $commandLines = @(Get-InstallWrappedLines -Text $example.Command -Width ($width - 4))
            Write-Host "    $($commandLines[0])" -ForegroundColor $ColorName
            foreach ($line in ($commandLines | Select-Object -Skip 1)) { Write-Host "        $line" -ForegroundColor $ColorName }
            foreach ($line in (Get-InstallWrappedLines -Text $example.Description -Width ($width - 8))) { Write-Host "        $line" }
        }
    }
    if ($Notes.Count -gt 0) {
        Write-Host ''
        Write-Host 'NOTES' -ForegroundColor $ColorTitle
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
    $width = Get-InstallTextWidth
    Write-Host ''
    Write-Host 'MANUAL' -ForegroundColor $ColorTitle
    Write-Host "    $Name" -ForegroundColor $ColorName
    Write-Host ''
    Write-Host 'PURPOSE' -ForegroundColor $ColorTitle
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
        Write-Host $section.Title -ForegroundColor $ColorTitle
        $number = 0
        foreach ($item in $section.Items) {
            $number++
            $marker = if ($section.Numbered) { ('{0,2}. ' -f $number) } else { '  - ' }
            $lines = @(Get-InstallWrappedLines -Text $item -Width ($width - 8))
            Write-Host '    ' -NoNewline
            Write-Host $marker -NoNewline -ForegroundColor $ColorName
            Write-Host $lines[0]
            foreach ($line in ($lines | Select-Object -Skip 1)) { Write-Host ('        ' + $line) }
        }
    }
    if ($Next) {
        Write-Host ''
        Write-Host 'NEXT STEP' -ForegroundColor $ColorTitle
        foreach ($line in (Get-InstallWrappedLines -Text $Next -Width ($width - 4))) { Write-Host "    $line" -ForegroundColor $ColorNext }
    }
    Write-Host ''
}

$selfVersion = Get-InstallFileVersion -Path $PSCommandPath
if (-not $selfVersion) { $selfVersion = 'unknown' }
Write-Host "install $selfVersion (docker-devbox-ubuntu installer)" -ForegroundColor $ColorNote
if ($Help) {
    Show-InstallHelp -Name 'dkdb-install.ps1' `
        -Description 'Installs docker-devbox-ubuntu: downloads manifest.json and every file it lists into <root>\devbox, creates <root>\tools and adds <root>\devbox\scripts\ps1 to the user PATH. It asks for the shared root and for the branch or tag to download.' `
        -Usage 'dkdb-install.ps1 [-Help]' `
        -Examples @(
            @{ Command = '& "C:\shared\devbox\install\dkdb-install.ps1"'; Description = 'Installs from the console where you run it (the PATH is already updated there).' },
            @{ Command = 'powershell -ExecutionPolicy Bypass -File "C:\shared\devbox\install\dkdb-install.ps1"'; Description = 'Same, from a console where scripts are blocked by the execution policy.' }
        ) `
        -Notes @(
            'The default shared root is C:\shared\ and the default branch is main; both are asked.',
            'Run it again to update: it asks before overwriting an existing installation.',
            'Nothing needs administrator rights: only the user PATH is changed.'
        )
    exit 0
}
if ($Man) {
    Show-InstallMan -Name 'dkdb-install.ps1' `
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
$rootPath = Read-InstallLine "Shared root path [$DefaultRootPath] (Esc cancels)"
if ($null -eq $rootPath) { Stop-Install 'Cancelled by the user.' }
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
$Branch = Read-InstallLine "Branch or tag to download [$DefaultBranch] (Esc cancels)"
if ($null -eq $Branch) { Stop-Install 'Cancelled by the user.' }
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
    # The installer itself is the running script: only its version is compared (dkdb-update replaces it later).
    if ($relative -eq 'install/dkdb-install.ps1') {
        if ($selfVersion -ne [string]$entry.Value) {
            Write-InstallWarning "Warning: this installer is version $selfVersion but $Branch expects $($entry.Value). Download dkdb-install.ps1 again from that branch."
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
    Write-InstallNext "Updated from ${previousVersion} to ${version}: rebuild the images (dkdb-image-create.ps1) and recreate the containers."
}
Write-InstallWarning 'Make sure Docker Engine is running (start Docker Desktop and wait until it is ready).'
Write-InstallNext 'Next: open a new terminal (so the PATH is refreshed) and run: dkdb-image-create.ps1'
