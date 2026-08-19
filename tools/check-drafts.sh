#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

"${PLANNER_PY[@]}" "$SCRIPT_DIR/lib/check_drafts.py" "$@"
