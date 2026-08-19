#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
FIXTURES="tools/fixtures/quotes"
SPEC="$FIXTURES/quotes-fixture.json"
TMP_ROOT="${TMPDIR:-/tmp}/saita-check-quotes-$$"

trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT"

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

assert_passes() {
  local review="$1"
  local output
  if output=$(bash tools/check-quotes.sh "$SPEC" "$review" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^OK:' && ! printf '%s\n' "$output" | grep -q '^FAIL:'; then
      pass
    else
      fail "check-quotes passing output should include OK and no FAIL: $review :: $output"
    fi
  else
    fail "check-quotes should pass: $review :: $output"
  fi
}

assert_warns_with() {
  local review="$1" expected="$2"
  local output
  if output=$(bash tools/check-quotes.sh "$SPEC" "$review" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^OK:' &&
       printf '%s\n' "$output" | grep '^WARN:' | grep -qF -- "$expected"; then
      pass
    else
      fail "check-quotes should pass with WARN containing $expected: $review :: $output"
    fi
  else
    fail "check-quotes should not fail on WARN-only case: $review :: $output"
  fi
}

assert_fails_with() {
  local spec="$1" review="$2" expected="$3"
  local output status
  output=$(bash tools/check-quotes.sh "$spec" "$review" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "check-quotes should fail: $review :: $output"
    return
  fi
  if printf '%s\n' "$output" | grep -qF -- "$expected"; then
    pass
  else
    fail "check-quotes failure for $review should include $expected :: $output"
  fi
}

# Exact quotations resolve, and rows without a clause citation are skipped.
assert_passes "$FIXTURES/review-green.md"

# A table with no data rows is not an error, but it is reported.
assert_passes "$FIXTURES/review-no-rows.md"
assert_warns_with "$FIXTURES/review-no-rows.md" "no clause quotation rows found"

# Whitespace-only differences stay green with a WARN (same verbatim rule as check-spec).
assert_warns_with "$FIXTURES/review-whitespace.md" "matches clauses[].text only after whitespace normalization"

# Quotations that do not exist in clauses[].text are the fabrication-risk case.
assert_fails_with "$SPEC" "$FIXTURES/review-fabricated.md" "quoted_text not found in clauses[].text"
assert_fails_with "$SPEC" "$FIXTURES/review-unknown-clause.md" "unknown clause_id: clause-9"
assert_fails_with "$SPEC" "$FIXTURES/review-missing-quote.md" "quoted_text is missing for clause: clause-1"
assert_fails_with "$SPEC" "$FIXTURES/review-no-table.md" "clause-verifier table not found"

# A quotation without a clause_id cannot be traced back to the guidelines.
cat > "$TMP_ROOT/review-missing-clause-id.md" <<'EOF'
# review

## clause-verifier チェック

| 判断 | clause_id | quoted_text | clauses[].text 内の完全一致 | 判定 | リスク |
| --- | --- | --- | --- | --- | --- |
| 補助上限の確認 |  | 補助上限額は50万円 | 一致 | green | 低 |
EOF
assert_fails_with "$SPEC" "$TMP_ROOT/review-missing-clause-id.md" "clause_id is missing for quoted_text"

# Input errors are reported instead of silently passing.
assert_fails_with "$SPEC" "$TMP_ROOT/missing-review.md" "review not found"
assert_fails_with "$TMP_ROOT/missing-spec.json" "$FIXTURES/review-green.md" "spec not found"

printf 'not json\n' > "$TMP_ROOT/broken-spec.json"
assert_fails_with "$TMP_ROOT/broken-spec.json" "$FIXTURES/review-green.md" "spec invalid JSON"

printf '{"subsidy_id": "quotes-fixture"}\n' > "$TMP_ROOT/no-clauses-spec.json"
assert_fails_with "$TMP_ROOT/no-clauses-spec.json" "$FIXTURES/review-green.md" "spec has no clauses[]"

echo "=== test-check-quotes: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
