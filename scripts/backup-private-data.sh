#!/usr/bin/env bash
# Explicit encrypted migration of private data; never called by ./install or --all.
set -euo pipefail
umask 077

source "$(dirname -- "$(readlink -f -- "$0")")/lib.sh"

usage() {
    echo 'Usage: backup-private-data.sh backup|restore|verify TARGET /path/on/USB/backup.tar.gpg'
    echo 'Targets: ssh, aws, git-config, git-signing (GPG), bash-history'
    echo 'Git config: append --git-file HOME_RELATIVE_PATH for additional included config files.'
    echo 'AWS only: append --aws-file NAME for each extra regular file directly in ~/.aws.'
    echo 'Repeat the same selections for backup, verify and restore.'
    echo 'Use a separate archive for each target. GnuPG prompts for the passphrase.'
}

fail() {
    echo "$1" >&2
    exit 1
}

[[ $# -ge 3 ]] || { usage; exit 2; }
mode=$1
kind=$2
archive_input=$3
shift 3
case $mode in backup|restore|verify) ;; *) usage; exit 2 ;; esac
[[ $EUID != 0 ]] || fail 'Run as your normal user, not root.'

# Keep targets explicit: no arbitrary home-directory or credential-store discovery.
# AWS caches are deliberately excluded; GPG selection excludes agent sockets/locks.
case $kind in
    ssh) target=.ssh; candidates=(.ssh) ;;
    aws) target=.aws; candidates=(.aws/config .aws/credentials) ;;
    git-config) target=.gitconfig; candidates=(.gitconfig .gitconfig.local .config/git/config) ;;
    git-signing)
        target=.gnupg
        candidates=(.gnupg/private-keys-v1.d .gnupg/openpgp-revocs.d
            .gnupg/pubring.kbx .gnupg/pubring.gpg .gnupg/secring.gpg
            .gnupg/trustdb.gpg .gnupg/tofu.db .gnupg/gpg.conf
            .gnupg/gpg-agent.conf .gnupg/common.conf)
        ;;
    bash-history) target=.bash_history; candidates=(.bash_history) ;;
    *) usage; exit 2 ;;
esac

# Extra AWS files are explicit top-level filenames, never paths/directories.
# Do not parse or execute credential_process commands to discover dependencies.
aws_extras=()
git_extras=()
while (($#)); do
    [[ $# -ge 2 ]] || { usage; exit 2; }
    name=$2
    case "$kind:$1" in
        aws:--aws-file)
            [[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || fail 'AWS extra must be a filename directly inside the AWS directory.'
            candidate=".aws/$name"
            aws_extras+=("$candidate")
            ;;
        git-config:--git-file)
            # Home-relative, explicit config files only: do not follow includes,
            # read credential stores, or execute helpers to discover dependencies.
            [[ $name =~ ^[a-zA-Z0-9._-][a-zA-Z0-9._/@+\ -]*$ && $name != */ ]] || fail 'Git extra must be a home-relative file path.'
            case /$name/ in */../*|*/./*|*//*) fail 'Git extra contains an unsafe path.' ;; esac
            case $name in .git-credentials|.config/git/credentials) fail 'Git credential stores are not supported; reauthenticate using a secure helper.' ;; esac
            candidate=$name
            git_extras+=("$candidate")
            ;;
        *) usage; exit 2 ;;
    esac
    for existing in "${candidates[@]}"; do
        [[ $existing != "$candidate" ]] || fail 'Duplicate file selection (standard files are already included).'
    done
    candidates+=("$candidate")
    shift 2
done

# Git config may live under multiple directories. Refuse symlinked ancestors
# instead of reading/writing private files outside the explicitly selected paths.
check_git_parents() {
    local parent
    parent=$(dirname -- "$HOME/$1")
    while [[ $parent != "$HOME" && $parent != / ]]; do
        [[ ! -L $parent && ( ! -e $parent || -d $parent ) ]] || fail 'Git config parent must be a real directory, not a link or file.'
        parent=$(dirname -- "$parent")
    done
}

for command in gpg tar realpath find stat; do
    command -v "$command" >/dev/null || fail "Required command missing: $command"
done

# Resolve symlinked parents too: private archives do not belong in this checkout.
archive=$(realpath -m -- "$archive_input")
case $archive in
    "$ROOT"|"$ROOT"/*) fail 'Choose an archive outside the dotfiles checkout, ideally on a mounted USB drive.' ;;
esac
for candidate in "${candidates[@]}"; do
    source_path=$(realpath -m -- "$HOME/$candidate")
    case $archive in
        "$source_path"|"$source_path"/*) fail 'The archive must be outside the data being backed up.' ;;
    esac
done

work=''
encrypted=''
stage=''
cleanup() {
    [[ -z $work ]] || rm -rf -- "$work"
    [[ -z $encrypted ]] || rm -f -- "$encrypted"
    [[ -z $stage ]] || rm -rf -- "$stage"
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ $mode == backup ]]; then
    [[ ! -L $HOME/$target ]] || fail 'The backup source must not be a symlink.'
    [[ -d $(dirname -- "$archive") ]] || fail 'Destination directory missing. Mount the USB drive first.'
    [[ ! -e $archive && ! -L $archive ]] || fail 'Archive already exists; choose a new filename.'

    # Keyboxd uses a live database not covered by this portable file selection.
    if [[ $kind == git-signing && -d $HOME/.gnupg/public-keys.d ]]; then
        fail 'Keyboxd detected. Use GnuPG export/import with a separate encrypted backup instead.'
    fi

    for extra in "${aws_extras[@]}" "${git_extras[@]}"; do
        [[ -f $HOME/$extra ]] || fail 'A selected extra is missing or is not a regular file.'
    done

    sources=()
    for candidate in "${candidates[@]}"; do
        path="$HOME/$candidate"
        [[ -e $path || -L $path ]] || continue
        if [[ $kind == git-config ]]; then check_git_parents "$candidate"; fi
        if [[ ( $kind == aws || $kind == git-config ) && ! -f $path ]]; then
            fail 'AWS and Git config selections must be regular files, never directories.'
        fi

        # Reject links and special files, rather than following external targets or
        # silently omitting potentially important data. Never print filenames/content.
        special=$(find "$path" ! -type d ! -type f -print -quit)
        [[ -z $special ]] || fail 'Selected source contains links or special files; handle them separately.'
        sources+=("$candidate")
    done
    ((${#sources[@]})) || fail 'No files found for this target.'

    if [[ $kind == bash-history ]]; then
        [[ -f $HOME/$target ]] || fail 'Bash history must be a regular file.'
    elif [[ $kind != git-config ]]; then
        [[ -d $HOME/$target ]] || fail 'The source must be a directory.'
    fi

    # Encrypt a stream: no plaintext archive is written to the USB or disk.
    # Publish without replacing an existing file; clean up partial encrypted output.
    encrypted=$(mktemp "$(dirname -- "$archive")/.private-backup.XXXXXXXX.gpg")
    echo 'GnuPG will request a backup passphrase. Store it separately from the USB.'
    tar --hard-dereference -C "$HOME" -cf - -- "${sources[@]}" |
        gpg --no-symkey-cache --symmetric --cipher-algo AES256 --output "$encrypted" --yes
    mv -n -- "$encrypted" "$archive"
    [[ ! -e $encrypted ]] || fail 'Destination appeared during backup; nothing was overwritten.'
    encrypted=''
    echo 'Encrypted backup created. Run verify before relying on it; safely eject the USB afterwards.'
    exit 0
fi

[[ -f $archive ]] || fail 'Encrypted archive not found.'

# Decrypt only into private Linux tmpfs, never a plaintext archive on persistent disk.
# Do not trust TMPDIR/XDG_RUNTIME_DIR to reside on a memory-backed filesystem.
[[ -d /dev/shm && -w /dev/shm ]] || fail 'Writable /dev/shm tmpfs is required for secure staging.'
[[ $(stat -f -c %T /dev/shm) == tmpfs ]] || fail '/dev/shm must be a tmpfs mount.'
work=$(mktemp -d /dev/shm/dotfiles-private.XXXXXXXX)
gpg --no-symkey-cache --output "$work/archive.tar" --decrypt "$archive"

# Validate types and paths before extraction. Never follow archive links or accept
# traversal, devices, or a different target's archive. Listings stay in private tmpfs.
tar --list --verbose --file="$work/archive.tar" > "$work/types"
if ! awk 'substr($0,1,1) != "-" && substr($0,1,1) != "d" { bad=1 } END { exit bad }' "$work/types"; then
    fail 'Unsafe archive: only regular files and directories are supported.'
fi

tar --list --quoting-style=literal --file="$work/archive.tar" > "$work/paths"
[[ -s $work/paths ]] || fail 'Archive is empty.'
while IFS= read -r entry; do
    if [[ $kind == git-config ]]; then
        allowed=false
        for candidate in "${candidates[@]}"; do
            [[ $entry != "$candidate" ]] || allowed=true
        done
        "$allowed" || fail 'Git archive contains unselected files; repeat the original --git-file selections.'
    else
        case $entry in
            "$target"|"$target/"|"$target/"*) ;;
            *) fail 'Archive contains a path outside the selected target.' ;;
        esac
    fi
    case /$entry/ in */../*|*/./*) fail 'Archive contains an unsafe path.' ;; esac

    # Even a manually created AWS archive must not transfer SSO caches.
    if [[ $kind == aws ]]; then
        allowed=false
        case $entry in .aws|.aws/) allowed=true ;; esac
        for candidate in "${candidates[@]}"; do
            [[ $entry != "$candidate" ]] || allowed=true
        done
        "$allowed" || fail 'AWS archive contains unselected files or caches. Repeat the original --aws-file selections.'
    fi
done < "$work/paths"

mkdir "$work/extracted"
tar --extract --file="$work/archive.tar" --directory="$work/extracted" \
    --no-same-owner --no-same-permissions --keep-old-files
# Git config is a set of independent files, not a directory to replace wholesale.
# Restore only archived files, preserving other ~/.config/git files and missing
# optional configurations. Never merge or rewrite identities, aliases or includes.
if [[ $kind == git-config ]]; then
    git_files=()
    for candidate in "${candidates[@]}"; do
        path="$work/extracted/$candidate"
        [[ -e $path ]] || continue
        [[ -f $path ]] || fail 'Git config archive must contain only regular files.'
        chmod 600 "$path"
        git_files+=("$candidate")
    done
    for extra in "${git_extras[@]}"; do
        [[ -f $work/extracted/$extra ]] || fail 'Git archive is missing a selected extra file.'
    done
    ((${#git_files[@]})) || fail 'Git config archive has no configuration files.'

    if [[ $mode == verify ]]; then
        echo 'Verified: Git config archive decrypts and contains restorable files. No home files changed.'
        exit 0
    fi

    # Preflight every parent before changing any file; do not follow existing
    # destination symlinks. Existing file symlinks themselves are backed up.
    for candidate in "${git_files[@]}"; do check_git_parents "$candidate"; done
    if ! confirm 'Restore archived Git config files verbatim, backing up existing files first?'; then exit 0; fi
    stage=$(mktemp -d "$HOME/.private-restore.XXXXXXXX")
    cp -a -- "$work/extracted/." "$stage/"
    for candidate in "${git_files[@]}"; do
        mkdir -p -- "$(dirname -- "$HOME/$candidate")"
        backup "$HOME/$candidate"
        mv -- "$stage/$candidate" "$HOME/$candidate"
    done
    echo 'Git configuration restored as private files (600). Review includes, identity and machine-specific paths locally.'
    exit 0
fi

if [[ $kind == bash-history ]]; then
    [[ -f $work/extracted/$target ]] || fail 'Archive has no history file.'
else
    [[ -d $work/extracted/$target ]] || fail 'Archive has no target directory.'
fi

# AWS extras must be files on restore too, even for manually created archives.
if [[ $kind == aws ]]; then
    for candidate in "${candidates[@]}"; do
        path="$work/extracted/$candidate"
        [[ ! -e $path || -f $path ]] || fail 'AWS archive contains a directory where a file was expected.'
    done
    for extra in "${aws_extras[@]}"; do
        [[ -f $work/extracted/$extra ]] || fail 'AWS archive is missing a selected extra file.'
    done
fi

# Conservative permissions suit keys, configs, history, and public key material.
find "$work/extracted/$target" -type d -exec chmod 700 {} +
find "$work/extracted/$target" -type f -exec chmod 600 {} +

if [[ $mode == verify ]]; then
    echo 'Verified: archive decrypts and contains restorable data. No home files changed.'
    exit 0
fi

# Restore a complete target, not a merge. Preserve any existing setup alongside it.
# Stage in HOME so the final rename stays on the destination filesystem.
echo "Restoring $kind replaces ~/$target; its current contents will be backed up."
if ! confirm 'Continue? Close applications using these files first.'; then exit 0; fi
stage=$(mktemp -d "$HOME/.private-restore.XXXXXXXX")
if ! cp -a -- "$work/extracted/$target" "$stage/$target"; then
    fail 'Could not stage restore; the current target was not changed.'
fi
backup "$HOME/$target"
mv -- "$stage/$target" "$HOME/$target"
rmdir -- "$stage"
stage=''
echo 'Restored with directories 700 and files 600. Review machine-specific configuration before use.'
