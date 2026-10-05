# Troubleshooting

Typical problems and their fixes. Commands in `PowerShell` run on the Windows host; commands in `bash` run inside the container.

## Installation and PATH

| # | Problem | Fix |
|---|---------|-----|
| 1 | The scripts are blocked ("running scripts is disabled on this system") | The execution policy is `Restricted` or `AllSigned`. For your user only: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`. |
| 2 | `dkdb-...` is not recognized as a command | Open a **new** terminal (the PATH is read when the terminal starts). If it still fails, check that `<root>\devbox\scripts\ps1` is in your user PATH, or run `install.ps1` again. |
| 3 | `install.ps1` cannot download a file | Check your internet access, that the repository is public and that the branch or tag you typed exists. |
| 4 | "the scripts must be in `<root>\devbox\scripts\ps1`" | The scripts were moved. They deduce the shared root from their location: run `install.ps1` again instead of moving them. |
| 5 | I want another shared root | Run `install.ps1` with the new root, then recreate your containers (they keep the host paths they were created with). The installer offers to remove the old PATH entry. |
| 6 | I want to remove everything | Run `<root>\devbox\install\uninstall.ps1`. It keeps `tools`, your projects, containers and images. |
| 7 | "the installed package is inconsistent with manifest.json" | A file is missing or has another version than the manifest. Run `dkdb-verify` to see which, then run `install.ps1` again. If it says "Inconsistent download" during the installation, wait a few minutes (GitHub caches raw files) and try again. |

## Docker

| # | Problem | Fix |
|---|---------|-----|
| 1 | "the Docker daemon is not reachable" | Start Docker Desktop and wait until it is running. |
| 2 | "Host path does not exist" in `dkdb-container-create` | The projects and tools folders must exist before creating the container. Create them, or type another path. |
| 3 | `git` says "dubious ownership" in the projects folder | With the bind mount, git is trusted only for `~/devbox/projects/*` (entrypoint). Rebuild the image and recreate the container if it was created before that setting. |
| 4 | `dkdb-image-delete` fails | A container still uses the image. Delete the container first with `dkdb-container-delete`. |

## Mutagen (optional projects sync)

| # | Problem | Fix |
|---|---------|-----|
| 1 | Changes are not reaching the other side | Run `dkdb-mutagen-status` and read the session state. If the daemon is stopped, `dkdb-mutagen-start`. If the container was started with plain `docker start` or Docker Desktop, run `dkdb-container-connect` (it creates or resumes the session). |
| 2 | The status shows conflicts | The same file changed on both sides before syncing. Delete the copy that must lose, on that side, and the other one is propagated. Edit each file from one side at a time. |
| 3 | Synchronization is halted after deleting or emptying a folder | Mutagen refuses to propagate the deletion of a whole root. If it was intentional: `mutagen sync resume <session>` or `mutagen sync reset <session>`. |
| 4 | The first synchronization is slow | The first scan copies every file; later ones only the changes. Large trees (dependencies, `node_modules`) take longer. |
| 5 | Leftover sessions of deleted containers | `dkdb-container-delete` terminates the session of the container it deletes. A leftover remains only if the container was deleted outside the scripts or the daemon was stopped. Run `dkdb-mutagen-clean` to terminate them (the host folders are not touched). |
| 6 | "Mutagen ... is older than ..." in `dkdb-container-create` | Update Mutagen, or remove the old one from the PATH so that the script installs its own (`<root>\devbox\mutagen`). |
| 7 | I want to stop Mutagen | `dkdb-mutagen-stop` stops the daemon for **all** your Mutagen sessions. `dkdb-container-stop` never touches Mutagen, and `dkdb-container-delete` only terminates the session of the deleted container. |
| 8 | Symbolic links are missing on the other side | They are ignored on purpose (`--symlink-mode=ignore`): repositories are cloned on Windows and must not depend on them. |
| 9 | "the Mutagen daemon could not be started" | The script waits about 10 seconds for the daemon and then prints why it does not answer. If it mentions a **version mismatch**, another Mutagen daemon (an older or different installation) is running: `dkdb-mutagen-stop` (or `mutagen daemon stop`) and try again; this stops all your Mutagen sessions. Otherwise run `mutagen daemon start` and `mutagen sync list` by hand and look at the error; security software can also block the daemon process. |

## Containers

| # | Problem | Fix |
|---|---------|-----|
| 1 | `dkdb-container-connect` shows no containers | It lists only running containers. Start one with `dkdb-container-start`. |
| 2 | The AI client installer says another client is installed | One AI client per container. Create another container for the other client. |
| 3 | `dkdb-install-*.sh` is not found | Run it with `bash ~/devbox/bash/<script>`; the `bash` folder is mounted read-only and Windows does not keep the execute bit. |
| 4 | I changed the image or `entrypoint.sh` | Rebuild with `dkdb-image-create` and recreate the containers: a container keeps the image it was created from. |
| 5 | `dkdb-container-start` or `dkdb-container-connect` says the image version is not compatible | The container was created from an image of another major.minor version than the scripts (0.x). Rebuild with `dkdb-image-create` and recreate the container. To reach its data meanwhile: `docker start <container>`, `docker exec -it -u <user> <container> bash`, `docker cp`. |
| 6 | "No image ... with a version compatible with the scripts" in `dkdb-container-create` | Build one with `dkdb-image-create`. Images are tagged with the version (`dkdb-<name>:<version>`); `latest` is never used. |
