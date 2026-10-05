#!/bin/bash
# Version: 0.1.2
# Install GitHub Copilot CLI (latest) in this container (no Node needed).
# Rule: one AI client per container. Run with: bash dkdb-install-ghcopilot-cli.sh
set -euo pipefail

# Message colors (spec 01): success (something was done correctly) in green, warnings and errors in red,
# the natural next step in yellow. Other messages keep the default color.
if [ -t 1 ]; then c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_off=$'\033[0m'; else c_green=''; c_yellow=''; c_off=''; fi
if [ -t 2 ]; then c_red=$'\033[31m'; else c_red=''; fi
ok() { printf '%s%s%s\n' "$c_green" "$*" "$c_off"; }
warn() { printf '%s%s%s\n' "$c_red" "$*" "$c_off" >&2; }
next() { printf '%s%s%s\n' "$c_yellow" "$*" "$c_off"; }
script_version="$(sed -n 's/^# Version: *//p' "$0" | head -n 1)"
echo "$(basename "$0") ${script_version:-unknown} (docker-devbox-ubuntu image ${DEVBOX_IMAGE_VERSION:-unknown})"

# Refuse to install if the other client is already present.
if command -v claude >/dev/null 2>&1 || [ -e "$HOME/.local/bin/claude" ]; then
    warn "Claude Code is already installed here."
    warn "Use another container to install GitHub Copilot CLI."
    exit 1
fi

echo "Downloading and installing GitHub Copilot CLI (it can take a few minutes; no progress bar is shown)..."
curl -fsSL https://gh.io/copilot-install | bash

# Make sure ~/.local/bin is on the PATH (idempotent).
line='export PATH="$HOME/.local/bin:$PATH"'
if ! grep -qxF "$line" "$HOME/.bashrc" 2>/dev/null; then
    echo "$line" >> "$HOME/.bashrc"
fi

ok "GitHub Copilot CLI installed."
next "Next: open a new shell (or run: source ~/.bashrc) and run: copilot"
