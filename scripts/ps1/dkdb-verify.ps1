# Check the installed package against manifest.json: every listed file must exist and carry
# Version: 0.2.5
# the version that the manifest says. Exit code 1 when something is inconsistent.
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Checks the installed package against manifest.json: every listed file must exist and have the version that the manifest says.' `
        -Usage 'dkdb-verify [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-verify'; Description = 'Lists the files checked and reports every difference.' }
        ) `
        -Notes @(
            'Exit code 1 when something is inconsistent; files that the manifest does not list, or says were removed, are reported as notes.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Checks the installed package against manifest.json.' `
        -Needs @(
            'The package installed by dkdb-install.ps1.'
        ) `
        -Steps @(
            'Reads manifest.json and checks that every listed file exists and has the version of the manifest.',
            'Reports files under scripts or install that the manifest does not list, or that it lists as removed (dkdb-update deletes them), as notes.'
        ) `
        -Changes @(
            'Nothing: it only reads.'
        ) `
        -Never @(
            'Downloads or repairs files (run dkdb-install.ps1 again for that).'
        ) `
        -Next 'dkdb-image-create builds the image, then dkdb-container-create.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath

$base = Get-DevboxBase
$result = Get-DevboxIntegrity -Base $base
$checkedText = "Checked $($result.Checked) files in "
if (($checkedText.Length + $base.Length) -le (Get-DevboxConsoleWidth)) {
    Write-Host $checkedText -NoNewline
    Write-Host $base -ForegroundColor $DevboxHostColor
} else {
    # The path does not fit after the text: it goes below, wrapped at its separators.
    Write-Host $checkedText.TrimEnd()
    foreach ($line in @(Get-DevboxValueLines -Text $base -Room ((Get-DevboxConsoleWidth) - 2))) { Write-Host "  $line" -ForegroundColor $DevboxHostColor }
}
foreach ($problem in $result.Errors) { Write-DevboxWarning "  ERROR: $problem" }
foreach ($note in $result.Notes) { Write-DevboxWarning "  note: $note" }
if ($result.Errors.Count -gt 0) {
    Write-DevboxWarning 'The package is inconsistent with manifest.json: run dkdb-install.ps1 again.'
    exit 1
}
Write-DevboxSuccess 'The package is consistent with manifest.json.'
Write-DevboxNext 'Next: dkdb-image-create.ps1 builds the image, then dkdb-container-create.ps1.'
