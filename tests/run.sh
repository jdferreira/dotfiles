#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)

# Isolate all file/Git changes from the real home and remove fixtures on exit.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
mkdir -p "$HOME" "$tmp/work"

# Seed regular-file conflicts, an existing Git identity, and a broken symlink.
printf 'original\n' > "$HOME/.bashrc"
printf '[user]\n name = Test\n email = test@example.invalid\n' > "$HOME/.gitconfig"
printf 'input\n' > "$HOME/.inputrc"
ln -s missing "$HOME/.vimrc"

# Installation must work outside the checkout, create links, preserve Git config,
# and back up both regular files and broken symlinks instead of overwriting them.
cd "$tmp/work"
"$ROOT/install" --dotfiles > "$tmp/first"
[[ -L $HOME/.bashrc && $(<"$HOME/.gitconfig") == *'Test'* ]]
compgen -G "$HOME/.bashrc.backup.*" >/dev/null
# .inputrc is no longer installed; leave any existing file untouched.
[[ ! -L $HOME/.inputrc && $(<"$HOME/.inputrc") == input ]]
compgen -G "$HOME/.vimrc.backup.*" >/dev/null

# A second run must not create more backups when links already match.
before=$(find "$HOME" -name '*.backup.*' | wc -l)
"$ROOT/install" --dotfiles > "$tmp/second"
[[ $(find "$HOME" -name '*.backup.*' | wc -l) == "$before" ]]

# Help must succeed without package/system operations; unknown flags must fail
# rather than accidentally launching an installation.
"$ROOT/install" --help >/dev/null
if "$ROOT/install" --invalid >/dev/null 2>&1; then exit 1; fi

# The repository audit must handle spaces and report both an untracked file
# and a local commit that is absent from all known remote-tracking refs.
mkdir -p "$HOME/Repos/project space"
repo="$HOME/Repos/project space"
git -C "$repo" init -q
git -C "$repo" -c commit.gpgsign=false commit --allow-empty -qm initial
printf 'untracked\n' > "$repo/file"
"$ROOT/scripts/old-laptop-check-repos.sh" > "$tmp/repos"
grep -q 'changed/untracked entries=1' "$tmp/repos"
grep -q 'commits not on known remotes=1' "$tmp/repos"

# List untracked and ignored filenames separately and safely, never their contents.
mkdir "$repo/new directory"
printf 'PRIVATE_CONTENT_MARKER\n' > "$repo/new directory/file name"
printf 'PRIVATE_CONTENT_MARKER\n' > "$repo/"$'line\nbreak'
printf 'ignored-secret\nignored directory/\n*.secret\n' > "$repo/.git/info/exclude"
printf 'PRIVATE_CONTENT_MARKER\n' > "$repo/ignored-secret"
mkdir "$repo/ignored directory"
printf 'PRIVATE_CONTENT_MARKER\n' > "$repo/ignored directory/file name"
printf 'PRIVATE_CONTENT_MARKER\n' > "$repo/ignored directory/"$'line\nbreak'
mkdir "$repo/normal directory"
printf 'PRIVATE_CONTENT_MARKER\n' > "$repo/normal directory/file.secret"
"$ROOT/scripts/old-laptop-check-repos.sh" > "$tmp/repos"
grep -Fq '  Untracked: file' "$tmp/repos"
grep -Fq '  Untracked: new\ directory/file\ name' "$tmp/repos"
grep -Fq "  Untracked: \$'line\\nbreak'" "$tmp/repos"
grep -Fq '  Ignored: ignored-secret' "$tmp/repos"
# Ignored directories appear once; ignored files in non-ignored directories remain visible.
[[ $(grep -Fxc '  Ignored: ignored\ directory/' "$tmp/repos") == 1 ]]
if grep -Fq '  Ignored: ignored\ directory/file' "$tmp/repos"; then exit 1; fi
[[ $(grep -c '^  Ignored:' "$tmp/repos") == 3 ]]
grep -Fq '  Ignored: normal\ directory/file.secret' "$tmp/repos"
if grep -Fxq '  Ignored: normal\ directory/' "$tmp/repos"; then exit 1; fi
if grep -Eq 'PRIVATE_CONTENT_MARKER|Untracked: ignored-secret' "$tmp/repos"; then exit 1; fi
rm "$repo/new directory/file name" "$repo/"$'line\nbreak'
rmdir "$repo/new directory"

# Simulate a published, clean branch using local refs only (no network fetch).
# Once its upstream exists and untracked files are removed, ignored files must
# still trigger a review with a repository heading, even though Git status is clean.
git -C "$repo" remote add origin "$tmp/unused-remote"
git -C "$repo" update-ref refs/remotes/origin/main HEAD
rm "$repo/file"
git -C "$repo" config "branch.$(git -C "$repo" branch --show-current).remote" origin
git -C "$repo" config "branch.$(git -C "$repo" branch --show-current).merge" refs/heads/main
"$ROOT/scripts/old-laptop-check-repos.sh" > "$tmp/repos"
grep -Fq 'Repository:' "$tmp/repos"
grep -Fq '  Ignored: ignored-secret' "$tmp/repos"
grep -q 'Review these repos privately' "$tmp/repos"
if grep -q 'No unpublished changes' "$tmp/repos"; then exit 1; fi

# Removing the ignored-only fixtures should leave a genuinely clean audit.
rm "$repo/ignored-secret" "$repo/ignored directory/file name" "$repo/ignored directory/"$'line\nbreak'
rmdir "$repo/ignored directory"
rm "$repo/normal directory/file.secret"
rmdir "$repo/normal directory"
"$ROOT/scripts/old-laptop-check-repos.sh" > "$tmp/repos"
grep -q 'No unpublished changes' "$tmp/repos"

# Confirm declining either APT installer never calls sudo, including --docker.
mkdir "$tmp/mock"
printf '#!/usr/bin/env bash\nexit 99\n' > "$tmp/mock/sudo"
chmod +x "$tmp/mock/sudo"
for step in --apt --docker; do
    PATH="$tmp/mock:$PATH" "$ROOT/install" "$step" <<< n >/dev/null
done

# Docker must have one package owner: its official APT manifest, not Homebrew.
if grep -Eq '^brew "docker(-compose)?"' "$ROOT/Brewfile"; then exit 1; fi
for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
    grep -Fxq "$package" "$ROOT/packages/docker-apt.txt"
done

printf 'PASS: links, backups, idempotency, existing Git config, arbitrary cwd, help, repo audit, declined sudo\n'
