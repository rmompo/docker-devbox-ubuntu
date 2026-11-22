# Build a devbox image named <prefix>-<name>.
# Version: 0.2.7
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
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
            'The output of docker build is shown only when the build fails.',
            'After an update that changes the Dockerfile or the entrypoint, build the image again and recreate the containers.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Builds the Docker image of the devbox (Ubuntu 26.04 LTS with the development tools) and tags it with the image version of the manifest, never with latest.' `
        -Needs @(
            'Docker Engine running.',
            'The installed package must be consistent with manifest.json (it stops otherwise).'
        ) `
        -Steps @(
            'Checks the package against manifest.json and checks Docker.',
            'Reads the image version (the image field of manifest.json).',
            'Asks for the image name (default devbox-ubuntu, so dkdb-devbox-ubuntu:<version>).',
            'Runs docker build with the Dockerfile of scripts\docker, passing the version as a build argument; its output is shown only if the build fails.'
        ) `
        -Changes @(
            'Adds the local Docker image dkdb-<name>:<version>.'
        ) `
        -Never @(
            'Tags latest.',
            'Touches existing containers, other images or any host folder.'
        ) `
        -Next 'dkdb-container-create.'
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
if ($null -eq $name) {
    Write-Host 'Cancelled. Nothing was built.'
    exit 0
}
$imageName = Get-DevboxFullName $name
$imageRef = "${imageName}:$version"

$dockerDir = (Resolve-Path (Join-Path $PSScriptRoot '..\docker')).Path
Write-Host "Building image '$imageRef' from $dockerDir (this can take a few minutes) ..."
# No path is passed to docker: the build runs from the folder of the Dockerfile with "." as the context. A docker.exe
# client reads that folder as it is, and a docker client inside WSL (a wsl.exe shim) gets the folder translated to
# /mnt/<drive>/... by WSL itself, so it works with both without guessing where the client runs.
# The output of docker is only shown when the build fails, so that the script prints just its own messages.
# docker can be a PowerShell function (a wrapper that runs the docker of WSL), so it is called by name from the
# folder of the Dockerfile (Invoke-DevboxNative needs a program on disk and cannot run a function). Its output is
# captured with 2>&1 here, which is safe because ErrorActionPreference is Continue while it runs (Windows
# PowerShell 5.1 would stop on the first error line otherwise).
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
Push-Location -LiteralPath $dockerDir
try {
    $buildOutput = & docker build -t $imageRef --build-arg "DEVBOX_IMAGE_VERSION=$version" -f Dockerfile . 2>&1 | ForEach-Object { "$_" }
    $buildExit = $LASTEXITCODE
}
finally {
    Pop-Location
    $ErrorActionPreference = $previousPreference
}
if ($buildExit -ne 0) {
    $buildOutput | ForEach-Object { Write-Host $_ }
    Write-DevboxWarning 'Error: the image build failed.'
    exit 1
}
Write-DevboxSuccess "Image '$imageRef' created."
Write-DevboxNext 'Next: dkdb-container-create.ps1.'
