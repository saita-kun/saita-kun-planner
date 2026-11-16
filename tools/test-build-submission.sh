#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${PLANNER_PYTHON:-python3}" - "$ROOT" <<'PY'
import json
import pathlib
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(source / "tools/lib"))
from schedule import relative_deadline_text
import build_submission

passed = 0
failed = 0


def expect(label, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
    else:
        failed += 1
        print("FAIL: {} {}".format(label, detail))


for unit, suffix in [("day", "日"), ("month", "か月"), ("year", "年")]:
    for direction, expected in [("within_after", "起算日から2{}以内"),
                                ("before", "起算日の2{}前まで"),
                                (None, "起算日起点・2{}（前後は要確認）")]:
        event = {"relative": {"anchor": "起算日", "offset": {"value": 2, "unit": unit}, "direction": direction}}
        expect("calendar unit and direction", relative_deadline_text(event) == expected.format(suffix))
for direction, expected in [("within_after", "起算日以降"), ("before", "起算日より前"), (None, "起算日起点")]:
    expect("unknown offset preserves direction", relative_deadline_text({"relative": {
        "anchor": "起算日", "offset": None, "direction": direction}}) == expected)


def run(*args, stderr=subprocess.STDOUT):
    return subprocess.run(
        ["bash", str(source / "tools/build-submission.sh")] + [str(arg) for arg in args],
        cwd=str(source),
        stdout=subprocess.PIPE,
        stderr=stderr,
        universal_newlines=True,
    )


def draft(deliverable_id, section_id, body):
    return (
        "---\n"
        "deliverable_id: {}\n"
        "section_id: {}\n"
        "---\n\n"
        "## 叩き台\n\n{}\n\n"
        "## メモ\n\nここは本文に含めない。\n"
    ).format(deliverable_id, section_id, body)


def clause_refs():
    return ["fixture-001"]


def make_spec():
    # A fictional scheme: names are generic so no real program is implied.
    return {
        "subsidy_id": "fixture-scheme",
        "spec_version": 3,
        "name": "架空の設備導入支援事業",
        "round": "架空第1回",
        "schedule": [
            {
                "event_id": "late-deadline", "name": "申請締切", "event_kind": "application_deadline",
                "date": "2030-03-31", "time": "17:00", "hard": True, "phase": "application",
                "source_clauses": clause_refs(),
            },
            {
                "event_id": "early-deadline", "name": "事前確認書の依頼締切", "event_kind": "support_letter_deadline",
                "date": "2030-03-10", "time": None, "hard": True, "phase": "application",
                "source_clauses": clause_refs(),
            },
            {
                "event_id": "soft-event", "name": "説明会", "event_kind": "other",
                "date": "2030-02-01", "hard": False, "phase": "application",
                "source_clauses": clause_refs(),
            },
            {
                "event_id": "report-deadline", "name": "実績報告期限", "event_kind": "report_deadline",
                "date": "2031-01-31", "hard": True, "phase": "post_adoption",
                "source_clauses": clause_refs(),
            },
            {
                "event_id": "undated", "name": "補助事業の実施期間", "event_kind": "project_period",
                "date": None, "hard": True,
                "source_clauses": clause_refs(),
            },
            {
                "event_id": "ends-only", "name": "事業の実施期限", "event_kind": "project_period",
                "date": None, "ends_at": "2031-06-30", "hard": True, "phase": "application",
                "relative": {"anchor": "交付決定日", "offset": None, "direction": None},
                "source_clauses": clause_refs(),
            },
            {
                "event_id": "anchor-only", "name": "見積の有効期間", "event_kind": "other",
                "date": None, "hard": True, "phase": "application",
                "relative": {"anchor": "採択発表日", "offset": {"value": 30, "unit": "day"}, "direction": "within_after"},
                "source_clauses": clause_refs(),
            },
        ],
        "deliverables": [
            {
                "deliverable_id": "plan", "name": "事業計画", "type": "form_input", "phase": "application",
                "produced_by": "ai_draftable", "required": True, "required_if": None,
                "format": "申請システムへ直接入力", "upload_target": "申請システムの計画欄",
                "due_event_id": "late-deadline",
                "sections": [
                    {"section_id": "second", "name": "二番目に定義した節", "kind": "prose", "max_chars": 40},
                    {"section_id": "first", "name": "一番目ではない節", "kind": "prose", "max_chars": None},
                    {"section_id": "third", "name": "まだ書いていない節", "kind": "prose", "max_chars": 100},
                ],
            },
            {
                "deliverable_id": "letter", "name": "事前確認書", "type": "attachment", "phase": "application",
                "produced_by": "external", "required": True, "required_if": None,
                "format": "PDF", "upload_target": "申請システムの添付欄",
                "due_event_id": "early-deadline", "sections": [],
            },
            {
                "deliverable_id": "optional-doc", "name": "加点の根拠資料", "type": "attachment",
                "produced_by": "human_only", "required": False, "required_if": None,
                "format": None, "upload_target": None, "due_event_id": None, "sections": [],
            },
            {
                "deliverable_id": "report", "name": "実績報告書", "type": "attachment", "phase": "post_adoption",
                "produced_by": "human_only", "required": True, "required_if": None,
                "format": "PDF", "upload_target": "申請システム", "due_event_id": "report-deadline",
                "sections": [],
            },
        ],
    }


for caps in (None, [], [{'kind': 'other'}], [{'kind': 'amount', 'amount': 10, 'applies_to': '全体', 'source_clauses': []}]):
    fixture = make_spec()
    fixture['funding'] = {'eligible_expenses': [{'category': '架空の区分', 'caps': caps}]}
    rendered = build_submission.render(fixture, {}, 'digest', [])
    note = '- 架空の区分\n  - この区分だけの上限は読み取ったデータにありません。全体の上限と条件は公募要領で確かめてください。'
    expect('expense without displayable caps has explanation: ' + str(caps),
           (note in rendered) == (not caps or caps[0]['kind'] == 'other'))

with tempfile.TemporaryDirectory(prefix="planner submission fixture ") as directory:
    root = pathlib.Path(directory)
    spec_path = root / "spec.json"
    spec_path.write_text(json.dumps(make_spec(), ensure_ascii=False), encoding="utf-8")
    drafts = root / "drafts"
    drafts.mkdir()
    # File names sort opposite to the spec order on purpose.
    (drafts / "a-first.md").write_text(
        draft("plan", "first", "一番目の本文。数値は [要確認] のまま、もう一つ [要確認] がある。"), encoding="utf-8")
    (drafts / "b-second.md").write_text(
        draft("plan", "second", "  二番目の本文。  \n\n段落を分けた。"), encoding="utf-8")
    output = root / "out dir" / "submission.md"

    result = run(spec_path, drafts, "--output", output)
    expect("ok exit code", result.returncode == 0, result.stdout)
    expect("ok message names the output", "OK: submission summary written" in result.stdout, result.stdout)
    expect("output file created with parent", output.is_file())
    text = output.read_text(encoding="utf-8") if output.is_file() else ""

    expect("title uses spec name", "# 提出用まとめ: 架空の設備導入支援事業" in text)
    expect("round shown", "架空第1回" in text)
    expect("applicant responsibility note", "申請者本人が行ってください" in text)
    second = text.find("#### 二番目に定義した節")
    first = text.find("#### 一番目ではない節")
    third = text.find("#### まだ書いていない節")
    expect("sections follow spec order, not file order", -1 < second < first < third, str((second, first, third)))
    expect("body copied without the non-body region", "二番目の本文。" in text and "ここは本文に含めない" not in text)
    expect("missing draft labelled", "- 状態: 未作成（上限 100 字）" in text)
    expect("null max_chars labelled", "上限は様式で確認" in text)
    expect("need-check marker counted", "[要確認] が 2 か所残っています" in text)
    expect("deliverable target shown", "- 提出先・入力先: 申請システムの計画欄" in text)
    expect("deliverable due resolved from schedule", "- 期限: 2030-03-31 17:00（申請締切）" in text)

    # check-drafts prints counts only on violations, so compare with its engine directly.
    sys.path.insert(0, str(source / "tools/lib"))
    import check_drafts  # noqa: E402
    expected_second = check_drafts.count_body_chars("  二番目の本文。  \n\n段落を分けた。")
    expect("char count equals check_drafts", "- 字数: {} 字（上限 40 字）".format(expected_second) in text, text)
    digest, digest_errors = check_drafts.draft_bodies_sha256(drafts)
    expect("draft hash equals check_drafts", not digest_errors and digest in text)

    others = text[text.find("## 2. 本文以外に用意するもの"):text.find("## 3. 期限")]
    expect("external deliverable listed as required", "- [ ] 事前確認書（必須）" in others, others)
    expect("optional deliverable listed as conditional", "- [ ] 加点の根拠資料（該当する場合）" in others, others)
    expect("missing fields point to official source", "spec に記載なし。公式資料で確認" in others, others)
    expect("post-adoption deliverable excluded", "実績報告書" not in text)

    deadlines = text[text.find("## 3. 期限"):]
    early = deadlines.find("2030-03-10: 事前確認書の依頼締切")
    late = deadlines.find("2030-03-31 17:00: 申請締切")
    expect("hard deadlines sorted by date", -1 < early < late, deadlines)
    expect("soft event excluded", "説明会" not in deadlines)
    expect("post-adoption deadline excluded", "実績報告期限" not in deadlines)
    undated = deadlines.find("日付は公式資料で確認: 補助事業の実施期間")
    ends_only = deadlines.find("〜2031-06-30: 事業の実施期限")
    anchor_only = deadlines.find("採択発表日から30日以内: 見積の有効期間")
    expect("undated hard event kept with a pointer", undated > -1, deadlines)
    expect("ends_at shown when date is null", ends_only > -1, deadlines)
    expect("relative anchor shown when no date or ends_at", anchor_only > -1, deadlines)
    expect("undated events follow dated ones in spec order", late < undated < ends_only < anchor_only, deadlines)

    stdout_result = run(spec_path, drafts, "--output", "-")
    expect("stdout mode exit code", stdout_result.returncode == 0)
    expect("stdout mode prints the document", stdout_result.stdout.startswith("# 提出用まとめ:"), stdout_result.stdout[:80])

    conditional = make_spec()
    for item in [conditional["deliverables"][0], conditional["deliverables"][1], conditional["deliverables"][0]["sections"][2]]:
        item.update(required=True, required_if={"scope": "application", "key": "equipment", "op": "eq", "value": True})
    conditional["deliverables"][1].update(condition="対象設備を導入する場合", due_event_id="anchor-only")
    fallback = "条件付き: spec の `required_if` を参照。該当するかは `input/deliverables.md` で確認"
    for offset, direction, label in [(7, "before", "採択発表日の7日前まで"), (30, "within_after", "採択発表日から30日以内"), (None, None, "採択発表日起点"), (0, "before", "採択発表日の0日前まで"), (7, None, "採択発表日起点・7日（前後は要確認）")]:
        conditional["schedule"][-1]["relative"].update(offset=None if offset is None else {"value": offset, "unit": "day"}, direction=direction)
        spec_path.write_text(json.dumps(conditional, ensure_ascii=False), encoding="utf-8")
        result = run(spec_path, drafts, "--output", "-")
        expect("conditional required overrides true", result.returncode == 0 and "事前確認書（条件付き: 対象設備を導入する場合）" in result.stdout and "事前確認書（必須）" not in result.stdout)
        expect("conditional body and section fallback", result.stdout.count(fallback) == 2)
        expect("relative deadline in both locations", "- 期限: " + label + "（見積の有効期間）" in result.stdout and "- " + label + ": 見積の有効期間" in result.stdout)
    spec_path.write_text(json.dumps(make_spec(), ensure_ascii=False), encoding="utf-8")

    (drafts / "c-extra.md").write_text(draft("plan", "unknown-section", "対象外の本文。"), encoding="utf-8")
    extra = run(spec_path, drafts, "--output", root / "extra.md", stderr=subprocess.PIPE)
    expect("unknown section draft is a warning", extra.returncode == 0 and "WARN: draft not listed in spec sections" in extra.stdout, extra.stdout)
    expect("unknown section body not copied", "対象外の本文" not in (root / "extra.md").read_text(encoding="utf-8"))
    warning_lines = [line for line in extra.stdout.splitlines() if line.startswith("WARN:")]
    expect("file mode keeps warning and success on stdout", bool(warning_lines) and not extra.stderr
           and extra.stdout.splitlines()[-1] == "OK: submission summary written: {}".format(root / "extra.md"), extra)
    extra_stdout = run(spec_path, drafts, "--output", "-", stderr=subprocess.PIPE)
    expect("stdout mode separates warnings from Markdown", extra_stdout.returncode == 0
           and extra_stdout.stdout.startswith("# ")
           and not any(line.startswith("WARN:") for line in extra_stdout.stdout.splitlines())
           and extra_stdout.stderr.splitlines() == warning_lines, extra_stdout)
    (drafts / "c-extra.md").unlink()

    (drafts / "d-dup.md").write_text(draft("plan", "first", "重複した本文。"), encoding="utf-8")
    dup = run(spec_path, drafts, "--output", root / "dup.md")
    expect("duplicate draft fails", dup.returncode != 0 and "FAIL:" in dup.stdout and "duplicate draft" in dup.stdout, dup.stdout)
    expect("no output on failure", not (root / "dup.md").exists())
    (drafts / "d-dup.md").unlink()

    (drafts / "e-broken.md").write_text("本文だけで frontmatter が無い。\n", encoding="utf-8")
    broken = run(spec_path, drafts, "--output", root / "broken.md")
    expect("broken draft fails", broken.returncode != 0 and "FAIL:" in broken.stdout, broken.stdout)
    (drafts / "e-broken.md").unlink()

    missing_spec = run(root / "nope.json", drafts, "--output", root / "nope.md")
    expect("missing spec fails", missing_spec.returncode != 0 and "FAIL: spec not found" in missing_spec.stdout, missing_spec.stdout)
    missing_dir = run(spec_path, root / "no-drafts", "--output", root / "nodir.md")
    expect("missing drafts_dir fails", missing_dir.returncode != 0 and "FAIL: drafts_dir not found" in missing_dir.stdout, missing_dir.stdout)

    empty = root / "empty"
    empty.mkdir()
    none = run(spec_path, empty, "--output", root / "none.md")
    expect("zero drafts still succeeds", none.returncode == 0, none.stdout)
    expect("zero drafts labels every section", (root / "none.md").read_text(encoding="utf-8").count("- 状態: 未作成") == 3)

# Exercise both output modes and compare the independent counting paths.
for label, bodies, total, section_count in [
    ("multiple sections", ["[要確認] と [要確認]", "[要確認]", "確認済み。"], 3, 2),
    ("zero markers", ["確認済み。", "要確認という語だけ。"], 0, 0),
    ("single section", ["[要確認] と [要確認]"], 2, 1),
]:
    with tempfile.TemporaryDirectory(prefix="planner marker total ") as directory:
        root = pathlib.Path(directory)
        spec_path = root / "spec.json"
        spec_path.write_text(json.dumps(make_spec(), ensure_ascii=False), encoding="utf-8")
        drafts = root / "drafts"
        drafts.mkdir()
        section_ids = [section["section_id"] for section in make_spec()["deliverables"][0]["sections"]]
        for section_id, body in zip(section_ids, bodies):
            content = draft("plan", section_id, body) + "メモだけの [要確認]。\n"
            (drafts / (section_id + ".md")).write_text(content, encoding="utf-8")
        errors, _, counters = check_drafts.check_drafts(spec_path, drafts)
        expect(label + " checker succeeds", not errors, errors)
        expect(label + " checker body total", counters["body_need_check"] == total, counters)
        expected = "本文に残っている [要確認]: " + (
            "合計 {} か所（{} セクション）".format(total, section_count) if total else "0 か所")
        output = root / "submission.md"
        result = run(spec_path, drafts, "--output", output, stderr=subprocess.PIPE)
        expect(label + " file output succeeds", result.returncode == 0, result.stdout)
        document = output.read_text(encoding="utf-8") if output.is_file() else ""
        expect(label + " exact total line once", document.splitlines().count(expected) == 1, document)
        expect(label + " total precedes section details",
               "## 1. 入力・貼り付けする本文\n\n" + expected + "\n" in document)
        stdout_result = run(spec_path, drafts, "--output", "-", stderr=subprocess.PIPE)
        expect(label + " stdout matches file", stdout_result.returncode == 0
               and stdout_result.stdout == document and not stdout_result.stderr, stdout_result)

sample = run(
    source / "examples/worked-example/pack/spec.sample.json",
    source / "examples/worked-example/drafts-sample",
    "--output", "-",
)
expect("worked example renders", sample.returncode == 0 and "#### 現状課題" in sample.stdout, sample.stdout[:200])

engine = (source / "tools/lib/build_submission.py").read_text(encoding="utf-8")
for token in ("持続化", "jizokuka", "様式2", "様式3", "様式4"):
    expect("engine has no scheme-specific literal: " + token, token not in engine)

print("build-submission tests: {} passed, {} failed".format(passed, failed))
sys.exit(1 if failed else 0)
PY
