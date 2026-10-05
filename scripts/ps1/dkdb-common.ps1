# Common definitions for the devbox PowerShell scripts.
# Load it with:  . "$PSScriptRoot\dkdb-common.ps1"
# ASCII only, English only, LF line endings (see specs/01-conventions.md).

# Prefix shared by every image, container and user name. Change it here only.
$DevboxPrefix = 'dkdb'
$DevboxDefaultName = 'ubuntu'
$DevboxDefaultProjectsPath = 'C:\Localfiles\proyectos\'

# Linux limits user names to 32 characters; the prefix and the hyphen use some.
$DevboxMaxInputLength = 32 - ($DevboxPrefix.Length + 1)

function Assert-DevboxDocker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host 'Error: docker was not found in the PATH.' -ForegroundColor Red
        exit 1
    }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Error: the Docker daemon is not reachable. Is Docker Desktop running?' -ForegroundColor Red
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
        [Parameter(Mandatory)][string]$Default
    )
    while ($true) {
        # The default is shown with the prefix; the typed text never includes it.
        $value = Read-Host "$Prompt [$DevboxPrefix-$Default]"
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        $value = $value.Trim()
        if ($value -cnotmatch '^[a-z][a-z0-9_-]*$') {
            Write-Host 'Use lowercase letters, digits, "-" or "_", starting with a letter.' -ForegroundColor Yellow
            continue
        }
        if ($value.Length -gt $DevboxMaxInputLength) {
            Write-Host "Maximum $DevboxMaxInputLength characters (the prefix '$DevboxPrefix-' is added)." -ForegroundColor Yellow
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

# Read the user configured for a container (stored in the DEVBOX_USER variable).
function Get-DevboxContainerUser {
    param([Parameter(Mandatory)][string]$Container)
    $envLines = docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $Container
    foreach ($line in $envLines) {
        if ($line -like 'DEVBOX_USER=*') { return $line.Substring('DEVBOX_USER='.Length) }
    }
    return $null
}

# Host folder with the AI client installers (scripts\bash next to scripts\ps1).
# It is bind-mounted read-only into the container; nothing is copied.
function Get-DevboxBashPath {
    $path = Join-Path $PSScriptRoot '..\bash'
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Write-Host "Error: bash folder not found: $path" -ForegroundColor Red
        exit 1
    }
    return (Resolve-Path -LiteralPath $path).Path
}
