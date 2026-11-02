#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "$0")")/lib.sh"

if confirm 'Restore tracked VS Code preferences (conflicts backed up)?'; then "$ROOT/scripts/export-restore-vscode.sh" restore; fi

if confirm 'Restore selected GNOME shortcuts (previous values backed up)?'; then "$ROOT/scripts/export-restore-gnome.sh" restore; fi

if confirm 'Restore legacy GNOME Terminal profile (entire terminal subtree backed up)?'; then
    command -v dconf >/dev/null || { echo 'Install dconf-cli first.' >&2; exit 1; }

    dir="$HOME/.local/state/dotfiles"
    mkdir -p "$dir"
    dconf dump /org/gnome/terminal/ > "$dir/terminal.$(date +%s).$$.dconf"
    dconf load /org/gnome/terminal/ < "$ROOT/preferences/gnome-terminal/config"
fi
