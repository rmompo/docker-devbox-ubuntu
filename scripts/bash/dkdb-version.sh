#!/bin/bash
# shellcheck disable=SC2034  # the MAN_* arrays are read by show_manual in dkdb-common.sh (through a nameref)
# Version: 0.1.0
# Show every version seen from inside the container: the image, the bash scripts against the manifest and the tools.
# Same layout as dkdb-version.ps1 on the host. It only reads; it works even when the host has not written the state.
set -u
# shellcheck source=dkdb-common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dkdb-common.sh"

usage() {
    show_help 'Shows every version seen from inside the container: the project and the image version that the host scripts expect, each bash script against the manifest, the tools, and the image this container was created from.' \
        'Prints all the versions.' \
        'The project and manifest versions come from the state file that the host scripts write (~/.devbox-state); run dkdb-container-connect on the host to refresh it.' \
        'An image older than the scripts is only reported; it keeps working.'
}
MAN_PURPOSE='Shows every version seen from inside the container, in the same layout as dkdb-version on the host.'
MAN_NEEDS=('Nothing. The project and manifest versions need the state file ~/.devbox-state, which the host scripts write (dkdb-container-connect refreshes it).')
MAN_STEPS=(
    'Prints the project version and the image version that the host scripts build and expect, from the state file.'
    'Compares each bash script of ~/devbox/bash (its Version header) with the version in the manifest.'
    'Prints the operating system, bash, git, python and the AI client installed.'
    'Prints the version of the image this container was created from and whether it is compatible with the scripts (same major.minor in 0.x, same major from 1.0).'
)
MAN_CHANGES=('Nothing: it only reads.')
MAN_NEVER=('Blocks anything: an older image is only reported.' 'Touches the host or Docker.')
MAN_NEXT='bash ~/devbox/bash/dkdb-info.sh shows how this container is set up.'
handle_arguments "$@"

banner "${BASH_SOURCE[0]}"
problems=0
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="$(state_get package)"
expected="$(state_get image_expected)"
updated="$(state_get updated)"

# --- Project ---
echo
echo 'Project'
if [ -n "$package" ]; then
    echo "  docker-devbox-ubuntu $package (manifest.json, written by the host at $updated)"
else
    bad '  docker-devbox-ubuntu unknown: the host has not written the state yet (run dkdb-container-connect on the host)'
    problems=$((problems + 1))
fi
echo "  image version that the scripts build and expect: ${expected:-unknown}"

# --- Files: the version in the manifest against the version in the file header ---
echo
echo 'Files (manifest / file)'
listed=0
mismatches=0
while IFS='|' read -r name wanted; do
    [ -n "$name" ] || continue
    listed=$((listed + 1))
    actual="$(file_version "$dir/$(basename "$name")")"
    line="$(printf '  %-46s %-9s %s' "$name" "$wanted" "${actual:-missing}")"
    if [ "$actual" = "$wanted" ]; then echo "$line"; else bad "$line"; mismatches=$((mismatches + 1)); fi
done < <(state_each file)
if [ "$listed" -eq 0 ]; then
    bad '  the state file lists no file (run dkdb-container-connect on the host)'
    problems=$((problems + 1))
elif [ "$mismatches" -gt 0 ]; then
    bad "  $mismatches of $listed files differ from the manifest: run install.ps1 again on the host (dkdb-verify shows the details)."
    problems=$((problems + 1))
else
    ok "  All $listed files match the manifest."
fi

# --- Tools ---
echo
echo 'Tools'
os="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
printf '  %-16s%s\n' 'Ubuntu' "${os:-unknown}"
printf '  %-16s%s\n' 'Bash' "${BASH_VERSION%%(*}"
printf '  %-16s%s\n' 'Git' "$(git --version 2>/dev/null | awk '{print $3}')"
printf '  %-16s%s\n' 'Python' "$(python3 --version 2>/dev/null | awk '{print $2}')"
if command -v claude >/dev/null 2>&1 || [ -e "$HOME/.local/bin/claude" ]; then
    printf '  %-16s%s\n' 'AI client' "Claude Code $(timeout 5 claude --version 2>/dev/null | head -n 1)"
elif command -v copilot >/dev/null 2>&1 || [ -e "$HOME/.local/bin/copilot" ]; then
    printf '  %-16s%s\n' 'AI client' "GitHub Copilot CLI $(timeout 5 copilot --version 2>/dev/null | head -n 1)"
else
    printf '  %-16s%s\n' 'AI client' 'none (bash ~/devbox/bash/dkdb-install-claudecode.sh or dkdb-install-ghcopilot-cli.sh)'
fi

# --- This container ---
echo
echo 'Container (version of the image it was created from)'
image_version="${DEVBOX_IMAGE_VERSION:-}"
[ -n "$image_version" ] || image_version="$(cat /etc/devbox-image-version 2>/dev/null)"
shown="${image_version:-unknown}"
if [ -n "$expected" ] && version_compatible "$shown" "$expected"; then
    printf '  %-30s %-9s compatible\n' "$(hostname)" "$shown"
else
    bad "$(printf '  %-30s %-9s not compatible (it keeps working; newer features may be missing)' "$(hostname)" "$shown")"
    problems=$((problems + 1))
fi

echo
if [ "$problems" -gt 0 ]; then
    next 'Next: to update the container, rebuild the image (dkdb-image-create) and recreate it from the host; bash ~/devbox/bash/dkdb-info.sh shows how it is set up.'
else
    next 'Next: bash ~/devbox/bash/dkdb-info.sh shows how this container is set up.'
fi
