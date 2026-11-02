#!/usr/bin/env bash
# Real encryption round trips with synthetic fixtures only; no live keys or history.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
cleanup() {
    # Stop only the agent started for the disposable test keyring.
    gpgconf --homedir "$tmp/test-gnupg" --kill all >/dev/null 2>&1 || true
    rm -rf -- "$tmp"
}
trap cleanup EXIT
export HOME="$tmp/home"
export GNUPGHOME="$tmp/test-gnupg"
export REAL_GPG
REAL_GPG=$(command -v gpg)
export TEST_PASSPHRASE_FILE="$tmp/test-passphrase"
mkdir -p "$HOME" "$GNUPGHOME" "$tmp/mock" "$tmp/usb"
chmod 700 "$GNUPGHOME"
printf 'synthetic-test-passphrase\n' > "$TEST_PASSPHRASE_FILE"
chmod 600 "$TEST_PASSPHRASE_FILE"

# Production always prompts; the test wrapper supplies only a disposable test
# passphrase from a private fixture and keeps test S2K work small for fast runs.
# shellcheck disable=SC2016 # Variables must expand in the generated wrapper, not here.
printf '%s\n' '#!/usr/bin/env bash' \
    'exec "$REAL_GPG" --batch --pinentry-mode loopback --passphrase-file "$TEST_PASSPHRASE_FILE" --s2k-count 65536 "$@"' > "$tmp/mock/gpg"
chmod +x "$tmp/mock/gpg"
export PATH="$tmp/mock:$PATH"
script="$ROOT/scripts/backup-restore-private-data.sh"

# All four targets round-trip, verify without changing HOME, preserve conflicts,
# normalize modes, and refuse overwriting the encrypted backup.
for kind in ssh aws git-signing bash-history; do
    case $kind in
        ssh) target=.ssh; file=.ssh/id_test ;;
        aws) target=.aws; file=.aws/config ;;
        git-signing) target=.gnupg; file=.gnupg/private-keys-v1.d/test.key ;;
        bash-history) target=.bash_history; file=.bash_history ;;
    esac
    mkdir -p "$HOME/$(dirname "$file")"
    printf 'SYNTHETIC_PRIVATE_DATA\n' > "$HOME/$file"
    if [[ $kind == aws ]]; then
        mkdir -p "$HOME/.aws/sso/cache"
        printf 'CACHE_MUST_NOT_MIGRATE\n' > "$HOME/.aws/sso/cache/test.json"
    fi

    archive="$tmp/usb/$kind.tar.gpg"
    bash "$script" backup "$kind" "$archive" > "$tmp/output" 2>&1
    if bash "$script" backup "$kind" "$archive" >> "$tmp/output" 2>&1; then exit 1; fi
    printf 'EXISTING_CONFIGURATION\n' > "$HOME/$file"
    bash "$script" verify "$kind" "$archive" >> "$tmp/output" 2>&1
    grep -q EXISTING_CONFIGURATION "$HOME/$file"

    # Declining restore or failing decryption must leave the current target intact.
    bash "$script" restore "$kind" "$archive" <<< n >> "$tmp/output" 2>&1
    grep -q EXISTING_CONFIGURATION "$HOME/$file"
    printf 'wrong-test-passphrase\n' > "$tmp/wrong-passphrase"
    if TEST_PASSPHRASE_FILE="$tmp/wrong-passphrase" bash "$script" restore "$kind" "$archive" <<< y >> "$tmp/output" 2>&1; then exit 1; fi
    grep -q EXISTING_CONFIGURATION "$HOME/$file"

    bash "$script" restore "$kind" "$archive" <<< y >> "$tmp/output" 2>&1
    grep -q SYNTHETIC_PRIVATE_DATA "$HOME/$file"
    [[ $(stat -c %a "$HOME/$file") == 600 ]]
    compgen -G "$HOME/$target.backup.*" >/dev/null
    if [[ $kind != bash-history ]]; then [[ $(stat -c %a "$HOME/$target") == 700 ]]; fi
    if [[ $kind == aws ]]; then [[ ! -e $HOME/.aws/sso ]]; fi
    if grep -Eq 'SYNTHETIC_PRIVATE_DATA|CACHE_MUST_NOT_MIGRATE' "$tmp/output"; then exit 1; fi
done

# AWS helper files are opt-in, round-trip as private data, and are never executed.
# The same selection is required to verify/restore; nested/cache paths are forbidden.
printf 'exit 99 # DO_NOT_EXECUTE_HELPER\n' > "$HOME/.aws/credentials-process.py"
extra_archive="$tmp/usb/aws-extra.tar.gpg"
bash "$script" backup aws "$extra_archive" --aws-file credentials-process.py > "$tmp/output" 2>&1
if bash "$script" verify aws "$extra_archive" >> "$tmp/output" 2>&1; then exit 1; fi
bash "$script" verify aws "$extra_archive" --aws-file credentials-process.py >> "$tmp/output" 2>&1
rm "$HOME/.aws/credentials-process.py"
bash "$script" restore aws "$extra_archive" --aws-file credentials-process.py <<< y >> "$tmp/output" 2>&1
grep -q DO_NOT_EXECUTE_HELPER "$HOME/.aws/credentials-process.py"
[[ $(stat -c %a "$HOME/.aws/credentials-process.py") == 600 ]]
if grep -q DO_NOT_EXECUTE_HELPER "$tmp/output"; then exit 1; fi
for invalid in ../outside sso/cache/test.json sso missing-helper.py; do
    if bash "$script" backup aws "$tmp/usb/invalid.gpg" --aws-file "$invalid" > "$tmp/output" 2>&1; then exit 1; fi
done
mkdir "$HOME/.aws/not-a-file"
if bash "$script" backup aws "$tmp/usb/directory.gpg" --aws-file not-a-file > "$tmp/output" 2>&1; then exit 1; fi

# Reject mixed targets, symlinks, and archives in the checkout before home changes.
if bash "$script" restore ssh "$tmp/usb/aws.tar.gpg" <<< y > "$tmp/output" 2>&1; then exit 1; fi
ln -s /nonexistent "$HOME/.ssh/link"
if bash "$script" backup ssh "$tmp/usb/links.tar.gpg" > "$tmp/output" 2>&1; then exit 1; fi
if bash "$script" backup aws "$ROOT/forbidden-backup.gpg" > "$tmp/output" 2>&1; then exit 1; fi

# Validate archive structure independently of the backup producer: refuse symlinks
# even when they occur inside a correctly encrypted, correctly named target.
mkdir -p "$tmp/unsafe/.ssh"
ln -s /nonexistent "$tmp/unsafe/.ssh/link"
tar -C "$tmp/unsafe" -cf - .ssh | gpg --symmetric --output "$tmp/usb/unsafe.gpg" > "$tmp/output" 2>&1
if bash "$script" restore ssh "$tmp/usb/unsafe.gpg" <<< y > "$tmp/output" 2>&1; then exit 1; fi

printf 'PASS: private backup round trips, verification, conflicts, permissions, cache exclusions, wrong passphrase, unsafe archives\n'
