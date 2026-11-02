#!/usr/bin/env bash
# Read-only: no fetch, checkout, stash or push. Never prints diffs or remote URLs.
set -euo pipefail

base=${1:-"$HOME/Repos"}
[[ -d $base ]] || { echo "$base missing; nothing scanned."; exit 0; }

echo 'Checking local remote-tracking refs only; fetch each repo yourself for current results.'
echo 'Untracked and ignored filenames are listed (not contents); keep this report private.'
issues=0

# NUL-delimited paths support spaces; .git may be a directory or worktree file.
# Prune Git internals while still discovering nested working repositories.
while IFS= read -r -d '' entry; do
    repo=${entry%/.git}
    if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        printf 'Cannot inspect: %s\n' "$repo"; issues=1; continue
    fi

    printf '\nRepository: %q\n' "$repo"

    # Count unpublished work without exposing contents or remote URLs.
    # Remote-tracking refs are local snapshots, not a live remote verification.
    dirty=$(git -C "$repo" status --porcelain --untracked-files=normal | wc -l)
    unpublished=$(git -C "$repo" rev-list --count --branches HEAD --not --remotes 2>/dev/null || echo unknown)
    stashes=$(git -C "$repo" stash list --format='%gd' | wc -l)
    no_upstream=$(git -C "$repo" for-each-ref --format='%(upstream)' refs/heads | grep -c '^$' || true)

    if ((dirty || stashes || no_upstream)) || [[ $unpublished != 0 ]]; then
        printf '%s: changed/untracked entries=%s, commits not on known remotes=%s, stashes=%s, branches without upstream=%s\n' \
            "$repo" "$dirty" "$unpublished" "$stashes" "$no_upstream"
        issues=1
    fi

    # List individual untracked files, including files inside untracked directories.
    # Exclude ignored files; shell-escape names so newlines/control characters are safe.
    while IFS= read -r -d '' file; do
        printf '  Untracked: %q\n' "$file"
    done < <(git -C "$repo" ls-files --others --exclude-standard -z)

    # Collapse ignored directories to a single entry instead of listing their contents.
    # Git may also emit non-ignored parent directories; do not label those as ignored.
    # Keep this loop in the current shell so an ignored-only repo also triggers review.
    while IFS= read -r -d '' file; do
        if [[ $file == */ ]] && ! git -C "$repo" check-ignore -q -- "$file"; then
            continue
        fi

        printf '  Ignored: %q\n' "$file"
        issues=1
    done < <(git -C "$repo" ls-files --others --ignored --exclude-standard --directory -z)
done < <(find "$base" -name .git -print0 -prune)

# This is an advisory migration report, not an automatic publish/backup operation.
if ((issues)); then echo 'Review these repos privately before migration, including ignored files. Bare repos are not audited.'
else echo 'No unpublished changes found in detected working repositories (cached refs only).'; fi
