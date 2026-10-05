# Check the installed package against manifest.json: every listed file must exist and carry
# Version: 0.1.0
# the version that the manifest says. Exit code 1 when something is inconsistent.
. "$PSScriptRoot\dkdb-common.ps1"
Show-DevboxVersion -Script $PSCommandPath

$base = Get-DevboxBase
$result = Get-DevboxIntegrity -Base $base
Write-Host "Checked $($result.Checked) files in $base"
foreach ($problem in $result.Errors) { Write-Host "  ERROR: $problem" -ForegroundColor Red }
foreach ($note in $result.Notes) { Write-Host "  note: $note" -ForegroundColor Yellow }
if ($result.Errors.Count -gt 0) {
    Write-Host 'The package is inconsistent with manifest.json: run install.ps1 again.' -ForegroundColor Red
    exit 1
}
Write-Host 'The package is consistent with manifest.json.' -ForegroundColor Green
