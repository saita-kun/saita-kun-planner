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

write_relative_deadline_spec() {
  local spec_path="$1"
  python3 - tools/fixtures/spec/good-spec.json "$spec_path" <<'PY'
import copy
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
spec["subsidy_id"] = "relative-deadline"
spec["name"] = "相対期限 fixture"
spec["round"] = None

application_deadline = copy.deepcopy(spec["schedule"][0])
application_deadline.update(
    {
        "date": None,
        "starts_at": None,
        "ends_at": None,
        "relative": {
            "anchor": "受付開始日",
            "offset_days": 14,
            "direction": "within_after",
        },
        "time": "17:00",
    }
)
long_anchor = (
    "補助事業が完了した日または補助対象経費の支払いが完了した日の"
    "いずれか遅い日として公式要項で定める基準日"
)
assert len(long_anchor) >= 40


def event(
    event_id,
    name,
    event_kind,
    phase,
    *,
    date=None,
    starts_at=None,
    relative=None,
    time=None,
):
    value = copy.deepcopy(application_deadline)
    value.update(
        {
            "event_id": event_id,
            "name": name,
            "event_kind": event_kind,
            "date": date,
            "starts_at": starts_at,
            "ends_at": None,
            "relative": relative,
            "time": time,
            "phase": phase,
        }
    )
    return value


spec["schedule"] = [
    application_deadline,
    event(
        "post-report-after",
        "実績報告期限",
        "report_deadline",
        "post_adoption",
        relative={
            "anchor": long_anchor,
            "offset_days": 30,
            "direction": "within_after",
        },
        time="18:00",
    ),
    event(
        "project-period-before",
        "事業完了期限",
        "project_period",
        "post_adoption",
        relative={
            "anchor": "実績報告期限",
            "offset_days": 30,
            "direction": "before",
        },
        time="16:45",
    ),
    event(
        "post-unknown-direction",
        "前後未確認の報告期限",
        "report_deadline",
        "post_adoption",
        relative={
            "anchor": "受付完了日",
            "offset_days": 45,
            "direction": None,
        },
    ),
    event(
        "post-open-after",
        "日数未確認の報告期限",
        "report_deadline",
        "post_adoption",
        relative={
            "anchor": "交付決定日",
            "offset_days": None,
            "direction": "within_after",
        },
    ),
    event(
        "project-period-open-before",
        "日数未確認の事業完了期限",
        "project_period",
        "post_adoption",
        relative={
            "anchor": "実績報告期限",
            "offset_days": None,
            "direction": "before",
        },
    ),
    event(
        "draft-anchor",
        "計画書準備の起点",
        "other",
        "application",
        relative={
            "anchor": "採択発表日",
            "offset_days": None,
            "direction": None,
        },
    ),
    event(
        "starts-only",
        "受付開始日",
        "other",
        "application",
        starts_at="2027-04-01",
    ),
    event(
        "application-deadline-late",
        "別手続の申請期限",
        "other",
        "application",
        relative={
            "anchor": "受付開始日",
            "offset_days": 14,
            "direction": "within_after",
        },
        time="18:00",
    ),
    event(
        "post-absolute",
        "絶対日付の報告期限",
        "report_deadline",
        "post_adoption",
        date="2027-03-31",
        relative={
            "anchor": "交付決定日",
            "offset_days": 90,
            "direction": "within_after",
        },
    ),
]

base = spec["deliverables"][0]
draft = copy.deepcopy(base)
draft.update(
    {
        "deliverable_id": "draft-plan",
        "name": "事業計画書",
        "due_event_id": "draft-anchor",
    }
)
draft_application = copy.deepcopy(draft)
draft_application.update(
    {
        "deliverable_id": "draft-application",
        "name": "申請書",
        "due_event_id": "application-deadline",
    }
)
post_after = copy.deepcopy(base)
post_after.update(
    {
        "deliverable_id": "post-report-after",
        "name": "実績報告書",
        "phase": "post_adoption",
        "produced_by": "human_only",
        "due_event_id": "post-report-after",
        "sections": [],
    }
)
post_absolute = copy.deepcopy(post_after)
post_absolute.update(
    {
        "deliverable_id": "post-absolute",
        "name": "年度報告書",
        "due_event_id": "post-absolute",
    }
)
post_unknown_direction = copy.deepcopy(post_after)
post_unknown_direction.update(
    {
        "deliverable_id": "post-unknown-direction",
        "name": "前後未確認の報告書",
        "due_event_id": "post-unknown-direction",
    }
)
post_open_after = copy.deepcopy(post_after)
post_open_after.update(
    {
        "deliverable_id": "post-open-after",
        "name": "日数未確認の報告書",
        "due_event_id": "post-open-after",
    }
)
spec["deliverables"] = [
    draft,
    draft_application,
    post_after,
    post_unknown_direction,
    post_open_after,
    post_absolute,
]
output_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  write_confirmation_for_spec "$spec_path" "${spec_path%.json}.confirmation.json"
}

# --- derive on the bundled spec -------------------------------------------

SPEC="specs/jizokuka-20/jizokuka-20.json"
FLOW="$TEST_DIR/flow.json"
HTML="$TEST_DIR/journey.html"
JIZOKUKA_FLOW_SHA256="f9df4f2fd97dbe2fd8fb81e344cd7ebe8ca62856440bb9b928a857e0da774143"

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
kakunin_steps = [
    step for step in steps if "kakunin-jiko" in step.get("deliverable_ids", [])
]
require(
    len(kakunin_steps) == 1
    and kakunin_steps[0]["zone"] == "application"
    and order.index("kit-review")
    < order.index(kakunin_steps[0]["step_id"])
    < order.index("kit-finalize"),
    "kakunin-jiko must sit in the application zone between review and finalize",
)
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

# --- post-submit human-only procedures ------------------------------------

POST_SUBMIT_SPEC="tools/fixtures/spec/fixture-journey-post-submit.json"
POST_SUBMIT_FLOW="$TEST_DIR/post-submit-flow.json"
POST_SUBMIT_HTML="$TEST_DIR/post-submit.html"

assert_journey_passes "derive post-submit procedure fixture" \
  derive "$POST_SUBMIT_SPEC" --out "$POST_SUBMIT_FLOW"
if [ -f "$POST_SUBMIT_FLOW" ]; then
  if python3 - "$POST_SUBMIT_FLOW" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
by_id = {step["step_id"]: step for step in flow["steps"]}
order = [step["step_id"] for step in flow["steps"]]


def require(condition, message):
    if not condition:
        raise SystemExit(message)


require(
    by_id["kit-finalize"]["next"] == ["ev-submit-interim"],
    "finalize next must enter submit due milestone",
)
require(
    by_id["ev-submit-interim"]["next"] == ["kit-submit"],
    "submit due milestone next must enter submit",
)
require(
    by_id["kit-submit"]["next"] == ["sp-oral-exam"],
    "submit next must enter the first post-submit procedure",
)
oral_exam = by_id.get("sp-oral-exam")
extra_docs = by_id.get("sp-extra-docs")
require(oral_exam is not None, "post-submit oral exam step missing")
require(extra_docs is not None, "post-submit extra documents step missing")
require(
    oral_exam["next"] == ["sp-extra-docs"],
    "oral exam next must enter extra documents",
)
require(extra_docs["next"] == ["kit-result"], "extra documents next must enter result")
require(by_id["kit-result"]["next"] == [], "result next must remain empty")
require(
    order.index("sp-oral-exam") < order.index("sp-extra-docs"),
    "flow steps must put the dependency before the dependent",
)
for step, label in ((oral_exam, "oral exam"), (extra_docs, "extra documents")):
    require(step["zone"] == "application", f"{label} must stay in application zone")
    require(step["lane"] == "owner", f"{label} must be on the owner lane")
    require(step["origin"] == "derived", f"{label} must be derived")
require(
    oral_exam["event_ids"] == ["oral-exam-window"],
    "oral exam event_ids mismatch",
)
require(
    extra_docs["event_ids"] == ["extra-docs-window"],
    "extra documents event_ids mismatch",
)
require(
    by_id["kit-submit"]["deliverable_ids"] == ["portal-procedure"],
    "submit must absorb only the portal procedure",
)
require(
    "ev-oral-exam-window" not in by_id,
    "oral exam due event must not also become a milestone",
)
require(
    "ev-extra-docs-window" not in by_id,
    "extra documents due event must not also become a milestone",
)
require(
    by_id["kit-env-setup"]["next"] == ["sp-account-prep"],
    "account preparation must remain immediately after environment setup",
)
PY
    pass
  else
    fail "post-submit procedure structure check"
  fi
else
  fail "post-submit procedure flow file missing"
fi

assert_journey_passes "render post-submit procedure fixture" \
  render "$POST_SUBMIT_FLOW" --out "$POST_SUBMIT_HTML"

MULTIPLE_APPLICATION_DEADLINES_SPEC="$TEST_DIR/multiple-application-deadlines-spec.json"
MULTIPLE_APPLICATION_DEADLINES_FLOW="$TEST_DIR/multiple-application-deadlines-flow.json"
python3 - "$POST_SUBMIT_SPEC" "$MULTIPLE_APPLICATION_DEADLINES_SPEC" <<'PY'
import copy
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
spec["subsidy_id"] = "fixture-journey-multiple-application-deadlines"
spec["name"] = "Journey map multiple application deadlines fixture"
application_deadline = next(
    event
    for event in spec["schedule"]
    if event.get("event_kind") == "application_deadline"
)
application_deadline["date"] = "2026-12-01"
late_application_deadline = copy.deepcopy(application_deadline)
late_application_deadline.update(
    {
        "event_id": "application-deadline-late",
        "name": "最終申請締切",
        "date": "2027-03-31",
    }
)
spec["schedule"].append(late_application_deadline)
for event in spec["schedule"]:
    if event.get("event_id") == "oral-exam-window":
        event["date"] = "2027-01-15"
        break
output_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
write_confirmation_for_spec \
  "$MULTIPLE_APPLICATION_DEADLINES_SPEC" \
  "${MULTIPLE_APPLICATION_DEADLINES_SPEC%.json}.confirmation.json"
assert_journey_passes "derive uses the latest application deadline as submit boundary" \
  derive "$MULTIPLE_APPLICATION_DEADLINES_SPEC" \
  --out "$MULTIPLE_APPLICATION_DEADLINES_FLOW"
if [ -f "$MULTIPLE_APPLICATION_DEADLINES_FLOW" ]; then
  if python3 - "$MULTIPLE_APPLICATION_DEADLINES_FLOW" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
by_id = {step["step_id"]: step for step in flow["steps"]}

if "oral-exam" not in by_id["kit-submit"]["deliverable_ids"]:
    raise SystemExit("procedure before the final application deadline must stay absorbed")
if "sp-oral-exam" in by_id:
    raise SystemExit("procedure before the final application deadline must not become a step")
PY
    pass
  else
    fail "multiple application deadlines absorption structure check"
  fi
else
  fail "multiple application deadlines flow file missing"
fi

NO_APPLICATION_DEADLINE_SPEC="$TEST_DIR/no-application-deadline-post-submit-spec.json"
NO_APPLICATION_DEADLINE_FLOW="$TEST_DIR/no-application-deadline-post-submit-flow.json"
python3 - "$POST_SUBMIT_SPEC" "$NO_APPLICATION_DEADLINE_SPEC" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
spec["subsidy_id"] = "fixture-journey-no-application-deadline"
spec["name"] = "Journey map no application deadline fixture"
for event in spec["schedule"]:
    if event.get("event_kind") == "application_deadline":
        event["event_kind"] = "other"
output_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
if python3 - "$NO_APPLICATION_DEADLINE_SPEC" "$NO_APPLICATION_DEADLINE_FLOW" <<'PY'; then
import json
import pathlib
import sys

sys.path.insert(0, "tools/lib")
import journey_map

spec_path = pathlib.Path(sys.argv[1])
flow_path = pathlib.Path(sys.argv[2])
errors = []
flow = journey_map.derive_flow(spec_path, errors)
if flow is None or errors:
    raise SystemExit("; ".join(errors or ["derive failed"]))
flow_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  pass
else
  fail "derive without application deadline absorbs procedures"
fi
if [ -f "$NO_APPLICATION_DEADLINE_FLOW" ]; then
  if python3 - "$NO_APPLICATION_DEADLINE_FLOW" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
by_id = {step["step_id"]: step for step in flow["steps"]}


def require(condition, message):
    if not condition:
        raise SystemExit(message)


require(
    by_id["kit-submit"]["deliverable_ids"]
    == ["portal-procedure", "extra-docs", "oral-exam"],
    "procedures must be absorbed when the application deadline cannot be found",
)
require("sp-extra-docs" not in by_id, "extra documents must not become a separate step")
require("sp-oral-exam" not in by_id, "oral exam must not become a separate step")
PY
    pass
  else
    fail "no application deadline absorption structure check"
  fi
else
  fail "no application deadline flow file missing"
fi

POST_SUBMIT_CYCLE_SPEC="$TEST_DIR/post-submit-cycle-spec.json"
python3 - "$POST_SUBMIT_SPEC" "$POST_SUBMIT_CYCLE_SPEC" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
spec["subsidy_id"] = "fixture-journey-post-submit-cycle"
spec["name"] = "Journey map post-submit cycle fixture"
for deliverable in spec["deliverables"]:
    if deliverable.get("deliverable_id") == "oral-exam":
        deliverable["depends_on"] = ["extra-docs"]
output_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
write_confirmation_for_spec \
  "$POST_SUBMIT_CYCLE_SPEC" \
  "${POST_SUBMIT_CYCLE_SPEC%.json}.confirmation.json"
assert_journey_fails_with "derive rejects post-submit depends_on cycle" \
  "post-submit deliverables have a depends_on cycle" \
  derive "$POST_SUBMIT_CYCLE_SPEC" --out "$TEST_DIR/post-submit-cycle-flow.json"
if [ -e "$TEST_DIR/post-submit-cycle-flow.json" ]; then
  fail "post-submit cycle refusal must not write a flow"
else
  pass
fi

POST_SUBMIT_SELF_CYCLE_SPEC="$TEST_DIR/post-submit-self-cycle-spec.json"
POST_SUBMIT_SELF_CYCLE_FLOW="$TEST_DIR/post-submit-self-cycle-flow.json"
python3 - "$POST_SUBMIT_SPEC" "$POST_SUBMIT_SELF_CYCLE_SPEC" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
spec["subsidy_id"] = "fixture-journey-post-submit-self-cycle"
spec["name"] = "Journey map post-submit self-cycle fixture"
for deliverable in spec["deliverables"]:
    if deliverable.get("deliverable_id") == "oral-exam":
        deliverable["depends_on"] = ["portal-procedure", "oral-exam"]
        break
output_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
write_confirmation_for_spec \
  "$POST_SUBMIT_SELF_CYCLE_SPEC" \
  "${POST_SUBMIT_SELF_CYCLE_SPEC%.json}.confirmation.json"
assert_journey_fails_with "derive rejects post-submit self depends_on cycle" \
  "post-submit deliverables have a depends_on cycle" \
  derive "$POST_SUBMIT_SELF_CYCLE_SPEC" --out "$POST_SUBMIT_SELF_CYCLE_FLOW"
if [ -e "$POST_SUBMIT_SELF_CYCLE_FLOW" ]; then
  fail "post-submit self-cycle refusal must not write a flow"
else
  pass
fi

if [ -f "$FLOW" ]; then
  if python3 - "$FLOW" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
by_id = {step["step_id"]: step for step in flow["steps"]}


def require(condition, message):
    if not condition:
        raise SystemExit(message)


require(
    "denshi-shinsei" in by_id["kit-submit"]["deliverable_ids"],
    "bundled submit must keep absorbing denshi-shinsei",
)
require(
    "sp-denshi-shinsei" not in by_id,
    "bundled denshi-shinsei must not move after submit",
)
PY
    pass
  else
    fail "bundled submit procedure non-regression check"
  fi
else
  fail "bundled flow file missing for submit procedure non-regression check"
fi

# --- relative deadlines ---------------------------------------------------

RELATIVE_SPEC="$TEST_DIR/relative-deadline-spec.json"
RELATIVE_FLOW="$TEST_DIR/relative-deadline-flow.json"
RELATIVE_HTML="$TEST_DIR/relative-deadline.html"
write_relative_deadline_spec "$RELATIVE_SPEC"

assert_journey_passes "derive relative deadline fixture" \
  derive "$RELATIVE_SPEC" --out "$RELATIVE_FLOW"
if [ -f "$RELATIVE_FLOW" ]; then
  if python3 - "$RELATIVE_FLOW" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
by_id = {step["step_id"]: step for step in flow["steps"]}
long_anchor = (
    "補助事業が完了した日または補助対象経費の支払いが完了した日の"
    "いずれか遅い日として公式要項で定める基準日"
)


def require(condition, message):
    if not condition:
        raise SystemExit(message)


require(
    by_id["kit-submit"]["deadline"] is None,
    "relative application deadline must not invent an absolute date",
)
require(
    by_id["kit-submit"]["deadline_note"] == "受付開始日から14日以内",
    "relative application deadline note mismatch",
)
require(
    by_id["kit-submit"]["deadline_time"] == "17:00",
    "relative application deadline time mismatch",
)
require(
    "application-deadline" in by_id["kit-submit"]["event_ids"],
    "relative application deadline event id missing",
)
require(
    "ev-application-deadline" not in by_id,
    "current derive must absorb the relative application deadline into submit",
)
require(
    by_id["sp-post-report-after"]["deadline_note"] == f"{long_anchor}から30日以内",
    "post-adoption relative deadline note mismatch",
)
require(
    by_id["sp-post-report-after"]["deadline_time"] == "18:00",
    "derived relative deadline time mismatch",
)
require(
    by_id["ev-project-period-before"]["deadline_note"] == "実績報告期限の30日前まで",
    "project-period relative deadline note mismatch",
)
require(
    by_id["ev-project-period-before"]["deadline_time"] == "16:45",
    "project-period relative deadline time mismatch",
)
require(
    by_id["sp-post-unknown-direction"]["deadline_note"]
    == "受付完了日起点・45日（前後は要確認）",
    "unknown-direction relative deadline note mismatch",
)
require(
    by_id["sp-post-open-after"]["deadline_note"] == "交付決定日以降",
    "direction-only within-after deadline note mismatch",
)
require(
    by_id["ev-project-period-open-before"]["deadline_note"] == "実績報告期限より前",
    "direction-only before deadline note mismatch",
)
require(
    by_id["ev-draft-anchor"]["deadline_note"] == "採択発表日起点",
    "absorbed due relative deadline note mismatch",
)
require(
    by_id["sp-post-absolute"]["deadline"] == "2027-03-31",
    "absolute deadline must remain unchanged",
)
require(
    by_id["sp-post-absolute"]["deadline_note"] is None,
    "absolute deadline must suppress its relative note",
)
require(
    all("deadline_note" in step for step in flow["steps"]),
    "every derived step must contain deadline_note",
)
require(
    flow.get("deadline_note_version") == 1,
    "current derive must declare deadline_note_version=1",
)
PY
    pass
  else
    fail "relative deadline flow structure check"
  fi
else
  fail "relative deadline flow file missing"
fi

assert_journey_passes "render relative deadline fixture" \
  render "$RELATIVE_FLOW" --out "$RELATIVE_HTML" --spec "$RELATIVE_SPEC"
for token in \
  "受付開始日から14日以内" \
  "17:00" \
  "30日以内" \
  "18:00" \
  "実績報告期限の30日前まで" \
  "16:45" \
  "受付完了日起点・45日（前後は要確認）" \
  "交付決定日以降" \
  "実績報告期限より前" \
  "採択発表日起点" \
  "締切 2027-03-31"; do
  assert_file_contains "relative deadline html" "$RELATIVE_HTML" "$token"
done
assert_file_lacks "absolute deadline html" "$RELATIVE_HTML" "交付決定日から90日以内"

INCOMPLETE_APPLICATION_SPEC="$TEST_DIR/incomplete-application-relative-spec.json"
INCOMPLETE_APPLICATION_FLOW="$TEST_DIR/incomplete-application-relative-flow.json"
python3 - "$RELATIVE_SPEC" "$INCOMPLETE_APPLICATION_SPEC" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
for event in spec["schedule"]:
    if event["event_kind"] == "application_deadline":
        event["relative"] = {
            "anchor": "",
            "offset_days": 14,
            "direction": "within_after",
        }
        event["time"] = "23:59"
        break
output_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
write_confirmation_for_spec \
  "$INCOMPLETE_APPLICATION_SPEC" \
  "${INCOMPLETE_APPLICATION_SPEC%.json}.confirmation.json"
assert_journey_passes "derive ignores incomplete relative application deadline" \
  derive "$INCOMPLETE_APPLICATION_SPEC" --out "$INCOMPLETE_APPLICATION_FLOW"
if [ -f "$INCOMPLETE_APPLICATION_FLOW" ]; then
  if python3 - "$INCOMPLETE_APPLICATION_FLOW" <<'PY'; then
import json
import sys

flow = json.load(open(sys.argv[1], encoding="utf-8"))
submit = next(step for step in flow["steps"] if step["step_id"] == "kit-submit")
if submit["deadline"] is not None:
    raise SystemExit("incomplete relative deadline must not set deadline")
if submit["deadline_note"] is not None:
    raise SystemExit("incomplete relative deadline must not set deadline_note")
if submit["deadline_time"] is not None:
    raise SystemExit("incomplete relative deadline must not set deadline_time")
if "application-deadline" in submit["event_ids"]:
    raise SystemExit("incomplete relative deadline must not add its event id")
PY
    pass
  else
    fail "incomplete relative application deadline structure check"
  fi
else
  fail "incomplete relative application deadline flow missing"
fi

FORGED_NOTE_FLOW="$TEST_DIR/forged-deadline-note-flow.json"
python3 - "$RELATIVE_FLOW" "$FORGED_NOTE_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "sp-post-report-after":
        step["deadline_note"] = "根拠のない相対期限"
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with "render rejects forged relative deadline note" "deadline_note" \
  render "$FORGED_NOTE_FLOW" --out "$TEST_DIR/forged-deadline-note.html" \
  --spec "$RELATIVE_SPEC"

MISSING_NOTE_FLOW="$TEST_DIR/missing-deadline-note-flow.json"
python3 - "$RELATIVE_FLOW" "$MISSING_NOTE_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "sp-post-report-after":
        step.pop("deadline_note")
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects one removed deadline_note in a current flow" \
  "without displaying deadline_note" \
  render "$MISSING_NOTE_FLOW" --out "$TEST_DIR/missing-deadline-note.html" \
  --spec "$RELATIVE_SPEC"

CHANGED_RELATIVE_EVENT_IDS_FLOW="$TEST_DIR/changed-relative-event-ids-flow.json"
python3 - "$RELATIVE_FLOW" "$CHANGED_RELATIVE_EVENT_IDS_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "kit-submit":
        step["event_ids"].append("application-deadline")
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects relative event_ids change in a current flow" \
  "protected field event_ids changed" \
  render "$CHANGED_RELATIVE_EVENT_IDS_FLOW" \
  --out "$TEST_DIR/changed-relative-event-ids.html" \
  --spec "$RELATIVE_SPEC"

CHANGED_RELATIVE_TIME_FLOW="$TEST_DIR/changed-relative-time-flow.json"
python3 - "$RELATIVE_FLOW" "$CHANGED_RELATIVE_TIME_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "sp-post-report-after":
        step["deadline_time"] = None
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects relative deadline_time change in a current flow" \
  "deadline_time mismatch: expected '18:00', got None" \
  render "$CHANGED_RELATIVE_TIME_FLOW" \
  --out "$TEST_DIR/changed-relative-time.html" \
  --spec "$RELATIVE_SPEC"

AI_RELATIVE_FLOW="$TEST_DIR/ai-relative-flow.json"
python3 - "$RELATIVE_FLOW" "$AI_RELATIVE_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
steps = flow["steps"]
by_id = {step["step_id"]: step for step in steps}
ai_step = {
    "step_id": "ai-relative-deadline-check",
    "origin": "ai",
    "base_step_id": None,
    "label": "相対期限を確認する",
    "description": None,
    "lane": "claude",
    "zone": "application",
    "kind": "process",
    "human_gate": False,
    "deliverable_ids": [],
    "event_ids": ["application-deadline"],
    "clause_ids": ["clause-1"],
    "deadline": None,
    "deadline_note": "受付開始日から14日以内",
    "deadline_time": "17:00",
    "issuer": None,
    "next": ["kit-submit"],
    "branches": [],
}
by_id["kit-finalize"]["next"] = [ai_step["step_id"]]
insert_at = next(index for index, step in enumerate(steps) if step["step_id"] == "kit-submit")
steps.insert(insert_at, ai_step)
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_passes \
  "render accepts ai step with matching relative deadline note and time" \
  render "$AI_RELATIVE_FLOW" \
  --out "$TEST_DIR/ai-relative.html" \
  --spec "$RELATIVE_SPEC"

AI_WRONG_RELATIVE_TIME_FLOW="$TEST_DIR/ai-wrong-relative-time-flow.json"
python3 - "$AI_RELATIVE_FLOW" "$AI_WRONG_RELATIVE_TIME_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "ai-relative-deadline-check":
        step["deadline_time"] = "00:01"
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects ai relative deadline with a different time" \
  "deadline_time mismatch: expected '17:00', got '00:01'" \
  render "$AI_WRONG_RELATIVE_TIME_FLOW" \
  --out "$TEST_DIR/ai-wrong-relative-time.html" \
  --spec "$RELATIVE_SPEC"

AI_MISSING_RELATIVE_TIME_FLOW="$TEST_DIR/ai-missing-relative-time-flow.json"
python3 - "$AI_RELATIVE_FLOW" "$AI_MISSING_RELATIVE_TIME_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "ai-relative-deadline-check":
        step["deadline_time"] = None
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects ai relative deadline with a missing time" \
  "deadline_time mismatch: expected '17:00', got None" \
  render "$AI_MISSING_RELATIVE_TIME_FLOW" \
  --out "$TEST_DIR/ai-missing-relative-time.html" \
  --spec "$RELATIVE_SPEC"

AI_MISSING_RELATIVE_NOTE_FLOW="$TEST_DIR/ai-missing-relative-note-flow.json"
python3 - "$AI_RELATIVE_FLOW" "$AI_MISSING_RELATIVE_NOTE_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "ai-relative-deadline-check":
        step["deadline_note"] = None
        step["deadline_time"] = None
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects ai step hiding a relative deadline" \
  "relative deadline event application-deadline without displaying deadline_note" \
  render "$AI_MISSING_RELATIVE_NOTE_FLOW" \
  --out "$TEST_DIR/ai-missing-relative-note.html" \
  --spec "$RELATIVE_SPEC"

AI_MIXED_DEADLINES_FLOW="$TEST_DIR/ai-mixed-deadlines-flow.json"
python3 - "$AI_RELATIVE_FLOW" "$AI_MIXED_DEADLINES_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "ai-relative-deadline-check":
        step["event_ids"] = ["post-absolute", "application-deadline"]
        step["deadline"] = "2027-03-31"
        step["deadline_note"] = None
        step["deadline_time"] = None
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects ai step mixing dated and relative deadline events" \
  "step ai-relative-deadline-check cannot mix dated event_ids ['post-absolute'] with relative deadline event_ids ['application-deadline']" \
  render "$AI_MIXED_DEADLINES_FLOW" \
  --out "$TEST_DIR/ai-mixed-deadlines.html" \
  --spec "$RELATIVE_SPEC"

AI_STARTS_AT_MIXED_FLOW="$TEST_DIR/ai-starts-at-mixed-flow.json"
python3 - "$AI_RELATIVE_FLOW" "$AI_STARTS_AT_MIXED_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "ai-relative-deadline-check":
        step["event_ids"] = ["starts-only", "application-deadline"]
        step["deadline"] = "2027-04-01"
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects ai step mixing starts_at and relative deadline events" \
  "step ai-relative-deadline-check cannot mix dated event_ids ['starts-only'] with relative deadline event_ids ['application-deadline']" \
  render "$AI_STARTS_AT_MIXED_FLOW" \
  --out "$TEST_DIR/ai-starts-at-mixed.html" \
  --spec "$RELATIVE_SPEC"

AI_BOTH_DEADLINE_FIELDS_FLOW="$TEST_DIR/ai-both-deadline-fields-flow.json"
python3 - "$AI_RELATIVE_FLOW" "$AI_BOTH_DEADLINE_FIELDS_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "ai-relative-deadline-check":
        step["event_ids"] = ["post-absolute"]
        step["deadline"] = "2027-03-31"
        step["deadline_note"] = "交付決定日から90日以内"
        step["deadline_time"] = None
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects a step carrying both deadline fields" \
  "step ai-relative-deadline-check cannot set both deadline '2027-03-31' and deadline_note '交付決定日から90日以内'" \
  render "$AI_BOTH_DEADLINE_FIELDS_FLOW" \
  --out "$TEST_DIR/ai-both-deadline-fields.html" \
  --spec "$RELATIVE_SPEC"

AI_AMBIGUOUS_RELATIVE_TIME_FLOW="$TEST_DIR/ai-ambiguous-relative-time-flow.json"
python3 - "$AI_RELATIVE_FLOW" "$AI_AMBIGUOUS_RELATIVE_TIME_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "ai-relative-deadline-check":
        step["event_ids"] = ["application-deadline", "application-deadline-late"]
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects one relative note backed by conflicting times" \
  "step ai-relative-deadline-check deadline_note '受付開始日から14日以内' has conflicting deadline_time values ['17:00', '18:00']" \
  render "$AI_AMBIGUOUS_RELATIVE_TIME_FLOW" \
  --out "$TEST_DIR/ai-ambiguous-relative-time.html" \
  --spec "$RELATIVE_SPEC"

AI_SPLIT_DEADLINES_FLOW="$TEST_DIR/ai-split-deadlines-flow.json"
python3 - "$AI_RELATIVE_FLOW" "$AI_SPLIT_DEADLINES_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
steps = flow["steps"]
by_id = {step["step_id"]: step for step in steps}
absolute_step = {
    "step_id": "ai-absolute-deadline-check",
    "origin": "ai",
    "base_step_id": None,
    "label": "絶対期限を確認する",
    "description": None,
    "lane": "claude",
    "zone": "application",
    "kind": "process",
    "human_gate": False,
    "deliverable_ids": [],
    "event_ids": ["post-absolute"],
    "clause_ids": ["clause-1"],
    "deadline": "2027-03-31",
    "deadline_note": None,
    "deadline_time": None,
    "issuer": None,
    "next": ["ai-relative-deadline-check"],
    "branches": [],
}
by_id["kit-finalize"]["next"] = [absolute_step["step_id"]]
insert_at = next(
    index
    for index, step in enumerate(steps)
    if step["step_id"] == "ai-relative-deadline-check"
)
steps.insert(insert_at, absolute_step)
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_passes \
  "render accepts separate ai steps for dated and relative deadlines" \
  render "$AI_SPLIT_DEADLINES_FLOW" \
  --out "$TEST_DIR/ai-split-deadlines.html" \
  --spec "$RELATIVE_SPEC"

DOWNGRADED_RELATIVE_FLOW="$TEST_DIR/downgraded-relative-flow.json"
python3 - "$RELATIVE_FLOW" "$DOWNGRADED_RELATIVE_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
flow.pop("deadline_note_version", None)
for step in flow["steps"]:
    step.pop("deadline_note", None)
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render rejects deadline-note format downgrade for a relative spec" \
  "rerun /journey-map derive to regenerate the flow" \
  render "$DOWNGRADED_RELATIVE_FLOW" \
  --out "$TEST_DIR/downgraded-relative.html" \
  --spec "$RELATIVE_SPEC"

LEGACY_FLOW="$TEST_DIR/legacy-no-deadline-note-flow.json"
if python3 - "$RELATIVE_SPEC" "$LEGACY_FLOW" <<'PY'; then
import json
import pathlib
import sys

sys.path.insert(0, "tools/lib")
import journey_map

spec_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(spec_path.read_text(encoding="utf-8"))
errors = []
base = journey_map.load_base_flow(errors)
flow = journey_map.derive_flow_from_spec(
    spec,
    spec_path,
    base,
    errors,
    deadline_note_support=False,
)
if flow is None or errors:
    raise SystemExit("legacy derive failed: " + "; ".join(errors))
if "deadline_note_version" in flow:
    raise SystemExit("legacy derive must omit deadline_note_version")
if any("deadline_note" in step for step in flow["steps"]):
    raise SystemExit("legacy derive must omit deadline_note fields")

by_id = {step["step_id"]: step for step in flow["steps"]}
if "ev-application-deadline" not in by_id:
    raise SystemExit("legacy derive must create the absorbed application deadline milestone")
if "application-deadline" in by_id["kit-submit"]["event_ids"]:
    raise SystemExit("legacy submit must not absorb a relative application deadline")
if by_id["kit-submit"]["deadline_time"] is not None:
    raise SystemExit("legacy submit must not display the relative application time")
if by_id["ev-application-deadline"]["deadline"] is not None:
    raise SystemExit("legacy absorbed milestone must not invent an absolute deadline")
if by_id["ev-application-deadline"]["deadline_time"] != "17:00":
    raise SystemExit("legacy absorbed milestone must retain its event time")
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  pass
else
  fail "legacy relative-deadline flow derive"
fi
assert_journey_fails_with \
  "render rejects an actual legacy flow for a relative-deadline spec" \
  "rerun /journey-map derive to regenerate the flow" \
  render "$LEGACY_FLOW" --out "$TEST_DIR/legacy-no-deadline-note.html" \
  --spec "$RELATIVE_SPEC"

LEGACY_NO_RELATIVE_SPEC="tools/fixtures/spec/good-spec.json"
LEGACY_NO_RELATIVE_FLOW="$TEST_DIR/legacy-no-relative-flow.json"
if python3 - "$LEGACY_NO_RELATIVE_SPEC" "$LEGACY_NO_RELATIVE_FLOW" <<'PY'; then
import json
import pathlib
import sys

sys.path.insert(0, "tools/lib")
import journey_map

spec_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(spec_path.read_text(encoding="utf-8"))
errors = []
base = journey_map.load_base_flow(errors)
flow = journey_map.derive_flow_from_spec(
    spec,
    spec_path,
    base,
    errors,
    deadline_note_support=False,
)
if flow is None or errors:
    raise SystemExit("legacy derive failed: " + "; ".join(errors))
if "deadline_note_version" in flow:
    raise SystemExit("legacy derive must omit deadline_note_version")
if any("deadline_note" in step for step in flow["steps"]):
    raise SystemExit("legacy derive must omit deadline_note fields")
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  pass
else
  fail "legacy no-relative flow derive"
fi
assert_journey_passes \
  "render accepts a legacy flow when its spec has no relative deadline" \
  render "$LEGACY_NO_RELATIVE_FLOW" \
  --out "$TEST_DIR/legacy-no-relative.html" \
  --spec "$LEGACY_NO_RELATIVE_SPEC"

INVALID_LEGACY_EVENT_IDS_FLOW="$TEST_DIR/invalid-legacy-event-ids-flow.json"
python3 - "$LEGACY_NO_RELATIVE_FLOW" "$INVALID_LEGACY_EVENT_IDS_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "kit-submit":
        step["event_ids"].append("application-deadline")
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render keeps unrelated legacy event_ids protected" \
  "protected field event_ids changed" \
  render "$INVALID_LEGACY_EVENT_IDS_FLOW" \
  --out "$TEST_DIR/invalid-legacy-event-ids.html" \
  --spec "$LEGACY_NO_RELATIVE_SPEC"

INVALID_LEGACY_PROTECTED_FLOW="$TEST_DIR/invalid-legacy-protected-flow.json"
python3 - "$LEGACY_NO_RELATIVE_FLOW" "$INVALID_LEGACY_PROTECTED_FLOW" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
flow = json.loads(source_path.read_text(encoding="utf-8"))
for step in flow["steps"]:
    if step["step_id"] == "kit-submit":
        step["description"] = "改変した提出工程"
        break
output_path.write_text(json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
assert_journey_fails_with \
  "render keeps legacy kit fields protected" \
  "step kit-submit protected field description changed" \
  render "$INVALID_LEGACY_PROTECTED_FLOW" \
  --out "$TEST_DIR/invalid-legacy-protected.html" \
  --spec "$LEGACY_NO_RELATIVE_SPEC"

NEGATIVE_OFFSET_SPEC="$TEST_DIR/negative-relative-offset-spec.json"
python3 - "$RELATIVE_SPEC" "$NEGATIVE_OFFSET_SPEC" <<'PY'
import json
import pathlib
import sys

source_path, output_path = map(pathlib.Path, sys.argv[1:3])
spec = json.loads(source_path.read_text(encoding="utf-8"))
for event in spec["schedule"]:
    if event["event_kind"] == "application_deadline":
        event["relative"]["offset_days"] = -14
        break
output_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
write_confirmation_for_spec \
  "$NEGATIVE_OFFSET_SPEC" \
  "${NEGATIVE_OFFSET_SPEC%.json}.confirmation.json"
assert_journey_fails_with \
  "derive rejects a negative relative deadline offset" \
  "relative.offset_days must be greater than or equal to 0" \
  derive "$NEGATIVE_OFFSET_SPEC" --out "$TEST_DIR/negative-relative-offset-flow.json"

if python3 - schemas/subsidy-spec.schema.json <<'PY'; then
import json
import sys

sys.path.insert(0, "tools/lib")
import journey_map

schema = json.load(open(sys.argv[1], encoding="utf-8"))
offset_schema = schema["properties"]["schedule"]["items"]["properties"]["relative"]
relative_object = next(
    option for option in offset_schema["oneOf"] if option.get("type") == "object"
)
if relative_object["properties"]["offset_days"].get("minimum") != 0:
    raise SystemExit("relative.offset_days schema minimum must be 0")
if journey_map.relative_deadline_text(
    {
        "relative": {
            "anchor": "受付開始日",
            "offset_days": -14,
            "direction": "within_after",
        }
    }
) is not None:
    raise SystemExit("negative offset must not produce relative deadline text")
PY
  pass
else
  fail "negative relative deadline defenses"
fi

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

test_tane01_application_roots() {
  if python3 - <<'PY'; then
import json
import pathlib
import shutil
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix="journey-map-tane01-") as temporary:
    root = pathlib.Path(temporary).resolve()
    shutil.copytree("tools/lib", root / "tools/lib")
    for name in ("journey-map.sh", "check-spec.sh"):
        shutil.copy2(pathlib.Path("tools") / name, root / "tools" / name)
    for name in ("schemas", "templates"):
        shutil.copytree(name, root / name)
    (root / "specs").mkdir()
    spec_path = root / "specs/fixture-good.json"
    shutil.copy2("tools/fixtures/spec/good-spec.json", spec_path)
    confirmation = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.confirmation.json").read_text(encoding="utf-8"))
    confirmation["spec_path"] = spec_path.as_posix()
    spec_path.with_suffix(".confirmation.json").write_text(json.dumps(confirmation), encoding="utf-8")
    default_path = root / "input/current-application.json"
    flow_path = root / "input/journey/baseline.json"
    checks = 0

    def run_case(action, label, options, expected=None):
        global checks
        source = spec_path if action == "derive" else flow_path
        suffix = "json" if action == "derive" else "html"
        out = root / "input/journey" / f"{label}-{action}.{suffix}"
        if out.exists():
            raise SystemExit(f"output must start absent: {out}")
        result = subprocess.run(
            ["bash", "tools/journey-map.sh", action, str(source), "--out", str(out), *options],
            cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        if expected is None:
            if result.returncode != 0 or not out.is_file() or "OK:" not in result.stdout:
                raise SystemExit(f"{label} {action} must produce output: {result.stdout}")
        elif result.returncode != 1 or expected not in result.stdout or out.exists():
            raise SystemExit(f"{label} {action} must exit 1 without output: {result.stdout}")
        if expected != "current application root must be an object" and "root must be an object" in result.stdout:
            raise SystemExit(f"{label} must preserve the read diagnostic: {result.stdout}")
        checks += 1
        return out

    # No default file is present: both commands must still produce their outputs.
    flow_path = run_case("derive", "absent-default", [])
    run_case("render", "absent-default", [])
    for mode in ("explicit", "default"):
        app_path = root / "application.json" if mode == "explicit" else default_path
        options = ["--current-application", str(app_path)] if mode == "explicit" else []
        for index, raw in enumerate(("null", "[]", "true", '"text"')):
            app_path.write_text(raw, encoding="utf-8")
            for action in ("derive", "render"):
                run_case(action, f"{mode}-{index}", options, "current application root must be an object")
                if mode == "default":
                    run_case(action, f"ignored-{index}", ["--no-current-application"])
        app_path.write_text("{", encoding="utf-8")
        for action in ("derive", "render"):
            run_case(action, f"{mode}-invalid-json", options, "current application invalid JSON")
        app_path.unlink()
    for action in ("derive", "render"):
        run_case(action, "explicit-missing", ["--current-application", str(root / "missing.json")], "current application not found")
    print(f"tane01 application roots: {checks} pass / 0 fail")
PY
    pass
  else
    fail "test_tane01_application_roots"
  fi
}

test_tane01_application_roots

test_pre_application_dependencies() {
  if python3 - "$TEST_DIR" <<'PY'; then
import copy
import hashlib
import json
import pathlib
import subprocess
import sys
import unittest

sys.path.insert(0, "tools/lib")
import check_spec

root = pathlib.Path(sys.argv[1]) / "pre-application"
template = json.loads(pathlib.Path("tools/fixtures/spec/good-spec.json").read_text(encoding="utf-8"))


def deliverable(identifier, dependencies=(), producer="external", kind="document", **fields):
    item = copy.deepcopy(template["deliverables"][0])
    item.update(deliverable_id=identifier, name=identifier, depends_on=list(dependencies),
                produced_by=producer, type=kind, due_event_id=None, sections=[])
    item.update(fields)
    return item


class PreApplicationDependencies(unittest.TestCase):
    def run_case(self, name, deliverables, *, expected=(), edges=None):
        directory = root / name
        directory.mkdir(parents=True)
        spec_path = directory / "spec.json"
        flow_path = directory / "flow.json"
        html_path = directory / "flow.html"
        spec = copy.deepcopy(template)
        spec["deliverables"] = deliverables
        for event_id, date in (("earlier", "2026-11-01"), ("later", "2027-01-15")):
            event = copy.deepcopy(template["schedule"][0])
            event.update(event_id=event_id, event_kind="other", date=date)
            spec["schedule"].append(event)
        spec_path.write_text(json.dumps(spec, ensure_ascii=False) + "\n", encoding="utf-8")
        items = []
        for field_path in check_spec.required_confirmation_field_paths(spec):
            item = {"field_path": field_path, "source_clauses": ["clause-1"],
                    "state": "confirmed", "note": "Fixture confirmation."}
            if field_path.startswith("eligibility.rules."):
                item["predicate_state"] = "not_encodable"
            items.append(item)
        confirmation = {
            "spec_path": spec_path.as_posix(), "spec_version": spec["spec_version"],
            "spec_sha256": hashlib.sha256(spec_path.read_bytes()).hexdigest(),
            "confirmed_by": "applicant", "confirmed_at": "2026-07-25T00:00:00+09:00",
            "items": items,
        }
        spec_path.with_suffix(".confirmation.json").write_text(
            json.dumps(confirmation, ensure_ascii=False) + "\n", encoding="utf-8")

        result = subprocess.run(
            ["bash", "tools/journey-map.sh", "derive", str(spec_path), "--out", str(flow_path),
             "--no-current-application"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if expected:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertFalse(flow_path.exists(), "refused derivation must not write a flow")
            for diagnostic in expected:
                self.assertIn(diagnostic, result.stdout)
            return
        self.assertEqual(result.returncode, 0, result.stdout)
        flow = json.loads(flow_path.read_text(encoding="utf-8"))
        by_id = {step["step_id"]: step for step in flow["steps"]}
        positions = {step["step_id"]: index for index, step in enumerate(flow["steps"])}
        for source, target in (edges or {}).items():
            self.assertEqual(by_id[source]["next"], [target], source)
            self.assertLess(positions[source], positions[target])
        result = subprocess.run(
            ["bash", "tools/journey-map.sh", "render", str(flow_path), "--out", str(html_path),
             "--no-current-application"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(html_path.is_file())

    def test_pre_application_dependency_order(self):
        for producer in ("external", "human_only"):
            for reverse in (False, True):
                with self.subTest(producer=producer, reverse=reverse):
                    items = [deliverable("a", ["b"], producer), deliverable("b")]
                    self.run_case(f"order-{producer}-{reverse}", items[::-1] if reverse else items,
                                  edges={"kit-review": "sp-b", "sp-b": "sp-a", "sp-a": "kit-finalize"})
        self.run_case("ready-tie", [deliverable("a", ["c"]), deliverable("b"), deliverable("c")],
                      edges={"kit-review": "sp-b", "sp-b": "sp-c", "sp-c": "sp-a", "sp-a": "kit-finalize"})

    def test_pre_application_dependency_cycle(self):
        for producer, kind in (("external", "document"), ("ai_draftable", "document"),
                               ("human_only", "procedure")):
            for self_reference in (False, True):
                with self.subTest(producer=producer, self_reference=self_reference):
                    items = [deliverable("a", ["a" if self_reference else "b"], producer, kind)]
                    if not self_reference:
                        items.append(deliverable("b", ["a"], producer, kind))
                    self.run_case(f"cycle-{producer}-{self_reference}", items,
                                  expected=("depends_on cycle",))
        self.run_case("cycle-across-regions", [deliverable("a", ["b"], "ai_draftable"),
                                              deliverable("b", ["a"])], expected=("depends_on cycle",))

    def test_pre_application_dependency_boundaries(self):
        prep = deliverable("prep", producer="human_only")
        draft = deliverable("draft", ["prep"], "ai_draftable")
        external = deliverable("external", ["draft"])
        submit = deliverable("submit", ["external"], "human_only", "procedure")
        post_submit = deliverable("post-submit", ["submit"], "human_only", "procedure", due_event_id="later")
        post_adoption = deliverable("post-adoption", ["post-submit"], phase="post_adoption")
        self.run_case("earlier-regions", [submit, external, draft, prep, post_submit, post_adoption], edges={
            "kit-env-setup": "sp-prep", "sp-prep": "kit-get-guidelines", "kit-draft": "kit-review",
            "kit-review": "sp-external", "sp-external": "kit-finalize", "kit-finalize": "kit-submit",
            "kit-submit": "sp-post-submit", "sp-post-submit": "kit-result", "kit-result": "sp-post-adoption",
        })
        regions = [draft, external, submit, post_submit, post_adoption]
        for source_index in range(3):
            for target_index in range(source_index + 1, len(regions)):
                source, target = copy.deepcopy(regions[source_index]), copy.deepcopy(regions[target_index])
                source["depends_on"] = [target["deliverable_id"]]
                target["depends_on"] = ["prep"]
                with self.subTest(source=source["deliverable_id"], target=target["deliverable_id"]):
                    self.run_case(f"later-region-{source_index}-{target_index}", [source, target, prep],
                                  expected=("depends_on", "later placement region",
                                            source["deliverable_id"], target["deliverable_id"]))
        for producer, kind in (("ai_draftable", "document"), ("human_only", "procedure")):
            with self.subTest(aggregate=producer):
                self.run_case(f"aggregate-acyclic-{producer}", [
                    deliverable("a", ["b"], producer, kind), deliverable("b", ["prep"], producer, kind), prep])
        self.run_case("independent-order", [
            deliverable("a", due_event_id="application-deadline"), deliverable("b", due_event_id="earlier"),
            deliverable("p", producer="human_only", due_event_id="application-deadline"),
            deliverable("q", producer="human_only", due_event_id="earlier"),
        ], edges={"kit-env-setup": "sp-p", "sp-p": "sp-q", "sp-q": "kit-get-guidelines",
                  "kit-review": "sp-a", "sp-a": "sp-b", "sp-b": "kit-finalize"})


unittest.main(argv=[sys.argv[0]])
PY
    pass
  else
    fail "test_pre_application_dependencies"
  fi
}

test_pre_application_dependencies

echo "PASS: $PASS FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
