#!/usr/bin/env bash
# Docker Engine, CLI and plugins all come from Docker's official Ubuntu APT repo.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "$0")")/lib.sh"

mapfile -t packages < <(grep -Ev '^\s*(#|$)' "$ROOT/packages/docker-apt.txt")
printf 'Docker APT packages: %s\n' "${packages[*]}"
if ! confirm 'Configure Docker official APT repository, install these packages and start the system daemon?'; then
    exit 0
fi

# Use the actual Ubuntu base codename, not a guessed release or derivative name.
# shellcheck source=/dev/null
source /etc/os-release
[[ ${ID:-} == ubuntu && -n ${UBUNTU_CODENAME:-${VERSION_CODENAME:-}} ]] || {
    echo 'This installer requires Ubuntu. See https://docs.docker.com/engine/install/ubuntu/.' >&2
    exit 1
}
codename=${UBUNTU_CODENAME:-$VERSION_CODENAME}
architecture=$(dpkg --print-architecture)

for command in curl gpg; do
    command -v "$command" >/dev/null || { echo 'Run ./install --apt first (curl and gnupg required).' >&2; exit 1; }
done

# Do not automatically remove another container runtime or distribution packages.
# Conflicting repositories need review too; never create duplicate Docker sources.
for package in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q '^install ok installed$'; then
        echo "Conflicting package: $package. Review/remove it manually before retrying --docker." >&2
        exit 1
    fi
done
if [[ -e /etc/apt/sources.list.d/docker.list ]]; then
    echo 'Legacy docker.list found. Review/consolidate it before retrying; nothing has been replaced.' >&2
    exit 1
fi

# Stage and verify the repository key before any /etc changes. Fail closed if
# Docker rotates its key; verify new fingerprints against official documentation.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$tmp/docker.asc"
fingerprint=$(gpg --show-keys --with-colons "$tmp/docker.asc" | awk -F: '$1=="fpr" {print $10; exit}')
[[ $fingerprint == 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 ]] || {
    echo 'Docker key changed; verify the official signing key before proceeding.' >&2
    exit 1
}

repository_source="Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $codename
Components: stable
Architectures: $architecture
Signed-By: /etc/apt/keyrings/docker.asc"
printf '%s\n' "$repository_source" > "$tmp/docker.sources"

# Idempotent repository files: leave identical files alone, preserve conflicts.
sudo install -d -m 755 /etc/apt/keyrings
for name in docker.asc docker.sources; do
    case $name in
        docker.asc) target=/etc/apt/keyrings/docker.asc ;;
        docker.sources) target=/etc/apt/sources.list.d/docker.sources ;;
    esac

    if ! sudo cmp -s "$tmp/$name" "$target"; then
        if sudo test -e "$target"; then
            sudo cp -a "$target" "$target.backup.$(date +%s).$$"
        fi
        sudo install -m 644 "$tmp/$name" "$target"
    fi
done

# APT remains interactive so package changes can be reviewed. Unsupported Ubuntu
# suites fail visibly rather than falling back to another release's packages.
sudo apt-get update
sudo apt-get install -- "${packages[@]}"
sudo systemctl enable --now docker

# Docker-group membership is root-equivalent; keep it a separate explicit choice.
user=$(id -un)
if id -nG "$user" | tr ' ' '\n' | grep -Fxq docker; then
    echo 'Current user already belongs to the docker group.'
elif confirm 'Grant this user root-equivalent access through the docker group?'; then
    if ! getent group docker >/dev/null; then sudo groupadd docker; fi
    sudo usermod -aG docker "$user"
    echo 'Log out and back in before using Docker without sudo.'
else
    echo 'Group access unchanged. Consider Docker rootless mode or use sudo deliberately.'
fi

echo 'Run docker info and docker compose version. No images, containers or volumes were migrated.'
