#!/usr/bin/env bash
# Migrate selected editable settings and extension IDs, never editor storage.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "$0")")/lib.sh"

dir="$HOME/.config/Code/User"
tracked="$ROOT/preferences/vscode"

case ${1:-} in
    export)
        # Settings must be reviewed privately before they enter the checkout.
        echo 'Settings can contain tokens, private URLs and paths. Review/redact privately first.'
        if confirm 'Copy ONLY reviewed settings.json and keybindings.json into the repo?'; then
            for file in settings.json keybindings.json; do
                if [[ -f $dir/$file ]]; then backup "$tracked/$file"; cp -- "$dir/$file" "$tracked/$file"; fi
            done
        fi

        # Record IDs rather than copying extension binaries or their cached data.
        command -v code >/dev/null || { echo 'code CLI missing.' >&2; exit 1; }
        backup "$tracked/extensions.txt"
        code --list-extensions | LC_ALL=C sort -u > "$tracked/extensions.txt"
        echo 'Edit preferences/vscode/extensions.txt to keep only relevant extensions; review before commit.'
        ;;

    restore)
        # Missing exports are optional; existing target files are backed up by link_file.
        for file in settings.json keybindings.json; do
            [[ ! -f $tracked/$file ]] || link_file "$tracked/$file" "$dir/$file"
        done

        # Allow comments/blank lines, but reject anything other than publisher.name IDs.
        if command -v code >/dev/null; then
            while IFS= read -r extension; do
                [[ -z $extension || $extension == \#* ]] && continue
                [[ $extension =~ ^[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+$ ]] || { echo 'Invalid extension ID' >&2; exit 1; }
                code --install-extension "$extension"
            done < "$tracked/extensions.txt"
        else echo 'Install VS Code and rerun --preferences to install extensions.'; fi
        ;;
    *) exit 2 ;;
esac
