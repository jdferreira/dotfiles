#!/usr/bin/env bash
# Export/restore only the shortcut keys explicitly selected in the allowlist.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "$0")")/lib.sh"

if ! command -v dconf >/dev/null || ! command -v gsettings >/dev/null; then
    echo 'Install dconf-cli and run inside a GNOME session.' >&2; exit 1
fi

mode=${1:-}
[[ $mode == export || $mode == restore ]] || exit 2
mkdir -p "$ROOT/preferences/gnome"

# Validate allowlist entries before deriving dconf paths and repository filenames.
while read -r schema key extra; do
    [[ -z $schema || $schema == \#* ]] && continue
    [[ -z $extra && $schema =~ ^org\.gnome\.[a-z.-]+$ && $key =~ ^[a-z-]+$ ]] || exit 2

    # GNOME versions differ: missing schemas/keys should not block other shortcuts.
    if ! gsettings list-keys "$schema" 2>/dev/null | grep -Fxq -- "$key"; then
        echo "Skipping unavailable $schema/$key"; continue
    fi

    path="/${schema//.//}/$key"
    file="$ROOT/preferences/gnome/$schema.$key.gvariant"

    if [[ $mode == export ]]; then
        value=$(dconf read "$path")
        # No value means distro default; never reset another machine's defaults.
        if [[ -n $value ]]; then
            backup "$file"
            printf '%s\n' "$value" > "$file"
        elif [[ -e $file ]]; then backup "$file"; fi
    elif [[ -f $file ]]; then
        value=$(<"$file")
        current=$(dconf read "$path")
        [[ $value == "$current" ]] && continue

        # Keep the previous value privately so each changed key can be undone.
        state="$HOME/.local/state/dotfiles/gnome"
        mkdir -p "$state"
        printf '%s\n' "$current" > "$state/$schema.$key.$(date +%s).$$.before"

        # gsettings validates schema types/ranges and writes through the dconf backend.
        if ! gsettings set "$schema" "$key" "$value" 2>/dev/null; then
            echo "Could not restore $schema/$key; review GNOME version compatibility." >&2
        fi
    fi
done < "$ROOT/preferences/gnome-keys.txt"
