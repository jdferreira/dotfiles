#!/usr/bin/env bash
# Keep software operations independent; system-changing branches ask permission.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "$0")")/lib.sh"

case ${1:-} in
    brew)
        # Reuse an existing installation before offering upstream's bootstrap script.
        init_brew
        if ! command -v brew >/dev/null; then
            if ! confirm 'Download and run the official Homebrew installer (may request sudo)?'; then exit 0; fi
            tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
            curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$tmp/install.sh"
            bash "$tmp/install.sh"
            init_brew
        fi

        # The reviewed manifest, not a hardcoded inventory, controls formula installs.
        brew bundle --file="$ROOT/Brewfile"
        ;;

    apps)
        # Fragile/platform-specific GUI and daemon installs remain guided steps.
        printf '%s\n' \
            'Review Brewfile for CLI tools; Docker is installed separately through APT.' \
            'GUI installers and Ringboard: follow README.md#applications.' \
            'Docker Engine, CLI and Compose: ./install --docker (official Docker APT repository).'
        ;;

    firefox)
        # Use Mozilla's signed repository instead of Ubuntu's Snap transition package.
        command -v gpg >/dev/null || { echo 'Run --apt first.' >&2; exit 1; }
        if ! confirm 'Configure Mozilla official APT repository, pin Firefox and install it system-wide?'; then exit 0; fi
        tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
        curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o "$tmp/key"

        # Fingerprint published by Mozilla; fail closed on key rotation.
        fingerprint=$(gpg --show-keys --with-colons "$tmp/key" | awk -F: '$1=="fpr" {print $10; exit}')
        [[ $fingerprint == 35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3 ]] || { echo 'Mozilla key changed; verify official instructions.' >&2; exit 1; }

        # Stage repository files locally before touching /etc.
        printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' > "$tmp/mozilla.list"
        printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > "$tmp/mozilla.pref"

        # Preserve conflicting repository configuration; identical files need no rewrite.
        sudo mkdir -p /etc/apt/keyrings
        for pair in 'key /etc/apt/keyrings/packages.mozilla.org.asc' 'mozilla.list /etc/apt/sources.list.d/mozilla.list' 'mozilla.pref /etc/apt/preferences.d/mozilla'; do
            read -r source target <<< "$pair"
            if ! sudo cmp -s "$tmp/$source" "$target"; then
                if sudo test -e "$target"; then sudo cp -a "$target" "$target.backup.$(date +%s).$$"; fi
                sudo install -m 644 "$tmp/$source" "$target"
            fi
        done

        sudo apt-get update
        sudo apt-get install firefox
        ;;

    remove-snap-flatpak)
        # Let the user review apps and back up their data before destructive changes.
        echo 'Back up any Snap/Flatpak application data privately first. Review installed apps:'
        if command -v snap >/dev/null; then snap list; fi
        if command -v flatpak >/dev/null; then flatpak list --app --columns=application; fi
        echo 'Close apps. Remove listed Snap apps manually (snap remove NAME), bases last.'
        echo 'Remove Flatpak apps manually, for both user and system installations.'
        if ! confirm 'Purge snapd and flatpak and block snapd in APT? Application data may be lost.'; then exit 0; fi

        # Block future APT reinstalls as well as removing the current frameworks.
        tmp=$(mktemp); trap 'rm -f -- "$tmp"' EXIT
        printf 'Package: snapd\nPin: release *\nPin-Priority: -10\n' > "$tmp"
        target=/etc/apt/preferences.d/no-snap.pref
        if ! sudo cmp -s "$tmp" "$target"; then
            if sudo test -e "$target"; then sudo cp -a "$target" "$target.backup.$(date +%s).$$"; fi
            sudo install -m 644 "$tmp" "$target"
        fi

        sudo apt-get purge snapd flatpak

        # Record successful removal so validation knows absence was requested.
        mkdir -p "$HOME/.local/state/dotfiles"
        touch "$HOME/.local/state/dotfiles/no-snap-flatpak"
        ;;

    keyboard) "$ROOT/scripts/new-laptop-configure-keyboard.sh" ;;
    *) exit 2 ;;
esac
