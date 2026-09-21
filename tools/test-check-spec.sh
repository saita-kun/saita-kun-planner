#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0

make_temp_dir() {
  local template="$1"
  local path status
  path="$(mktemp -d "$template")"
  status=$?
  if [ "$status" -ne 0 ] || [ -z "$path" ]; then
    printf 'ERROR: failed to create temporary directory: %s\n' "$template" >&2
    return 1
  fi
  printf '%s\n' "$path"
}

make_temp_file() {
  local template="$1"
  local path status
  path="$(mktemp "$template")"
  status=$?
  if [ "$status" -ne 0 ] || [ -z "$path" ]; then
    printf 'ERROR: failed to create temporary file: %s\n' "$template" >&2
    return 1
  fi
  printf '%s\n' "$path"
}

RELATIVE_OFFSET_TEST_DIR="$(make_temp_dir "${TMPDIR:-/tmp}/check-spec-relative-offset.XXXXXX")" || exit 1
DEPENDENCY_TEST_DIR="$(make_temp_dir "${TMPDIR:-/tmp}/check-spec-dependency.XXXXXX")" || exit 1
RESOLVE_APPLICATION_TEST_DIR="$(make_temp_dir "${TMPDIR:-/tmp}/check-spec-resolve-application.XXXXXX")" || exit 1
RESOLVED_APPLICATION_TEST_DIR=""
if ! RESOLVED_APPLICATION_TEST_DIR="$(cd "$RESOLVE_APPLICATION_TEST_DIR" && pwd)" ||
   [ -z "$RESOLVED_APPLICATION_TEST_DIR" ]; then
  printf 'ERROR: failed to resolve temporary directory: %s\n' "$RESOLVE_APPLICATION_TEST_DIR" >&2
  exit 1
fi
RESOLVE_APPLICATION_TEST_DIR="$RESOLVED_APPLICATION_TEST_DIR"
unset RESOLVED_APPLICATION_TEST_DIR
ISOLATED_RESOLVER_ROOT="$RESOLVE_APPLICATION_TEST_DIR/isolated-root"
INPUT_SPEC_RESOLVER_ROOT="$RESOLVE_APPLICATION_TEST_DIR/input-spec-root"
CURRENT_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/current-application.XXXXXX")" || exit 1
STALE_CURRENT_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/stale-current-application.XXXXXX")" || exit 1
INVALID_CURRENT_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/invalid-current-application.XXXXXX")" || exit 1
NON_OBJECT_CURRENT_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/non-object-current-application.XXXXXX")" || exit 1
NULL_PREDICATE_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/null-predicate-application.XXXXXX")" || exit 1
UNBOUND_PREDICATE_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/unbound-predicate-application.XXXXXX")" || exit 1
LEADING_HYPHEN_PREDICATE_SPEC_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/leading-hyphen-predicate-spec.XXXXXX")" || exit 1
BOOL_SPEC_VERSION_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/bool-spec-version-application.XXXXXX")" || exit 1
STRING_SPEC_VERSION_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/string-spec-version-application.XXXXXX")" || exit 1
NUMERIC_SUBSIDY_ID_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/numeric-subsidy-id-application.XXXXXX")" || exit 1
VALID_BINDING_APPLICATION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/valid-binding-application.XXXXXX")" || exit 1
INVALID_SPEC_SUBSIDY_ID_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/invalid-spec-subsidy-id.XXXXXX")" || exit 1
INVALID_SPEC_VERSION_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/invalid-spec-version.XXXXXX")" || exit 1
PREDICATE_KEYS_MERGE_SPEC_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/predicate-keys-merge.XXXXXX")" || exit 1
UNDECLARED_PROFILE_KEY_SPEC_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/undeclared-profile-key.XXXXXX")" || exit 1
PREDICATE_KEYS_OUTPUT_A="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/predicate-keys-output-a.XXXXXX")" || exit 1
PREDICATE_KEYS_OUTPUT_B="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/predicate-keys-output-b.XXXXXX")" || exit 1
RESOLVE_STDOUT_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/stdout.XXXXXX")" || exit 1
RESOLVE_STDERR_FILE="$(make_temp_file "$RESOLVE_APPLICATION_TEST_DIR/stderr.XXXXXX")" || exit 1
MISSING_CURRENT_APPLICATION_FILE="$RESOLVE_APPLICATION_TEST_DIR/missing-current-application.json"

printf '%s\n' \
  '{"subsidy_id":"jizokuka-20","spec_path":"specs/jizokuka-20/jizokuka-20.json"}' \
  > "$CURRENT_APPLICATION_FILE"
printf '%s\n' \
  '{"subsidy_id":"jizokuka-20","spec_path":"specs/jizokuka-20.json"}' \
  > "$STALE_CURRENT_APPLICATION_FILE"
printf '%s\n' '{not-json' > "$INVALID_CURRENT_APPLICATION_FILE"
printf '%s\n' '[]' > "$NON_OBJECT_CURRENT_APPLICATION_FILE"
printf '%s\n' \
  '{"subsidy_id":"predicate-application-scope","spec_version":1,"chosen_funding":null}' \
  > "$NULL_PREDICATE_APPLICATION_FILE"
printf '%s\n' \
  '{"chosen_funding":{"base":true,"addon_ids":["wage-up"]}}' \
  > "$UNBOUND_PREDICATE_APPLICATION_FILE"
printf '%s\n' \
  '{"subsidy_id":"leading-hyphen-rules","spec_version":1,"eligibility":{"rules":[{"rule_id":"-leading-rule","predicate":{"scope":"profile","key":"employees","op":"eq","value":5}},{"rule_id":"-h","predicate":{"scope":"profile","key":"employees","op":"eq","value":5}},{"rule_id":"--current-application","predicate":{"scope":"profile","key":"employees","op":"eq","value":5}}]}}' \
  > "$LEADING_HYPHEN_PREDICATE_SPEC_FILE"
printf '%s\n' \
  '{"subsidy_id":"leading-hyphen-rules","spec_version":true}' \
  > "$BOOL_SPEC_VERSION_APPLICATION_FILE"
printf '%s\n' \
  '{"subsidy_id":"leading-hyphen-rules","spec_version":"1"}' \
  > "$STRING_SPEC_VERSION_APPLICATION_FILE"
printf '%s\n' \
  '{"subsidy_id":42,"spec_version":1}' \
  > "$NUMERIC_SUBSIDY_ID_APPLICATION_FILE"
printf '%s\n' \
  '{"subsidy_id":"leading-hyphen-rules","spec_version":1}' \
  > "$VALID_BINDING_APPLICATION_FILE"
printf '%s\n' \
  '{"subsidy_id":42,"spec_version":1,"eligibility":{"rules":[{"rule_id":"-leading-rule","predicate":{"scope":"profile","key":"employees","op":"eq","value":5}}]}}' \
  > "$INVALID_SPEC_SUBSIDY_ID_FILE"
printf '%s\n' \
  '{"subsidy_id":"leading-hyphen-rules","spec_version":true,"eligibility":{"rules":[{"rule_id":"-leading-rule","predicate":{"scope":"profile","key":"employees","op":"eq","value":5}}]}}' \
  > "$INVALID_SPEC_VERSION_FILE"
printf '%s\n' \
  '{"subsidy_id":"predicate-keys-merge","spec_version":1,"eligibility":{"rules":[{"rule_id":"rule-z","predicate":{"all":[{"scope":"profile","key":"employees","op":"exists"}]}},{"rule_id":"rule-a","predicate":{"not":{"scope":"profile","key":"employees","op":"eq","value":0}}}]},"deliverables":[{"deliverable_id":"employee-plan","required_if":{"scope":"profile","key":"employees","op":"exists"}}]}' \
  > "$PREDICATE_KEYS_MERGE_SPEC_FILE"
python3 - \
  "tools/fixtures/spec/good-spec.json" \
  "$UNDECLARED_PROFILE_KEY_SPEC_FILE" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
spec["status"] = "draft"
spec["eligibility"]["rules"][0]["predicate"] = {
    "scope": "profile",
    "key": "custom_metrics.score",
    "op": "gte",
    "value": 1,
}
output_path.write_text(
    json.dumps(spec, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

copy_resolver_test_root() {
  local destination="$1"
  mkdir -p "$destination/tools"
  cp -R tools/check-spec.sh tools/lib "$destination/tools/"
  cp -R specs "$destination/"
}

copy_resolver_test_root "$ISOLATED_RESOLVER_ROOT"
copy_resolver_test_root "$INPUT_SPEC_RESOLVER_ROOT"
mkdir -p "$INPUT_SPEC_RESOLVER_ROOT/input/spec"
cp -R specs/jizokuka-20 "$INPUT_SPEC_RESOLVER_ROOT/input/spec/"

cleanup() {
  local target
  for target in "${RELATIVE_OFFSET_TEST_DIR:-}" "${DEPENDENCY_TEST_DIR:-}" "${RESOLVE_APPLICATION_TEST_DIR:-}"; do
    case "$target" in
      ""|/|"$ROOT")
        continue
        ;;
    esac
    rm -rf -- "$target"
  done
}
trap cleanup EXIT

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

run_repo_check_spec() {
  bash tools/check-spec.sh "$@"
}

run_isolated_check_spec() {
  bash "$ISOLATED_RESOLVER_ROOT/tools/check-spec.sh" "$@"
}

run_input_spec_check_spec() {
  bash "$INPUT_SPEC_RESOLVER_ROOT/tools/check-spec.sh" "$@"
}

assert_check_spec_passes() {
  local path="$1"
  shift
  local output
  if output=$(bash tools/check-spec.sh "$path" "$@" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^OK:' && printf '%s\n' "$output" | grep -q '^READINESS:'; then
      pass
    else
      fail "check-spec passing output should include OK and READINESS: $path :: $output"
    fi
  else
    fail "check-spec should pass: $path :: $output"
  fi
}

assert_check_spec_passes_with() {
  local path="$1" expected="$2"
  shift 2
  local output
  if output=$(bash tools/check-spec.sh "$path" "$@" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^OK:' && printf '%s\n' "$output" | grep -qF -- "$expected"; then
      pass
    else
      fail "check-spec passing output for $path should include: $expected :: $output"
    fi
  else
    fail "check-spec should pass: $path :: $output"
  fi
}

assert_check_spec_passes_without() {
  local path="$1" unexpected="$2"
  shift 2
  local output
  if output=$(bash tools/check-spec.sh "$path" "$@" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^OK:' &&
       printf '%s\n' "$output" | grep -q '^READINESS:' &&
       ! printf '%s\n' "$output" | grep -qF -- "$unexpected"; then
      pass
    else
      fail "check-spec passing output for $path should not include: $unexpected :: $output"
    fi
  else
    fail "check-spec should pass: $path :: $output"
  fi
}

assert_check_spec_fails_with() {
  local path="$1" expected="$2"
  shift 2
  local output status
  output=$(bash tools/check-spec.sh "$path" "$@" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "check-spec should fail: $path"
    return
  fi
  if printf '%s\n' "$output" | grep -qF -- "$expected"; then
    pass
  else
    fail "check-spec failure for $path should include: $expected :: $output"
  fi
}

assert_tane03_dependency_case() {
  local due="$1" dependencies="$2" expected_status="$3" expected="$4"
  local output status
  if ! python3 - "$DEPENDENCY_TEST_DIR" "$due" "$dependencies" <<'PY'
import copy
import hashlib
import json
import pathlib
import sys

output_dir = pathlib.Path(sys.argv[1])
spec_path = output_dir / "dependency.json"
spec = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.json").read_text(encoding="utf-8"))
confirmation = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.confirmation.json").read_text(encoding="utf-8"))
reference = copy.deepcopy(spec["deliverables"][0])
reference.update(deliverable_id="deliverable-2", sections=[])
spec["deliverables"].append(reference)
deliverable = spec["deliverables"][0]
if sys.argv[2] == "unset":
    deliverable.pop("due_event_id")
else:
    deliverable["due_event_id"] = json.loads(sys.argv[2])
if sys.argv[3] == "unset":
    deliverable.pop("depends_on")
else:
    deliverable["depends_on"] = json.loads(sys.argv[3])
confirmation["items"].append({
    "field_path": "deliverables.deliverable-2",
    "source_clauses": reference["source_clauses"],
    "state": "confirmed",
    "note": "Fixture confirmation for the referenced deliverable.",
})
spec_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
confirmation["spec_path"] = spec_path.as_posix()
confirmation["spec_sha256"] = hashlib.sha256(spec_path.read_bytes()).hexdigest()
spec_path.with_suffix(".confirmation.json").write_text(
    json.dumps(confirmation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
)
PY
  then
    fail "dependency fixture creation failed"
    return
  fi
  output=$(bash tools/check-spec.sh "$DEPENDENCY_TEST_DIR/dependency.json" 2>&1)
  status=$?
  if [ "$status" -eq "$expected_status" ] && printf '%s\n' "$output" | grep -qF -- "$expected"; then
    pass
  else
    fail "dependency case due=$due depends_on=$dependencies expected status=$expected_status and '$expected' :: status=$status $output"
  fi
}

test_tane03_missing_dependency_without_due() {
  local due
  for due in null unset; do
    assert_tane03_dependency_case "$due" '["missing-id"]' 1 \
      'unknown depends_on reference: $.deliverables[0].depends_on[0]=missing-id'
  done
}

test_tane03_valid_dependency_without_due() {
  local due
  for due in null unset; do
    assert_tane03_dependency_case "$due" '["deliverable-2"]' 0 'OK:'
    assert_tane03_dependency_case "$due" '[]' 0 'OK:'
    assert_tane03_dependency_case "$due" 'unset' 0 'OK:'
  done
}

test_tane03_dependency_types() {
  local due
  for due in null unset; do
    assert_tane03_dependency_case "$due" '"deliverable-2"' 1 '$.deliverables[0].depends_on must be an array'
    assert_tane03_dependency_case "$due" 'null' 1 '$.deliverables[0].depends_on must be an array'
    assert_tane03_dependency_case "$due" '[42]' 1 '$.deliverables[0].depends_on[0] must be a string'
  done
}

assert_deadline_case() {
  local path="$1" now="$2" expected_gate="$3" expected_warn="$4"
  local output check_status gate_output gate_status
  local warn_text="WARN: application deadline"
  local gate_text="FAIL: 有効な申請締切が残っていません; 公募回が更新されていないか公式サイトで確認してください"

  output=$(bash tools/check-spec.sh "$path" --now "$now" 2>&1)
  check_status=$?
  if [ "$check_status" -ne 0 ]; then
    fail "deadline WARN evaluation should not fail: $path at $now :: $output"
  elif [ "$expected_warn" = "warn" ] && printf '%s\n' "$output" | grep -qF -- "$warn_text"; then
    pass
  elif [ "$expected_warn" = "none" ] && ! printf '%s\n' "$output" | grep -qF -- "$warn_text"; then
    pass
  else
    fail "deadline WARN mismatch: $path at $now expected $expected_warn :: $output"
  fi

  gate_output=$(bash tools/check-spec.sh "$path" --gate select --now "$now" 2>&1)
  gate_status=$?
  if [ "$expected_gate" = "pass" ] &&
     [ "$gate_status" -eq 0 ] &&
     printf '%s\n' "$gate_output" | grep -q '^OK:'; then
    pass
  elif [ "$expected_gate" = "fail" ] &&
       [ "$gate_status" -ne 0 ] &&
       printf '%s\n' "$gate_output" | grep -qF -- "$gate_text" &&
       ! printf '%s\n' "$gate_output" | grep -qE '入口A|入口B'; then
    pass
  else
    fail "deadline select gate mismatch: $path at $now expected $expected_gate :: $gate_output"
  fi
}

assert_list_bundled_exact() {
  local bundled_root="$1" expected="$2"
  local output
  if output=$(bash tools/check-spec.sh --list-bundled --bundled-root "$bundled_root" 2>&1); then
    if [ "$output" = "$expected" ]; then
      pass
    else
      fail "--list-bundled output mismatch for $bundled_root :: $output"
    fi
  else
    fail "--list-bundled should pass for $bundled_root :: $output"
  fi
}

assert_list_bundled_fails_with() {
  local bundled_root="$1" expected="$2"
  local output list_status
  output=$(bash tools/check-spec.sh --list-bundled --bundled-root "$bundled_root" 2>&1)
  list_status=$?
  if [ "$list_status" -ne 0 ] && printf '%s\n' "$output" | grep -qF -- "$expected"; then
    pass
  else
    fail "--list-bundled should fail for $bundled_root with $expected :: $output"
  fi
}

assert_predicate_keys_entry() {
  local path="$1" scope="$2" key="$3" expected_declared="$4" expected_unit="$5" expected_phase="$6"
  local output stderr_output status
  bash tools/check-spec.sh "$path" --list-predicate-keys \
    >"$RESOLVE_STDOUT_FILE" 2>"$RESOLVE_STDERR_FILE"
  status=$?
  output="$(<"$RESOLVE_STDOUT_FILE")"
  stderr_output="$(<"$RESOLVE_STDERR_FILE")"
  if [ "$status" -ne 0 ] || [ -n "$stderr_output" ]; then
    fail "--list-predicate-keys should return JSON for $path :: status=$status stdout=$output stderr=$stderr_output"
    return
  fi
  if python3 - \
    "$RESOLVE_STDOUT_FILE" \
    "$scope" \
    "$key" \
    "$expected_declared" \
    "$expected_unit" \
    "$expected_phase" <<'PY'
import json
import pathlib
import sys

output_path = pathlib.Path(sys.argv[1])
scope, key, raw_declared, raw_unit, expected_phase = sys.argv[2:7]
data = json.loads(output_path.read_text(encoding="utf-8"))
expected_declared = {"true": True, "false": False, "null": None}[raw_declared]
expected_unit = None if raw_unit == "null" else raw_unit
matches = [
    entry
    for entry in data["keys"]
    if entry.get("scope") == scope and entry.get("key") == key
]
assert len(matches) == 1
entry = matches[0]
assert entry["root_key"] == key.split(".", 1)[0]
assert entry["declared"] is expected_declared
assert entry["unit"] == expected_unit
assert expected_phase in entry["confirm_phase"]
if scope == "profile" and key == "employees":
    assert entry["type"] == ["integer", "null"]
    assert entry["description"] == "常時使用する従業員数"
if scope == "application":
    assert entry["type"] is None
    assert entry["description"] is None
PY
  then
    pass
  else
    fail "--list-predicate-keys entry mismatch for $scope.$key in $path :: $output"
  fi
}

assert_predicate_keys_merged() {
  local path="$1"
  local output stderr_output status
  bash tools/check-spec.sh "$path" --list-predicate-keys \
    >"$RESOLVE_STDOUT_FILE" 2>"$RESOLVE_STDERR_FILE"
  status=$?
  output="$(<"$RESOLVE_STDOUT_FILE")"
  stderr_output="$(<"$RESOLVE_STDERR_FILE")"
  if [ "$status" -ne 0 ] || [ -n "$stderr_output" ]; then
    fail "--list-predicate-keys merge fixture should pass :: status=$status stdout=$output stderr=$stderr_output"
    return
  fi
  if python3 - "$RESOLVE_STDOUT_FILE" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert len(data["keys"]) == 1
entry = data["keys"][0]
assert entry["scope"] == "profile"
assert entry["key"] == "employees"
assert entry["referenced_by"] == [
    "deliverables.employee-plan.required_if",
    "eligibility.rules.rule-a",
    "eligibility.rules.rule-z",
]
assert entry["confirm_phase"] == ["intake", "plan-deliverables"]
PY
  then
    pass
  else
    fail "--list-predicate-keys should merge duplicate references :: $output"
  fi
}

assert_predicate_keys_stable() {
  local path="$1"
  local first_stderr second_stderr first_status second_status
  bash tools/check-spec.sh "$path" --list-predicate-keys \
    >"$PREDICATE_KEYS_OUTPUT_A" 2>"$RESOLVE_STDERR_FILE"
  first_status=$?
  first_stderr="$(<"$RESOLVE_STDERR_FILE")"
  bash tools/check-spec.sh "$path" --list-predicate-keys \
    >"$PREDICATE_KEYS_OUTPUT_B" 2>"$RESOLVE_STDERR_FILE"
  second_status=$?
  second_stderr="$(<"$RESOLVE_STDERR_FILE")"
  if [ "$first_status" -eq 0 ] &&
     [ "$second_status" -eq 0 ] &&
     [ -z "$first_stderr" ] &&
     [ -z "$second_stderr" ] &&
     cmp -s "$PREDICATE_KEYS_OUTPUT_A" "$PREDICATE_KEYS_OUTPUT_B" &&
     python3 - "$PREDICATE_KEYS_OUTPUT_A" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
pairs = [(entry["scope"], entry["key"]) for entry in data["keys"]]
assert pairs == sorted(pairs)
for entry in data["keys"]:
    assert entry["referenced_by"] == sorted(entry["referenced_by"])
    assert entry["confirm_phase"] == sorted(entry["confirm_phase"])
PY
  then
    pass
  else
    fail "--list-predicate-keys output should be stable and sorted for $path"
  fi
}

assert_predicate_keys_schema_unavailable() {
  local spec_path="$ISOLATED_RESOLVER_ROOT/specs/jizokuka-20/jizokuka-20.json"
  local output stderr_output status
  run_isolated_check_spec "$spec_path" --list-predicate-keys \
    >"$RESOLVE_STDOUT_FILE" 2>"$RESOLVE_STDERR_FILE"
  status=$?
  output="$(<"$RESOLVE_STDOUT_FILE")"
  stderr_output="$(<"$RESOLVE_STDERR_FILE")"
  if [ "$status" -ne 0 ] || [ -n "$stderr_output" ]; then
    fail "--list-predicate-keys should tolerate an unavailable profile schema :: status=$status stdout=$output stderr=$stderr_output"
    return
  fi
  if python3 - "$RESOLVE_STDOUT_FILE" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
entry = next(
    item
    for item in data["keys"]
    if item["scope"] == "profile" and item["key"] == "employees"
)
assert entry["declared"] is None
assert entry["type"] is None
assert entry["unit"] is None
assert entry["description"] is None
PY
  then
    pass
  else
    fail "--list-predicate-keys should emit null schema metadata when the schema is unavailable :: $output"
  fi
}

assert_resolve_application_exact_with_runner() {
  local runner="$1" expected="$2"
  shift 2
  local output stderr_output line_count status
  "$runner" --resolve-application "$@" \
    >"$RESOLVE_STDOUT_FILE" 2>"$RESOLVE_STDERR_FILE"
  status=$?
  output="$(<"$RESOLVE_STDOUT_FILE")"
  stderr_output="$(<"$RESOLVE_STDERR_FILE")"
  line_count="$(wc -l < "$RESOLVE_STDOUT_FILE" | tr -d ' ')"
  if [ "$status" -eq 0 ] &&
     [ "$output" = "$expected" ] &&
     [ "$line_count" -eq 1 ] &&
     [ -z "$stderr_output" ]; then
    pass
  else
    fail "--resolve-application output mismatch via $runner: expected one line '$expected' :: status=$status stdout=$output stderr=$stderr_output"
  fi
}

assert_resolve_application_exact() {
  local expected="$1"
  shift
  assert_resolve_application_exact_with_runner \
    run_isolated_check_spec \
    "$expected" \
    "$@"
}

assert_resolve_application_stale() {
  local expected="$1" expected_info="$2"
  shift 2
  local output stderr_output line_count status
  run_isolated_check_spec --resolve-application "$@" \
    >"$RESOLVE_STDOUT_FILE" 2>"$RESOLVE_STDERR_FILE"
  status=$?
  output="$(<"$RESOLVE_STDOUT_FILE")"
  stderr_output="$(<"$RESOLVE_STDERR_FILE")"
  line_count="$(wc -l < "$RESOLVE_STDOUT_FILE" | tr -d ' ')"
  if [ "$status" -eq 0 ] &&
     [ "$output" = "$expected" ] &&
     [ "$line_count" -eq 1 ] &&
     ! grep -qF -- "INFO:" "$RESOLVE_STDOUT_FILE" &&
     printf '%s\n' "$stderr_output" | grep -qF -- "$expected_info"; then
    pass
  else
    fail "stale --resolve-application output mismatch :: status=$status stdout=$output stderr=$stderr_output"
  fi
}

assert_check_spec_cli_fails_with_runner() {
  local runner="$1" expected="$2"
  shift 2
  local output stderr_output status
  "$runner" "$@" >"$RESOLVE_STDOUT_FILE" 2>"$RESOLVE_STDERR_FILE"
  status=$?
  output="$(<"$RESOLVE_STDOUT_FILE")"
  stderr_output="$(<"$RESOLVE_STDERR_FILE")"
  if [ "$status" -ne 0 ] &&
     [ -z "$output" ] &&
     printf '%s\n' "$stderr_output" | grep -qF -- "$expected"; then
    pass
  else
    fail "check-spec CLI via $runner should fail with '$expected' and empty stdout :: status=$status stdout=$output stderr=$stderr_output"
  fi
}

assert_check_spec_cli_fails_with() {
  local expected="$1"
  shift
  assert_check_spec_cli_fails_with_runner run_repo_check_spec "$expected" "$@"
}

assert_isolated_check_spec_cli_fails_with() {
  local expected="$1"
  shift
  assert_check_spec_cli_fails_with_runner run_isolated_check_spec "$expected" "$@"
}

assert_freshness_records_fail_with() {
  local bundled_root="$1" expected="$2"
  local output status
  output=$(python3 - "$bundled_root" <<'PY' 2>&1
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("tools/lib").resolve()))
import check_trust_freshness

try:
    check_trust_freshness.provider_pack_records(pathlib.Path(sys.argv[1]), pathlib.Path("."))
except check_trust_freshness.ValidationError as exc:
    print(exc)
    raise SystemExit(1)
raise SystemExit("freshness records unexpectedly accepted the negative fixture")
PY
)
  status=$?
  if [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -qF -- "$expected"; then
    pass
  else
    fail "freshness records should fail for $bundled_root with $expected :: $output"
  fi
}

assert_check_spec_gate_passes() {
  local path="$1"
  local output
  if output=$(bash tools/check-spec.sh "$path" --gate confirm 2>&1); then
    if printf '%s\n' "$output" | grep -q '^OK:' && printf '%s\n' "$output" | grep -q '^READINESS:'; then
      pass
    else
      fail "check-spec --gate confirm passing output should include OK and READINESS: $path :: $output"
    fi
  else
    fail "check-spec --gate confirm should pass: $path :: $output"
  fi
}

assert_check_spec_gate_fails_with() {
  local path="$1" expected="$2"
  local output status
  output=$(bash tools/check-spec.sh "$path" --gate confirm 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "check-spec --gate confirm should fail: $path"
    return
  fi
  if printf '%s\n' "$output" | grep -qF -- "$expected"; then
    pass
  else
    fail "check-spec --gate confirm failure for $path should include: $expected :: $output"
  fi
}

assert_predicate_rule() {
  local spec="$1" rule_id="$2" profile="$3" expected="$4"
  local output status
  output=$(python3 tools/lib/predicate.py "$spec" "$rule_id" "$profile" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    fail "predicate CLI failed for $spec $rule_id $profile :: $output"
    return
  fi
  if [ "$output" = "$expected" ]; then
    pass
  else
    fail "predicate result for $spec $rule_id $profile: expected $expected, got $output"
  fi
}

assert_predicate_with_application() {
  local spec="$1" rule_id="$2" profile="$3" application="$4" expected="$5"
  local output status
  output=$(python3 tools/lib/predicate.py \
    "$spec" "$rule_id" "$profile" \
    --current-application "$application" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    fail "predicate CLI failed for $spec $rule_id $profile with $application :: $output"
    return
  fi
  if [ "$output" = "$expected" ]; then
    pass
  else
    fail "predicate result for $spec $rule_id $profile with $application: expected $expected, got $output"
  fi
}

assert_predicate_cli_fails_with() {
  local expected="$1"
  shift
  local output stderr_output status
  python3 tools/lib/predicate.py "$@" \
    >"$RESOLVE_STDOUT_FILE" 2>"$RESOLVE_STDERR_FILE"
  status=$?
  output="$(<"$RESOLVE_STDOUT_FILE")"
  stderr_output="$(<"$RESOLVE_STDERR_FILE")"
  if [ "$status" -ne 0 ] &&
     [ -z "$output" ] &&
     printf '%s\n' "$stderr_output" | grep -qF -- "$expected"; then
    pass
  else
    fail "predicate CLI should fail with '$expected' and empty stdout :: status=$status stdout=$output stderr=$stderr_output"
  fi
}

assert_predicate() {
  local profile="$1" expected="$2"
  assert_predicate_rule "specs/jizokuka-20/jizokuka-20.json" "size-limit" "$profile" "$expected"
}

# Fixed --now values make the deadline assertions deterministic. This removes
# the post-2026 expiry failure without weakening any structural check.
assert_check_spec_passes \
  "tools/fixtures/spec/good-spec.json" \
  --now "2026-12-30T12:00:00+09:00"
assert_check_spec_passes_without \
  "tools/fixtures/spec/good-spec.json" \
  "application deadline" \
  --now "2026-12-30T12:00:00+09:00"
assert_check_spec_passes_with \
  "tools/fixtures/spec/stale-deadline.json" \
  "WARN: application deadline 2020-01-01 has passed; 公募回が更新されていないか公式サイトで確認してください" \
  --now "2026-07-17T12:00:00+09:00"
assert_check_spec_passes \
  "specs/jizokuka-20/jizokuka-20.json" \
  --now "2026-07-17T12:00:00+09:00"

assert_deadline_case \
  "tools/fixtures/spec/deadline-past.json" \
  "2026-12-15T12:00:00+09:00" fail warn
assert_deadline_case \
  "tools/fixtures/spec/deadline-start-past-future.json" \
  "2026-12-15T12:00:00+09:00" pass none
assert_deadline_case \
  "tools/fixtures/spec/deadline-multiple-partial.json" \
  "2026-12-15T12:00:00+09:00" pass warn
assert_deadline_case \
  "tools/fixtures/spec/deadline-date-only.json" \
  "2026-12-15T23:59:59+09:00" pass none
assert_deadline_case \
  "tools/fixtures/spec/deadline-date-only.json" \
  "2026-12-16T00:00:00+09:00" fail warn
assert_deadline_case \
  "tools/fixtures/spec/deadline-time.json" \
  "2026-12-15T16:59:59+09:00" pass none
assert_deadline_case \
  "tools/fixtures/spec/deadline-time.json" \
  "2026-12-15T17:00:00+09:00" pass none
assert_deadline_case \
  "tools/fixtures/spec/deadline-time.json" \
  "2026-12-15T17:00:01+09:00" fail warn

assert_list_bundled_exact \
  "specs" \
  "specs/jizokuka-20/jizokuka-20.json"
assert_list_bundled_exact \
  "tools/fixtures/bundled-resolver/stable-order" \
  $'tools/fixtures/bundled-resolver/stable-order/alpha.json\ntools/fixtures/bundled-resolver/stable-order/zeta.json'
assert_list_bundled_exact \
  "tools/fixtures/bundled-resolver/pack-flat-conflict" \
  "tools/fixtures/bundled-resolver/pack-flat-conflict/canonical/resolver-conflict-pack.json"
assert_list_bundled_fails_with \
  "tools/fixtures/bundled-resolver/flat-duplicate" \
  "duplicate bundled subsidy_id in flat specs: resolver-flat-duplicate"
assert_list_bundled_fails_with \
  "tools/fixtures/bundled-resolver/pack-duplicate" \
  "duplicate bundled subsidy_id in pack specs: resolver-pack-duplicate"

assert_predicate_keys_entry \
  "specs/jizokuka-20/jizokuka-20.json" \
  "profile" \
  "employees" \
  "true" \
  "人" \
  "intake"
assert_predicate_keys_entry \
  "examples/worked-example/pack/spec.sample.json" \
  "application" \
  "chosen_funding.addon_ids" \
  "null" \
  "null" \
  "plan-deliverables"
assert_predicate_keys_merged "$PREDICATE_KEYS_MERGE_SPEC_FILE"
assert_predicate_keys_stable "specs/jizokuka-20/jizokuka-20.json"
assert_predicate_keys_entry \
  "$UNDECLARED_PROFILE_KEY_SPEC_FILE" \
  "profile" \
  "custom_metrics.score" \
  "false" \
  "null" \
  "intake"
assert_predicate_keys_schema_unavailable
assert_check_spec_cli_fails_with \
  "--list-predicate-keys cannot be combined" \
  specs/jizokuka-20/jizokuka-20.json \
  --list-predicate-keys \
  --gate confirm
assert_check_spec_cli_fails_with \
  "--list-predicate-keys cannot be combined" \
  specs/jizokuka-20/jizokuka-20.json \
  --list-predicate-keys \
  --list-bundled
assert_check_spec_cli_fails_with \
  "a spec path is required with --list-predicate-keys" \
  --list-predicate-keys
assert_check_spec_fails_with \
  "$INVALID_CURRENT_APPLICATION_FILE" \
  "FAIL: spec invalid JSON" \
  --list-predicate-keys
assert_check_spec_passes_with \
  "$UNDECLARED_PROFILE_KEY_SPEC_FILE" \
  "WARN: predicate references undeclared profile key: custom_metrics.score (eligibility.rules.rule-1)" \
  --now "2026-12-30T12:00:00+09:00"
assert_check_spec_passes_without \
  "specs/jizokuka-20/jizokuka-20.json" \
  "predicate references undeclared profile key" \
  --now "2026-07-17T12:00:00+09:00"
assert_check_spec_passes_without \
  "examples/worked-example/pack/spec.sample.json" \
  "predicate references undeclared profile key" \
  --now "2026-07-17T12:00:00+09:00"

assert_resolve_application_exact \
  "specs/jizokuka-20/jizokuka-20.json" \
  --subsidy-id="jizokuka-20" \
  --no-current-application
assert_isolated_check_spec_cli_fails_with \
  "FAIL: spec not found for subsidy_id: does-not-exist" \
  --resolve-application \
  --subsidy-id="does-not-exist" \
  --no-current-application
assert_resolve_application_exact \
  "specs/jizokuka-20/jizokuka-20.json" \
  --current-application "$CURRENT_APPLICATION_FILE"
assert_resolve_application_stale \
  "specs/jizokuka-20/jizokuka-20.json" \
  "INFO: resolved canonical spec specs/jizokuka-20/jizokuka-20.json instead of stale entry specs/jizokuka-20.json" \
  --current-application "$STALE_CURRENT_APPLICATION_FILE"
assert_resolve_application_exact_with_runner \
  run_input_spec_check_spec \
  "input/spec/jizokuka-20/jizokuka-20.json" \
  --subsidy-id="jizokuka-20" \
  --no-current-application
assert_check_spec_cli_fails_with \
  "FAIL: --subsidy-id mismatch with current application: --subsidy-id='other-id', current application subsidy_id='jizokuka-20'" \
  --resolve-application \
  --subsidy-id="other-id" \
  --current-application "$CURRENT_APPLICATION_FILE"
assert_check_spec_cli_fails_with \
  "FAIL: current application not found" \
  --resolve-application \
  --current-application "$MISSING_CURRENT_APPLICATION_FILE"
assert_check_spec_cli_fails_with \
  "FAIL: current application invalid JSON" \
  --resolve-application \
  --current-application "$INVALID_CURRENT_APPLICATION_FILE"
assert_check_spec_cli_fails_with \
  "FAIL: current application root must be an object" \
  --resolve-application \
  --current-application "$NON_OBJECT_CURRENT_APPLICATION_FILE"
assert_check_spec_cli_fails_with \
  "FAIL: subsidy_id is required; pass --subsidy-id <id>" \
  --resolve-application \
  --no-current-application
assert_check_spec_cli_fails_with \
  "--resolve-application cannot be combined" \
  --resolve-application \
  --list-bundled
assert_check_spec_cli_fails_with \
  "require --resolve-application" \
  --subsidy-id="x"
assert_check_spec_cli_fails_with \
  "not allowed with argument --current-application" \
  --resolve-application \
  --current-application "$CURRENT_APPLICATION_FILE" \
  --no-current-application
assert_check_spec_cli_fails_with \
  "--resolve-application cannot be combined" \
  specs/jizokuka-20/jizokuka-20.json \
  --resolve-application \
  --no-current-application
assert_check_spec_cli_fails_with \
  "--resolve-application cannot be combined" \
  --resolve-application \
  --subsidy-id="jizokuka-20" \
  --no-current-application \
  --gate confirm
assert_check_spec_cli_fails_with \
  "--resolve-application cannot be combined" \
  --resolve-application \
  --subsidy-id="jizokuka-20" \
  --no-current-application \
  --now 2026-07-17T12:00:00+09:00
assert_check_spec_cli_fails_with \
  "--resolve-application cannot be combined" \
  --resolve-application \
  --subsidy-id="jizokuka-20" \
  --no-current-application \
  --bundled-root specs
assert_check_spec_cli_fails_with \
  "require --resolve-application" \
  --current-application "$CURRENT_APPLICATION_FILE"
assert_check_spec_cli_fails_with \
  "require --resolve-application" \
  --no-current-application
assert_freshness_records_fail_with \
  "tools/fixtures/trust-freshness/stale-spec-sha" \
  "confirmation spec_sha256 mismatch"

assert_check_spec_fails_with \
  "tools/fixtures/spec/provider-null-round.json" \
  "provider confirmation requires spec.round to be non-null" \
  --now "2026-07-17T12:00:00+09:00"
assert_check_spec_fails_with \
  "tools/fixtures/spec/provider-null-portal-url.json" \
  "provider confirmation requires spec.portal_url to be non-null" \
  --now "2026-07-17T12:00:00+09:00"
assert_check_spec_fails_with \
  "tools/fixtures/spec/provider-missing-item-confirmed-at.json" \
  "provider confirmation requires an ISO date: confirmation.items[0].confirmed_at" \
  --now "2026-07-17T12:00:00+09:00"
assert_check_spec_fails_with \
  "tools/fixtures/spec/provider-invalid-item-confirmed-at.json" \
  "provider confirmation requires a valid ISO date: confirmation.items[0].confirmed_at='2026-13-99'" \
  --now "2026-07-17T12:00:00+09:00"
assert_check_spec_passes \
  "tools/fixtures/spec/provider-customer-null-boundary.json" \
  --now "2026-07-17T12:00:00+09:00"

assert_check_spec_passes "tools/fixtures/spec/predicate-kleene.json"
assert_check_spec_passes "tools/fixtures/spec/predicate-type-mismatch.json"
assert_check_spec_passes "tools/fixtures/spec/predicate-application-scope.json"
assert_check_spec_passes "tools/fixtures/spec/gate-green-draft.json"
assert_check_spec_gate_passes "tools/fixtures/spec/gate-green-draft.json"

# P-91: confirmation references must retain every source required by their field.
# P-78: Recheck the ingest contract using isolated input/spec files and fresh processes.
cp -R schemas "$ISOLATED_RESOLVER_ROOT/"
if confirmation_contract_output=$(python3 -B - "$ISOLATED_RESOLVER_ROOT" <<'PY' 2>&1
import copy
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest


ISOLATED_ROOT = pathlib.Path(sys.argv.pop())


class ConfirmationSourceTests(unittest.TestCase):
    def setUp(self):
        fixture = pathlib.Path("tools/fixtures/spec/good-spec.json")
        self.spec = json.loads(fixture.read_text(encoding="utf-8"))
        self.confirmation = json.loads(
            fixture.with_suffix(".confirmation.json").read_text(encoding="utf-8")
        )
        self.confirmation["confirmed_by"] = "applicant"
        funding = self.spec["funding"]
        funding["add_ons"] = [
            {"addon_id": addon_id, "name": addon_id, "max_amount_delta": 10,
             "required_rules": [], "source_clauses": ["clause-1"]}
            for addon_id in ("addon-a", "addon-b")
        ]
        funding["combinations"] = [
            {"addon_ids": ["addon-a", "addon-b"], "max_amount_total": 70}
        ]
        self.spec["bonus_items"] = [{"bonus_id": "bonus-1", "name": "Fixture bonus"}]
        deliverable = self.spec["deliverables"][0]
        section = deliverable["sections"][0]
        section["max_pages"] = 1
        self.fields = (
            ("schedule.application-deadline", self.spec["schedule"][0]),
            ("eligibility.rules.rule-1", self.spec["eligibility"]["rules"][0]),
            ("funding.base_award", funding["base_award"]),
            ("funding.add_ons.addon-a", funding["add_ons"][0]),
            ("funding.add_ons.addon-b", funding["add_ons"][1]),
            ("funding.combinations.addon-a+addon-b", funding["combinations"][0]),
            ("funding.eligible_expenses.広報費", funding["eligible_expenses"][0]),
            ("bonus_items.bonus-1", self.spec["bonus_items"][0]),
            ("deliverables.deliverable-1", deliverable),
            ("deliverables.deliverable-1.sections.section-1.max_chars", section),
            ("deliverables.deliverable-1.sections.section-1.max_pages", section),
        )
        for index, (_, field) in enumerate(self.fields):
            clause_id = f"field-source-{index}"
            field["source_clauses"] = [clause_id, "clause-1"]
            clause = dict(self.spec["clauses"][0], clause_id=clause_id)
            self.spec["clauses"].append(clause)
        items = {item["field_path"]: item for item in self.confirmation["items"]}
        for field_path, field in self.fields:
            item = items.setdefault(field_path, {
                "field_path": field_path, "state": "confirmed", "note": "Fixture confirmation.",
            })
            item["source_clauses"] = list(field["source_clauses"])
        self.confirmation["items"] = list(items.values())
        self.temp = tempfile.TemporaryDirectory(prefix="check-spec-confirmation-sources-")
        self.addCleanup(self.temp.cleanup)
        self.spec_path = pathlib.Path(self.temp.name) / "source-coverage.json"

    def check_confirmation(self, confirmation, status, *messages):
        self.spec_path.write_text(json.dumps(self.spec), encoding="utf-8")
        confirmation["spec_path"] = self.spec_path.as_posix()
        confirmation["spec_sha256"] = hashlib.sha256(self.spec_path.read_bytes()).hexdigest()
        confirmation_path = self.spec_path.with_suffix(".confirmation.json")
        confirmation_path.write_text(json.dumps(confirmation), encoding="utf-8")
        before = (self.spec_path.read_bytes(), confirmation_path.read_bytes())
        for gate in ([], ["--gate", "confirm"]):
            with self.subTest(gate=gate, spec_status=self.spec["status"]):
                result = subprocess.run(
                    ["bash", "tools/check-spec.sh", str(self.spec_path),
                     "--now", "2026-09-01T12:00:00+09:00", *gate],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                )
                self.assertEqual(result.returncode, status, result.stdout)
                for message in messages:
                    self.assertIn(message, result.stdout)
                self.assertNotIn("Traceback", result.stdout)
                self.assertEqual(before, (self.spec_path.read_bytes(), confirmation_path.read_bytes()))

    def test_tane05_unknown_clause(self):
        for spec_status in ("draft", "confirmed"):
            self.spec["status"] = spec_status
            for supplemental in (False, True):
                confirmation = copy.deepcopy(self.confirmation)
                item = confirmation["items"][0]
                item["source_clauses"] = (
                    item["source_clauses"] if supplemental else []
                ) + ["unknown-clause"]
                clause_index = len(item["source_clauses"]) - 1
                with self.subTest(supplemental=supplemental):
                    self.check_confirmation(
                        confirmation, 1, "unknown confirmation source_clauses reference",
                        f"confirmation.items[0].source_clauses[{clause_index}]=unknown-clause",
                    )
        # Additional field paths still require real references.
        confirmation = copy.deepcopy(self.confirmation)
        confirmation["items"][0]["field_path"] = "additional.notes"
        confirmation["items"][0]["source_clauses"] = ["unknown-clause"]
        self.check_confirmation(confirmation, 1, "unknown confirmation source_clauses reference")

    def test_tane05_field_source_coverage(self):
        for field_path, field in self.fields:
            required = field["source_clauses"]
            other = next(value for _, value in self.fields if value["source_clauses"] != required)
            replacements = ([other["source_clauses"][0]], required[:1], required[1:])
            for sources in replacements:
                with self.subTest(field_path=field_path, sources=sources):
                    confirmation = copy.deepcopy(self.confirmation)
                    item = next(item for item in confirmation["items"] if item["field_path"] == field_path)
                    item["source_clauses"] = sources
                    self.check_confirmation(
                        confirmation, 1, "confirmation source_clauses mismatch", field_path,
                    )

    def test_tane05_supplemental_sources(self):
        for supplemental in (False, True):
            confirmation = copy.deepcopy(self.confirmation)
            for field_path, field in self.fields:
                sources = list(reversed(field["source_clauses"]))
                if supplemental:
                    other = next(value for _, value in self.fields if value["source_clauses"] != field["source_clauses"])
                    sources.append(other["source_clauses"][0])
                item = next(item for item in confirmation["items"] if item["field_path"] == field_path)
                item["source_clauses"] = sources
            self.check_confirmation(confirmation, 0, "OK: spec checks passed")

    def test_tane05_source_types(self):
        for sources, message in (
            ([], ".source_clauses must be a non-empty array"),
            ("clause-1", ".source_clauses must be a non-empty array"),
            ([None], ".source_clauses[0] must be a string"),
            ([{}], ".source_clauses[0] must be a string"),
            ([[]], ".source_clauses[0] must be a string"),
        ):
            with self.subTest(sources=sources):
                confirmation = copy.deepcopy(self.confirmation)
                confirmation["items"][0]["source_clauses"] = sources
                self.check_confirmation(confirmation, 1, "confirmation.items[0]" + message)


class IngestContractTests(unittest.TestCase):
    def setUp(self):
        input_spec = ISOLATED_ROOT / "input" / "spec"
        input_spec.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix="p78-", dir=input_spec)
        self.addCleanup(temporary.cleanup)
        self.directory = pathlib.Path(temporary.name)
        self.path = self.directory / "spec.json"
        self.confirmation_path = self.directory / "spec.confirmation.json"
        self.spec = json.loads(pathlib.Path("tools/fixtures/spec/gate-green-draft.json").read_text(encoding="utf-8"))
        self.confirmation = json.loads(pathlib.Path("tools/fixtures/spec/gate-green-draft.confirmation.json").read_text(encoding="utf-8"))
        self.confirmation.update(
            spec_path=self.path.relative_to(ISOLATED_ROOT).as_posix(),
            ingest_mode="ai_only", extract_sha256={},
        )
        self.spec["source_documents"] = []
        self.spec["clauses"] = []
        self.add_document("doc-1", "Fixture clause one.")
        self.add_document("doc-2", "Fixture clause two.")

    def add_document(self, document_id, text, referenced=True):
        path = self.directory / (document_id + ".extract.md")
        path.write_text("# Fixture\n\n## p.1\n\n" + text + "\n", encoding="utf-8")
        self.spec["source_documents"].append({
            "document_id": document_id, "title": "Fixture source",
            "url_or_path": "fixture-source.pdf", "sha256": "a" * 64,
            "extract_path": path.relative_to(ISOLATED_ROOT).as_posix(),
        })
        self.confirmation["extract_sha256"][document_id] = hashlib.sha256(path.read_bytes()).hexdigest()
        if referenced:
            self.spec["clauses"].append({
                "clause_id": "clause-" + str(len(self.spec["clauses"]) + 1),
                "source_document_id": document_id, "text": text,
            })
        return path

    def run_check(self, gate=None, with_confirmation=True, absolute=False):
        self.path.write_text(json.dumps(self.spec), encoding="utf-8")
        spec_arg = str(self.path) if absolute else self.path.relative_to(ISOLATED_ROOT).as_posix()
        self.confirmation["spec_path"] = spec_arg
        if self.spec["status"] == "confirmed":
            self.confirmation.update(
                spec_sha256=hashlib.sha256(self.path.read_bytes()).hexdigest(),
                confirmed_by="applicant", confirmed_at="2026-09-12",
            )
        if with_confirmation:
            self.confirmation_path.write_text(json.dumps(self.confirmation), encoding="utf-8")
        else:
            if self.confirmation_path.exists():
                self.confirmation_path.unlink()
        command = ["bash", str(ISOLATED_ROOT / "tools/check-spec.sh"), spec_arg]
        if gate:
            command.extend(["--gate", gate])
        return subprocess.run(command, cwd=ISOLATED_ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def assert_result(self, result, status, *messages):
        self.assertEqual(result.returncode, status, result.stdout)
        self.assertNotIn("Traceback", result.stdout)
        self.assertIn("OK:" if status == 0 else "FAIL:", result.stdout)
        for message in messages:
            self.assertIn(message, result.stdout)

    def prepare_ingest_confirmation(self):
        self.confirmation.pop("ingest_mode", None)
        self.confirmation.pop("extract_sha256", None)
        for item in self.confirmation["items"]:
            item["state"] = "open"
            if "predicate_state" in item:
                item["predicate_state"] = "pending"
        self.path.write_text(json.dumps(self.spec), encoding="utf-8")
        self.confirmation_path.write_text(json.dumps(self.confirmation), encoding="utf-8")

    def run_ingest_step(self, step, mode="ai_only"):
        command = pathlib.Path(".claude/commands/ingest-guidelines.md").read_text(encoding="utf-8")
        section = command.split(f"### {step}.", 1)[1].split(f"### {step + 1}.", 1)[0]
        blocks = re.findall(r"```bash\n(.*?)```", section, re.S)
        self.assertEqual(len(blocks), 1, f"ingest step {step} must have one executable bash block")
        block = blocks[0].replace(
            "input/spec/<subsidy_id>.json", self.path.relative_to(ISOLATED_ROOT).as_posix(),
        ).replace("<ingest_mode>", mode)
        return subprocess.run(
            ["bash", "-eu", "-c", block], cwd=ISOLATED_ROOT,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )

    def test_ingest_step3_ai_only_confirmation_passes_gate(self):
        confirmed_items = copy.deepcopy(self.confirmation["items"])
        self.add_document("doc-3", "Unreferenced fixture text.", referenced=False)
        extract = self.directory / "doc-1.extract.md"
        extract.write_bytes(extract.read_bytes().replace(b"\n", b"\r\n"))
        self.spec["source_documents"][1]["extract_path"] = "doc-2.extract.md"
        self.spec["source_documents"][2]["extract_path"] = str(self.directory / "doc-3.extract.md")
        self.prepare_ingest_confirmation()
        spec_bytes = self.path.read_bytes()
        result = self.run_ingest_step(3)
        self.assertEqual(result.returncode, 0, result.stdout)
        saved = json.loads(self.confirmation_path.read_text(encoding="utf-8"))
        self.assertEqual(saved["ingest_mode"], "ai_only")
        self.assertEqual(saved["extract_sha256"], {
            document["document_id"]: hashlib.sha256(
                (self.directory / (document["document_id"] + ".extract.md")).read_bytes()
            ).hexdigest()
            for document in self.spec["source_documents"]
        })
        self.assertEqual(saved["items"], self.confirmation["items"])
        self.assertIsNone(saved["spec_sha256"])
        self.assertEqual(self.path.read_bytes(), spec_bytes)
        self.assertFalse((ISOLATED_ROOT / "input/current-application.json").exists())
        self.assert_result(self.run_ingest_step(4), 0, "verbatim coverage 2/2 matched")
        gate_command = ["bash", "tools/check-spec.sh", saved["spec_path"], "--gate", "confirm"]
        self.assert_result(subprocess.run(
            gate_command, cwd=ISOLATED_ROOT, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True,
        ), 1, "unconfirmed required item")
        # Represent the applicant's confirmation without replacing the saved ingest contract.
        saved["items"] = confirmed_items
        self.confirmation_path.write_text(json.dumps(saved), encoding="utf-8")
        self.assert_result(subprocess.run(
            gate_command, cwd=ISOLATED_ROOT, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True,
        ), 0, "verbatim coverage 2/2 matched", "0 mismatched; 0 skipped without extract_path")

    def test_ingest_step3_human_spot_check_confirmation_accepted(self):
        for document in self.spec["source_documents"]:
            del document["extract_path"]
        self.prepare_ingest_confirmation()
        result = self.run_ingest_step(3, "human_spot_check")
        self.assertEqual(result.returncode, 0, result.stdout)
        saved = json.loads(self.confirmation_path.read_text(encoding="utf-8"))
        self.assertEqual(saved["ingest_mode"], "human_spot_check")
        self.assertEqual(saved["items"], self.confirmation["items"])
        self.assert_result(self.run_ingest_step(4), 0)

    def test_ingest_step3_invalid_mode_preserves_confirmation(self):
        self.prepare_ingest_confirmation()
        before = self.confirmation_path.read_bytes()
        result = self.run_ingest_step(3, "unknown")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("invalid choice", result.stdout)
        self.assertEqual(self.confirmation_path.read_bytes(), before)

    def test_ai_only_missing_extract_rejected(self):
        invalid_utf8 = self.directory / "invalid-utf8.md"
        invalid_utf8.write_bytes(b"\xff\xfe")
        for value, diagnostic in (
            (None, "ai_only requires extract_path"),
            ("", "invalid extract_path"),
            (7, "invalid extract_path"),
            ("absent.md", "extract file not found"),
            (str(self.directory), "extract file cannot be read"),
            (str(invalid_utf8), "extract file cannot be read"),
        ):
            self.spec["source_documents"][0]["extract_path"] = value
            for gate in (None, "confirm"):
                with self.subTest(value=value, gate=gate):
                    self.assert_result(self.run_check(gate), 1, diagnostic)

    def test_ai_only_extract_hash_required(self):
        for value in (None, {}, {"doc-1": None}, {"doc-1": "invalid"}, {"doc-1": "0" * 64}):
            self.confirmation["extract_sha256"] = value
            for gate in (None, "confirm"):
                with self.subTest(value=value, gate=gate):
                    self.assert_result(self.run_check(gate), 1, "extract_sha256")
        del self.confirmation["extract_sha256"]
        self.assert_result(self.run_check("confirm"), 1, "extract_sha256")

    def test_ai_only_incomplete_clause_coverage_rejected(self):
        original = copy.deepcopy(self.spec["clauses"])
        for changes in (
            {"text": "Different fixture text."}, {"text": None},
            {"raw_text": "Different raw fixture text."}, {"text": " \n "},
            {"source_document_id": None}, {"source_document_id": "unknown-doc"},
        ):
            self.spec["clauses"] = copy.deepcopy(original)
            self.spec["clauses"][1].update(changes)
            for gate in (None, "confirm"):
                with self.subTest(changes=changes, gate=gate):
                    self.assert_result(self.run_check(gate), 1, "ai_only requires complete verbatim coverage")

    def test_ai_only_unreferenced_document_missing_extract_rejected(self):
        path = self.add_document("doc-3", "Unreferenced fixture text.", referenced=False)
        document = self.spec["source_documents"][-1]
        extract_path = document.pop("extract_path")
        self.assert_result(self.run_check("confirm"), 1, "ai_only requires extract_path", "source_documents[2]")
        document["extract_path"] = "absent.md"
        self.assert_result(self.run_check("confirm"), 1, "extract file not found", "source_documents[2]")
        document["extract_path"] = str(self.directory)
        self.assert_result(self.run_check("confirm"), 1, "extract file cannot be read", "source_documents[2]")
        document["extract_path"] = extract_path
        path.write_text("Changed unreferenced fixture text.\n", encoding="utf-8")
        self.assert_result(self.run_check("confirm"), 1, "extract_sha256 mismatch", "doc-3")

    def test_ai_only_rechecked_after_restart(self):
        path = self.directory / "doc-1.extract.md"
        original = path.read_bytes()
        for status in ("draft", "confirmed"):
            self.spec["status"] = status
            self.assert_result(self.run_check("confirm"), 0)
            path.write_bytes(original + b"\nAdditional fixture text.\n")
            for gate in (None, "confirm"):
                with self.subTest(status=status, gate=gate, changed="extract"):
                    self.assert_result(self.run_check(gate), 1, "extract_sha256 mismatch")
            path.write_bytes(original)
            self.spec["clauses"][0]["text"] = "Changed clause text."
            for gate in (None, "confirm"):
                with self.subTest(status=status, gate=gate, changed="spec"):
                    self.assert_result(self.run_check(gate), 1, "ai_only requires complete verbatim coverage")
            self.spec["clauses"][0]["text"] = "Fixture clause one."

    def test_unmarked_input_draft_rejected_with_reingest_guidance(self):
        del self.confirmation["ingest_mode"]
        del self.confirmation["extract_sha256"]
        for with_confirmation in (True, False):
            for gate in (None, "confirm"):
                for absolute in (False, True):
                    with self.subTest(confirmation=with_confirmation, gate=gate, absolute=absolute):
                        self.assert_result(
                            self.run_check(gate, with_confirmation, absolute), 1,
                            "ingest_mode", "/ingest-guidelines", "工程確認からやり直",
                            "手順 3", "extract_sha256",
                        )

    def test_invalid_ingest_mode_rejected(self):
        for value in (None, "", "unknown", 7, [], {}):
            self.confirmation["ingest_mode"] = value
            for gate in (None, "confirm"):
                with self.subTest(value=value, gate=gate):
                    self.assert_result(self.run_check(gate), 1, "confirmation.ingest_mode must be")

    def test_unmarked_input_draft_links_require_reingest(self):
        del self.confirmation["ingest_mode"]
        temporary = tempfile.TemporaryDirectory(prefix="p78-stored-", dir=ISOLATED_ROOT)
        self.addCleanup(temporary.cleanup)
        stored = pathlib.Path(temporary.name)
        self.path.symlink_to(stored / "spec.json")
        for kind in ("file", "directory", "linked-parent"):
            if kind == "directory":
                link = self.directory / "linked"
                link.symlink_to(stored, target_is_directory=True)
                self.path = link / "spec.json"
                self.confirmation_path = link / "spec.confirmation.json"
                self.confirmation["spec_path"] = self.path.relative_to(ISOLATED_ROOT).as_posix()
            elif kind == "linked-parent":
                target = self.directory / "target"
                (target / "child").mkdir(parents=True)
                link = stored / "linked-child"
                link.symlink_to(target / "child", target_is_directory=True)
                self.path = link / ".." / "spec.json"
                self.confirmation_path = self.path.with_name("spec.confirmation.json")
            for gate in (None, "confirm"):
                for absolute in (False, True):
                    with self.subTest(kind=kind, gate=gate, absolute=absolute):
                        self.assert_result(self.run_check(gate, absolute=absolute), 1, "/ingest-guidelines")

    def test_human_spot_check_compatible(self):
        self.confirmation["ingest_mode"] = "human_spot_check"
        del self.confirmation["extract_sha256"]
        for document in self.spec["source_documents"]:
            del document["extract_path"]
        for gate in (None, "confirm"):
            self.assert_result(self.run_check(gate), 0)

    def test_unmarked_input_draft_case_variants_require_reingest(self):
        directory = ISOLATED_ROOT / "INPUT" / "SPEC" / self.directory.name
        if not directory.is_dir():
            self.skipTest("Directory name case is distinct on this filesystem")
        self.path = directory / "spec.json"
        self.confirmation_path = directory / "spec.confirmation.json"
        del self.confirmation["ingest_mode"]
        for gate in (None, "confirm"):
            for absolute in (False, True):
                with self.subTest(gate=gate, absolute=absolute):
                    self.assert_result(self.run_check(gate, absolute=absolute), 1, "/ingest-guidelines")

    def test_legacy_confirmed_pack_compatible(self):
        result = subprocess.run(
            ["bash", "tools/check-spec.sh", "specs/jizokuka-20/jizokuka-20.json"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        self.assert_result(result, 0, "71 skipped without extract_path")

    def test_ai_only_valid_pack_accepted(self):
        confirmed_items = copy.deepcopy(self.confirmation["items"])
        for item in self.confirmation["items"]:
            item["state"] = "open"
        self.assert_result(self.run_check(), 0, "verbatim coverage 2/2 matched")
        self.assert_result(self.run_check("confirm"), 1, "unconfirmed required item")
        self.confirmation["items"] = confirmed_items
        self.add_document("doc-3", "Valid unreferenced fixture text.", referenced=False)
        self.assert_result(self.run_check("confirm"), 0, "verbatim coverage 2/2 matched")
        self.spec["status"] = "confirmed"
        self.assert_result(self.run_check(), 0, "0 mismatched; 0 skipped without extract_path")


unittest.main(verbosity=2)
PY
); then
  pass
  printf '%s\n' "$confirmation_contract_output"
else
  fail "P-91/P-78 confirmation contract checks must pass :: $confirmation_contract_output"
fi

python3 - \
  tools/fixtures/spec/gate-green-draft.json \
  tools/fixtures/spec/gate-green-draft.confirmation.json \
  "$RELATIVE_OFFSET_TEST_DIR" <<'PY'
import copy
import json
import pathlib
import sys

spec_path, confirmation_path, output_dir = map(pathlib.Path, sys.argv[1:4])
base_spec = json.loads(spec_path.read_text(encoding="utf-8"))
base_confirmation = json.loads(confirmation_path.read_text(encoding="utf-8"))
for label, offset_days in (("negative", -14), ("zero", 0), ("positive", 14)):
    output_spec_path = output_dir / f"{label}.json"
    output_confirmation_path = output_dir / f"{label}.confirmation.json"
    spec = copy.deepcopy(base_spec)
    spec["schedule"][0]["relative"] = {
        "anchor": "受付開始日",
        "offset_days": offset_days,
        "direction": "within_after",
    }
    confirmation = copy.deepcopy(base_confirmation)
    confirmation["spec_path"] = output_spec_path.as_posix()
    output_spec_path.write_text(
        json.dumps(spec, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    output_confirmation_path.write_text(
        json.dumps(confirmation, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
PY
assert_check_spec_gate_fails_with \
  "$RELATIVE_OFFSET_TEST_DIR/negative.json" \
  '$.schedule[0].relative.offset_days must be greater than or equal to 0: -14'
assert_check_spec_gate_passes "$RELATIVE_OFFSET_TEST_DIR/zero.json"
assert_check_spec_gate_passes "$RELATIVE_OFFSET_TEST_DIR/positive.json"

assert_check_spec_passes "tools/fixtures/spec/gate-open-remaining.json"
assert_check_spec_passes "tools/fixtures/spec/gate-predicate-pending.json"
assert_check_spec_passes "tools/fixtures/spec/gate-predicate-mismatch.json"
assert_check_spec_passes_with "tools/fixtures/spec/verbatim-match.json" "READINESS: verbatim coverage 1/1 matched"
assert_check_spec_passes_with "tools/fixtures/spec/verbatim-mismatch.json" "WARN: clause verbatim mismatch"
assert_check_spec_gate_passes "tools/fixtures/spec/verbatim-match.json"

assert_check_spec_fails_with "tools/fixtures/spec/missing-required-key.json" "missing required key: $.spec_version"
assert_check_spec_fails_with "tools/fixtures/spec/duplicate-id.json" "duplicate id: rule_id=rule-1"
assert_check_spec_fails_with "tools/fixtures/spec/bad-id-pattern.json" "bad id pattern: $.eligibility.rules[0].rule_id=Bad Rule"
assert_check_spec_fails_with "tools/fixtures/spec/no-application-deadline.json" "schedule must include at least one event_kind=application_deadline"
assert_check_spec_fails_with "tools/fixtures/spec/bad-due-event.json" "unknown due_event_id: $.deliverables[0].due_event_id=missing-event"
assert_check_spec_fails_with "tools/fixtures/spec/bad-source-document.json" "unknown source_document_id: $.clauses[0].source_document_id=missing-doc"
assert_check_spec_fails_with "tools/fixtures/spec/bad-source-documents-fields.json" "missing required key: $.source_documents[0].url_or_path"
assert_check_spec_fails_with "tools/fixtures/spec/bad-category-tag.json" "unknown category_tags reference: $.category_tags[0]=unknown-tag"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-open-item.json" "unconfirmed required item: schedule.application-deadline"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-open-item.json" "invalid confirmation state: confirmation.items[1].state='unknown-state'"
assert_check_spec_fails_with "tools/fixtures/spec/stale-sha.json" "confirmation spec_sha256 mismatch"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-null-fixed-fields.json" "confirmation.spec_sha256 must be a string when spec status is confirmed"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-null-fixed-fields.json" "confirmation.confirmed_by must be one of applicant, provider"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-null-fixed-fields.json" "confirmation.confirmed_at must be a string when spec status is confirmed"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-missing-fixed-fields.json" "missing required key: confirmation.spec_sha256"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-missing-fixed-fields.json" "missing required key: confirmation.confirmed_by"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-missing-fixed-fields.json" "missing required key: confirmation.confirmed_at"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-invalid-fixed-fields.json" "confirmation.spec_sha256 must be a 64-character lowercase hex string"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-invalid-fixed-fields.json" "confirmation.confirmed_by must be one of applicant, provider"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-invalid-fixed-fields.json" "confirmation.confirmed_at must look like ISO8601"
assert_check_spec_fails_with "tools/fixtures/spec/confirmation-missing-path.json" "confirmation missing required field_path: schedule.application-deadline"
assert_check_spec_fails_with "tools/fixtures/spec/bonus-missing.json" "confirmation missing required field_path: bonus_items.fixture-bonus"
assert_check_spec_fails_with "tools/fixtures/spec/source-clauses-empty.json" "missing or empty source_clauses: $.funding.base_award.source_clauses"
assert_check_spec_fails_with "tools/fixtures/spec/bad-depends-on.json" "unknown depends_on reference: $.deliverables[0].depends_on[0]=missing-deliverable"
test_tane03_missing_dependency_without_due
test_tane03_valid_dependency_without_due
test_tane03_dependency_types
assert_tane03_dependency_case '42' '[]' 1 '$.deliverables[0].due_event_id must be a string or null'
assert_tane03_dependency_case '"missing-event"' '[]' 1 'unknown due_event_id: $.deliverables[0].due_event_id=missing-event'
assert_check_spec_fails_with "tools/fixtures/spec/predicate-invalid-empty-all.json" "invalid predicate: $.eligibility.rules[0].predicate.all must be a non-empty array"
assert_check_spec_fails_with "tools/fixtures/spec/predicate-invalid-empty-any.json" "invalid predicate: $.eligibility.rules[0].predicate.any must be a non-empty array"
assert_check_spec_fails_with "tools/fixtures/spec/predicate-invalid-missing-value.json" "invalid predicate: $.eligibility.rules[0].predicate.value is required unless op=exists"
assert_check_spec_fails_with "tools/fixtures/spec/coverage-missing-draft.json" "confirmation missing required field_path: deliverables.deliverable-1"
assert_check_spec_fails_with "tools/fixtures/spec/direct-bypass-confirmed.json" "missing predicate_state: eligibility.rules.rule-1"
assert_check_spec_gate_fails_with "tools/fixtures/spec/gate-open-remaining.json" "unconfirmed required item: schedule.application-deadline"
assert_check_spec_gate_fails_with "tools/fixtures/spec/gate-predicate-pending.json" "predicate_state pending: eligibility.rules.rule-1"
assert_check_spec_gate_fails_with "tools/fixtures/spec/gate-predicate-mismatch.json" "predicate_state mismatch: eligibility.rules.rule-2 encoded but predicate is null"
assert_check_spec_gate_fails_with "tools/fixtures/spec/verbatim-mismatch.json" "clause verbatim mismatch"

assert_predicate "tools/fixtures/profiles/shougyou-5.json" "true"
assert_predicate "tools/fixtures/profiles/seizou-25.json" "false"
assert_predicate "tools/fixtures/profiles/unknown-emp.json" "unknown"

assert_predicate_rule "tools/fixtures/spec/predicate-kleene.json" "chusho-service-capital-employees" "tools/fixtures/profiles/chusho-service-ok.json" "true"
assert_predicate_rule "tools/fixtures/spec/predicate-kleene.json" "chusho-service-capital-employees" "tools/fixtures/profiles/chusho-retail-false.json" "false"
assert_predicate_rule "tools/fixtures/spec/predicate-kleene.json" "chusho-service-capital-employees" "tools/fixtures/profiles/chusho-unknown-null.json" "unknown"

assert_predicate_rule "tools/fixtures/spec/predicate-kleene.json" "not-unknown" "tools/fixtures/profiles/shougyou-5.json" "unknown"
assert_predicate_rule "tools/fixtures/spec/predicate-kleene.json" "all-true-unknown" "tools/fixtures/profiles/shougyou-5.json" "unknown"
assert_predicate_rule "tools/fixtures/spec/predicate-kleene.json" "all-false-unknown" "tools/fixtures/profiles/shougyou-5.json" "false"
assert_predicate_rule "tools/fixtures/spec/predicate-kleene.json" "any-true-unknown" "tools/fixtures/profiles/shougyou-5.json" "true"
assert_predicate_rule "tools/fixtures/spec/predicate-kleene.json" "any-false-unknown" "tools/fixtures/profiles/shougyou-5.json" "unknown"
assert_predicate_rule "tools/fixtures/spec/predicate-invalid-empty-all.json" "invalid-predicate" "tools/fixtures/profiles/shougyou-5.json" "unknown"
assert_predicate_rule "tools/fixtures/spec/predicate-invalid-empty-any.json" "invalid-predicate" "tools/fixtures/profiles/shougyou-5.json" "unknown"
assert_predicate_rule "tools/fixtures/spec/predicate-invalid-missing-value.json" "invalid-predicate" "tools/fixtures/profiles/shougyou-5.json" "unknown"

assert_predicate_rule "tools/fixtures/spec/predicate-type-mismatch.json" "emp-eq-25" "tools/fixtures/profiles/type-mismatch-string-emp.json" "unknown"
assert_predicate_rule "tools/fixtures/spec/predicate-type-mismatch.json" "emp-ne-25" "tools/fixtures/profiles/type-mismatch-string-emp.json" "unknown"
assert_predicate_rule "tools/fixtures/spec/predicate-type-mismatch.json" "industry-in-string" "tools/fixtures/profiles/seizou-25.json" "unknown"
assert_predicate_rule "tools/fixtures/spec/predicate-type-mismatch.json" "flag-eq-one" "tools/fixtures/profiles/type-mismatch-bool-flag.json" "unknown"
assert_predicate_rule "tools/fixtures/spec/predicate-application-scope.json" "missing-rule-id" "tools/fixtures/profiles/shougyou-5.json" "unknown"

# P-74: bounded facts never replace unknown exact values.
if bounded_fact_output=$(python3 -B - <<'PY' 2>&1
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


class BoundedFactTests(unittest.TestCase):
    exact_key = "taxable_income_avg_3y"
    bounded_key = "taxable_income_avg_3y_lte_15"

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.spec_path = pathlib.Path(temporary.name) / "spec.json"
        self.profile_path = pathlib.Path(temporary.name) / "profile.json"
        spec = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.json").read_text(encoding="utf-8"))
        spec["status"] = "draft"
        template = spec["eligibility"]["rules"][0]
        spec["eligibility"]["rules"] = [
            dict(template, rule_id=rule_id, text="記録規約の回帰テスト用条件。", predicate={
                "scope": "profile", "key": key, "op": op, "value": value,
            })
            for rule_id, key, op, value in (
                ("numeric-gt", self.exact_key, "gt", 15),
                ("numeric-lte", self.exact_key, "lte", 15),
                ("numeric-lt", self.exact_key, "lt", 15),
                ("bounded-boolean", self.bounded_key, "eq", True),
            )
        ]
        self.spec_path.write_text(json.dumps(spec), encoding="utf-8")
        self.profile = {"entity_type": None, "industry_class": None, "employees": None,
                        self.exact_key: None, self.bounded_key: True}

    def assert_result(self, rule_id, expected):
        self.profile_path.write_text(json.dumps(self.profile), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, "-B", "tools/lib/predicate.py", str(self.spec_path),
             rule_id, str(self.profile_path)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected + "\n")
        self.assertEqual(result.stderr, "")

    def test_bounded_fact_exact_value_unknown(self):
        for value in (True, False, None):
            self.profile[self.bounded_key] = value
            for rule_id in ("numeric-gt", "numeric-lte", "numeric-lt"):
                with self.subTest(bounded=value, rule_id=rule_id):
                    self.assert_result(rule_id, "unknown")

    def test_bounded_fact_boolean_states(self):
        for value, expected in ((True, "true"), (False, "false"), (None, "unknown")):
            with self.subTest(value=value):
                self.profile[self.bounded_key] = value
                self.assert_result("bounded-boolean", expected)
        del self.profile[self.bounded_key]
        self.assert_result("bounded-boolean", "unknown")

    def test_bounded_fact_boundary_operators(self):
        self.profile[self.exact_key] = 15
        for rule_id, expected in (("numeric-lte", "true"), ("numeric-lt", "false"),
                                  ("numeric-gt", "false")):
            with self.subTest(rule_id=rule_id):
                self.assert_result(rule_id, expected)

    def test_bounded_fact_undeclared_key(self):
        command = ["bash", "tools/check-spec.sh", str(self.spec_path)]
        result = subprocess.run(command + ["--now", "2026-07-17T12:00:00+09:00"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("WARN: predicate references undeclared profile key: " + self.bounded_key,
                      result.stdout + result.stderr)
        result = subprocess.run(command + ["--list-predicate-keys"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        entry = next(item for item in json.loads(result.stdout)["keys"]
                     if item["scope"] == "profile" and item["key"] == self.bounded_key)
        self.assertIs(entry["declared"], False)


unittest.main(verbosity=2)
PY
); then
  pass
  printf '%s\n' "$bounded_fact_output"
else
  fail "P-74 bounded fact contract :: $bounded_fact_output"
fi

# P-90: comparison categories and three-valued membership share one contract.
if tane07_output=$(python3 -B - <<'PY' 2>&1
import unittest

from tools.lib.predicate import compare_values, eval_predicate

T, F, U = "true", "false", "unknown"


class PredicateComparisonTests(unittest.TestCase):
    def assert_comparison(self, actual, op, value, result):
        with self.subTest(actual=actual, op=op, value=value):
            self.assertEqual(compare_values(actual, op, value), result)
            leaf = {"scope": "profile", "key": "field", "op": op, "value": value}
            self.assertEqual(eval_predicate(leaf, {"profile": {"field": actual}}), result)

    def test_tane07_comparison_matrix(self):
        # Rows and columns: boolean, number, string, array.
        values = (True, 1, "1", [1])
        matrices = {
            "eq": ((T, U, U, U), (U, T, U, U), (U, U, T, U), (U, U, U, U)),
            "ne": ((F, U, U, U), (U, F, U, U), (U, U, F, U), (U, U, U, U)),
            "lt": ((U, U, U, U), (U, F, U, U), (U, U, F, U), (U, U, U, U)),
            "lte": ((U, U, U, U), (U, T, U, U), (U, U, T, U), (U, U, U, U)),
            "gt": ((U, U, U, U), (U, F, U, U), (U, U, F, U), (U, U, U, U)),
            "gte": ((U, U, U, U), (U, T, U, U), (U, U, T, U), (U, U, U, U)),
            "in": ((U, U, U, U), (U, U, U, T), (U, U, U, U), (U, U, U, U)),
            "contains": ((U, U, U, U), (U, U, U, U), (U, U, T, U), (U, T, U, U)),
        }
        for op, matrix in matrices.items():
            for row, actual in enumerate(values):
                for column, value in enumerate(values):
                    self.assert_comparison(actual, op, value, matrix[row][column])

    def test_tane07_typed_membership(self):
        self.assert_comparison(True, "lte", 5, U)
        cases = (
            (True, [1], U),
            (False, [0.0], U),
            (1, [True], U),
            (0, [False], U),
            (True, [1, True], T),
            (True, [True, 1], T),
            (False, [True, False], T),
            (True, [False], F),
            (False, [True], F),
            (1, [True, 1.0], T),
            (1, [1.0, True], T),
            (1, [True, 2], U),
            (1, [2, True], U),
            (1, [2, 3.0], F),
            ("1", [1, "1"], T),
            ("1", ["2", "3"], F),
            ("1", [1, 2], U),
            (1, [[1], {}], U),
            (1, [None], U),
            (1, [None, {}, [1], 1.0], T),
            (1, [1.0, [1], {}, None], T),
        )
        for actual, candidates, result in cases:
            self.assert_comparison(actual, "in", candidates, result)
            self.assert_comparison(candidates, "contains", actual, result)
        for actual in (False, True, 0, 1.0, "", "1"):
            self.assert_comparison(actual, "in", [], F)
            self.assert_comparison([], "contains", actual, F)
        for actual in ([], [1], [[1]], {}, {"key": 1}, None):
            for op in ("eq", "ne", "lt", "lte", "gt", "gte"):
                self.assert_comparison(actual, op, actual, U)
            for candidates in ([], [actual]):
                self.assert_comparison(actual, "in", candidates, U)
                self.assert_comparison(candidates, "contains", actual, U)
        self.assert_comparison({"key": 1}, "contains", "key", U)
        self.assert_comparison("key", "in", {"key": 1}, U)

    def test_tane07_existing_semantics(self):
        operators = ("eq", "ne", "lt", "lte", "gt", "gte")
        cases = (
            (1, 1.0, (T, F, F, T, F, T)),
            (1.0, 1, (T, F, F, T, F, T)),
            (1, 2.0, (F, T, T, T, F, F)),
            (2.0, 1, (F, T, F, F, T, T)),
            (-2, -1.5, (F, T, T, T, F, F)),
            ("10", "2", (F, T, T, T, F, F)),
            ("b", "a", (F, T, F, F, T, T)),
        )
        for actual, value, results in cases:
            for op, result in zip(operators, results):
                self.assert_comparison(actual, op, value, result)
        for actual, value, result in ((False, False, T), (False, True, F), (True, False, F)):
            self.assert_comparison(actual, "eq", value, result)
            self.assert_comparison(actual, "ne", value, F if result == T else T)
        for actual, value, result in (("abc", "b", T), ("abc", "bd", F), ("abc", "", T), ("", "", T), ("", "a", F)):
            self.assert_comparison(actual, "contains", value, result)

        exists = {"scope": "profile", "key": "field", "op": "exists"}
        for profile, result in (({}, U), ({"field": None}, U)):
            with self.subTest(profile=profile):
                self.assertEqual(eval_predicate(exists, {"profile": profile}), result)
        for value in (False, 0, "", [], {}):
            with self.subTest(exists=value):
                self.assertEqual(eval_predicate(exists, {"profile": {"field": value}}), T)

        leaves = (
            {"scope": "profile", "key": "field", "op": "eq", "value": 1},
            {"scope": "profile", "key": "field", "op": "eq", "value": 2},
            {"scope": "profile", "key": "missing", "op": "eq", "value": 1},
        )
        contexts = {"profile": {"field": 1}}
        for leaf, result in zip(leaves, (F, T, U)):
            with self.subTest(negated=leaf):
                self.assertEqual(eval_predicate({"not": leaf}, contexts), result)
        matrices = {
            "all": ((T, F, U), (F, F, F), (U, F, U)),
            "any": ((T, T, T), (T, F, U), (T, U, U)),
        }
        for op, matrix in matrices.items():
            for row, left in enumerate(leaves):
                for column, right in enumerate(leaves):
                    with self.subTest(op=op, row=row, column=column):
                        self.assertEqual(
                            eval_predicate({op: [left, right]}, contexts), matrix[row][column]
                        )


unittest.main(verbosity=2)
PY
); then
  pass
  printf '%s\n' "$tane07_output"
else
  fail "P-90 typed comparison contract :: $tane07_output"
fi

assert_predicate_rule \
  "$LEADING_HYPHEN_PREDICATE_SPEC_FILE" \
  "-leading-rule" \
  "tools/fixtures/profiles/shougyou-5.json" \
  "true"
assert_predicate_rule \
  "$LEADING_HYPHEN_PREDICATE_SPEC_FILE" \
  "-h" \
  "tools/fixtures/profiles/shougyou-5.json" \
  "true"
assert_predicate_rule \
  "$LEADING_HYPHEN_PREDICATE_SPEC_FILE" \
  "--current-application" \
  "tools/fixtures/profiles/shougyou-5.json" \
  "true"
for PREDICATE_HELP_FLAG in -h --help; do
  PREDICATE_HELP_OUTPUT="$(python3 tools/lib/predicate.py "$PREDICATE_HELP_FLAG" 2>&1)"
  PREDICATE_HELP_STATUS=$?
  if [ "$PREDICATE_HELP_STATUS" -eq 0 ] &&
     printf '%s\n' "$PREDICATE_HELP_OUTPUT" | grep -qF -- "usage:"; then
    pass
  else
    fail "predicate CLI leading $PREDICATE_HELP_FLAG should print usage and exit 0 :: status=$PREDICATE_HELP_STATUS output=$PREDICATE_HELP_OUTPUT"
  fi
done
assert_predicate_cli_fails_with \
  "usage:" \
  "$LEADING_HYPHEN_PREDICATE_SPEC_FILE" \
  "-h"

assert_predicate_rule \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "profile-only-employees" \
  "tools/fixtures/profiles/shougyou-5.json" \
  "true"
assert_predicate_with_application \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json" \
  "tools/fixtures/applications/chosen-funding-wage-up.json" \
  "true"
assert_predicate_with_application \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "nested-application-branch" \
  "tools/fixtures/profiles/shougyou-5.json" \
  "tools/fixtures/applications/chosen-funding-wage-up.json" \
  "true"
assert_predicate_cli_fails_with \
  "application scope requires --current-application" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json"
assert_predicate_cli_fails_with \
  "application scope requires --current-application" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "nested-application-branch" \
  "tools/fixtures/profiles/seizou-25.json"
assert_predicate_cli_fails_with \
  "current application subsidy_id mismatch" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application "tools/fixtures/applications/subsidy-id-mismatch.json"
assert_predicate_cli_fails_with \
  "current application spec_version mismatch" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application "tools/fixtures/applications/spec-version-mismatch.json"
assert_predicate_cli_fails_with \
  "current application spec_version must be an integer" \
  "$LEADING_HYPHEN_PREDICATE_SPEC_FILE" \
  "-leading-rule" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application="$BOOL_SPEC_VERSION_APPLICATION_FILE"
assert_predicate_cli_fails_with \
  "current application spec_version must be an integer" \
  "$LEADING_HYPHEN_PREDICATE_SPEC_FILE" \
  "-leading-rule" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application "$STRING_SPEC_VERSION_APPLICATION_FILE"
assert_predicate_cli_fails_with \
  "current application subsidy_id must be a string" \
  "$LEADING_HYPHEN_PREDICATE_SPEC_FILE" \
  "-leading-rule" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application "$NUMERIC_SUBSIDY_ID_APPLICATION_FILE"
assert_predicate_cli_fails_with \
  "spec subsidy_id must be a string" \
  "$INVALID_SPEC_SUBSIDY_ID_FILE" \
  "-leading-rule" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application "$VALID_BINDING_APPLICATION_FILE"
assert_predicate_cli_fails_with \
  "spec spec_version must be an integer" \
  "$INVALID_SPEC_VERSION_FILE" \
  "-leading-rule" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application "$VALID_BINDING_APPLICATION_FILE"
assert_predicate_cli_fails_with \
  "current application not found" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application "$MISSING_CURRENT_APPLICATION_FILE"
assert_predicate_cli_fails_with \
  "current application invalid JSON" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application "$INVALID_CURRENT_APPLICATION_FILE"
assert_predicate_cli_fails_with \
  "current application root must be an object" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json" \
  --current-application "$NON_OBJECT_CURRENT_APPLICATION_FILE"
assert_predicate_cli_fails_with \
  "remove it and pass current-application.json with --current-application" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "profile-only-employees" \
  "tools/fixtures/profiles/embedded-application.json"
assert_predicate_cli_fails_with \
  "remove it and pass current-application.json with --current-application" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "profile-only-employees" \
  "tools/fixtures/profiles/embedded-application.json" \
  --current-application "tools/fixtures/applications/chosen-funding-wage-up.json"
assert_predicate_with_application \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json" \
  "$NULL_PREDICATE_APPLICATION_FILE" \
  "unknown"
assert_predicate_with_application \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json" \
  "$UNBOUND_PREDICATE_APPLICATION_FILE" \
  "true"
assert_predicate_cli_fails_with \
  "unrecognized arguments" \
  "tools/fixtures/spec/predicate-application-scope.json" \
  "addon-wage-up-chosen" \
  "tools/fixtures/profiles/shougyou-5.json" \
  "tools/fixtures/applications/chosen-funding-wage-up.json"

test_tane01_spec_confirmation_roots() {
  local case_dir="$RESOLVE_APPLICATION_TEST_DIR/tane01-roots"
  local root_value label gate output status
  local check_args=()
  mkdir -p "$case_dir"
  for root_value in 'null' '[]' 'true' '"text"'; do
    for label in spec confirmation; do
      if ! python3 - "$case_dir" "$label" "$root_value" <<'PY'; then
import json
import pathlib
import sys

case_dir, label, raw = sys.argv[1:]
spec_path = pathlib.Path(case_dir) / "spec.json"
spec_text = pathlib.Path("tools/fixtures/spec/good-spec.json").read_text(encoding="utf-8")
confirmation = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.confirmation.json").read_text(encoding="utf-8"))
confirmation["spec_path"] = spec_path.as_posix()
spec_path.write_text(raw if label == "spec" else spec_text, encoding="utf-8")
spec_path.with_suffix(".confirmation.json").write_text(
    raw if label == "confirmation" else json.dumps(confirmation), encoding="utf-8"
)
PY
        fail "tane01 spec root fixture setup"
        return
      fi
      for gate in normal confirm; do
        check_args=("$case_dir/spec.json")
        if [ "$gate" = confirm ]; then check_args+=(--gate confirm); fi
        output=$(bash tools/check-spec.sh "${check_args[@]}" 2>&1)
        status=$?
        if [ "$status" -eq 1 ] &&
           printf '%s\n' "$output" | grep -qF "FAIL: $label root must be an object"; then
          pass
        else
          fail "tane01 $label root $root_value gate=$gate must exit 1 with root diagnostic :: $output"
        fi
      done
    done
  done
}

test_tane01_spec_confirmation_roots
if python3 - <<'PY'
import copy
import json
import pathlib
import subprocess
import tempfile
import unittest


class SectionDefinitionTests(unittest.TestCase):
    def setUp(self):
        self.spec = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.json").read_text(encoding="utf-8"))
        self.spec["status"] = "draft"
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = pathlib.Path(temporary.name) / "spec.json"

    def run_check(self):
        self.path.write_text(json.dumps(self.spec), encoding="utf-8")
        return subprocess.run(
            ["bash", "tools/check-spec.sh", str(self.path), "--now", "2026-12-30T12:00:00+09:00"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )

    def test_tane04_duplicate_section_definition(self):
        deliverable = self.spec["deliverables"][0]
        deliverable["sections"].append(dict(deliverable["sections"][1], max_chars=10000))
        for due_event_id in ("application-deadline", None):
            with self.subTest(due_event_id=due_event_id):
                deliverable["due_event_id"] = due_event_id
                result = self.run_check()
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn("FAIL: duplicate section_id: deliverable-1/section-2", result.stdout)

    def test_tane04_section_scope(self):
        second = copy.deepcopy(self.spec["deliverables"][0])
        second["deliverable_id"] = "deliverable-2"
        self.spec["deliverables"].append(second)
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout)


unittest.main(verbosity=2)
PY
then
  pass
else
  fail "section definition checks must pass"
fi

test_tane06_confirmation_selection() {
  if python3 - "$RESOLVE_APPLICATION_TEST_DIR/tane06-selection" <<'PY'; then
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path("tools/lib").resolve()))
import check_spec

case_dir = pathlib.Path(sys.argv[1])
case_dir.mkdir()
spec_path = case_dir / "spec.json"
spec_path.write_bytes(pathlib.Path("tools/fixtures/spec/good-spec.json").read_bytes())
confirmation = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.confirmation.json").read_text(encoding="utf-8"))
confirmation["spec_path"] = spec_path.as_posix()
valid = json.dumps(confirmation)
confirmation["spec_version"] += 1
invalid = json.dumps(confirmation)
default_path = case_dir / "spec.confirmation.json"
explicit_path = case_dir / "approved.json"
now = check_spec.parse_now("2026-07-05T00:00:00+09:00")

for gate in (None, "confirm", "select"):
    default_path.write_text(invalid, encoding="utf-8")
    explicit_path.write_text(valid, encoding="utf-8")
    errors, _, _ = check_spec.check_spec(spec_path, gate=gate, now=now, confirmation_path=explicit_path)
    assert not errors, ("explicit confirmation must take precedence", gate, errors)
    errors, _, _ = check_spec.check_spec(spec_path, gate=gate, now=now)
    assert any("confirmation spec_version mismatch:" in error for error in errors), errors

    default_path.write_text(valid, encoding="utf-8")
    explicit_path.write_text(invalid, encoding="utf-8")
    errors, _, _ = check_spec.check_spec(spec_path, gate=gate, now=now)
    assert not errors, ("omitted confirmation must use the default", gate, errors)
    errors, _, _ = check_spec.check_spec(spec_path, gate=gate, now=now, confirmation_path=explicit_path)
    assert any("confirmation spec_version mismatch:" in error for error in errors), errors

    explicit_path.unlink()
    errors, _, _ = check_spec.check_spec(spec_path, gate=gate, now=now, confirmation_path=explicit_path)
    assert errors == [f"confirmation not found: {explicit_path}"], errors

default_path.unlink()
explicit_path.write_text(valid, encoding="utf-8")
errors, _, _ = check_spec.check_spec(spec_path)
assert errors == [f"confirmation not found: {default_path}"], errors

# Drafts may omit confirmation unless the caller explicitly selects a file.
spec = json.loads(spec_path.read_text(encoding="utf-8"))
spec["status"] = "draft"
spec_path.write_text(json.dumps(spec), encoding="utf-8")
errors, _, _ = check_spec.check_spec(spec_path)
assert not errors, errors
explicit_path.unlink()
errors, _, _ = check_spec.check_spec(spec_path, confirmation_path=explicit_path)
assert errors == [f"confirmation not found: {explicit_path}"], errors
PY
    pass
  else
    fail "tane06 confirmation selection must honor explicit paths and default naming"
  fi
}

test_tane06_confirmation_selection

echo "=== test-check-spec: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
