#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

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
assert_check_spec_passes "tools/fixtures/spec/gate-green-draft.json"
assert_check_spec_gate_passes "tools/fixtures/spec/gate-green-draft.json"
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

echo "=== test-check-spec: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
