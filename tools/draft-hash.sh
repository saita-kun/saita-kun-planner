#!/bin/bash
set -u

if [ "$#" -ne 2 ]; then
  echo "usage: bash tools/draft-hash.sh <spec.json> <drafts_dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="$1"
DRAFTS_DIR="$2"

if [ ! -f "$SPEC_PATH" ]; then
  echo "FAIL: spec not found: $SPEC_PATH" >&2
  exit 1
fi

# Duplicated in each wrapper so every wrapper stays self-contained.
if [ -n "${PLANNER_PYTHON:-}" ]; then
  if "$PLANNER_PYTHON" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
    PLANNER_PY=("$PLANNER_PYTHON")
  else
    echo "FAIL: Python 3 not found (set PLANNER_PYTHON)" >&2
    exit 1
  fi
elif python3 -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
  PLANNER_PY=(python3)
elif python -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
  PLANNER_PY=(python)
elif py -3 -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
  PLANNER_PY=(py -3)
else
  echo "FAIL: Python 3 not found (set PLANNER_PYTHON)" >&2
  exit 1
fi

PYTHONPATH="$SCRIPT_DIR/lib" "${PLANNER_PY[@]}" - "$DRAFTS_DIR" <<'PY'
import pathlib
import sys

import check_drafts

digest, errors = check_drafts.draft_bodies_sha256(pathlib.Path(sys.argv[1]))
if errors:
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    raise SystemExit(1)
print(digest)
PY
