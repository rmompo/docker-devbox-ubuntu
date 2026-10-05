#!/bin/bash
# Install GitHub Copilot CLI (latest) in this container (no Node needed).
# Rule: one AI client per container. Run with: bash install-ghcopilot-cli.sh
set -euo pipefail

# Refuse to install if the other client is already present.
if command -v claude >/dev/null 2>&1 || [ -e "$HOME/.local/bin/claude" ]; then
    echo "Claude Code is already installed here." >&2
    echo "Use another container to install GitHub Copilot CLI." >&2
    exit 1
fi

echo "Downloading and installing GitHub Copilot CLI (it can take a few minutes; no progress bar is shown)..."
curl -fsSL https://gh.io/copilot-install | bash

# Make sure ~/.local/bin is on the PATH (idempotent).
line='export PATH="$HOME/.local/bin:$PATH"'
if ! grep -qxF "$line" "$HOME/.bashrc" 2>/dev/null; then
    echo "$line" >> "$HOME/.bashrc"
fi

echo "GitHub Copilot CLI installed. Open a new shell (or run: source ~/.bashrc) and run: copilot"
