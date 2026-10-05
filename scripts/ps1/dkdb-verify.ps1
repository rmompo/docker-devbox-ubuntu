# Check the installed package against manifest.json: every listed file must exist and carry
# Version: 0.1.1
# the version that the manifest says. Exit code 1 when something is inconsistent.
. "$PSScriptRoot\dkdb-common.ps1"
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
