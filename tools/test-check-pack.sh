#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
GREEN="tools/fixtures/packs/green"
TMP_ROOT="${TMPDIR:-/tmp}/saita-check-pack-$$"

trap 'rm -rf "$TMP_ROOT"' EXIT

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

copy_case() {
  local name="$1"
  mkdir -p "$TMP_ROOT/$name"
  cp -R "$GREEN"/. "$TMP_ROOT/$name"/
  python3 - "$TMP_ROOT/$name" <<'PY'
import hashlib
import json
import pathlib
import sys

pack_dir = pathlib.Path(sys.argv[1])
confirmation_path = pack_dir / "pack-fixture.confirmation.json"
confirmation = json.loads(confirmation_path.read_text(encoding="utf-8"))
confirmation["spec_path"] = (pack_dir / "pack-fixture.json").as_posix()
confirmation_path.write_text(json.dumps(confirmation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

pack_path = pack_dir / "pack.json"
pack = json.loads(pack_path.read_text(encoding="utf-8"))
pack["confirmation"]["sha256"] = hashlib.sha256(confirmation_path.read_bytes()).hexdigest()
pack_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

update_note_sha() {
  local pack_dir="$1" note_path="$2"
  python3 - "$pack_dir/pack.json" "$note_path" <<'PY'
import hashlib
import json
import pathlib
import sys

pack_path = pathlib.Path(sys.argv[1])
note_path = pathlib.PurePosixPath(sys.argv[2])
pack_dir = pack_path.parent
pack = json.loads(pack_path.read_text(encoding="utf-8"))
digest = hashlib.sha256((pack_dir / note_path).read_bytes()).hexdigest()
for note in pack["notes"]:
    if note["path"] == note_path.as_posix():
        note["sha256"] = digest
pack_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

add_note_entry() {
  local pack_dir="$1" note_path="$2" kind="$3"
  python3 - "$pack_dir/pack.json" "$note_path" "$kind" <<'PY'
import hashlib
import json
import pathlib
import sys

pack_path = pathlib.Path(sys.argv[1])
note_path = pathlib.PurePosixPath(sys.argv[2])
kind = sys.argv[3]
pack_dir = pack_path.parent
pack = json.loads(pack_path.read_text(encoding="utf-8"))
pack["notes"].append({
    "path": note_path.as_posix(),
    "kind": kind,
    "sha256": hashlib.sha256((pack_dir / note_path).read_bytes()).hexdigest(),
    "derived_from_spec_sha256": pack["spec"]["sha256"],
})
pack_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

assert_check_pack_passes() {
  local dir="$1"
  local output
  if output=$(bash tools/check-pack.sh "$dir" 2>&1); then
    if printf '%s\n' "$output" | grep -qx 'OK: pack checks passed' \
      && ! printf '%s\n' "$output" | grep -q '^WARN:' \
      && ! printf '%s\n' "$output" | grep -q '^FAIL:'; then
      pass
    else
      fail "check-pack passing output should include OK and no WARN or FAIL: $dir :: $output"
    fi
  else
    fail "check-pack should pass: $dir :: $output"
  fi
}

assert_check_pack_warns() {
  local dir="$1"
  local output
  if output=$(bash tools/check-pack.sh "$dir" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^WARN:' && printf '%s\n' "$output" | grep -q '^OK:'; then
      pass
    else
      fail "check-pack should pass with WARN: $dir :: $output"
    fi
  else
    fail "check-pack should not fail on WARN-only case: $dir :: $output"
  fi
}

assert_check_pack_fails_with() {
  local dir="$1" expected="$2"
  local output status
  output=$(bash tools/check-pack.sh "$dir" 2>&1)
  status=$?
  if [ "$status" -ne 1 ]; then
    fail "check-pack should exit 1: $dir :: status=$status :: $output"
    return
  fi
  if printf '%s\n' "$output" | grep -qF -- "$expected"; then
    pass
  else
    fail "check-pack failure for $dir should include $expected :: $output"
  fi
}

assert_check_pack_passes "$GREEN"

copy_case "warn-only"
printf '\n上限50万円の扱いは別途確認する。\n' >> "$TMP_ROOT/warn-only/notes/review-lens.md"
update_note_sha "$TMP_ROOT/warn-only" "notes/review-lens.md"
assert_check_pack_warns "$TMP_ROOT/warn-only"

copy_case "heading-not-fact-like"
printf '\n## 締切・期限\n   ###### 補助上限50万円について\n' >> "$TMP_ROOT/heading-not-fact-like/notes/review-lens.md"
update_note_sha "$TMP_ROOT/heading-not-fact-like" "notes/review-lens.md"
assert_check_pack_passes "$TMP_ROOT/heading-not-fact-like"

copy_case "heading-like-but-not-heading"
printf '\n#締切\n####### 補助上限50万円について\n' >> "$TMP_ROOT/heading-like-but-not-heading/notes/review-lens.md"
update_note_sha "$TMP_ROOT/heading-like-but-not-heading" "notes/review-lens.md"
assert_check_pack_warns "$TMP_ROOT/heading-like-but-not-heading"

copy_case "missing-required-key"
python3 - "$TMP_ROOT/missing-required-key/pack.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
pack = json.loads(path.read_text(encoding="utf-8"))
del pack["built_by"]
path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_check_pack_fails_with "$TMP_ROOT/missing-required-key" "missing required key: $.built_by"

copy_case "top-level-extra-key"
python3 - "$TMP_ROOT/top-level-extra-key/pack.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
pack = json.loads(path.read_text(encoding="utf-8"))
pack["extra"] = "not allowed"
path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_check_pack_fails_with "$TMP_ROOT/top-level-extra-key" "unexpected key: $.extra"

copy_case "spec-entry-extra-key"
python3 - "$TMP_ROOT/spec-entry-extra-key/pack.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
pack = json.loads(path.read_text(encoding="utf-8"))
pack["spec"]["extra"] = "not allowed"
path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_check_pack_fails_with "$TMP_ROOT/spec-entry-extra-key" "unexpected key: spec.extra"

copy_case "confirmation-entry-extra-key"
python3 - "$TMP_ROOT/confirmation-entry-extra-key/pack.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
pack = json.loads(path.read_text(encoding="utf-8"))
pack["confirmation"]["extra"] = "not allowed"
path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_check_pack_fails_with "$TMP_ROOT/confirmation-entry-extra-key" "unexpected key: confirmation.extra"

copy_case "note-entry-extra-key"
python3 - "$TMP_ROOT/note-entry-extra-key/pack.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
pack = json.loads(path.read_text(encoding="utf-8"))
pack["notes"][0]["extra"] = "not allowed"
path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_check_pack_fails_with "$TMP_ROOT/note-entry-extra-key" "unexpected key: notes[0].extra"

copy_case "missing-file"
python3 - "$TMP_ROOT/missing-file/pack.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
pack = json.loads(path.read_text(encoding="utf-8"))
pack["spec"]["path"] = "missing.json"
path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_check_pack_fails_with "$TMP_ROOT/missing-file" "pack listed file not found"

copy_case "sha-mismatch"
python3 - "$TMP_ROOT/sha-mismatch/pack.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
pack = json.loads(path.read_text(encoding="utf-8"))
pack["notes"][0]["sha256"] = "0" * 64
path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_check_pack_fails_with "$TMP_ROOT/sha-mismatch" "sha256 mismatch"

copy_case "stale-derived"
python3 - "$TMP_ROOT/stale-derived/pack.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
pack = json.loads(path.read_text(encoding="utf-8"))
pack["notes"][0]["derived_from_spec_sha256"] = "f" * 64
path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_check_pack_fails_with "$TMP_ROOT/stale-derived" "derived_from_spec_sha256 mismatch"

copy_case "bad-clause"
printf '\n存在しない根拠を参照する。[clause: missing-clause]\n' >> "$TMP_ROOT/bad-clause/notes/review-lens.md"
update_note_sha "$TMP_ROOT/bad-clause" "notes/review-lens.md"
assert_check_pack_fails_with "$TMP_ROOT/bad-clause" "unknown clause reference"

copy_case "unsupported-file"
printf 'print("not allowed")\n' > "$TMP_ROOT/unsupported-file/notes/helper.py"
assert_check_pack_fails_with "$TMP_ROOT/unsupported-file" "unsupported file in pack dir"

copy_case "unlisted-note"
printf 'Unlisted note fixture.\n' > "$TMP_ROOT/unlisted-note/notes/orphan.md"
assert_check_pack_fails_with "$TMP_ROOT/unlisted-note" "unlisted pack file: notes/orphan.md"

copy_case "duplicate-listed-path"
python3 - "$TMP_ROOT/duplicate-listed-path/pack.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
pack = json.loads(path.read_text(encoding="utf-8"))
pack["notes"][1]["path"] = pack["notes"][0]["path"]
path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_check_pack_fails_with "$TMP_ROOT/duplicate-listed-path" "duplicate listed pack path: notes/review-lens.md"

copy_case "examples-no-source"
cat > "$TMP_ROOT/examples-no-source/notes/examples.md" <<'EOF'
---
subsidy_id: pack-fixture
kind: examples
---

# 参考事例

## 事例1

上限50万円の投資例を確認する。[clause: clause-2]
EOF
add_note_entry "$TMP_ROOT/examples-no-source" "notes/examples.md" "examples"
assert_check_pack_fails_with "$TMP_ROOT/examples-no-source" "examples note missing source:"

copy_case "examples-second-block-no-source"
cat > "$TMP_ROOT/examples-second-block-no-source/notes/examples.md" <<'EOF'
---
subsidy_id: pack-fixture
kind: examples
---

# 参考事例

## 事例1

source: 合成募集要項 p.1

上限50万円の投資例を確認する。[clause: clause-2]

## 事例2

補助率50%の書き方を確認する。[clause: clause-2]
EOF
add_note_entry "$TMP_ROOT/examples-second-block-no-source" "notes/examples.md" "examples"
assert_check_pack_fails_with "$TMP_ROOT/examples-second-block-no-source" "examples note missing source:"

copy_case "duplicate-frontmatter-key"
cat > "$TMP_ROOT/duplicate-frontmatter-key/notes/review-lens.md" <<'EOF'
---
subsidy_id: pack-fixture
kind: review-lens
kind: review-lens
---

# レビュー観点

- 事業概要では、制度が求める記載対象と申請者自身の事業内容を分けて確認する。[clause: clause-3]
EOF
update_note_sha "$TMP_ROOT/duplicate-frontmatter-key" "notes/review-lens.md"
assert_check_pack_fails_with "$TMP_ROOT/duplicate-frontmatter-key" "note frontmatter duplicate key:"

test_tane01_draft_pack_roots() {
  local label root_value case_dir output status case_index=0
  for label in pack.json spec confirmation; do
    for root_value in 'null' '[]' 'true' '"text"'; do
      case_index=$((case_index+1))
      copy_case "tane01-roots-$case_index"
      case_dir="$TMP_ROOT/tane01-roots-$case_index"
      if ! python3 - "$case_dir" "$label" "$root_value" <<'PY'; then
import hashlib
import json
import pathlib
import sys

case_dir, label, raw = sys.argv[1:]
pack_dir = pathlib.Path(case_dir)
pack_path = pack_dir / "pack.json"
pack = json.loads(pack_path.read_text(encoding="utf-8"))
if label == "pack.json":
    pack_path.write_text(raw, encoding="utf-8")
else:
    target = pack_dir / pack[label]["path"]
    target.write_text(raw, encoding="utf-8")
    pack[label]["sha256"] = hashlib.sha256(target.read_bytes()).hexdigest()
    if label == "spec":
        confirmation_path = pack_dir / pack["confirmation"]["path"]
        confirmation = json.loads(confirmation_path.read_text(encoding="utf-8"))
        confirmation["spec_sha256"] = pack["spec"]["sha256"]
        confirmation_path.write_text(json.dumps(confirmation), encoding="utf-8")
        pack["confirmation"]["sha256"] = hashlib.sha256(confirmation_path.read_bytes()).hexdigest()
        # Keep inventory and provenance consistent with the changed spec.
        pack["notes"] = []
        for note_path in (pack_dir / "notes").rglob("*.md"):
            note_path.unlink()
    pack_path.write_text(json.dumps(pack), encoding="utf-8")
PY
        fail "tane01 pack root fixture setup"
        return
      fi
      output=$(bash tools/check-pack.sh "$case_dir" 2>&1)
      status=$?
      if [ "$status" -eq 1 ] &&
         printf '%s\n' "$output" | grep -qF "FAIL: $label root must be an object" &&
         ! printf '%s\n' "$output" | grep -qE 'sha256 mismatch|unlisted pack file|listed file not found'; then
        pass
      else
        fail "tane01 pack $label root $root_value must exit 1 with root diagnostic :: $output"
      fi
    done
  done
}

test_tane01_draft_pack_roots

prepare_tane06_named_confirmation() {
  local name="$1" field="${2:-valid}"
  copy_case "$name" || return 1
  python3 - "$TMP_ROOT/$name" "$field" <<'PY'
import hashlib
import json
import pathlib
import sys

pack_dir = pathlib.Path(sys.argv[1])
field = sys.argv[2]
pack_path = pack_dir / "pack.json"
pack = json.loads(pack_path.read_text(encoding="utf-8"))
confirmation_path = pack_dir / "approved.json"
(pack_dir / pack["confirmation"]["path"]).rename(confirmation_path)
confirmation = json.loads(confirmation_path.read_text(encoding="utf-8"))
if field == "spec_path":
    confirmation[field] = "other-spec.json"
elif field == "spec_version":
    confirmation[field] += 1
elif field == "spec_sha256":
    confirmation[field] = "0" * 64
elif field == "open":
    confirmation["items"][0]["state"] = "open"
elif field == "pending":
    item = next(item for item in confirmation["items"]
                if item["field_path"] == "eligibility.rules.rule-1")
    item["predicate_state"] = "pending"
elif field == "confirmed_by":
    confirmation[field] = ["provider"]
elif field != "valid":
    raise SystemExit("unknown confirmation fixture field")
confirmation_path.write_text(json.dumps(confirmation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
pack["confirmation"]["path"] = "approved.json"
pack["confirmation"]["sha256"] = hashlib.sha256(confirmation_path.read_bytes()).hexdigest()
pack_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

test_tane06_named_confirmation() {
  if ! prepare_tane06_named_confirmation "tane06-named"; then
    fail "tane06 named confirmation fixture setup"
    return
  fi
  assert_check_pack_passes "$TMP_ROOT/tane06-named"
  assert_check_pack_passes "$TMP_ROOT/tane06-named/pack.json"
}

test_tane06_named_confirmation_invalid() {
  local field expected
  for field in spec_path spec_version spec_sha256 open pending; do
    if ! prepare_tane06_named_confirmation "tane06-named-$field" "$field"; then
      fail "tane06 named confirmation $field fixture setup"
      continue
    fi
    case "$field" in
      spec_path|spec_version|spec_sha256) expected="confirmation $field mismatch:" ;;
      open) expected="unconfirmed required item: schedule.application-deadline" ;;
      pending) expected="predicate_state pending: eligibility.rules.rule-1" ;;
    esac
    assert_check_pack_fails_with "$TMP_ROOT/tane06-named-$field" "$expected"
    assert_check_pack_fails_with "$TMP_ROOT/tane06-named-$field/pack.json" "$expected"
  done
}

test_tane06_named_confirmation
test_tane06_named_confirmation_invalid

test_tane06_confirmation_invalid_type_preserves_diagnostics() {
  local case_dir="$TMP_ROOT/tane06-confirmation-invalid-type"
  local stderr_path="$TMP_ROOT/tane06-confirmation-invalid-type.stderr"
  local pack_input output status
  if ! prepare_tane06_named_confirmation "tane06-confirmation-invalid-type" "confirmed_by"; then
    fail "tane06 invalid confirmation type fixture setup"
    return
  fi
  printf 'Unlisted note fixture.\n' > "$case_dir/notes/orphan.md"
  # Leave the note hash unchanged to verify later diagnostics are preserved.
  printf '\nUnknown reference fixture. [clause: missing-clause]\n' >> "$case_dir/notes/review-lens.md"

  for pack_input in "$case_dir" "$case_dir/pack.json"; do
    output=$(bash tools/check-pack.sh "$pack_input" 2>"$stderr_path")
    status=$?
    if [ "$status" -eq 1 ] &&
       printf '%s\n' "$output" | grep -qF 'FAIL: unlisted pack file: notes/orphan.md' &&
       printf '%s\n' "$output" | grep -qF 'FAIL: check-spec failed:' &&
       printf '%s\n' "$output" | grep -qF 'FAIL: sha256 mismatch: notes[0].path=notes/review-lens.md' &&
       printf '%s\n' "$output" | grep -qF 'FAIL: unknown clause reference:' &&
       printf '%s\n' "$output" | grep -qF '[clause: missing-clause]' &&
       ! printf '%s\n' "$output" | grep -qE 'Traceback|TypeError|sha256 mismatch: confirmation' &&
       ! grep -qE 'Traceback|TypeError' "$stderr_path"; then
      pass
    else
      fail "tane06 invalid confirmation type must exit 1 and preserve stdout diagnostics: $pack_input :: status=$status :: stdout=$output :: stderr=$(cat "$stderr_path")"
    fi
  done
}

test_tane06_confirmation_invalid_type_preserves_diagnostics

test_tane06_failure_matrix() {
  if python3 -B - "$TMP_ROOT/tane06-failures" <<'PY'; then
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
green = pathlib.Path("tools/fixtures/packs/green")

# Each row combines one input failure with independent inventory, hash, and note errors.
cases = [
    ("confirmation-type", "confirmation", ("confirmed_by",), ["provider"], "confirmation.confirmed_by"),
    ("confirmation-state-type", "confirmation", ("items", 0, "state"), {}, "invalid confirmation state"),
    ("confirmation-predicate-type", "confirmation", ("items", 0, "predicate_state"), [], "predicate_state must be"),
    ("confirmation-via-type", "confirmation", ("items", 0, "confirmed_via"), {}, "confirmed_via must be"),
    ("confirmation-items-type", "confirmation", ("items",), None, "confirmation.items must be an array"),
    ("confirmation-item-type", "confirmation", ("items", 0), False, "confirmation.items[0] must be an object"),
    ("confirmation-field-type", "confirmation", ("items", 0, "field_path"), {}, "field_path must be"),
    ("confirmation-clause-type", "confirmation", ("items", 0, "source_clauses"), [{}], "source_clauses[0] must be a string"),
    ("confirmation-clause-unknown", "confirmation", ("items", 0, "source_clauses"), ["missing-clause"], "unknown confirmation source_clauses reference:"),
    ("confirmation-clause-mismatch", "confirmation", ("items", 0, "source_clauses"), ["clause-2"], "confirmation source_clauses mismatch:"),
    ("confirmation-sha-type", "confirmation", ("spec_sha256",), [], "confirmation.spec_sha256 must be"),
    ("confirmation-path-type", "confirmation", ("spec_path",), [], "confirmation.spec_path must be"),
    ("confirmation-json", "confirmation", (), "json", "confirmation invalid JSON:"),
    ("confirmation-decode", "confirmation", (), "decode", "confirmation cannot be read:"),
    ("confirmation-missing", "confirmation", (), "missing", "pack listed file not found: confirmation"),
    ("confirmation-permission", "confirmation", (), "permission", "confirmation cannot be read:"),
    ("extract-type", "spec", ("source_documents", 0, "extract_path"), {}, "invalid extract_path:"),
    ("extract-missing", "extract", (), "missing", "extract file not found:"),
    ("extract-permission", "extract", (), "permission", "extract file cannot be read:"),
    ("extract-directory", "extract", (), "directory", "extract file cannot be read:"),
    ("extract-decode", "extract", (), "decode", "extract file cannot be read:"),
    ("extract-path-value", "spec", ("source_documents", 0, "extract_path"), "bad\0path", "extract file cannot be read:"),
    ("spec-clauses-type", "spec", ("clauses",), None, "$.clauses must be an array"),
    ("spec-deliverables-type", "spec", ("deliverables",), False, "$.deliverables must be an array"),
    ("spec-json", "spec", (), "json", "spec invalid JSON:"),
    ("spec-decode", "spec", (), "decode", "spec cannot be read:"),
    ("spec-hash-permission", "spec", (), "hash-permission", "cannot be hashed:"),
    ("confirmation-hash-permission", "confirmation", (), "hash-permission", "cannot be hashed:"),
    ("confirmation-sha-read", "spec", (), "second-hash-permission", "spec cannot be hashed:"),
    ("note-type", "pack", ("notes", 0, "kind"), [], "notes[0].kind must be"),
    ("pack-type", "pack", ("built_by",), {}, "built_by must be"),
    ("note-decode", "note", (), "decode", "note cannot be read:"),
    ("note-permission", "note", (), "permission", "note cannot be read:"),
    ("note-hash-permission", "note", (), "hash-permission", "cannot be hashed:"),
    ("note-missing", "note", (), "missing", "pack listed file not found: notes[0]"),
]

# Inject filesystem exceptions at the I/O boundary, including under privileged test users.
runner = r'''
import errno
import pathlib
import runpy
import sys
from unittest.mock import patch

script, pack_input, fault_path, fault = sys.argv[1:]
sys.path.insert(0, str(pathlib.Path(script).resolve().parent))
original_open = pathlib.Path.open
hash_reads = 0
def fixture_open(path, mode="r", *args, **kwargs):
    global hash_reads
    if str(path) == fault_path:
        if mode == "rb":
            hash_reads += 1
        if (fault == "permission" or
                fault == "hash-permission" and mode == "rb" or
                fault == "second-hash-permission" and mode == "rb" and hash_reads == 2):
            raise PermissionError(errno.EACCES, "Permission denied", str(path))
    return original_open(path, mode, *args, **kwargs)
sys.argv = [script, pack_input]
with patch.object(pathlib.Path, "open", fixture_open):
    runpy.run_path(script, run_name="__main__")
'''

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

failures = []
checks = 0
for name, target, keys, value, expected in cases:
    for named in (False, True):
        case_dir = (root / (name + ("-named" if named else "-default"))).resolve()
        shutil.copytree(green, case_dir)
        pack_path = case_dir / "pack.json"
        pack = json.loads(pack_path.read_text(encoding="utf-8"))
        spec_path = case_dir / pack["spec"]["path"]
        spec = json.loads(spec_path.read_text(encoding="utf-8"))
        confirmation_path = case_dir / pack["confirmation"]["path"]
        confirmation = json.loads(confirmation_path.read_text(encoding="utf-8"))
        if named:
            confirmation_path = confirmation_path.rename(case_dir / "approved.json")
            pack["confirmation"]["path"] = confirmation_path.name
        extract_path = case_dir.parent / (case_dir.name + ".extract.md")
        note_path = case_dir / pack["notes"][0]["path"]
        confirmation["spec_path"] = str(spec_path)
        objects = {"spec": spec, "confirmation": confirmation, "pack": pack}
        if keys:
            obj = objects[target]
            for key in keys[:-1]:
                obj = obj[key]
            obj[keys[-1]] = value
        if target == "extract":
            spec["source_documents"][0]["extract_path"] = str(extract_path)
            extract_path.write_text("Synthetic extract.\n", encoding="utf-8")
        # These checks must survive earlier extract, confirmation type, and hash failures.
        confirmation["spec_version"] += 1
        if isinstance(confirmation.get("items"), list) and isinstance(confirmation["items"][1], dict):
            confirmation["items"][1]["state"] = "open"
        save(spec_path, spec)
        pack["spec"]["sha256"] = digest(spec_path)
        if not (target == "confirmation" and keys == ("spec_sha256",)):
            confirmation["spec_sha256"] = pack["spec"]["sha256"]
        save(confirmation_path, confirmation)
        pack["confirmation"]["sha256"] = digest(confirmation_path)
        for note in pack["notes"]:
            note["derived_from_spec_sha256"] = pack["spec"]["sha256"]
        fault_path = {"spec": spec_path, "confirmation": confirmation_path,
                      "extract": extract_path, "note": note_path, "pack": pack_path}[target]
        fault = value if not keys else ""
        if fault == "decode":
            fault_path.write_bytes(b"\xff")
        elif fault == "json":
            fault_path.write_text("{", encoding="utf-8")
        if fault_path.is_file() and target in ("spec", "confirmation"):
            pack[target]["sha256"] = digest(fault_path)
        if fault == "missing":
            fault_path.unlink()
        elif fault == "directory":
            fault_path.unlink()
            fault_path.mkdir()
        (case_dir / "notes/orphan.md").write_text("Unlisted note fixture.\n", encoding="utf-8")
        # A later note must still report both its hash and its clause reference error.
        later_note = case_dir / pack["notes"][1]["path"]
        with later_note.open("a", encoding="utf-8") as stream:
            stream.write("\nUnknown reference fixture. [clause: missing-clause]\n")
        pack["notes"][1]["derived_from_spec_sha256"] = "0" * 64
        save(pack_path, pack)
        required = [
            "FAIL: unlisted pack file: notes/orphan.md",
            "FAIL: check-spec failed:",
            "FAIL: sha256 mismatch: notes[1].path=notes/scoring-strategy.md",
            "FAIL: derived_from_spec_sha256 mismatch: notes[1]",
            "FAIL: unknown clause reference:", "[clause: missing-clause]", expected,
        ]
        if target in ("extract", "note") or keys or "hash-permission" in fault:
            required.append("confirmation spec_version mismatch:")
        if target == "extract" or "hash-permission" in fault:
            required.append("unconfirmed required item: eligibility.rules.rule-1")
        for pack_input in (case_dir, pack_path):
            result = subprocess.run(
                [sys.executable, "-B", "-c", runner, "tools/lib/check_pack.py",
                 str(pack_input), str(fault_path), fault],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            checks += 1
            if (result.returncode != 1 or result.stderr or "Traceback" in result.stdout or
                    not all(message in result.stdout for message in required)):
                failures.append(f"{case_dir.name}/{pack_input.name}: exit={result.returncode}\n"
                                f"stdout={result.stdout}\nstderr={result.stderr}")
for failure in failures:
    print("FAIL: tane06 failure matrix: " + failure)
print(f"=== tane06 failure matrix: {checks - len(failures)} pass / {len(failures)} fail ===")
sys.exit(bool(failures))
PY
    pass
  else
    fail "tane06 failure matrix must preserve independent diagnostics without Traceback"
  fi
}

test_tane06_failure_matrix

echo "=== test-check-pack: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
