# Delete one devbox image chosen from a menu.
# Version: 0.2.0
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Deletes one devbox image (dkdb-*) chosen from a menu.' `
        -Usage 'dkdb-image-delete [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-image-delete'; Description = 'Shows the images and deletes the one you pick.' }
        ) `
        -Notes @(
            'A container that uses the image must be deleted first (dkdb-container-delete).'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Deletes one devbox image chosen from a menu.' `
        -Needs @(
            'Docker Engine running.',
            'At least one image whose name starts with dkdb-.'
        ) `
        -Steps @(
            'Lists the images starting with dkdb-.',
            'Shows a menu (Esc cancels).',
            'Runs docker rmi on the chosen one; Docker refuses when a container still uses it.'
        ) `
        -Changes @(
            'Removes the chosen image.'
        ) `
        -Never @(
            'Deletes containers, volumes or host folders.'
        ) `
        -Next 'dkdb-image-create builds a new image when you need one.'
    exit 0
}
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
