#!/bin/bash
# Install Claude Code (latest) in this container.
# Rule: one AI client per container. Run with: bash install-claudecode.sh
set -euo pipefail

# Refuse to install if the other client is already present.
if command -v copilot >/dev/null 2>&1 || [ -e "$HOME/.local/bin/copilot" ]; then
    echo "GitHub Copilot CLI is already installed here." >&2
    echo "Use another container to install Claude Code." >&2
    exit 1
fi

echo "Downloading and installing Claude Code (about 240 MB, it can take a few minutes; no progress bar is shown)..."
curl -fsSL https://claude.ai/install.sh | bash

# Make sure ~/.local/bin is on the PATH (idempotent).
line='export PATH="$HOME/.local/bin:$PATH"'
if ! grep -qxF "$line" "$HOME/.bashrc" 2>/dev/null; then
    echo "$line" >> "$HOME/.bashrc"
fi

echo "Claude Code installed. Open a new shell (or run: source ~/.bashrc) and run: claude"
