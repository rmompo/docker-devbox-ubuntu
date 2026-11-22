#!/bin/bash
# Version: 0.1.2
# Run a command inside a private D-Bus session with the GNOME keyring unlocked (default command: claude).
# ia4d keeps its session (jwt_token, refresh_token...) in the keyring (Secret Service over D-Bus), so the
# ia4d installer and Claude Code (its plugins and hooks) must run inside such a session to find it.
# Installed as ~/.local/bin/dkdb-keyring-run by dkdb-ntm-ssologin-ia4d.sh setup. ASCII only, English only, LF line endings.
set -uo pipefail

case "${1:-}" in
    -h|--help)
        # Wrapped at the words to the width of the terminal (80 when it cannot be known).
        columns="$(stty size <&2 2>/dev/null | awk '{print $2}')" || columns=''
        [ "${columns:-0}" -ge 40 ] 2>/dev/null || columns=80
        printf '%s\n' "usage: dkdb-keyring-run [command [args...]]   (default command: claude)" \
            "Runs the command inside a D-Bus session with the keyring ~/.local/share/keyrings unlocked." \
            "The keyring password is DKDB_KEYRING_PASS (default: devbox); it must never change." | fold -s -w $((columns - 1))
        exit 0 ;;
esac
[ "$#" -gt 0 ] || set -- claude

# Nested call (already inside a session started by this script): just run the command.
if [ -n "${DKDB_KEYRING_SESSION:-}" ] && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    exec "$@"
fi

for tool in dbus-daemon gnome-keyring-daemon; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "dkdb-keyring-run: $tool is missing; run: bash dkdb-ntm-ssologin-ia4d.sh setup" >&2
        exit 127
    fi
done

keyrings="${XDG_DATA_HOME:-$HOME/.local/share}/keyrings"
mkdir -p "$keyrings" && chmod 700 "$keyrings"

# A private session bus. Its messages go to /dev/null so they never show up inside the claude screen.
bus="$(dbus-daemon --session --fork --print-address=1 --print-pid=1 2>/dev/null)" || {
    echo "dkdb-keyring-run: could not start dbus-daemon" >&2; exit 1; }
bus_address="$(printf '%s\n' "$bus" | sed -n 1p)"
bus_pid="$(printf '%s\n' "$bus" | sed -n 2p)"
export DBUS_SESSION_BUS_ADDRESS="$bus_address" DKDB_KEYRING_SESSION=1
cleanup() { kill "$bus_pid" 2>/dev/null; }
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Start the keyring daemon on that bus and unlock (or create, the first time) the 'login' keyring.
# An empty password does not work without a display (it opens a prompt), hence a fixed one.
keyring_env="$(printf '%s\n' "${DKDB_KEYRING_PASS:-devbox}" | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null)"
eval "$keyring_env"
export GNOME_KEYRING_CONTROL

"$@"
exit $?
