#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/saita-update-core.XXXXXX")"
LOCAL="$TMP_ROOT/local"
UPSTREAM="$TMP_ROOT/upstream"
ANCESTOR="$TMP_ROOT/ancestor"
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
JOURNEY_MANIFEST_PATHS=(
  ".claude/commands/journey-map.md"
  "schemas/journey-flow.schema.json"
  "templates/journey/base-flow.json"
  "tools/fixtures/journey/ai-no-clause-flow.json"
  "tools/fixtures/journey/cycle-flow.json"
  "tools/fixtures/journey/missing-ref-flow.json"
  "tools/fixtures/journey/post-cycle-spec.json"
  "tools/fixtures/journey/schema-bad-flow.json"
  "tools/fixtures/journey/xss-spec.json"
  "tools/journey-map.sh"
  "tools/lib/journey_map.py"
  "tools/test-journey-map.sh"
)
NEW_MANIFEST_PATHS=(
  "${PR1_MANIFEST_PATHS[@]}"
  "${PR2_MANIFEST_PATHS[@]}"
  "${JOURNEY_MANIFEST_PATHS[@]}"
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
import subprocess
import sys

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])

git_result = subprocess.run(
    ["git", "-C", str(src), "ls-files", "-z", "--", "input"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if git_result.returncode != 0:
    stderr = git_result.stderr.decode("utf-8", errors="replace").strip()
    raise SystemExit(f"git ls-files failed while computing tracked input files: {stderr}")

tracked_input_files = {
    path.decode("utf-8")
    for path in git_result.stdout.split(b"\0")
    if path
}
tracked_input_dirs = set()
for relative_path in tracked_input_files:
    parent = pathlib.PurePosixPath(relative_path).parent
    while str(parent) not in ("", "."):
        tracked_input_dirs.add(parent.as_posix())
        parent = parent.parent

retained_input_paths = tracked_input_files | tracked_input_dirs
for relative_path in sorted(
    retained_input_paths,
    key=lambda path: (path.count("/"), path),
):
    if (src / relative_path).is_symlink():
        raise SystemExit(
            f"refusing to copy symlink in retained input path: {relative_path}"
        )

def ignore(_dir, names):
    ignored = {".git", ".ralph", ".update-core-state.json", ".update-core-state.json.tmp", "__pycache__"}
    ignored_names = [name for name in names if name in ignored or name.endswith(".pyc")]
    relative_dir = pathlib.Path(_dir).relative_to(src).as_posix()
    if relative_dir == ".":
        if "input" in names and "input" not in tracked_input_dirs:
            ignored_names.append("input")
        return ignored_names
    if relative_dir == "input" or relative_dir.startswith("input/"):
        for name in names:
            relative_path = f"{relative_dir}/{name}"
            if relative_path not in tracked_input_files and relative_path not in tracked_input_dirs:
                ignored_names.append(name)
    return ignored_names

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

prepare_copy_fixture_seal_repo() {
  local target="$1"
  mkdir -p "$target" || return 1
  git -C "$target" init --quiet || return 1
  git -C "$target" config user.email "fixture@example.invalid" || return 1
  git -C "$target" config user.name "Fixture" || return 1
  mkdir -p "$target/input/nested" "$target/sub/input" || return 1
  printf 'tracked root input\n' > "$target/input/.gitkeep" || return 1
  printf 'tracked deep input\n' > "$target/input/nested/deep.txt" || return 1
  printf 'tracked nested-name file\n' > "$target/sub/input/keep.txt" || return 1
  git -C "$target" add input/.gitkeep input/nested/deep.txt sub/input/keep.txt || return 1
  git -C "$target" commit --quiet -m "fixture base" || return 1
  mkdir -p "$target/input/junk" || return 1
  printf 'root secret\n' > "$target/input/secret.txt" || return 1
  printf 'sibling secret\n' > "$target/input/nested/sibling-secret.txt" || return 1
  printf 'junk secret\n' > "$target/input/junk/file.txt" || return 1
  printf 'other input extra\n' > "$target/sub/input/extra.txt" || return 1
  ln -s secret.txt "$target/input/secret-link" || return 1
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
  rm -rf "$LOCAL" "$UPSTREAM" "$ANCESTOR"
  copy_fixture "$ROOT" "$LOCAL"
  copy_fixture "$ROOT" "$UPSTREAM"
}

install_legacy_updater() {
  local target
  for target in "$@"; do
    FIXTURE_ROOT="$target" python3 - <<'PY'
import os
import pathlib

root = pathlib.Path(os.environ["FIXTURE_ROOT"])
(root / "tools/update-core.sh").write_text(
    """#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$SCRIPT_DIR/lib/update_core.py" --repo-root "$ROOT" "$@"
""",
    encoding="utf-8",
)
(root / "tools/lib/update_core.py").write_text(
    """#!/usr/bin/env python3
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("upstream_checkout", nargs="?")
parser.add_argument("--repo-root", required=True)
parser.add_argument("--dry-run", action="store_true")
parser.add_argument("--apply", action="store_true")
parser.add_argument("--generate-state", action="store_true")
parser.add_argument("--force-file", action="append", default=[])
parser.parse_args()
""",
    encoding="utf-8",
)
PY
  done
}

write_baseline_state() {
  if python3 "$LOCAL/tools/lib/update_core.py" \
      --repo-root "$LOCAL" \
      --generate-state &&
     [ -f "$LOCAL/.update-core-state.json" ]; then
    pass
  else
    fail "old-customer fixture should create .update-core-state.json"
  fi
}

seal_src="$TMP_ROOT/seal-src"
seal_dst="$TMP_ROOT/seal-dst"
if ! prepare_copy_fixture_seal_repo "$seal_src"; then
  echo "FAIL: could not prepare copy_fixture seal repo"
  exit 1
fi

seal_output="$(copy_fixture "$seal_src" "$seal_dst" 2>&1)"
seal_status=$?
if [ "$seal_status" -eq 0 ]; then
  pass
else
  fail "sealed fixture copy should exit 0 :: $seal_output"
fi
assert_present "$seal_dst/input/.gitkeep" "sealed fixture keeps tracked root input file"
assert_present "$seal_dst/input/nested/deep.txt" "sealed fixture keeps tracked deep input file"
assert_present "$seal_dst/sub/input/keep.txt" "sealed fixture keeps tracked file outside root input"
assert_present "$seal_dst/sub/input/extra.txt" "sealed fixture keeps untracked file outside root input"
assert_absent "$seal_dst/input/secret.txt" "sealed fixture excludes root input secret"
assert_absent "$seal_dst/input/nested/sibling-secret.txt" "sealed fixture excludes sibling secret"
assert_absent "$seal_dst/input/junk" "sealed fixture excludes untracked input directory"
assert_absent "$seal_dst/input/secret-link" "sealed fixture excludes untracked input symlink"

rm "$seal_src/input/.gitkeep"
ln -s secret.txt "$seal_src/input/.gitkeep"
file_symlink_output="$(copy_fixture "$seal_src" "$TMP_ROOT/seal-file-symlink-dst" 2>&1)"
file_symlink_status=$?
if [ "$file_symlink_status" -ne 0 ]; then
  pass
else
  fail "tracked input file symlink should fail closed"
fi
assert_output_contains \
  "$file_symlink_output" \
  "refusing to copy symlink in retained input path: input/.gitkeep" \
  "tracked input file symlink failure"
rm "$seal_src/input/.gitkeep"
printf 'tracked root input\n' > "$seal_src/input/.gitkeep"

mv "$seal_src/input/nested" "$seal_src/nested-target"
ln -s ../nested-target "$seal_src/input/nested"
dir_symlink_output="$(copy_fixture "$seal_src" "$TMP_ROOT/seal-dir-symlink-dst" 2>&1)"
dir_symlink_status=$?
if [ "$dir_symlink_status" -ne 0 ]; then
  pass
else
  fail "tracked input ancestor symlink should fail closed"
fi
assert_output_contains \
  "$dir_symlink_output" \
  "refusing to copy symlink in retained input path: input/nested" \
  "tracked input ancestor symlink failure"
rm "$seal_src/input/nested"
mv "$seal_src/nested-target" "$seal_src/input/nested"

mv "$seal_src/input" "$seal_src/input-target"
ln -s input-target "$seal_src/input"
input_symlink_output="$(copy_fixture "$seal_src" "$TMP_ROOT/seal-input-symlink-dst" 2>&1)"
input_symlink_status=$?
if [ "$input_symlink_status" -ne 0 ]; then
  pass
else
  fail "root input symlink should fail closed"
fi
assert_output_contains \
  "$input_symlink_output" \
  "refusing to copy symlink in retained input path: input" \
  "root input symlink failure"

plain_src="$TMP_ROOT/plain-src"
mkdir -p "$plain_src"
printf 'not a git repo\n' > "$plain_src/file.txt"
plain_output="$(copy_fixture "$plain_src" "$TMP_ROOT/plain-dst" 2>&1)"
plain_status=$?
if [ "$plain_status" -ne 0 ]; then
  pass
else
  fail "non-git fixture source should fail closed"
fi
assert_output_contains \
  "$plain_output" \
  "git ls-files failed while computing tracked input files" \
  "non-git fixture source failure"

reset_pair

write_baseline_state

printf '\nUPSTREAM SEEDED FIRST-RUN CORE EDIT\n' >> "$UPSTREAM/docs/manual.md"
printf '\nLOCAL SEEDED FIRST-RUN README EDIT\n' >> "$LOCAL/README.md"
printf '\nUPSTREAM SEEDED FIRST-RUN README EDIT\n' >> "$UPSTREAM/README.md"

seeded_first_run_output="$(cd "$LOCAL" && bash tools/update-core.sh --apply "$UPSTREAM" 2>&1)"
seeded_first_run_status=$?
if [ "$seeded_first_run_status" -eq 0 ]; then
  pass
else
  fail "seeded first-run apply should exit 0 :: $seeded_first_run_output"
fi
assert_output_contains "$seeded_first_run_output" $'changed\tdocs/manual.md' "seeded first-run upstream change status"
assert_output_contains "$seeded_first_run_output" $'user-modified\tREADME.md' "seeded first-run local edit status"
assert_output_contains "$seeded_first_run_output" "WARN: skipped user-modified README.md" "seeded first-run local edit warning"
assert_file_contains "$LOCAL/docs/manual.md" "UPSTREAM SEEDED FIRST-RUN CORE EDIT" "seeded first-run copies upstream core edit"
assert_file_contains "$LOCAL/README.md" "LOCAL SEEDED FIRST-RUN README EDIT" "seeded first-run preserves local core edit"
assert_file_not_contains "$LOCAL/README.md" "UPSTREAM SEEDED FIRST-RUN README EDIT" "seeded first-run skips conflicting upstream edit"
if STATE_ROOT="$LOCAL" STATE_REL="docs/manual.md" python3 - <<'PY'
import hashlib
import json
import os
import pathlib

root = pathlib.Path(os.environ["STATE_ROOT"])
relative_path = os.environ["STATE_REL"]
state = json.loads((root / ".update-core-state.json").read_text(encoding="utf-8"))
expected = hashlib.sha256((root / relative_path).read_bytes()).hexdigest()
actual = state.get("files", {}).get(relative_path)
raise SystemExit(0 if actual == expected else 1)
PY
then
  pass
else
  fail "seeded first-run state should record copied upstream hash"
fi

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
assert_output_contains "$first_run_output" $'unknown-ancestor\tdocs/manual.md' "first-run unknown ancestor status"
assert_output_contains "$first_run_output" "WARN: skipped unknown-ancestor docs/manual.md" "first-run unknown ancestor warning"
assert_output_contains "$first_run_output" "--adopt-ancestor <installed-version-dir>" "first-run warning explains ancestor adoption"
assert_output_contains "$first_run_output" "--force-file docs/manual.md" "first-run warning explains force-file override"
assert_file_contains "$LOCAL/docs/manual.md" "LOCAL FIRST-RUN EDIT" "first-run skip preserves local core edit"
assert_file_not_contains "$LOCAL/docs/manual.md" "UPSTREAM FIRST-RUN EDIT" "first-run skip prevents silent overwrite"

reset_pair

printf '\nUPSTREAM UNKNOWN-ANCESTOR EDIT\n' >> "$UPSTREAM/docs/manual.md"

unknown_dry_output="$(cd "$LOCAL" && bash tools/update-core.sh --dry-run "$UPSTREAM" 2>&1)"
unknown_dry_status=$?
if [ "$unknown_dry_status" -eq 0 ]; then
  pass
else
  fail "unknown-ancestor dry-run should exit 0 :: $unknown_dry_output"
fi
assert_output_contains \
  "$unknown_dry_output" \
  $'unknown-ancestor\tdocs/manual.md' \
  "state-less unchanged local file has unknown ancestor"

unknown_apply_output="$(cd "$LOCAL" && bash tools/update-core.sh --apply "$UPSTREAM" 2>&1)"
unknown_apply_status=$?
if [ "$unknown_apply_status" -eq 0 ]; then
  pass
else
  fail "unknown-ancestor apply should exit 0 while skipping :: $unknown_apply_output"
fi
assert_output_contains \
  "$unknown_apply_output" \
  "WARN: skipped unknown-ancestor docs/manual.md (no recorded ancestor;" \
  "unknown-ancestor apply explains fail-safe skip"
assert_output_contains \
  "$unknown_apply_output" \
  "--adopt-ancestor <installed-version-dir>" \
  "unknown-ancestor apply names the recovery command"
assert_file_not_contains \
  "$LOCAL/docs/manual.md" \
  "UPSTREAM UNKNOWN-ANCESTOR EDIT" \
  "unknown-ancestor apply leaves the local file unchanged"
if STATE_ROOT="$LOCAL" STATE_REL="docs/manual.md" python3 - <<'PY'
import json
import os
import pathlib

root = pathlib.Path(os.environ["STATE_ROOT"])
relative_path = os.environ["STATE_REL"]
state = json.loads((root / ".update-core-state.json").read_text(encoding="utf-8"))
raise SystemExit(0 if relative_path not in state.get("files", {}) else 1)
PY
then
  pass
else
  fail "unknown-ancestor skip should not advance the recorded ancestor"
fi

unknown_force_output="$(
  cd "$LOCAL" \
    && bash tools/update-core.sh --apply --force-file docs/manual.md "$UPSTREAM" 2>&1
)"
unknown_force_status=$?
if [ "$unknown_force_status" -eq 0 ]; then
  pass
else
  fail "forced unknown-ancestor apply should exit 0 :: $unknown_force_output"
fi
assert_file_contains \
  "$LOCAL/docs/manual.md" \
  "UPSTREAM UNKNOWN-ANCESTOR EDIT" \
  "force-file overwrites an unknown-ancestor path"
if STATE_ROOT="$LOCAL" STATE_REL="docs/manual.md" python3 - <<'PY'
import hashlib
import json
import os
import pathlib

root = pathlib.Path(os.environ["STATE_ROOT"])
relative_path = os.environ["STATE_REL"]
state = json.loads((root / ".update-core-state.json").read_text(encoding="utf-8"))
expected = hashlib.sha256((root / relative_path).read_bytes()).hexdigest()
actual = state.get("files", {}).get(relative_path)
raise SystemExit(0 if actual == expected else 1)
PY
then
  pass
else
  fail "forced unknown-ancestor apply should record the upstream hash"
fi

reset_pair
copy_fixture "$ROOT" "$ANCESTOR"
install_legacy_updater "$LOCAL" "$ANCESTOR"

printf '\nUPSTREAM BOOTSTRAP EDIT\n' >> "$UPSTREAM/docs/manual.md"

legacy_adopt_output="$(
  cd "$LOCAL" \
    && bash tools/update-core.sh --adopt-ancestor "$ANCESTOR" 2>&1
)"
legacy_adopt_status=$?
if [ "$legacy_adopt_status" -ne 0 ]; then
  pass
else
  fail "legacy updater should reject --adopt-ancestor"
fi
assert_output_contains \
  "$legacy_adopt_output" \
  "unrecognized arguments" \
  "legacy updater reproduces the bootstrap trap"

bootstrap_adopt_output="$(
  cd "$LOCAL" \
    && bash "$UPSTREAM/tools/update-core.sh" \
      --repo-root . \
      --adopt-ancestor "$ANCESTOR" 2>&1
)"
bootstrap_adopt_status=$?
if [ "$bootstrap_adopt_status" -eq 0 ]; then
  pass
else
  fail "upstream updater bootstrap adoption should exit 0 :: $bootstrap_adopt_output"
fi
assert_present \
  "$LOCAL/.update-core-state.json" \
  "upstream updater writes bootstrap state to the customer repo"
assert_absent \
  "$UPSTREAM/.update-core-state.json" \
  "upstream updater does not write bootstrap state to itself"

bootstrap_equals_output="$(
  cd "$TMP_ROOT" \
    && bash "$UPSTREAM/tools/update-core.sh" \
      --repo-root="$LOCAL" \
      --dry-run "$UPSTREAM" 2>&1
)"
bootstrap_equals_status=$?
if [ "$bootstrap_equals_status" -eq 0 ]; then
  pass
else
  fail "equals-form repo-root dry-run should exit 0 :: $bootstrap_equals_output"
fi
assert_output_contains \
  "$bootstrap_equals_output" \
  $'changed\tdocs/manual.md' \
  "equals-form repo-root targets the customer repo"

bootstrap_apply_output="$(
  cd "$LOCAL" \
    && bash "$UPSTREAM/tools/update-core.sh" \
      --repo-root . \
      --apply "$UPSTREAM" 2>&1
)"
bootstrap_apply_status=$?
if [ "$bootstrap_apply_status" -eq 0 ]; then
  pass
else
  fail "upstream updater bootstrap apply should exit 0 :: $bootstrap_apply_output"
fi
assert_output_contains \
  "$bootstrap_apply_output" \
  $'changed\tdocs/manual.md' \
  "bootstrap apply classifies the upstream manual change"
assert_file_contains \
  "$LOCAL/docs/manual.md" \
  "UPSTREAM BOOTSTRAP EDIT" \
  "bootstrap apply copies the upstream manual change"
assert_file_contains \
  "$LOCAL/tools/update-core.sh" \
  "--repo-root <dir>" \
  "bootstrap apply self-updates the legacy updater"

reset_pair
copy_fixture "$ROOT" "$ANCESTOR"

printf '\nUPSTREAM ADOPTED-ANCESTOR EDIT\n' >> "$UPSTREAM/docs/manual.md"

adopt_output="$(cd "$LOCAL" && bash tools/update-core.sh --adopt-ancestor "$ANCESTOR" 2>&1)"
adopt_status=$?
if [ "$adopt_status" -eq 0 ]; then
  pass
else
  fail "adopt-ancestor should exit 0 :: $adopt_output"
fi
assert_output_contains \
  "$adopt_output" \
  "adopted ancestor from " \
  "adopt-ancestor reports the source"
assert_output_contains \
  "$adopt_output" \
  " paths" \
  "adopt-ancestor reports the path count"

adopt_apply_output="$(cd "$LOCAL" && bash tools/update-core.sh --apply "$UPSTREAM" 2>&1)"
adopt_apply_status=$?
if [ "$adopt_apply_status" -eq 0 ]; then
  pass
else
  fail "apply after adopt-ancestor should exit 0 :: $adopt_apply_output"
fi
assert_output_contains \
  "$adopt_apply_output" \
  $'changed\tdocs/manual.md' \
  "adopted ancestor enables upstream change classification"
assert_file_contains \
  "$LOCAL/docs/manual.md" \
  "UPSTREAM ADOPTED-ANCESTOR EDIT" \
  "apply copies an upstream change after ancestor adoption"

reset_pair
copy_fixture "$ROOT" "$ANCESTOR"

printf '\nLOCAL EDIT AFTER INSTALLED VERSION\n' >> "$LOCAL/docs/manual.md"
printf '\nUPSTREAM EDIT AFTER INSTALLED VERSION\n' >> "$UPSTREAM/docs/manual.md"

adopt_modified_output="$(cd "$LOCAL" && bash tools/update-core.sh --adopt-ancestor "$ANCESTOR" 2>&1)"
adopt_modified_status=$?
if [ "$adopt_modified_status" -eq 0 ]; then
  pass
else
  fail "adopt-ancestor before a conflicting apply should exit 0 :: $adopt_modified_output"
fi

adopt_modified_apply_output="$(cd "$LOCAL" && bash tools/update-core.sh --apply "$UPSTREAM" 2>&1)"
adopt_modified_apply_status=$?
if [ "$adopt_modified_apply_status" -eq 0 ]; then
  pass
else
  fail "apply after adopting a locally modified ancestor should exit 0 :: $adopt_modified_apply_output"
fi
assert_output_contains \
  "$adopt_modified_apply_output" \
  $'user-modified\tdocs/manual.md' \
  "adopted ancestor detects a later local edit"
assert_output_contains \
  "$adopt_modified_apply_output" \
  "WARN: skipped user-modified docs/manual.md" \
  "adopted ancestor preserves the user-modified warning"
assert_file_contains \
  "$LOCAL/docs/manual.md" \
  "LOCAL EDIT AFTER INSTALLED VERSION" \
  "apply after adoption preserves the local edit"
assert_file_not_contains \
  "$LOCAL/docs/manual.md" \
  "UPSTREAM EDIT AFTER INSTALLED VERSION" \
  "apply after adoption skips the conflicting upstream edit"

reset_pair
copy_fixture "$ROOT" "$ANCESTOR"

printf '\nLOCAL CONTENT ADOPT MUST PRESERVE\n' >> "$LOCAL/docs/manual.md"
cp "$LOCAL/docs/manual.md" "$TMP_ROOT/manual-before-adopt.md"
adopt_only_output="$(cd "$LOCAL" && bash tools/update-core.sh --adopt-ancestor "$ANCESTOR" 2>&1)"
adopt_only_status=$?
if [ "$adopt_only_status" -eq 0 ]; then
  pass
else
  fail "state-only ancestor adoption should exit 0 :: $adopt_only_output"
fi
assert_files_identical \
  "$TMP_ROOT/manual-before-adopt.md" \
  "$LOCAL/docs/manual.md" \
  "adopt-ancestor does not overwrite core files"
assert_present "$LOCAL/.update-core-state.json" "adopt-ancestor creates the state file"

reset_pair
write_baseline_state
copy_fixture "$ROOT" "$ANCESTOR"

printf '\nANCESTOR MERGE REPLACEMENT\n' >> "$ANCESTOR/docs/manual.md"
rm "$ANCESTOR/README.md"
adopt_merge_output="$(cd "$LOCAL" && bash tools/update-core.sh --adopt-ancestor "$ANCESTOR" 2>&1)"
adopt_merge_status=$?
if [ "$adopt_merge_status" -eq 0 ]; then
  pass
else
  fail "adopt-ancestor should tolerate a missing manifest path :: $adopt_merge_output"
fi
if STATE_ROOT="$LOCAL" ANCESTOR_ROOT="$ANCESTOR" python3 - <<'PY'
import hashlib
import json
import os
import pathlib

state_root = pathlib.Path(os.environ["STATE_ROOT"])
ancestor_root = pathlib.Path(os.environ["ANCESTOR_ROOT"])
files = json.loads(
    (state_root / ".update-core-state.json").read_text(encoding="utf-8")
).get("files", {})
adopted_hash = hashlib.sha256((ancestor_root / "docs/manual.md").read_bytes()).hexdigest()
retained_hash = hashlib.sha256((state_root / "README.md").read_bytes()).hexdigest()
if files.get("docs/manual.md") != adopted_hash:
    raise SystemExit("adopted entry did not replace the existing state hash")
if files.get("README.md") != retained_hash:
    raise SystemExit("missing ancestor path did not retain the existing state hash")
PY
then
  pass
else
  fail "adopt-ancestor should merge over existing state and retain missing entries"
fi

missing_adopt_output="$(
  cd "$LOCAL" \
    && bash tools/update-core.sh --adopt-ancestor "$TMP_ROOT/missing-ancestor" 2>&1
)"
missing_adopt_status=$?
if [ "$missing_adopt_status" -ne 0 ]; then
  pass
else
  fail "adopt-ancestor should reject a missing directory"
fi
assert_output_contains \
  "$missing_adopt_output" \
  "FAIL: ancestor checkout is not a directory:" \
  "missing ancestor directory error"

same_root_adopt_output="$(cd "$LOCAL" && bash tools/update-core.sh --adopt-ancestor "$LOCAL" 2>&1)"
same_root_adopt_status=$?
if [ "$same_root_adopt_status" -ne 0 ]; then
  pass
else
  fail "adopt-ancestor should reject repo-root itself"
fi
assert_output_contains \
  "$same_root_adopt_output" \
  "use --generate-state for an unmodified repo" \
  "same-root ancestor error names generate-state"

combined_adopt_output="$(
  cd "$LOCAL" \
    && bash tools/update-core.sh --adopt-ancestor "$ANCESTOR" --apply 2>&1
)"
combined_adopt_status=$?
if [ "$combined_adopt_status" -ne 0 ]; then
  pass
else
  fail "adopt-ancestor should reject --apply"
fi
assert_output_contains \
  "$combined_adopt_output" \
  "--adopt-ancestor cannot be combined" \
  "adopt-ancestor and apply argument error"

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
  $'unknown-ancestor\t.gitattributes' \
  "dry-run recognizes the missing ancestor for legacy unmanaged .gitattributes"
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
  "WARN: skipped unknown-ancestor .gitattributes" \
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
