#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/lib/python-resolver.sh" || exit 1
planner_resolve_python "$SCRIPT_DIR/../input/.planner-python" || exit 1

"${PLANNER_PY[@]}" "$SCRIPT_DIR/lib/journey_map.py" "$@"
