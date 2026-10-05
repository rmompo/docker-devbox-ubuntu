# Check the installed package against manifest.json: every listed file must exist and carry
# Version: 0.2.0
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
            'Exit code 1 when something is inconsistent; files that the manifest does not list are reported as notes.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Checks the installed package against manifest.json.' `
        -Needs @(
            'The package installed by install.ps1.'
        ) `
        -Steps @(
            'Reads manifest.json and checks that every listed file exists and has the version of the manifest.',
            'Reports files under scripts or install that the manifest does not list, as notes.'
        ) `
        -Changes @(
            'Nothing: it only reads.'
        ) `
        -Never @(
            'Downloads or repairs files (run install.ps1 again for that).'
        ) `
        -Next 'dkdb-image-create builds the image, then dkdb-container-create.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath

$base = Get-DevboxBase
$result = Get-DevboxIntegrity -Base $base
Write-Host "Checked $($result.Checked) files in $base"
foreach ($problem in $result.Errors) { Write-DevboxWarning "  ERROR: $problem" }
foreach ($note in $result.Notes) { Write-DevboxWarning "  note: $note" }
if ($result.Errors.Count -gt 0) {
    Write-DevboxWarning 'The package is inconsistent with manifest.json: run install.ps1 again.'
    exit 1
}
Write-DevboxSuccess 'The package is consistent with manifest.json.'
Write-DevboxNext 'Next: dkdb-image-create builds the image, then dkdb-container-create.'
