#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "$0")")/lib.sh"

mapfile -t packages < <(grep -Ev '^\s*(#|$)' "$ROOT/packages/apt.txt")
printf 'APT packages: %s\n' "${packages[*]}"

if confirm 'Install these system packages?'; then
    sudo apt update
    sudo apt install "${packages[@]}"
fi
