#!/bin/bash
# Version: 0.4.1
# ia4d (ntm GenAI Suite) for Claude Code in this container: keyring, login (credential renewal) and installer.
# Exclusive to the ntm Claude Code containers. Repo: scripts/bash/ntmsso-iagentic/, seen in the container (read-only)
# as ~/devbox/bash/ntmsso-iagentic/. Run with: bash ~/devbox/bash/ntmsso-iagentic/dkdb-ia4d.sh [all | status | setup | login | renew | install]
# ASCII only, English only, LF line endings (see specs/01-conventions.md). The manual is in README.md.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner="$HOME/.local/bin/dkdb-keyring-run"
tools_dir="$HOME/devbox/tools/iagentic"
# The script that installs the missing tools (one folder up, in ~/devbox/bash).
tools_script="$(cd "$here/.." && pwd)/dkdb-install-tools.sh"
# How the messages tell to run this script: its real path, with ~ for the home folder.
self_cmd="bash ${here/#$HOME/\~}/$(basename "$0")"
marketplace_dir="$HOME/.claude/plugins/marketplaces/ia4d-expert-agents-marketplace"
# command:package needed for the keyring session and the login (the same tools as the base and keyring groups of
# dkdb-install-tools.sh, which installs them when they are missing).
required_tools=(dbus-daemon:dbus gnome-keyring-daemon:gnome-keyring secret-tool:libsecret-tools script:bsdutils curl:curl)

# Colors (spec 01): green success, red warnings and errors, yellow the next step, cyan headings.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    c_green=$'\033[32m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'; c_cyan=$'\033[36m'; c_off=$'\033[0m'
else
    c_green=''; c_red=''; c_yellow=''; c_cyan=''; c_off=''
fi
ok() { printf '%s%s%s\n' "$c_green" "$*" "$c_off"; }
warn() { printf '%s%s%s\n' "$c_red" "$*" "$c_off" >&2; }
next() { printf '%s%s%s\n' "$c_yellow" "$*" "$c_off"; }
title() { printf '\n%s== %s%s\n' "$c_cyan" "$*" "$c_off"; }

usage() {
    local name
    name="$(basename "$0")"
    printf '\n%sNAME%s\n    %s%s%s\n' "$c_cyan" "$c_off" "$c_green" "$name" "$c_off"
    printf '\n%sDESCRIPTION%s\n' "$c_cyan" "$c_off"
    printf '%s\n' "Prepares this container for ia4d (ntm GenAI Suite) in Claude Code: the GNOME keyring where ia4d keeps its session, the SSO login (also to renew the credentials) and the ia4d installer. Every step is idempotent." | fold -s -w 92 | sed 's/ *$//; s/^/    /'
    printf '\n%sUSAGE%s\n    %s%s [all | status | setup | login | renew | install] [-h | man]%s\n' "$c_cyan" "$c_off" "$c_green" "$self_cmd" "$c_off"
    printf '\n%sCOMMANDS%s\n' "$c_cyan" "$c_off"
    printf '    %s%-10s%s %s\n' "$c_green" all "$c_off" 'Default. setup, login if the installer session expired, install, then status.'
    printf '    %s%-10s%s %s\n' "$c_green" status "$c_off" 'Only reads: tools, keyring, session, ia4d files and plugins. Exit code 1 if something is wrong.'
    printf '    %s%-10s%s %s\n' "$c_green" setup "$c_off" 'Tools (installed with dkdb-install-tools.sh when missing) and dkdb-keyring-run in ~/.local/bin (the keyring the installer needs).'
    printf '    %s%-10s%s %s\n' "$c_green" login "$c_off" 'SSO login when the installer session expired. One URL to open, one URL to paste.'
    printf '    %s%-10s%s %s\n' "$c_green" renew "$c_off" 'Renew the credentials: logout, then login.'
    printf '    %s%-10s%s %s\n' "$c_green" install "$c_off" 'Runs the ia4d installer inside the keyring session (logs in first when needed).'
    printf '    %s%-10s%s %s\n' "$c_green" '-h, --help' "$c_off" 'Show this help and exit.'
    printf '    %s%-10s%s %s\n' "$c_green" man "$c_off" 'Show the manual (what each command does, step by step) and exit.'
    printf '\n%sENVIRONMENT%s\n' "$c_cyan" "$c_off"
    printf '    %s%-18s%s %s\n' "$c_green" IA4D_INSTALLER "$c_off" 'Path of ia4d-installer-linux (default: ~/devbox/tools/iagentic, or next to this folder).'
    printf '    %s%-18s%s %s\n' "$c_green" DKDB_KEYRING_PASS "$c_off" 'Keyring password (default: devbox). Never change it once the keyring exists.'
    printf '\n'
}

manual() {
    item() { printf '%s\n' "$2" | fold -s -w 84 | sed "1s/^/    $c_green$1$c_off /;2,\$s/^/        /; s/ *\$//"; }
    printf '\n%sMANUAL%s\n    %s%s%s\n' "$c_cyan" "$c_off" "$c_green" "$(basename "$0")" "$c_off"
    printf '\n%sPURPOSE%s\n' "$c_cyan" "$c_off"
    printf '%s\n' 'The ia4d installer keeps its session in the keyring (Secret Service over D-Bus), which a container does not have; the ia4d plugins use ~/.ia4d/.infra-token and .infra-refresh-token (5 days, renewed by the plugins). This script provides the keyring, logs in through the ia4d SSO bridge (it writes both) and runs the installer. README.md (same folder) explains why and how.' | fold -s -w 92 | sed 's/ *$//; s/^/    /'
    printf '\n%sWHAT IT DOES%s\n' "$c_cyan" "$c_off"
    item 'setup 1.' 'Checks dbus-daemon, gnome-keyring-daemon, secret-tool, script and curl; installs the missing ones with dkdb-install-tools.sh (sudo apt-get). login, renew and install do this check first.'
    item 'setup 2.' 'Copies dkdb-keyring-run.sh to ~/.local/bin/dkdb-keyring-run when it differs.'
    item 'setup 3.' 'Tests the keyring: stores, reads and deletes a test secret.'
    item 'login 1.' 'Starts "ia4d-installer-linux login" in the background inside the keyring session and shows its SSO URL; when the installer says it is already authenticated, it stops there.'
    item 'login 2.' 'Asks for the http://localhost:PORT/callback?... address the browser could not open, without showing it, and sends it to the waiting installer with curl.'
    item 'login 3.' 'Checks that the installer says "Autenticado como"; the session is now in the keyring and in ~/.ia4d/.infra-*.'
    item 'renew' 'Runs "ia4d-installer-linux logout" (it empties the ia4d session) and then the login steps.'
    item 'install' 'Runs ia4d-installer-linux (interactive, in the foreground) inside the keyring session.'
    item 'status' 'Prints each check in green, yellow or red and the next step. Decisive: the plugins session (.infra-refresh-token, 5 days). Informative: the installer session (keyring, 1 hour, expired is normal).'
    printf '\n%sWHAT IT CHANGES%s\n' "$c_cyan" "$c_off"
    item '  -' 'Packages (setup), ~/.local/bin/dkdb-keyring-run, the keyring in ~/.local/share/keyrings, ~/.ia4d and, through the ia4d installer, ~/.claude.'
    printf '\n%sWHAT IT NEVER DOES%s\n' "$c_cyan" "$c_off"
    item '  -' 'Prints or stores a token in a file, the history or the screen.'
    item '  -' 'Touches the host, Mutagen or other containers.'
    printf '\n%sNEXT STEP%s\n' "$c_cyan" "$c_off"
    printf '%s\n' "Run claude as usual. Renew with: $self_cmd renew (at least every 5 days without using claude)." | fold -s -w 92 | sed "s/ *\$//; s/^/    $c_yellow/; s/\$/$c_off/"
    printf '\n'
}

strip_ansi() { sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g'; }
# Never show who is logged in (name, email, role, groups): this output may end up in tickets or documents.
redact() {
    sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/<email>/g; s/(utenticado como) .*/\1 <user>/' |
        grep -avE '^[^A-Za-z]*(Usuario|Email|Rol|Grupos)[: ]'
}

# The installer: IA4D_INSTALLER, else next to this folder, else ~/devbox/tools/iagentic (where it is dropped);
# when only the tarball is there, extract it (this folder may be read-only: the tarball folder must be writable).
find_installer() {
    local candidate tarball
    for candidate in "${IA4D_INSTALLER:-}" "$here/ia4d-installer-linux" "$here/../ia4d-installer-linux" "$tools_dir/ia4d-installer-linux"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            chmod +x "$candidate" 2>/dev/null
            (cd "$(dirname "$candidate")" && printf '%s/%s\n' "$(pwd)" "$(basename "$candidate")")
            return 0
        fi
    done
    tarball="$(ls -1 "$here"/ia4d-installer-linux-x64-*.tar.gz "$here"/../ia4d-installer-linux-x64-*.tar.gz "$tools_dir"/ia4d-installer-linux-x64-*.tar.gz 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$tarball" ]; then
        tar -xzf "$tarball" -C "$(dirname "$tarball")" --exclude='._*' 2>/dev/null &&
            [ -f "$(dirname "$tarball")/ia4d-installer-linux" ] &&
            { chmod +x "$(dirname "$tarball")/ia4d-installer-linux"; find_installer; return $?; }
    fi
    warn "ia4d-installer-linux not found (set IA4D_INSTALLER, or put it or its tar.gz in ~/devbox/tools/iagentic)."
    return 1
}

# Run a command inside the keyring session with a pseudo-terminal (the installer prints nothing without one).
run_in_keyring() { "$runner" script -qfc "$1" /dev/null </dev/null 2>&1 | strip_ansi; }

# whoami output (only the useful lines). Sets session_ok=1 when the session is valid.
session_ok=0
check_session() {
    local installer output
    session_ok=0
    installer="$(find_installer)" || return 1
    output="$(run_in_keyring "$(printf '%q whoami' "$installer")")"
    session_text="$(printf '%s\n' "$output" | grep -aE 'Sesi|No hay sesi|v[0-9]+\.[0-9]+\.[0-9]+ ' | sed 's/^ *//')"
    if printf '%s\n' "$output" | grep -aE 'Sesi' | grep -aq 'lida'; then session_ok=1; fi
    return 0
}

missing_packages() {
    local entry
    for entry in "${required_tools[@]}"; do
        command -v "${entry%%:*}" >/dev/null 2>&1 || printf '%s\n' "${entry#*:}"
    done | sort -u
}

# Before anything else: the tools must be present. Silent when they are; otherwise they are installed with
# dkdb-install-tools.sh (sudo apt-get when that script is not at hand). Returns 1 when they cannot be installed.
step_tools() {
    local missing
    missing="$(missing_packages | tr '\n' ' ' | sed 's/ *$//')"
    [ -z "$missing" ] && return 0
    warn "Missing tools: $missing. Installing them ..."
    if [ -r "$tools_script" ]; then
        bash "$tools_script" base keyring || { warn "Could not install the tools. Try: bash ${tools_script/#$HOME/\~} check"; return 1; }
    else
        # shellcheck disable=SC2086
        { sudo apt-get update -qq && sudo apt-get install -y -qq --no-install-recommends $(missing_packages | tr '\n' ' '); } \
            || { warn "Could not install: $missing"; return 1; }
    fi
    missing="$(missing_packages | tr '\n' ' ' | sed 's/ *$//')"
    if [ -n "$missing" ]; then warn "Still missing: $missing"; return 1; fi
    return 0
}

step_setup() {
    title 'setup'
    step_tools || return 1
    ok "Tools: ok"

    mkdir -p "$(dirname "$runner")"
    if ! cmp -s "$here/dkdb-keyring-run.sh" "$runner"; then
        install -m 0755 "$here/dkdb-keyring-run.sh" "$runner" || { warn "Could not install $runner"; return 1; }
        ok "Installed $runner"
    else
        ok "Runner: $runner up to date"
    fi

    if "$runner" bash -c 'printf ok | secret-tool store --label="dkdb-ia4d self-test" service dkdb-ia4d-test username test &&
            [ "$(secret-tool lookup service dkdb-ia4d-test username test)" = ok ] &&
            secret-tool clear service dkdb-ia4d-test username test' >/dev/null 2>&1; then
        ok "Keyring: ok (~/.local/share/keyrings)"
    else
        warn "Keyring: the self-test failed. If the keyring was created with another password, set DKDB_KEYRING_PASS."
        return 1
    fi
}

# Stop the background login (the runner, script and the installer under it) and remove its temp folder.
login_pid=''; login_tmp=''
stop_login() {
    if [ -n "$login_pid" ]; then
        pkill -TERM -P "$(pgrep -d, -P "$login_pid")" 2>/dev/null
        pkill -TERM -P "$login_pid" 2>/dev/null
        kill "$login_pid" 2>/dev/null
        login_pid=''
    fi
    [ -n "$login_tmp" ] && rm -rf "$login_tmp"
    login_tmp=''
    trap - EXIT INT TERM HUP PIPE
}

step_login() {
    local installer tmpdir log pid url port callback code attempt i
    title 'login'
    installer="$(find_installer)" || return 1
    tmpdir="$(mktemp -d)" && chmod 700 "$tmpdir"
    log="$tmpdir/login.log"
    : > "$log"
    "$runner" script -qfc "$(printf '%q login' "$installer")" "$log" </dev/null >/dev/null 2>&1 &
    pid=$!
    login_pid="$pid"; login_tmp="$tmpdir"
    # Whatever ends this script (Ctrl+C, closed terminal, broken pipe), the background login must not stay behind.
    trap stop_login EXIT
    trap 'exit 130' INT TERM HUP PIPE

    url=''
    for i in $(seq 1 60); do
        url="$(strip_ansi < "$log" | grep -aoE 'https://[^ ]*cli-auth\?port=[0-9]+' | head -n 1)"
        [ -n "$url" ] && break
        if strip_ansi < "$log" | grep -aq 'Ya autenticado'; then
            stop_login
            ok "Login: already authenticated (to force a new login: $self_cmd renew)"
            return 0
        fi
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    if [ -z "$url" ]; then
        warn "The installer did not show the SSO URL. Its output:"
        strip_ansi < "$log" | grep -av -e '^\s*$' -e '^Script ' | redact | tail -n 15 >&2
        stop_login
        return 1
    fi
    port="${url##*port=}"

    next "1. Open this URL in the browser (Windows) and sign in with your ntm account:"
    printf '\n   %s\n\n' "$url"
    next "2. At the end the browser fails to open http://localhost:$port/callback?... That is expected."
    next "3. Copy that whole address from the address bar, paste it here and press Enter (it is not shown)."
    for attempt in 1 2 3; do
        callback=''
        IFS= read -rs -p "   callback URL> " callback; echo
        callback="$(printf '%s' "$callback" | tr -d '[:space:]')"
        if [[ $callback =~ ^http://(localhost|127\.0\.0\.1):$port/ ]]; then break; fi
        warn "   That is not http://localhost:$port/callback?... (attempt $attempt of 3)."
        callback=''
    done
    if [ -z "$callback" ] || ! kill -0 "$pid" 2>/dev/null; then
        [ -n "$callback" ] && warn "The installer stopped waiting (timeout?). Run the login again."
        stop_login
        return 1
    fi
    # The URL goes through stdin (curl -K -), never as an argument, so it never shows up in ps.
    code="$(printf 'url = "%s"\n' "$callback" | curl -s -o /dev/null -w '%{http_code}' --max-time 30 -K -)"
    callback=''
    for i in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    login_tmp=''; stop_login  # stop the installer but keep the log: it is read below, then removed

    if strip_ansi < "$log" | grep -aq 'Autenticado como'; then
        rm -rf "$tmpdir"
        ok "Login: ok (session saved in the keyring and in ~/.ia4d/.infra-*)"
    else
        warn "Login failed (callback HTTP $code). Installer output:"
        strip_ansi < "$log" | grep -av -e '^\s*$' -e '^Script ' | redact | tail -n 15 >&2
        rm -rf "$tmpdir"
        return 1
    fi
}

# renew: close the ia4d session (logout) and log in again. Use it when ia4d asks to re-authenticate.
step_renew() {
    local installer
    title 'renew'
    installer="$(find_installer)" || return 1
    next "Closing the current ia4d session (logout)..."
    run_in_keyring "$(printf '%q logout' "$installer")" | grep -aiE 'sesi|logout|error' | redact | sed 's/^ */   /'
    step_login
}

step_install() {
    local installer
    title 'install'
    installer="$(find_installer)" || return 1
    check_session
    if [ "$session_ok" != 1 ]; then
        next "The installer session (keyring) expired; logging in first."
        step_login || return 1
    fi
    next "Running the ia4d installer ($installer); answer its questions if it asks."
    (cd "$(dirname "$installer")" && "$runner" "$installer") || { warn "The ia4d installer failed."; return 1; }
    ok "ia4d installer finished."
}

# exp claim (epoch seconds) of a JWT file; empty when unreadable. Only the payload is decoded, nothing is printed.
jwt_exp() {
    local payload
    payload="$(cut -d. -f2 "$1" 2>/dev/null | tr '_-' '/+')"
    while [ $(( ${#payload} % 4 )) -ne 0 ]; do payload="$payload="; done
    printf '%s' "$payload" | base64 -d 2>/dev/null | grep -o '"exp":[0-9]*' | cut -d: -f2
}

step_status() {
    local failed=0 missing count line refresh_exp left until_text
    title 'status'
    missing="$(missing_packages | tr '\n' ' ' | sed 's/ *$//')"
    if [ -z "$missing" ]; then ok "  Tools          ok"; else warn "  Tools          missing: $missing ($self_cmd setup)"; failed=1; fi
    if [ -x "$runner" ] && cmp -s "$here/dkdb-keyring-run.sh" "$runner"; then ok "  Runner         $runner"
    else warn "  Runner         missing or outdated ($self_cmd setup)"; failed=1; fi

    # Decisive: what the ia4d plugins use. The access token lasts 1 hour and the plugins renew it with the
    # refresh token (5 days, rotated on each renewal); only when the refresh token expires a login is needed.
    refresh_exp="$(jwt_exp "$HOME/.ia4d/.infra-refresh-token")"
    if [ -s "$HOME/.ia4d/.infra-token" ] && [ -n "$refresh_exp" ]; then
        left=$(( refresh_exp - $(date +%s) ))
        until_text="$(date -d "@$refresh_exp" '+%Y-%m-%d %H:%M %Z')"
        if [ "$left" -le 0 ]; then
            warn "  Plugins        session expired on $until_text ($self_cmd renew)"; failed=1
        elif [ "$left" -lt 86400 ]; then
            next "  Plugins        session valid until $until_text, less than 1 day ($self_cmd renew soon)"
        else
            ok "  Plugins        session valid until $until_text (refresh token; the plugins renew the 1-hour token)"
        fi
    else
        warn "  Plugins        no session: ~/.ia4d/.infra-token or .infra-refresh-token missing ($self_cmd login)"; failed=1
    fi

    # Informative: the installer session in the keyring. It lasts 1 hour and is not renewed; expired is normal,
    # install logs in again when it needs it.
    if [ -z "$missing" ] && [ -x "$runner" ]; then
        count="$("$runner" secret-tool search --all service ia4d 2>/dev/null | grep -c '^label')"
        if check_session && [ "$session_ok" = 1 ]; then
            ok "  Installer      session valid ($count keyring entries)"
        else
            next "  Installer      session expired or absent ($count keyring entries); normal, install logs in when needed"
        fi
        printf '%s\n' "${session_text:-}" | while IFS= read -r line; do [ -n "$line" ] && printf '                 %s\n' "$line"; done
    fi

    if [ -d "$marketplace_dir" ]; then
        count="$(grep -c '@ia4d-expert-agents-marketplace"' "$HOME/.claude/settings.json" 2>/dev/null)"
        ok "  ia4d plugins   marketplace installed, ${count:-0} plugin entries in settings.json"
    else warn "  ia4d plugins   not installed ($self_cmd install)"; failed=1; fi

    if [ "$failed" = 0 ]; then next "Ready. Run claude as usual."
    else next "Next: fix the red lines (or run: $self_cmd all)."; fi
    return "$failed"
}

command='all'
for argument in "$@"; do
    case "$argument" in
        -h|--help) usage; exit 0 ;;
        man) manual; exit 0 ;;
        all|status|setup|login|renew|install) command="$argument" ;;
        *) warn "Unknown argument: $argument (use -h or man)."; exit 1 ;;
    esac
done
script_version="$(sed -n 's/^# Version: *//p' "$0" | head -n 1)"
echo "$(basename "$0") ${script_version:-unknown} (docker-devbox-ubuntu image ${DEVBOX_IMAGE_VERSION:-unknown})"

case "$command" in
    status) step_status ;;
    setup) step_setup ;;
    login) step_tools && step_setup >/dev/null && step_login ;;
    renew) step_tools && step_setup >/dev/null && step_renew ;;
    install) step_tools && step_setup >/dev/null && step_install ;;
    all)
        step_setup || exit 1
        check_session
        if [ "$session_ok" = 1 ]; then ok "Session: valid, no login needed"; else step_login || exit 1; fi
        step_install || exit 1
        step_status ;;
esac
