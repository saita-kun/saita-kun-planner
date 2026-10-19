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
SEPARATOR_CELL_RE = re.compile(r"^:?-+:?$")
ATX_HEADING_RE = re.compile(r"^ {0,3}#{1,6}(?:[ \t]|$)")
SETEXT_HEADING_RE = re.compile(r"^ {0,3}(?:=+|-+) *$")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
LIST_ITEM_RE = re.compile(r"^ {0,3}(?P<marker>[-+*]|[0-9]{1,9}[.)])(?P<padding> +|$)")
BLOCK_QUOTE_RE = re.compile(r"^ {0,3}> ?")
THEMATIC_BREAK_RE = re.compile(r"^ {0,3}(?:(?:\* *){3,}|(?:- *){3,}|(?:_ *){3,})$")
# GFM HTML block start/end conditions: https://github.github.com/gfm/#html-blocks
HTML_BLOCK_RULES = (
    (re.compile(r"^ {0,3}<(?:script|pre|style)(?:[ \t>]|$)", re.I),
     re.compile(r"</(?:script|pre|style)>", re.I)),
    (re.compile(r"^ {0,3}<!--"), re.compile(r"-->")),
    (re.compile(r"^ {0,3}<\?"), re.compile(r"\?>")),
    (re.compile(r"^ {0,3}<![A-Z]"), re.compile(r">")),
    (re.compile(r"^ {0,3}<!\[CDATA\["), re.compile(r"\]\]>")),
    (re.compile(
        r"^ {0,3}</?(?:address|article|aside|base|basefont|blockquote|body|caption|"
        r"center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|"
        r"figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|"
        r"li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|section|"
        r"source|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:[ \t>]|/>|$)",
        re.I,
    ), re.compile(r"^ *$")),
)
HTML_COMPLETE_TAG_RE = re.compile(
    r"^ {0,3}(?:<(?!script[\s/>]|pre[\s/>]|style[\s/>])[a-z][a-z0-9-]*"
    r"(?:[ \t]+[a-z_:][a-z0-9_.:-]*"
    r'''(?:[ \t]*=[ \t]*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*'''
    r"[ \t]*/?>|</[a-z][a-z0-9-]*[ \t]*>)[ \t]*$",
    re.I,
)
HTML_BLANK_END_RE = re.compile(r"^ *$")
CLAUSE_ID_HEADERS = ("clause_id", "clauseid")
QUOTED_TEXT_HEADERS = ("quoted_text", "quotedtext")
EMPTY_ROW_CELLS = {"", "-"}
EXCERPT_LIMIT = 40


class QuoteRow(typing.NamedTuple):
    line_number: int
    clause_id: str
    quoted_text: str


class MarkdownLine(typing.NamedTuple):
    line_number: int
    kind: str
    content: str


class Container(typing.NamedTuple):
    kind: str
    width: int
    empty: bool = False


class BlockStart(typing.NamedTuple):
    kind: str
    width: int = 0
    fence: str = ""
    html_end: typing.Optional[typing.Pattern[str]] = None


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


def header_index(cells: typing.List[str], keys: typing.Tuple[str, ...]) -> typing.Optional[int]:
    for index, cell in enumerate(cells):
        flattened = normalize_nfkc(cell).replace("`", "").replace(" ", "").lower()
        if any(key in flattened for key in keys):
            return index
    return None


def is_separator_row(cells: typing.List[str]) -> bool:
    return bool(cells) and all(SEPARATOR_CELL_RE.match(cell.strip()) for cell in cells)


def match_code_fence(line: str) -> typing.Optional[typing.Match[str]]:
    match = FENCE_RE.match(line)
    # Backtick fence info cannot contain backticks; inline code remains a cell.
    if match and match.group(1)[0] == "`" and "`" in match.group(2):
        return None
    return match


def html_block_end(line: str, in_paragraph: bool = False) -> typing.Optional[typing.Pattern[str]]:
    for start, end in HTML_BLOCK_RULES:
        if start.match(line):
            return end
    # Complete standalone tags (type 7) cannot interrupt an existing paragraph.
    if not in_paragraph and HTML_COMPLETE_TAG_RE.match(line):
        return HTML_BLANK_END_RE
    return None


def start_markdown_block(line: str, in_paragraph: bool = False) -> BlockStart:
    """Classify content after container markers, using GFM block precedence."""
    if not line.strip():
        return BlockStart("blank")
    if ATX_HEADING_RE.match(line) or (in_paragraph and SETEXT_HEADING_RE.match(line)):
        return BlockStart("heading")
    if THEMATIC_BREAK_RE.match(line):
        return BlockStart("break")
    quote = BLOCK_QUOTE_RE.match(line)
    if quote:
        return BlockStart("quote", quote.end())
    item = LIST_ITEM_RE.match(line)
    if item:
        marker = item.group("marker")
        nonempty = bool(line[item.end():].strip())
        interrupts = nonempty and (not marker[0].isdigit() or int(marker[:-1]) == 1)
        if not in_paragraph or interrupts:
            padding = len(item.group("padding")) if nonempty else 1
            width = item.start("padding") + (padding if 1 <= padding <= 4 else 1)
            return BlockStart("list", width)
    fence = match_code_fence(line)
    if fence:
        return BlockStart("fence", fence=fence.group(1))
    html_end = html_block_end(line, in_paragraph)
    if html_end is not None:
        return BlockStart("html", html_end=html_end)
    if line.startswith("    ") and not in_paragraph:
        return BlockStart("indented_code")
    return BlockStart("paragraph")


def match_containers(line: str, containers: typing.List[Container]) -> typing.Tuple[int, int]:
    """Return the matched stack depth and the content's visual column."""
    offset = 0
    matched = 0
    for container in containers:
        content = line[offset:]
        if container.kind == "quote":
            marker = BLOCK_QUOTE_RE.match(content)
            if marker is None:
                break
            offset += marker.end()
        elif not content.strip():
            # An empty item cannot contain a second leading blank line.
            if container.empty:
                break
            offset = len(line)
        elif content.startswith(" " * container.width):
            offset += container.width
        else:
            break
        matched += 1
    return matched, offset


def source_content(line: str, offset: int) -> str:
    """Strip visual container columns without expanding tabs inside cells."""
    column = 0
    for index, character in enumerate(line):
        if column >= offset:
            return line[index:]
        column += 4 - column % 4 if character == "\t" else 1
        if column > offset:
            return " " * (column - offset) + line[index + 1:]
    return ""


def tokenize_markdown_lines(text: str) -> typing.List[MarkdownLine]:
    """Track containers and their leaf block once; table collection uses tokens.

    A delimiter promotes the preceding paragraph line to a table header. This
    keeps list-opener headers and ordinary tables in the same state machine as
    quotation tables, without a separate lookahead or row-scanning parser.
    """
    tokens: typing.List[MarkdownLine] = []
    containers: typing.List[Container] = []
    block = BlockStart("blank")
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.expandtabs(4)
        matched, offset = match_containers(line, containers)
        content = line[offset:]
        if matched < len(containers):
            start = start_markdown_block(content)
            if block.kind == "paragraph" and start.kind in ("paragraph", "indented_code"):
                # Lazy text belongs to the existing paragraph, never its parent.
                tokens.append(MarkdownLine(number, "lazy", source_content(raw, offset)))
                continue
            del containers[matched:]
            block = BlockStart("blank")
        if content.strip():
            containers = [container._replace(empty=False) for container in containers]

        if block.kind == "fence":
            fence = match_code_fence(content)
            if (fence and fence.group(1)[0] == block.fence[0]
                    and len(fence.group(1)) >= len(block.fence)
                    and not fence.group(2).strip()):
                block = BlockStart("blank")
            tokens.append(MarkdownLine(number, "code", source_content(raw, offset)))
            continue
        if block.kind == "html":
            if block.html_end.search(content):
                block = BlockStart("blank")
            tokens.append(MarkdownLine(number, "html", source_content(raw, offset)))
            continue
        if block.kind == "indented_code":
            if not content.strip() or content.startswith("    "):
                tokens.append(MarkdownLine(number, "code", source_content(raw, offset)))
                continue
            block = BlockStart("blank")

        # A lazy header must start at the matched container's content column;
        # leftover indentation keeps it paragraph text in GFM.
        # It also takes precedence over a one-column setext underline.
        if (block.kind == "paragraph" and tokens[-1].kind in ("paragraph", "lazy")
                and not (tokens[-1].kind == "lazy" and tokens[-1].content.startswith((" ", "\t")))
                and not content.startswith("    ")
                and CELL_SPLIT_RE.search(tokens[-1].content)):
            separator = split_row(content)
            if (is_separator_row(separator)
                    and len(split_row(tokens[-1].content)) == len(separator)):
                tokens[-1] = tokens[-1]._replace(kind="table_header")
                tokens.append(MarkdownLine(number, "table_delimiter", source_content(raw, offset)))
                block = BlockStart("table")
                continue

        start = start_markdown_block(content, block.kind == "paragraph")
        while start.kind in ("list", "quote"):
            offset += start.width
            content = line[offset:]
            containers.append(Container(start.kind, start.width, not content.strip()))
            block = BlockStart("blank")
            start = start_markdown_block(content)
        if start.kind == "paragraph" and block.kind == "table":
            kind = "table_row"
        else:
            block = start
            kind = start.kind
            if kind == "html" and start.html_end.search(content):
                block = BlockStart("blank")
        tokens.append(MarkdownLine(number, kind, source_content(raw, offset)))
    return tokens


def collect_quote_rows(text: str) -> typing.Tuple[typing.List[QuoteRow], int]:
    """Return quotation rows from table tokens, retaining source line numbers."""
    rows: typing.List[QuoteRow] = []
    tables = 0
    columns: typing.Optional[typing.Tuple[int, int]] = None
    for token in tokenize_markdown_lines(text):
        if token.kind == "table_header":
            headers = [clean_cell(cell) for cell in split_row(token.content)]
            clause_column = header_index(headers, CLAUSE_ID_HEADERS)
            quote_column = header_index(headers, QUOTED_TEXT_HEADERS)
            columns = None
            if clause_column is not None and quote_column is not None and clause_column != quote_column:
                columns = (clause_column, quote_column)
                tables += 1
        elif token.kind == "table_row" and columns is not None:
            # Short rows still need validation, even when they contain no pipe.
            cells = [clean_cell(cell) for cell in split_row(token.content)]
            clause_id, quoted_text = (cells[column] if column < len(cells) else "" for column in columns)
            rows.append(QuoteRow(token.line_number, clause_id, quoted_text))
        elif token.kind not in ("table_row", "table_delimiter"):
            columns = None
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
        clause_text = clause_texts.get(row.clause_id)
        # Empty-row markers apply only when the ID does not resolve.
        if (
            clause_text is None
            and row.clause_id in EMPTY_ROW_CELLS
            and row.quoted_text in EMPTY_ROW_CELLS
        ):
            continue
        if not row.clause_id:
            errors.append(
                f"line {row.line_number}: clause_id is missing for quoted_text: {excerpt(row.quoted_text)}"
            )
            continue
        if not row.quoted_text:
            errors.append(f"line {row.line_number}: quoted_text is missing for clause: {row.clause_id}")
            continue
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
