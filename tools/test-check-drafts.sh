#!/bin/bash
set -u

# The good fixture intentionally includes a draft whose frontmatter and preamble
# exceed the section's max_chars=30 limit. Its counted body is short enough, and
# a follow-up "## " section after the draft body must not be counted. The good
# spec also has an optional section with no draft; that must not emit a WARN.
# The partial fixture proves required ai_draftable coverage gaps remain WARNs.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
SPEC="tools/fixtures/spec/good-spec.json"

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

assert_check_drafts_passes() {
  local dir="$1"
  local output
  if output=$(bash tools/check-drafts.sh "$SPEC" "$dir" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^FAIL:'; then
      fail "check-drafts emitted FAIL while passing: $dir :: $output"
    elif printf '%s\n' "$output" | grep -q '^WARN:'; then
      fail "check-drafts emitted unexpected WARN while passing: $dir :: $output"
    elif ! printf '%s\n' "$output" | grep -q '^OK:'; then
      fail "check-drafts passing output should include OK: $dir :: $output"
    else
      pass
    fi
  else
    fail "check-drafts should pass: $dir :: $output"
  fi
}

assert_check_drafts_fails() {
  local dir="$1"
  local output status
  output=$(bash tools/check-drafts.sh "$SPEC" "$dir" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "check-drafts should fail: $dir :: $output"
    return
  fi
  if printf '%s\n' "$output" | grep -q '^FAIL:'; then
    pass
  else
    fail "check-drafts failure should include a FAIL line: $dir :: $output"
  fi
}

assert_check_drafts_warns_without_failing() {
  local dir="$1"
  local output status
  output=$(bash tools/check-drafts.sh "$SPEC" "$dir" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    fail "check-drafts should not fail on coverage WARN: $dir :: $output"
    return
  fi
  if printf '%s\n' "$output" | grep -q '^WARN:'; then
    pass
  else
    fail "check-drafts should emit WARN for partial coverage: $dir :: $output"
  fi
}

assert_duplicate_drafts_fail_with_both_paths() {
  local dir="tools/fixtures/drafts/drafts-duplicate"
  local first_path="$dir/section-1-duplicate.md"
  local second_path="$dir/section-1.md"
  local expected="duplicate draft for deliverable-1/section-1"
  local output status
  output=$(bash tools/check-drafts.sh "$SPEC" "$dir" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "duplicate drafts should fail: $dir :: $output"
    return
  fi
  if printf '%s\n' "$output" | grep -qF -- "FAIL: $expected" &&
     printf '%s\n' "$output" | grep -qF -- "$first_path" &&
     printf '%s\n' "$output" | grep -qF -- "$second_path"; then
    pass
  else
    fail "duplicate drafts failure should include both paths: $dir :: $output"
  fi
}

assert_check_drafts_passes "tools/fixtures/drafts/drafts-good"

for broken_dir in \
  tools/fixtures/drafts/drafts-overflow \
  tools/fixtures/drafts/drafts-no-frontmatter \
  tools/fixtures/drafts/drafts-unknown-ids \
  tools/fixtures/drafts/drafts-no-heading; do
  assert_check_drafts_fails "$broken_dir"
done

assert_check_drafts_warns_without_failing "tools/fixtures/drafts/drafts-partial"
assert_duplicate_drafts_fail_with_both_paths

echo "=== test-check-drafts: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
