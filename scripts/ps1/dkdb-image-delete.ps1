# Delete one devbox image chosen from a menu.
# Version: 0.1.2
. "$PSScriptRoot\dkdb-common.ps1"
Show-DevboxVersion -Script $PSCommandPath
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
    Write-DevboxWarning "Error: could not delete '$selected' (is a container using it?)."
    exit 1
}
Write-DevboxSuccess "Image '$selected' deleted."
Write-DevboxNext 'Next: dkdb-image-create builds a new image when you need one.'
