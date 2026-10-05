# Delete one stopped devbox container chosen from a menu.
# Version: 0.2.0
# The host folders (projects, tools, bash) are NOT touched, but everything stored only
# inside the container (its home, installed AI client, login) is lost.
# With a Mutagen container, only its Mutagen sessions (the whole projects folder and its
# folders) are terminated (never the daemon or sessions of other containers).
# PositionalBinding is off so that a stray argument is an error.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Man,
    [switch]$Help
)
. "$PSScriptRoot\dkdb-common.ps1"
if ($Help) {
    Show-DevboxHelp -Script $PSCommandPath `
        -Description 'Deletes one stopped devbox container chosen from a menu, after asking for confirmation.' `
        -Usage 'dkdb-container-delete [-Help]' `
        -Examples @(
            @{ Command = 'dkdb-container-delete'; Description = 'Shows the stopped containers and deletes the one you pick.' }
        ) `
        -Notes @(
            'Its home, the installed AI client and (with Mutagen) its copy of the projects are lost; the host folders are not touched.',
            'For a Mutagen container it also terminates its Mutagen sessions.'
        )
    exit 0
}
if ($Man) {
    Show-DevboxMan -Script $PSCommandPath `
        -Purpose 'Deletes one stopped devbox container chosen from a menu.' `
        -Needs @(
            'Docker Engine running and a stopped dkdb- container (stop a running one first).'
        ) `
        -Steps @(
            'Shows the menu of stopped containers.',
            'Asks [y/N]: its home and installed AI client are lost (with Mutagen, also the container copy of the projects).',
            'For a Mutagen container, reads the names of its sessions first (they depend on the container ID).',
            'Runs docker rm.',
            'With Mutagen, terminates the sessions of that container (the whole projects folder and its folders) when the daemon is running; otherwise dkdb-mutagen-clean removes them later.'
        ) `
        -Changes @(
            'Removes the container and, with Mutagen, its sessions.'
        ) `
        -Never @(
            'Touches the host folders (projects, tools, bash).',
            'Stops the Mutagen daemon or touches the sessions of other containers.'
        ) `
        -Next 'dkdb-container-create creates another one.'
    exit 0
}
Show-DevboxVersion -Script $PSCommandPath
Assert-DevboxDocker

$containers = Get-DevboxContainers -Running $false
if ($containers.Count -eq 0) {
    Write-Host "No stopped containers starting with '$DevboxPrefix-' were found (stop it first with dkdb-container-stop)."
    exit 0
}

$selected = Select-DevboxItem -Title 'Select the container to delete:' -Items $containers
if (-not $selected) {
    Write-Host 'Cancelled.'
    exit 0
}

$answer = Read-Host "Delete '$selected'? Its home and installed AI client are lost (with Mutagen, the container copy of the projects too). [y/N]"
if ($answer -notmatch '^[yY]$') {
    Write-Host 'Cancelled.'
    exit 0
}

# The session names depend on the container ID: read them before the container is removed (the
# session of the whole projects folder and those of its folders).
$sessionNames = @()
$usesMutagen = $false
if ((Get-DevboxContainerEnv -Container $selected -Name 'DEVBOX_SYNC') -eq 'mutagen') {
    $sessionNames = @(Get-DevboxContainerSessionNames -Container $selected)
    $usesMutagen = $true
}

docker rm $selected | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-DevboxWarning "Error: could not delete '$selected'."
    exit 1
}
Write-DevboxSuccess "Container '$selected' deleted."
if ($usesMutagen) { foreach ($sessionName in $sessionNames) { Remove-DevboxSyncSession -SessionName $sessionName } }
Write-DevboxNext 'Next: dkdb-container-create creates another one.'
