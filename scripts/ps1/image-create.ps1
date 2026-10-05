# Build a devbox image named <prefix>-<name>.
. "$PSScriptRoot\common.ps1"
Assert-DevboxDocker

$name = Read-DevboxName -Prompt 'Image name' -Default $DevboxDefaultName
$imageName = Get-DevboxFullName $name

$dockerDir = (Resolve-Path (Join-Path $PSScriptRoot '..\docker')).Path
Write-Host "Building image '$imageName' from $dockerDir ..."
docker build -t $imageName -f (Join-Path $dockerDir 'Dockerfile') $dockerDir
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Error: the image build failed.' -ForegroundColor Red
    exit 1
}
Write-Host "Image '$imageName' created." -ForegroundColor Green
