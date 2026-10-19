#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${PLANNER_PYTHON:-python3}" - "$ROOT" <<'PY'
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1])
passed = 0
failed = 0


def expect(label, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
    else:
        failed += 1
        print("FAIL: {} {}".format(label, detail))


def snapshot(root):
    return {str(path.relative_to(root)): path.read_bytes() if path.is_file() else None
            for path in root.rglob("*")}


with tempfile.TemporaryDirectory(prefix="planner setup fixture ") as directory:
    root = pathlib.Path(directory)
    (root / "input").mkdir()
    (root / "docs").mkdir()
    (root / "tools/lib").mkdir(parents=True)
    for name in ("tools/check-setup.sh", "tools/lib/check_setup.py"):
        shutil.copyfile(str(source / name), str(root / name))
    (root / "TERMS.md").write_text("架空の利用規約\n", encoding="utf-8")
    (root / "docs/data-policy.md").write_text("架空のデータポリシー\n", encoding="utf-8")
    state_path = root / "input/setup-state.json"
    valid = {
        "setup_state_version": 1,
        "setup_completed_at": "2026-09-18T12:34:56+09:00",
        "terms_sha256": hashlib.sha256((root / "TERMS.md").read_bytes()).hexdigest(),
        "data_policy_sha256": hashlib.sha256((root / "docs/data-policy.md").read_bytes()).hexdigest(),
        "result_report_choice": "保留",
    }

    def run(label, value, diagnostic=None, raw=False, missing=False, env=None, args=()):
        if missing:
            if state_path.exists():
                state_path.unlink()
        else:
            state_path.write_text(value if raw else json.dumps(value), encoding="utf-8")
        before = snapshot(root)
        result = subprocess.run(
            ["bash", "tools/check-setup.sh"] + list(args), cwd=str(root), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        output = result.stdout + result.stderr
        if diagnostic is None:
            expect(label, result.returncode == 0 and result.stdout.strip() == "OK: setup-state", output)
        else:
            expect(label, result.returncode != 0 and diagnostic in output
                   and "OK: setup-state" not in output, output)
        expect(label + " read_only", before == snapshot(root))

    run("missing file", None, "input/setup-state.json", missing=True)
    run("malformed JSON", "{", "input/setup-state.json", raw=True)
    for value in ([], None, True, 1, "record"):
        run("non object", value, "JSON object")
    for key in valid:
        value = dict(valid)
        del value[key]
        run("missing " + key, value, key)
    for key, values in (
        ("setup_state_version", [0, 2, True, False, 1.0, "1", None, [], {}]),
        ("setup_completed_at", [None, 1, [], {}, "", "2026-09-18", "invalid",
                                "2026-02-30T12:00:00", "2025-02-29T12:00:00",
                                "2026-09-18T24:00:00", "2026-09-18T12:60:00",
                                "2026-09-18T12:00:60", "2026-09-18T12:00:00+24:00",
                                "2026-09-18T12:00:00+09:60", "2026-09-18X12:00:00"]),
        ("result_report_choice", ["unknown", "", None, True, [], {}]),
        ("terms_sha256", [None, 123, [], {}, "", "a" * 63, "a" * 65, "g" * 64, "0" * 64]),
        ("data_policy_sha256", [None, 123, [], {}, "", "a" * 63, "a" * 65, "g" * 64, "0" * 64]),
    ):
        for value in values:
            run("invalid " + key, dict(valid, **{key: value}), key)
    for choice in ("提出する", "提出しない", "保留"):
        for timestamp in ("2026-09-18T12:34:56", "2026-09-18T12:34:56Z",
                          "2026-09-18T12:34:56+09:00", "2026-09-18T12:34:56-03:30",
                          "2024-02-29T12:34:56.123456Z", "2026-09-18 12:34:56",
                          "2026-09-18T12:34", "2026-09-18T12:34:56+0900"):
            run("valid choice and datetime", dict(valid, result_report_choice=choice,
                                                   setup_completed_at=timestamp))
    run("uppercase hashes", dict(valid, terms_sha256=valid["terms_sha256"].upper(),
                                 data_policy_sha256=valid["data_policy_sha256"].upper()))
    run("extra field", dict(valid, extra="preserved"))
    for key, name in (("terms_sha256", "TERMS.md"), ("data_policy_sha256", "docs/data-policy.md")):
        path = root / name
        original = path.read_bytes()
        path.write_bytes(original + b"changed")
        run("changed document", valid, key)
        path.unlink()
        run("missing document", valid, key)
        path.mkdir()
        run("document is directory", valid, key)
        path.rmdir()
        path.write_bytes(original)
    env = dict(os.environ, PLANNER_PYTHON=sys.executable)
    run("explicit interpreter", valid, env=env)
    env["PLANNER_PYTHON"] = str(root / "no-python")
    run("invalid interpreter", valid, "PLANNER_PYTHON", env=env)
    run("unexpected arguments", valid, "使い方", args=("--write",))

print("PASS: {} FAIL: {}".format(passed, failed))
sys.exit(1 if failed else 0)
PY
