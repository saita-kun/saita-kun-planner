#!/usr/bin/env python3
# tools/lib/build_submission.py
#
# Builds one Markdown file that lists the draft bodies in the order the spec
# defines them, so the applicant can copy each body into the official form.
# Body extraction and character counting reuse check_drafts.py so the numbers
# shown here always match check-drafts.sh. This tool never judges eligibility
# or coverage; missing drafts are only labelled.

import argparse
import pathlib
import sys
import typing

if sys.version_info < (3, 7):
    sys.stderr.write(
        "FAIL: Python 3.7+ required (running %s)\n" % sys.version.split()[0]
    )
    raise SystemExit(1)

import check_drafts
from check_spec import check_expense_caps
from schedule import relative_deadline_text


Json = typing.Any
SectionKey = typing.Tuple[str, str]

NEED_CHECK_MARKER = "[要確認]"
APPLICATION_PHASE = "application"


class DraftBody(typing.NamedTuple):
    path: pathlib.Path
    body: str
    char_count: int
    need_check_count: int


def as_list(value: Json) -> typing.List[Json]:
    return value if isinstance(value, list) else []


def text_or_dash(value: Json) -> str:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return "（spec に記載なし。公式資料で確認）"


def required_label(item: Json) -> str:
    if item.get("required_if") is not None:
        condition = item.get("condition")
        hint = condition.strip() if isinstance(condition, str) and condition.strip() else "spec の `required_if` を参照。該当するかは `input/deliverables.md` で確認"
        return f"条件付き: {hint}"
    return "必須" if item.get("required") is True else "該当する場合"


def phase_of(item: Json) -> str:
    phase = item.get("phase") if isinstance(item, dict) else None
    return phase if isinstance(phase, str) and phase else APPLICATION_PHASE


def trim_blank_edges(body: str) -> str:
    lines = body.splitlines()
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


def collect_drafts(
    drafts_dir: pathlib.Path, errors: typing.List[str]
) -> typing.Dict[SectionKey, DraftBody]:
    drafts: typing.Dict[SectionKey, DraftBody] = {}
    if not drafts_dir.exists():
        errors.append(f"drafts_dir not found: {drafts_dir}")
        return drafts
    if not drafts_dir.is_dir():
        errors.append(f"drafts_dir is not a directory: {drafts_dir}")
        return drafts

    for draft_path in sorted(drafts_dir.glob("*.md")):
        text, read_errors = check_drafts.read_draft(draft_path, errors)
        if read_errors:
            errors.extend(read_errors)
            continue
        frontmatter, body_start, frontmatter_errors = check_drafts.parse_frontmatter(draft_path, text)
        if frontmatter_errors:
            errors.extend(frontmatter_errors)
            continue
        body, body_errors = check_drafts.find_draft_body(draft_path, text.splitlines(), body_start)
        if body_errors:
            errors.extend(body_errors)
            continue
        key = (frontmatter["deliverable_id"], frontmatter["section_id"])
        if key in drafts:
            errors.append(
                f"{draft_path}: duplicate draft for {key[0]}/{key[1]} "
                f"(also {drafts[key].path})"
            )
            continue
        drafts[key] = DraftBody(
            path=draft_path,
            body=trim_blank_edges(body),
            char_count=check_drafts.count_body_chars(body),
            need_check_count=body.count(NEED_CHECK_MARKER),
        )
    return drafts


def event_label(event: Json) -> str:
    date = event.get("date")
    time = event.get("time")
    if isinstance(date, str) and date:
        return f"{date} {time}" if isinstance(time, str) and time else date
    ends_at = event.get("ends_at")
    if isinstance(ends_at, str) and ends_at:
        return f"〜{ends_at}"
    return relative_deadline_text(event) or "日付は公式資料で確認"


def schedule_index(spec: Json) -> typing.Dict[str, Json]:
    index: typing.Dict[str, Json] = {}
    for event in as_list(spec.get("schedule")):
        if isinstance(event, dict) and isinstance(event.get("event_id"), str):
            index[event["event_id"]] = event
    return index


def due_label(deliverable: Json, events: typing.Dict[str, Json]) -> str:
    event = events.get(deliverable.get("due_event_id")) if isinstance(deliverable.get("due_event_id"), str) else None
    if event is None:
        return "（spec に記載なし。公式資料で確認）"
    return f"{event_label(event)}（{text_or_dash(event.get('name'))}）"


def char_limit_label(section: Json) -> str:
    max_chars = section.get("max_chars")
    if isinstance(max_chars, int) and not isinstance(max_chars, bool):
        return f"上限 {max_chars} 字"
    return "上限は様式で確認"


def render(
    spec: Json,
    drafts: typing.Dict[SectionKey, DraftBody],
    drafts_digest: str,
    warnings: typing.List[str],
) -> str:
    events = schedule_index(spec)
    deliverables = [item for item in as_list(spec.get("deliverables")) if isinstance(item, dict)]
    application_items = [item for item in deliverables if phase_of(item) == APPLICATION_PHASE]
    with_sections = [item for item in application_items if as_list(item.get("sections"))]
    without_sections = [item for item in application_items if not as_list(item.get("sections"))]

    out: typing.List[str] = []
    out.append(f"# 提出用まとめ: {text_or_dash(spec.get('name'))}")
    out.append("")
    out.append(f"- 公募回: {text_or_dash(spec.get('round'))}")
    out.append(f"- 対象 ID: {text_or_dash(spec.get('subsidy_id'))}（spec_version {spec.get('spec_version')}）")
    out.append(f"- draft 本文ハッシュ: {drafts_digest}")
    out.append("")
    out.append(
        "この資料は、作成した叩き台を公式の様式・申請システムへ移すための控えです。"
        "転記・提出・内容の最終確認は申請者本人が行ってください。"
        "字数・様式・提出方法は、必ず公式の募集要項で確認してください。"
    )
    out.append("")
    out.append("## 1. 入力・貼り付けする本文")
    out.append("")
    need_check_total = sum(draft.need_check_count for draft in drafts.values())
    need_check_sections = sum(1 for draft in drafts.values() if draft.need_check_count)
    if need_check_total:
        out.append(
            f"本文に残っている {NEED_CHECK_MARKER}: 合計 {need_check_total} か所"
            f"（{need_check_sections} セクション）"
        )
    else:
        out.append(f"本文に残っている {NEED_CHECK_MARKER}: 0 か所")
    out.append("")

    used: typing.Set[SectionKey] = set()
    if not with_sections:
        out.append("spec に、本文を作る対象の成果物がありません。")
        out.append("")
    for deliverable in with_sections:
        deliverable_id = deliverable.get("deliverable_id")
        out.append(f"### {text_or_dash(deliverable.get('name'))}")
        out.append("")
        if deliverable.get("required_if") is not None:
            out.append(f"- {required_label(deliverable)}")
        out.append(f"- 形式: {text_or_dash(deliverable.get('format'))}")
        out.append(f"- 提出先・入力先: {text_or_dash(deliverable.get('upload_target'))}")
        out.append(f"- 期限: {due_label(deliverable, events)}")
        out.append("")
        for section in as_list(deliverable.get("sections")):
            if not isinstance(section, dict):
                continue
            section_id = section.get("section_id")
            key = (deliverable_id, section_id)
            out.append(f"#### {text_or_dash(section.get('name'))}")
            out.append("")
            if section.get("required_if") is not None:
                out.append(f"- {required_label(section)}")
            draft = drafts.get(key)
            if draft is None:
                out.append(f"- 状態: 未作成（{char_limit_label(section)}）")
                out.append("")
                continue
            used.add(key)
            out.append(f"- 字数: {draft.char_count} 字（{char_limit_label(section)}）")
            if draft.need_check_count:
                out.append(
                    f"- {NEED_CHECK_MARKER} が {draft.need_check_count} か所残っています。"
                    "転記の前に確認して書き直してください。"
                )
            out.append("")
            out.append(draft.body)
            out.append("")

    for key in sorted(set(drafts) - used):
        warnings.append(
            f"draft not listed in spec sections, skipped: {key[0]}/{key[1]} ({drafts[key].path})"
        )

    out.append("## 2. 本文以外に用意するもの")
    out.append("")
    if not without_sections:
        out.append("spec に、本文以外の成果物の記載がありません。公式資料で確認してください。")
        out.append("")
    for deliverable in without_sections:
        required = required_label(deliverable)
        out.append(f"- [ ] {text_or_dash(deliverable.get('name'))}（{required}）")
        out.append(f"  - 形式: {text_or_dash(deliverable.get('format'))}")
        out.append(f"  - 提出先・入力先: {text_or_dash(deliverable.get('upload_target'))}")
        out.append(f"  - 期限: {due_label(deliverable, events)}")
    if without_sections:
        out.append("")

    out.append("## 3. 期限")
    out.append("")
    hard_events = [
        event
        for event in as_list(spec.get("schedule"))
        if isinstance(event, dict) and event.get("hard") is True and phase_of(event) == APPLICATION_PHASE
    ]
    dated = sorted(
        (event for event in hard_events if isinstance(event.get("date"), str) and event.get("date")),
        key=lambda event: (event["date"], event.get("time") or ""),
    )
    undated = [event for event in hard_events if event not in dated]
    if not hard_events:
        out.append("spec に、申請までの期限の記載がありません。公式資料で確認してください。")
    for event in dated + undated:
        out.append(f"- {event_label(event)}: {text_or_dash(event.get('name'))}")
    out.append("")
    out.append("## 4. 経費区分の上限")
    out.append("")
    out.append("各上限をすべて確認してください。上限に収まるか・超えるかは断定しません。原文への当てはめは申請者本人が確認してください。")
    funding = spec.get("funding") or {}
    for expense in as_list(funding.get("eligible_expenses")):
        out.append(f"- {text_or_dash(expense.get('category'))}")
        if not any(cap.get("kind") in ("amount", "ratio") for cap in as_list(expense.get("caps"))):
            out.append("  - この区分だけの上限は読み取ったデータにありません。全体の上限と条件は公募要領で確かめてください。")
        for cap in as_list(expense.get("caps")):
            if cap.get("kind") == "amount":
                limit = f"{cap['amount']} 万円"
            elif cap.get("kind") == "ratio":
                limit = f"{cap['basis']}の {cap['numerator']}/{cap['denominator']} "
            else:
                continue
            sources = "、".join(cap.get("source_clauses", []))
            out.append(f"  - {cap['applies_to']}: {limit}まで（根拠: {sources}）")
    out.append("")
    return "\n".join(out)


def default_output(spec: Json) -> pathlib.Path:
    root = pathlib.Path(__file__).resolve().parents[2]
    return root / "input" / "submission" / f"{spec.get('subsidy_id')}.md"


def main(argv: typing.List[str]) -> int:
    parser = argparse.ArgumentParser(usage=(
        "bash tools/build-submission.sh <spec.json> <drafts_dir> [--output <path>|-]"
    ))
    parser.add_argument("spec", type=pathlib.Path)
    parser.add_argument("drafts_dir", type=pathlib.Path)
    parser.add_argument("--output", default=None)
    args = parser.parse_args(argv[1:])

    errors: typing.List[str] = []
    warnings: typing.List[str] = []
    spec = check_drafts.load_json(args.spec, errors, "spec")
    if spec is not None and not isinstance(spec, dict):
        errors.append(f"spec must be a JSON object: {args.spec}")
        spec = None
    if isinstance(spec, dict) and not (isinstance(spec.get("subsidy_id"), str) and spec.get("subsidy_id")):
        errors.append(f"spec missing subsidy_id: {args.spec}")

    if isinstance(spec, dict):
        check_expense_caps(spec, errors)
    drafts = collect_drafts(args.drafts_dir, errors)
    drafts_digest, digest_errors = check_drafts.draft_bodies_sha256(args.drafts_dir)
    for error in digest_errors:
        if error not in errors:
            errors.append(error)

    if errors or spec is None:
        for error in errors:
            print(f"FAIL: {error}")
        return 1

    document = render(spec, drafts, drafts_digest, warnings)
    for warning in warnings:
        print(f"WARN: {warning}", file=sys.stderr if args.output == "-" else sys.stdout)

    if args.output == "-":
        sys.stdout.write(document)
        return 0

    output_path = pathlib.Path(args.output) if args.output else default_output(spec)
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(document, encoding="utf-8")
    except OSError as exc:
        print(f"FAIL: cannot write {output_path}: {exc}")
        return 1
    print(f"OK: submission summary written: {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
