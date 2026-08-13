#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import typing


Json = typing.Any

VALID_BUILT_BY = {"provider", "applicant"}
VALID_NOTE_KINDS = {"review-lens", "scoring-strategy", "section-note", "examples"}
NOTE_KINDS_REQUIRING_CLAUSES = {"review-lens", "scoring-strategy", "section-note"}
PACK_KEYS = {"pack_version", "subsidy_id", "spec_version", "built_at", "built_by", "spec", "confirmation", "notes"}
LISTED_FILE_KEYS = {"path", "sha256"}
NOTE_ENTRY_KEYS = {"path", "kind", "sha256", "derived_from_spec_sha256"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
LOWER_ID_RE = re.compile(r"^[a-z0-9-]+$")
ISO8601_OFFSET_RE = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$"
)
CLAUSE_REF_RE = re.compile(r"\[clause:\s*([A-Za-z0-9_.-]+)\]")
FACT_LIKE_RE = re.compile(r"(万円|%|％|以内|締切|上限)")
FRONTMATTER_KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def display_path(path: pathlib.Path) -> str:
    root = pathlib.Path(__file__).resolve().parents[2]
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except (OSError, ValueError):
        return path.as_posix()


def load_json(path: pathlib.Path, errors: typing.List[str], label: str) -> Json:
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        errors.append(f"{label} not found: {display_path(path)}")
    except json.JSONDecodeError as exc:
        errors.append(f"{label} invalid JSON: {display_path(path)}: line {exc.lineno} column {exc.colno}")
    except OSError as exc:
        errors.append(f"{label} cannot be read: {display_path(path)}: {exc}")
    return None


def sha256_file(path: pathlib.Path, errors: typing.List[str], label: str) -> typing.Optional[str]:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        errors.append(f"{label} cannot be hashed: {display_path(path)}: {exc}")
    return None


def require_key(obj: Json, key: str, path: str, errors: typing.List[str]) -> bool:
    if not isinstance(obj, dict) or key not in obj:
        errors.append(f"missing required key: {path}.{key}")
        return False
    return True


def check_allowed_keys(obj: Json, allowed: typing.Set[str], path: str, errors: typing.List[str]) -> None:
    if not isinstance(obj, dict):
        return
    for key in sorted(set(obj) - allowed):
        errors.append(f"unexpected key: {path}.{key}")


def is_safe_relative_path(raw_path: Json, label: str, errors: typing.List[str]) -> typing.Optional[pathlib.PurePosixPath]:
    if not isinstance(raw_path, str) or not raw_path:
        errors.append(f"{label}.path must be a non-empty string")
        return None
    if "\\" in raw_path:
        errors.append(f"{label}.path must use forward slashes: {raw_path}")
        return None
    pure = pathlib.PurePosixPath(raw_path)
    if pure.is_absolute() or any(part in ("", ".", "..") for part in pure.parts):
        errors.append(f"{label}.path must be relative to the pack dir: {raw_path}")
        return None
    return pure


def resolve_pack_path(pack_dir: pathlib.Path, pure: pathlib.PurePosixPath) -> pathlib.Path:
    return pack_dir.joinpath(*pure.parts)


def validate_sha(value: Json, label: str, errors: typing.List[str]) -> typing.Optional[str]:
    if not isinstance(value, str) or not SHA256_RE.match(value):
        errors.append(f"{label} must be a sha256 hex string")
        return None
    return value


def read_listed_file(
    pack_dir: pathlib.Path,
    entry: Json,
    label: str,
    errors: typing.List[str],
    allowed_keys: typing.Optional[typing.Set[str]] = None,
) -> typing.Optional[typing.Tuple[pathlib.Path, str]]:
    if not isinstance(entry, dict):
        errors.append(f"{label} must be an object")
        return None
    check_allowed_keys(entry, allowed_keys or LISTED_FILE_KEYS, label, errors)
    pure = is_safe_relative_path(entry.get("path"), label, errors)
    expected_sha = validate_sha(entry.get("sha256"), f"{label}.sha256", errors)
    if pure is None or expected_sha is None:
        return None
    path = resolve_pack_path(pack_dir, pure)
    if not path.is_file():
        errors.append(f"pack listed file not found: {label}.path={pure.as_posix()}")
        return None
    actual_sha = sha256_file(path, errors, label)
    if actual_sha is not None and actual_sha != expected_sha:
        errors.append(f"sha256 mismatch: {label}.path={pure.as_posix()}")
    return path, expected_sha


def check_pack_json_structure(pack: Json, errors: typing.List[str]) -> None:
    if not isinstance(pack, dict):
        errors.append("pack root must be an object")
        return
    check_allowed_keys(pack, PACK_KEYS, "$", errors)
    for key in ("pack_version", "subsidy_id", "spec_version", "built_at", "built_by", "spec", "confirmation", "notes"):
        require_key(pack, key, "$", errors)

    if pack.get("pack_version") != 1:
        errors.append("pack_version must be 1")
    if not isinstance(pack.get("subsidy_id"), str) or not LOWER_ID_RE.match(str(pack.get("subsidy_id", ""))):
        errors.append("subsidy_id must match ^[a-z0-9-]+$")
    if not isinstance(pack.get("spec_version"), int) or pack.get("spec_version") < 1:
        errors.append("spec_version must be an integer >= 1")
    if not isinstance(pack.get("built_at"), str) or not ISO8601_OFFSET_RE.match(str(pack.get("built_at", ""))):
        errors.append("built_at must be offset ISO8601 like 2026-07-05T00:00:00+09:00")
    if pack.get("built_by") not in VALID_BUILT_BY:
        errors.append("built_by must be provider or applicant")
    if "notes" in pack and not isinstance(pack.get("notes"), list):
        errors.append("notes must be an array")


def collect_clause_and_section_ids(spec: Json) -> typing.Tuple[typing.Set[str], typing.Set[typing.Tuple[str, str]]]:
    clause_ids: typing.Set[str] = set()
    section_ids: typing.Set[typing.Tuple[str, str]] = set()
    if isinstance(spec, dict):
        for clause in spec.get("clauses", []):
            if isinstance(clause, dict) and isinstance(clause.get("clause_id"), str):
                clause_ids.add(clause["clause_id"])
        for deliverable in spec.get("deliverables", []):
            if not isinstance(deliverable, dict) or not isinstance(deliverable.get("deliverable_id"), str):
                continue
            deliverable_id = deliverable["deliverable_id"]
            sections = deliverable.get("sections", [])
            if not isinstance(sections, list):
                continue
            for section in sections:
                if isinstance(section, dict) and isinstance(section.get("section_id"), str):
                    section_ids.add((deliverable_id, section["section_id"]))
    return clause_ids, section_ids


def parse_limited_frontmatter(path: pathlib.Path) -> typing.Tuple[typing.Dict[str, str], typing.List[str], int, typing.List[str]]:
    errors: typing.List[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        return {}, [], 0, [f"note cannot be read: {display_path(path)}: {exc}"]

    if not lines or lines[0].strip() != "---":
        return {}, lines, 1, [f"note frontmatter missing: {display_path(path)}"]

    closing_index = None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            closing_index = index
            break
    if closing_index is None:
        return {}, lines, 1, [f"note frontmatter closing delimiter missing: {display_path(path)}"]

    values: typing.Dict[str, str] = {}
    for line_number, line in enumerate(lines[1:closing_index], start=2):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            continue
        if ":" not in stripped:
            errors.append(f"note frontmatter invalid line: {display_path(path)}:{line_number}")
            continue
        key, raw_value = stripped.split(":", 1)
        key = key.strip()
        value = raw_value.strip()
        if not FRONTMATTER_KEY_RE.match(key):
            errors.append(f"note frontmatter invalid key: {display_path(path)}:{line_number}")
            continue
        if key in values:
            errors.append(f"note frontmatter duplicate key: {display_path(path)}:{line_number} {key}")
            continue
        if value.startswith(("-", "{", "[")):
            errors.append(f"note frontmatter value must be scalar: {display_path(path)}:{line_number}")
            continue
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1].strip()
        values[key] = value

    return values, lines[closing_index + 1 :], closing_index + 2, errors


def check_examples_source_blocks(
    note_path: pathlib.Path,
    body_lines: typing.List[str],
    body_start_line: int,
    errors: typing.List[str],
) -> None:
    blocks: typing.List[typing.Tuple[int, str, typing.List[str]]] = []
    current_heading: typing.Optional[typing.Tuple[int, str]] = None
    current_lines: typing.List[str] = []

    for offset, line in enumerate(body_lines):
        if re.match(r"^##\s+\S", line):
            if current_heading is not None:
                blocks.append((current_heading[0], current_heading[1], current_lines))
            current_heading = (body_start_line + offset, line.strip())
            current_lines = []
        elif current_heading is not None:
            current_lines.append(line)

    if current_heading is not None:
        blocks.append((current_heading[0], current_heading[1], current_lines))

    if not blocks:
        errors.append(f"examples note missing source: {display_path(note_path)} has no ## example blocks")
        return

    for line_number, heading, block_lines in blocks:
        if not any(re.match(r"^\s*source:\s*\S", line) for line in block_lines):
            errors.append(f"examples note missing source: {display_path(note_path)}:{line_number} {heading}")


def check_note(
    pack: typing.Dict[str, Json],
    pack_dir: pathlib.Path,
    note_entry: Json,
    index: int,
    spec_sha256: typing.Optional[str],
    clause_ids: typing.Set[str],
    section_ids: typing.Set[typing.Tuple[str, str]],
    errors: typing.List[str],
    warnings: typing.List[str],
) -> None:
    label = f"notes[{index}]"
    if not isinstance(note_entry, dict):
        errors.append(f"{label} must be an object")
        return

    kind = note_entry.get("kind")
    if kind not in VALID_NOTE_KINDS:
        errors.append(f"{label}.kind must be one of {', '.join(sorted(VALID_NOTE_KINDS))}")
    derived_sha = validate_sha(note_entry.get("derived_from_spec_sha256"), f"{label}.derived_from_spec_sha256", errors)
    if spec_sha256 is not None and derived_sha is not None and derived_sha != spec_sha256:
        errors.append(f"derived_from_spec_sha256 mismatch: {label}")

    listed = read_listed_file(pack_dir, note_entry, label, errors, NOTE_ENTRY_KEYS)
    if listed is None:
        return
    note_path, _expected_sha = listed
    if note_path.suffix != ".md":
        errors.append(f"{label}.path must point to a .md note")

    frontmatter, body_lines, body_start_line, frontmatter_errors = parse_limited_frontmatter(note_path)
    errors.extend(frontmatter_errors)

    subsidy_id = frontmatter.get("subsidy_id")
    if subsidy_id != pack.get("subsidy_id"):
        errors.append(f"note subsidy_id mismatch: {display_path(note_path)}")

    frontmatter_kind = frontmatter.get("kind")
    if frontmatter_kind not in VALID_NOTE_KINDS:
        errors.append(f"note kind invalid: {display_path(note_path)}")
    elif kind in VALID_NOTE_KINDS and frontmatter_kind != kind:
        errors.append(f"note kind mismatch: {display_path(note_path)}")

    if kind == "section-note":
        deliverable_id = frontmatter.get("deliverable_id")
        section_id = frontmatter.get("section_id")
        if not deliverable_id or not section_id:
            errors.append(f"section-note frontmatter missing deliverable_id or section_id: {display_path(note_path)}")
        elif (deliverable_id, section_id) not in section_ids:
            errors.append(f"unknown section-note target: {display_path(note_path)} {deliverable_id}/{section_id}")

    body = "\n".join(body_lines)
    refs = CLAUSE_REF_RE.findall(body)
    for clause_id in refs:
        if clause_id not in clause_ids:
            errors.append(f"unknown clause reference: {display_path(note_path)} [clause: {clause_id}]")
    if kind in NOTE_KINDS_REQUIRING_CLAUSES and not refs:
        errors.append(f"note has no clause references: {display_path(note_path)}")

    if kind == "examples":
        check_examples_source_blocks(note_path, body_lines, body_start_line, errors)

    for offset, line in enumerate(body_lines):
        if FACT_LIKE_RE.search(line) and "[clause:" not in line and "[要確認]" not in line:
            warnings.append(
                f"{display_path(note_path)}:{body_start_line + offset}: fact-like line lacks [clause:] or [要確認]"
            )


def check_pack_dir_extensions(pack_dir: pathlib.Path, errors: typing.List[str]) -> None:
    if not pack_dir.is_dir():
        errors.append(f"pack path is not a directory: {display_path(pack_dir)}")
        return
    for path in pack_dir.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix not in {".md", ".json"}:
            errors.append(f"unsupported file in pack dir: {display_path(path)}")


def check_pack_file_inventory(
    pack_dir: pathlib.Path,
    pack_json_path: pathlib.Path,
    pack: typing.Dict[str, Json],
    errors: typing.List[str],
) -> None:
    if not pack_dir.is_dir():
        return

    actual_paths: typing.Set[pathlib.PurePosixPath] = set()
    for path in pack_dir.rglob("*"):
        if path.is_file() and path.suffix in {".md", ".json"}:
            actual_paths.add(pathlib.PurePosixPath(path.relative_to(pack_dir).as_posix()))

    listed_paths: typing.Set[pathlib.PurePosixPath] = set()

    def add_listed_path(pure: pathlib.PurePosixPath, label: str) -> None:
        if pure in listed_paths:
            errors.append(f"duplicate listed pack path: {pure.as_posix()} ({label})")
            return
        listed_paths.add(pure)

    add_listed_path(pathlib.PurePosixPath(pack_json_path.name), "pack.json")

    for key in ("spec", "confirmation"):
        entry = pack.get(key)
        if isinstance(entry, dict):
            pure = is_safe_relative_path(entry.get("path"), key, errors)
            if pure is not None:
                add_listed_path(pure, key)

    notes = pack.get("notes")
    if isinstance(notes, list):
        for index, note_entry in enumerate(notes):
            if not isinstance(note_entry, dict):
                continue
            label = f"notes[{index}]"
            pure = is_safe_relative_path(note_entry.get("path"), label, errors)
            if pure is not None:
                add_listed_path(pure, label)

    for pure in sorted(actual_paths - listed_paths, key=lambda value: value.as_posix()):
        errors.append(f"unlisted pack file: {pure.as_posix()}")


def run_check_spec(spec_path: pathlib.Path, errors: typing.List[str]) -> None:
    root = pathlib.Path(__file__).resolve().parents[2]
    command = ["bash", str(root / "tools" / "check-spec.sh"), str(spec_path)]
    result = subprocess.run(command, cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        errors.append(f"check-spec failed: {display_path(spec_path)}")


def check_pack(pack_input: pathlib.Path) -> typing.Tuple[typing.List[str], typing.List[str]]:
    errors: typing.List[str] = []
    warnings: typing.List[str] = []

    if pack_input.is_dir():
        pack_dir = pack_input
        pack_json_path = pack_dir / "pack.json"
    else:
        pack_json_path = pack_input
        pack_dir = pack_json_path.parent

    check_pack_dir_extensions(pack_dir, errors)
    pack = load_json(pack_json_path, errors, "pack.json")
    if not isinstance(pack, dict):
        return errors, warnings

    check_pack_json_structure(pack, errors)
    check_pack_file_inventory(pack_dir, pack_json_path, pack, errors)

    spec_sha256: typing.Optional[str] = None
    spec: Json = None
    spec_file = read_listed_file(pack_dir, pack.get("spec"), "spec", errors)
    if spec_file is not None:
        spec_path, spec_sha256 = spec_file
        spec = load_json(spec_path, errors, "spec")
        if isinstance(spec, dict):
            if spec.get("status") != "confirmed":
                errors.append("spec status must be confirmed")
            if spec.get("subsidy_id") != pack.get("subsidy_id"):
                errors.append("pack subsidy_id does not match spec.subsidy_id")
            if spec.get("spec_version") != pack.get("spec_version"):
                errors.append("pack spec_version does not match spec.spec_version")
        run_check_spec(spec_path, errors)

    confirmation_file = read_listed_file(pack_dir, pack.get("confirmation"), "confirmation", errors)
    if confirmation_file is not None:
        confirmation_path, _confirmation_sha = confirmation_file
        confirmation = load_json(confirmation_path, errors, "confirmation")
        if isinstance(confirmation, dict) and spec_sha256 is not None:
            if confirmation.get("spec_sha256") != spec_sha256:
                errors.append("confirmation spec_sha256 does not match pack spec.sha256")

    clause_ids, section_ids = collect_clause_and_section_ids(spec)
    notes = pack.get("notes", [])
    if isinstance(notes, list):
        for index, note_entry in enumerate(notes):
            check_note(pack, pack_dir, note_entry, index, spec_sha256, clause_ids, section_ids, errors, warnings)

    return errors, warnings


def main(argv: typing.List[str]) -> int:
    parser = argparse.ArgumentParser(usage="bash tools/check-pack.sh <pack_dir|pack.json>")
    parser.add_argument("pack_path")
    args = parser.parse_args(argv[1:])

    errors, warnings = check_pack(pathlib.Path(args.pack_path))
    for warning in warnings:
        print(f"WARN: {warning}")
    for error in errors:
        print(f"FAIL: {error}")
    if errors:
        return 1
    print("OK: pack checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
