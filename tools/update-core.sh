#!/bin/bash
set -u

# Usage:
#   bash tools/update-core.sh [--dry-run] <upstream_checkout>
#   bash tools/update-core.sh --apply [--force-file <path>] <upstream_checkout>
#   bash tools/update-core.sh --adopt-ancestor <installed-version-dir>
#   bash <upstream>/tools/update-core.sh --repo-root <dir> --adopt-ancestor <installed-version-dir>
#
# Default mode is --dry-run. --apply updates only files listed in the upstream
# core-manifest.json, while preserving input/, knowledge/, and my-* commands.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HAS_REPO_ROOT=0
for arg in "$@"; do
  case "$arg" in
    --repo-root|--repo-root=*)
      HAS_REPO_ROOT=1
      break
      ;;
  esac
done

if [ "$HAS_REPO_ROOT" -eq 1 ]; then
  python3 "$SCRIPT_DIR/lib/update_core.py" "$@"
else
  python3 "$SCRIPT_DIR/lib/update_core.py" --repo-root "$ROOT" "$@"
fi
