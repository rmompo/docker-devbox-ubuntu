# Build a devbox image named <prefix>-<name>.
# Version: 0.1.3
. "$PSScriptRoot\dkdb-common.ps1"
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
