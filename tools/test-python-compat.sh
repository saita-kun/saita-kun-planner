#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PLANNER_PYTHON="${PLANNER_PYTHON:-python3}"
export PYTHONDONTWRITEBYTECODE=1

"$PLANNER_PYTHON" - <<'PY'
import importlib
import pathlib
import subprocess
import sys

print("Python %s" % sys.version.split()[0], flush=True)
sys.path.insert(0, str(pathlib.Path("tools/lib").resolve()))
for module in ("check_spec", "journey_map", "check_trust_freshness"):
    importlib.import_module(module)
print("PASS: python_compat_imports", flush=True)

result = subprocess.run(
    ["bash", "tools/check-spec.sh", "--list-bundled"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    universal_newlines=True,
)
if result.returncode != 0:
    raise SystemExit(
        "FAIL: python_compat_bundled_listing: %s%s" % (result.stdout, result.stderr)
    )
spec_paths = result.stdout.splitlines()
if not spec_paths:
    raise SystemExit("FAIL: python_compat_bundled_listing: no bundled specs")
for spec_path in spec_paths:
    if not pathlib.Path(spec_path).is_file():
        raise SystemExit("FAIL: python_compat_bundled_listing: missing file: %s" % spec_path)
print("PASS: python_compat_bundled_listing")
PY
