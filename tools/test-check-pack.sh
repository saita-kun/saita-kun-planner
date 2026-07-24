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
    if printf '%s\n' "$output" | grep -q '^OK:' && ! printf '%s\n' "$output" | grep -q '^FAIL:'; then
      pass
    else
      fail "check-pack passing output should include OK and no FAIL: $dir :: $output"
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
  if [ "$status" -eq 0 ]; then
    fail "check-pack should fail: $dir :: $output"
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

echo "=== test-check-pack: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
