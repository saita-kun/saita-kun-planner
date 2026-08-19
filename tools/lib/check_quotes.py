#!/usr/bin/env python3
"""Verify that clause quotations in a /review output exist in the spec clauses.

Usage: bash tools/check-quotes.sh <spec.json> <review.md>

The checker reads the clause-verifier table of a /review output (any Markdown
table whose header row has both a clause_id column and a quoted_text column),
then compares every quoted_text against clauses[].text of the given spec.

Verdicts:
  - pass : quoted_text is a substring of clauses[].text after NFKC normalization
  - WARN : it matches only after whitespace is also removed (same verbatim rule
           check_spec.py applies to extracts), which is a formatting difference
  - FAIL : the clause_id does not exist, a cell is missing, or the quotation is
           not found at all (the review must classify it as a fabrication risk)
"""
from __future__ import annotations

import sys

if sys.version_info < (3, 7):
    sys.stderr.write(
        "FAIL: Python 3.7+ required (running %s)\n" % sys.version.split()[0]
    )
    raise SystemExit(1)

import argparse
import json
import pathlib
import re
import typing
import unicodedata

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from check_spec import normalize_verbatim_text  # noqa: E402

CELL_SPLIT_RE = re.compile(r"(?<!\\)\|")
SEPARATOR_CELL_RE = re.compile(r"^:?-{3,}:?$")
CLAUSE_ID_HEADERS = ("clause_id", "clauseid")
QUOTED_TEXT_HEADERS = ("quoted_text", "quotedtext")
PLACEHOLDER_CELLS = {"", "-", "--", "---", "—", "–", "n/a", "na", "なし", "該当なし", "無し"}
EXCERPT_LIMIT = 40


class QuoteRow(typing.NamedTuple):
    line_number: int
    clause_id: str
    quoted_text: str


def normalize_nfkc(text: str) -> str:
    return unicodedata.normalize("NFKC", text)


def excerpt(text: str) -> str:
    single_line = " ".join(text.split())
    if len(single_line) <= EXCERPT_LIMIT:
        return single_line
    return single_line[:EXCERPT_LIMIT] + "…"


def split_row(line: str) -> typing.List[str]:
    stripped = line.strip()
    if stripped.startswith("|"):
        stripped = stripped[1:]
    if stripped.endswith("|") and not stripped.endswith("\\|"):
        stripped = stripped[:-1]
    return [cell.replace("\\|", "|").strip() for cell in CELL_SPLIT_RE.split(stripped)]


def clean_cell(cell: str) -> str:
    value = cell.strip()
    if len(value) >= 2 and value.startswith("`") and value.endswith("`"):
        value = value.strip("`").strip()
    return value


def is_placeholder(value: str) -> bool:
    return value.strip().lower() in PLACEHOLDER_CELLS


def header_index(cells: typing.List[str], keys: typing.Tuple[str, ...]) -> typing.Optional[int]:
    for index, cell in enumerate(cells):
        flattened = normalize_nfkc(cell).replace("`", "").replace(" ", "").lower()
        if any(key in flattened for key in keys):
            return index
    return None


def is_separator_row(cells: typing.List[str]) -> bool:
    return bool(cells) and all(SEPARATOR_CELL_RE.match(cell.strip()) for cell in cells)


def collect_quote_rows(text: str) -> typing.Tuple[typing.List[QuoteRow], int]:
    """Return quotation rows and the number of clause-verifier tables found."""
    lines = text.splitlines()
    rows: typing.List[QuoteRow] = []
    tables = 0
    index = 0
    while index < len(lines):
        if not lines[index].strip().startswith("|") or index + 1 >= len(lines):
            index += 1
            continue
        header_cells = [clean_cell(cell) for cell in split_row(lines[index])]
        if not is_separator_row(split_row(lines[index + 1])):
            index += 1
            continue
        clause_column = header_index(header_cells, CLAUSE_ID_HEADERS)
        quote_column = header_index(header_cells, QUOTED_TEXT_HEADERS)
        if clause_column is None or quote_column is None:
            index += 1
            continue
        tables += 1
        cursor = index + 2
        while cursor < len(lines) and lines[cursor].strip().startswith("|"):
            cells = [clean_cell(cell) for cell in split_row(lines[cursor])]
            clause_id = cells[clause_column] if clause_column < len(cells) else ""
            quoted_text = cells[quote_column] if quote_column < len(cells) else ""
            rows.append(QuoteRow(cursor + 1, clause_id, quoted_text))
            cursor += 1
        index = cursor
    return rows, tables


def load_clause_texts(
    spec_path: pathlib.Path, errors: typing.List[str]
) -> typing.Dict[str, str]:
    try:
        spec = json.loads(spec_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        errors.append(f"spec not found: {spec_path}")
        return {}
    except json.JSONDecodeError as exc:
        errors.append(f"spec invalid JSON: {spec_path}: line {exc.lineno} column {exc.colno}")
        return {}
    except OSError as exc:
        errors.append(f"spec cannot be read: {spec_path}: {exc}")
        return {}

    clauses = spec.get("clauses") if isinstance(spec, dict) else None
    if not isinstance(clauses, list) or not clauses:
        errors.append(f"spec has no clauses[]: {spec_path}")
        return {}

    clause_texts: typing.Dict[str, str] = {}
    for position, clause in enumerate(clauses):
        if not isinstance(clause, dict):
            errors.append(f"spec clauses[{position}] is not an object")
            continue
        clause_id = clause.get("clause_id")
        clause_text = clause.get("text")
        if not isinstance(clause_id, str) or not clause_id:
            errors.append(f"spec clauses[{position}] has no clause_id")
            continue
        if not isinstance(clause_text, str):
            errors.append(f"spec clauses[{position}] ({clause_id}) has no text")
            continue
        clause_texts[clause_id] = clause_text
    return clause_texts


def evaluate_rows(
    rows: typing.List[QuoteRow], clause_texts: typing.Dict[str, str]
) -> typing.Tuple[typing.List[str], typing.List[str], int]:
    errors: typing.List[str] = []
    warnings: typing.List[str] = []
    verified = 0
    for row in rows:
        clause_missing = is_placeholder(row.clause_id)
        quote_missing = is_placeholder(row.quoted_text)
        if clause_missing and quote_missing:
            continue
        if clause_missing:
            errors.append(
                f"line {row.line_number}: clause_id is missing for quoted_text: {excerpt(row.quoted_text)}"
            )
            continue
        if quote_missing:
            errors.append(f"line {row.line_number}: quoted_text is missing for clause: {row.clause_id}")
            continue
        clause_text = clause_texts.get(row.clause_id)
        if clause_text is None:
            errors.append(f"line {row.line_number}: unknown clause_id: {row.clause_id}")
            continue
        if normalize_nfkc(row.quoted_text) in normalize_nfkc(clause_text):
            verified += 1
            continue
        if normalize_verbatim_text(row.quoted_text) in normalize_verbatim_text(clause_text):
            warnings.append(
                f"line {row.line_number}: {row.clause_id}: quoted_text matches clauses[].text "
                f"only after whitespace normalization: {excerpt(row.quoted_text)}"
            )
            verified += 1
            continue
        errors.append(
            f"line {row.line_number}: {row.clause_id}: quoted_text not found in clauses[].text "
            f"(classify as fabrication risk): {excerpt(row.quoted_text)}"
        )
    return errors, warnings, verified


def check_quotes(
    spec_path: pathlib.Path, review_path: pathlib.Path
) -> typing.Tuple[typing.List[str], typing.List[str], int]:
    errors: typing.List[str] = []
    warnings: typing.List[str] = []
    clause_texts = load_clause_texts(spec_path, errors)

    try:
        review_text = review_path.read_text(encoding="utf-8")
    except FileNotFoundError:
        errors.append(f"review not found: {review_path}")
        return errors, warnings, 0
    except (OSError, UnicodeDecodeError) as exc:
        errors.append(f"review cannot be read: {review_path}: {exc}")
        return errors, warnings, 0

    rows, tables = collect_quote_rows(review_text)
    if tables == 0:
        errors.append(
            f"clause-verifier table not found in {review_path} "
            "(expected a Markdown table with clause_id and quoted_text columns)"
        )
        return errors, warnings, 0

    if errors:
        return errors, warnings, 0

    row_errors, row_warnings, verified = evaluate_rows(rows, clause_texts)
    errors.extend(row_errors)
    warnings.extend(row_warnings)
    if verified == 0 and not row_errors:
        warnings.append(f"no clause quotation rows found in {review_path}")
    return errors, warnings, verified


def main(argv: typing.List[str]) -> int:
    parser = argparse.ArgumentParser(usage="bash tools/check-quotes.sh <spec.json> <review.md>")
    parser.add_argument("spec_path")
    parser.add_argument("review_path")
    args = parser.parse_args(argv[1:])

    errors, warnings, verified = check_quotes(
        pathlib.Path(args.spec_path), pathlib.Path(args.review_path)
    )
    for warning in warnings:
        print(f"WARN: {warning}")
    for error in errors:
        print(f"FAIL: {error}")
    if errors:
        return 1
    print(f"OK: quote checks passed ({verified} quotation(s) verified)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
