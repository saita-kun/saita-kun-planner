#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${PLANNER_PYTHON:-python3}" - "$ROOT" <<'PY'
import hashlib
import json
import os
import pathlib
import shutil
import shlex
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
    for name in ("tools/check-setup.sh", "tools/lib/check_setup.py", "tools/lib/python-resolver.sh"):
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
            if state_path.is_file():
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
        return result, output

    result, output = run("missing file", None, "input/setup-state.json", missing=True)
    expect("first use guidance", result.returncode == 1 and "初回" in output
           and "/setup" in output and "Errno" not in output, output)
    result, output = run("malformed JSON", "{", "input/setup-state.json", raw=True)
    expect("malformed JSON guidance", result.returncode == 1 and "FAIL:" in output
           and "JSON の形式が不正です" in output and "Errno" not in output, output)
    state_path.unlink()
    state_path.mkdir()
    result, output = run("state is directory", None, "ファイルを開けません", missing=True)
    expect("directory guidance", result.returncode == 1 and "Errno" not in output
           and "初回" not in output and "/setup" in output, output)
    state_path.rmdir()
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
        result, output = run("missing document", valid, key)
        expect("missing document guidance", result.returncode == 1
               and "{}: {} がありません".format(key, name) in output
               and "Errno" not in output, output)
        path.mkdir()
        result, output = run("document is directory", valid, key)
        expect("unreadable document guidance", result.returncode == 1
               and "{}: {} を読み取れません（ファイルを開けません）".format(key, name) in output
               and "Errno" not in output, output)
        path.rmdir()
        path.write_bytes(original)
    env = dict(os.environ, PLANNER_PYTHON=sys.executable)
    run("explicit interpreter", valid, env=env)
    env["PLANNER_PYTHON"] = "nopy"
    result, output = run("invalid interpreter", valid, "PLANNER_PYTHON", env=env)
    expect("invalid environment single FAIL", result.returncode == 1
           and sum(line.startswith("FAIL") for line in output.splitlines()) == 1
           and "Python（nopy）" in output and "指定を直すか外してください。" in output, output)
    saved = root / "input/.planner-python"
    interpreter = root / "saved python"
    interpreter.write_text(
        '#!/bin/bash\nif [ "$1" != "-c" ]; then echo saved-python-used >&2; fi\n'
        + 'exec ' + shlex.quote(sys.executable) + ' "$@"\n', encoding="utf-8")
    interpreter.chmod(0o755)
    saved.write_text(str(interpreter) + "\n", encoding="utf-8")
    saved_env = dict(os.environ)
    saved_env.pop("PLANNER_PYTHON", None)
    result, output = run("saved interpreter", valid, env=saved_env)
    expect("saved interpreter executed", "saved-python-used" in result.stderr, output)
    saved.write_text(str(root / "no-python") + "\n", encoding="utf-8")
    result, output = run("saved invalid interpreter does not fall back", valid, "保存設定", env=saved_env)
    expect("invalid saved single FAIL", result.returncode == 1
           and sum(line.startswith("FAIL") for line in output.splitlines()) == 1
           and "/setup で再保存または解除してください。" in output, output)
    run("explicit interpreter overrides saved", valid,
        env=dict(saved_env, PLANNER_PYTHON=sys.executable))
    saved.unlink()
    bin_dir = root / "bin"
    bin_dir.mkdir()
    for command in ("bash", "dirname"):
        (bin_dir / command).symlink_to(shutil.which(command))
    result, output = run("automatic detection failure", valid, "自動検出", env=dict(saved_env, PATH=str(bin_dir)))
    expect("missing Python guidance: automatic detection single FAIL", result.returncode == 1
           and sum(line.startswith("FAIL") for line in output.splitlines()) == 1
           and "/setup の環境確認の手順で導入してください。" in output, output)
    run("unexpected arguments", valid, "使い方", args=("--write",))

print("PASS: {} FAIL: {}".format(passed, failed))
sys.exit(1 if failed else 0)
PY
