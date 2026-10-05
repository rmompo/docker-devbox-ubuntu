# Build a devbox image named <prefix>-<name>.
# Version: 0.1.0
. "$PSScriptRoot\dkdb-common.ps1"
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxIntegrity
Assert-DevboxDocker

$name = Read-DevboxName -Prompt 'Image name' -Default $DevboxDefaultName
$imageName = Get-DevboxFullName $name

# The image is tagged with the project version (name:version), never with latest.
$version = Get-DevboxVersion
if ($version -eq 'unknown') {
    Write-Host 'Error: the project version could not be read from manifest.json.' -ForegroundColor Red
    exit 1
}
$imageRef = "${imageName}:$version"

$dockerDir = (Resolve-Path (Join-Path $PSScriptRoot '..\docker')).Path
Write-Host "Building image '$imageRef' from $dockerDir ..."
docker build -t $imageRef --build-arg "DEVBOX_VERSION=$version" -f (Join-Path $dockerDir 'Dockerfile') $dockerDir
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Error: the image build failed.' -ForegroundColor Red
    exit 1
}
Write-Host "Image '$imageRef' created." -ForegroundColor Green
