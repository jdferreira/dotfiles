#!/usr/bin/env bash
# Minimal system fallback: do not shadow the distro's full Portuguese layout.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "$0")")/lib.sh"

file=/usr/share/X11/xkb/symbols/pt
tmp=$(mktemp); trap 'rm -f -- "$tmp"' EXIT

# Build a candidate without modifying the installed layout.
# Patch only TLDE in the basic section, not variant definitions.
# Require exactly one recognized key definition; reject unexpected distro formats.
awk '
/xkb_symbols "basic"/ { basic=1 }
basic && /key <TLDE>/ {
    if ($0 !~ /backslash, *bar,/) exit 2
    sub(/\[.*\]/, "[ backslash, bar, grave, notsign ]")
    found++
}
{ print }
/^};/ { basic=0 }
END { if (found != 1) exit 3 }
' "$file" > "$tmp" || { echo 'Unrecognized Portuguese layout; patch manually. Nothing changed.' >&2; exit 1; }

# Reruns need no sudo, confirmation or extra backup when the mapping already matches.
if cmp -s "$file" "$tmp"; then echo 'Portuguese layout already patched.'; exit 0; fi

# Only this confirmed section writes system files; preserve the original first.
if confirm 'Patch system Portuguese basic TLDE mapping (backup created)?'; then
    sudo cp -a "$file" "$file.backup.$(date +%s).$$"
    sudo install -m 644 "$tmp" "$file"
    echo 'Log out/in. Reapply after xkeyboard-config upgrades. Select Portuguese basic layout.'
fi
