#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"${PLANNER_PYTHON:-python3}" -B - <<'PY'
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
from urllib.parse import unquote

root = pathlib.Path.cwd()
review_path = pathlib.Path("docs/design/pack-contribution-review.md")
documents = {
    path: pathlib.Path(path).read_text(encoding="utf-8")
    for path in ("CONTRIBUTING.md", "ADOPTERS.md", review_path.as_posix())
}
guide = documents["CONTRIBUTING.md"].split("## 補助金パックの貢献\n", 1)[1]
review = documents[review_path.as_posix()]
adopters = documents["ADOPTERS.md"]


def require(condition, label):
    if not condition:
        raise SystemExit("FAIL: " + label)


def contains(text, phrases, label):
    for phrase in phrases:
        require(phrase in text, label + ": missing " + phrase)


for text in (guide, review):
    contains(text, ("check-spec.sh", "--gate confirm", "check-pack.sh", "DCO",
                    "公式原本突合", "provider confirmation", "core-manifest.json",
                    "tools/test-*.sh", "[要確認]", "[clause: <clause_id>]", "source:"),
             "PC-procedure")
contains(review, ("spec・confirmation・`pack.json`・`notes/`", "status=confirmed",
                  "spec_sha256", "built_by=provider", "derived_from_spec_sha256",
                  "registry.origin=bundled", "items[].confirmed_at"), "PC-procedure")
require(review.index("--gate confirm") < review.index("status=confirmed")
        < review.index("spec_sha256`・`spec_version"), "PC-procedure: promotion order")
print("PASS: PC-procedure")

header = "| 公式 URL | 資料版 | SHA または再確認日時 | ページ・節 | field_path | 原本値 | spec 値 | 確認者 | 確認日 | 判定 |"
require(header in review.splitlines(), "PC-evidence-fields: evidence table header")
contains(review, ("1行は1つの `field_path`", "全必須項目", "source_clauses",
                  "作成者・再照合担当", "それぞれの確認日"), "PC-evidence-fields")
print("PASS: PC-evidence-fields")

for text in (guide, review):
    contains(text, ("作成者と別のメンテナ", "再照合", "疑義", "保留", "提供側",
                    "confirmed_by=provider"), "PC-review-roles")
contains(review, ("未解決のまま confirmed 化しない", "自己申告や AI の出力だけで",
                  "受入可・修正依頼・保留", "merge・公開は既存の承認手順"), "PC-review-roles")
print("PASS: PC-review-roles")

issue_url = "https://github.com/saita-kun/saita-kun-planner/issues/new?template=adopter-entry.yml"
for text in (guide, review, adopters):
    contains(text, ("本人同意", "公開表示名・パック ID・canonical PR URL", "自動転記しません"
                    if text == adopters or text == guide else "自動転記しない"),
             "PC-credit-separation")
for text in (guide, review):
    contains(text, ("`pack.json` にクレジット用のキーを追加しません"
                    if text == guide else "`pack.json` にクレジット用のキーを追加しない",
                    "DCO sign-off", "掲載", "同意"), "PC-credit-separation")
contains(adopters, (issue_url, "直接 Pull Request は受け付けていません",
                    "掲載の削除依頼も同じ Issue フォーム", "公開履歴・通知・複製"),
         "PC-credit-separation")
require(issue_url in documents["CONTRIBUTING.md"] and issue_url in review,
        "PC-credit-separation: canonical issue route")
print("PASS: PC-credit-separation")

require(review.startswith("---\naudience: ai\n---\n"), "PC-references: audience")
manifest = json.loads(pathlib.Path("core-manifest.json").read_text(encoding="utf-8"))
for path in (review_path.as_posix(), "tools/test-pack-contribution-docs.sh"):
    require(manifest["core_paths"].count(path) == 1, "PC-references: manifest " + path)
for path, text in documents.items():
    for target in re.findall(r"\]\(([^)]+)\)", text):
        if target.startswith(("https://", "http://", "mailto:")):
            continue
        relative, _, anchor = unquote(target).partition("#")
        destination = pathlib.Path(path).parent / relative if relative else pathlib.Path(path)
        require(destination.is_file(), "PC-references: " + path + " -> " + target)
        if anchor:
            headings = re.findall(r"^#+ (.+)$", destination.read_text(encoding="utf-8"), re.M)
            slugs = [re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-") for heading in headings]
            require(anchor in slugs, "PC-references: anchor " + target)
print("PASS: PC-references")

# Execute the actual documented blocks, with a draft gate before promotion.
blocks = re.findall(r"^```bash\n(.*?)^```", review, re.M | re.S)
require(len(blocks) == 2, "PC-example-commands: expected two command blocks")
require(blocks[0].strip() == 'bash tools/check-spec.sh "$SPEC_PATH" --gate confirm',
        "PC-example-commands: draft command")
require(blocks[1].splitlines() == ['bash tools/check-spec.sh "$SPEC_PATH"',
                                  'bash tools/check-pack.sh "$PACK_DIR"'],
        "PC-example-commands: final commands")


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run_block(block, environment):
    result = subprocess.run(["bash", "-euo", "pipefail", "-c", block], cwd=str(root),
                            env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            universal_newlines=True)
    require(result.returncode == 0, "PC-example-commands: " + result.stdout)
    require("FAIL:" not in result.stdout, "PC-example-commands: " + result.stdout)
    return result.stdout


with tempfile.TemporaryDirectory(prefix="pack contribution ") as temporary:
    pack_dir = pathlib.Path(temporary) / "green"
    shutil.copytree(root / "tools/fixtures/packs/green", pack_dir)
    spec_path = pack_dir / "pack-fixture.json"
    confirmation_path = pack_dir / "pack-fixture.confirmation.json"
    original_spec = spec_path.read_bytes()
    confirmation = json.loads(confirmation_path.read_text(encoding="utf-8"))
    confirmation["spec_path"] = spec_path.as_posix()
    environment = dict(os.environ, PACK_DIR=str(pack_dir), SPEC_PATH=str(spec_path))
    draft = json.loads(original_spec.decode("utf-8"))
    draft["status"] = "draft"
    write_json(spec_path, draft)
    draft_confirmation = dict(confirmation, spec_sha256=None, confirmed_by=None, confirmed_at=None)
    write_json(confirmation_path, draft_confirmation)
    run_block(blocks[0], environment)

    # Restore the confirmed fixture; only its location and binding digest change.
    spec_path.write_bytes(original_spec)
    write_json(confirmation_path, confirmation)
    pack_path = pack_dir / "pack.json"
    pack = json.loads(pack_path.read_text(encoding="utf-8"))
    pack["confirmation"]["sha256"] = hashlib.sha256(confirmation_path.read_bytes()).hexdigest()
    write_json(pack_path, pack)
    output = run_block(blocks[1], environment)
    require("OK: pack checks passed" in output.splitlines(), "PC-example-commands: pack success")
    print("OK: pack checks passed")
print("PASS: PC-example-commands")
PY
