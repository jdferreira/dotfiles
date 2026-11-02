#!/usr/bin/env bash
# Shared by installers; no system changes on source.

# shellcheck disable=SC2034 # Used by callers.
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Preserve existing files and broken symlinks; avoid backup-name collisions.
backup() {
    local target=$1 saved
    if [[ -e $target || -L $target ]]; then
        saved="${target}.backup.$(date +%Y%m%d-%H%M%S).$$"
        while [[ -e $saved || -L $saved ]]; do saved+=.1; done
        mv -- "$target" "$saved"
        printf 'Backed up %s -> %s\n' "$target" "$saved"
    fi
}

# Leave matching links alone; back up any other target before linking.
link_file() {
    local source=$1 target=$2
    [[ -L $target && $(readlink -- "$target") == "$source" ]] && return 0

    mkdir -p -- "$(dirname -- "$target")"
    backup "$target"
    ln -s -- "$source" "$target"
}

# Only an explicit y/Y approves an operation; EOF and all other input decline.
confirm() {
    local answer
    printf '%s [y/N] ' "$1" >&2
    read -r answer || return 1
    [[ $answer == y || $answer == Y ]]
}

# Make an existing Linux Homebrew installation available in this process.
# This does not install Homebrew or persist shell configuration.
init_brew() {
    if ! command -v brew >/dev/null; then
        local brew
        for brew in /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
            if [[ -x $brew ]]; then eval "$("$brew" shellenv)"; break; fi
        done
    fi
}
