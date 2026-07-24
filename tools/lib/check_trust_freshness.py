#!/usr/bin/env python3
"""Validate PR-2 trust/freshness documents without third-party packages."""

from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import re
import sys
import typing

import check_spec
import spec_resolver


Json = typing.Any
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
TABLE_HEADING = "## 同梱 spec の鮮度（原本突合の記録）"
TABLE_HEADERS = (
    "spec id",
    "公募回",
    "個別項目の突合日（範囲・件数）",
    "provider 最終確認日",
    "版固定資料数",
    "出典",
)
CANONICAL_ISSUE_URL = (
    "https://github.com/saita-kun/saita-kun-planner/issues/new?template=adopter-entry.yml"
)


class ValidationError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def load_object(path: pathlib.Path, label: str) -> typing.Dict[str, Json]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"{label} cannot be loaded: {path.as_posix()}: {exc}") from exc
    require(isinstance(value, dict), f"{label} root must be an object: {path.as_posix()}")
    return typing.cast(typing.Dict[str, Json], value)


def confirmation_path_for(spec_path: pathlib.Path) -> pathlib.Path:
    return spec_path.with_name(f"{spec_path.stem}.confirmation.json")


def _table_cells(line: str) -> typing.List[str]:
    stripped = line.strip()
    require(stripped.startswith("|") and stripped.endswith("|"), f"invalid table row: {line}")
    return [cell.strip() for cell in stripped[1:-1].split("|")]


def freshness_table_rows(path: pathlib.Path) -> typing.List[typing.List[str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    try:
        heading_index = lines.index(TABLE_HEADING)
    except ValueError as exc:
        raise ValidationError(f"freshness table heading missing: {TABLE_HEADING}") from exc

    table_index: typing.Optional[int] = None
    for index in range(heading_index + 1, len(lines)):
        if lines[index].startswith("## "):
            break
        if lines[index].lstrip().startswith("|"):
            table_index = index
            break
    require(table_index is not None, "freshness table is missing")
    assert table_index is not None

    headers = _table_cells(lines[table_index])
    require(tuple(headers) == TABLE_HEADERS, f"freshness table headers mismatch: {headers}")
    require(table_index + 1 < len(lines), "freshness table separator is missing")
    separators = _table_cells(lines[table_index + 1])
    require(
        len(separators) == len(TABLE_HEADERS)
        and all(re.fullmatch(r":?-{3,}:?", cell) for cell in separators),
        "freshness table separator is invalid",
    )

    rows: typing.List[typing.List[str]] = []
    for line in lines[table_index + 2 :]:
        if not line.lstrip().startswith("|"):
            break
        cells = _table_cells(line)
        require(len(cells) == len(TABLE_HEADERS), f"freshness table row width mismatch: {line}")
        rows.append(cells)
    return rows


def parse_iso_date(value: Json, label: str) -> datetime.date:
    require(isinstance(value, str), f"{label} must be an ISO date string")
    assert isinstance(value, str)
    require(re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value) is not None, f"{label} must be YYYY-MM-DD")
    try:
        return datetime.date.fromisoformat(value)
    except ValueError as exc:
        raise ValidationError(f"{label} is not a valid ISO date: {value}") from exc


def parse_confirmation_date(value: Json, label: str) -> datetime.date:
    require(isinstance(value, str), f"{label} must be an ISO8601 string")
    assert isinstance(value, str)
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        return datetime.datetime.fromisoformat(normalized).date()
    except ValueError as exc:
        raise ValidationError(f"{label} is not a valid ISO8601 datetime: {value}") from exc


def provider_pack_records(
    specs_root: pathlib.Path,
    repo_root: pathlib.Path,
) -> typing.Dict[str, typing.Tuple[typing.Dict[str, Json], typing.Dict[str, Json]]]:
    records: typing.Dict[str, typing.Tuple[typing.Dict[str, Json], typing.Dict[str, Json]]] = {}
    try:
        candidates = spec_resolver.resolve_bundled_specs(specs_root, repo_root)
    except spec_resolver.ResolverError as exc:
        raise ValidationError("; ".join(exc.messages)) from exc

    for candidate in candidates:
        if candidate.source_kind != "pack":
            continue
        spec = load_object(candidate.spec_path, "bundled spec")
        confirmation_path = confirmation_path_for(candidate.spec_path)
        if not confirmation_path.is_file():
            continue
        confirmation = load_object(confirmation_path, "confirmation")
        if spec.get("status") != "confirmed" or confirmation.get("confirmed_by") != "provider":
            continue
        binding_errors: typing.List[str] = []
        check_spec.check_confirmation_spec_reference(
            spec,
            candidate.spec_path,
            confirmation,
            binding_errors,
        )
        check_spec.check_confirmation_sha(
            candidate.spec_path,
            confirmation_path,
            confirmation,
            binding_errors,
        )
        require(
            not binding_errors,
            f"{candidate.subsidy_id}: invalid confirmation binding: {'; '.join(binding_errors)}",
        )
        records[candidate.subsidy_id] = (spec, confirmation)
    return records


def expected_freshness_cells(
    subsidy_id: str,
    spec: typing.Dict[str, Json],
    confirmation: typing.Dict[str, Json],
) -> typing.Tuple[str, str, str, str, str]:
    round_name = spec.get("round")
    require(isinstance(round_name, str) and bool(round_name), f"{subsidy_id}: round is required")
    portal_url = spec.get("portal_url")
    require(isinstance(portal_url, str) and bool(portal_url), f"{subsidy_id}: portal_url is required")

    items = confirmation.get("items")
    require(isinstance(items, list) and bool(items), f"{subsidy_id}: confirmation.items is required")
    dates: typing.List[datetime.date] = []
    counts = {"confirmed": 0, "na": 0}
    assert isinstance(items, list)
    for index, item in enumerate(items):
        require(isinstance(item, dict), f"{subsidy_id}: confirmation.items[{index}] must be an object")
        assert isinstance(item, dict)
        dates.append(
            parse_iso_date(item.get("confirmed_at"), f"{subsidy_id}: confirmation.items[{index}].confirmed_at")
        )
        state = item.get("state")
        require(state in counts, f"{subsidy_id}: provider item state must be confirmed or na: {state!r}")
        counts[typing.cast(str, state)] += 1

    confirmed_range = (
        f"{min(dates).isoformat()}〜{max(dates).isoformat()}"
        f"（confirmed {counts['confirmed']} / na {counts['na']}）"
    )
    provider_date = parse_confirmation_date(
        confirmation.get("confirmed_at"),
        f"{subsidy_id}: confirmation.confirmed_at",
    ).isoformat()

    source_documents = spec.get("source_documents")
    require(isinstance(source_documents, list) and bool(source_documents), f"{subsidy_id}: source_documents is required")
    fixed = 0
    assert isinstance(source_documents, list)
    for index, document in enumerate(source_documents):
        require(isinstance(document, dict), f"{subsidy_id}: source_documents[{index}] must be an object")
        assert isinstance(document, dict)
        sha256 = document.get("sha256")
        if sha256 is None:
            continue
        require(
            isinstance(sha256, str) and SHA256_RE.fullmatch(sha256) is not None,
            f"{subsidy_id}: source_documents[{index}].sha256 is invalid",
        )
        fixed += 1
    total = len(source_documents)
    fixed_label = f"sha256 固定 {fixed} / 全 {total}"
    if fixed < total:
        fixed_label += "（live 再確認必須）"

    return (
        typing.cast(str, round_name),
        confirmed_range,
        provider_date,
        fixed_label,
        typing.cast(str, portal_url),
    )


def check_freshness_table(repo_root: pathlib.Path) -> None:
    rows = freshness_table_rows(repo_root / "specs/README.md")
    row_ids = [row[0] for row in rows]
    require(len(row_ids) == len(set(row_ids)), f"freshness table has duplicate spec ids: {row_ids}")

    records = provider_pack_records(repo_root / "specs", repo_root)
    require(
        set(row_ids) == set(records),
        f"freshness table spec set mismatch: table={sorted(row_ids)}, bundled={sorted(records)}",
    )

    rows_by_id = {row[0]: row for row in rows}
    for subsidy_id, (spec, confirmation) in sorted(records.items()):
        expected_round, expected_range, expected_provider_date, expected_fixed, portal_url = (
            expected_freshness_cells(subsidy_id, spec, confirmation)
        )
        actual = rows_by_id[subsidy_id]
        require(actual[1] == expected_round, f"{subsidy_id}: freshness round mismatch")
        require(actual[2] == expected_range, f"{subsidy_id}: freshness item dates/counts mismatch")
        require(actual[3] == expected_provider_date, f"{subsidy_id}: freshness provider date mismatch")
        require(actual[4] == expected_fixed, f"{subsidy_id}: freshness sha256 count/note mismatch")
        source_match = re.fullmatch(r"\[[^\]]+\]\(([^)]+)\)", actual[5])
        require(source_match is not None, f"{subsidy_id}: freshness source must be a Markdown link")
        assert source_match is not None
        require(source_match.group(1) == portal_url, f"{subsidy_id}: freshness portal_url mismatch")


class YamlSubsetParser:
    """Parse the mapping/list/scalar subset used by GitHub Issue Forms."""

    def __init__(self, text: str) -> None:
        self.lines = text.splitlines()
        for line_number, line in enumerate(self.lines, start=1):
            if "\t" in line:
                raise ValidationError(f"YAML tabs are not supported: line {line_number}")

    @staticmethod
    def _indent(line: str) -> int:
        return len(line) - len(line.lstrip(" "))

    def _next_content(self, index: int) -> int:
        while index < len(self.lines):
            stripped = self.lines[index].strip()
            if stripped and not stripped.startswith("#"):
                break
            index += 1
        return index

    @staticmethod
    def _key_value(text: str, line_number: int) -> typing.Tuple[str, str]:
        if ":" not in text:
            raise ValidationError(f"YAML mapping entry lacks colon: line {line_number}")
        key, value = text.split(":", 1)
        key = key.strip()
        if not re.fullmatch(r"[A-Za-z0-9_-]+", key):
            raise ValidationError(f"unsupported YAML key {key!r}: line {line_number}")
        return key, value.strip()

    @staticmethod
    def _scalar(value: str, line_number: int) -> Json:
        if not value:
            raise ValidationError(f"empty YAML scalar: line {line_number}")
        if value in {"null", "~"}:
            return None
        if value == "true":
            return True
        if value == "false":
            return False
        if value.startswith('"'):
            try:
                parsed = json.loads(value)
            except json.JSONDecodeError as exc:
                raise ValidationError(f"invalid quoted YAML scalar: line {line_number}") from exc
            require(isinstance(parsed, str), f"quoted YAML scalar must be a string: line {line_number}")
            return parsed
        if value.startswith("["):
            try:
                parsed = json.loads(value)
            except json.JSONDecodeError as exc:
                raise ValidationError(f"invalid inline YAML list: line {line_number}") from exc
            require(isinstance(parsed, list), f"inline YAML value must be a list: line {line_number}")
            return parsed
        if value.startswith(("{", "&", "*", "!")):
            raise ValidationError(f"unsupported YAML feature: line {line_number}")
        return value

    def _block_scalar(self, index: int, parent_indent: int) -> typing.Tuple[str, int]:
        start = index
        while index < len(self.lines):
            line = self.lines[index]
            if line.strip() and self._indent(line) <= parent_indent:
                break
            index += 1
        block_lines = self.lines[start:index]
        content_indents = [self._indent(line) for line in block_lines if line.strip()]
        require(bool(content_indents), f"empty YAML block scalar after line {start}")
        content_indent = min(content_indents)
        value = "\n".join(
            line[content_indent:] if line.strip() else "" for line in block_lines
        )
        return value, index

    def _mapping_value(
        self,
        raw_value: str,
        index: int,
        indent: int,
    ) -> typing.Tuple[Json, int]:
        if raw_value in {"|", "|-", "|+", ">", ">-", ">+"}:
            return self._block_scalar(index + 1, indent)
        if raw_value:
            return self._scalar(raw_value, index + 1), index + 1
        child_index = self._next_content(index + 1)
        require(child_index < len(self.lines), f"missing nested YAML value: line {index + 1}")
        child_indent = self._indent(self.lines[child_index])
        require(child_indent > indent, f"nested YAML value must be indented: line {child_index + 1}")
        return self._node(child_index, child_indent)

    def _mapping(self, index: int, indent: int) -> typing.Tuple[typing.Dict[str, Json], int]:
        result: typing.Dict[str, Json] = {}
        while True:
            index = self._next_content(index)
            if index >= len(self.lines):
                break
            line = self.lines[index]
            current_indent = self._indent(line)
            if current_indent < indent:
                break
            require(current_indent == indent, f"unexpected YAML indentation: line {index + 1}")
            stripped = line.strip()
            if stripped.startswith("- "):
                break
            key, raw_value = self._key_value(stripped, index + 1)
            require(key not in result, f"duplicate YAML key {key!r}: line {index + 1}")
            value, index = self._mapping_value(raw_value, index, indent)
            result[key] = value
        return result, index

    def _sequence(self, index: int, indent: int) -> typing.Tuple[typing.List[Json], int]:
        result: typing.List[Json] = []
        while True:
            index = self._next_content(index)
            if index >= len(self.lines):
                break
            line = self.lines[index]
            current_indent = self._indent(line)
            if current_indent < indent:
                break
            require(current_indent == indent, f"unexpected YAML sequence indentation: line {index + 1}")
            stripped = line.strip()
            if not stripped.startswith("- "):
                break
            item_text = stripped[2:].strip()
            require(bool(item_text), f"empty YAML sequence item: line {index + 1}")

            if ":" not in item_text:
                result.append(self._scalar(item_text, index + 1))
                index += 1
                continue

            key, raw_value = self._key_value(item_text, index + 1)
            item: typing.Dict[str, Json] = {}
            value, next_index = self._mapping_value(raw_value, index, indent + 2)
            item[key] = value
            index = next_index

            continuation_index = self._next_content(index)
            if continuation_index < len(self.lines):
                continuation_indent = self._indent(self.lines[continuation_index])
                if continuation_indent > indent:
                    continuation, index = self._mapping(continuation_index, continuation_indent)
                    overlap = set(item) & set(continuation)
                    require(not overlap, f"duplicate YAML sequence mapping keys: {sorted(overlap)}")
                    item.update(continuation)
            result.append(item)
        return result, index

    def _node(self, index: int, indent: int) -> typing.Tuple[Json, int]:
        index = self._next_content(index)
        require(index < len(self.lines), "YAML document is empty")
        if self.lines[index].strip().startswith("- "):
            return self._sequence(index, indent)
        return self._mapping(index, indent)

    def parse(self) -> Json:
        index = self._next_content(0)
        require(index < len(self.lines), "YAML document is empty")
        indent = self._indent(self.lines[index])
        require(indent == 0, "YAML root must start at column zero")
        value, next_index = self._node(index, indent)
        require(self._next_content(next_index) == len(self.lines), "trailing YAML content")
        return value


def field_by_id(body: typing.List[Json], field_id: str) -> typing.Dict[str, Json]:
    matches = [item for item in body if isinstance(item, dict) and item.get("id") == field_id]
    require(len(matches) == 1, f"Issue Form must contain exactly one field id={field_id!r}")
    return typing.cast(typing.Dict[str, Json], matches[0])


def field_options(field: typing.Dict[str, Json], field_id: str) -> typing.List[Json]:
    attributes = field.get("attributes")
    require(isinstance(attributes, dict), f"Issue Form {field_id}.attributes must be an object")
    options = attributes.get("options")
    require(isinstance(options, list), f"Issue Form {field_id}.attributes.options must be an array")
    return typing.cast(typing.List[Json], options)


def field_required(field: typing.Dict[str, Json]) -> Json:
    validations = field.get("validations")
    return validations.get("required") if isinstance(validations, dict) else None


def check_adopter_form(repo_root: pathlib.Path) -> None:
    form_path = repo_root / ".github/ISSUE_TEMPLATE/adopter-entry.yml"
    document = YamlSubsetParser(form_path.read_text(encoding="utf-8")).parse()
    require(isinstance(document, dict), "Issue Form YAML root must be a mapping")
    assert isinstance(document, dict)
    for key in ("name", "description", "body"):
        require(key in document, f"Issue Form top-level key is missing: {key}")
    require(
        isinstance(document.get("name"), str) and bool(document.get("name")),
        "Issue Form name must be a non-empty string",
    )
    description = document.get("description")
    require(isinstance(description, str), "Issue Form description must be a string")
    assert isinstance(description, str)
    require("canonical repo" in description and "でのみ" in description, "Issue Form description lacks canonical-only notice")

    body = document.get("body")
    require(isinstance(body, list) and bool(body), "Issue Form body must be a non-empty array")
    assert isinstance(body, list)
    intro = body[0]
    require(isinstance(intro, dict) and intro.get("type") == "markdown", "Issue Form body[0] must be markdown")
    assert isinstance(intro, dict)
    intro_attributes = intro.get("attributes")
    require(isinstance(intro_attributes, dict), "Issue Form body[0].attributes must be an object")
    intro_value = intro_attributes.get("value") if isinstance(intro_attributes, dict) else None
    require(isinstance(intro_value, str), "Issue Form body[0].attributes.value must be a string")
    assert isinstance(intro_value, str)
    for anchor in (
        CANONICAL_ISSUE_URL,
        "複製した自分の repo",
        "本家",
        "投稿した GitHub アカウント",
        "公開されます",
        "制度の正式名称・公募回・年度・地域",
        "申請中の情報",
        "顧客・第三者の特定",
        "申請本文",
        "具体的数値",
        "完全には消えません",
    ):
        require(anchor in intro_value, f"Issue Form intro missing required notice: {anchor}")

    display_name = field_by_id(body, "display-name")
    require(display_name.get("type") == "input", "Issue Form display-name must be input")
    require(field_required(display_name) is True, "Issue Form display-name must be required")
    display_attributes = display_name.get("attributes")
    display_description = display_attributes.get("description") if isinstance(display_attributes, dict) else None
    require(
        isinstance(display_description, str) and "アカウント名と別の名称" in display_description,
        "Issue Form display-name must explain that another name is allowed",
    )

    role = field_by_id(body, "role")
    require(role.get("type") == "dropdown", "Issue Form role must be dropdown")
    role_options = field_options(role, "role")
    for role_name in ("事業者", "支援者", "開発者"):
        require(any(isinstance(option, str) and role_name in option for option in role_options), f"Issue Form role missing {role_name}")

    category = field_by_id(body, "subsidy-category")
    require(category.get("type") == "dropdown", "Issue Form subsidy-category must be dropdown")
    require(field_required(category) is False, "Issue Form subsidy-category must be optional")
    category_options = field_options(category, "subsidy-category")
    for category_name in ("持続化", "ものづくり", "IT導入", "事業再構築", "自治体系", "その他", "非公開"):
        require(category_name in category_options, f"Issue Form subsidy-category missing {category_name}")

    comment = field_by_id(body, "comment")
    require(comment.get("type") == "textarea", "Issue Form comment must be textarea")

    input_fields = [
        field for field in body if isinstance(field, dict) and field.get("type") == "input"
    ]
    require(
        len(input_fields) == 1 and input_fields[0].get("id") == "display-name",
        "Issue Form must not contain an input other than display-name",
    )
    for field in input_fields:
        if not isinstance(field, dict) or field.get("type") != "input":
            continue
        attributes = field.get("attributes")
        searchable = " ".join(
            str(value)
            for value in (
                field.get("id"),
                attributes.get("label") if isinstance(attributes, dict) else None,
                attributes.get("description") if isinstance(attributes, dict) else None,
            )
            if value is not None
        )
        require("制度名" not in searchable and "補助金名" not in searchable, "Issue Form must not have a free-text subsidy name input")

    consent = field_by_id(body, "consent")
    require(consent.get("type") == "checkboxes", "Issue Form consent must be checkboxes")
    consent_options = field_options(consent, "consent")
    require(len(consent_options) == 5, "Issue Form consent must contain exactly five items")
    labels: typing.List[str] = []
    for index, option in enumerate(consent_options):
        require(isinstance(option, dict), f"Issue Form consent option {index} must be an object")
        assert isinstance(option, dict)
        require(option.get("required") is True, f"Issue Form consent option {index} must be required")
        label = option.get("label")
        require(isinstance(label, str), f"Issue Form consent option {index}.label must be a string")
        labels.append(typing.cast(str, label))
    require(len(labels) == len(set(labels)), "Issue Form consent labels must be unique")
    joined = "\n".join(labels)
    for anchors in (
        ("ADOPTERS.md", "掲載"),
        ("投稿", "アカウント", "公開"),
        ("体裁編集", "OSS", "Apache-2.0", "収載", "許諾"),
        ("本人", "掲載", "権限"),
        ("掲載規定", "従"),
    ):
        require(any(all(anchor in label for anchor in anchors) for label in labels), f"Issue Form consent missing anchors: {anchors}; labels={joined}")


def main(argv: typing.List[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("check", choices=["freshness-table", "adopter-form", "all"])
    parser.add_argument("--repo-root", default=".")
    args = parser.parse_args(argv[1:])
    repo_root = pathlib.Path(args.repo_root)
    try:
        if args.check in {"freshness-table", "all"}:
            check_freshness_table(repo_root)
        if args.check in {"adopter-form", "all"}:
            check_adopter_form(repo_root)
    except (OSError, ValidationError) as exc:
        print(f"FAIL: {exc}")
        return 1
    print(f"OK: trust/freshness {args.check} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
