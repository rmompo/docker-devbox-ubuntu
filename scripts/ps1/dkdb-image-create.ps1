# Build a devbox image named <prefix>-<name>.
# Version: 0.1.4
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Builds the devbox Docker image dkdb-<name>:<image version> from the Dockerfile of this installation. It asks for the image name; the default is shown in the prompt.' `
        -Usage 'dkdb-image-create [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-image-create'; Description = 'Builds the image with the default name.' }
        ) `
        -Notes @(
            'The tag is the image version (the ''image'' field of manifest.json), never latest.',
            'After an update that changes the Dockerfile or the entrypoint, build the image again and recreate the containers.'
        )
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity
Assert-DevboxDocker

# The image is tagged with its own version (name:version, the "image" field of manifest.json), never with latest.
$version = Get-DevboxImageVersion
if ($version -eq 'unknown') {
    Write-DevboxWarning 'Error: the image version could not be read from manifest.json.'
    exit 1
}

$name = Read-DevboxName -Prompt 'Image name' -Default $DevboxDefaultName -DefaultSuffix ":$version"
$imageName = Get-DevboxFullName $name
$imageRef = "${imageName}:$version"

$dockerDir = (Resolve-Path (Join-Path $PSScriptRoot '..\docker')).Path
Write-Host "Building image '$imageRef' from $dockerDir ..."
docker build -t $imageRef --build-arg "DEVBOX_IMAGE_VERSION=$version" -f (Join-Path $dockerDir 'Dockerfile') $dockerDir
if ($LASTEXITCODE -ne 0) {
    Write-DevboxWarning 'Error: the image build failed.'
    exit 1
}
Write-DevboxSuccess "Image '$imageRef' created."
Write-DevboxNext 'Next: dkdb-container-create.'
