#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

TEST_DIR="input/journey/.test-$$"
EVIL_TMP="${TMPDIR:-/tmp}/journey-map-evil-$$.html"
STALE_ID="journey-stale-$$"
mkdir -p "$TEST_DIR"
cleanup() {
  rm -rf "$TEST_DIR"
  rm -f "$EVIL_TMP"
  rm -rf "specs/$STALE_ID"
  rm -f "specs/$STALE_ID.json"
  rm -f "specs/$STALE_ID.confirmation.json"
}
trap cleanup EXIT

has_current_application_arg() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --current-application|--current-application=*)
        return 0
        ;;
    esac
  done
  return 1
}

run_journey_map() {
  local args=("$@")
  if ! has_current_application_arg "${args[@]}"; then
    args+=(--no-current-application)
  fi
  bash tools/journey-map.sh "${args[@]}"
}

assert_journey_passes() {
  local label="$1"
  shift
  local output
  if output=$(run_journey_map "$@" 2>&1); then
    if printf '%s\n' "$output" | grep -q '^OK:'; then
      pass
    else
      fail "$label should print OK :: $output"
    fi
  else
    fail "$label should pass :: $output"
  fi
}

assert_journey_fails_with() {
  local label="$1" expected="$2"
  shift 2
  local output
  if output=$(run_journey_map "$@" 2>&1); then
    fail "$label should fail :: $output"
  else
    if printf '%s\n' "$output" | grep -qF -- "$expected"; then
      pass
    else
      fail "$label should mention: $expected :: $output"
    fi
  fi
}

assert_journey_fails() {
  local label="$1"
  shift
  local output
  if output=$(run_journey_map "$@" 2>&1); then
    fail "$label should fail :: $output"
  else
    pass
  fi
}

assert_file_contains() {
  local label="$1" path="$2" expected="$3"
  if grep -qF -- "$expected" "$path"; then
    pass
  else
    fail "$label should contain: $expected"
  fi
}

assert_file_lacks() {
  local label="$1" path="$2" unexpected="$3"
  if grep -qF -- "$unexpected" "$path"; then
    fail "$label must not contain: $unexpected"
  else
    pass
  fi
}

write_confirmation_for_spec() {
  local spec_path="$1" confirmation_path="$2"
  python3 - "$spec_path" "$confirmation_path" <<'PY'
import hashlib
import json
import pathlib
import sys

sys.path.insert(0, "tools/lib")
import check_spec

spec_path = pathlib.Path(sys.argv[1])
confirmation_path = pathlib.Path(sys.argv[2])
spec = json.loads(spec_path.read_text(encoding="utf-8"))
items = []
for field_path in check_spec.required_confirmation_field_paths(spec):
    item = {
        "field_path": field_path,
        "source_clauses": ["clause-1"],
        "state": "confirmed",
        "note": f"Fixture confirmation for {field_path}.",
    }
    if field_path.startswith("eligibility.rules."):
        item["predicate_state"] = "not_encodable"
    items.append(item)
confirmation = {
    "spec_path": spec_path.as_posix(),
    "spec_version": spec.get("spec_version"),
    "spec_sha256": hashlib.sha256(spec_path.read_bytes()).hexdigest(),
    "confirmed_by": "applicant",
    "confirmed_at": "2026-07-25T00:00:00+09:00",
    "items": items,
}
confirmation_path.write_text(
    json.dumps(confirmation, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

write_xss_spec() {
  local spec_path="$1"
  python3 - tools/fixtures/spec/good-spec.json "$spec_path" <<'PY'
import copy
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
spec["subsidy_id"] = "fixture-xss"
spec["name"] = "Fixture <script>alert('name')</script> subsidy"
spec["round"] = "第1回 <script>alert('round')</script>"
base = spec["deliverables"][0]
external = copy.deepcopy(base)
external.update(
    {
        "deliverable_id": "evil-doc",
        "name": "<script>alert('deliverable')</script>証明書",
        "type": "document",
        "produced_by": "external",
        "issuer": "\"><img src=x onerror=alert('issuer')>窓口",
        "sections": [],
    }
)
draft = copy.deepcopy(base)
draft.update(
    {
        "deliverable_id": "evil-draft",
        "name": "計画書<script>alert('draft')</script>",
        "type": "form_input",
        "produced_by": "ai_draftable",
        "issuer": None,
    }
)
spec["deliverables"] = [external, draft]
output_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  write_confirmation_for_spec "$spec_path" "${spec_path%.json}.confirmation.json"
}

write_post_cycle_spec() {
  local spec_path="$1"
  python3 - tools/fixtures/spec/good-spec.json "$spec_path" <<'PY'
import copy
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
spec["subsidy_id"] = "post-cycle"
spec["name"] = "採択後循環 fixture"
spec["round"] = None
base = spec["deliverables"][0]
post_a = copy.deepcopy(base)
post_a.update(
    {
        "deliverable_id": "post-a",
        "name": "採択後提出物A",
        "phase": "post_adoption",
        "produced_by": "human_only",
        "due_event_id": None,
        "sections": [],
        "depends_on": ["post-b"],
    }
)
post_b = copy.deepcopy(post_a)
post_b.update(
    {
        "deliverable_id": "post-b",
        "name": "採択後提出物B",
        "depends_on": ["post-a"],
    }
)
spec["deliverables"] = [post_a, post_b]
output_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  write_confirmation_for_spec "$spec_path" "${spec_path%.json}.confirmation.json"
}

# --- derive on the bundled spec -------------------------------------------

SPEC="specs/jizokuka-20/jizokuka-20.json"
FLOW="$TEST_DIR/flow.json"
HTML="$TEST_DIR/journey.html"
JIZOKUKA_FLOW_SHA256="95886656945861ee6e316f619ec2570700203c30ff8d7b659eae87ef89f2b9cd"

assert_journey_passes "derive bundled spec" derive "$SPEC" --out "$FLOW"

if [ -f "$FLOW" ]; then
  if python3 - "$FLOW" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
steps = flow["steps"]
by_id = {step["step_id"]: step for step in steps}


def require(condition, message):
    if not condition:
        raise SystemExit(message)


yoshiki = by_id.get("sp-yoshiki-4")
require(yoshiki is not None, "yoshiki-4 step missing")
require(yoshiki["origin"] == "derived", "yoshiki-4 must be origin=derived")
require(yoshiki["lane"] == "external", "yoshiki-4 must be on the external lane")
require("yoshiki-4" in yoshiki["deliverable_ids"], "yoshiki-4 must cite its deliverable")
require(yoshiki["deadline"] == "2026-12-04", "yoshiki-4 deadline must come from its due event")

post_deliverable_steps = [
    step for step in steps if step["zone"] == "post_adoption" and step["deliverable_ids"]
]
require(len(post_deliverable_steps) == 3, "post-adoption deliverable steps must be 3")
post_ids = {step["deliverable_ids"][0] for step in post_deliverable_steps}
require(post_ids == {"mitsumori", "jisseki-hokoku", "koka-hokoku"}, f"unexpected post ids: {post_ids}")

require("ev-project-period" in by_id, "project period milestone missing")
require(by_id["ev-project-period"]["zone"] == "post_adoption", "project period must be post-adoption")

gbiz = by_id.get("sp-gbiz-id")
require(gbiz is not None, "gbiz-id preparation step missing")
require(gbiz["zone"] == "application", "gbiz-id must be in application zone")

submit = by_id["kit-submit"]
require("denshi-shinsei" in submit["deliverable_ids"], "submit must absorb denshi-shinsei")
require(submit["deadline"] == "2026-12-15", "submit must show the application deadline")

draft = by_id["kit-draft"]
require(
    set(draft["deliverable_ids"]) == {"keiei-keikaku", "hojo-jigyo-keikaku"},
    "draft must absorb ai-draftable deliverables",
)

order = [step["step_id"] for step in steps]
require(
    order.index("sp-gbiz-id") < order.index("kit-get-guidelines"),
    "preparation steps must come before getting the guidelines",
)
require(
    order.index("kit-review") < order.index("sp-yoshiki-4") < order.index("kit-finalize"),
    "external steps must sit between review and finalize",
)
post_order = [step["step_id"] for step in steps if step["zone"] == "post_adoption"]
require(
    post_order == ["sp-mitsumori", "ev-project-period", "sp-jisseki-hokoku", "sp-koka-hokoku"],
    f"post-adoption order must follow dates: {post_order}",
)
PY
    pass
  else
    fail "derived flow structure check"
  fi
else
  fail "derived flow file missing"
fi

if python3 - "$FLOW" "$JIZOKUKA_FLOW_SHA256" <<'PY'; then
import hashlib
import pathlib
import sys

flow_path = pathlib.Path(sys.argv[1])
expected = sys.argv[2]
actual = hashlib.sha256(flow_path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"expected {expected}, got {actual}")
PY
  pass
else
  fail "jizokuka-20 derive output must stay byte-stable"
fi

# --- determinism -----------------------------------------------------------

bash tools/journey-map.sh derive "$SPEC" --out "$TEST_DIR/flow-again.json" --no-current-application >/dev/null 2>&1
if cmp -s "$FLOW" "$TEST_DIR/flow-again.json"; then
  pass
else
  fail "derive must be deterministic (two runs differ)"
fi

# --- render on the bundled spec -------------------------------------------

assert_journey_passes "render bundled flow" render "$FLOW" --out "$HTML"

for token in "経営者（あなた）" "Claude Code との作業" "外部の窓口" "2026-12-15" "2026-12-04" "stroke-dasharray" "採択後" "提出物ではありません" "商工会・商工会議所"; do
  assert_file_contains "rendered journey html" "$HTML" "$token"
done

for forbidden in "[要確認]" "input/" "subsidy_id" "spec_path" "/setup" "/journey-map" "/draft-section" "current-application"; do
  assert_file_lacks "rendered journey html (kit-internal terms)" "$HTML" "$forbidden"
done

# --- absorbed intermediate due milestones ----------------------------------

MID_SPEC="tools/fixtures/spec/fixture-journey-mid-deadline.json"
MID_FLOW="$TEST_DIR/mid-deadline-flow.json"
MID_HTML="$TEST_DIR/mid-deadline.html"

assert_journey_passes "derive absorbed intermediate due fixture" derive "$MID_SPEC" --out "$MID_FLOW"
if [ -f "$MID_FLOW" ]; then
  if python3 - "$MID_FLOW" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
steps = flow["steps"]
by_id = {step["step_id"]: step for step in steps}
order = [step["step_id"] for step in steps]


def require(condition, message):
    if not condition:
        raise SystemExit(message)


draft_due = by_id.get("ev-draft-interim")
submit_due = by_id.get("ev-submit-interim")
require(draft_due is not None, "draft absorbed due milestone missing")
require(submit_due is not None, "submit absorbed due milestone missing")
require(draft_due["origin"] == "derived", "draft due milestone must be derived")
require(draft_due["kind"] == "milestone", "draft due milestone must be milestone")
require(draft_due["deadline"] == "2026-11-20", "draft due milestone deadline mismatch")
require(draft_due["deadline_time"] == "17:00", "draft due milestone time mismatch")
require(draft_due["deliverable_ids"] == ["draft-plan"], "draft due deliverables mismatch")
require(draft_due["event_ids"] == ["draft-interim"], "draft due event_ids mismatch")
require(submit_due["origin"] == "derived", "submit due milestone must be derived")
require(submit_due["kind"] == "milestone", "submit due milestone must be milestone")
require(submit_due["deadline"] == "2026-12-10", "submit due milestone deadline mismatch")
require(submit_due["deadline_time"] == "18:00", "submit due milestone time mismatch")
require(submit_due["deliverable_ids"] == ["portal-procedure"], "submit due deliverables mismatch")
require(submit_due["event_ids"] == ["submit-interim"], "submit due event_ids mismatch")
require(
    order.index("kit-draft") + 1 == order.index("ev-draft-interim"),
    "draft due milestone must be immediately after kit-draft",
)
require(
    order.index("ev-submit-interim") + 1 == order.index("kit-submit"),
    "submit due milestone must be immediately before kit-submit",
)
require(by_id["kit-draft"]["next"] == ["ev-draft-interim"], "kit-draft next must enter draft due")
require(draft_due["next"] == ["kit-review"], "draft due next must preserve draft tail")
require(by_id["kit-finalize"]["next"] == ["ev-submit-interim"], "finalize next must enter submit due")
require(submit_due["next"] == ["kit-submit"], "submit due next must enter submit")
PY
    pass
  else
    fail "absorbed intermediate due milestone structure check"
  fi
else
  fail "absorbed intermediate due flow file missing"
fi

assert_journey_passes "render absorbed intermediate due fixture" render "$MID_FLOW" --out "$MID_HTML"
for token in "2026-11-20" "2026-12-10"; do
  assert_file_contains "absorbed intermediate due html" "$MID_HTML" "$token"
done

HIDDEN_DATE_FLOW="$TEST_DIR/hidden-date-flow.json"
python3 - "$MID_FLOW" "$HIDDEN_DATE_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "ev-draft-interim":
        step["deadline"] = None
        step["deadline_time"] = None
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with "render rejects dated event hidden from deadline" "without displaying a deadline" \
  render "$HIDDEN_DATE_FLOW" --out "$TEST_DIR/hidden-date.html"

# --- confirmed spec contract ----------------------------------------------

assert_journey_fails_with "derive refuses missing required spec keys" "missing required key: $.spec_version" \
  derive tools/fixtures/spec/missing-required-key.json --out "$TEST_DIR/missing-key-flow.json"
if [ -e "$TEST_DIR/missing-key-flow.json" ]; then
  fail "missing-key refusal must not write a flow"
else
  pass
fi

assert_journey_fails_with "derive refuses stale confirmation sha" "confirmation spec_sha256 mismatch" \
  derive tools/fixtures/spec/stale-sha.json --out "$TEST_DIR/stale-sha-flow.json"
if [ -e "$TEST_DIR/stale-sha-flow.json" ]; then
  fail "stale-sha refusal must not write a flow"
else
  pass
fi

assert_journey_fails_with "derive refuses draft spec" "status must be confirmed" \
  derive tools/fixtures/spec/gate-green-draft.json --out "$TEST_DIR/draft-flow.json"
if [ -e "$TEST_DIR/draft-flow.json" ]; then
  fail "draft spec refusal must not write a flow"
else
  pass
fi

CURRENT_DRAFT="$TEST_DIR/current-draft.json"
python3 - "$CURRENT_DRAFT" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.write_text(
    json.dumps(
        {
            "subsidy_id": "fixture-good",
            "spec_path": "tools/fixtures/spec/good-spec.json",
            "spec_version": 1,
            "chosen_funding": None,
            "state": "spec_draft",
            "updated_at": "2026-07-25T00:00:00+09:00",
        },
        ensure_ascii=False,
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY
assert_journey_fails_with "derive refuses unconfirmed current application state" \
  "current application state must be spec_confirmed" \
  derive tools/fixtures/spec/good-spec.json --current-application "$CURRENT_DRAFT" \
  --out "$TEST_DIR/current-draft-flow.json"
if [ -e "$TEST_DIR/current-draft-flow.json" ]; then
  fail "current-draft refusal must not write a flow"
else
  pass
fi

assert_journey_fails "derive rejects conflicting current application flags" \
  derive tools/fixtures/spec/good-spec.json --current-application "$CURRENT_DRAFT" \
  --no-current-application --out "$TEST_DIR/current-conflict-flow.json"
if [ -e "$TEST_DIR/current-conflict-flow.json" ]; then
  fail "current-application conflict refusal must not write a flow"
else
  pass
fi

# --- resolver stale flat path ---------------------------------------------

mkdir -p "specs/$STALE_ID"
CANONICAL_SPEC="specs/$STALE_ID/$STALE_ID.json"
STALE_FLAT_SPEC="specs/$STALE_ID.json"
python3 - "$STALE_ID" "$CANONICAL_SPEC" "$STALE_FLAT_SPEC" "specs/$STALE_ID/pack.json" <<'PY'
import json
import pathlib
import sys

subsidy_id, canonical_path, stale_path, pack_path = sys.argv[1:5]
canonical_path = pathlib.Path(canonical_path)
stale_path = pathlib.Path(stale_path)
pack_path = pathlib.Path(pack_path)
base = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.json").read_text(encoding="utf-8"))
canonical = dict(base)
canonical["subsidy_id"] = subsidy_id
canonical["name"] = "Canonical packed journey fixture"
stale = dict(base)
stale["subsidy_id"] = subsidy_id
stale["name"] = "Stale flat journey fixture"
canonical_path.write_text(json.dumps(canonical, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
stale_path.write_text(json.dumps(stale, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
pack_path.write_text(
    json.dumps({"subsidy_id": subsidy_id, "spec": {"path": f"{subsidy_id}.json"}}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
write_confirmation_for_spec "$CANONICAL_SPEC" "specs/$STALE_ID/$STALE_ID.confirmation.json"
write_confirmation_for_spec "$STALE_FLAT_SPEC" "specs/$STALE_ID.confirmation.json"

STALE_FLOW="$TEST_DIR/stale-resolver-flow.json"
assert_journey_passes "derive ignores stale bundled flat path" \
  derive "$STALE_FLAT_SPEC" --out "$STALE_FLOW"
if [ -f "$STALE_FLOW" ]; then
  if python3 - "$STALE_FLOW" "$CANONICAL_SPEC" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
canonical_spec = sys.argv[2]
if flow.get("subsidy_name") != "Canonical packed journey fixture":
    raise SystemExit("canonical packed spec name was not used")
if flow.get("spec_path") != canonical_spec:
    raise SystemExit(f"unexpected flow spec_path: {flow.get('spec_path')}")
PY
    pass
  else
    fail "stale flat path must resolve to packed canonical spec"
  fi
else
  fail "stale resolver flow missing"
fi

CURRENT_STALE="$TEST_DIR/current-stale.json"
python3 - "$CURRENT_STALE" "$STALE_ID" "$STALE_FLAT_SPEC" <<'PY'
import json
import pathlib
import sys

path, subsidy_id, stale_spec_path = sys.argv[1:4]
pathlib.Path(path).write_text(
    json.dumps(
        {
            "subsidy_id": subsidy_id,
            "spec_path": stale_spec_path,
            "spec_version": 1,
            "chosen_funding": None,
            "state": "spec_confirmed",
            "updated_at": "2026-07-25T00:00:00+09:00",
        },
        ensure_ascii=False,
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY

STALE_APP_FLOW="$TEST_DIR/stale-current-application-flow.json"
assert_journey_passes "derive resolves stale current-application spec_path" \
  derive "$CANONICAL_SPEC" --current-application "$CURRENT_STALE" --out "$STALE_APP_FLOW"
if [ -f "$STALE_APP_FLOW" ]; then
  if python3 - "$STALE_APP_FLOW" "$CANONICAL_SPEC" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
if flow.get("spec_path") != sys.argv[2]:
    raise SystemExit(f"unexpected flow spec_path: {flow.get('spec_path')}")
PY
    pass
  else
    fail "stale current-application path must resolve to packed canonical spec"
  fi
else
  fail "stale current-application resolver flow missing"
fi

# --- output path confinement ----------------------------------------------

rm -f "$EVIL_TMP"
assert_journey_fails_with "derive refuses /tmp output" "must be under input/journey/" \
  derive "$SPEC" --out "$EVIL_TMP"
if [ -e "$EVIL_TMP" ]; then
  fail "derive refused /tmp output must not create $EVIL_TMP"
else
  pass
fi
assert_journey_fails_with "render refuses /tmp output" "must be under input/journey/" \
  render "$FLOW" --out "$EVIL_TMP"
if [ -e "$EVIL_TMP" ]; then
  fail "render refused /tmp output must not create $EVIL_TMP"
else
  pass
fi

CLAUDE_MD_SHA_BEFORE="$(python3 - <<'PY'
import hashlib
from pathlib import Path

print(hashlib.sha256(Path("CLAUDE.md").read_bytes()).hexdigest())
PY
)"
assert_journey_fails_with "derive refuses repo root output" "must be under input/journey/" \
  derive "$SPEC" --out CLAUDE.md
assert_journey_fails_with "render refuses repo root output" "must be under input/journey/" \
  render "$FLOW" --out CLAUDE.md
assert_journey_fails_with "derive refuses relative breakout output" "must be under input/journey/" \
  derive "$SPEC" --out input/journey/../../CLAUDE.md
CLAUDE_MD_SHA_AFTER="$(python3 - <<'PY'
import hashlib
from pathlib import Path

print(hashlib.sha256(Path("CLAUDE.md").read_bytes()).hexdigest())
PY
)"
if [ "$CLAUDE_MD_SHA_BEFORE" = "$CLAUDE_MD_SHA_AFTER" ]; then
  pass
else
  fail "refused root output must not modify CLAUDE.md"
fi

# --- protected flow edits --------------------------------------------------

METADATA_EDIT_FLOW="$TEST_DIR/metadata-edit-flow.json"
python3 - "$FLOW" "$METADATA_EDIT_FLOW" <<'PY'
import json
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
flow = json.load(open(source_path, encoding="utf-8"))
flow["subsidy_name"] = "AIが書き換えた補助金名"
json.dump(flow, open(output_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
assert_journey_fails_with "render rejects protected subsidy name edit" \
  "does not match the spec" \
  render "$METADATA_EDIT_FLOW" --out "$TEST_DIR/metadata-edit.html"

AI_INSERT_FLOW="$TEST_DIR/ai-insert-flow.json"
python3 - "$FLOW" "$AI_INSERT_FLOW" <<'PY'
import json
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
flow = json.load(open(source_path, encoding="utf-8"))
steps = flow["steps"]
by_id = {step["step_id"]: step for step in steps}

ai_step = {
    "step_id": "ai-submit-precheck",
    "origin": "ai",
    "base_step_id": None,
    "label": "提出前の注意点を確認する",
    "description": "公募要領の提出条件に沿って、見落としがないかを確認します。",
    "lane": "claude",
    "zone": "application",
    "kind": "process",
    "human_gate": False,
    "deliverable_ids": [],
    "event_ids": [],
    "clause_ids": ["eligibility-001"],
    "deadline": None,
    "deadline_time": None,
    "issuer": None,
    "next": ["kit-submit"],
    "branches": [],
}
by_id["kit-finalize"]["next"] = [ai_step["step_id"]]
insert_at = next(index for index, step in enumerate(steps) if step["step_id"] == "kit-submit")
steps.insert(insert_at, ai_step)
json.dump(flow, open(output_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
assert_journey_passes "render allows ai insertion on existing edge" \
  render "$AI_INSERT_FLOW" --out "$TEST_DIR/ai-insert.html"

AI_MULTI_NEXT_FLOW="$TEST_DIR/ai-multi-next-flow.json"
python3 - "$AI_INSERT_FLOW" "$AI_MULTI_NEXT_FLOW" <<'PY'
import json
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
flow = json.load(open(source_path, encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "ai-submit-precheck":
        step["next"] = ["kit-submit", "kit-result"]
json.dump(flow, open(output_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
assert_journey_fails_with "render rejects ai insertion with multiple exits" \
  "single-exit process/milestone insertion" \
  render "$AI_MULTI_NEXT_FLOW" --out "$TEST_DIR/ai-multi-next.html"

NO_SUBMIT_FLOW="$TEST_DIR/no-submit-flow.json"
python3 - "$FLOW" "$NO_SUBMIT_FLOW" <<'PY'
import json
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
flow = json.load(open(source_path, encoding="utf-8"))
flow["steps"] = [step for step in flow["steps"] if step["step_id"] != "kit-submit"]
for step in flow["steps"]:
    if step["step_id"] == "kit-finalize":
        step["next"] = ["kit-result"]
json.dump(flow, open(output_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
assert_journey_fails_with "render rejects required step removal" "required and cannot be removed" \
  render "$NO_SUBMIT_FLOW" --out "$TEST_DIR/no-submit.html"

RELABEL_FLOW="$TEST_DIR/relabel-flow.json"
python3 - "$FLOW" "$RELABEL_FLOW" <<'PY'
import json
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
flow = json.load(open(source_path, encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "sp-yoshiki-4":
        step["label"] = "AIが書き換えた様式4ラベル"
json.dump(flow, open(output_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
assert_journey_fails_with "render rejects protected label edit" "protected field label" \
  render "$RELABEL_FLOW" --out "$TEST_DIR/relabel.html"

DESCRIPTION_EDIT_FLOW="$TEST_DIR/description-edit-flow.json"
python3 - "$FLOW" "$DESCRIPTION_EDIT_FLOW" <<'PY'
import json
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
flow = json.load(open(source_path, encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "sp-yoshiki-4":
        step["description"] = "AIが根拠なしに書き換えた説明"
json.dump(flow, open(output_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
assert_journey_fails_with "render rejects protected description edit" \
  "protected field description" \
  render "$DESCRIPTION_EDIT_FLOW" --out "$TEST_DIR/description-edit.html"

EXTRA_TRANSITION_FLOW="$TEST_DIR/extra-transition-flow.json"
python3 - "$FLOW" "$EXTRA_TRANSITION_FLOW" <<'PY'
import json
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
flow = json.load(open(source_path, encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "kit-finalize":
        step["next"] = ["kit-submit", "kit-result"]
json.dump(flow, open(output_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
assert_journey_fails_with "render rejects extra protected transition" \
  "extra or missing transitions" \
  render "$EXTRA_TRANSITION_FLOW" --out "$TEST_DIR/extra-transition.html"

BYPASS_FLOW="$TEST_DIR/bypass-flow.json"
python3 - "$FLOW" "$BYPASS_FLOW" <<'PY'
import json
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
flow = json.load(open(source_path, encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "kit-finalize":
        step["next"] = ["kit-result"]
json.dump(flow, open(output_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
assert_journey_fails "render rejects submit bypass with all steps retained" \
  render "$BYPASS_FLOW" --out "$TEST_DIR/bypass.html"

# --- validation gate refusals ---------------------------------------------

assert_journey_fails_with "missing deliverable reference" "unknown deliverable" \
  render tools/fixtures/journey/missing-ref-flow.json --out "$TEST_DIR/refused-1.html"
assert_journey_fails_with "uncited ai step" "clause" \
  render tools/fixtures/journey/ai-no-clause-flow.json --out "$TEST_DIR/refused-2.html"
assert_journey_fails_with "cyclic flow" "cycle" \
  render tools/fixtures/journey/cycle-flow.json --out "$TEST_DIR/refused-3.html"
assert_journey_fails_with "schema violation" "schema violation" \
  render tools/fixtures/journey/schema-bad-flow.json --out "$TEST_DIR/refused-4.html"

for refused in refused-1 refused-2 refused-3 refused-4; do
  if [ -e "$TEST_DIR/$refused.html" ]; then
    fail "refused render must not write $refused.html"
  else
    pass
  fi
done

# --- escaping --------------------------------------------------------------

XSS_SPEC="$TEST_DIR/xss-spec.json"
XSS_FLOW="$TEST_DIR/xss-flow.json"
XSS_HTML="$TEST_DIR/xss-journey.html"
write_xss_spec "$XSS_SPEC"
assert_journey_passes "derive xss spec" derive "$XSS_SPEC" --out "$XSS_FLOW"
assert_journey_passes "render xss flow" render "$XSS_FLOW" --out "$XSS_HTML" \
  --spec "$XSS_SPEC"

if [ -f "$XSS_HTML" ]; then
  assert_file_lacks "xss journey html" "$XSS_HTML" "<script>alert"
  assert_file_lacks "xss journey html" "$XSS_HTML" "<img src=x"
  assert_file_contains "xss journey html" "$XSS_HTML" "&lt;script&gt;"
else
  fail "xss journey html missing"
fi

# --- spec status gate ------------------------------------------------------

DRAFT_XSS_SPEC="$TEST_DIR/xss-draft-spec.json"
python3 - "$XSS_SPEC" "$DRAFT_XSS_SPEC" <<'PY'
import json
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
spec = json.load(open(source_path, encoding="utf-8"))
spec["status"] = "draft"
json.dump(spec, open(output_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
assert_journey_fails_with "derive refuses draft spec" "status must be confirmed" \
  derive "$DRAFT_XSS_SPEC" --out "$TEST_DIR/draft-xss-flow.json"
if [ -e "$TEST_DIR/draft-xss-flow.json" ]; then
  fail "draft spec refusal must not write a flow"
else
  pass
fi
assert_journey_fails_with "render refuses draft spec" "status must be confirmed" \
  render "$XSS_FLOW" --out "$TEST_DIR/draft-xss.html" --spec "$DRAFT_XSS_SPEC"
if [ -e "$TEST_DIR/draft-xss.html" ]; then
  fail "draft spec render refusal must not write html"
else
  pass
fi

POST_CYCLE_SPEC="$TEST_DIR/post-cycle-spec.json"
write_post_cycle_spec "$POST_CYCLE_SPEC"
assert_journey_fails_with "derive rejects post-adoption depends_on cycle" \
  "depends_on cycle" \
  derive "$POST_CYCLE_SPEC" --out "$TEST_DIR/post-cycle-flow.json"
if [ -e "$TEST_DIR/post-cycle-flow.json" ]; then
  fail "post-adoption cycle refusal must not write a flow"
else
  pass
fi

echo "PASS: $PASS FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
