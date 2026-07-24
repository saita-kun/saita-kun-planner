#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/saita-update-core.XXXXXX")"
LOCAL="$TMP_ROOT/local"
UPSTREAM="$TMP_ROOT/upstream"
PASS=0
FAIL=0

# Files introduced by each stacked manifest change. The upgrade fixture removes
# every one from the old customer checkout while leaving upstream untouched.
PR1_MANIFEST_PATHS=(
  "README.en.md"
  "docs/ai-agent-guide.md"
  "tools/fixtures/forbidden/adversarial.json"
  "tools/fixtures/forbidden/cases.json"
  "tools/fixtures/forbidden/legal-negative.json"
  "tools/forbidden-phrase-allowlist.json"
  "tools/lib/check_forbidden_phrases.py"
  "tools/lib/export-excluded-paths.txt"
  "tools/test-forbidden-phrases.sh"
)
PR2_MANIFEST_PATHS=(
  ".github/ISSUE_TEMPLATE/adopter-entry.yml"
  "ADOPTERS.md"
  "tools/fixtures/bundled-resolver/flat-duplicate/one.json"
  "tools/fixtures/bundled-resolver/flat-duplicate/two.json"
  "tools/fixtures/bundled-resolver/pack-duplicate/one/one.json"
  "tools/fixtures/bundled-resolver/pack-duplicate/one/pack.json"
  "tools/fixtures/bundled-resolver/pack-duplicate/two/pack.json"
  "tools/fixtures/bundled-resolver/pack-duplicate/two/two.json"
  "tools/fixtures/bundled-resolver/pack-flat-conflict/canonical/pack.json"
  "tools/fixtures/bundled-resolver/pack-flat-conflict/canonical/resolver-conflict-pack.json"
  "tools/fixtures/bundled-resolver/pack-flat-conflict/resolver-conflict.json"
  "tools/fixtures/bundled-resolver/stable-order/alpha.json"
  "tools/fixtures/bundled-resolver/stable-order/zeta.json"
  "tools/fixtures/spec/deadline-date-only.json"
  "tools/fixtures/spec/deadline-multiple-partial.json"
  "tools/fixtures/spec/deadline-past.json"
  "tools/fixtures/spec/deadline-start-past-future.json"
  "tools/fixtures/spec/deadline-time.json"
  "tools/fixtures/spec/provider-customer-null-boundary.json"
  "tools/fixtures/spec/provider-invalid-item-confirmed-at.confirmation.json"
  "tools/fixtures/spec/provider-invalid-item-confirmed-at.json"
  "tools/fixtures/spec/provider-missing-item-confirmed-at.confirmation.json"
  "tools/fixtures/spec/provider-missing-item-confirmed-at.json"
  "tools/fixtures/spec/provider-null-portal-url.confirmation.json"
  "tools/fixtures/spec/provider-null-portal-url.json"
  "tools/fixtures/spec/provider-null-round.confirmation.json"
  "tools/fixtures/spec/provider-null-round.json"
  "tools/fixtures/trust-freshness/stale-spec-sha/freshness-stale-sha/freshness-stale-sha.confirmation.json"
  "tools/fixtures/trust-freshness/stale-spec-sha/freshness-stale-sha/freshness-stale-sha.json"
  "tools/fixtures/trust-freshness/stale-spec-sha/freshness-stale-sha/pack.json"
  "tools/lib/check_trust_freshness.py"
  "tools/lib/spec_resolver.py"
)
NEW_MANIFEST_PATHS=(
  "${PR1_MANIFEST_PATHS[@]}"
  "${PR2_MANIFEST_PATHS[@]}"
)
NEWLY_MANAGED_CORE_PATHS=(
  ".gitattributes"
  "${NEW_MANIFEST_PATHS[@]}"
)

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

copy_fixture() {
  local src="$1" dst="$2"
  python3 - "$src" "$dst" <<'PY'
import pathlib
import shutil
import sys

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])

def ignore(_dir, names):
    ignored = {".git", ".ralph", ".update-core-state.json", ".update-core-state.json.tmp", "__pycache__"}
    return [name for name in names if name in ignored or name.endswith(".pyc")]

shutil.copytree(src, dst, ignore=ignore)
PY
}

prepare_git_repo() {
  git -C "$LOCAL" init --quiet || return 1
  git -C "$LOCAL" config user.email "fixture@example.invalid" || return 1
  git -C "$LOCAL" config user.name "Fixture" || return 1
  git -C "$LOCAL" add . || return 1
  git -C "$LOCAL" commit --quiet -m "fixture base" || return 1
}

mutate_upstream() {
  python3 - "$UPSTREAM" <<'PY'
import pathlib
import sys

upstream = pathlib.Path(sys.argv[1])

(upstream / "docs/manual.md").write_text(
    (upstream / "docs/manual.md").read_text(encoding="utf-8")
    + "\n\n<!-- update-core fixture: upstream core change -->\n",
    encoding="utf-8",
)

(upstream / "input/.gitkeep").write_text("UPSTREAM INPUT CHANGE\n", encoding="utf-8")
(upstream / "knowledge/lessons/upstream-should-not-copy.md").write_text(
    "UPSTREAM KNOWLEDGE CHANGE\n",
    encoding="utf-8",
)
(upstream / ".claude/commands/my-upstream.md").write_text(
    "---\ndescription: user command fixture\n---\n\nこのファイルはコピーされてはいけません。\n",
    encoding="utf-8",
)
PY
}

prepare_old_customer() {
  local target="$1"
  shift
  python3 - "$target" "$@" <<'PY'
import importlib.util
import json
import pathlib
import shutil
import sys

target = pathlib.Path(sys.argv[1])
removed = tuple(sys.argv[2:])
if not removed:
    raise SystemExit("old-customer fixture requires new manifest paths")

checker_path = target / "tools/lib/check_forbidden_phrases.py"
spec = importlib.util.spec_from_file_location("fixture_forbidden_checker", checker_path)
if spec is None or spec.loader is None:
    raise SystemExit("could not load fixture export exclusion parser")
checker = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = checker
spec.loader.exec_module(checker)
for relative_path in checker.load_export_excluded_paths(target):
    path = target / relative_path
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)

manifest_path = target / "core-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
core_paths = manifest.get("core_paths")
if not isinstance(core_paths, list):
    raise SystemExit("fixture manifest core_paths must be an array")
newly_managed = {".gitattributes", *removed}
missing = sorted(newly_managed - set(core_paths))
if missing:
    raise SystemExit(f"new paths missing from reviewed upstream manifest: {missing}")

for relative_path in removed:
    path = target / relative_path
    if not path.is_file():
        raise SystemExit(f"new fixture path is not a file: {relative_path}")
    path.unlink()

manifest["core_paths"] = [
    path for path in manifest["core_paths"] if path not in newly_managed
]
manifest_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
(target / ".gitattributes").write_text(
    """# Fresh-start export uses git archive, which must exclude .ralph.
.ralph export-ignore

# Legacy public export exclusions.
docs/strategy export-ignore
docs/design/pivot-decision.md export-ignore
docs/design/wave-plans.md export-ignore
docs/design/harness-backlog.md export-ignore
docs/plans export-ignore
tools/release export-ignore
""",
    encoding="utf-8",
)
PY
}

assert_status_clean() {
  local label="$1" status
  status="$(git -C "$LOCAL" status --short)"
  if [ -z "$status" ]; then
    pass
  else
    fail "$label should leave git status clean :: $status"
  fi
}

assert_output_contains() {
  local output="$1" needle="$2" label="$3"
  if printf '%s\n' "$output" | grep -qF -- "$needle"; then
    pass
  else
    fail "$label missing output: $needle :: $output"
  fi
}

assert_file_contains() {
  local path="$1" needle="$2" label="$3"
  if [ -f "$path" ] && grep -qF -- "$needle" "$path"; then
    pass
  else
    fail "$label missing file content: $path :: $needle"
  fi
}

assert_file_not_contains() {
  local path="$1" needle="$2" label="$3"
  if [ -f "$path" ] && ! grep -qF -- "$needle" "$path"; then
    pass
  else
    fail "$label should not contain: $path :: $needle"
  fi
}

assert_absent() {
  local path="$1" label="$2"
  if [ ! -e "$path" ]; then
    pass
  else
    fail "$label should be absent: $path"
  fi
}

assert_present() {
  local path="$1" label="$2"
  if [ -f "$path" ]; then
    pass
  else
    fail "$label should be a file: $path"
  fi
}

assert_files_identical() {
  local left="$1" right="$2" label="$3"
  if cmp -s "$left" "$right"; then
    pass
  else
    fail "$label should be identical: $left :: $right"
  fi
}

assert_manifest_membership() {
  local manifest_path="$1" label="$2"
  shift 2
  if python3 - "$manifest_path" "$@" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
required = set(sys.argv[2:])
document = json.loads(manifest_path.read_text(encoding="utf-8"))
core_paths = document.get("core_paths")
if not isinstance(core_paths, list):
    raise SystemExit("core_paths must be an array")
missing = sorted(required - set(core_paths))
if missing:
    raise SystemExit(f"manifest membership missing: {missing}")
PY
  then
    pass
  else
    fail "$label"
  fi
}

reset_pair() {
  rm -rf "$LOCAL" "$UPSTREAM"
  copy_fixture "$ROOT" "$LOCAL"
  copy_fixture "$ROOT" "$UPSTREAM"
}

write_baseline_state() {
  python3 - "$LOCAL" <<'PY'
import hashlib
import json
import pathlib
import sys

local = pathlib.Path(sys.argv[1])
manifest = json.loads((local / "core-manifest.json").read_text(encoding="utf-8"))
core_paths = manifest.get("core_paths")
if not isinstance(core_paths, list):
    raise SystemExit("old-customer core_paths must be an array")

files = {}
for relative_path in core_paths:
    path = local / relative_path
    if not path.is_file():
        raise SystemExit(f"old-customer core path missing: {relative_path}")
    files[relative_path] = hashlib.sha256(path.read_bytes()).hexdigest()

state = {"state_version": 1, "files": dict(sorted(files.items()))}
(local / ".update-core-state.json").write_text(
    json.dumps(state, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
  if [ -f "$LOCAL/.update-core-state.json" ]; then
    pass
  else
    fail "old-customer fixture should create .update-core-state.json"
  fi
}

reset_pair

printf '\nLOCAL FIRST-RUN EDIT\n' >> "$LOCAL/docs/manual.md"
printf '\nUPSTREAM FIRST-RUN EDIT\n' >> "$UPSTREAM/docs/manual.md"

first_run_output="$(cd "$LOCAL" && bash tools/update-core.sh --apply "$UPSTREAM" 2>&1)"
first_run_status=$?
if [ "$first_run_status" -eq 0 ]; then
  pass
else
  fail "first-run apply should exit 0 while skipping local edits :: $first_run_output"
fi
assert_output_contains "$first_run_output" $'user-modified\tdocs/manual.md' "first-run local edit status"
assert_output_contains "$first_run_output" "WARN: skipped user-modified docs/manual.md" "first-run local edit warning"
assert_output_contains "$first_run_output" "--force-file docs/manual.md" "first-run warning explains force-file override"
assert_file_contains "$LOCAL/docs/manual.md" "LOCAL FIRST-RUN EDIT" "first-run skip preserves local core edit"
assert_file_not_contains "$LOCAL/docs/manual.md" "UPSTREAM FIRST-RUN EDIT" "first-run skip prevents silent overwrite"

reset_pair
prepare_old_customer "$LOCAL" "${NEW_MANIFEST_PATHS[@]}"
write_baseline_state

if ! prepare_git_repo; then
  echo "FAIL: could not prepare temp git repo"
  exit 1
fi

mutate_upstream
assert_files_identical \
  "$ROOT/core-manifest.json" \
  "$UPSTREAM/core-manifest.json" \
  "upstream fixture keeps the reviewed manifest unchanged"

dry_output="$(cd "$LOCAL" && bash tools/update-core.sh --dry-run "$UPSTREAM" 2>&1)"
dry_status=$?
if [ "$dry_status" -eq 0 ]; then
  pass
else
  fail "dry-run should exit 0 :: $dry_output"
fi
assert_output_contains "$dry_output" $'changed\tdocs/manual.md' "dry-run changed core file"
for relative_path in "${NEW_MANIFEST_PATHS[@]}"; do
  assert_output_contains \
    "$dry_output" \
    "$(printf 'new\t%s' "$relative_path")" \
    "dry-run distributes new manifest file $relative_path"
done
assert_output_contains \
  "$dry_output" \
  $'user-modified\t.gitattributes' \
  "dry-run recognizes the legacy unmanaged .gitattributes"
assert_status_clean "dry-run"

apply_output="$(cd "$LOCAL" && bash tools/update-core.sh --apply "$UPSTREAM" 2>&1)"
apply_status=$?
if [ "$apply_status" -eq 0 ]; then
  pass
else
  fail "apply should exit 0 :: $apply_output"
fi
assert_file_contains "$LOCAL/docs/manual.md" "update-core fixture: upstream core change" "apply copies changed core file"
assert_file_contains "$LOCAL/README.en.md" "## Legal scope" "apply distributes new English README"
assert_file_contains "$LOCAL/docs/ai-agent-guide.md" "guide_version" "apply distributes new AI guide"
assert_file_contains "$LOCAL/tools/lib/check_forbidden_phrases.py" "NEGATION_TERMS" "apply distributes new checker helper"
for relative_path in "${NEW_MANIFEST_PATHS[@]}"; do
  assert_present "$LOCAL/$relative_path" "apply distributes new manifest file $relative_path"
done
assert_output_contains \
  "$apply_output" \
  "WARN: skipped user-modified .gitattributes" \
  "apply preserves the legacy unmanaged .gitattributes"
assert_file_contains \
  "$LOCAL/.gitattributes" \
  "docs/strategy export-ignore" \
  "legacy customer .gitattributes remains available to migration validation"
assert_files_identical \
  "$ROOT/core-manifest.json" \
  "$LOCAL/core-manifest.json" \
  "apply copies the reviewed upstream manifest"
assert_manifest_membership \
  "$LOCAL/core-manifest.json" \
  "applied manifest includes every new PR-1/PR-2 path" \
  "${NEWLY_MANAGED_CORE_PATHS[@]}"
assert_file_contains "$LOCAL/.update-core-state.json" "docs/manual.md" "apply creates state file"
assert_file_not_contains "$LOCAL/input/.gitkeep" "UPSTREAM INPUT CHANGE" "apply leaves input untouched"
assert_absent "$LOCAL/knowledge/lessons/upstream-should-not-copy.md" "apply leaves knowledge untouched"
assert_absent "$LOCAL/.claude/commands/my-upstream.md" "apply leaves my-* command untouched"

customer_validate_output="$(
  cd "$LOCAL" \
    && SAITA_UPDATE_CORE_NESTED_VALIDATE=1 bash tools/validate.sh 2>&1
)"
customer_validate_status=$?
if [ "$customer_validate_status" -eq 0 ]; then
  pass
else
  validate_tail="$(printf '%s\n' "$customer_validate_output" | tail -n 20)"
  fail "updated legacy customer checkout should validate green :: $validate_tail"
fi
assert_output_contains \
  "$customer_validate_output" \
  "WARN: legacy .gitattributes export-ignore entries accepted for migration" \
  "validate guides the legacy .gitattributes migration"
assert_output_contains \
  "$customer_validate_output" \
  "=== validate:" \
  "updated legacy customer checkout completes validate"

printf '\nLOCAL README CHANGE\n' >> "$LOCAL/README.md"
printf '\nUPSTREAM README CHANGE\n' >> "$UPSTREAM/README.md"

skip_output="$(cd "$LOCAL" && bash tools/update-core.sh --apply "$UPSTREAM" 2>&1)"
skip_status=$?
if [ "$skip_status" -eq 0 ]; then
  pass
else
  fail "apply with local modification should still exit 0 :: $skip_output"
fi
assert_output_contains "$skip_output" $'user-modified\tREADME.md' "local modification status"
assert_output_contains "$skip_output" "WARN: skipped user-modified README.md" "local modification warning"
assert_file_contains "$LOCAL/README.md" "LOCAL README CHANGE" "skip preserves local core edit"
assert_file_not_contains "$LOCAL/README.md" "UPSTREAM README CHANGE" "skip does not overwrite local core edit"

echo "=== test-update-core: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
