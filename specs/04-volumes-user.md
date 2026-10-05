# 04 - Volumes and user

## Context
VS Code and Docker must point to the same projects folder on the host. The container's user is defined when the container is created, not in the image.

## Reasoning
1. Code must outlive the container -> bind mounts to host folders. (With Mutagen, spec 08, the container holds a synchronized copy and the host folder stays the persistent one.)
2. Host paths differ between machines -> `dkdb-container-create` asks for them, with defaults.
3. The mount target depends on the user -> `/home/<user>/devbox/...`.
4. Tools such as Maven or JDKs should be installed once and shared by every container -> a separate `tools` bind mount, by default `<root>\tools` next to the installation.
5. With `-v`, Docker Desktop creates a missing folder, which contradicts the rule "if it does not exist, do nothing" -> use `--mount type=bind` plus prior validation: nothing is created and the script aborts.
6. The user needs sudo, protected by a password for safety -> `sudo` group without `NOPASSWD`.
7. Remembering a separate password is inconvenient in a local environment -> password equals the user name (weak by design, acceptable locally).

## Decision
- **Host paths** (projects and tools are asked when creating the container):
  - Projects: `C:\LocalFiles\proyectos\`
  - Tools: `<root>\tools`, by default `C:\shared\tools` (shared tools such as Maven, JDKs: one installation for every container). The root is chosen once by `install.ps1` and deduced afterwards (spec 07); the user organizes the content of `tools`.
  - Bash: not asked; it is `<root>\devbox\scripts\bash`, mounted `readonly` (the container cannot modify the installers).
- **Mutagen (optional, spec 08):** instead of the projects bind mount, `~/devbox/projects` is a folder inside the container synchronized with the host projects path.
- **Container targets:** `/home/<user>/devbox/projects`, `/home/<user>/devbox/tools` (read/write) and `/home/<user>/devbox/bash` (read-only).
- **Missing path:** `dkdb-container-create` aborts with an error and creates nothing.
- **User:** `dkdb-<input>`; by default, the full container name. It is validated (lowercase, at most 32 characters) before creating anything.
- **Password:** equal to the full user name (example: `dkdb-user1`).
- **Sudo:** the user is a sudoer, always with a password.

## Consequences
- Permissions inside Windows bind mounts are handled by Docker Desktop, not by `chown`.
- The password is weak by design; the container must not be exposed to untrusted networks.
- The user is never named `ubuntu`, so it cannot clash with the user shipped in newer images.
