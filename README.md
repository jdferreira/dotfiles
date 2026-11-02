# Ubuntu dotfiles migration

Small Bash installers, not a machine image. Run scripts as your normal user,
never `sudo ./install`. They resolve paths independently of the working
directory. Review manifests and configuration before running. No packages are
installed by tests.

## Script names

- `scripts/old-laptop-*.sh`: inspect or export from the laptop you are leaving.
- `scripts/new-laptop-*.sh`: install, restore or validate on the replacement laptop.
- `scripts/export-restore-gnome.sh` and `scripts/export-restore-vscode.sh`:
  run `export` on the old laptop and `restore` on the new one.
- `scripts/backup-restore-private-data.sh`: run `backup` on the old laptop,
  `verify` on either laptop, and `restore` on the new one.
- `scripts/lib.sh`: shared helpers, not a standalone command.

Keep using `./install` for new-laptop setup and `./install --check-repos` for
the old-laptop audit. To export GNOME and VS Code together on the old laptop,
run `./scripts/old-laptop-export-preferences.sh`.

## Old laptop

Run this checklist on the **laptop you are migrating from**, inside the dotfiles
checkout. Mark skipped/not-applicable items as done after reviewing them.

### 1. Choose a private backup destination

**This repository backs up your environment; it does not back up your projects,
files or database contents.** Preserve anything you cannot clone or reinstall.

- [x] Choose an encrypted external drive or a trusted encrypted backup tool. An
      existing reliable encrypted backup is sufficient.
  - Keep this backup outside the dotfiles checkout: it may contain secrets and
    company data.
  - Keep its password/recovery key accessible from outside the old laptop.

### 2. Find and preserve local project work (`~/Repos`)

- [x] Fetch trusted remotes in each project if you want up-to-date comparisons.
      The audit does not fetch or contact remotes itself.
- [x] Run the repository audit:
```bash
./install --check-repos
```
- [x] Review reported uncommitted changes, local-only commits, stashes and
      branches without upstreams. Push only work that is safe and intended to
      be published; preserve the rest in your encrypted backup.
- [x] Review the separate **Untracked** and **Ignored** file lists. Back up
      needed `.env` files, local configuration, datasets and other local-only
      data. Skip disposable dependencies, build outputs and caches.
- [x] Back up project working directories under `~/Repos`, including selected
      untracked/ignored files. Git push alone does not preserve those files.
- [x] Check projects outside `~/Repos`, symlinked project directories and bare
      repositories separately; the audit does not discover them automatically.

The report includes nested repositories, submodules and worktrees. File paths
are repository-relative and shell-escaped; contents, diffs and remote URLs are
not printed. **Keep the report private: filenames can be sensitive.** Ignored
folders are listed once with a trailing `/`, without listing their contents.
Individual ignored files outside those folders are still listed. A clean report
uses cached remote refs and is not proof that the remote or your backup is
complete.

### 3. Export and review software inventories

- [x] If Homebrew is installed, export its current inventory:
      ```bash
      brew bundle dump --file=/tmp/Brewfile --force
      ```
- [x] Review `/tmp/Brewfile` and merge only wanted Linux formulas into the
      committed `Brewfile`. Omit Git, which is already in the APT manifest.
- [x] Export manually installed APT packages as a reference:
      ```bash
      apt-mark showmanual > /tmp/apt-manual.txt
      ```
- [x] Review `/tmp/apt-manual.txt` against `packages/apt.txt`. Add only needed
      Ubuntu packages not already handled through brew; do not copy the whole
      list.

### 4. Select and export GNOME shortcuts

- [x] Open `preferences/gnome-keys.txt` and review which shortcuts are selected.
- [x] Discover other available shortcut keys, if needed:
      ```bash
      for i in \
          org.gnome.desktop.wm.keybindings \
          org.gnome.settings-daemon.plugins.media-keys \
          org.gnome.shell.keybindings \
          org.gnome.mutter.keybindings; do
          echo $i
          gsettings list-keys $i
          echo
      done
      ```
- [x] Add wanted schema/key pairs to `preferences/gnome-keys.txt`.
- [x] Export the selected shortcuts from your logged-in GNOME session:
      ```bash
      ./scripts/export-restore-gnome.sh export
      ```
- [x] Review the exported files in `preferences/gnome/`.
- [x] Record custom shortcuts that launch commands in your private migration
      notes; recreate them manually on the new laptop. Do not commit secrets
      embedded in commands.

### 5. Export VS Code preferences and extensions

- [x] Review `~/.config/Code/User/settings.json` and `keybindings.json`, if
      present, for secrets, private URLs and machine-specific paths.
- [x] Export reviewed settings, keybindings and installed extension IDs:
      ```bash
      ./scripts/export-restore-vscode.sh export
      ```
      Confirm copying settings only if they are safe to enter the checkout.
      Otherwise decline and prepare sanitized copies manually. The extension
      inventory is exported even when you decline settings copying.
- [x] Review `preferences/vscode/settings.json` and `keybindings.json`, if
      present. No custom keybindings means there is nothing to export for them.
- [x] Edit `preferences/vscode/extensions.txt` to keep only wanted extensions,
      including the extension providing your theme.

### 6. Enable account-based settings synchronization

- [x] Sign into IntelliJ's **Settings Sync / Backup and Sync** using your
      JetBrains account. Check that keymaps, settings and wanted plugins sync.
- [x] Sign into Firefox Sync and review the categories you want synchronized.
- [x] Sign into Chrome Sync and review the categories you want synchronized.

### 7. Verify the backup and save reviewed repository changes

- [x] Back up needed SSH keys and authentication material following the
      [authentication guidance below](#authentication-and-private-data).
- [x] Review the changed files in this repository with `git status` and
      `git diff`.
- [x] Stage only intended, sanitized settings with `git diff --cached`.
- [x] Commit and push the reviewed dotfiles changes so the new laptop can clone
  them.

## New laptop

Install a supported Ubuntu release, apply updates and log into GNOME. Use the
normal Portuguese **basic** keyboard layout. Install Git to clone if necessary;
review the small APT list before proceeding (Git is the one bootstrap dependency
retained in APT).

```bash
sudo apt update && sudo apt install git  # explicit system operation
mkdir -p ~/Repos
git clone https://github.com/jdferreira/dotfiles ~/Repos/dotfiles
cd ~/Repos/dotfiles
./install --dotfiles
./install --apt
./install --brew
./install --docker # Engine, CLI, Buildx and Compose via official Docker APT
./install --apps # guided GUI/Ringboard instructions
./install --firefox # official Mozilla APT, not Ubuntu's Snap wrapper
./install --preferences
./install --keyboard # optional, system patch, asks confirmation
./install --remove-snap-flatpak # optional, destructive, asks confirmation
./scripts/new-laptop-check-environment.sh
```

Every operation is independently rerunnable; combine flags if useful, e.g.
`./install --apt --docker`. Docker is a separate APT step, not part of `--brew`
or the base Ubuntu manifest. No unattended confirmation bypass. Decline prompts
to skip; EOF also declines. System changes always require confirmation. Brew's
upstream bootstrap may itself request sudo. Downloads require working TLS/network
access.

Dotfiles use symlinks; conflicts (including broken links) are renamed alongside
the original as `.backup.TIMESTAMP.PID`. Keep this checkout in place. Remove a
link and move its backup back to undo. VS Code edits through its links change
the checkout: inspect before committing. Existing `~/.gitconfig` is never
replaced. On an empty home the tracked Git config is offered explicitly: it
contains the original author's **personal identity**. Review it, or configure
Git privately yourself. Its only other settings are Vim as editor and verbose
commits. Existing Git aliases/includes/helpers must be restored from your
private backup.

## Applications

- CLI: review the committed `Brewfile`, merge wanted old-laptop formulas, then
  rerun `--brew`. Avoid installing the same tools through both brew and APT.
- VS Code: download the `.deb` for your architecture from
  https://code.visualstudio.com/Download. Review the file, then explicitly
  install with `sudo apt install /absolute/path/to/download.deb`. Rerun
  `--preferences`. Theme extensions are included in the reviewed extension list.
- JetBrains Toolbox: https://www.jetbrains.com/toolbox-app/; unpack the official
  Linux download and launch it as your user. Install IntelliJ IDEA through
  Toolbox, log in, enable Settings Sync. No bulk IDE directory copying.
- Chrome: https://www.google.com/chrome/; install the official `.deb` explicitly
  as above. Google's Linux Chrome download is amd64; on ARM use another browser.
- Firefox: `--firefox` uses Mozilla's distribution-independent `mozilla` APT
  suite, verifies its signing-key fingerprint and pins that origin. Existing
  repository files are backed up before replacement.  
  Verify `apt-cache policy firefox` and `readlink -f "$(command -v firefox)"`.
  If an old transitional Ubuntu package blocks installation, review policy and
  the current https://support.mozilla.org/kb/install-firefox-linux instructions,
  then remove that wrapper before retrying.
- Ringboard: Use **manual installation with prebuilt release binaries**.
  Download a matching architecture release, verify it using available upstream
  checksums/signatures, inspect its contents, and install the server,
  CLI/client, and the appropriate X11 or Wayland watcher into `~/.local/bin`
  (now on PATH). No Rust toolchain is needed for prebuilt releases. Install the
  upstream matching `ringboard-server.service` and watcher unit in
  `~/.config/systemd/user`; inspect ExecStart paths (point to your binaries)
  before `systemctl --user daemon-reload` and `systemctl --user enable --now
  ringboard-x11` **or** `ringboard-wayland`. Requires kernel 6+ and compatible
  compositor protocols; stock GNOME Wayland may require upstream's X11 fallback
  and may not capture native Wayland apps. Follow upstream's Wayland interface
  check; prefer a manual tested setup to a blind installer. Bind the chosen UI
  in GNOME Keyboard Settings. Do not migrate clipboard history; it can contain
  passwords. If no compatible prebuilt release exists, stop and review upstream
  build requirements rather than implicitly installing Rust.

### Docker

Docker Engine, its CLI, Buildx and Compose are installed **only through APT**, not
Homebrew. Review `packages/docker-apt.txt`, then run:

```bash
./install --apt # prerequisite tools, including curl and gnupg
./install --docker
# Log out and back in if you approved Docker-group membership, then:
docker info
docker compose version
```

`--docker` configures Docker's official Ubuntu repository with a
fingerprint-checked key and `Signed-By` (no `apt-key`). It uses the installed
Ubuntu codename and architecture, installs `docker-ce`, `docker-ce-cli`,
`containerd.io`, `docker-buildx-plugin` and `docker-compose-plugin`, and
enables/starts the daemon. Repository-file conflicts are backed up; identical
files are left unchanged. Installation and system changes require confirmation.
Docker-group membership is a **separate prompt**, because it grants
root-equivalent access. Existing group membership is preserved. Consider
Docker's documented rootless setup instead if that access or a system daemon is
unacceptable; decline this installer in that case. Never chmod the socket to 666
or expose an unauthenticated TCP socket.

Supported releases and manual installation instructions:
https://docs.docker.com/engine/install/ubuntu/. Unsupported releases fail rather
than borrowing another Ubuntu version's repository. Re-run `--docker`
independently as needed. No images, containers or volumes are exported/restored
by these scripts.

## Snap / Flatpak

`--remove-snap-flatpak` lists apps first and asks confirmation before purging
the frameworks and adding an APT pin blocking `snapd`. Back up data privately
first; remove listed apps deliberately, Snap bases last, and remove both
user/system Flatpak apps. The operation does not erase leftover home
directories, mounts or external Flatpak repositories. Inspect them manually.
Reboot after removal. No `autoremove` or recursive home deletion is automated.
The validator checks absence only once removal was requested and completed. To
undo, remove the pin intentionally and reinstall the frameworks. Ubuntu desktop
metapackages/release upgrades may conflict with the pin or restore Snap; review
upgrade plans and rerun validation.

## Preferences / compatibility

GNOME exports are restricted to `preferences/gnome-keys.txt`; no full-desktop
dump. Missing schemas/keys are skipped with a diagnostic. Restore uses
schema-validated GSettings writes through dconf; before-values go to
`~/.local/state/dotfiles/gnome`. Restore manually with `dconf write
/schema/path/key VALUE`, or `dconf reset PATH` when the before-file is empty.
Review shortcut conflicts across GNOME versions. Custom media-key command trees
are deliberately manual: commands may contain secrets; recreate reviewed ones in
Keyboard Settings. The allowlist covers the four relevant WM, media-keys, shell
and mutter schemas, not every shortcut. GNOME Terminal's existing legacy profile
is a separate opt-in restore with a subtree backup (undo using `dconf load
/org/gnome/terminal/ < BACKUP`). Run desktop operations inside the logged-in
user's GNOME session, not through sudo/SSH without a session bus.

Portuguese customization patches **only** TLDE in the system `basic` section to:
```xkb
key <TLDE> { [ backslash, bar, grave, notsign ] };
```
A complete user `pt` override risks shadowing distro variants, and GNOME Wayland
handling of user XKB search paths varies. Therefore this uses a confirmed
minimal system patch with backup, rejecting unexpected layouts. Log out/in;
reapply after `xkeyboard-config` upgrades. Variants other than basic may
override this key. Restore the adjacent backup to undo. No whole XKB file is
committed.

## Authentication and private data

Never commit secrets to this repository. This includes, for example:
- SSH/GPG private keys
- AWS config/credentials/SSO caches
- Git credentials
- GitHub tokens
- browser data (cookies, history, company URLs or secrets, ...)
- shell history

Even Git config, AWS config, GNOME commands and editor settings can
contain PII or secrets. 

Ignore rules are guardrails, **not proof of safety**. No automated
secret-scanning workflow is configured. At every stage, carefully review files
staged locally. Consider that old commits retain original files and that
deleting a file does not erase history. If a secret was ever committed,
revoke/rotate it and coordinate history cleanup.

Use `scripts/backup-restore-private-data.sh` to create, verify and restore
**separate encrypted backups** outside this repository, ideally on a USB drive.
Store the passphrase separately. This is an explicit opt-in operation, never
part of `./install`. See [commands and limitations below](#encrypted-private-data-backups).

Here are a few points for backing up and restoring sensitive data securely:

- **SSH (`ssh` target):** back up and restore `~/.ssh` using the script.
  Restored directories are mode 700 and all files 600, owned by the current
  user; public keys do not need to be made more permissive. Review config paths
  and known_hosts; verify host fingerprints independently.
- **GitHub (manual authentication):** restore SSH keys with the `ssh` target,
  or reauthenticate interactively using `gh auth login`. GitHub tokens and Git
  credential stores are not backed up by this script. Never commit token stores
  or print `gh auth token`.
- **AWS (`aws` target):** back up and restore `~/.aws/config` and
  `~/.aws/credentials`, if present. Include required helper files explicitly with
  `--aws-file`, repeating the same selections for backup, verify and restore.
  No SSO caches are transferred. Review hardcoded `credential_process` paths and
  install helper dependencies separately; the script never executes helpers.
  Authenticate manually with `aws sso login --profile NAME` for SSO, or your
  reviewed credential helper as appropriate. Prefer SSO to static credentials;
  rotate exposed keys. Config files and profile names may contain sensitive data.
- **Git signing (`git-signing` target for GPG):** back up and restore the
  supported conventional `~/.gnupg` files using the script. Keyboxd/custom GPG
  homes need a separate procedure, described below. SSH signing keys under
  `~/.ssh` use the `ssh` target; external keys and hardware tokens need their own
  recovery/enrollment. Git preferences are not included: review `user.signingkey`,
  `gpg.format`, allowed-signers paths and `commit.gpgsign` privately. The script
  does not change Git identity or signing preferences.
- **Bash history (`bash-history` target):** optionally back up and restore
  `~/.bash_history` with the script. Flush pending history and close other shells
  first; follow the restore instructions below to avoid overwriting restored
  history. Custom `HISTFILE` locations are not included. History often contains
  secrets: never stage it, display it in logs or include it in inventories.

Each restore requires confirmation and replaces, rather than merges, its target.
Existing data is preserved in an adjacent private `.backup.TIMESTAMP.PID` file or
folder. Protect those plaintext backups as carefully as the restored data.

### Encrypted private-data backups

Use `scripts/backup-restore-private-data.sh` as your normal user, never with sudo. It requires
GnuPG and GNU tar (Ubuntu provides them through the bootstrap packages/base system).
Use a separate archive for each target; do not pass passwords on the command line.
GnuPG prompts through pinentry. Use a strong passphrase and keep it separate from
the USB drive; key passphrases alone are not a substitute for archive encryption.

1. Mount your USB drive using Files. Replace `/media/$USER/MY_USB` below with its
   **actual mounted path**. The script requires an existing destination directory
   but cannot prove it is a USB drive. It refuses paths inside this checkout or the
   source directory and refuses to overwrite an existing archive.
2. Close programs modifying these files. For history, run `history -a` in each open
   Bash shell to flush pending commands, then close other shells. For GPG, close
   signing applications and stop its agent with `gpgconf --kill gpg-agent` before
   backup/restore. Do not sign concurrently with migration.
3. On the old laptop, run only the targets you need:
   ```bash
   ./scripts/backup-restore-private-data.sh backup ssh /media/$USER/MY_USB/ssh.tar.gpg
   ./scripts/backup-restore-private-data.sh backup aws /media/$USER/MY_USB/aws.tar.gpg
   ./scripts/backup-restore-private-data.sh backup git-signing /media/$USER/MY_USB/signing.tar.gpg
   ./scripts/backup-restore-private-data.sh backup bash-history /media/$USER/MY_USB/history.tar.gpg
   ```
4. Verify each archive before relying on it, for example:
   ```bash
   ./scripts/backup-restore-private-data.sh verify ssh /media/$USER/MY_USB/ssh.tar.gpg
   ```
   Repeat with the corresponding target/path for the other archives. Verification
   decrypts, validates and extracts privately without replacing any home files.
   Safely eject the USB afterwards. Keep the old laptop until restoration is tested.
5. On the new laptop, mount the USB and restore the targets you backed up:
   ```bash
   ./scripts/backup-restore-private-data.sh restore ssh /media/$USER/MY_USB/ssh.tar.gpg
   ./scripts/backup-restore-private-data.sh restore aws /media/$USER/MY_USB/aws.tar.gpg
   ./scripts/backup-restore-private-data.sh restore git-signing /media/$USER/MY_USB/signing.tar.gpg
   ./scripts/backup-restore-private-data.sh restore bash-history /media/$USER/MY_USB/history.tar.gpg
   ```
   Each restore asks confirmation after decryption/validation. It **replaces rather
   than merges** the target and preserves any existing target as an adjacent
   `.backup.TIMESTAMP.PID` file/directory. These backups are private plaintext:
   protect them and remove them deliberately when no longer needed. Directories
   are restored as 700, all files as 600, owned by the current user.

Target contents and limitations:

- `ssh`: `~/.ssh`, including config and known_hosts. Rejects symlinks, sockets and
  other special files rather than following or silently skipping them. Handle
  agent sockets and externally stored keys separately. Review paths and host keys.
- `aws`: `~/.aws/config` and `~/.aws/credentials`, if present, plus explicitly
  selected helper files (see below). **No SSO caches or directories** are copied.
  All these files may contain secrets/PII. After restoring, authenticate yourself
  using SSO or your reviewed credential helper as appropriate. Sessions are not
  transferred; logging in on the new laptop does not revoke sessions on the old one.
- `git-signing`: conventional `~/.gnupg` key files, private-key directory,
  revocation certificates, trust database and selected configuration. Not Git
  identity/signing preferences. SSH signing keys belong in the `ssh` backup;
  external/hardware keys require their own recovery/enrollment procedure.
  Keyboxd (`~/.gnupg/public-keys.d`) is detected and refused: use GnuPG's supported
  export/import through your encrypted backup tool instead. Custom `GNUPGHOME`
  locations are not discovered. Review restored GPG configuration before use.
- `bash-history`: only `~/.bash_history`, not custom `HISTFILE` locations or in-memory
  history. After restore, close the migration shell without overwriting restored
  history (`unset HISTFILE; exit`) and start a new shell.

#### AWS credential helpers and other extra files

If `credential_process` references a helper such as `~/.aws/credentials-process.py`,
include it explicitly. Repeat `--aws-file NAME` for each needed regular file directly
inside `~/.aws`; paths, directories and symlinks are not supported. Review imported
modules and other dependencies manually: the script does not discover them, parse
AWS config or execute credential helpers.

```bash
scripts/backup-restore-private-data.sh \
  backup aws \
  "/media/$USER/MY_USB/aws.tar.gpg" \
  --aws-file credentials-process.py
scripts/backup-restore-private-data.sh \
  verify aws \
  "/media/$USER/MY_USB/aws.tar.gpg" \
  --aws-file credentials-process.py
scripts/backup-restore-private-data.sh \
  restore aws \
  "/media/$USER/MY_USB/aws.tar.gpg" \
  --aws-file credentials-process.py
```

Repeat the same file selections for all three operations. Restore refuses archives
containing unselected files. Keep the selection names in private migration notes,
not in a committed personal AWS config. After restoring:

- Review `credential_process` paths for a changed username/home directory; prefer
  `"$HOME/.aws/credentials-process.py"` inside the shell command where appropriate.
  The script preserves configuration verbatim rather than rewriting it.
- Install dependencies such as `uv` separately. Restored helper files are mode 600;
  an interpreter-invoked helper needs no executable bit. Set it deliberately if
  your command invokes the helper directly.
- Run authentication manually when ready; it may request MFA or an interactive TTY.
  No login or credential-process execution occurs during backup, verify or restore.

Encryption streams directly to the destination; no plaintext tar is written there.
Restore/verify use a private directory on `/dev/shm` tmpfs and clean it on normal
exit/failure. Staging may use swap: use encrypted swap/full-disk encryption too.
An interrupted restore may leave a private staging directory in HOME; inspect
`.private-restore.*` after crashes. Plaintext restored files are necessarily on
local storage. Never commit archives, passwords, private data or backup listings.
The script does not install packages, change Git identity, authenticate to services,
or validate that restored credentials are still accepted.

## Validation / development

`./scripts/new-laptop-check-environment.sh` is read-only, returns nonzero for
missing checks, and never launches login flows. It suppresses Git identity
values and Docker info; AWS profile **names** are printed as requested, so keep
its output private. Verify Toolbox/IntelliJ, keyboard mapping, themes, browser
sync and Ringboard capture in the GUI; binary detection alone cannot prove
functionality. No AWS network auth test.

```bash
bash tests/run.sh
bash tests/backup-restore-private-data.sh  # synthetic fixtures; real encryption, no live secrets
shellcheck -x -P scripts install scripts/*.sh tests/*.sh .bashrc
```
Tests use a temporary HOME and local repositories; they cover symlink conflicts,
backups, reruns, existing Git preferences, cwd independence, CLI help,
repository reporting and declined system changes. They never install/remove
software or change live desktop/system settings. Package/repository
compatibility, actual GUI restores, SSO and system changes still require manual
checks on the target Ubuntu release.
