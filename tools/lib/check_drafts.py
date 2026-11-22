#!/usr/bin/env python3
# tools/lib/check_drafts.py
#
# Character count rule: for each draft, only the text below the first line whose
# stripped content is exactly "## 叩き台" is counted, ending at the next same-level
# "## " heading or EOF. For that region, each line is stripped of
# leading/trailing whitespace, the lines are concatenated with no newline
# characters, the result is NFKC-normalized, and Python len() is used.

import argparse
import datetime
import hashlib
import json
import pathlib
import re
import sys
import typing
import unicodedata

if sys.version_info < (3, 7):
    sys.stderr.write(
        "FAIL: Python 3.7+ required (running %s)\n" % sys.version.split()[0]
    )
    raise SystemExit(1)

import predicate


Json = typing.Any
SectionKey = typing.Tuple[str, str]
CoverageInputs = typing.Dict[typing.Tuple[str, str], Json]


def load_json(path: pathlib.Path, errors: typing.List[str], label: str) -> Json:
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        errors.append(f"{label} not found: {path}")
    except json.JSONDecodeError as exc:
        errors.append(f"{label} invalid JSON: {path}: line {exc.lineno} column {exc.colno}")
    except UnicodeDecodeError:
        errors.append(f"{label} invalid JSON: {path}: expected UTF-8")
    except OSError as exc:
        errors.append(f"{label} cannot be read: {path}: {exc}")
    return None


def clean_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1].strip()
    return value


def parse_frontmatter(path: pathlib.Path, text: str) -> typing.Tuple[typing.Dict[str, str], int, typing.List[str]]:
    errors: typing.List[str] = []
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, 0, [f"{path}: missing YAML frontmatter opening delimiter"]

    closing_index = None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            closing_index = index
            break

    if closing_index is None:
        return {}, 0, [f"{path}: missing YAML frontmatter closing delimiter"]

    values: typing.Dict[str, str] = {}
    for line_number, line in enumerate(lines[1:closing_index], start=2):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if ":" not in stripped:
            continue
        key, raw_value = stripped.split(":", 1)
        key = key.strip()
        if key in ("deliverable_id", "section_id"):
            values[key] = clean_scalar(raw_value)

    for required_key in ("deliverable_id", "section_id"):
        if not values.get(required_key):
            errors.append(f"{path}: frontmatter missing {required_key}")

    return values, closing_index + 1, errors


def find_draft_body(path: pathlib.Path, lines: typing.List[str], start_index: int) -> typing.Tuple[str, typing.List[str]]:
    for index in range(start_index, len(lines)):
        if lines[index].strip() == "## 叩き台":
            end_index = len(lines)
            for next_index in range(index + 1, len(lines)):
                if lines[next_index].strip().startswith("## "):
                    end_index = next_index
                    break
            return "\n".join(lines[index + 1 : end_index]), []
    return "", [f"{path}: missing ## 叩き台 heading"]


def normalize_body_text(body: str) -> str:
    stripped_joined = "".join(line.strip() for line in body.splitlines())
    return unicodedata.normalize("NFKC", stripped_joined)


def count_body_chars(body: str) -> int:
    return len(normalize_body_text(body))


def draft_bodies_sha256(drafts_dir: pathlib.Path) -> typing.Tuple[str, typing.List[str]]:
    errors: typing.List[str] = []
    if not drafts_dir.exists():
        return "", [f"drafts_dir not found: {drafts_dir}"]
    if not drafts_dir.is_dir():
        return "", [f"drafts_dir is not a directory: {drafts_dir}"]

    parts: typing.List[str] = []
    for draft_path in sorted(drafts_dir.glob("*.md")):
        text, read_errors = read_draft(draft_path, errors)
        if read_errors:
            errors.extend(read_errors)
            continue
        frontmatter, body_start, frontmatter_errors = parse_frontmatter(draft_path, text)
        del frontmatter
        if frontmatter_errors:
            errors.extend(frontmatter_errors)
            continue
        body, body_errors = find_draft_body(draft_path, text.splitlines(), body_start)
        if body_errors:
            errors.extend(body_errors)
            continue
        parts.append(normalize_body_text(body))

    joined = "\n---\n".join(parts)
    digest = hashlib.sha256(joined.encode("utf-8")).hexdigest()
    return digest, errors


def record_required_if_inputs(node: Json, contexts: typing.Dict[str, Json], inputs: CoverageInputs) -> None:
    if not isinstance(node, dict):
        return
    scope, key = node.get("scope"), node.get("key")
    if isinstance(scope, str) and scope in predicate.VALID_SCOPES and isinstance(key, str) and key:
        value = predicate.get_path(contexts.get(scope), key)
        inputs[(scope, key)] = {"present": value is not predicate.MISSING}
        if value is not predicate.MISSING:
            inputs[(scope, key)]["value"] = value
    # Include every branch, even when predicate evaluation short-circuits.
    for operator in ("all", "any"):
        children = node.get(operator)
        if isinstance(children, list):
            for child in children:
                record_required_if_inputs(child, contexts, inputs)
    record_required_if_inputs(node.get("not"), contexts, inputs)


def build_section_index(
    spec: typing.Dict[str, Json],
    errors: typing.List[str],
    contexts: typing.Optional[typing.Dict[str, Json]] = None,
    coverage_inputs: typing.Optional[CoverageInputs] = None,
) -> typing.Tuple[typing.Dict[SectionKey, typing.Dict[str, Json]], typing.Dict[SectionKey, str]]:
    section_index: typing.Dict[SectionKey, typing.Dict[str, Json]] = {}
    required_ai_sections: typing.Dict[SectionKey, str] = {}
    if contexts is None:
        contexts = predicate.build_contexts({}, None)

    deliverables = spec.get("deliverables")
    if not isinstance(deliverables, list):
        errors.append("spec.deliverables must be an array")
        return section_index, required_ai_sections

    for deliverable_index, deliverable in enumerate(deliverables):
        if not isinstance(deliverable, dict):
            errors.append(f"spec.deliverables[{deliverable_index}] must be an object")
            continue

        deliverable_id = deliverable.get("deliverable_id")
        if not isinstance(deliverable_id, str) or not deliverable_id:
            errors.append(f"spec.deliverables[{deliverable_index}].deliverable_id must be a string")
            continue

        sections = deliverable.get("sections", [])
        if sections is None:
            sections = []
        if not isinstance(sections, list):
            errors.append(f"spec.deliverables[{deliverable_index}].sections must be an array")
            continue

        coverage_keys: typing.List[SectionKey] = []
        for section_index_number, section in enumerate(sections):
            if not isinstance(section, dict):
                errors.append(
                    f"spec.deliverables[{deliverable_index}].sections[{section_index_number}] must be an object"
                )
                continue
            section_id = section.get("section_id")
            if not isinstance(section_id, str) or not section_id:
                errors.append(
                    f"spec.deliverables[{deliverable_index}].sections[{section_index_number}].section_id must be a string"
                )
                continue
            key = (deliverable_id, section_id)
            if key in section_index:
                errors.append(f"duplicate section_id: {deliverable_id}/{section_id}")
                continue
            section_index[key] = section
            if (
                deliverable.get("produced_by") == "ai_draftable"
                and section.get("optional") is not True
            ):
                coverage_keys.append(key)

        # Only coverage candidates require application context for required_if.
        if not coverage_keys:
            continue
        required_if = deliverable.get("required_if")
        required_state = predicate.TRUE if deliverable.get("required") is True else predicate.FALSE
        if required_if is not None:
            if coverage_inputs is not None:
                record_required_if_inputs(required_if, contexts, coverage_inputs)
            if predicate.predicate_uses_application_scope(required_if) and contexts.get("application") is None:
                errors.append(f"application scope requires --current-application <path> for {deliverable_id}")
                continue
            required_state = predicate.eval_predicate(required_if, contexts)
        if required_state != predicate.FALSE:
            for key in coverage_keys:
                required_ai_sections[key] = required_state

    return section_index, required_ai_sections


def read_draft(path: pathlib.Path, errors: typing.List[str]) -> typing.Tuple[str, typing.List[str]]:
    try:
        return path.read_text(encoding="utf-8"), []
    except OSError as exc:
        return "", [f"{path}: cannot be read: {exc}"]


def unused_review_message(path, stale=False):
    reason = "本文を直す前の記録" if stale else "現在の本文・引用の検査に不合格"
    return f"INFO: 古いレビュー記録は使いません（{reason}）: {path}"


def check_draft_file(
    path: pathlib.Path,
    section_index: typing.Dict[SectionKey, typing.Dict[str, Json]],
    produced_sections: typing.Dict[SectionKey, pathlib.Path],
    counters: typing.Dict[str, Json],
    draftable_deliverables: typing.Dict[str, bool],
) -> typing.List[str]:
    errors: typing.List[str] = []
    text, read_errors = read_draft(path, errors)
    if read_errors:
        return read_errors

    counters["bracketed_need_check"] += text.count("[要確認]")
    counters["bare_need_check"] += text.count("要確認") - text.count("[要確認]")

    for number, line in enumerate(text.splitlines(), 1):
        if line.count("要確認") > line.count("[要確認]"):
            counters.setdefault("bare_locations", []).append(f"{path}:{number}")

    frontmatter, body_start, frontmatter_errors = parse_frontmatter(path, text)
    errors.extend(frontmatter_errors)

    lines = text.splitlines()
    body, body_errors = find_draft_body(path, lines, body_start)
    errors.extend(body_errors)

    deliverable_id = frontmatter.get("deliverable_id")
    section_id = frontmatter.get("section_id")
    if not deliverable_id or not section_id:
        return errors

    key = (deliverable_id, section_id)
    section = section_index.get(key)
    if section is None:
        errors.append(f"{path}: unknown deliverable_id/section_id: {deliverable_id}/{section_id}")
        if deliverable_id in draftable_deliverables:
            hint = f"{deliverable_id} の有効な section_id: " + ", ".join(
                key[1] for key in section_index if key[0] == deliverable_id
            )
        else:
            hint = "有効な deliverable_id: " + ", ".join(
                key for key, draftable in draftable_deliverables.items() if draftable
            )
        counters["error_hints"][errors[-1]] = hint
        return errors

    previous_path = produced_sections.get(key)
    if previous_path is None:
        produced_sections[key] = path
    else:
        errors.append(f"duplicate draft for {deliverable_id}/{section_id}: {previous_path}, {path}")

    if body_errors:
        return errors

    body_need_check = body.count("[要確認]")
    counters["body_need_check"] += body_need_check
    counters["info"].append(
        f"[要確認] in draft body: {deliverable_id}/{section_id} {body_need_check}"
    )

    max_chars = section.get("max_chars")
    if max_chars is None:
        counters["info"].append(
            f"max_chars not set in spec: {deliverable_id}/{section_id} ({count_body_chars(body)} chars)"
        )
        return errors
    if not isinstance(max_chars, int):
        errors.append(f"{path}: spec max_chars must be an integer or null for {deliverable_id}/{section_id}")
        return errors

    count = count_body_chars(body)
    counters["info"].append(f"chars: {deliverable_id}/{section_id} {count}/{max_chars}")
    if count > max_chars:
        errors.append(f"{path}: char count {count} exceeds max_chars {max_chars} for {deliverable_id}/{section_id}")
    return errors


def check_review_record(
    path: pathlib.Path,
    drafts_dir: pathlib.Path,
    produced_sections: typing.Dict[SectionKey, pathlib.Path],
) -> typing.List[str]:
    try:
        text = path.read_text(encoding="utf-8")
        match = re.match(r"\A```json\n(.*?)\n```(?:\n|$)", text, re.S)
        if match is None:
            raise ValueError("leading fenced json required")
        record = json.loads(match.group(1))
        if not isinstance(record, dict):
            raise ValueError("record must be an object")
        digest = record["reviewed_draft_bodies_sha256"]
        sections = record["reviewed_sections"]
        reviewed_at = record["reviewed_at"]
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", digest):
            raise ValueError("reviewed_draft_bodies_sha256 must be 64 hex digits")
        if not isinstance(sections, list) or any(
            not isinstance(section, str) or not re.fullmatch(r"[^/\s]+/[^/\s]+", section)
            for section in sections
        ):
            raise ValueError("reviewed_sections must be an array of deliverable_id/section_id strings")
        if not isinstance(reviewed_at, str) or not re.match(r"^\d{4}-\d{2}-\d{2}T", reviewed_at):
            raise ValueError("reviewed_at must be an ISO 8601 datetime")
        datetime.datetime.fromisoformat(reviewed_at.replace("Z", "+00:00"))
    except (OSError, UnicodeError, ValueError, KeyError) as exc:
        return [f"review record unreadable: {path}: {exc}"]

    current_digest, errors = draft_bodies_sha256(drafts_dir)
    if digest.lower() != current_digest:
        errors.append(f"review record hash mismatch: {path}: draft bodies changed after review")
    missing = sorted("/".join(key) for key in produced_sections if "/".join(key) not in sections)
    if missing:
        errors.append(f"review record missing sections: {path}: {', '.join(missing)}")
    return errors


def check_drafts(
    spec_path: pathlib.Path,
    drafts_dir: pathlib.Path,
    profile_path: typing.Optional[pathlib.Path] = None,
    current_application_path: typing.Optional[pathlib.Path] = None,
    require_coverage: bool = False,
    waive: typing.Sequence[str] = (),
    review_record: typing.Optional[pathlib.Path] = None,
) -> typing.Tuple[typing.List[str], typing.List[str], typing.Dict[str, Json]]:
    errors: typing.List[str] = []
    warnings: typing.List[str] = []
    counters = {"bracketed_need_check": 0, "bare_need_check": 0, "body_need_check": 0}

    spec = load_json(spec_path, errors, "spec")
    if not isinstance(spec, dict):
        if not errors:
            errors.append(f"spec root must be an object: {spec_path}")
        return errors, warnings, counters

    profile_doc = {}
    if profile_path is not None:
        profile_doc = load_json(profile_path, errors, "profile")
        if not isinstance(profile_doc, dict):
            if not errors:
                errors.append(f"profile root must be an object: {profile_path}")
            return errors, warnings, counters
    try:
        contexts = predicate.build_contexts(profile_doc, None)
        if current_application_path is not None:
            application_doc = predicate.load_current_application(current_application_path)
            for key in ("subsidy_id", "spec_version"):
                if key not in application_doc:
                    raise predicate.PredicateInputError(f"current application missing {key}")
            predicate.validate_application_binding(spec, application_doc)
            contexts["application"] = application_doc
    except predicate.PredicateInputError as exc:
        errors.append(str(exc))
        return errors, warnings, counters

    if not drafts_dir.exists():
        errors.append(f"drafts_dir not found: {drafts_dir}")
        return errors, warnings, counters
    if not drafts_dir.is_dir():
        errors.append(f"drafts_dir is not a directory: {drafts_dir}")
        return errors, warnings, counters

    coverage_inputs: CoverageInputs = {}
    section_index, required_ai_sections = build_section_index(spec, errors, contexts, coverage_inputs)
    draftable_deliverables = {
        item["deliverable_id"]: item.get("produced_by") == "ai_draftable"
        and any(key[0] == item["deliverable_id"] for key in section_index)
        for item in spec.get("deliverables", []) if isinstance(item, dict)
        and isinstance(item.get("deliverable_id"), str)
    } if isinstance(spec.get("deliverables"), list) else {}
    counters["error_hints"] = {}
    counters["info"] = []
    produced_sections: typing.Dict[SectionKey, pathlib.Path] = {}

    draft_paths = sorted(drafts_dir.glob("*.md"))
    if require_coverage and not draft_paths:
        errors.append("no drafts: このキットで作った draft が 1 件もないため、提出前チェックの対象外です")
    for draft_path in draft_paths:
        errors.extend(check_draft_file(draft_path, section_index, produced_sections, counters, draftable_deliverables))

    waived_sections: typing.Set[SectionKey] = set()
    if waive and not require_coverage:
        errors.append("--waive requires --require-coverage")
    for value in waive:
        parts = value.split("/")
        if len(parts) != 2 or any(not part or part.strip() != part for part in parts):
            errors.append(f"invalid format for --waive: {value}; expected <deliverable_id>/<section_id>")
            continue
        key = (parts[0], parts[1])
        if key not in section_index:
            errors.append(f"unknown section for --waive: {value}")
            counters["error_hints"][errors[-1]] = "有効な <deliverable_id>/<section_id>: " + ", ".join(
                "/".join(key) for key in section_index
            )
        elif key in produced_sections:
            errors.append(f"draft exists for --waive: {value}; draft を消すか --waive を外してください")
        elif require_coverage:
            waived_sections.add(key)
    counters["waived_sections"] = ["/".join(key) for key in sorted(waived_sections)]

    missing_sections = sorted(required_ai_sections.keys() - produced_sections.keys())
    for deliverable_id, section_id in missing_sections:
        key = (deliverable_id, section_id)
        if key in waived_sections and required_ai_sections[key] == predicate.TRUE:
            continue
        if require_coverage and required_ai_sections[key] == predicate.TRUE:
            errors.append(f"missing required draft for {deliverable_id}/{section_id}")
            continue
        section = section_index.get(key, {})
        marker = "[要確認] " if required_ai_sections[key] == predicate.UNKNOWN else ""
        name = section.get("name")
        if isinstance(name, str) and name:
            warnings.append(f"{marker}missing draft for {deliverable_id}/{section_id}: {name}")
        else:
            warnings.append(f"{marker}missing draft for {deliverable_id}/{section_id}")

    if review_record is not None:
        review_errors = check_review_record(review_record, drafts_dir, produced_sections)
        errors.extend(review_errors)
        if not review_errors:
            counters["reviewed_section_count"] = len(produced_sections)

    return errors, warnings, dict(counters, coverage_inputs_sha256=coverage_inputs_sha256(coverage_inputs))


def coverage_inputs_sha256(coverage_inputs: CoverageInputs) -> str:
    snapshot = [[scope, key, value] for (scope, key), value in sorted(coverage_inputs.items())]
    return hashlib.sha256(json.dumps(
        snapshot, sort_keys=True, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")).hexdigest()



def main(argv: typing.List[str]) -> int:
    parser = argparse.ArgumentParser(usage=(
        "bash tools/check-drafts.sh <spec.json> <drafts_dir> "
        "[--profile <path>] [--current-application <path>] "
        "[--require-coverage] [--waive <deliverable_id>/<section_id>] [--review-record <review.md>]"
    ))
    parser.add_argument("spec", type=pathlib.Path)
    parser.add_argument("drafts_dir", type=pathlib.Path)
    parser.add_argument("--review-record", type=pathlib.Path)
    parser.add_argument("--profile", type=pathlib.Path)
    parser.add_argument("--current-application", type=pathlib.Path)
    parser.add_argument("--require-coverage", action="store_true")
    parser.add_argument("--waive", action="append", default=[])
    try:
        args = parser.parse_args(argv[1:])
    except SystemExit as exc:
        return 0 if exc.code == 0 else 1

    errors, warnings, counters = check_drafts(
        args.spec, args.drafts_dir, args.profile, args.current_application,
        args.require_coverage, args.waive, args.review_record,
    )
    for section in counters.get("waived_sections", []):
        print(f"INFO: waived by applicant: {section}")
    for warning in warnings:
        print(f"WARN: {warning}")
    print(f"INFO: [要確認] total: {counters['bracketed_need_check']}")
    print(f"INFO: [要確認] in draft bodies: {counters['body_need_check']}")
    if counters["bare_need_check"] > 0:
        print(f"INFO: bare 要確認 total: {counters['bare_need_check']}")
        for location in counters.get("bare_locations", []):
            print(f"INFO: bare 要確認: {location}")
    for info in dict.fromkeys(counters.get("info", [])):
        print(f"INFO: {info}")
    emitted_hints = set()
    for error in errors:
        print(f"FAIL: {error}")
        hint = counters.get("error_hints", {}).get(error)
        if hint is not None and hint not in emitted_hints:
            print(f"INFO: {hint}")
            emitted_hints.add(hint)
    if errors:
        return 1
    print(f"INFO: coverage_inputs_sha256: {counters['coverage_inputs_sha256']}")
    if args.review_record is not None:
        print(f"INFO: review record ok: {args.review_record} ({counters['reviewed_section_count']} sections)")
    print("OK: draft checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
