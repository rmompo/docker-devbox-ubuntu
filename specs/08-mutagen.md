# 08 - Mutagen (optional projects sync)

## Context
On Docker Desktop with WSL2, bind mounts from `C:\` (9p) are slow for projects with many small files. Mutagen synchronizes the host folder with a copy that lives inside the container (native ext4).

## Reasoning
1. A copy in the container removes the 9p bottleneck; Mutagen replicates changes in both directions.
2. The choice is per container, not per installation -> `dkdb-container-create` asks for it with a menu.
3. Mutagen is third-party and about 100 MB -> it is optional and installed on demand: `install.ps1` runs once, while the choice is made per container in `dkdb-container-create`.
4. The agent is copied into the container by Mutagen itself (`docker cp` + `docker exec`) -> nothing is added to the image.
5. Files created by Mutagen belong to the container user -> no "dubious ownership" problem in git.
6. Sessions are created or resumed by `start` and `connect`; `stop` and `delete` never touch Mutagen (a leftover session cannot reach another container because it is bound to the container ID).

## Decision
- **Installation:** `dkdb-container-create` calls `Install-DevboxMutagen` (in `dkdb-common.ps1`) when Mutagen is chosen and missing: it asks `[y/N]`, downloads the release zip of `$DevboxMutagenVersion` (0.18.1), verifies it against `SHA256SUMS`, extracts it into `<install path>\mutagen\` and adds that folder to the user PATH. If declined or failed, the script aborts and creates nothing. `Get-DevboxMutagenExe` finds `mutagen.exe` in the PATH or in that folder, so the other scripts do not depend on a refreshed PATH.
- **Menu in `dkdb-container-create`:** "Docker bind mount (traditional)" or "Mutagen sync", always shown.
- **Mutagen container:** no projects bind mount; environment variables `DEVBOX_SYNC=mutagen` and `DEVBOX_SYNC_PATH=<host projects path>`. The bash volume is unchanged.
- **Session:** named `<container>-<first 12 characters of the container ID>`, `two-way-safe`, `--no-ignore-vcs`, **no ignore patterns** (everything, including `.git`, is synchronized), `--symlink-mode=ignore` (repositories are cloned on Windows, so they must not depend on symlinks), file mode `0644`, directory mode `0755`, beta owner and group = the container user. Endpoints: `<host path>` (alpha) and `docker://<user>@<container ID>/home/<user>/devbox/proyectos` (beta). The ID, not the name, is used so that a container recreated with the same name never reuses a leftover session.
- **Daemon:** `Test-DevboxMutagenDaemon` checks it with autostart disabled (`MUTAGEN_DISABLE_AUTOSTART=1`) and `Start-DevboxMutagenDaemon` starts it only when it is stopped. `dkdb-mutagen-start` and `dkdb-mutagen-stop` check the state and start or stop it by hand; stopping it stops every Mutagen session of the user.
- **`dkdb-container-start`:** after `docker start`, waits for `/dev/shm/devbox-ready` (created by the entrypoint), makes sure the daemon is running, creates or resumes the session and flushes.
- **`dkdb-container-connect`:** for a Mutagen container, runs the same create-or-resume step as `start` (idempotent), so a container started with plain `docker start` or Docker Desktop gets its session back. The shell opens even if the sync fails, with a warning.
- **`dkdb-container-stop`:** never touches Mutagen: no flush, no pause, no daemon stop. The session stays active (and retries to reach the container) until `start` or `connect` reconnects it. Only `dkdb-mutagen-stop` stops the daemon.
- **`dkdb-container-delete`:** never touches Mutagen. The host folder is not touched; the container copy is lost. The session of the deleted container is left behind (harmless: it cannot reach any other container, see Session); remove it by hand with `mutagen sync terminate <session>`.
- **Existing containers** keep their bind mount; recreate them to use Mutagen.

## Consequences
- `.git` is synchronized because the AI client inside the container needs the repository. Mutagen's documentation recommends against it: the Git index stores inode and mtime data specific to each filesystem (full re-hash after syncing), garbage collection reorganizes objects at any time, and hooks are a code-execution vector. Mitigation: run Git operations from one side at a time, preferably inside the container.
- Symbolic links are ignored; in `portable` mode (Mutagen's default) a non-portable link would halt the synchronization.
- Mutagen halts instead of propagating the deletion or emptying of a sync root (safety mechanisms); recover with `mutagen sync resume` or `mutagen sync reset`.
- Mutagen identifies a docker endpoint by the container identifier it is given; the ID is used (not the name) so that leftover sessions of deleted containers stay harmless. They are not removed automatically: list them with `mutagen sync list` and terminate them by hand.
- Syncing everything between Windows and Linux has risks: platform-specific `node_modules` or `.venv`, slow first scan on big trees, and case-insensitive host names. If it becomes a problem, add `--ignore` patterns in `Start-DevboxSync`.
- Not documented by Mutagen and still to verify: whether sessions resume after rebooting the PC (its data is stored in `~/.mutagen`), behavior when Docker Desktop stops with the container running, and how case-only name differences between Windows and Linux are handled.
- Mutagen license: MIT plus SSPL for the code in its `sspl` folder (included in official builds since v0.17). Devbox neither bundles nor links Mutagen; it only downloads it from its official release.
- Not tested yet on Windows with Docker (this environment has neither).
