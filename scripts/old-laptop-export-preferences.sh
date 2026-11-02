#!/usr/bin/env bash
# Old-laptop export entry point; deliberately no full desktop/profile exports.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)

"$ROOT/scripts/export-restore-gnome.sh" export
"$ROOT/scripts/export-restore-vscode.sh" export
