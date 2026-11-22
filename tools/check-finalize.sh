#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/lib/python-resolver.sh" || exit 2
planner_resolve_python "$SCRIPT_DIR/../input/.planner-python" || exit 2

"${PLANNER_PY[@]}" "$SCRIPT_DIR/lib/check_finalize.py" "$@"
