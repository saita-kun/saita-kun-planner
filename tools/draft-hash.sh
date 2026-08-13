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

PYTHONPATH="$SCRIPT_DIR/lib" python3 - "$DRAFTS_DIR" <<'PY'
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
