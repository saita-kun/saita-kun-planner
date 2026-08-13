#!/usr/bin/env python3
"""Derive and render subsidy-specific application journey flowcharts.

Subcommands:
  derive <spec_path> --out <flow_path>
      Build a journey flow JSON from a confirmed subsidy spec (v2) and the kit
      base flow (templates/journey/base-flow.json). The derivation is fully
      deterministic: it reads only structured spec fields (deliverables[],
      schedule[]) and never extracts steps from free text.

  render <flow_path> --out <html_path> [--spec <spec_path>]
      Validate the flow JSON against schemas/journey-flow.schema.json and its
      sources (anti-hallucination gate), then emit a self-contained HTML file
      with an inline SVG flowchart. Any violation refuses rendering (exit 1).

Design constraints:
  - stdlib only, no network, no timestamps (deterministic output).
  - Rendered text is plain Japanese for business readers; kit-internal terms
    (file paths, command names, schema words) must not appear in the HTML.
  - All strings originating from JSON inputs are HTML-escaped on render.
"""

import argparse
import html
import json
import pathlib
import sys
import typing

import check_spec
import spec_resolver

Json = typing.Any

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
BASE_FLOW_PATH = REPO_ROOT / "templates" / "journey" / "base-flow.json"
FLOW_SCHEMA_PATH = REPO_ROOT / "schemas" / "journey-flow.schema.json"
DEFAULT_CURRENT_APPLICATION_PATH = REPO_ROOT / "input" / "current-application.json"

LANE_IDS = ("owner", "claude", "external")
ZONES = ("application", "post_adoption")
STEP_KINDS = ("process", "decision", "milestone", "terminal")
ORIGINS = ("kit", "derived", "ai")

LANE_BY_PRODUCED_BY = {
    "ai_draftable": "claude",
    "human_only": "owner",
    "external": "external",
}

# Deterministic label templates keyed by (produced_by, type). Deliverable
# names come from the spec verbatim; only the verb phrase is kit-provided.
VERB_PHRASES = {
    ("external", "document"): "{name}の発行を受ける",
    ("external", "attachment"): "{name}の発行を受ける",
    ("external", "form_input"): "{name}の手続きを外部の窓口と進める",
    ("external", "procedure"): "{name}の手続きを外部の窓口と進める",
    ("human_only", "document"): "{name}を作成して提出する",
    ("human_only", "attachment"): "{name}を用意して提出する",
    ("human_only", "form_input"): "{name}を自分で入力する",
    ("human_only", "procedure"): "{name}を済ませる",
    ("ai_draftable", "document"): "{name}の下書きを作って仕上げる",
    ("ai_draftable", "form_input"): "{name}の下書きを作って仕上げる",
    ("ai_draftable", "attachment"): "{name}を準備する",
    ("ai_draftable", "procedure"): "{name}を進める",
}

# base-flow step ids the derive merge rules anchor on.
REQUIRED_BASE_STEPS = (
    "consult",
    "env-setup",
    "get-guidelines",
    "review",
    "finalize",
    "draft",
    "submit",
    "result",
)

DATE_MAX_KEY = "￿"
PROTECTED_STEP_FIELDS = (
    "origin",
    "label",
    "description",
    "lane",
    "zone",
    "kind",
    "human_gate",
    "deliverable_ids",
    "event_ids",
    "deadline",
    "deadline_time",
    "issuer",
)
PROTECTED_FLOW_METADATA = (
    ("subsidy_id", "subsidy_id"),
    ("subsidy_name", "name"),
    ("round", "round"),
    ("spec_version", "spec_version"),
)
CONFIRMED_APPLICATION_STATES = {
    "spec_confirmed",
    "intake_done",
    "fit_done",
    "planned",
    "drafting",
    "verified",
    "finalized",
}


def load_json(path: pathlib.Path, errors: typing.List[str], label: str) -> Json:
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        errors.append(f"{label} not found: {path}")
    except json.JSONDecodeError as exc:
        errors.append(f"{label} invalid JSON: {path}: line {exc.lineno} column {exc.colno}")
    except OSError as exc:
        errors.append(f"{label} cannot be read: {path}: {exc}")
    return None


def require_confirmed_spec(spec: Json, errors: typing.List[str]) -> bool:
    status = spec.get("status") if isinstance(spec, dict) else None
    if status != "confirmed":
        errors.append(
            f"spec status must be confirmed before /journey-map; "
            f"run /confirm-spec or /select-subsidy first (got: {status})"
        )
        return False
    return True


def display_path(path: pathlib.Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except (OSError, ValueError):
        return path.as_posix()


def default_current_application_path() -> typing.Optional[pathlib.Path]:
    if DEFAULT_CURRENT_APPLICATION_PATH.is_file():
        return DEFAULT_CURRENT_APPLICATION_PATH
    return None


def load_current_application(
    raw_path: typing.Optional[str],
    errors: typing.List[str],
    no_current_application: bool = False,
) -> typing.Optional[typing.Dict[str, Json]]:
    if no_current_application:
        return None
    if raw_path is None:
        path = default_current_application_path()
        if path is None:
            return None
    else:
        path = pathlib.Path(raw_path)
    value = load_json(path, errors, "current application")
    if not isinstance(value, dict):
        return None
    return value


def validate_current_application(
    current_application: typing.Optional[typing.Dict[str, Json]],
    spec: typing.Dict[str, Json],
    errors: typing.List[str],
) -> None:
    if current_application is None:
        return

    state = current_application.get("state")
    if state not in CONFIRMED_APPLICATION_STATES:
        errors.append(
            "current application state must be spec_confirmed or later before "
            f"/journey-map; run /confirm-spec first (got: {state})"
        )

    app_subsidy_id = current_application.get("subsidy_id")
    if not isinstance(app_subsidy_id, str) or not app_subsidy_id:
        errors.append("current application subsidy_id must be a non-empty string")
    elif app_subsidy_id != spec.get("subsidy_id"):
        errors.append(
            "current application subsidy_id does not match the resolved spec "
            f"(expected {app_subsidy_id!r}, got {spec.get('subsidy_id')!r})"
        )


def validate_confirmed_spec(
    spec_path: pathlib.Path,
    spec: typing.Dict[str, Json],
    errors: typing.List[str],
) -> None:
    require_confirmed_spec(spec, errors)

    check_runs = [
        check_spec.check_spec(spec_path),
        check_spec.check_spec(spec_path, gate="confirm"),
    ]
    seen: typing.Set[str] = set()
    for check_errors, _warnings, _readiness in check_runs:
        for message in check_errors:
            if message in seen:
                continue
            seen.add(message)
            errors.append(
                f"confirmed spec validation failed: {message}; "
                "run bash tools/check-spec.sh <spec_path> and /confirm-spec before /journey-map"
            )


def resolve_confirmed_spec(
    raw_spec_path: str,
    errors: typing.List[str],
    current_application_path: typing.Optional[str] = None,
    no_current_application: bool = False,
) -> typing.Tuple[typing.Optional[pathlib.Path], typing.Optional[typing.Dict[str, Json]]]:
    current_application = load_current_application(
        current_application_path,
        errors,
        no_current_application,
    )
    entry_spec_path = pathlib.Path(raw_spec_path)
    current_subsidy_id = (
        current_application.get("subsidy_id")
        if isinstance(current_application, dict)
        else None
    )
    if current_subsidy_id is not None and not isinstance(current_subsidy_id, str):
        errors.append("current application subsidy_id must be a string")
        current_subsidy_id = None
    if current_application is not None:
        current_spec_path = current_application.get("spec_path")
        if not isinstance(current_spec_path, str) or not current_spec_path:
            errors.append("current application spec_path must be a non-empty string")
        else:
            entry_spec_path = pathlib.Path(current_spec_path)

    try:
        resolved = spec_resolver.resolve_application_spec(
            REPO_ROOT,
            current_subsidy_id,
            entry_spec_path,
        )
    except spec_resolver.ResolverError as exc:
        errors.extend(exc.messages)
        return None, None

    spec = load_json(resolved.spec_path, errors, "spec")
    if not isinstance(spec, dict):
        return resolved.spec_path, None

    validate_current_application(current_application, spec, errors)
    validate_confirmed_spec(resolved.spec_path, spec, errors)
    if resolved.stale_entry_path is not None and not errors:
        print(
            "INFO: resolved canonical spec "
            f"{display_path(resolved.spec_path)} instead of stale entry "
            f"{display_path(resolved.stale_entry_path)}"
        )
    return resolved.spec_path, spec


def resolve_journey_output_path(raw_path: str, errors: typing.List[str]) -> typing.Optional[pathlib.Path]:
    out_path = pathlib.Path(raw_path)
    try:
        resolved_out = out_path.resolve()
        journey_root = (pathlib.Path.cwd() / "input" / "journey").resolve()
        resolved_out.relative_to(journey_root)
    except (OSError, ValueError):
        errors.append(f"output path must be under input/journey/: {out_path}")
        return None
    return out_path


# ---------------------------------------------------------------------------
# Minimal JSON Schema interpreter (subset used by journey-flow.schema.json:
# type / required / properties / additionalProperties / items / enum /
# minItems). Keeping the schema file as the single source of truth avoids
# maintaining a parallel hand-written structural validator.
# ---------------------------------------------------------------------------

_TYPE_CHECKS = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
}


def validate_schema(value: Json, schema: Json, path: str, errors: typing.List[str]) -> None:
    expected_type = schema.get("type")
    if expected_type is not None:
        types = expected_type if isinstance(expected_type, list) else [expected_type]
        if not any(_TYPE_CHECKS[t](value) for t in types):
            errors.append(f"schema violation: {path} must be of type {'/'.join(types)}")
            return
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"schema violation: {path} must be one of {schema['enum']}")
        return
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"schema violation: {path}.{key} is required")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for key in value:
                if key not in properties:
                    errors.append(f"schema violation: {path}.{key} is not an allowed key")
        for key, subschema in properties.items():
            if key in value:
                validate_schema(value[key], subschema, f"{path}.{key}", errors)
    elif isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"schema violation: {path} must have at least {schema['minItems']} items")
        items = schema.get("items")
        if items is not None:
            for index, item in enumerate(value):
                validate_schema(item, items, f"{path}[{index}]", errors)


# ---------------------------------------------------------------------------
# derive
# ---------------------------------------------------------------------------


def load_base_flow(errors: typing.List[str]) -> Json:
    base = load_json(BASE_FLOW_PATH, errors, "base flow")
    if base is None:
        return None
    steps = base.get("steps")
    if not isinstance(steps, list) or not steps:
        errors.append("base flow must contain a non-empty steps array")
        return None
    step_ids = set()
    for step in steps:
        if not isinstance(step, dict) or not isinstance(step.get("step_id"), str):
            errors.append("base flow steps must be objects with a step_id")
            return None
        step_ids.add(step["step_id"])
    for required in REQUIRED_BASE_STEPS:
        if required not in step_ids:
            errors.append(f"base flow is missing required step: {required}")
    lanes = base.get("lanes")
    if not isinstance(lanes, list) or not lanes:
        errors.append("base flow must define lanes")
    return None if errors else base


def kit_step(base_step: Json) -> Json:
    return {
        "step_id": f"kit-{base_step['step_id']}",
        "origin": "kit",
        "base_step_id": base_step["step_id"],
        "label": base_step["label"],
        "description": base_step.get("description"),
        "lane": base_step["lane"],
        "zone": "application",
        "kind": base_step["kind"],
        "human_gate": bool(base_step.get("human_gate")),
        "deliverable_ids": [],
        "event_ids": [],
        "clause_ids": [],
        "deadline": None,
        "deadline_time": None,
        "issuer": None,
        "next": [f"kit-{next_id}" for next_id in base_step.get("next", [])],
        "branches": [
            {"label": branch["label"], "next": f"kit-{branch['next']}"}
            for branch in base_step.get("branches", [])
        ],
    }


def verb_phrase(deliverable: Json) -> str:
    key = (deliverable.get("produced_by"), deliverable.get("type"))
    template = VERB_PHRASES.get(key, "{name}に対応する")
    return template.format(name=deliverable.get("name", ""))


def optional_note(deliverable: Json) -> typing.Optional[str]:
    if deliverable.get("required") is False or deliverable.get("required_if") is not None:
        return "該当する場合のみ行います。"
    return None


def event_date_key(event: Json) -> str:
    for field in ("date", "starts_at", "ends_at"):
        value = event.get(field)
        if isinstance(value, str) and value:
            return value
    return DATE_MAX_KEY


def event_deadline_date(event: Json) -> typing.Optional[str]:
    for field in ("date", "ends_at"):
        value = event.get(field)
        if isinstance(value, str) and value:
            return value
    return None


def event_time(event: Json) -> typing.Optional[str]:
    value = event.get("time")
    if isinstance(value, str) and value:
        return value
    return None


def derived_step(
    deliverable: Json,
    events_by_id: typing.Dict[str, Json],
    zone: str,
    errors: typing.List[str],
) -> Json:
    deliverable_id = deliverable.get("deliverable_id")
    lane = LANE_BY_PRODUCED_BY.get(deliverable.get("produced_by"))
    if lane is None:
        errors.append(f"deliverable {deliverable_id} has unknown produced_by")
        lane = "owner"
    deadline = None
    deadline_time = None
    event_ids: typing.List[str] = []
    due_event_id = deliverable.get("due_event_id")
    if due_event_id:
        event = events_by_id.get(due_event_id)
        if event is None:
            errors.append(
                f"deliverable {deliverable_id} references unknown due_event_id: {due_event_id}"
            )
        else:
            event_ids.append(due_event_id)
            date = event_deadline_date(event)
            if date:
                deadline = date
                time = event_time(event)
                if time:
                    deadline_time = time
    description = optional_note(deliverable)
    return {
        "step_id": f"sp-{deliverable_id}",
        "origin": "derived",
        "base_step_id": None,
        "label": verb_phrase(deliverable),
        "description": description,
        "lane": lane,
        "zone": zone,
        "kind": "process",
        "human_gate": False,
        "deliverable_ids": [deliverable_id],
        "event_ids": event_ids,
        "clause_ids": [],
        "deadline": deadline,
        "deadline_time": deadline_time,
        "issuer": deliverable.get("issuer"),
        "next": [],
        "branches": [],
    }


def period_milestone(event: Json) -> Json:
    deadline = None
    for field in ("ends_at", "date"):
        value = event.get(field)
        if isinstance(value, str) and value:
            deadline = value
            break
    return {
        "step_id": f"ev-{event['event_id']}",
        "origin": "derived",
        "base_step_id": None,
        "label": str(event.get("name", "")),
        "description": None,
        "lane": "owner",
        "zone": "post_adoption",
        "kind": "milestone",
        "human_gate": False,
        "deliverable_ids": [],
        "event_ids": [event["event_id"]],
        "clause_ids": [],
        "deadline": deadline,
        "deadline_time": None,
        "issuer": None,
        "next": [],
        "branches": [],
    }


def absorbed_due_milestone(event: Json, deliverable_ids: typing.List[str]) -> Json:
    event_id = event["event_id"]
    return {
        "step_id": f"ev-{event_id}",
        "origin": "derived",
        "base_step_id": None,
        "label": str(event.get("name", "")),
        "description": None,
        "lane": "owner",
        "zone": "application",
        "kind": "milestone",
        "human_gate": False,
        "deliverable_ids": list(deliverable_ids),
        "event_ids": [event_id],
        "clause_ids": [],
        "deadline": event_deadline_date(event),
        "deadline_time": event_time(event),
        "issuer": None,
        "next": [],
        "branches": [],
    }


def displayed_event_ids(steps: typing.Iterable[Json]) -> typing.Set[str]:
    visible: typing.Set[str] = set()
    for step in steps:
        if step["deadline"] is None and step["kind"] != "milestone":
            continue
        for event_id in step["event_ids"]:
            if isinstance(event_id, str):
                visible.add(event_id)
    return visible


def absorbed_due_sort_key(
    event_id: str,
    events_by_id: typing.Dict[str, Json],
) -> typing.Tuple[str, str, str]:
    event = events_by_id.get(event_id) or {}
    return (
        event_deadline_date(event) or DATE_MAX_KEY,
        event_time(event) or "",
        event_id,
    )


def append_absorbed_due(
    absorbed_due: typing.Dict[str, typing.Dict[str, typing.List[str]]],
    anchor_id: str,
    deliverable: Json,
    events_by_id: typing.Dict[str, Json],
    errors: typing.List[str],
) -> None:
    deliverable_id = deliverable.get("deliverable_id")
    due_event_id = deliverable.get("due_event_id")
    if not due_event_id:
        return
    if not isinstance(due_event_id, str) or due_event_id not in events_by_id:
        errors.append(
            f"deliverable {deliverable_id} references unknown due_event_id: {due_event_id}"
        )
        return
    event_deliverables = absorbed_due[anchor_id].setdefault(due_event_id, [])
    if deliverable_id not in event_deliverables:
        event_deliverables.append(deliverable_id)


def merged_absorbed_deliverable_ids(
    absorbed_due: typing.Dict[str, typing.Dict[str, typing.List[str]]],
    event_id: str,
) -> typing.List[str]:
    deliverable_ids: typing.List[str] = []
    seen: typing.Set[str] = set()
    for anchor_id in ("kit-draft", "kit-submit"):
        for deliverable_id in absorbed_due[anchor_id].get(event_id, []):
            if deliverable_id in seen:
                continue
            seen.add(deliverable_id)
            deliverable_ids.append(deliverable_id)
    return deliverable_ids


def due_milestones_for_anchor(
    anchor_id: str,
    absorbed_due: typing.Dict[str, typing.Dict[str, typing.List[str]]],
    events_by_id: typing.Dict[str, Json],
    visible_event_ids: typing.Set[str],
    existing_step_ids: typing.Set[str],
    generated_event_ids: typing.Set[str],
    errors: typing.List[str],
) -> typing.List[Json]:
    milestones: typing.List[Json] = []
    event_ids = sorted(
        absorbed_due[anchor_id],
        key=lambda event_id: absorbed_due_sort_key(event_id, events_by_id),
    )
    for event_id in event_ids:
        if event_id in visible_event_ids or event_id in generated_event_ids:
            continue
        step_id = f"ev-{event_id}"
        if step_id in existing_step_ids:
            errors.append(f"cannot derive duplicate milestone step_id: {step_id}")
            continue
        event = events_by_id[event_id]
        milestones.append(
            absorbed_due_milestone(
                event,
                merged_absorbed_deliverable_ids(absorbed_due, event_id),
            )
        )
        generated_event_ids.add(event_id)
        existing_step_ids.add(step_id)
    return milestones


def chain(steps: typing.List[Json], tail_next: typing.List[str]) -> None:
    """Link steps sequentially; the last one points at tail_next."""
    for index, step in enumerate(steps):
        if index + 1 < len(steps):
            step["next"] = [steps[index + 1]["step_id"]]
        else:
            step["next"] = list(tail_next)


def insert_after_step(anchor_step: Json, inserted_steps: typing.List[Json]) -> None:
    if not inserted_steps:
        return
    tail = anchor_step["next"]
    chain(inserted_steps, tail)
    anchor_step["next"] = [inserted_steps[0]["step_id"]]


def insert_before_step(
    steps: typing.Iterable[Json],
    target_id: str,
    inserted_steps: typing.List[Json],
    errors: typing.List[str],
) -> None:
    if not inserted_steps:
        return
    first_inserted_id = inserted_steps[0]["step_id"]
    rewired = False
    for step in steps:
        for index, next_id in enumerate(step["next"]):
            if next_id == target_id:
                step["next"][index] = first_inserted_id
                rewired = True
        for branch in step["branches"]:
            if branch["next"] == target_id:
                branch["next"] = first_inserted_id
                rewired = True
    if not rewired:
        errors.append(f"cannot insert milestone before missing target step: {target_id}")
        return
    chain(inserted_steps, [target_id])


def order_post_adoption(
    entries: typing.List[typing.Tuple[str, Json]],
    deliverables_by_id: typing.Dict[str, Json],
    errors: typing.List[str],
) -> typing.List[Json]:
    """Order post-adoption steps deterministically.

    Priority: earliest related date, then original spec order. depends_on
    edges between post-adoption deliverables are honored via a stable
    Kahn topological sort.
    """
    keyed = []
    for index, (date_key, step) in enumerate(entries):
        keyed.append({"date_key": date_key, "index": index, "step": step})
    id_to_entry = {}
    for entry in keyed:
        for deliverable_id in entry["step"]["deliverable_ids"]:
            id_to_entry[deliverable_id] = entry
    in_degree = {entry["index"]: 0 for entry in keyed}
    dependents: typing.Dict[int, typing.List[int]] = {entry["index"]: [] for entry in keyed}
    for entry in keyed:
        for deliverable_id in entry["step"]["deliverable_ids"]:
            deliverable = deliverables_by_id.get(deliverable_id)
            if not deliverable:
                continue
            for dependency_id in deliverable.get("depends_on", []) or []:
                dependency = id_to_entry.get(dependency_id)
                if dependency is not None and dependency["index"] != entry["index"]:
                    in_degree[entry["index"]] += 1
                    dependents[dependency["index"]].append(entry["index"])
    by_index = {entry["index"]: entry for entry in keyed}
    ready = sorted(
        [entry for entry in keyed if in_degree[entry["index"]] == 0],
        key=lambda entry: (entry["date_key"], entry["index"]),
    )
    ordered: typing.List[Json] = []
    while ready:
        current = ready.pop(0)
        ordered.append(current["step"])
        for dependent_index in dependents[current["index"]]:
            in_degree[dependent_index] -= 1
            if in_degree[dependent_index] == 0:
                ready.append(by_index[dependent_index])
        ready.sort(key=lambda entry: (entry["date_key"], entry["index"]))
    if len(ordered) < len(keyed):
        errors.append("post-adoption deliverables have a depends_on cycle")
        return []
    return ordered


def derive_flow_from_spec(
    spec: Json,
    spec_path: pathlib.Path,
    base: Json,
    errors: typing.List[str],
) -> typing.Optional[Json]:
    deliverables = spec.get("deliverables")
    schedule = spec.get("schedule")
    if not isinstance(deliverables, list):
        errors.append("spec.deliverables must be an array")
    if not isinstance(schedule, list):
        errors.append("spec.schedule must be an array")
    if errors:
        return None

    events_by_id = {
        event.get("event_id"): event
        for event in schedule
        if isinstance(event, dict) and event.get("event_id")
    }
    deliverables_by_id = {
        deliverable.get("deliverable_id"): deliverable
        for deliverable in deliverables
        if isinstance(deliverable, dict) and deliverable.get("deliverable_id")
    }

    steps_by_id: typing.Dict[str, Json] = {}
    for base_step in base["steps"]:
        step = kit_step(base_step)
        steps_by_id[step["step_id"]] = step

    draft_names: typing.List[str] = []
    submit_names: typing.List[str] = []
    prep_steps: typing.List[Json] = []
    pre_final_steps: typing.List[Json] = []
    post_entries: typing.List[typing.Tuple[str, Json]] = []
    absorbed_due = {"kit-draft": {}, "kit-submit": {}}

    for deliverable in deliverables:
        if not isinstance(deliverable, dict):
            errors.append("spec.deliverables entries must be objects")
            continue
        deliverable_id = deliverable.get("deliverable_id")
        produced_by = deliverable.get("produced_by")
        phase = deliverable.get("phase")
        depends_on = deliverable.get("depends_on") or []
        if not deliverable_id or produced_by not in LANE_BY_PRODUCED_BY or phase not in ZONES:
            errors.append(f"deliverable entry is missing id/produced_by/phase: {deliverable_id!r}")
            continue

        if phase == "post_adoption":
            step = derived_step(deliverable, events_by_id, "post_adoption", errors)
            date_key = DATE_MAX_KEY
            if step["event_ids"]:
                date_key = event_date_key(events_by_id[step["event_ids"][0]])
            post_entries.append((date_key, step))
            continue

        if produced_by == "ai_draftable":
            step = steps_by_id["kit-draft"]
            step["deliverable_ids"].append(deliverable_id)
            append_absorbed_due(absorbed_due, "kit-draft", deliverable, events_by_id, errors)
            draft_names.append(str(deliverable.get("name", "")))
            continue

        if produced_by == "human_only" and not depends_on:
            prep_steps.append(derived_step(deliverable, events_by_id, "application", errors))
            continue

        if produced_by == "human_only" and deliverable.get("type") == "procedure":
            step = steps_by_id["kit-submit"]
            step["deliverable_ids"].append(deliverable_id)
            append_absorbed_due(absorbed_due, "kit-submit", deliverable, events_by_id, errors)
            submit_names.append(str(deliverable.get("name", "")))
            continue

        # external deliverables and remaining human_only documents both sit
        # between review and finalize.
        pre_final_steps.append(derived_step(deliverable, events_by_id, "application", errors))

    # Application deadline is always shown on the submit step.
    application_deadline = None
    for event in schedule:
        if isinstance(event, dict) and event.get("event_kind") == "application_deadline":
            application_deadline = event
            break
    if application_deadline is not None:
        submit = steps_by_id["kit-submit"]
        date = application_deadline.get("date") or application_deadline.get("ends_at")
        if isinstance(date, str) and date:
            submit["deadline"] = date
            time = application_deadline.get("time")
            if isinstance(time, str) and time:
                submit["deadline_time"] = time
            submit["event_ids"].append(application_deadline.get("event_id"))

    # Project period events become milestones inside the post-adoption zone.
    for event in schedule:
        if isinstance(event, dict) and event.get("event_kind") == "project_period":
            if not event.get("event_id"):
                continue
            step = period_milestone(event)
            post_entries.append((event_date_key(event), step))

    visibility_steps = (
        list(steps_by_id.values())
        + prep_steps
        + pre_final_steps
        + [entry[1] for entry in post_entries]
    )
    visible_event_ids = displayed_event_ids(visibility_steps)
    existing_step_ids = {step["step_id"] for step in visibility_steps}
    generated_event_ids: typing.Set[str] = set()
    draft_due_milestones = due_milestones_for_anchor(
        "kit-draft",
        absorbed_due,
        events_by_id,
        visible_event_ids,
        existing_step_ids,
        generated_event_ids,
        errors,
    )
    submit_due_milestones = due_milestones_for_anchor(
        "kit-submit",
        absorbed_due,
        events_by_id,
        visible_event_ids,
        existing_step_ids,
        generated_event_ids,
        errors,
    )

    if draft_names:
        draft = steps_by_id["kit-draft"]
        draft["description"] = (
            (draft["description"] or "") + "作る下書き: " + "、".join(draft_names) + "。"
        )
    if submit_names:
        submit = steps_by_id["kit-submit"]
        submit["description"] = (
            (submit["description"] or "") + "、".join(submit_names) + "も自分の手で行います。"
        )

    if prep_steps:
        env = steps_by_id["kit-env-setup"]
        tail = env["next"]
        chain(prep_steps, tail)
        env["next"] = [prep_steps[0]["step_id"]]
    if pre_final_steps:
        review = steps_by_id["kit-review"]
        tail = review["next"]
        chain(pre_final_steps, tail)
        review["next"] = [pre_final_steps[0]["step_id"]]
    insert_after_step(steps_by_id["kit-draft"], draft_due_milestones)
    insert_before_step(
        list(steps_by_id.values()) + prep_steps + pre_final_steps,
        "kit-submit",
        submit_due_milestones,
        errors,
    )

    post_steps = order_post_adoption(post_entries, deliverables_by_id, errors)
    if post_steps:
        chain(post_steps, [])
        steps_by_id["kit-result"]["next"] = [post_steps[0]["step_id"]]

    if errors:
        return None

    ordered_steps: typing.List[Json] = []
    for base_step in base["steps"]:
        if base_step["step_id"] == "submit":
            ordered_steps.extend(submit_due_milestones)
        step = steps_by_id[f"kit-{base_step['step_id']}"]
        ordered_steps.append(step)
        if base_step["step_id"] == "env-setup":
            ordered_steps.extend(prep_steps)
        elif base_step["step_id"] == "review":
            ordered_steps.extend(pre_final_steps)
        elif base_step["step_id"] == "draft":
            ordered_steps.extend(draft_due_milestones)
    ordered_steps.extend(post_steps)

    spec_path_text = str(spec_path)
    try:
        spec_path_text = str(spec_path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        pass

    return {
        "flow_version": 1,
        "subsidy_id": spec.get("subsidy_id"),
        "subsidy_name": spec.get("name"),
        "round": spec.get("round"),
        "spec_path": spec_path_text,
        "spec_version": spec.get("spec_version"),
        "lanes": [
            {"lane_id": lane["lane_id"], "label": lane["label"]} for lane in base["lanes"]
        ],
        "steps": ordered_steps,
    }


def derive_flow(spec_path: pathlib.Path, errors: typing.List[str]) -> typing.Optional[Json]:
    spec = load_json(spec_path, errors, "spec")
    base = load_base_flow(errors)
    if errors or spec is None or base is None:
        return None
    if not isinstance(spec, dict):
        errors.append("spec must be an object")
        return None
    return derive_flow_from_spec(spec, spec_path, base, errors)


# ---------------------------------------------------------------------------
# render: validation gate
# ---------------------------------------------------------------------------


def step_edges(step: Json) -> typing.List[str]:
    if step["kind"] == "decision":
        return [branch["next"] for branch in step["branches"]]
    return list(step["next"])


def reaches_target_through_ai_steps(
    start_ids: typing.Iterable[str],
    target_id: str,
    steps_by_id: typing.Dict[str, Json],
) -> bool:
    stopped: typing.Set[str] = set()
    visited: typing.Set[str] = set()
    stack = list(start_ids)
    while stack:
        current_id = stack.pop()
        if current_id in visited:
            continue
        visited.add(current_id)
        step = steps_by_id[current_id]
        if step["origin"] == "ai":
            stack.extend(step_edges(step))
        else:
            stopped.add(current_id)
    return target_id in stopped


def validate_protected_flow(
    flow: Json,
    base: Json,
    spec: Json,
    errors: typing.List[str],
) -> None:
    for flow_field, spec_field in PROTECTED_FLOW_METADATA:
        if flow.get(flow_field) != spec.get(spec_field):
            errors.append(f"flow {flow_field} does not match the spec")
    if errors:
        return

    rederive_errors: typing.List[str] = []
    reference = derive_flow_from_spec(
        spec,
        pathlib.Path(flow.get("spec_path", "")),
        base,
        rederive_errors,
    )
    if reference is None or rederive_errors:
        detail = "; ".join(rederive_errors or ["derive failed"])
        errors.append(f"spec re-derivation failed: {detail}")
        return

    flow_steps_by_id = {step["step_id"]: step for step in flow["steps"]}
    reference_steps_by_id = {step["step_id"]: step for step in reference["steps"]}

    for reference_step in reference["steps"]:
        step_id = reference_step["step_id"]
        flow_step = flow_steps_by_id.get(step_id)
        if flow_step is None:
            errors.append(f"step {step_id} is required and cannot be removed")
            continue
        for field in PROTECTED_STEP_FIELDS:
            if flow_step[field] != reference_step[field]:
                errors.append(f"step {step_id} protected field {field} changed")
        if len(flow_step["next"]) != len(reference_step["next"]):
            errors.append(f"step {step_id} has extra or missing transitions")
        if reference_step["kind"] == "decision":
            reference_labels = [branch["label"] for branch in reference_step["branches"]]
            flow_labels = [branch["label"] for branch in flow_step["branches"]]
            if flow_labels != reference_labels:
                errors.append(f"step {step_id} protected field branches.label changed")

    for flow_step in flow["steps"]:
        step_id = flow_step["step_id"]
        if flow_step["origin"] != "ai" and step_id not in reference_steps_by_id:
            errors.append(
                f"step {step_id} has origin={flow_step['origin']} but is not derivable; "
                "only origin=ai steps may be added"
            )

    for reference_step in reference["steps"]:
        step_id = reference_step["step_id"]
        flow_step = flow_steps_by_id.get(step_id)
        if flow_step is None:
            continue
        if reference_step["kind"] == "decision":
            for reference_branch, flow_branch in zip(
                reference_step["branches"], flow_step["branches"]
            ):
                if reference_branch["label"] != flow_branch["label"]:
                    continue
                target_id = reference_branch["next"]
                if not reaches_target_through_ai_steps(
                    [flow_branch["next"]], target_id, flow_steps_by_id
                ):
                    errors.append(
                        f"edge {step_id} -> {target_id} was rewired; "
                        "only ai-step insertion is allowed"
                    )
        else:
            for target_id in reference_step["next"]:
                if not reaches_target_through_ai_steps(
                    flow_step["next"], target_id, flow_steps_by_id
                ):
                    errors.append(
                        f"edge {step_id} -> {target_id} was rewired; "
                        "only ai-step insertion is allowed"
                    )


def validate_flow(
    flow: Json,
    base: Json,
    spec: Json,
    errors: typing.List[str],
) -> None:
    schema_errors: typing.List[str] = []
    schema = load_json(FLOW_SCHEMA_PATH, schema_errors, "flow schema")
    if schema is None:
        errors.extend(schema_errors)
        return
    validate_schema(flow, schema, "flow", errors)
    if errors:
        return

    base_step_ids = {step["step_id"] for step in base["steps"]}
    base_by_id = {step["step_id"]: step for step in base["steps"]}
    deliverable_ids = {
        deliverable.get("deliverable_id")
        for deliverable in spec.get("deliverables", [])
        if isinstance(deliverable, dict)
    }
    event_ids = {
        event.get("event_id")
        for event in spec.get("schedule", [])
        if isinstance(event, dict)
    }
    events_by_id = {
        event.get("event_id"): event
        for event in spec.get("schedule", [])
        if isinstance(event, dict)
    }
    clause_ids = {
        clause.get("clause_id")
        for clause in spec.get("clauses", [])
        if isinstance(clause, dict)
    }
    lane_ids = {lane["lane_id"] for lane in flow["lanes"]}

    steps = flow["steps"]
    steps_by_id: typing.Dict[str, Json] = {}
    for step in steps:
        step_id = step["step_id"]
        if step_id in steps_by_id:
            errors.append(f"duplicate step_id: {step_id}")
        steps_by_id[step_id] = step

    for step in steps:
        step_id = step["step_id"]
        origin = step["origin"]
        if step["lane"] not in lane_ids:
            errors.append(f"step {step_id} uses undefined lane: {step['lane']}")
        if origin == "kit":
            base_id = step["base_step_id"]
            if base_id not in base_step_ids:
                errors.append(f"step {step_id} references unknown base step: {base_id}")
            else:
                base_step = base_by_id[base_id]
                for field in ("label", "lane", "kind"):
                    if step[field] != base_step[field]:
                        errors.append(
                            f"step {step_id} must keep base {field} (got {step[field]!r})"
                        )
                if step["human_gate"] != bool(base_step.get("human_gate")):
                    errors.append(f"step {step_id} must keep base human_gate")
        else:
            if step["base_step_id"] is not None:
                errors.append(f"step {step_id} (origin={origin}) must not set base_step_id")
        if origin == "derived":
            if not step["deliverable_ids"] and not step["event_ids"]:
                errors.append(
                    f"step {step_id} (origin=derived) needs deliverable_ids or event_ids"
                )
        if origin == "ai":
            if not step["clause_ids"]:
                errors.append(f"step {step_id} (origin=ai) needs at least one clause id")
            if (
                step["kind"] not in ("process", "milestone")
                or step["branches"]
                or len(step["next"]) != 1
            ):
                errors.append(
                    f"step {step_id} (origin=ai) must be a single-exit "
                    "process/milestone insertion"
                )
        for deliverable_id in step["deliverable_ids"]:
            if deliverable_id not in deliverable_ids:
                errors.append(f"step {step_id} references unknown deliverable: {deliverable_id}")
        for event_id in step["event_ids"]:
            if event_id not in event_ids:
                errors.append(f"step {step_id} references unknown event: {event_id}")
        for clause_id in step["clause_ids"]:
            if clause_id not in clause_ids:
                errors.append(f"step {step_id} references unknown clause: {clause_id}")
        if step["deadline"] is not None:
            if not step["event_ids"]:
                errors.append(f"step {step_id} has a deadline without a source event")
            else:
                dates = set()
                for event_id in step["event_ids"]:
                    event = events_by_id.get(event_id)
                    if event:
                        for field in ("date", "starts_at", "ends_at"):
                            value = event.get(field)
                            if isinstance(value, str) and value:
                                dates.add(value)
                if step["deadline"] not in dates:
                    errors.append(
                        f"step {step_id} deadline {step['deadline']} does not match its events"
                    )
        for event_id in step["event_ids"]:
            event = events_by_id.get(event_id)
            if not event:
                continue
            displayed_deadline = event_deadline_date(event)
            if not displayed_deadline:
                continue
            if step["deadline"] is None:
                errors.append(
                    f"step {step_id} references dated event {event_id} without displaying a deadline"
                )
            elif step["deadline"] != displayed_deadline:
                errors.append(
                    f"step {step_id} displays {step['deadline']} but event {event_id} "
                    f"has deadline {displayed_deadline}"
                )
        if step["kind"] == "decision":
            if len(step["branches"]) < 2:
                errors.append(f"step {step_id} (decision) needs at least 2 branches")
            if step["next"]:
                errors.append(f"step {step_id} (decision) must use branches, not next")
        elif step["branches"]:
            errors.append(f"step {step_id} (kind={step['kind']}) must not have branches")

    for step in steps:
        for target_id in step_edges(step):
            if target_id not in steps_by_id:
                errors.append(f"step {step['step_id']} points at unknown step: {target_id}")
                continue
            target = steps_by_id[target_id]
            if step["zone"] == "post_adoption" and target["zone"] == "application":
                errors.append(
                    f"step {step['step_id']} flows backwards from post_adoption to application"
                )

    if errors:
        return

    # One-way requirement: the flow graph must be a DAG with a single start
    # from which every step is reachable.
    in_degree = {step["step_id"]: 0 for step in steps}
    for step in steps:
        for target_id in step_edges(step):
            in_degree[target_id] += 1
    starts = [step_id for step_id, degree in in_degree.items() if degree == 0]
    if len(starts) != 1:
        errors.append(f"flow must have exactly one start step, found: {sorted(starts)}")
        return
    visited = set()
    stack = [starts[0]]
    while stack:
        current = stack.pop()
        if current in visited:
            continue
        visited.add(current)
        stack.extend(step_edges(steps_by_id[current]))
    unreachable = sorted(set(steps_by_id) - visited)
    if unreachable:
        errors.append(f"steps unreachable from the start: {unreachable}")
    remaining = dict(in_degree)
    queue = [starts[0]]
    seen = 0
    while queue:
        current = queue.pop()
        seen += 1
        for target_id in step_edges(steps_by_id[current]):
            remaining[target_id] -= 1
            if remaining[target_id] == 0:
                queue.append(target_id)
    if seen < len(steps):
        errors.append("flow contains a cycle (one-way rule: no backward arrows)")
    if errors:
        return

    validate_protected_flow(flow, base, spec, errors)


# ---------------------------------------------------------------------------
# render: SVG / HTML
# ---------------------------------------------------------------------------

CANVAS_W = 1080
LANE_W = 340
LANE_GAP = 10
MARGIN_X = 20
LANE_HEAD_H = 44
ROW_H = 112
BOX_W = 300
BOX_H = 84
ZONE_PAD = 46
FOOT_PAD = 24

COLOR_BOX = "#f1f5f9"
COLOR_BOX_STROKE = "#64748b"
COLOR_GATE = "#fef3c7"
COLOR_GATE_STROKE = "#d97706"
COLOR_TEXT = "#1e293b"
COLOR_SUB = "#475569"
COLOR_DEADLINE = "#b91c1c"
COLOR_EDGE = "#64748b"
COLOR_ZONE = "#7c3aed"


def display_width(text: str) -> float:
    return sum(0.5 if ord(char) < 128 else 1.0 for char in text)


def wrap_text(text: str, max_units: float, max_lines: int) -> typing.List[str]:
    lines: typing.List[str] = []
    current = ""
    current_units = 0.0
    for char in text:
        char_units = 0.5 if ord(char) < 128 else 1.0
        if current_units + char_units > max_units and current:
            lines.append(current)
            current = char
            current_units = char_units
        else:
            current += char
            current_units += char_units
    if current:
        lines.append(current)
    if len(lines) > max_lines:
        kept = lines[:max_lines]
        last = kept[-1]
        while display_width(last) > max_units - 1 and last:
            last = last[:-1]
        kept[-1] = last + "…"
        return kept
    return lines


def lane_x(lane_index: int) -> int:
    return MARGIN_X + lane_index * (LANE_W + LANE_GAP)


def svg_text_lines(
    x: float,
    y: float,
    lines: typing.List[str],
    size: int,
    color: str,
    weight: str = "normal",
    anchor: str = "middle",
    line_height: int = 18,
) -> typing.List[str]:
    parts = []
    for index, line in enumerate(lines):
        parts.append(
            f'<text x="{x:.0f}" y="{y + index * line_height:.0f}" '
            f'font-size="{size}" fill="{color}" font-weight="{weight}" '
            f'text-anchor="{anchor}">{html.escape(line)}</text>'
        )
    return parts


def render_svg(flow: Json) -> str:
    lanes = flow["lanes"]
    lane_index = {lane["lane_id"]: index for index, lane in enumerate(lanes)}
    steps = flow["steps"]

    # Draw rows in a stable topological order so arrows always point down.
    steps_by_id = {step["step_id"]: step for step in steps}
    order_index = {step["step_id"]: index for index, step in enumerate(steps)}

    def edges_of(step: Json) -> typing.List[str]:
        if step["kind"] == "decision":
            return [branch["next"] for branch in step["branches"]]
        return list(step["next"])

    in_degree = {step["step_id"]: 0 for step in steps}
    for step in steps:
        for target in edges_of(step):
            in_degree[target] += 1
    ready = sorted(
        [step_id for step_id, degree in in_degree.items() if degree == 0],
        key=lambda step_id: order_index[step_id],
    )
    ordered: typing.List[Json] = []
    while ready:
        current_id = ready.pop(0)
        ordered.append(steps_by_id[current_id])
        for target in edges_of(steps_by_id[current_id]):
            in_degree[target] -= 1
            if in_degree[target] == 0:
                ready.append(target)
        ready.sort(key=lambda step_id: order_index[step_id])

    # Row layout with an extra gap when entering the post-adoption zone.
    positions: typing.Dict[str, typing.Tuple[float, float]] = {}
    y = LANE_HEAD_H + 24
    zone_top: typing.Optional[float] = None
    for step in ordered:
        if step["zone"] == "post_adoption" and zone_top is None:
            y += ZONE_PAD
            zone_top = y - 18
        center_x = lane_x(lane_index[step["lane"]]) + LANE_W / 2
        positions[step["step_id"]] = (center_x, y)
        y += ROW_H
    zone_bottom = y - ROW_H + BOX_H + 18 if zone_top is not None else None
    height = y + FOOT_PAD

    parts: typing.List[str] = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS_W} {height:.0f}" '
        f'role="img" aria-label="{html.escape(str(flow.get("subsidy_name") or ""))} 申請の流れ">'
    )
    parts.append(
        '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" '
        'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{COLOR_EDGE}"/></marker></defs>'
    )

    for index, lane in enumerate(lanes):
        x = lane_x(index)
        parts.append(
            f'<rect x="{x}" y="0" width="{LANE_W}" height="{LANE_HEAD_H - 8}" '
            f'rx="8" fill="#e2e8f0"/>'
        )
        parts.extend(
            svg_text_lines(
                x + LANE_W / 2,
                (LANE_HEAD_H - 8) / 2 + 5,
                [lane["label"]],
                15,
                COLOR_TEXT,
                weight="bold",
            )
        )
        parts.append(
            f'<line x1="{x + LANE_W / 2}" y1="{LANE_HEAD_H}" x2="{x + LANE_W / 2}" '
            f'y2="{height - FOOT_PAD}" stroke="#e2e8f0" stroke-width="1"/>'
        )

    if zone_top is not None and zone_bottom is not None:
        parts.append(
            f'<rect x="8" y="{zone_top:.0f}" width="{CANVAS_W - 16}" '
            f'height="{zone_bottom - zone_top:.0f}" rx="12" fill="none" '
            f'stroke="{COLOR_ZONE}" stroke-width="2" stroke-dasharray="8 6"/>'
        )
        parts.extend(
            svg_text_lines(
                24,
                zone_top - 10,
                ["ここから先は採択後"],
                14,
                COLOR_ZONE,
                weight="bold",
                anchor="start",
            )
        )

    # Edges first, boxes on top.
    for step in ordered:
        from_x, from_y = positions[step["step_id"]]
        step_height = BOX_H
        edges = (
            [(branch["label"], branch["next"]) for branch in step["branches"]]
            if step["kind"] == "decision"
            else [(None, target) for target in step["next"]]
        )
        for edge_index, (edge_label, target_id) in enumerate(edges):
            to_x, to_y = positions[target_id]
            start_y = from_y + step_height
            end_y = to_y - 4
            label_x: typing.Optional[float] = None
            label_y: typing.Optional[float] = None
            label_anchor = "middle"
            if step["kind"] == "decision" and to_x < from_x - 1:
                start_x = from_x - BOX_W / 2
                start_y = from_y + step_height / 2
                path = (
                    f'M {start_x:.0f} {start_y:.0f} L {to_x:.0f} {start_y:.0f} '
                    f'L {to_x:.0f} {end_y:.0f}'
                )
                label_x = start_x - 8
                label_y = start_y - 8
                label_anchor = "end"
            elif step["kind"] == "decision" and to_x > from_x + 1:
                start_x = from_x + BOX_W / 2
                start_y = from_y + step_height / 2
                path = (
                    f'M {start_x:.0f} {start_y:.0f} L {to_x:.0f} {start_y:.0f} '
                    f'L {to_x:.0f} {end_y:.0f}'
                )
                label_x = start_x + 8
                label_y = start_y - 8
                label_anchor = "start"
            elif abs(to_x - from_x) < 1:
                path = f'M {from_x:.0f} {start_y:.0f} L {to_x:.0f} {end_y:.0f}'
                if step["kind"] == "decision":
                    label_x = from_x + 8
                    label_y = start_y + 16
                    label_anchor = "start"
            else:
                mid_y = start_y + 16
                path = (
                    f'M {from_x:.0f} {start_y:.0f} L {from_x:.0f} {mid_y:.0f} '
                    f'L {to_x:.0f} {mid_y:.0f} L {to_x:.0f} {end_y:.0f}'
                )
            parts.append(
                f'<path d="{path}" fill="none" stroke="{COLOR_EDGE}" '
                f'stroke-width="1.6" marker-end="url(#arrow)"/>'
            )
            if edge_label:
                if label_x is None or label_y is None:
                    label_x = from_x + (edge_index * 2 - 1) * 40
                    label_y = start_y + 14
                parts.extend(
                    svg_text_lines(
                        label_x,
                        label_y,
                        [edge_label],
                        12,
                        COLOR_SUB,
                        anchor=label_anchor,
                    )
                )

    for step in ordered:
        center_x, top_y = positions[step["step_id"]]
        box_x = center_x - BOX_W / 2
        is_gate = bool(step["human_gate"])
        fill = COLOR_GATE if is_gate else COLOR_BOX
        stroke = COLOR_GATE_STROKE if is_gate else COLOR_BOX_STROKE
        if step["kind"] == "decision":
            points = (
                f"{center_x:.0f},{top_y:.0f} "
                f"{center_x + BOX_W / 2:.0f},{top_y + BOX_H / 2:.0f} "
                f"{center_x:.0f},{top_y + BOX_H:.0f} "
                f"{center_x - BOX_W / 2:.0f},{top_y + BOX_H / 2:.0f}"
            )
            parts.append(
                f'<polygon points="{points}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>'
            )
        elif step["kind"] in ("milestone", "terminal"):
            parts.append(
                f'<rect x="{box_x:.0f}" y="{top_y:.0f}" width="{BOX_W}" height="{BOX_H}" '
                f'rx="{BOX_H / 2:.0f}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>'
            )
        else:
            parts.append(
                f'<rect x="{box_x:.0f}" y="{top_y:.0f}" width="{BOX_W}" height="{BOX_H}" '
                f'rx="10" fill="{fill}" stroke="{stroke}" stroke-width="2"/>'
            )

        text_max_units = 19.0 if step["kind"] != "decision" else 15.0
        label_lines = wrap_text(str(step["label"]), text_max_units, 2)
        extra_lines: typing.List[typing.Tuple[str, str]] = []
        if step["issuer"]:
            extra_lines.append((f"窓口: {step['issuer']}", COLOR_SUB))
        if step["deadline"]:
            deadline_text = f"締切 {step['deadline']}"
            if step["kind"] == "milestone":
                deadline_text = f"期限 {step['deadline']}"
            if step["deadline_time"]:
                deadline_text += f" {step['deadline_time']}"
            extra_lines.append((deadline_text, COLOR_DEADLINE))
        if is_gate:
            extra_lines.append(("あなたが確認・実行", COLOR_GATE_STROKE))

        total_lines = len(label_lines) + len(extra_lines)
        line_height = 17
        block_height = total_lines * line_height
        text_y = top_y + BOX_H / 2 - block_height / 2 + 13
        parts.extend(
            svg_text_lines(center_x, text_y, label_lines, 14, COLOR_TEXT, weight="bold", line_height=line_height)
        )
        extra_y = text_y + len(label_lines) * line_height
        for text, color in extra_lines:
            parts.extend(
                svg_text_lines(
                    center_x,
                    extra_y,
                    wrap_text(text, 21.0, 1),
                    12,
                    color,
                    line_height=line_height,
                )
            )
            extra_y += line_height

    parts.append("</svg>")
    return "".join(parts)


def render_html(flow: Json) -> str:
    name = html.escape(str(flow.get("subsidy_name") or ""))
    round_name = flow.get("round")
    round_html = f'<p class="round">{html.escape(str(round_name))}</p>' if round_name else ""
    svg = render_svg(flow)
    descriptions = []
    for step in flow["steps"]:
        if step.get("description"):
            descriptions.append(
                f"<dt>{html.escape(str(step['label']))}</dt>"
                f"<dd>{html.escape(str(step['description']))}</dd>"
            )
    description_html = ""
    if descriptions:
        description_html = (
            '<section class="notes"><h2>各工程のひとこと補足</h2><dl>'
            + "".join(descriptions)
            + "</dl></section>"
        )
    return f"""<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>{name} 申請の流れ</title>
<style>
body {{ font-family: "Hiragino Sans", "Yu Gothic", "Noto Sans JP", sans-serif;
       color: #1e293b; background: #ffffff; margin: 0 auto; padding: 24px 16px 48px;
       max-width: 1120px; }}
h1 {{ font-size: 22px; margin: 0 0 4px; }}
.round {{ color: #475569; margin: 0 0 12px; }}
.notice {{ background: #fef3c7; border: 1px solid #d97706; border-radius: 8px;
           padding: 10px 14px; font-size: 14px; margin: 0 0 16px; }}
.legend {{ font-size: 13px; color: #475569; margin: 0 0 12px; }}
.legend span {{ margin-right: 16px; }}
.legend .amber {{ border-left: 12px solid #d97706; padding-left: 6px; }}
.legend .dashed {{ border-left: 12px solid #7c3aed; padding-left: 6px; }}
svg {{ width: 100%; height: auto; }}
.notes {{ margin-top: 24px; font-size: 14px; }}
.notes h2 {{ font-size: 16px; }}
.notes dt {{ font-weight: bold; margin-top: 10px; }}
.notes dd {{ margin: 2px 0 0 0; color: #475569; }}
footer {{ margin-top: 24px; font-size: 12px; color: #64748b; }}
</style>
</head>
<body>
<header>
<h1>{name} 申請の流れ</h1>
{round_html}
<p class="notice">この図は全体の流れをつかむための地図です。提出物ではありません。正式な内容は必ず公募要領で確認してください。</p>
<p class="legend">
<span class="amber">色つきの工程 = あなた自身が確認・実行する工程</span>
<span class="dashed">破線の囲み = 採択された後の工程</span>
<span>ひし形 = 分かれ道</span>
</p>
</header>
{svg}
{description_html}
<footer>公募要領をもとに作成した参考図です。日付や手続きは公募要領が正です。</footer>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def cmd_derive(args: argparse.Namespace) -> int:
    errors: typing.List[str] = []
    spec_path, _spec = resolve_confirmed_spec(
        args.spec_path,
        errors,
        args.current_application,
        args.no_current_application,
    )
    if spec_path is None or errors:
        for message in errors:
            print(f"NG: {message}")
        return 1
    flow = derive_flow(spec_path, errors)
    if flow is None or errors:
        for message in errors or ["derive failed"]:
            print(f"NG: {message}")
        return 1
    out_path = resolve_journey_output_path(args.out, errors)
    if out_path is None or errors:
        for message in errors:
            print(f"NG: {message}")
        return 1
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(flow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"OK: derived journey flow: {out_path} (steps: {len(flow['steps'])})")
    return 0


def cmd_render(args: argparse.Namespace) -> int:
    errors: typing.List[str] = []
    flow = load_json(pathlib.Path(args.flow_path), errors, "flow")
    if flow is None:
        for message in errors:
            print(f"NG: {message}")
        return 1
    spec_path = args.spec or (flow.get("spec_path") if isinstance(flow, dict) else None)
    if not isinstance(spec_path, str) or not spec_path:
        print("NG: flow has no spec_path and --spec was not given")
        return 1
    resolved_spec_path, spec = resolve_confirmed_spec(
        spec_path,
        errors,
        args.current_application,
        args.no_current_application,
    )
    if resolved_spec_path is None or spec is None or errors:
        for message in errors:
            print(f"NG: {message}")
        return 1
    base = load_base_flow(errors)
    if base is None:
        for message in errors:
            print(f"NG: {message}")
        return 1
    validate_flow(flow, base, spec, errors)
    if errors:
        for message in errors:
            print(f"NG: {message}")
        return 1
    out_path = resolve_journey_output_path(args.out, errors)
    if out_path is None or errors:
        for message in errors:
            print(f"NG: {message}")
        return 1
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render_html(flow), encoding="utf-8")
    print(f"OK: rendered journey map: {out_path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Derive and render subsidy application journey flowcharts."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    derive_parser = subparsers.add_parser(
        "derive", help="build a journey flow JSON from a confirmed spec"
    )
    derive_parser.add_argument("spec_path")
    derive_parser.add_argument("--out", required=True)
    derive_current_application_group = derive_parser.add_mutually_exclusive_group()
    derive_current_application_group.add_argument("--current-application", default=None)
    derive_current_application_group.add_argument(
        "--no-current-application",
        action="store_true",
    )
    derive_parser.set_defaults(func=cmd_derive)

    render_parser = subparsers.add_parser(
        "render", help="validate a flow JSON and render the journey HTML"
    )
    render_parser.add_argument("flow_path")
    render_parser.add_argument("--out", required=True)
    render_parser.add_argument("--spec", default=None)
    render_current_application_group = render_parser.add_mutually_exclusive_group()
    render_current_application_group.add_argument("--current-application", default=None)
    render_current_application_group.add_argument(
        "--no-current-application",
        action="store_true",
    )
    render_parser.set_defaults(func=cmd_render)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
