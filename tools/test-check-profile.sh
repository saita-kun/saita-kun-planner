#!/bin/bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${PLANNER_PYTHON:-python3}" - "$ROOT" <<'PY'
import json
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
valid = {"entity_type": "法人", "industry_class": "製造業その他", "employees": 6}
cases = [
    ("valid", valid, 0, "OK: profile checks passed"),
    ("required", {"entity_type": None, "employees": 6}, 1, "FAIL: $.industry_class:"),
    ("enum", dict(valid, industry_class="invalid"), 1, "FAIL: $.industry_class:"),
    ("type", dict(valid, employees="6"), 1, "FAIL: $.employees:"),
    ("boolean is not integer", dict(valid, employees=True), 1, "FAIL: $.employees:"),
    ("null", dict.fromkeys(valid), 0, "OK: profile checks passed"),
    ("extension", dict(valid, custom_fact=True), 0, "INFO: schema に無いキー: custom_fact"),
    ("array item", dict(valid, plans=[1]), 1, "FAIL: $.plans[0]:"),
]
failed = 0
with tempfile.TemporaryDirectory(prefix="planner-profile-") as tmp:
    path = pathlib.Path(tmp) / "profile.json"
    for name, value, code, message in cases:
        path.write_text(json.dumps(value), encoding="utf-8")
        result = subprocess.run(["bash", str(root / "tools/check-profile.sh"), str(path)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                universal_newlines=True)
        if result.returncode != code or message not in result.stdout or result.stderr:
            failed += 1
            print("FAIL:", name, result.returncode, result.stdout, result.stderr)
    read_cases = [
        ("missing", None, f"FAIL: {path} がありません（/intake で作成します）"),
        ("invalid JSON", "{", f"FAIL: {path}: JSON の形式が不正です"),
        ("array root", "[]", f"FAIL: {path}: JSON object ではありません"),
    ]
    for name, content, message in read_cases:
        if content is None:
            path.unlink()
        else:
            path.write_text(content, encoding="utf-8")
        result = subprocess.run(["bash", str(root / "tools/check-profile.sh"), str(path)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                universal_newlines=True)
        output = result.stdout + result.stderr
        if (result.returncode != 1 or result.stdout.strip() != message or result.stderr
                or "Errno" in output or "Traceback" in output):
            failed += 1
            print("FAIL:", name, result.returncode, output)
print(f"{len(cases) + len(read_cases) - failed} pass / {failed} fail")
sys.exit(bool(failed))
PY
