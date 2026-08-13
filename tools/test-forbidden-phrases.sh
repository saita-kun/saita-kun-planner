#!/bin/bash
# Table-driven regression tests for the public forbidden-phrase checker.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import importlib.util
import json
import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
module_path = root / "tools/lib/check_forbidden_phrases.py"
spec = importlib.util.spec_from_file_location("check_forbidden_phrases", module_path)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL: could not load forbidden phrase checker")
checker = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = checker
spec.loader.exec_module(checker)

passed = 0
failures = []


def check(condition, label):
    global passed
    if condition:
        passed += 1
    else:
        failures.append(label)


def load_fixture(name):
    path = root / "tools/fixtures/forbidden" / name
    document = json.loads(path.read_text(encoding="utf-8"))
    check(document.get("fixture_version") == 1, f"{name}: fixture_version")
    return document


cases = load_fixture("cases.json")
required_positive = {
    "採択されます", "採択される", "採択させます", "必ず採択",
    "絶対に通り", "確実に受かり", "通ります", "受かります",
    "保証します", "保証いたします", "採択を保証", "全自動",
    "完全自動", "自動で作成", "自動で完成", "自動で申請",
    "自動で提出", "作成代行", "代理提出", "代理申請", "代筆",
    "成功報酬",
}
actual_positive = {
    case["text"][:-1] if case["text"].endswith("。") else case["text"]
    for case in cases["positive_cases"]
}
check(actual_positive == required_positive, "positive fixture covers every AC alternative")
for case in cases["positive_cases"]:
    hits, _ = checker.find_forbidden(case["text"], f"positive/{case['id']}")
    check(bool(hits), f"positive case must fail: {case['id']}")

negation_terms = {case["term"] for case in cases["negation_cases"]}
check(negation_terms == set(checker.NEGATION_TERMS), "negation fixture matches checker constant")
for case in cases["negation_cases"]:
    has_raw_pattern = any(
        pattern.search(case["text"])
        for _, pattern in checker.JAPANESE_FORBIDDEN_PATTERNS
    )
    hits, _ = checker.find_forbidden(case["text"], f"negative/{case['term']}")
    check(case["term"] in case["text"], f"negation term appears: {case['term']}")
    check(has_raw_pattern, f"negation case contains a positive pattern: {case['term']}")
    check(not hits, f"negation case must not fail: {case['term']}")

required_boundary_patterns = {
    "japanese-stop": re.compile(r"^必ず採択されます。[^。\n]*保証[^。\n]*しません。$"),
    "newline": re.compile(r"^必ず採択されます\n[^。\n]*保証[^。\n]*しません。$"),
}
boundary_by_id = {case["id"]: case["text"] for case in cases["boundary_cases"]}
check(
    len(cases["boundary_cases"]) == len(required_boundary_patterns)
    and set(boundary_by_id) == set(required_boundary_patterns),
    "boundary fixture has the fixed case IDs",
)
for case_id, pattern in required_boundary_patterns.items():
    text = boundary_by_id.get(case_id, "")
    check(bool(pattern.fullmatch(text)), f"boundary fixture text pattern: {case_id}")
check("。" in boundary_by_id.get("japanese-stop", ""), "Japanese-stop boundary is present")
check("\n" in boundary_by_id.get("newline", ""), "newline boundary is present")
for case in cases["boundary_cases"]:
    hits, _ = checker.find_forbidden(case["text"], f"boundary/{case['id']}")
    check(bool(hits), f"boundary case must fail: {case['id']}")

required_english = {
    "guaranteed approval", "guarantee of adoption", "we file on your behalf",
    "we submit on your behalf", "on your behalf", "fully automated filing",
    "fully automated submission", "automatically files", "automatically submits",
    "100% success", "100% approval",
}
actual_english = {case["text"] for case in cases["english_positive_cases"]}
check(actual_english == required_english, "English fixture covers every AC alternative")
for case in cases["english_positive_cases"]:
    hits, _ = checker.find_forbidden(case["text"], f"english/{case['id']}")
    check(any(hit.language == "en" for hit in hits), f"English case must fail: {case['id']}")

legal = load_fixture("legal-negative.json")
check(bool(legal.get("extraction_command")), "legal fixture records extraction command")
extraction = re.compile(legal["extraction_regex"])
actual_legal = set()
for source in legal["extraction_sources"]:
    for line in (root / source).read_text(encoding="utf-8").splitlines():
        if extraction.search(line):
            actual_legal.add((source, line))
fixture_legal = {(entry["path"], entry["text"]) for entry in legal["entries"]}
check(actual_legal == fixture_legal, "legal fixture is a complete mechanical extraction")

allowlist = checker.load_allowlist(root / checker.DEFAULT_ALLOWLIST)
allowed_keys = {(entry.path, entry.sentence) for entry in allowlist}
for entry in legal["entries"]:
    hits, _ = checker.find_forbidden(entry["text"], entry["path"], allowed_keys)
    check(not hits, f"legal negative fixture must not fail: {entry['path']}")

with tempfile.TemporaryDirectory(prefix="forbidden-allowlist-fields.") as temp_dir:
    allowlist_path = pathlib.Path(temp_dir) / "allowlist.json"
    valid_entry = {
        "path": "README.md",
        "sentence": "必ず採択されます",
        "reason": "Reviewed legal-context exception.",
    }
    for field in ("path", "sentence", "reason"):
        invalid_entry = dict(valid_entry)
        invalid_entry[field] = None
        allowlist_path.write_text(
            json.dumps(
                {"allowlist_version": 1, "entries": [invalid_entry]},
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        try:
            checker.load_allowlist(allowlist_path)
        except ValueError:
            check(True, f"allowlist rejects null {field}")
        else:
            check(False, f"allowlist rejects null {field}")

adversarial = load_fixture("adversarial.json")
required_adversarial_patterns = {
    "unrelated-denial-after-stop": re.compile(
        r"^必ず採択されます。ただし保証はしません。$"
    ),
    "unrelated-denial-after-newline": re.compile(
        r"^作成代行を提供します。\n提出判断は行いません。$"
    ),
    "automatic-claim-before-denial": re.compile(
        r"^完全自動で申請します。代理提出はしません。$"
    ),
    "guarantee-before-unrelated-prohibition": re.compile(
        r"^採択を保証。数値の推測は禁止。$"
    ),
}
adversarial_by_id = {case["id"]: case["text"] for case in adversarial["cases"]}
check(
    len(adversarial["cases"]) == len(required_adversarial_patterns)
    and set(adversarial_by_id) == set(required_adversarial_patterns),
    "adversarial fixture has the fixed case IDs",
)
for case_id, pattern in required_adversarial_patterns.items():
    text = adversarial_by_id.get(case_id, "")
    check(bool(pattern.fullmatch(text)), f"adversarial fixture text pattern: {case_id}")
    sentences = [sentence for _, sentence in checker.iter_sentences(text)]
    first_is_positive = bool(sentences) and any(
        raw_pattern.search(sentences[0])
        for _, raw_pattern in checker.JAPANESE_FORBIDDEN_PATTERNS
    )
    later_has_denial = any(
        term in sentence
        for sentence in sentences[1:]
        for term in checker.NEGATION_TERMS
    )
    check(first_is_positive, f"adversarial affirmative sentence exists: {case_id}")
    check(later_has_denial, f"adversarial unrelated denial exists: {case_id}")
for case in adversarial["cases"]:
    hits, _ = checker.find_forbidden(case["text"], f"adversarial/{case['id']}")
    check(bool(hits), f"adversarial case must fail: {case['id']}")

normalized_exclusions = checker.parse_export_excluded_paths(
    "# fixture\n.ralph/\ndocs/strategy/\n",
    source="valid-exclusions",
)
check(
    normalized_exclusions == (".ralph", "docs/strategy"),
    "export exclusions normalize one trailing slash",
)
invalid_exclusion_lists = {
    "leading-space": " docs/strategy/\n",
    "trailing-space": "docs/strategy/ \n",
    "whitespace-only-line": "docs/strategy/\n   \ntools/release/\n",
    "entry-crlf": "docs/strategy/\r\n",
    "comment-crlf": "# fixture\r\ndocs/strategy/\n",
}
for case_id, text in invalid_exclusion_lists.items():
    try:
        checker.parse_export_excluded_paths(text, source=f"invalid/{case_id}")
    except ValueError:
        check(True, f"export exclusion rejects {case_id}")
    else:
        check(False, f"export exclusion rejects {case_id}")

with tempfile.TemporaryDirectory(prefix="forbidden-phrase-test.") as temp_dir:
    temp = pathlib.Path(temp_dir)
    positive_path = temp / "positive.txt"
    negative_path = temp / "negative.txt"
    positive_path.write_text("必ず採択されます。", encoding="utf-8")
    negative_path.write_text("採択を保証しません。", encoding="utf-8")
    positive_run = subprocess.run(
        [sys.executable, str(module_path), "--no-allowlist", str(positive_path)],
        capture_output=True,
        text=True,
    )
    negative_run = subprocess.run(
        [sys.executable, str(module_path), "--no-allowlist", str(negative_path)],
        capture_output=True,
        text=True,
    )
    check(positive_run.returncode == 1, "CLI returns nonzero for a forbidden phrase")
    check(negative_run.returncode == 0, "CLI returns zero for a negated phrase")

with tempfile.TemporaryDirectory(prefix="forbidden-repository-paths.") as temp_dir:
    repo = pathlib.Path(temp_dir) / "repo"
    (repo / "tools/lib").mkdir(parents=True)
    (repo / "docs").mkdir()
    (repo / ".github/ISSUE_TEMPLATE").mkdir(parents=True)
    (repo / "examples/worked-example").mkdir(parents=True)
    (repo / "knowledge/lessons").mkdir(parents=True)
    (repo / "input").mkdir()
    (repo / ".claude/commands").mkdir(parents=True)
    (repo / ".ralph").mkdir()
    (repo / "tools/lib/export-excluded-paths.txt").write_text(
        ".ralph/\n", encoding="utf-8"
    )
    (repo / "core-manifest.json").write_text(
        json.dumps(
            {
                "manifest_version": 1,
                "core_paths": [
                    "README.md",
                    "README.en.md",
                    "docs/ai-agent-guide.md",
                ],
            }
        )
        + "\n",
        encoding="utf-8",
    )
    (repo / ".gitignore").write_text("ignored.md\n", encoding="utf-8")
    (repo / "README.md").write_text("tracked customer text\n", encoding="utf-8")
    (repo / "README.en.md").write_text("guaranteed approval\n", encoding="utf-8")
    (repo / "docs/ai-agent-guide.md").write_text(
        "必ず採択されます。\n", encoding="utf-8"
    )
    (repo / "ignored.md").write_text("guaranteed approval\n", encoding="utf-8")
    (repo / "customer-note.md").write_text(
        "必ず採択されます。\n", encoding="utf-8"
    )
    (repo / "untracked-note.md").write_text(
        "必ず採択されます。\n", encoding="utf-8"
    )
    (repo / ".github/ISSUE_TEMPLATE/bug.md").write_text(
        "必ず採択されます。\n", encoding="utf-8"
    )
    (repo / "examples/worked-example/sample.md").write_text(
        "guaranteed approval\n", encoding="utf-8"
    )
    (repo / "knowledge/README.md").write_text(
        "必ず採択されます。\n", encoding="utf-8"
    )
    (repo / "knowledge/lessons/next-review.md").write_text(
        "次回は採択されるために、今回の反省を残す。\n", encoding="utf-8"
    )
    (repo / "input/customer-notes.md").write_text(
        "必ず採択されます。\n", encoding="utf-8"
    )
    (repo / ".claude/commands/my-customer.md").write_text(
        "必ず採択されます。\n", encoding="utf-8"
    )
    (repo / ".ralph/internal.md").write_text(
        "必ず採択されます。\n", encoding="utf-8"
    )
    subprocess.run(["git", "init", "--quiet", str(repo)], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "add",
            ".gitignore",
            "README.md",
            "core-manifest.json",
            "customer-note.md",
            ".github/ISSUE_TEMPLATE/bug.md",
            "examples/worked-example/sample.md",
            "knowledge/README.md",
            "knowledge/lessons/next-review.md",
            "input/customer-notes.md",
            ".claude/commands/my-customer.md",
            ".ralph/internal.md",
            "tools/lib/export-excluded-paths.txt",
        ],
        check=True,
    )
    repository_paths = set(checker.repository_text_paths(repo))
    check("README.md" in repository_paths, "repository scan includes tracked customer text")
    check("README.en.md" in repository_paths, "repository scan includes untracked English README")
    check(
        "docs/ai-agent-guide.md" in repository_paths,
        "repository scan includes untracked AI guide",
    )
    check("ignored.md" not in repository_paths, "repository scan honors standard ignores")
    check("customer-note.md" in repository_paths, "repository scan includes tracked text outside manifest")
    check("untracked-note.md" in repository_paths, "repository scan includes untracked non-ignored text outside manifest")
    check(
        ".github/ISSUE_TEMPLATE/bug.md" in repository_paths,
        "repository scan includes tracked issue templates outside manifest",
    )
    check(
        "examples/worked-example/sample.md" in repository_paths,
        "repository scan includes tracked examples outside manifest",
    )
    check(
        "knowledge/README.md" in repository_paths,
        "repository scan includes tracked knowledge README",
    )
    check(
        "knowledge/lessons/next-review.md" not in repository_paths,
        "repository scan excludes generated knowledge lessons",
    )
    check(
        "input/customer-notes.md" not in repository_paths,
        "repository scan excludes customer input",
    )
    check(
        ".claude/commands/my-customer.md" in repository_paths,
        "repository scan includes tracked my-* commands",
    )
    check(
        ".ralph/internal.md" not in repository_paths,
        "repository scan excludes shared export-excluded paths",
    )
    repository_hits, _ = checker.scan_repository(repo, ())
    hit_paths = {hit.path for hit in repository_hits}
    check("README.en.md" in hit_paths, "repository scan checks untracked English README")
    check(
        "docs/ai-agent-guide.md" in hit_paths,
        "repository scan checks untracked AI guide",
    )
    check("customer-note.md" in hit_paths, "repository scan checks tracked text outside manifest")
    check("untracked-note.md" in hit_paths, "repository scan checks untracked text outside manifest")
    check(
        ".github/ISSUE_TEMPLATE/bug.md" in hit_paths,
        "forbidden issue-template claim fails the repository scan",
    )
    check(
        "examples/worked-example/sample.md" in hit_paths,
        "forbidden example claim fails the repository scan",
    )
    check(
        "knowledge/README.md" in hit_paths,
        "forbidden knowledge README claim fails the repository scan",
    )
    check(
        ".claude/commands/my-customer.md" in hit_paths,
        "repository scan checks tracked my-* commands",
    )
    check("ignored.md" not in hit_paths, "repository scan does not check ignored files")
    check(
        "knowledge/lessons/next-review.md" not in hit_paths,
        "generated knowledge prose does not fail the public-core scan",
    )
    check(
        not hit_paths.intersection(
            {"input/customer-notes.md", "knowledge/lessons/next-review.md"}
        ),
        "customer growth-layer text does not fail the repository scan",
    )
    check(
        ".ralph/internal.md" not in hit_paths,
        "export-excluded text does not fail the repository scan",
    )
    repository_run = subprocess.run(
        [
            sys.executable,
            str(module_path),
            "--repo-root",
            str(repo),
            "--no-allowlist",
        ],
        capture_output=True,
        text=True,
    )
    check(
        repository_run.returncode == 1,
        "CLI fails for forbidden tracked files outside the manifest",
    )
    check(
        "FORBIDDEN: .github/ISSUE_TEMPLATE/bug.md" in repository_run.stdout,
        "CLI reports the forbidden issue-template claim",
    )
    check(
        "FORBIDDEN: examples/worked-example/sample.md" in repository_run.stdout,
        "CLI reports the forbidden example claim",
    )
    check(
        "FORBIDDEN: knowledge/README.md" in repository_run.stdout,
        "CLI reports the forbidden knowledge README claim",
    )

for failure in failures:
    print(f"FAIL: {failure}")
print(f"=== test-forbidden-phrases: {passed} pass / {len(failures)} fail ===")
raise SystemExit(1 if failures else 0)
PY
