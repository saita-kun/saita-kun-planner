#!/usr/bin/env python3
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import sys
import typing
import unicodedata

import spec_resolver


LOWER_ID_RE = re.compile(r"^[a-z0-9-]+$")
CLAUSE_ID_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
DOCUMENT_ID_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
VALID_STATUSES = {"draft", "confirmed"}
VALID_CONFIRMATION_STATES = {"confirmed", "na", "open"}
VALID_CONFIRMED_BY = {"applicant", "provider"}
VALID_CONFIRMED_VIA = {"group-table", "individual"}
VALID_PREDICATE_STATES = {"encoded", "not_encodable", "pending"}
VALID_PREDICATE_SCOPES = {"profile", "application"}
VALID_PREDICATE_OPS = {"eq", "ne", "lt", "lte", "gt", "gte", "in", "contains", "exists"}
PAGE_ANCHOR_RE = re.compile(r"^## p\.\d+\s*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ISO8601_LIKE_RE = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}"
    r"(?:T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:Z|[+-][0-9]{2}:[0-9]{2})?)?$"
)
ISO_DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
JST = datetime.timezone(datetime.timedelta(hours=9), name="JST")


Json = typing.Any


class DeadlineEvaluation(typing.NamedTuple):
    event_id: str
    raw_date: str
    raw_time: typing.Optional[str]
    expired: bool


def normalize_verbatim_text(text: str) -> str:
    normalized = unicodedata.normalize("NFKC", text)
    return "".join(char for char in normalized if not char.isspace())


def normalize_extract_text(text: str) -> str:
    body_lines = [
        line
        for line in text.splitlines()
        if not line.startswith("# ") and not PAGE_ANCHOR_RE.match(line)
    ]
    return normalize_verbatim_text("\n".join(body_lines))


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


def require_key(obj: Json, key: str, path: str, errors: typing.List[str]) -> bool:
    if not isinstance(obj, dict) or key not in obj:
        errors.append(f"missing required key: {path}.{key}")
        return False
    return True


def require_list(obj: Json, key: str, path: str, errors: typing.List[str]) -> typing.List[Json]:
    if not require_key(obj, key, path, errors):
        return []
    value = obj[key]
    if not isinstance(value, list):
        errors.append(f"{path}.{key} must be an array")
        return []
    if not value:
        errors.append(f"{path}.{key} must not be empty")
    return value


def collect_ids(
    items: typing.List[Json],
    key: str,
    pattern: re.Pattern[str],
    label: str,
    errors: typing.List[str],
) -> typing.Set[str]:
    seen: typing.Set[str] = set()
    for index, item in enumerate(items):
        item_path = f"{label}[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{item_path} must be an object")
            continue
        value = item.get(key)
        if not isinstance(value, str) or not value:
            errors.append(f"missing or invalid id: {item_path}.{key}")
            continue
        if not pattern.match(value):
            errors.append(f"bad id pattern: {item_path}.{key}={value}")
        if value in seen:
            errors.append(f"duplicate id: {key}={value}")
        seen.add(value)
    return seen


def load_taxonomy_ids(root: pathlib.Path, errors: typing.List[str]) -> typing.Set[str]:
    taxonomy_path = root / "schemas" / "taxonomy-v1.json"
    taxonomy = load_json(taxonomy_path, errors, "taxonomy")
    ids: typing.Set[str] = set()
    if not isinstance(taxonomy, dict):
        return ids
    categories = taxonomy.get("categories")
    if not isinstance(categories, list):
        errors.append("taxonomy.categories must be an array")
        return ids
    for index, category in enumerate(categories):
        if not isinstance(category, dict) or not isinstance(category.get("id"), str):
            errors.append(f"taxonomy.categories[{index}].id must be a string")
            continue
        ids.add(category["id"])
    return ids


def check_required_structure(spec: Json, errors: typing.List[str]) -> None:
    if not isinstance(spec, dict):
        errors.append("spec root must be an object")
        return

    for key in (
        "subsidy_id",
        "schema_version",
        "spec_version",
        "status",
        "source_documents",
        "schedule",
        "eligibility",
        "funding",
        "deliverables",
        "clauses",
    ):
        require_key(spec, key, "$", errors)

    if spec.get("schema_version") != "2.0":
        errors.append("schema_version must be 2.0")

    status = spec.get("status")
    if status not in VALID_STATUSES:
        errors.append("status must be draft or confirmed")

    subsidy_id = spec.get("subsidy_id")
    if not isinstance(subsidy_id, str) or not LOWER_ID_RE.match(subsidy_id):
        errors.append("subsidy_id must match ^[a-z0-9-]+$")

    eligibility = spec.get("eligibility")
    if isinstance(eligibility, dict):
        require_list(eligibility, "rules", "$.eligibility", errors)
    elif "eligibility" in spec:
        errors.append("$.eligibility must be an object")

    funding = spec.get("funding")
    if isinstance(funding, dict):
        if not require_key(funding, "base_award", "$.funding", errors):
            return
        if not isinstance(funding.get("base_award"), dict):
            errors.append("$.funding.base_award must be an object")
    elif "funding" in spec:
        errors.append("$.funding must be an object")


def find_source_clause_refs(value: Json, path: str, errors: typing.List[str]) -> typing.List[typing.Tuple[str, str]]:
    refs: typing.List[typing.Tuple[str, str]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}" if path else key
            if key == "source_clauses":
                if not isinstance(child, list):
                    errors.append(f"{child_path} must be an array")
                    continue
                for index, clause_id in enumerate(child):
                    ref_path = f"{child_path}[{index}]"
                    if isinstance(clause_id, str):
                        refs.append((ref_path, clause_id))
                    else:
                        errors.append(f"{ref_path} must be a string")
            else:
                refs.extend(find_source_clause_refs(child, child_path, errors))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            refs.extend(find_source_clause_refs(child, f"{path}[{index}]", errors))
    return refs


def require_source_clauses(item: Json, path: str, errors: typing.List[str]) -> None:
    if not isinstance(item, dict):
        return
    value = item.get("source_clauses")
    if not isinstance(value, list) or not value:
        errors.append(f"missing or empty source_clauses: {path}.source_clauses")


def check_fact_source_clauses(spec: typing.Dict[str, Json], errors: typing.List[str]) -> None:
    schedule = spec.get("schedule") if isinstance(spec.get("schedule"), list) else []
    eligibility = spec.get("eligibility") if isinstance(spec.get("eligibility"), dict) else {}
    rules = eligibility.get("rules") if isinstance(eligibility.get("rules"), list) else []
    funding = spec.get("funding") if isinstance(spec.get("funding"), dict) else {}
    deliverables = spec.get("deliverables") if isinstance(spec.get("deliverables"), list) else []

    for index, event in enumerate(schedule):
        require_source_clauses(event, f"$.schedule[{index}]", errors)
    for index, rule in enumerate(rules):
        require_source_clauses(rule, f"$.eligibility.rules[{index}]", errors)

    require_source_clauses(funding.get("base_award"), "$.funding.base_award", errors)
    for key in ("add_ons", "combinations", "eligible_expenses"):
        items = funding.get(key) if isinstance(funding.get(key), list) else []
        for index, item in enumerate(items):
            require_source_clauses(item, f"$.funding.{key}[{index}]", errors)

    bonus_items = spec.get("bonus_items") if isinstance(spec.get("bonus_items"), list) else []
    for index, item in enumerate(bonus_items):
        require_source_clauses(item, f"$.bonus_items[{index}]", errors)

    for deliverable_index, deliverable in enumerate(deliverables):
        require_source_clauses(deliverable, f"$.deliverables[{deliverable_index}]", errors)
        sections = deliverable.get("sections") if isinstance(deliverable, dict) and isinstance(deliverable.get("sections"), list) else []
        for section_index, section in enumerate(sections):
            require_source_clauses(section, f"$.deliverables[{deliverable_index}].sections[{section_index}]", errors)


def check_source_documents(spec: typing.Dict[str, Json], errors: typing.List[str]) -> None:
    source_documents = spec.get("source_documents") if isinstance(spec.get("source_documents"), list) else []
    for index, document in enumerate(source_documents):
        document_path = f"$.source_documents[{index}]"
        if not isinstance(document, dict):
            errors.append(f"{document_path} must be an object")
            continue

        for key in ("document_id", "title", "url_or_path"):
            if key not in document:
                errors.append(f"missing required key: {document_path}.{key}")
                continue
            if not isinstance(document.get(key), str) or not document.get(key):
                errors.append(f"{document_path}.{key} must be a non-empty string")

        sha256 = document.get("sha256")
        if sha256 is not None and (not isinstance(sha256, str) or not SHA256_RE.match(sha256)):
            errors.append(f"{document_path}.sha256 must be null or a 64-character lowercase hex string")

        extract_path = document.get("extract_path")
        if extract_path is not None and not isinstance(extract_path, str):
            errors.append(f"{document_path}.extract_path must be a string or null")


def validate_predicate(predicate: Json, path: str, errors: typing.List[str]) -> None:
    if predicate is None:
        return
    if not isinstance(predicate, dict):
        errors.append(f"invalid predicate: {path} must be null or an object")
        return

    keys = set(predicate)
    if "all" in predicate:
        if keys != {"all"}:
            errors.append(f"invalid predicate: {path}.all must be the only key")
            return
        items = predicate.get("all")
        if not isinstance(items, list) or not items:
            errors.append(f"invalid predicate: {path}.all must be a non-empty array")
            return
        for index, item in enumerate(items):
            validate_predicate(item, f"{path}.all[{index}]", errors)
        return

    if "any" in predicate:
        if keys != {"any"}:
            errors.append(f"invalid predicate: {path}.any must be the only key")
            return
        items = predicate.get("any")
        if not isinstance(items, list) or not items:
            errors.append(f"invalid predicate: {path}.any must be a non-empty array")
            return
        for index, item in enumerate(items):
            validate_predicate(item, f"{path}.any[{index}]", errors)
        return

    if "not" in predicate:
        if keys != {"not"}:
            errors.append(f"invalid predicate: {path}.not must be the only key")
            return
        validate_predicate(predicate.get("not"), f"{path}.not", errors)
        return

    allowed_leaf_keys = {"scope", "key", "op", "value"}
    unexpected = sorted(keys - allowed_leaf_keys)
    if unexpected:
        errors.append(f"invalid predicate: {path} has unexpected keys: {', '.join(unexpected)}")
        return

    scope = predicate.get("scope")
    key = predicate.get("key")
    op = predicate.get("op")
    if scope not in VALID_PREDICATE_SCOPES:
        errors.append(f"invalid predicate: {path}.scope must be profile or application")
    if not isinstance(key, str) or not key:
        errors.append(f"invalid predicate: {path}.key must be a non-empty string")
    if op not in VALID_PREDICATE_OPS:
        errors.append(f"invalid predicate: {path}.op is not supported")
    elif op != "exists" and "value" not in predicate:
        errors.append(f"invalid predicate: {path}.value is required unless op=exists")


def check_predicates(spec: typing.Dict[str, Json], errors: typing.List[str]) -> None:
    eligibility = spec.get("eligibility") if isinstance(spec.get("eligibility"), dict) else {}
    rules = eligibility.get("rules") if isinstance(eligibility.get("rules"), list) else []
    for index, rule in enumerate(rules):
        if isinstance(rule, dict):
            validate_predicate(rule.get("predicate"), f"$.eligibility.rules[{index}].predicate", errors)

    deliverables = spec.get("deliverables") if isinstance(spec.get("deliverables"), list) else []
    for index, deliverable in enumerate(deliverables):
        if isinstance(deliverable, dict):
            validate_predicate(deliverable.get("required_if"), f"$.deliverables[{index}].required_if", errors)


def required_confirmation_field_paths(spec: typing.Dict[str, Json]) -> typing.List[str]:
    # Confirmation field_path convention:
    # schedule.<event_id>, eligibility.rules.<rule_id>, funding.base_award,
    # funding.add_ons.<addon_id>, funding.combinations.<addon_id+addon_id>,
    # funding.eligible_expenses.<category>, bonus_items.<bonus_id>,
    # deliverables.<deliverable_id>, and
    # deliverables.<deliverable_id>.sections.<section_id>.<max_chars|max_pages>.
    paths: typing.List[str] = []

    schedule = spec.get("schedule") if isinstance(spec.get("schedule"), list) else []
    for event in schedule:
        if isinstance(event, dict) and isinstance(event.get("event_id"), str):
            paths.append(f"schedule.{event['event_id']}")

    eligibility = spec.get("eligibility") if isinstance(spec.get("eligibility"), dict) else {}
    rules = eligibility.get("rules") if isinstance(eligibility.get("rules"), list) else []
    for rule in rules:
        if isinstance(rule, dict) and isinstance(rule.get("rule_id"), str):
            paths.append(f"eligibility.rules.{rule['rule_id']}")

    funding = spec.get("funding") if isinstance(spec.get("funding"), dict) else {}
    if isinstance(funding.get("base_award"), dict):
        paths.append("funding.base_award")
    add_ons = funding.get("add_ons") if isinstance(funding.get("add_ons"), list) else []
    for add_on in add_ons:
        if isinstance(add_on, dict) and isinstance(add_on.get("addon_id"), str):
            paths.append(f"funding.add_ons.{add_on['addon_id']}")
    combinations = funding.get("combinations") if isinstance(funding.get("combinations"), list) else []
    for combination in combinations:
        if isinstance(combination, dict):
            addon_ids = combination.get("addon_ids")
            if isinstance(addon_ids, list) and addon_ids and all(isinstance(addon_id, str) for addon_id in addon_ids):
                paths.append(f"funding.combinations.{'+'.join(addon_ids)}")
    eligible_expenses = funding.get("eligible_expenses") if isinstance(funding.get("eligible_expenses"), list) else []
    for expense in eligible_expenses:
        if isinstance(expense, dict) and isinstance(expense.get("category"), str):
            paths.append(f"funding.eligible_expenses.{expense['category']}")

    bonus_items = spec.get("bonus_items") if isinstance(spec.get("bonus_items"), list) else []
    for bonus_item in bonus_items:
        if isinstance(bonus_item, dict) and isinstance(bonus_item.get("bonus_id"), str):
            paths.append(f"bonus_items.{bonus_item['bonus_id']}")

    deliverables = spec.get("deliverables") if isinstance(spec.get("deliverables"), list) else []
    for deliverable in deliverables:
        if not isinstance(deliverable, dict) or not isinstance(deliverable.get("deliverable_id"), str):
            continue
        deliverable_id = deliverable["deliverable_id"]
        paths.append(f"deliverables.{deliverable_id}")
        sections = deliverable.get("sections") if isinstance(deliverable.get("sections"), list) else []
        for section in sections:
            if not isinstance(section, dict) or not isinstance(section.get("section_id"), str):
                continue
            section_id = section["section_id"]
            if section.get("max_chars") is not None:
                paths.append(f"deliverables.{deliverable_id}.sections.{section_id}.max_chars")
            if section.get("max_pages") is not None:
                paths.append(f"deliverables.{deliverable_id}.sections.{section_id}.max_pages")

    return paths


def confirmation_path_for(spec_path: pathlib.Path) -> pathlib.Path:
    return spec_path.with_name(f"{spec_path.stem}.confirmation.json")


def display_spec_path(spec_path: pathlib.Path) -> str:
    root = pathlib.Path(__file__).resolve().parents[2]
    try:
        return spec_path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return spec_path.as_posix()


def spec_path_candidates(spec_path: pathlib.Path) -> typing.Set[str]:
    root = pathlib.Path(__file__).resolve().parents[2]
    candidates = {spec_path.as_posix(), display_spec_path(spec_path)}
    try:
        candidates.add(spec_path.resolve().as_posix())
    except OSError:
        pass
    try:
        candidates.add(spec_path.resolve().relative_to(pathlib.Path.cwd().resolve()).as_posix())
    except ValueError:
        pass
    try:
        candidates.add(spec_path.resolve().relative_to(root.resolve()).as_posix())
    except ValueError:
        pass
    return candidates


def resolve_extract_path(spec_path: pathlib.Path, root: pathlib.Path, extract_path: str) -> pathlib.Path:
    path = pathlib.Path(extract_path)
    if path.is_absolute():
        return path

    root_relative = root / path
    if root_relative.exists():
        return root_relative

    spec_relative = spec_path.parent / path
    if spec_relative.exists():
        return spec_relative

    return root_relative


def mandatory_or_exclude_rules(spec: typing.Dict[str, Json]) -> typing.List[typing.Dict[str, Json]]:
    eligibility = spec.get("eligibility") if isinstance(spec.get("eligibility"), dict) else {}
    rules = eligibility.get("rules") if isinstance(eligibility.get("rules"), list) else []
    return [
        rule
        for rule in rules
        if isinstance(rule, dict) and rule.get("kind") in {"mandatory", "exclude"}
    ]


def ai_draftable_prose_sections(spec: typing.Dict[str, Json]) -> typing.List[typing.Dict[str, Json]]:
    deliverables = spec.get("deliverables") if isinstance(spec.get("deliverables"), list) else []
    sections: typing.List[typing.Dict[str, Json]] = []
    for deliverable in deliverables:
        if not isinstance(deliverable, dict) or deliverable.get("produced_by") != "ai_draftable":
            continue
        deliverable_sections = deliverable.get("sections")
        if not isinstance(deliverable_sections, list):
            continue
        for section in deliverable_sections:
            if isinstance(section, dict) and section.get("kind") == "prose":
                sections.append(section)
    return sections


def verbatim_check(
    spec: typing.Dict[str, Json],
    spec_path: pathlib.Path,
    root: pathlib.Path,
    gate: typing.Optional[str],
    errors: typing.List[str],
    warnings: typing.List[str],
) -> typing.Dict[str, int]:
    source_documents = spec.get("source_documents") if isinstance(spec.get("source_documents"), list) else []
    clauses = spec.get("clauses") if isinstance(spec.get("clauses"), list) else []

    extract_by_document: typing.Dict[str, str] = {}
    extract_text_by_document: typing.Dict[str, str] = {}
    for index, document in enumerate(source_documents):
        if not isinstance(document, dict):
            continue
        document_id = document.get("document_id")
        if not isinstance(document_id, str):
            continue
        if "extract_path" not in document or document.get("extract_path") is None:
            continue
        extract_path = document.get("extract_path")
        if not isinstance(extract_path, str) or not extract_path:
            errors.append(f"invalid extract_path: $.source_documents[{index}].extract_path")
            continue
        extract_by_document[document_id] = extract_path

        resolved = resolve_extract_path(spec_path, root, extract_path)
        try:
            raw_text = resolved.read_text(encoding="utf-8")
        except FileNotFoundError:
            errors.append(f"extract file not found: $.source_documents[{index}].extract_path={extract_path}")
            continue
        except OSError as exc:
            errors.append(f"extract file cannot be read: $.source_documents[{index}].extract_path={extract_path}: {exc}")
            continue
        extract_text_by_document[document_id] = normalize_extract_text(raw_text)

    stats = {"target": 0, "matched": 0, "mismatched": 0, "skipped_no_extract": 0}
    for index, clause in enumerate(clauses):
        if not isinstance(clause, dict):
            continue
        source_document_id = clause.get("source_document_id")
        if not isinstance(source_document_id, str):
            continue
        if source_document_id not in extract_by_document:
            stats["skipped_no_extract"] += 1
            continue

        raw_clause_text = clause.get("raw_text")
        text = clause.get("text")
        if isinstance(raw_clause_text, str) and raw_clause_text:
            needle_text = raw_clause_text
            needle_field = "raw_text"
        elif isinstance(text, str) and text:
            needle_text = text
            needle_field = "text"
        else:
            message = f"clause verbatim text missing: $.clauses[{index}].raw_text or $.clauses[{index}].text"
            if gate == "confirm":
                errors.append(message)
            else:
                warnings.append(message)
            stats["target"] += 1
            stats["mismatched"] += 1
            continue

        extract_text = extract_text_by_document.get(source_document_id)
        if extract_text is None:
            continue

        stats["target"] += 1
        clause_text = normalize_verbatim_text(needle_text)
        clause_id = clause.get("clause_id", f"index-{index}")
        if clause_text and clause_text in extract_text:
            stats["matched"] += 1
            continue

        message = f"clause verbatim mismatch: $.clauses[{index}].{needle_field} ({clause_id}) not found in extract_path for document {source_document_id}"
        if gate == "confirm":
            errors.append(message)
        else:
            warnings.append(message)
        stats["mismatched"] += 1

    return stats


def check_confirmation_spec_reference(
    spec: typing.Dict[str, Json],
    spec_path: pathlib.Path,
    confirmation: typing.Dict[str, Json],
    errors: typing.List[str],
) -> None:
    expected_path = confirmation.get("spec_path")
    if not isinstance(expected_path, str) or not expected_path:
        errors.append("confirmation.spec_path must be a non-empty string")
    elif expected_path not in spec_path_candidates(spec_path):
        errors.append(f"confirmation spec_path mismatch: expected {display_spec_path(spec_path)}, got {expected_path}")

    expected_version = spec.get("spec_version")
    confirmation_version = confirmation.get("spec_version")
    if confirmation_version != expected_version:
        errors.append(f"confirmation spec_version mismatch: expected {expected_version!r}, got {confirmation_version!r}")


def check_confirmation_structure(
    spec: typing.Dict[str, Json],
    spec_path: pathlib.Path,
    confirmation: typing.Dict[str, Json],
    errors: typing.List[str],
) -> typing.Dict[str, typing.Dict[str, Json]]:
    check_confirmation_spec_reference(spec, spec_path, confirmation, errors)

    status = spec.get("status")

    for key in ("spec_sha256", "confirmed_by", "confirmed_at"):
        require_key(confirmation, key, "confirmation", errors)

    spec_sha256 = confirmation.get("spec_sha256")
    if spec_sha256 is None:
        if status == "confirmed":
            errors.append("confirmation.spec_sha256 must be a string when spec status is confirmed")
    elif not isinstance(spec_sha256, str):
        errors.append("confirmation.spec_sha256 must be a string or null")
    elif not SHA256_RE.match(spec_sha256):
        errors.append("confirmation.spec_sha256 must be a 64-character lowercase hex string")

    confirmed_by = confirmation.get("confirmed_by")
    if confirmed_by is None:
        if status == "confirmed":
            errors.append("confirmation.confirmed_by must be one of applicant, provider")
    elif confirmed_by not in VALID_CONFIRMED_BY:
        errors.append(f"confirmation.confirmed_by must be one of applicant, provider: {confirmed_by!r}")

    confirmed_at = confirmation.get("confirmed_at")
    if confirmed_at is None:
        if status == "confirmed":
            errors.append("confirmation.confirmed_at must be a string when spec status is confirmed")
    elif not isinstance(confirmed_at, str):
        errors.append("confirmation.confirmed_at must be a string or null")
    elif not ISO8601_LIKE_RE.match(confirmed_at):
        errors.append("confirmation.confirmed_at must look like ISO8601")

    items = confirmation.get("items")
    if not isinstance(items, list):
        errors.append("confirmation.items must be an array")
        return {}
    if not items:
        errors.append("confirmation.items must not be empty")

    items_by_path: typing.Dict[str, typing.Dict[str, Json]] = {}
    for index, item in enumerate(items):
        item_path = f"confirmation.items[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{item_path} must be an object")
            continue

        field_path = item.get("field_path")
        if not isinstance(field_path, str) or not field_path:
            errors.append(f"{item_path}.field_path must be a non-empty string")
        elif field_path in items_by_path:
            errors.append(f"duplicate confirmation field_path: {field_path}")
        else:
            items_by_path[field_path] = item

        source_clauses = item.get("source_clauses")
        if not isinstance(source_clauses, list) or not source_clauses:
            errors.append(f"{item_path}.source_clauses must be a non-empty array")
        else:
            for clause_index, clause_id in enumerate(source_clauses):
                if not isinstance(clause_id, str):
                    errors.append(f"{item_path}.source_clauses[{clause_index}] must be a string")

        state = item.get("state")
        if state not in VALID_CONFIRMATION_STATES:
            errors.append(f"invalid confirmation state: {item_path}.state={state!r}")

        note = item.get("note")
        if not isinstance(note, str):
            errors.append(f"{item_path}.note must be a string")

        predicate_state = item.get("predicate_state")
        if predicate_state is not None and predicate_state not in VALID_PREDICATE_STATES:
            errors.append(f"{item_path}.predicate_state must be encoded, not_encodable, or pending")

        item_confirmed_at = item.get("confirmed_at")
        if item_confirmed_at is not None and not isinstance(item_confirmed_at, str):
            errors.append(f"{item_path}.confirmed_at must be a string")

        confirmed_via = item.get("confirmed_via")
        if confirmed_via is not None and confirmed_via not in VALID_CONFIRMED_VIA:
            errors.append(f"{item_path}.confirmed_via must be group-table or individual")

        shown_page = item.get("shown_page")
        if shown_page is not None and not isinstance(shown_page, (int, str)):
            errors.append(f"{item_path}.shown_page must be a number, string, or null")

    for field_path in required_confirmation_field_paths(spec):
        if field_path not in items_by_path:
            errors.append(f"confirmation missing required field_path: {field_path}")

    return items_by_path


def check_provider_confirmation_requirements(
    spec: typing.Dict[str, Json],
    confirmation: typing.Dict[str, Json],
    errors: typing.List[str],
) -> None:
    """Enforce metadata needed to publish a provider-confirmed bundled spec.

    Applicant-authored specs intentionally retain the schema's nullable
    ``round`` and ``portal_url`` boundary.
    """

    registry = spec.get("registry")
    is_bundled = isinstance(registry, dict) and registry.get("origin") == "bundled"
    if confirmation.get("confirmed_by") != "provider" or not is_bundled:
        return

    round_name = spec.get("round")
    if not isinstance(round_name, str) or not round_name:
        errors.append("provider confirmation requires spec.round to be non-null")

    portal_url = spec.get("portal_url")
    if not isinstance(portal_url, str) or not portal_url:
        errors.append("provider confirmation requires spec.portal_url to be non-null")

    items = confirmation.get("items")
    if not isinstance(items, list):
        return
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        item_path = f"confirmation.items[{index}].confirmed_at"
        raw_date = item.get("confirmed_at")
        if not isinstance(raw_date, str) or not ISO_DATE_RE.fullmatch(raw_date):
            errors.append(f"provider confirmation requires an ISO date: {item_path}")
            continue
        try:
            datetime.date.fromisoformat(raw_date)
        except ValueError:
            errors.append(f"provider confirmation requires a valid ISO date: {item_path}={raw_date!r}")


def check_required_confirmation_closed(
    spec: typing.Dict[str, Json],
    items_by_path: typing.Dict[str, typing.Dict[str, Json]],
    errors: typing.List[str],
) -> None:
    for field_path in required_confirmation_field_paths(spec):
        item = items_by_path.get(field_path)
        if isinstance(item, dict) and item.get("state") == "open":
            errors.append(f"unconfirmed required item: {field_path}")


def check_confirmation_sha(
    spec_path: pathlib.Path,
    confirmation_path: pathlib.Path,
    confirmation: typing.Dict[str, Json],
    errors: typing.List[str],
) -> None:
    actual_sha = hashlib.sha256(spec_path.read_bytes()).hexdigest()
    expected_sha = confirmation.get("spec_sha256")
    if expected_sha != actual_sha:
        errors.append(f"confirmation spec_sha256 mismatch: {confirmation_path}")


def check_confirm_gate(
    spec: typing.Dict[str, Json],
    items_by_path: typing.Dict[str, typing.Dict[str, Json]],
    errors: typing.List[str],
) -> None:
    check_required_confirmation_closed(spec, items_by_path, errors)
    for rule in mandatory_or_exclude_rules(spec):
        rule_id = rule.get("rule_id")
        if not isinstance(rule_id, str):
            continue
        field_path = f"eligibility.rules.{rule_id}"
        item = items_by_path.get(field_path)
        if not isinstance(item, dict) or item.get("state") == "na":
            continue
        predicate_state = item.get("predicate_state")
        if predicate_state is None:
            errors.append(f"missing predicate_state: {field_path}")
            continue
        if predicate_state == "pending":
            errors.append(f"predicate_state pending: {field_path}")
            continue
        predicate = rule.get("predicate")
        if predicate_state == "encoded" and predicate is None:
            errors.append(f"predicate_state mismatch: {field_path} encoded but predicate is null")
        if predicate_state == "not_encodable" and predicate is not None:
            errors.append(f"predicate_state mismatch: {field_path} not_encodable but predicate is non-null")


def readiness_lines(
    spec: typing.Dict[str, Json],
    confirmation: typing.Optional[typing.Dict[str, Json]],
    verbatim_stats: typing.Optional[typing.Dict[str, int]],
) -> typing.List[str]:
    states = {"confirmed": 0, "open": 0, "na": 0}
    predicate_items: typing.Dict[str, Json] = {}
    if isinstance(confirmation, dict):
        items = confirmation.get("items")
        if isinstance(items, list):
            for item in items:
                if not isinstance(item, dict):
                    continue
                state = item.get("state")
                if state in states:
                    states[state] += 1
                field_path = item.get("field_path")
                if isinstance(field_path, str) and field_path.startswith("eligibility.rules."):
                    predicate_items[field_path] = item

    target_rules = mandatory_or_exclude_rules(spec)
    encoded_rules = 0
    for rule in target_rules:
        rule_id = rule.get("rule_id")
        if not isinstance(rule_id, str):
            continue
        item = predicate_items.get(f"eligibility.rules.{rule_id}")
        if isinstance(item, dict) and item.get("predicate_state") == "encoded":
            encoded_rules += 1

    prose_sections = ai_draftable_prose_sections(spec)
    max_chars_null = sum(1 for section in prose_sections if section.get("max_chars") is None)

    source_documents = spec.get("source_documents") if isinstance(spec.get("source_documents"), list) else []
    sha256_null = sum(
        1
        for document in source_documents
        if isinstance(document, dict) and document.get("sha256") is None
    )

    return [
        f"confirmation {states['confirmed']} confirmed, {states['open']} open, {states['na']} na",
        f"predicate coverage {encoded_rules}/{len(target_rules)} encoded for mandatory+exclude rules",
        f"max_chars null {max_chars_null}/{len(prose_sections)} for prose ai_draftable sections",
        (
            "verbatim coverage "
            f"{(verbatim_stats or {}).get('matched', 0)}/{(verbatim_stats or {}).get('target', 0)} "
            "matched for clauses with extract_path; "
            f"{(verbatim_stats or {}).get('mismatched', 0)} mismatched; "
            f"{(verbatim_stats or {}).get('skipped_no_extract', 0)} skipped without extract_path"
        ),
        f"source_documents sha256 null {sha256_null}/{len(source_documents)}",
    ]


def check_reference_integrity(
    spec: typing.Dict[str, Json],
    root: pathlib.Path,
    errors: typing.List[str],
) -> None:
    source_documents = spec.get("source_documents") if isinstance(spec.get("source_documents"), list) else []
    schedule = spec.get("schedule") if isinstance(spec.get("schedule"), list) else []
    eligibility = spec.get("eligibility") if isinstance(spec.get("eligibility"), dict) else {}
    rules = eligibility.get("rules") if isinstance(eligibility.get("rules"), list) else []
    funding = spec.get("funding") if isinstance(spec.get("funding"), dict) else {}
    add_ons = funding.get("add_ons") if isinstance(funding.get("add_ons"), list) else []
    combinations = funding.get("combinations") if isinstance(funding.get("combinations"), list) else []
    deliverables = spec.get("deliverables") if isinstance(spec.get("deliverables"), list) else []
    clauses = spec.get("clauses") if isinstance(spec.get("clauses"), list) else []

    document_ids = collect_ids(source_documents, "document_id", DOCUMENT_ID_RE, "$.source_documents", errors)
    event_ids = collect_ids(schedule, "event_id", LOWER_ID_RE, "$.schedule", errors)
    rule_ids = collect_ids(rules, "rule_id", LOWER_ID_RE, "$.eligibility.rules", errors)
    addon_ids = collect_ids(add_ons, "addon_id", LOWER_ID_RE, "$.funding.add_ons", errors)
    deliverable_ids = collect_ids(deliverables, "deliverable_id", LOWER_ID_RE, "$.deliverables", errors)
    clause_ids = collect_ids(clauses, "clause_id", CLAUSE_ID_RE, "$.clauses", errors)

    for ref_path, clause_id in find_source_clause_refs(spec, "$", errors):
        if clause_id not in clause_ids:
            errors.append(f"unknown source_clauses reference: {ref_path}={clause_id}")

    for index, clause in enumerate(clauses):
        if not isinstance(clause, dict):
            continue
        source_document_id = clause.get("source_document_id")
        if not isinstance(source_document_id, str):
            errors.append(f"missing or invalid reference: $.clauses[{index}].source_document_id")
        elif source_document_id not in document_ids:
            errors.append(f"unknown source_document_id: $.clauses[{index}].source_document_id={source_document_id}")

    for index, deliverable in enumerate(deliverables):
        if not isinstance(deliverable, dict):
            continue
        due_event_id = deliverable.get("due_event_id")
        if due_event_id is None:
            continue
        if not isinstance(due_event_id, str):
            errors.append(f"$.deliverables[{index}].due_event_id must be a string or null")
        elif due_event_id not in event_ids:
            errors.append(f"unknown due_event_id: $.deliverables[{index}].due_event_id={due_event_id}")
        depends_on = deliverable.get("depends_on")
        if depends_on is None:
            continue
        if not isinstance(depends_on, list):
            errors.append(f"$.deliverables[{index}].depends_on must be an array")
            continue
        for depends_index, deliverable_id in enumerate(depends_on):
            if not isinstance(deliverable_id, str):
                errors.append(f"$.deliverables[{index}].depends_on[{depends_index}] must be a string")
            elif deliverable_id not in deliverable_ids:
                errors.append(f"unknown depends_on reference: $.deliverables[{index}].depends_on[{depends_index}]={deliverable_id}")

    for index, add_on in enumerate(add_ons):
        if not isinstance(add_on, dict):
            continue
        required_rules = add_on.get("required_rules")
        if not isinstance(required_rules, list):
            errors.append(f"$.funding.add_ons[{index}].required_rules must be an array")
            continue
        for rule_index, rule_id in enumerate(required_rules):
            if not isinstance(rule_id, str):
                errors.append(f"$.funding.add_ons[{index}].required_rules[{rule_index}] must be a string")
            elif rule_id not in rule_ids:
                errors.append(f"unknown required_rules reference: $.funding.add_ons[{index}].required_rules[{rule_index}]={rule_id}")

    for index, combination in enumerate(combinations):
        if not isinstance(combination, dict):
            continue
        combination_addons = combination.get("addon_ids")
        if not isinstance(combination_addons, list):
            errors.append(f"$.funding.combinations[{index}].addon_ids must be an array")
            continue
        for addon_index, addon_id in enumerate(combination_addons):
            if not isinstance(addon_id, str):
                errors.append(f"$.funding.combinations[{index}].addon_ids[{addon_index}] must be a string")
            elif addon_id not in addon_ids:
                errors.append(f"unknown addon_ids reference: $.funding.combinations[{index}].addon_ids[{addon_index}]={addon_id}")

    taxonomy_ids = load_taxonomy_ids(root, errors)
    category_tags = spec.get("category_tags", [])
    if category_tags is None:
        category_tags = []
    if not isinstance(category_tags, list):
        errors.append("$.category_tags must be an array")
    else:
        for index, tag in enumerate(category_tags):
            if not isinstance(tag, str):
                errors.append(f"$.category_tags[{index}] must be a string")
            elif tag not in taxonomy_ids:
                errors.append(f"unknown category_tags reference: $.category_tags[{index}]={tag}")

    if not any(isinstance(event, dict) and event.get("event_kind") == "application_deadline" for event in schedule):
        errors.append("schedule must include at least one event_kind=application_deadline")


def evaluate_application_deadlines(
    spec: typing.Dict[str, Json],
    now: datetime.datetime,
) -> typing.List[DeadlineEvaluation]:
    """Evaluate application deadlines once for both WARN and select gate.

    Deadline semantics are fixed to JST (+09:00). A deadline with ``time`` is
    expired only when ``now > deadline datetime``; equality remains active. A
    deadline without ``time`` is date-granular, so its calendar day remains
    active through the end of that JST day.
    """

    schedule = spec.get("schedule") if isinstance(spec.get("schedule"), list) else []
    now_jst = now.astimezone(JST)
    evaluations: typing.List[DeadlineEvaluation] = []
    for event in schedule:
        if not isinstance(event, dict) or event.get("event_kind") != "application_deadline":
            continue
        raw_date = event.get("date")
        if not isinstance(raw_date, str):
            continue
        try:
            deadline_date = datetime.date.fromisoformat(raw_date)
        except ValueError:
            continue

        raw_time = event.get("time")
        if raw_time is None:
            expired = now_jst.date() > deadline_date
        elif isinstance(raw_time, str):
            try:
                deadline_time = datetime.time.fromisoformat(raw_time)
            except ValueError:
                continue
            if deadline_time.tzinfo is not None:
                continue
            deadline_at = datetime.datetime.combine(deadline_date, deadline_time, tzinfo=JST)
            expired = now_jst > deadline_at
        else:
            continue

        event_id = event.get("event_id")
        evaluations.append(
            DeadlineEvaluation(
                event_id if isinstance(event_id, str) else "unknown",
                raw_date,
                raw_time,
                expired,
            )
        )
    return evaluations


def check_application_deadline_freshness(
    evaluations: typing.List[DeadlineEvaluation],
    warnings: typing.List[str],
) -> None:
    for evaluation in evaluations:
        if evaluation.expired:
            warnings.append(
                f"application deadline {evaluation.raw_date} has passed; "
                "公募回が更新されていないか公式サイトで確認してください"
            )


def check_select_gate(
    evaluations: typing.List[DeadlineEvaluation],
    errors: typing.List[str],
) -> None:
    if not any(not evaluation.expired for evaluation in evaluations):
        errors.append(
            "有効な申請締切が残っていません; "
            "公募回が更新されていないか公式サイトで確認してください"
        )


def check_confirmation_gateways(
    spec: typing.Dict[str, Json],
    spec_path: pathlib.Path,
    gate: typing.Optional[str],
    errors: typing.List[str],
) -> typing.Optional[typing.Dict[str, Json]]:
    confirmation_path = confirmation_path_for(spec_path)
    requires_confirmation = spec.get("status") == "confirmed" or gate == "confirm"
    if not requires_confirmation and not confirmation_path.exists():
        return None

    confirmation = load_json(confirmation_path, errors, "confirmation")
    if not isinstance(confirmation, dict):
        return None

    items_by_path = check_confirmation_structure(spec, spec_path, confirmation, errors)
    check_provider_confirmation_requirements(spec, confirmation, errors)
    if spec.get("status") == "confirmed" and gate != "confirm":
        check_confirmation_sha(spec_path, confirmation_path, confirmation, errors)
        check_confirm_gate(spec, items_by_path, errors)
    elif gate == "confirm":
        check_confirm_gate(spec, items_by_path, errors)
    return confirmation


def check_spec(
    spec_path: pathlib.Path,
    gate: typing.Optional[str] = None,
    now: typing.Optional[datetime.datetime] = None,
) -> typing.Tuple[typing.List[str], typing.List[str], typing.List[str]]:
    errors: typing.List[str] = []
    warnings: typing.List[str] = []
    root = pathlib.Path(__file__).resolve().parents[2]
    spec = load_json(spec_path, errors, "spec")
    if not isinstance(spec, dict):
        return errors, warnings, ["READINESS: unavailable because spec could not be loaded"]

    check_required_structure(spec, errors)
    require_list(spec, "source_documents", "$", errors)
    require_list(spec, "schedule", "$", errors)
    require_list(spec, "deliverables", "$", errors)
    require_list(spec, "clauses", "$", errors)
    check_source_documents(spec, errors)
    check_fact_source_clauses(spec, errors)
    check_predicates(spec, errors)
    check_reference_integrity(spec, root, errors)
    reference_now = now if now is not None else datetime.datetime.now(JST)
    deadline_evaluations = evaluate_application_deadlines(spec, reference_now)
    check_application_deadline_freshness(deadline_evaluations, warnings)
    if gate == "select":
        check_select_gate(deadline_evaluations, errors)
    verbatim_stats = verbatim_check(spec, spec_path, root, gate, errors, warnings)
    confirmation = check_confirmation_gateways(spec, spec_path, gate, errors)
    return errors, warnings, [f"READINESS: {line}" for line in readiness_lines(spec, confirmation, verbatim_stats)]


def parse_now(value: str) -> datetime.datetime:
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid ISO8601 datetime: {value}") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=JST)
    return parsed.astimezone(JST)


def main(argv: typing.List[str]) -> int:
    parser = argparse.ArgumentParser(
        usage=(
            "bash tools/check-spec.sh <spec.json> [--gate confirm|select] [--now ISO8601] "
            "| --list-bundled [--bundled-root DIR]"
        )
    )
    parser.add_argument("spec_path", nargs="?")
    parser.add_argument("--gate", choices=["confirm", "select"], default=None)
    parser.add_argument("--now", type=parse_now, default=None)
    parser.add_argument("--list-bundled", action="store_true")
    parser.add_argument("--bundled-root", default="specs")
    args = parser.parse_args(argv[1:])

    root = pathlib.Path(__file__).resolve().parents[2]
    if args.list_bundled:
        if args.spec_path is not None or args.gate is not None or args.now is not None:
            parser.error("--list-bundled cannot be combined with a spec path, --gate, or --now")
        bundled_root = pathlib.Path(args.bundled_root)
        try:
            candidates = spec_resolver.resolve_bundled_specs(bundled_root, root)
        except spec_resolver.ResolverError as exc:
            for message in exc.messages:
                print(f"FAIL: {message}")
            return 1
        for candidate in candidates:
            print(spec_resolver.repo_relative_path(candidate.spec_path, root))
        return 0

    if args.spec_path is None:
        parser.error("a spec path is required unless --list-bundled is used")
    if args.bundled_root != "specs":
        parser.error("--bundled-root requires --list-bundled")

    errors, warnings, readiness = check_spec(
        pathlib.Path(args.spec_path),
        args.gate,
        args.now,
    )
    for line in readiness:
        print(line)
    for warning in warnings:
        print(f"WARN: {warning}")
    for error in errors:
        print(f"FAIL: {error}")
    if errors:
        return 1
    print("OK: spec checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
