#!/usr/bin/env python3
# tools/lib/check_drafts.py
#
# Character count rule: for each draft, only the text below the first line whose
# stripped content is exactly "## 叩き台" is counted, ending at the next same-level
# "## " heading or EOF. For that region, each line is stripped of
# leading/trailing whitespace, the lines are concatenated with no newline
# characters, the result is NFKC-normalized, and Python len() is used.

import argparse
import hashlib
import json
import pathlib
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


def build_section_index(
    spec: typing.Dict[str, Json],
    errors: typing.List[str],
    contexts: typing.Optional[typing.Dict[str, Json]] = None,
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


def check_draft_file(
    path: pathlib.Path,
    section_index: typing.Dict[SectionKey, typing.Dict[str, Json]],
    produced_sections: typing.Dict[SectionKey, pathlib.Path],
    counters: typing.Dict[str, int],
) -> typing.List[str]:
    errors: typing.List[str] = []
    text, read_errors = read_draft(path, errors)
    if read_errors:
        return read_errors

    counters["bracketed_need_check"] += text.count("[要確認]")
    counters["bare_need_check"] += text.count("要確認") - text.count("[要確認]")

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
        return errors

    previous_path = produced_sections.get(key)
    if previous_path is None:
        produced_sections[key] = path
    else:
        errors.append(f"duplicate draft for {deliverable_id}/{section_id}: {previous_path}, {path}")

    if body_errors:
        return errors

    max_chars = section.get("max_chars")
    if max_chars is None:
        return errors
    if not isinstance(max_chars, int):
        errors.append(f"{path}: spec max_chars must be an integer or null for {deliverable_id}/{section_id}")
        return errors

    count = count_body_chars(body)
    if count > max_chars:
        errors.append(f"{path}: char count {count} exceeds max_chars {max_chars} for {deliverable_id}/{section_id}")
    return errors


def check_drafts(
    spec_path: pathlib.Path,
    drafts_dir: pathlib.Path,
    profile_path: typing.Optional[pathlib.Path] = None,
    current_application_path: typing.Optional[pathlib.Path] = None,
) -> typing.Tuple[typing.List[str], typing.List[str], typing.Dict[str, int]]:
    errors: typing.List[str] = []
    warnings: typing.List[str] = []
    counters = {"bracketed_need_check": 0, "bare_need_check": 0}

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

    section_index, required_ai_sections = build_section_index(spec, errors, contexts)
    produced_sections: typing.Dict[SectionKey, pathlib.Path] = {}

    for draft_path in sorted(drafts_dir.glob("*.md")):
        errors.extend(check_draft_file(draft_path, section_index, produced_sections, counters))

    missing_sections = sorted(required_ai_sections.keys() - produced_sections.keys())
    for deliverable_id, section_id in missing_sections:
        key = (deliverable_id, section_id)
        section = section_index.get(key, {})
        marker = "[要確認] " if required_ai_sections[key] == predicate.UNKNOWN else ""
        name = section.get("name")
        if isinstance(name, str) and name:
            warnings.append(f"{marker}missing draft for {deliverable_id}/{section_id}: {name}")
        else:
            warnings.append(f"{marker}missing draft for {deliverable_id}/{section_id}")

    return errors, warnings, counters


def main(argv: typing.List[str]) -> int:
    parser = argparse.ArgumentParser(usage=(
        "bash tools/check-drafts.sh <spec.json> <drafts_dir> "
        "[--profile <path>] [--current-application <path>]"
    ))
    parser.add_argument("spec", type=pathlib.Path)
    parser.add_argument("drafts_dir", type=pathlib.Path)
    parser.add_argument("--profile", type=pathlib.Path)
    parser.add_argument("--current-application", type=pathlib.Path)
    try:
        args = parser.parse_args(argv[1:])
    except SystemExit as exc:
        return 0 if exc.code == 0 else 1

    errors, warnings, counters = check_drafts(args.spec, args.drafts_dir, args.profile, args.current_application)
    for warning in warnings:
        print(f"WARN: {warning}")
    print(f"INFO: [要確認] total: {counters['bracketed_need_check']}")
    if counters["bare_need_check"] > 0:
        print(f"INFO: bare 要確認 total: {counters['bare_need_check']}")
    for error in errors:
        print(f"FAIL: {error}")
    if errors:
        return 1
    print("OK: draft checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
