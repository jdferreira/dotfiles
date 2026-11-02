#!/usr/bin/env bash
# Read-only checks: collect failures instead of stopping at the first missing tool.
set -uo pipefail

source "$(dirname -- "$(readlink -f -- "$0")")/lib.sh"
init_brew
missing=0

# Suppress command output so configuration values and daemon details stay private.
check() {
    if "$@" >/dev/null 2>&1; then printf 'OK: %s\n' "$*";
    else printf 'MISSING/REVIEW: %s\n' "$*"; missing=$((missing+1)); fi
}

# Start with executable discovery, then check configuration and connectivity.
for app in git brew docker aws uv ringboard code firefox google-chrome; do check command -v "$app"; done

# Verify identity fields exist without printing their values.
if command -v git >/dev/null; then
    for key in user.name user.email; do
        if git -C "$HOME" config --get "$key" >/dev/null 2>&1; then echo "OK: Git $key configured (value hidden)";
        else echo "REVIEW: configure Git $key privately"; missing=$((missing+1)); fi
    done
fi

# Bound daemon probing so an unreachable Docker context cannot hang validation.
if command -v docker >/dev/null; then
    check timeout 10 docker info
    check docker compose version
    echo 'If daemon unavailable: run ./install --docker (APT); group access requires a new login.'
fi

# Listing profiles is local and does not trigger SSO login or request credentials.
if command -v aws >/dev/null; then
    if [[ $(aws --version 2>&1) != aws-cli/2.* ]]; then echo 'REVIEW: AWS CLI v2 required'; missing=$((missing+1)); fi
    echo 'AWS profile names (no credentials; names may be personal, keep output private):'
    aws configure list-profiles || missing=$((missing+1))
fi

# Toolbox detection is only a hint; IDE installation still needs GUI verification.
if command -v jetbrains-toolbox >/dev/null || [[ -x $HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox ]]; then
    echo 'OK: Toolbox detected; open it to verify IntelliJ and Settings Sync.'
else echo 'REVIEW: install JetBrains Toolbox, then IntelliJ IDEA (README).'; missing=$((missing+1)); fi

# Check managed links separately from the user's independently maintained Git config.
for file in .bashrc .inputrc .vimrc; do
    if [[ -L $HOME/$file && $(readlink -- "$HOME/$file") == "$ROOT/$file" && -e $HOME/$file ]]; then echo "OK: $file link";
    else echo "REVIEW: $file; run ./install --dotfiles"; missing=$((missing+1)); fi
done
check test -f "$HOME/.gitconfig"

# Only require VS Code files that were actually exported into this repository.
for file in settings.json keybindings.json; do
    [[ ! -f $ROOT/preferences/vscode/$file ]] || check test "$HOME/.config/Code/User/$file" -ef "$ROOT/preferences/vscode/$file"
done

# Enforce absence only after the user explicitly completed the removal operation.
if [[ -f $HOME/.local/state/dotfiles/no-snap-flatpak ]]; then
    for app in snap flatpak; do
        if command -v "$app" >/dev/null || dpkg-query -W -f='${Status}' "$([[ $app == snap ]] && echo snapd || echo flatpak)" 2>/dev/null | grep -q 'install ok installed'; then
            echo "REVIEW: $app still installed"; missing=$((missing+1))
        fi
    done
    check test -f /etc/apt/preferences.d/no-snap.pref
fi

# A nonzero exit status lets callers detect incomplete setups without logging in.
echo 'No authentication flows launched. Missing tools: review Brewfile, run --apt/--brew/--docker as needed; see README for GUI apps.'
((missing == 0))
