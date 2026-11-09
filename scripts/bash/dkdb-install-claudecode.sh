#!/bin/bash
# Version: 0.3.0
# Install Claude Code (latest) in this container.
# Rule: one AI client per container. Run with: bash dkdb-install-claudecode.sh
set -euo pipefail

# Colors and messages (ok, warn, next): the table of dkdb-common.sh, shared by every script (spec 01).
# shellcheck source=dkdb-common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dkdb-common.sh"
# Help (-h, --help) and manual (man): same layout as the dkdb-* scripts (spec 01).
usage() {
    local heading name off
    heading="$c_title"; name="$c_name"; off="$c_off"
    printf '\n%sNAME%s\n    %s%s%s\n' "$heading" "$off" "$name" "$(basename "$0")" "$off"
    printf '\n%sDESCRIPTION%s\n' "$heading" "$off"
    printf '%s\n' "Installs Claude Code (latest) in this container with its official installer, and puts ~/.local/bin on the PATH." | fold -s -w 92 | sed 's/ *$//; s/^/    /'
    printf '\n%sUSAGE%s\n    %sbash ~/devbox/bash/%s [-h | man]%s\n' "$heading" "$off" "$name" "$(basename "$0")" "$off"
    printf '\n%sPARAMETERS%s\n' "$heading" "$off"
    printf '    %s%-10s%s Show this help and exit.\n' "$name" "-h, --help" "$off"
    printf '    %s%-10s%s Show the manual (what the script does, step by step) and exit.\n' "$name" "man" "$off"
    printf '\n%sEXAMPLES%s\n    %sbash ~/devbox/bash/%s%s\n        Installs Claude Code.\n' "$heading" "$off" "$name" "$(basename "$0")" "$off"
    printf '\n%sNOTES%s\n' "$heading" "$off"
    printf '%s\n' "One AI client per container: it refuses to install if GitHub Copilot CLI is already here." | fold -s -w 90 | sed '1s/^/    - /;2,$s/^/      /'
    printf '%s\n' "Run it inside the container (dkdb-container-connect opens a shell)." | fold -s -w 90 | sed '1s/^/    - /;2,$s/^/      /'
    printf '%s\n' "It downloads about 240 MB and shows no progress bar." | fold -s -w 90 | sed '1s/^/    - /;2,$s/^/      /'
    printf '\n'
}
# Manual (man): what the script does, in colors (same layout as the dkdb-* scripts, spec 01).
manual() {
    local heading name yellow off
    heading="$c_title"; name="$c_name"; yellow="$c_yellow"; off="$c_off"
    item() { printf '%s\n' "$2" | fold -s -w 84 | sed "1s/^/    $name$1$off /;2,\$s/^/        /; s/ *\$//"; }
    printf '\n%sMANUAL%s\n    %s%s%s\n' "$heading" "$off" "$name" "$(basename "$0")" "$off"
    printf '\n%sPURPOSE%s\n' "$heading" "$off"
    printf '%s\n' 'Installs Claude Code (latest) in this container with its official installer. One AI client per container.' | fold -s -w 92 | sed 's/ *$//; s/^/    /'
    printf '\n%sREQUIREMENTS%s\n' "$heading" "$off"
    item '  -' 'Run it inside the container (dkdb-container-connect opens a shell).'
    item '  -' 'Internet access (it downloads about 240 MB).'
    item '  -' 'No other AI client installed here.'
    printf '\n%sWHAT IT DOES%s\n' "$heading" "$off"
    item ' 1.' 'Refuses, in red, when GitHub Copilot CLI is already installed.'
    item ' 2.' 'Downloads and runs the official installer from claude.ai (no progress bar is shown; it can take a few minutes).'
    item ' 3.' 'Adds ~/.local/bin to the PATH in ~/.bashrc, once.'
    printf '\n%sWHAT IT CHANGES%s\n' "$heading" "$off"
    item '  -' 'Claude Code under ~/.local, and one line in ~/.bashrc.'
    printf '\n%sWHAT IT NEVER DOES%s\n' "$heading" "$off"
    item '  -' 'Installs a second AI client.'
    item '  -' 'Touches the host or other containers.'
    printf '\n%sNEXT STEP%s\n' "$heading" "$off"
    printf '%s\n' 'Open a new shell (or run: source ~/.bashrc) and run: claude' | fold -s -w 92 | sed "s/ *\$//; s/^/    $yellow/; s/\$/$off/"
    printf '\n'
}
for argument in "$@"; do
    case "$argument" in
        -h|--help) usage; exit 0 ;;
        man) manual; exit 0 ;;
        *) warn "Unknown argument: $argument (use -h or man)."; exit 1 ;;
    esac
done
script_version="$(sed -n 's/^# Version: *//p' "$0" | head -n 1)"
echo "$(basename "$0") ${script_version:-unknown} (docker-devbox-ubuntu image ${DEVBOX_IMAGE_VERSION:-unknown})"

# Refuse to install if the other client is already present.
if command -v copilot >/dev/null 2>&1 || [ -e "$HOME/.local/bin/copilot" ]; then
    warn "GitHub Copilot CLI is already installed here."
    warn "Use another container to install Claude Code."
    exit 1
fi

echo "Downloading and installing Claude Code (about 240 MB, it can take a few minutes; no progress bar is shown)..."
curl -fsSL https://claude.ai/install.sh | bash

# Make sure ~/.local/bin is on the PATH (idempotent).
line='export PATH="$HOME/.local/bin:$PATH"'
if ! grep -qxF "$line" "$HOME/.bashrc" 2>/dev/null; then
    echo "$line" >> "$HOME/.bashrc"
fi

ok "Claude Code installed."
next "Next: open a new shell (or run: source ~/.bashrc) and run: claude"
