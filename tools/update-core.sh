#!/bin/bash
set -u

# Usage:
#   bash tools/update-core.sh [--dry-run] <upstream_checkout>
#   bash tools/update-core.sh --apply [--force-file <path>] <upstream_checkout>
#
# Default mode is --dry-run. --apply updates only files listed in the upstream
# core-manifest.json, while preserving input/, knowledge/, and my-* commands.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$SCRIPT_DIR/lib/update_core.py" --repo-root "$ROOT" "$@"
