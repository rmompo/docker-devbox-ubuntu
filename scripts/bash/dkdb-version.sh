#!/bin/bash
# shellcheck disable=SC2034  # the MAN_* arrays are read by show_manual in dkdb-common.sh (through a nameref)
# Version: 0.3.1
# Show every version seen from inside the container: the image, the bash scripts against the manifest and the tools.
# Same layout as dkdb-version.ps1 on the host. It only reads; it works even when the host has not written the state.
set -u
# shellcheck source=dkdb-common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dkdb-common.sh"

usage() {
    show_help 'Shows every version seen from inside the container: the project and the image version that the host scripts expect, each bash script against the manifest, the tools, and the image this container was created from.' \
        'Prints all the versions.' \
        'The project and manifest versions come from the state file that the host scripts write (~/.devbox-state); run dkdb-container-connect on the host to refresh it.' \
        'An image older than the scripts is only reported; it keeps working.' \
        'Layout (same as dkdb-version on the host): SECTIONS in capitals, PROPERTIES in capitals followed by dots. Files: the name is orange, the version of the manifest green, and the version of the file green when it matches and red when it does not; the columns line up whatever the length of the names. COMPATIBLE (green) and NOT-COMPATIBLE (red) are shown in reverse video.'
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

# Reverse-video word (only on a terminal): COMPATIBLE green, NOT-COMPATIBLE red.
compat_badge() {
    if [ "$1" = yes ]; then badge compatible ' COMPATIBLE '; else badge incompatible ' NOT-COMPATIBLE '; fi
}

# --- Project ---
info_section 'Project'
if [ -n "$package" ]; then
    info_field 'Version' 8 2 "t:green:$package" 't:none: (docker-devbox-ubuntu, manifest.json)'
else
    info_field 'Version' 8 2 't:red:unknown: the host has not written the state yet (run dkdb-container-connect on the host)'
    problems=$((problems + 1))
fi
info_field 'Image' 8 2 "t:green:${expected:-unknown}" 't:none: (the image version that the scripts build and expect)'
[ -z "$updated" ] || info_field 'Reported' 8 2 "t:none:as the host wrote it at $updated"

# --- Files: the version in the manifest against the version in the file header ---
printf '\n%sFILES%s %s(%smanifest%s%s / file)%s\n' "$c_section" "$c_off" "$c_gray" "$c_green" "$c_off" "$c_gray" "$c_off"
listed=0
mismatches=0
# The columns are as wide as the longest name and version, so that they always line up.
name_width=0
version_width=0
while IFS='|' read -r name wanted; do
    [ -n "$name" ] || continue
    [ "${#name}" -le "$name_width" ] || name_width=${#name}
    [ "${#wanted}" -le "$version_width" ] || version_width=${#wanted}
done < <(state_each file)
while IFS='|' read -r name wanted; do
    [ -n "$name" ] || continue
    listed=$((listed + 1))
    actual="$(file_version "$dir/${name#scripts/bash/}")"
    # Name in orange, version of the manifest in green, version of the file green when it matches and red when not.
    printf '  %s%-*s%s %s%-*s%s ' "$c_name" "$name_width" "$name" "$c_off" "$c_green" "$version_width" "$wanted" "$c_off"
    if [ "$actual" = "$wanted" ]; then printf '%s%s%s\n' "$c_green" "$actual" "$c_off"; else printf '%s%s%s\n' "$c_red" "${actual:-missing}" "$c_off"; mismatches=$((mismatches + 1)); fi
done < <(state_each file)
if [ "$listed" -eq 0 ]; then
    bad '  the state file lists no file (run dkdb-container-connect on the host)'
    problems=$((problems + 1))
elif [ "$mismatches" -gt 0 ]; then
    bad "  $mismatches of $listed files differ from the manifest: run dkdb-install.ps1 again on the host (dkdb-verify shows the details)."
    problems=$((problems + 1))
else
    ok "  All $listed files match the manifest."
fi

# --- Tools ---
info_section 'Tools'
os="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
info_field 'Ubuntu' 9 2 "t:none:${os:-unknown}"
info_field 'Bash' 9 2 "t:none:${BASH_VERSION%%(*}"
info_field 'Git' 9 2 "t:none:$(git --version 2>/dev/null | awk '{print $3}')"
info_field 'Python' 9 2 "t:none:$(python3 --version 2>/dev/null | awk '{print $2}')"
if command -v claude >/dev/null 2>&1 || [ -e "$HOME/.local/bin/claude" ]; then
    info_field 'AI client' 9 2 "t:none:Claude Code $(timeout 5 claude --version 2>/dev/null | head -n 1)"
elif command -v copilot >/dev/null 2>&1 || [ -e "$HOME/.local/bin/copilot" ]; then
    info_field 'AI client' 9 2 "t:none:GitHub Copilot CLI $(timeout 5 copilot --version 2>/dev/null | head -n 1)"
else
    info_field 'AI client' 9 2 't:none:none (bash ~/devbox/bash/dkdb-install-claudecode.sh or dkdb-install-ghcopilot-cli.sh)'
fi

# --- This container ---
info_section 'Container' '(version of the image it was created from)'
image_version="${DEVBOX_IMAGE_VERSION:-}"
[ -n "$image_version" ] || image_version="$(cat /etc/devbox-image-version 2>/dev/null)"
shown="${image_version:-unknown}"
if [ -n "$expected" ] && version_compatible "$shown" "$expected"; then
    printf '  %s%s%s %s%-9s%s ' "$c_name" "$(hostname)" "$c_off" "$c_green" "$shown" "$c_off"
    compat_badge yes; echo
else
    printf '  %s%s%s %s%-9s%s ' "$c_name" "$(hostname)" "$c_off" "$c_red" "$shown" "$c_off"
    compat_badge no; printf '%s (it keeps working; newer features may be missing)%s\n' "$c_red" "$c_off"
    problems=$((problems + 1))
fi

echo
if [ "$problems" -gt 0 ]; then
    next 'Next: to update the container, rebuild the image (dkdb-image-create) and recreate it from the host; bash ~/devbox/bash/dkdb-info.sh shows how it is set up.'
else
    next 'Next: bash ~/devbox/bash/dkdb-info.sh shows how this container is set up.'
fi
