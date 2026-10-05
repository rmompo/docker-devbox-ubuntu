# Delete one devbox image chosen from a menu.
. "$PSScriptRoot\common.ps1"
Assert-DevboxDocker

$images = Get-DevboxImages
if ($images.Count -eq 0) {
    Write-Host "No images starting with '$DevboxPrefix-' were found."
    exit 0
}

$selected = Select-DevboxItem -Title 'Select the image to delete:' -Items $images
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

docker rmi $selected
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: could not delete '$selected' (is a container using it?)." -ForegroundColor Red
    exit 1
}
Write-Host "Image '$selected' deleted." -ForegroundColor Green
