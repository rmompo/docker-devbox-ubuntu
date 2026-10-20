# Update the installed scripts from the repository (optionally from another branch or tag).
# Version: 0.1.0
# It downloads manifest.json and the files whose version changed into a temporary folder, checks them
# and only then copies them over the installation. Nothing is changed if anything fails.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Branch = 'main',
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Updates the installed scripts from the GitHub repository: downloads manifest.json and the files whose version changed, checks them and copies them over the installation after you confirm. The branch or tag is optional (default main).' `
        -Usage 'dkdb-update [-Branch <branch or tag>] [-Help] [-Man]' `
        -Parameters @(
            @{ Name = '-Branch'; Description = 'Branch or tag to download from (default main). Letters, digits, ., _, - and / only.' }
        ) `
        -Examples @(
            @{ Command = 'dkdb-update'; Description = 'Updates from the main branch.' },
            @{ Command = 'dkdb-update -Branch feature-x'; Description = 'Updates from the branch feature-x (to test it before merging).' }
        ) `
        -Notes @(
            'Only the files whose version differs from the manifest (or that are missing) are replaced; manual edits to those files are lost.',
            'Files that are no longer in the repository are not deleted (dkdb-verify reports them as notes).',
            'install.ps1 is not replaced: it is downloaded by hand; the script tells you when its version changed.',
            'It never touches images, containers, Mutagen sessions or your projects.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Updates the installed scripts from the repository without running the installer again.' `
        -Needs @(
            'Internet access to raw.githubusercontent.com (the repository is public).',
            'The package installed by install.ps1.'
        ) `
        -Steps @(
            'Downloads manifest.json of the branch or tag (default main) into a temporary folder.',
            'Compares the version of every listed file with the installed one and lists what is new or changed.',
            'When there is nothing to update it says so and stops.',
            'Asks [y/N] before replacing anything.',
            'Downloads the files to update into the temporary folder and checks that the Version header of each one equals the manifest; otherwise it stops and nothing is changed.',
            'Copies the files over the installation (manifest.json last), unblocks the .ps1 files and removes the temporary folder.',
            'Checks the installation against the new manifest and tells you if the image must be rebuilt (image version changed incompatibly).'
        ) `
        -Changes @(
            'The files under <root>\devbox whose version changed, and manifest.json.'
        ) `
        -Never @(
            'Deletes files, images, containers, Mutagen sessions or projects.',
            'Replaces install.ps1 (downloaded by hand) or changes the PATH.',
            'Changes anything when a download or a check fails.'
        ) `
        -Next 'dkdb-version shows the result; if it says so, rebuild the image (dkdb-image-create) and recreate the containers.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath

$RepoUrl = 'https://github.com/rmompo/docker-devbox-ubuntu'
if ($RepoUrl.TrimEnd('/') -notmatch '^https://github\.com/([^/]+/[^/]+)$') {
    Write-DevboxWarning "Error: RepoUrl is not a valid GitHub repository URL: $RepoUrl"
    exit 1
}
$repoSlug = $Matches[1]
$Branch = $Branch.Trim()
if ($Branch -notmatch '^[A-Za-z0-9._/-]+$') {
    Write-DevboxWarning "Error: invalid branch or tag name: $Branch"
    exit 1
}
$rawBase = "https://raw.githubusercontent.com/$repoSlug/$Branch"
$base = Get-DevboxBase
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("dkdb-update-" + [guid]::NewGuid().ToString('N'))

# Download one repository file into the temporary folder, keeping its relative path. Returns the path or $null.
function Save-DevboxUpdateFile {
    param([Parameter(Mandatory)][string]$Relative)
    $target = Join-Path $staging ($Relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    try {
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }
        # Bytes are saved as they are, so LF line endings are preserved.
        Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/$Relative" -OutFile $target
    } catch {
        Write-DevboxWarning "Error: could not download $Relative ($($_.Exception.Message)). Is the repository public and the branch '$Branch' right?"
        return $null
    }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Get-Item -LiteralPath $target).Length -eq 0) {
        Write-DevboxWarning "Error: the downloaded file is missing or empty: $Relative"
        return $null
    }
    return $target
}

try {
    New-Item -ItemType Directory -Path $staging | Out-Null
    Write-Host "Downloading manifest.json from $RepoUrl ($Branch) ..."
    $manifestFile = Save-DevboxUpdateFile -Relative 'manifest.json'
    if (-not $manifestFile) { exit 1 }
    try { $manifest = Get-Content -Raw -LiteralPath $manifestFile | ConvertFrom-Json }
    catch {
        Write-DevboxWarning 'Error: the downloaded manifest.json is not valid JSON. Nothing was changed.'
        exit 1
    }
    $entries = @()
    if ($manifest.files) { $entries = @($manifest.files.PSObject.Properties) }
    if ($entries.Count -eq 0) {
        Write-DevboxWarning 'Error: the downloaded manifest.json does not list any file. Nothing was changed.'
        exit 1
    }
    $oldVersion = Get-DevboxVersion
    $oldImage = Get-DevboxImageVersion
    $newVersion = [string]$manifest.version
    $newImage = [string]$manifest.image
    Write-Host "Installed: $oldVersion (image $oldImage). Repository ($Branch): $newVersion (image $newImage)."

    # What changes: files that are missing or whose version differs. install.ps1 is only compared.
    $changes = @()
    $installerNote = $null
    foreach ($entry in $entries) {
        $relative = $entry.Name
        $path = Join-Path $base ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $current = Get-DevboxFileVersion -Path $path
        if ($relative -eq 'install/install.ps1') {
            if ($current -and $current -ne [string]$entry.Value) { $installerNote = "install.ps1 is version $current here and $($entry.Value) in ${Branch}: download it again by hand." }
            continue
        }
        if ($current -ne [string]$entry.Value) {
            $changes += [pscustomobject]@{ Relative = $relative; Path = $path; Old = $current; New = [string]$entry.Value }
        }
    }
    if ($changes.Count -eq 0 -and $oldVersion -eq $newVersion) {
        Write-DevboxSuccess "Already up to date ($oldVersion)."
        if ($installerNote) { Write-DevboxNext "Next: $installerNote" } else { Write-DevboxNext 'Next: nothing to do; dkdb-version shows every version.' }
        exit 0
    }
    Write-Host 'Files to update:'
    foreach ($change in $changes) {
        $from = if ($change.Old) { $change.Old } else { 'missing' }
        Write-Host "  $($change.Relative): $from -> $($change.New)"
    }
    Write-DevboxWarning 'These files are overwritten (manual edits are lost); files that no longer exist in the repository are not deleted.'
    $answer = Read-Host 'Continue? [y/N]'
    if ($answer -notmatch '^\s*(y|yes)\s*$') {
        Write-Host 'Cancelled: nothing was changed.'
        exit 0
    }

    # Download and check everything before touching the installation.
    foreach ($change in $changes) {
        $downloaded = Save-DevboxUpdateFile -Relative $change.Relative
        if (-not $downloaded) {
            Write-DevboxWarning 'Nothing was changed.'
            exit 1
        }
        $actual = Get-DevboxFileVersion -Path $downloaded
        if ($actual -ne $change.New) {
            Write-DevboxWarning "Error: inconsistent download: $($change.Relative) is version '$actual' but manifest.json says $($change.New). Try again in a few minutes (GitHub caches raw files). Nothing was changed."
            exit 1
        }
        $change | Add-Member -NotePropertyName Staged -NotePropertyValue $downloaded
    }

    # Copy: the files first, manifest.json last.
    try {
        foreach ($change in $changes) {
            $targetDir = Split-Path -Parent $change.Path
            if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }
            Copy-Item -LiteralPath $change.Staged -Destination $change.Path -Force
            # Best effort: the files downloaded from the Internet are unblocked so that the execution policy accepts them.
            if ($change.Path -like '*.ps1') { try { Unblock-File -LiteralPath $change.Path } catch { Write-Verbose 'Unblock-File is not available' } }
        }
        Copy-Item -LiteralPath $manifestFile -Destination (Join-Path $base 'manifest.json') -Force
    } catch {
        Write-DevboxWarning "Error: could not copy the files ($($_.Exception.Message)). The installation may be inconsistent: run dkdb-verify, or the installer again."
        exit 1
    }
    Write-DevboxSuccess "Updated $($changes.Count) file(s): $oldVersion -> $newVersion."

    $integrity = Get-DevboxIntegrity -Base $base
    foreach ($problem in $integrity.Errors) { Write-DevboxWarning "  ERROR: $problem" }
    foreach ($note in $integrity.Notes) { Write-DevboxWarning "  note: $note" }
    if ($integrity.Errors.Count -gt 0) {
        Write-DevboxWarning 'The installation is inconsistent with the new manifest.json: run the installer again.'
        exit 1
    }
    if ($installerNote) { Write-DevboxNext "Next: $installerNote" }
    if (-not (Test-DevboxVersionCompatible -Left $oldImage -Right $newImage)) {
        Write-DevboxNext "Next: the image version changed ($oldImage -> $newImage): rebuild the image (dkdb-image-create) and recreate the containers."
    } else {
        Write-DevboxNext 'Next: dkdb-version shows every version; existing images and containers keep working.'
    }
} finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
}
