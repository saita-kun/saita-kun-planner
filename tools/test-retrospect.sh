#!/bin/bash
# Exercise the record checker extracted from the shipped command.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import copy
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
command = (root / ".claude/commands/retrospect.md").read_text(encoding="utf-8")
blocks = re.findall(
    r"^python3 - knowledge/records/[^\n]+ <<'PY'\n(.*?)^PY$",
    command, re.MULTILINE | re.DOTALL,
)
if len(blocks) != 1:
    raise SystemExit("FAIL: expected exactly one embedded record checker")
checker = blocks[0]
base = {"record_id": "record-1", "subsidy_id": "subsidy-1", "spec_version": 1, "result": "pending"}
lesson = {"lesson_id": "lesson-1", "phase": "fit", "text": "確認資料を早めに整理する。"}
success = "OK: record matches application-record schema\n"
passed = 0
failed = 0


def check_record(label, record, paths=()):
    global passed, failed
    record_path.write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
    result = subprocess.run(
        [sys.executable, "-", str(record_path)], input=checker,
        cwd=work, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True,
    )
    if paths:
        lines = result.stdout.splitlines()
        valid = result.returncode == 1 and not result.stderr and bool(lines) and all(
            line.startswith("FAIL: ") for line in lines
        ) and all(any(line.startswith(f"FAIL: {path}:") for line in lines) for path in paths)
    else:
        valid = result.returncode == 0 and result.stdout == success and not result.stderr
    if valid:
        passed += 1
    else:
        failed += 1
        print(f"FAIL: {label}: status={result.returncode} stdout={result.stdout!r} stderr={result.stderr!r}")


def record_types_rejected():
    for value in ([], None, "fake", 1, 1.5, True, False):
        check_record(f"record_types_rejected root {value!r}", value, ("$",))
    invalid_fields = {
        "spec_version": ("1", True, False, None, 1.5, [], {}),
        "record_id": (1, None), "subsidy_id": (True, None),
        "result": (1, None), "round": (1, False, [], {}),
        "submitted_at": (1, False, [], {}), "score": ("1", True, False, [], {}),
        "feedback_text": (1, False, [], {}), "created_at": (1, False, [], {}),
    }
    for field, values in invalid_fields.items():
        for value in values:
            check_record(f"record_types_rejected {field} {value!r}",
                         dict(base, **{field: value}), (f"$.{field}",))
    for field in ("chosen_addons", "next_actions", "lessons"):
        for value in (None, "fake", 1, False, {}):
            check_record(f"record_types_rejected {field} container {value!r}",
                         dict(base, **{field: value}), (f"$.{field}",))
        values = (None, 1, False, [], "fake") if field == "lessons" else (None, 1, False, [], {})
        first = lesson if field == "lessons" else "valid"
        for value in values:
            check_record(f"record_types_rejected {field} item {value!r}",
                         dict(base, **{field: [first, value]}), (f"$.{field}[1]",))


def record_patterns_and_nested_rules():
    for field in ("record_id", "subsidy_id"):
        for value in ("", "Upper", "has_underscore", "has space", "日本語", "record-1\n"):
            check_record(f"record_patterns_and_nested_rules {field} {value!r}",
                         dict(base, **{field: value}), (f"$.{field}",))
    for value in ("", "2026/07/01", "2026-7-01", "26-07-01", "2026-07-01T00:00:00Z", "2026-07-01\n"):
        check_record(f"record_patterns_and_nested_rules submitted_at {value!r}",
                     dict(base, submitted_at=value), ("$.submitted_at",))
    for field in base:
        record = dict(base)
        del record[field]
        check_record(f"record_patterns_and_nested_rules required {field}", record, (f"$.{field}",))
    check_record("record_patterns_and_nested_rules root unknown key",
                 dict(base, extra="fake"), ("$.extra",))
    check_record("record_patterns_and_nested_rules result enum",
                 dict(base, result="unknown"), ("$.result",))
    for field in lesson:
        item = dict(lesson)
        del item[field]
        check_record(f"record_patterns_and_nested_rules lesson required {field}",
                     dict(base, lessons=[item]), (f"$.lessons[0].{field}",))
    invalid_fields = {
        "lesson_id": (None, 1, "", "Lesson_1", "has space", "lesson-1\n"),
        "phase": (None, 1, "unknown"), "text": (None, 1, False, [], {}),
        "applies_to": (1, False, [], {}), "extra": ("fake",),
    }
    for field, values in invalid_fields.items():
        for value in values:
            check_record(f"record_patterns_and_nested_rules lesson {field} {value!r}",
                         dict(base, lessons=[dict(lesson, **{field: value})]), (f"$.lessons[0].{field}",))
    check_record("record_patterns_and_nested_rules multiple paths",
                 dict(base, record_id="Invalid", spec_version=True, lessons=[dict(lesson, phase="unknown"), None]),
                 ("$.record_id", "$.spec_version", "$.lessons[0].phase", "$.lessons[1]"))


def record_nullable_values_accepted():
    check_record("record_nullable_values_accepted minimal", base)
    sample = json.loads((root / "examples/worked-example/record.sample.json").read_text(encoding="utf-8"))
    check_record("record_nullable_values_accepted worked example", sample)
    example = re.findall(r"^```json\n(.*?)^```$", command, re.MULTILINE | re.DOTALL)
    if len(example) != 1:
        raise SystemExit("FAIL: expected exactly one command JSON example")
    check_record("record_nullable_values_accepted command example", json.loads(example[0]))
    nullable = copy.deepcopy(sample)
    for field in ("round", "submitted_at", "score", "feedback_text", "created_at"):
        nullable[field] = None
    for item in nullable["lessons"]:
        item["applies_to"] = None
    check_record("record_nullable_values_accepted all nullable fields", nullable)
    check_record("record_nullable_values_accepted empty arrays",
                 dict(base, chosen_addons=[], lessons=[], next_actions=[]))
    for value in (0, -1, 1.0):
        check_record(f"record_nullable_values_accepted integer {value!r}", dict(base, spec_version=value))
    for value in (0, -1, 1.5):
        check_record(f"record_nullable_values_accepted number {value!r}", dict(base, score=value))
    for result in ("adopted", "rejected", "not_submitted", "pending"):
        check_record(f"record_nullable_values_accepted result {result}", dict(base, result=result))
    for phase in ("intake", "fit", "draft", "verify", "finalize"):
        check_record(f"record_nullable_values_accepted phase {phase}",
                     dict(base, lessons=[dict(lesson, phase=phase)]))
    # Keep the schema's pattern and string contracts without adding calendar rules.
    check_record("record_nullable_values_accepted schema string boundaries",
                 dict(base, record_id="-", subsidy_id="0", round="", submitted_at="2026-02-31",
                      created_at="free text", feedback_text="",
                      lessons=[dict(lesson, lesson_id="-", text="", applies_to="")]))


with tempfile.TemporaryDirectory(prefix="planner retrospect ") as directory:
    work = pathlib.Path(directory)
    (work / "schemas").mkdir()
    shutil.copyfile(root / "schemas/application-record.schema.json", work / "schemas/application-record.schema.json")
    record_path = work / "fake record.json"
    record_types_rejected()
    record_patterns_and_nested_rules()
    record_nullable_values_accepted()

print(f"=== test-retrospect: {passed} pass / {failed} fail ===")
sys.exit(1 if failed else 0)
PY
