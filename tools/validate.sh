#!/bin/bash
# tools/validate.sh — structural completeness gate for saita-kun-planner.
#
# This is the build-time contract checker (the Ralph harness gate). It does NOT
# judge prose quality — only that the deliverable's structure is complete and
# self-consistent: required files exist, slash commands are well-formed, the
# manual references every command, templates referenced by commands exist, the
# 行政書士法 guardrail is present where required, and there are no broken
# internal links or leftover placeholders in shipped files.
#
# Each wave EXTENDS this with its own assertions. Exit 0 = all green.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
FAILED=()

ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); FAILED+=("$1"); echo "FAIL: $1"; }

# check_file <path> [<min_bytes>] — file exists and is at least min_bytes (default 1)
check_file() {
  local f="$1" min="${2:-1}"
  if [ ! -f "$f" ]; then bad "missing file: $f"; return 1; fi
  local sz; sz=$(wc -c < "$f" | tr -d ' ')
  if [ "$sz" -lt "$min" ]; then bad "file too small (<${min}B): $f"; return 1; fi
  ok; return 0
}

# check_contains <path> <substring> <label>
check_contains() {
  local f="$1" needle="$2" label="$3"
  if [ ! -f "$f" ]; then bad "contains-check on missing file: $f ($label)"; return 1; fi
  if ! grep -qF -- "$needle" "$f"; then bad "$f missing expected content: $label"; return 1; fi
  ok; return 0
}

# check_in_order <path> <label> <substring>... — substrings appear in the given order
check_in_order() {
  local f="$1" label="$2"
  shift 2
  if [ ! -f "$f" ]; then bad "order-check on missing file: $f ($label)"; return 1; fi
  if python3 - "$f" "$@" <<'PY' >/dev/null 2>&1; then
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
needles = sys.argv[2:]
text = path.read_text(encoding="utf-8")
pos = 0
for needle in needles:
    found = text.find(needle, pos)
    if found < 0:
        raise SystemExit(1)
    pos = found + len(needle)
PY
    ok
    return 0
  fi
  bad "$f order mismatch: $label"
  return 1
}

# check_json <path> — JSON file parses with python3 stdlib
check_json() {
  local f="$1"
  if [ ! -f "$f" ]; then bad "json-check on missing file: $f"; return 1; fi
  if ! python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$f" >/dev/null 2>&1; then
    bad "invalid JSON: $f"; return 1
  fi
  ok; return 0
}

# check_spec_confirmation_binding <spec> <confirmation> — confirmation pins spec bytes
check_spec_confirmation_binding() {
  local spec="$1" confirmation="$2"
  if [ ! -f "$spec" ] || [ ! -f "$confirmation" ]; then
    bad "sha binding check on missing file: $spec / $confirmation"; return 1
  fi
  if ! python3 -c 'import hashlib, json, sys; spec, confirmation = sys.argv[1:3]; actual = hashlib.sha256(open(spec, "rb").read()).hexdigest(); expected = json.load(open(confirmation, encoding="utf-8")).get("spec_sha256"); raise SystemExit(0 if expected == actual else 1)' "$spec" "$confirmation" >/dev/null 2>&1; then
    bad "confirmation spec_sha256 mismatch: $confirmation -> $spec"; return 1
  fi
  ok; return 0
}

# no_placeholder <path> — shipped files must not contain TODO/FIXME/XXX/lorem
no_placeholder() {
  local f="$1"
  [ -f "$f" ] || return 0
  if grep -qiE 'TODO|FIXME|\bXXX\b|\bT''BD\b|lorem ipsum|<placeholder>' "$f"; then
    bad "placeholder marker left in shipped file: $f"; return 1
  fi
  ok; return 0
}

# check_relative_links <path> — every ](relative/path) target must exist
check_relative_links() {
  local f="$1"
  [ -f "$f" ] || return 0
  local missing=0 target
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    case "$target" in http*|\#*|mailto:*) continue ;; esac
    target="${target%%#*}"
    [ -n "$target" ] || continue
    if [ ! -e "$ROOT/$target" ] && [ ! -e "$(dirname "$f")/$target" ]; then
      bad "broken link in $f -> $target"; missing=1
    fi
  done < <(grep -oE '\]\(([^)]+)\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
  [ "$missing" = "0" ] && ok
}

# ---- baseline structure (extended by later waves) --------------------------
check_file "README.md" 1
check_file "CLAUDE.md" 1
check_file ".gitignore" 1
[ -d ".claude/commands" ] && ok || bad "missing dir: .claude/commands"
[ -d "docs" ] && ok || bad "missing dir: docs"
[ -d "templates" ] && ok || bad "missing dir: templates"

# ---- WAVE EXTENSION POINT --------------------------------------------------
# Later waves append their assertions below this line.

# Wave: a15-checker-false-negatives
check_contains "tools/lib/check_drafts.py" "duplicate draft for" "check-drafts reports duplicate draft keys"
check_contains "tools/test-check-drafts.sh" "drafts-duplicate" "check-drafts test covers duplicate drafts"
for fixture_file in \
  tools/fixtures/drafts/drafts-duplicate/section-1.md \
  tools/fixtures/drafts/drafts-duplicate/section-1-duplicate.md; do
  check_file "$fixture_file" 1
  no_placeholder "$fixture_file"
done

duplicate_output=$(bash tools/check-drafts.sh tools/fixtures/spec/good-spec.json tools/fixtures/drafts/drafts-duplicate 2>&1)
duplicate_status=$?
if [ "$duplicate_status" -ne 0 ] &&
   printf '%s\n' "$duplicate_output" | grep -qF -- "FAIL: duplicate draft for deliverable-1/section-1" &&
   printf '%s\n' "$duplicate_output" | grep -qF -- "tools/fixtures/drafts/drafts-duplicate/section-1.md" &&
   printf '%s\n' "$duplicate_output" | grep -qF -- "tools/fixtures/drafts/drafts-duplicate/section-1-duplicate.md"; then
  ok
else
  bad "duplicate draft fixture must fail with both paths"
fi

check_contains "tools/lib/check_spec.py" "check_application_deadline_freshness" "check-spec checks application deadline freshness"
check_contains "tools/test-check-spec.sh" "stale-deadline" "check-spec test covers stale deadline warning"
for json_file in \
  tools/fixtures/spec/stale-deadline.json \
  tools/fixtures/spec/stale-deadline.confirmation.json; do
  check_file "$json_file" 1
  check_json "$json_file"
  no_placeholder "$json_file"
done

# Fixed --now values make deadline checks deterministic past 2026. This is a
# determinism fix, not a relaxation of the freshness assertion.
stale_deadline_output=$(
  bash tools/check-spec.sh \
    tools/fixtures/spec/stale-deadline.json \
    --now 2026-07-17T12:00:00+09:00 \
    2>&1
)
stale_deadline_status=$?
if [ "$stale_deadline_status" -eq 0 ] &&
   printf '%s\n' "$stale_deadline_output" | grep -qF -- "WARN: application deadline 2020-01-01 has passed; 公募回が更新されていないか公式サイトで確認してください"; then
  ok
else
  bad "stale deadline fixture must warn without failing"
fi

good_spec_output=$(
  bash tools/check-spec.sh \
    tools/fixtures/spec/good-spec.json \
    --now 2026-12-30T12:00:00+09:00 \
    2>&1
)
good_spec_status=$?
if [ "$good_spec_status" -eq 0 ] &&
   ! printf '%s\n' "$good_spec_output" | grep -qF -- "application deadline"; then
  ok
else
  bad "future application deadline fixture must not warn"
fi

check_contains "tools/lib/predicate.py" "comparison_category" "predicate evaluator guards eq/ne by type category"
check_contains "tools/lib/predicate.py" "not isinstance(expected, list)" "predicate evaluator treats non-list in as unknown"
check_contains "tools/test-check-spec.sh" "emp-eq-25" "predicate test covers eq type mismatch"
check_contains "tools/test-check-spec.sh" "industry-in-string" "predicate test covers in string mismatch"
for json_file in \
  tools/fixtures/spec/predicate-type-mismatch.json \
  tools/fixtures/profiles/type-mismatch-string-emp.json \
  tools/fixtures/profiles/type-mismatch-bool-flag.json; do
  check_file "$json_file" 1
  check_json "$json_file"
  no_placeholder "$json_file"
done

check_predicate_unknown() {
  local rule_id="$1" profile="$2" output
  output=$(python3 tools/lib/predicate.py tools/fixtures/spec/predicate-type-mismatch.json "$rule_id" "$profile" 2>&1)
  if [ "$output" = "unknown" ]; then
    ok
  else
    bad "predicate type mismatch must be unknown: $rule_id with $profile -> $output"
  fi
}

check_predicate_unknown "emp-eq-25" "tools/fixtures/profiles/type-mismatch-string-emp.json"
check_predicate_unknown "emp-ne-25" "tools/fixtures/profiles/type-mismatch-string-emp.json"
check_predicate_unknown "industry-in-string" "tools/fixtures/profiles/seizou-25.json"
check_predicate_unknown "flag-eq-one" "tools/fixtures/profiles/type-mismatch-bool-flag.json"

# ---- internal-only paths (strategy SSoT + planning docs + release tooling) --
# The export script, validator, and customer-text checker consume this source.
EXPORT_EXCLUDED_PATHS_FILE="tools/lib/export-excluded-paths.txt"
INTERNAL_ONLY_PATHS=()
if [ -f "$EXPORT_EXCLUDED_PATHS_FILE" ]; then
  if normalized_internal_paths="$(
    python3 tools/lib/check_forbidden_phrases.py \
      --normalize-export-exclusions "$EXPORT_EXCLUDED_PATHS_FILE"
  )"; then
    while IFS= read -r internal_path || [ -n "$internal_path" ]; do
      [ -n "$internal_path" ] && INTERNAL_ONLY_PATHS+=("$internal_path")
    done <<< "$normalized_internal_paths"
  else
    bad "invalid shared export exclusion path list: $EXPORT_EXCLUDED_PATHS_FILE"
  fi
else
  bad "missing shared export exclusion path list: $EXPORT_EXCLUDED_PATHS_FILE"
fi

# A reviewed legacy file is accepted during migration. Any other active
# export-ignore definition is rejected so the shared list remains authoritative.
if [ ! -f ".gitattributes" ]; then
  bad "missing .gitattributes"
else
  if gitattributes_mode="$(python3 - <<'PY'
import pathlib
import re
import sys

sys.path.insert(0, "tools/lib")
import check_forbidden_phrases as checker

expected = set(checker.load_export_excluded_paths(pathlib.Path(".")))
legacy_expected = {
    ".ralph",
    "docs/strategy",
    "docs/design/pivot-decision.md",
    "docs/design/wave-plans.md",
    "docs/design/harness-backlog.md",
    "docs/plans",
    "tools/release",
}
active = []
errors = []
for line_number, raw_line in enumerate(
    pathlib.Path(".gitattributes").read_text(encoding="utf-8").splitlines(),
    start=1,
):
    stripped = raw_line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    fields = stripped.split()
    attributes = fields[1:]
    export_attributes = [
        field
        for field in attributes
        if re.fullmatch(r"[-!]?export-ignore(?:=.*)?", field)
    ]
    if not export_attributes:
        continue
    if attributes != ["export-ignore"]:
        errors.append(f"line {line_number} is not a legacy export-ignore entry")
        continue
    pattern = fields[0]
    candidate = pattern[:-1] if pattern.endswith("/") else pattern
    normalized = checker._normalized_relative_path(
        candidate, source=f".gitattributes:{line_number}"
    )
    if normalized != candidate:
        errors.append(f"line {line_number} has a non-normalized pattern: {pattern!r}")
        continue
    active.append(normalized)

if active and (
    len(active) != len(set(active))
    or set(active) != legacy_expected
    or not legacy_expected.issubset(expected)
):
    errors.append(
        "active export-ignore entries are not the reviewed legacy set "
        "or are absent from the shared exclusions"
    )
if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
print("legacy" if active else "clean")
PY
  )"; then
    if [ "$gitattributes_mode" = "legacy" ]; then
      echo "WARN: legacy .gitattributes export-ignore entries accepted for migration; replace with the upstream core file (update-core --apply --force-file .gitattributes)." >&2
    fi
    ok
  else
    bad ".gitattributes contains unsupported export-ignore definitions"
  fi
fi

# is_internal_only_path <path> - true if path is (under) an internal-only entry.
is_internal_only_path() {
  local candidate="$1" entry
  for entry in "${INTERNAL_ONLY_PATHS[@]}"; do
    case "$candidate" in
      "$entry"|"$entry"/*) return 0 ;;
    esac
  done
  return 1
}

# internal mode = development worktree (.ralph sentinel word list present)
VALIDATE_INTERNAL_MODE=0
[ -f ".ralph/public-scrub-sentinel-words.txt" ] && VALIDATE_INTERNAL_MODE=1

if [ "$VALIDATE_INTERNAL_MODE" = "1" ]; then
  check_contains "docs/design/harness-backlog.md" "rule_id 不存在" "backlog tracks missing rule_id predicate ambiguity"
  check_contains "docs/design/harness-backlog.md" "max_pages の対称対応" "backlog tracks max_pages symmetric handling"
  check_contains "docs/design/harness-backlog.md" "READINESS coverage 表示拡張" "backlog tracks readiness coverage display extension"
fi

# Wave: customer-claude-md
check_contains "CLAUDE.md" "Claude Code 契約者" "Claude Code subscriber premise"
check_contains "CLAUDE.md" "補助金申請用の事業計画書" "subsidy plan purpose"
check_contains "CLAUDE.md" "/intake" "workflow includes intake"
check_contains "CLAUDE.md" "/subsidy-fit" "workflow includes subsidy-fit"
check_contains "CLAUDE.md" "/draft-section" "workflow includes draft-section"
check_contains "CLAUDE.md" "/review" "workflow includes review"
check_contains "CLAUDE.md" "/finalize" "workflow includes finalize"
check_contains "CLAUDE.md" "作成者は顧客本人" "customer author guardrail"
check_contains "CLAUDE.md" "行政書士法" "administrative scrivener law guardrail"
check_contains "CLAUDE.md" "[要確認]" "unknown facts marker"
check_contains "CLAUDE.md" "募集要項" "official requirements priority"
check_contains "CLAUDE.md" "input/" "input directory guidance"
check_contains "CLAUDE.md" "templates/" "templates directory guidance"
check_contains "CLAUDE.md" "docs/" "docs directory guidance"
no_placeholder "CLAUDE.md"

# Wave: manual-core
check_file "docs/manual.md" 3000
check_contains "docs/manual.md" "## 概要" "manual overview section"
check_contains "docs/manual.md" "## 前提" "manual premise section"
check_contains "docs/manual.md" "Claude Code 契約者" "manual Claude Code subscriber premise"
check_contains "docs/manual.md" "git clone" "manual clone prerequisite"
check_contains "docs/manual.md" "## セットアップ" "manual setup section"
check_contains "docs/manual.md" "Claude Code で開" "manual open in Claude Code setup"
check_contains "docs/manual.md" "## 使い方" "manual usage section"
check_contains "docs/manual.md" "/intake" "manual mentions intake command"
check_contains "docs/manual.md" "/subsidy-fit" "manual mentions subsidy-fit command"
check_contains "docs/manual.md" "/draft-section" "manual mentions draft-section command"
check_contains "docs/manual.md" "/review" "manual mentions review command"
check_contains "docs/manual.md" "/finalize" "manual mentions finalize command"
check_contains "docs/manual.md" "## 法務上の注意" "manual legal section"
check_contains "docs/manual.md" "作成者は顧客本人" "manual customer author guardrail"
check_contains "docs/manual.md" "[要確認]" "manual unknown facts marker"
check_contains "docs/manual.md" "申請書の作成代行者ではありません" "manual no agency guardrail"
check_contains "docs/manual.md" "## つまずいたら" "manual troubleshooting section"
check_contains "docs/manual.md" "docs/faq.md" "manual points to FAQ"
no_placeholder "docs/manual.md"

# Wave: cmd-intake
check_file ".claude/commands/intake.md" 3000
check_contains ".claude/commands/intake.md" "description:" "intake command frontmatter description"
check_contains ".claude/commands/intake.md" "input/company-profile.md" "intake output path"
check_contains ".claude/commands/intake.md" "事業概要" "intake asks business overview"
check_contains ".claude/commands/intake.md" "沿革" "intake asks company history"
check_contains ".claude/commands/intake.md" "従業員" "intake asks employee scale"
check_contains ".claude/commands/intake.md" "売上規模" "intake asks revenue scale"
check_contains ".claude/commands/intake.md" "課題" "intake asks business challenges"
check_contains ".claude/commands/intake.md" "投資計画" "intake asks investment plan"
check_contains ".claude/commands/intake.md" "選択済み補助金の spec エコー" "intake echoes selected spec instead of asking subsidy field"
check_contains ".claude/commands/intake.md" "入力は顧客の実情報" "intake customer-data guardrail"
check_contains ".claude/commands/intake.md" "AIは整理のみ" "intake AI-only-organizes guardrail"
check_contains ".claude/commands/intake.md" "公開リポジトリへコミットしない" "intake input confidentiality guardrail"
check_file "templates/intake-questionnaire.md" 2000
check_contains "templates/intake-questionnaire.md" "作成者は顧客本人" "intake template customer author guardrail"
check_contains "templates/intake-questionnaire.md" "[要確認]" "intake template unknown facts marker"
no_placeholder ".claude/commands/intake.md"
no_placeholder "templates/intake-questionnaire.md"

# Wave: cmd-subsidy-fit
check_file ".claude/commands/subsidy-fit.md" 3000
check_contains ".claude/commands/subsidy-fit.md" "description:" "subsidy-fit command frontmatter description"
check_contains ".claude/commands/subsidy-fit.md" "input/company-profile.md" "subsidy-fit input profile path"
check_contains ".claude/commands/subsidy-fit.md" "募集要項" "subsidy-fit official requirements"
check_contains ".claude/commands/subsidy-fit.md" "一次情報" "subsidy-fit official source priority"
check_contains ".claude/commands/subsidy-fit.md" "[要確認]" "subsidy-fit unknown facts marker"
check_contains ".claude/commands/subsidy-fit.md" "除外要件チェック" "subsidy-fit exclusion check"
check_contains ".claude/commands/subsidy-fit.md" "必須要件チェック" "subsidy-fit required check"
check_contains ".claude/commands/subsidy-fit.md" "加点要素" "subsidy-fit bonus elements"
check_contains ".claude/commands/subsidy-fit.md" "不足準備" "subsidy-fit preparation gaps"
check_contains ".claude/commands/subsidy-fit.md" "3段階 explainable matching" "subsidy-fit explainable matching"
check_contains ".claude/commands/subsidy-fit.md" "要件・数値は募集要項が正" "subsidy-fit requirement-number guardrail"
check_file "templates/補助金要件マッピング.md" 2500
check_contains "templates/補助金要件マッピング.md" "募集要項" "requirement mapping official requirements"
check_contains "templates/補助金要件マッピング.md" "事業計画書セクション" "requirement mapping section mapping"
check_contains "templates/補助金要件マッピング.md" "除外要件チェック" "requirement mapping exclusion check"
check_contains "templates/補助金要件マッピング.md" "必須要件チェック" "requirement mapping required check"
check_contains "templates/補助金要件マッピング.md" "加点要素" "requirement mapping bonus elements"
check_contains "templates/補助金要件マッピング.md" "[要確認]" "requirement mapping unknown facts marker"
no_placeholder ".claude/commands/subsidy-fit.md"
no_placeholder "templates/補助金要件マッピング.md"

# Wave: cmd-draft-section
check_file ".claude/commands/draft-section.md" 3000
check_contains ".claude/commands/draft-section.md" "description:" "draft-section command frontmatter description"
check_contains ".claude/commands/draft-section.md" "input/company-profile.md" "draft-section company profile input"
check_contains ".claude/commands/draft-section.md" "input/subsidy-fit.md" "draft-section subsidy-fit input"
check_contains ".claude/commands/draft-section.md" "1 セクション" "draft-section one-section scope"
check_contains ".claude/commands/draft-section.md" "叩き台" "draft-section draft output"
check_contains ".claude/commands/draft-section.md" "課題" "draft-section challenge perspective"
check_contains ".claude/commands/draft-section.md" "解決" "draft-section solution perspective"
check_contains ".claude/commands/draft-section.md" "実現性" "draft-section feasibility perspective"
check_contains ".claude/commands/draft-section.md" "効果" "draft-section impact perspective"
check_contains ".claude/commands/draft-section.md" "数値根拠" "draft-section evidence perspective"
check_contains ".claude/commands/draft-section.md" "これは叩き台、確定は顧客本人" "draft-section customer finalization guardrail"
check_contains ".claude/commands/draft-section.md" "数値根拠なき主張は [要確認]" "draft-section unknown evidence guardrail"
check_file "templates/事業計画書テンプレ.md" 3000
check_contains "templates/事業計画書テンプレ.md" "事業概要" "plan template business overview section"
check_contains "templates/事業計画書テンプレ.md" "現状課題" "plan template current challenge section"
check_contains "templates/事業計画書テンプレ.md" "事業内容" "plan template project content section"
check_contains "templates/事業計画書テンプレ.md" "実施体制" "plan template implementation structure section"
check_contains "templates/事業計画書テンプレ.md" "スケジュール" "plan template schedule section"
check_contains "templates/事業計画書テンプレ.md" "資金計画" "plan template budget section"
check_contains "templates/事業計画書テンプレ.md" "効果・KPI" "plan template KPI section"
check_contains "templates/事業計画書テンプレ.md" "数値根拠なき主張は [要確認]" "plan template evidence guardrail"
no_placeholder ".claude/commands/draft-section.md"
no_placeholder "templates/事業計画書テンプレ.md"

# Wave: cmd-review
check_file ".claude/commands/review.md" 3000
check_contains ".claude/commands/review.md" "description:" "review command frontmatter description"
check_contains ".claude/commands/review.md" "募集要項" "review official requirements check"
check_contains ".claude/commands/review.md" "文字数" "review character-count check"
check_contains ".claude/commands/review.md" "judgment_basis" "review judgment basis check"
check_contains ".claude/commands/review.md" "[要確認]" "review unknown facts marker"
check_contains ".claude/commands/review.md" "捏造" "review fabrication detection"
check_contains ".claude/commands/review.md" "誇張" "review exaggeration detection"
check_contains ".claude/commands/review.md" "行政書士法" "review legal guardrail"
check_contains ".claude/commands/review.md" "作成者は顧客本人" "review customer author guardrail"
check_contains ".claude/commands/review.md" "作成代行" "review no drafting agency"
check_contains ".claude/commands/review.md" "代理提出" "review no proxy submission"
check_contains ".claude/commands/review.md" "顧客本人が修正" "review customer fixes issues"
check_contains ".claude/commands/review.md" "黙って完成版" "review does not silently rewrite filing"
no_placeholder ".claude/commands/review.md"

# Wave: cmd-finalize
check_file ".claude/commands/finalize.md" 3000
check_contains ".claude/commands/finalize.md" "description:" "finalize command frontmatter description"
check_contains ".claude/commands/finalize.md" "体裁整え" "finalize formatting purpose"
check_contains ".claude/commands/finalize.md" "見出し" "finalize heading check"
check_contains ".claude/commands/finalize.md" "文字数" "finalize character-count check"
check_contains ".claude/commands/finalize.md" "様式" "finalize form compliance check"
check_contains ".claude/commands/finalize.md" "添付資料" "finalize attachment check"
check_contains ".claude/commands/finalize.md" "期限" "finalize deadline check"
check_contains ".claude/commands/finalize.md" "提出前チェックリスト" "finalize pre-submission checklist"
check_contains ".claude/commands/finalize.md" "募集要項の最新版を確認した" "finalize official requirements checklist item"
check_contains ".claude/commands/finalize.md" "作成者は顧客本人" "finalize customer author guardrail"
check_contains ".claude/commands/finalize.md" "提出は顧客本人の責任・判断" "finalize customer submission decision guardrail"
check_contains ".claude/commands/finalize.md" "申請代行" "finalize no filing agency"
check_contains ".claude/commands/finalize.md" "代理提出" "finalize no proxy submission"
check_contains ".claude/commands/finalize.md" "[要確認]" "finalize unknown facts marker"
no_placeholder ".claude/commands/finalize.md"

# Wave: cmd-start-and-index
check_file ".claude/commands/start.md" 3000
check_contains ".claude/commands/start.md" "description:" "start command frontmatter description"
check_contains ".claude/commands/start.md" "Claude Code 契約者" "start confirms Claude Code subscriber premise"
check_contains ".claude/commands/start.md" "docs/manual.md" "start points to manual"
check_contains ".claude/commands/start.md" "/intake" "start points to intake"
check_contains ".claude/commands/start.md" "/subsidy-fit" "start points to subsidy-fit"
check_contains ".claude/commands/start.md" "/draft-section" "start points to draft-section"
check_contains ".claude/commands/start.md" "/review" "start points to review"
check_contains ".claude/commands/start.md" "/finalize" "start points to finalize"
check_contains ".claude/commands/start.md" "作成者は顧客本人" "start customer author guardrail"
check_contains ".claude/commands/start.md" "行政書士法" "start administrative scrivener law guardrail"
check_contains ".claude/commands/start.md" "[要確認]" "start unknown facts marker"

for cmd in start select-subsidy ingest-guidelines confirm-spec intake subsidy-fit plan-deliverables draft-section review verify finalize retrospect; do
  check_file ".claude/commands/${cmd}.md" 1
  check_contains "docs/manual.md" "/${cmd}" "manual mentions /${cmd}"
done

while IFS= read -r cmd; do
  check_file ".claude/commands/${cmd}.md" 1
done < <(grep -hoE '`/[A-Za-z0-9_-]+`' docs/manual.md CLAUDE.md | tr -d '`/' | sort -u)

for command_file in .claude/commands/*.md; do
  cmd="$(basename "$command_file" .md)"
  case "$cmd" in my-*) continue ;; esac
  check_contains "docs/manual.md" "/${cmd}" "manual references command file /${cmd}"
done

resolver_commands=(intake subsidy-fit plan-deliverables draft-section review verify finalize)
for cmd in "${resolver_commands[@]}"; do
  command_file=".claude/commands/${cmd}.md"
  check_in_order "$command_file" "resolver precedence for /${cmd}" \
    '## spec / confirmation / notes の解決順' \
    '同じ `subsidy_id` の spec は、次の順で解決してください。' \
    '1. `input/spec/<subsidy_id>/<subsidy_id>.json`' \
    '2. `input/spec/<subsidy_id>.json`' \
    '3. `specs/<subsidy_id>/<subsidy_id>.json`' \
    '4. `specs/<subsidy_id>.json`' \
    '`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。'
  check_contains "$command_file" '`spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合' "resolver stale spec_path guidance for /${cmd}"
done

no_placeholder ".claude/commands/start.md"
no_placeholder "docs/manual.md"

# Wave: doc-subsidy-selection
check_file "docs/補助金の選び方.md" 5000
check_contains "docs/補助金の選び方.md" "Claude Code 契約者" "subsidy selection Claude Code subscriber audience"
check_contains "docs/補助金の選び方.md" "本書は探索の地図" "subsidy selection guide-map positioning"
check_contains "docs/補助金の選び方.md" "一次情報は必ず公式" "subsidy selection official primary source guidance"
check_contains "docs/補助金の選び方.md" "J-Net21" "subsidy selection J-Net21 source guidance"
check_contains "docs/補助金の選び方.md" "Jグランツ" "subsidy selection J-Grants source guidance"
check_contains "docs/補助金の選び方.md" "## 自社との適合を見極める" "subsidy selection fit evaluation section"
check_contains "docs/補助金の選び方.md" "## 締切から逆算する" "subsidy selection deadline back-planning section"
check_contains "docs/補助金の選び方.md" "## よくあるミスマッチ" "subsidy selection mismatch section"
check_contains "docs/補助金の選び方.md" "[要確認]" "subsidy selection unknown facts marker"
check_contains "docs/補助金の選び方.md" "作成者は顧客本人" "subsidy selection customer author guardrail"
check_contains "docs/manual.md" "docs/補助金の選び方.md" "manual references subsidy selection doc"
no_placeholder "docs/補助金の選び方.md"

# Wave: doc-plan-structure
check_file "docs/事業計画書の構成.md" 8000
check_contains "docs/事業計画書の構成.md" "templates/事業計画書テンプレ.md" "plan structure references plan template"
check_contains "docs/事業計画書の構成.md" "目的" "plan structure covers section purpose"
check_contains "docs/事業計画書の構成.md" "補助金審査での見られ方" "plan structure covers review perspective"
check_contains "docs/事業計画書の構成.md" "書く順番" "plan structure covers writing order"
check_contains "docs/事業計画書の構成.md" "数値根拠の置き方" "plan structure covers numeric evidence placement"
check_contains "docs/事業計画書の構成.md" "ありがちな減点" "plan structure covers common deductions"
check_contains "docs/事業計画書の構成.md" "作成者は顧客本人" "plan structure customer author guardrail"
check_contains "docs/事業計画書の構成.md" "行政書士法" "plan structure legal guardrail"
check_contains "docs/事業計画書の構成.md" "[要確認]" "plan structure unknown facts marker"
check_contains "docs/manual.md" "docs/事業計画書の構成.md" "manual references plan structure doc"

for section in 事業概要 現状課題 事業内容 実施体制 スケジュール 資金計画 効果・KPI; do
  check_contains "templates/事業計画書テンプレ.md" "$section" "plan template includes section: $section"
  check_contains "docs/事業計画書の構成.md" "$section" "plan structure includes section: $section"
done

no_placeholder "docs/事業計画書の構成.md"

# Wave: example-worked
check_file "examples/worked-example/README.md" 1500
check_file "examples/worked-example/company-profile.sample.md" 3000
check_file "examples/worked-example/subsidy-fit.sample.md" 3500
check_file "examples/worked-example/draft-section.sample.md" 3000
check_file "examples/worked-example/review-note.sample.md" 3000
check_contains "examples/worked-example/README.md" "架空のサンプル" "worked example README fictional sample label"
check_contains "examples/worked-example/README.md" "/intake" "worked example README intake flow"
check_contains "examples/worked-example/README.md" "/subsidy-fit" "worked example README subsidy-fit flow"
check_contains "examples/worked-example/README.md" "/draft-section" "worked example README draft-section flow"
check_contains "examples/worked-example/README.md" "/review" "worked example README review flow"
check_contains "examples/worked-example/README.md" "実際の数値・要件は" "worked example actual requirements caution"
check_contains "examples/worked-example/README.md" "[要確認]" "worked example README unknown marker"
check_contains "examples/worked-example/company-profile.sample.md" "架空のサンプル" "worked company profile fictional sample label"
check_contains "examples/worked-example/company-profile.sample.md" "作成者: 顧客本人" "worked company profile customer author"
check_contains "examples/worked-example/company-profile.sample.md" "[要確認]" "worked company profile unknown marker"
check_contains "examples/worked-example/subsidy-fit.sample.md" "架空のサンプル" "worked subsidy fit fictional sample label"
check_contains "examples/worked-example/subsidy-fit.sample.md" "公式の募集要項" "worked subsidy fit official requirements"
check_contains "examples/worked-example/subsidy-fit.sample.md" "3段階 explainable matching" "worked subsidy fit explainable matching"
check_contains "examples/worked-example/subsidy-fit.sample.md" "[要確認]" "worked subsidy fit unknown marker"
check_contains "examples/worked-example/draft-section.sample.md" "架空のサンプル" "worked draft fictional sample label"
check_contains "examples/worked-example/draft-section.sample.md" "叩き台" "worked draft section draft label"
check_contains "examples/worked-example/draft-section.sample.md" "対象セクション: 現状課題" "worked draft one section"
check_contains "examples/worked-example/draft-section.sample.md" "[要確認]" "worked draft unknown marker"
check_contains "examples/worked-example/review-note.sample.md" "架空のサンプル" "worked review fictional sample label"
check_contains "examples/worked-example/review-note.sample.md" "judgment_basis" "worked review judgment basis"
check_contains "examples/worked-example/review-note.sample.md" "行政書士法" "worked review legal guardrail"
check_contains "examples/worked-example/review-note.sample.md" "[要確認]" "worked review unknown marker"
check_contains "docs/manual.md" "examples/worked-example/" "manual references worked example"
no_placeholder "examples/worked-example/README.md"
no_placeholder "examples/worked-example/company-profile.sample.md"
no_placeholder "examples/worked-example/subsidy-fit.sample.md"
no_placeholder "examples/worked-example/draft-section.sample.md"
no_placeholder "examples/worked-example/review-note.sample.md"

# Wave: doc-faq
check_file "docs/faq.md" 5000
check_contains "docs/faq.md" "Claude Code 契約者" "FAQ Claude Code subscriber audience"
check_contains "docs/faq.md" "## slash command が出てこない" "FAQ slash-command troubleshooting entry"
check_contains "docs/faq.md" ".claude/commands/" "FAQ command directory guidance"
check_contains "docs/faq.md" "リポジトリのルートフォルダを Claude Code で開いている" "FAQ open repo in Claude Code guidance"
check_contains "docs/faq.md" "## \`input/\` に何を置けばよいか" "FAQ input directory entry"
check_contains "docs/faq.md" "公開リポジトリにコミットしない" "FAQ input confidentiality guidance"
check_contains "docs/faq.md" "## コマンドの実行順を迷ったら" "FAQ command order entry"
check_contains "docs/faq.md" "/start" "FAQ mentions start command"
check_contains "docs/faq.md" "/intake" "FAQ mentions intake command"
check_contains "docs/faq.md" "/subsidy-fit" "FAQ mentions subsidy-fit command"
check_contains "docs/faq.md" "/draft-section" "FAQ mentions draft-section command"
check_contains "docs/faq.md" "/review" "FAQ mentions review command"
check_contains "docs/faq.md" "/finalize" "FAQ mentions finalize command"
check_contains "docs/faq.md" "## 行政書士法に関するよくある誤解" "FAQ legal misconception entry"
check_contains "docs/faq.md" "作成者は顧客本人" "FAQ customer author guardrail"
check_contains "docs/faq.md" "申請代行" "FAQ no application agency guardrail"
check_contains "docs/faq.md" "代理提出" "FAQ no proxy submission guardrail"
check_contains "docs/faq.md" "## 補助金が見つからない" "FAQ subsidy-not-found entry"
check_contains "docs/faq.md" "補助金の選び方.md" "FAQ links subsidy selection doc"
check_contains "docs/faq.md" "[要確認]" "FAQ unknown facts marker"
check_contains "docs/manual.md" "docs/faq.md" "manual references FAQ"
no_placeholder "docs/faq.md"

# Wave: readme-icp
check_file "README.md" 4500
check_contains "README.md" "Claude Code 契約者" "README states Claude Code subscriber ICP"
check_contains "README.md" "## 何ができるか" "README capabilities section"
check_contains "README.md" "## 対象" "README target audience section"
check_contains "README.md" "## 提供物" "README deliverables section"
check_contains "README.md" "## 5分クイックスタート" "README five-minute quickstart section"
check_contains "README.md" "Use this template" "README template quickstart"
check_contains "README.md" "git clone" "README clone quickstart"
check_contains "README.md" "Claude Code で開" "README open in Claude Code quickstart"
check_contains "README.md" "/start" "README quickstart names start command"
check_contains "README.md" "docs/manual.md" "README links manual"
check_contains "README.md" "slash commands" "README mentions slash commands"
check_contains "README.md" "作成者は顧客本人" "README customer author guardrail"
check_contains "README.md" "申請代行ではありません" "README no application agency disclaimer"
check_contains "README.md" "行政書士法" "README administrative scrivener law guardrail"
check_contains "README.md" "[要確認]" "README unknown facts marker"
check_relative_links "README.md"
no_placeholder "README.md"

# Wave: github-template-setup
check_file "LICENSE" 1000
check_contains "LICENSE" "Apache License" "Apache-2.0 license"
check_contains "LICENSE" "Version 2.0, January 2004" "Apache-2.0 version"
check_contains "LICENSE" "APPENDIX: How to apply the Apache License to your work." "Apache-2.0 appendix"
check_contains "LICENSE" "Copyright 2026 日本補助金支援機構株式会社" "Apache-2.0 copyright notice"
check_file ".github/ISSUE_TEMPLATE/feedback.md" 800
check_contains ".github/ISSUE_TEMPLATE/feedback.md" "質問・フィードバック" "GitHub issue template title"
check_contains ".github/ISSUE_TEMPLATE/feedback.md" "機密情報" "GitHub issue template confidentiality caution"
check_contains ".github/ISSUE_TEMPLATE/feedback.md" "作成者は顧客本人" "GitHub issue template customer author guardrail"
check_contains ".github/ISSUE_TEMPLATE/feedback.md" "申請代行" "GitHub issue template no agency guardrail"
check_file "docs/テンプレートrepoの使い方.md" 3000
check_contains "docs/テンプレートrepoの使い方.md" "Use this template" "template usage note mentions Use this template"
check_contains "docs/テンプレートrepoの使い方.md" "private" "template usage note recommends private repo"
check_contains "docs/テンプレートrepoの使い方.md" "input/" "template usage note covers input directory"
check_contains "docs/テンプレートrepoの使い方.md" "Claude Code 契約者" "template usage note Claude Code audience"
check_contains "docs/テンプレートrepoの使い方.md" "作成者は顧客本人" "template usage note customer author guardrail"
check_contains "docs/テンプレートrepoの使い方.md" "[要確認]" "template usage note unknown facts marker"
check_contains "README.md" "Use this template" "README mentions Use this template"
check_contains "README.md" "docs/テンプレートrepoの使い方.md" "README links template usage note"
check_contains "docs/manual.md" "docs/テンプレートrepoの使い方.md" "manual links template usage note"
check_relative_links "README.md"
check_relative_links "docs/manual.md"
no_placeholder "LICENSE"
no_placeholder ".github/ISSUE_TEMPLATE/feedback.md"
no_placeholder "docs/テンプレートrepoの使い方.md"

# Wave: legal-guardrail-pass
check_file "docs/法務とスコープ.md" 3000
check_contains "docs/法務とスコープ.md" "情報補助ツール" "legal scope information-assistance positioning"
check_contains "docs/法務とスコープ.md" "作成者は顧客本人" "legal scope customer author guardrail"
check_contains "docs/法務とスコープ.md" "申請代行" "legal scope no application agency"
check_contains "docs/法務とスコープ.md" "代理提出" "legal scope no proxy submission"
check_contains "docs/法務とスコープ.md" "税理士法" "legal scope tax accountant law boundary"
check_contains "docs/法務とスコープ.md" "行政書士法" "legal scope administrative scrivener law boundary"
check_contains "docs/法務とスコープ.md" "数値は推測しません" "legal scope no guessed numbers"
check_contains "docs/法務とスコープ.md" "公式の募集要項が正" "legal scope official requirements priority"
check_contains "docs/法務とスコープ.md" "[要確認]" "legal scope unknown facts marker"
check_contains "README.md" "docs/法務とスコープ.md" "README links legal scope doc"
check_contains "docs/manual.md" "docs/法務とスコープ.md" "manual links legal scope doc"

for f in CLAUDE.md docs/manual.md .claude/commands/review.md .claude/commands/finalize.md docs/法務とスコープ.md; do
  check_contains "$f" "作成者は顧客本人" "final legal consistency customer author in $f"
  check_contains "$f" "行政書士法" "final legal consistency administrative scrivener law in $f"
done

check_relative_links "README.md"
check_relative_links "docs/manual.md"
no_placeholder "docs/法務とスコープ.md"

# Wave: public-scrub
public_scrub_strategy_paths=(
  "docs/strategy/business-design.md"
  "docs/strategy/data-loop-design.md"
  "docs/strategy/monetization-research-2026-07-02.md"
  "docs/strategy/zagumi-research-2026-07-03.md"
  "docs/design/pivot-decision.md"
  "docs/design/wave-plans.md"
  "docs/design/harness-backlog.md"
)
if [ "$VALIDATE_INTERNAL_MODE" = "1" ]; then
  for strategy_path in "${public_scrub_strategy_paths[@]}"; do
    if [ -f "$strategy_path" ]; then
      ok
    else
      bad "strategy SSoT file missing (must exist in internal repo): $strategy_path"
    fi
  done
  for internal_path in "${INTERNAL_ONLY_PATHS[@]}"; do
    case "$internal_path" in
      */)
        if [ -f "core-manifest.json" ] && grep -qF -- "\"$internal_path" core-manifest.json; then
          bad "core-manifest.json must not include internal-only path: $internal_path"
        else
          ok
        fi
        ;;
      *)
        if [ -f "core-manifest.json" ] && grep -qF -- "\"$internal_path\"" core-manifest.json; then
          bad "core-manifest.json must not include internal-only path: $internal_path"
        else
          ok
        fi
        ;;
    esac
  done
else
  for removed_path in "${public_scrub_strategy_paths[@]}"; do
    if [ -e "$removed_path" ]; then
      bad "public scrub removed path still exists: $removed_path"
    else
      ok
    fi
  done
  for removed_path in "docs/plans" "tools/release"; do
    if [ -e "$removed_path" ]; then
      bad "public scrub internal-only path still exists: $removed_path"
    else
      ok
    fi
  done
fi

# The word list lives only in .ralph/ (excluded from the public tree). In the
# public repo this check self-skips, intentionally keeping those terms out of
# this script while still enforcing them in the private development worktree.
sentinel_file=".ralph/public-scrub-sentinel-words.txt"
if [ -f "$sentinel_file" ]; then
  sentinel_fail=0
  sentinel_hits_file="$(mktemp "${TMPDIR:-/tmp}/public-scrub-sentinel.XXXXXX")"
  while IFS= read -r sentinel_word || [ -n "$sentinel_word" ]; do
    case "$sentinel_word" in ""|\#*) continue ;; esac
    : > "$sentinel_hits_file"
    while IFS= read -r -d '' tracked_file; do
      case "$tracked_file" in
        .ralph/*|docs/design/public-release-plan.md) ;;
        *)
          if ! is_internal_only_path "$tracked_file"; then
            grep -Fn -- "$sentinel_word" "$tracked_file" >> "$sentinel_hits_file" 2>/dev/null || true
          fi
          ;;
      esac
    done < <(git ls-files -z)
    if [ -s "$sentinel_hits_file" ]; then
      cat "$sentinel_hits_file"
      sentinel_fail=1
    fi
  done < "$sentinel_file"
  rm -f "$sentinel_hits_file"
  if [ "$sentinel_fail" = "0" ]; then
    ok
  else
    bad "public scrub sentinel scan found non-public wording"
  fi
else
  ok
fi

if [ "$VALIDATE_INTERNAL_MODE" = "1" ]; then
  check_contains "tools/release/export.sh" \
    'git show "$SRC:$EXCLUDED_PATHS_FILE"' \
    "export reads exclusions from source commit shared list"
  check_contains "tools/release/export.sh" \
    '--normalize-export-exclusions "$EXCLUDED_PATHS_BLOB"' \
    "export uses the shared fail-closed exclusion parser"
  check_contains "tools/release/export.sh" \
    'assert_exclusion_target_safe "$p"' \
    "export validates exclusion targets before removal"
  check_contains "tools/release/export.sh" \
    '[ -L "$current" ]' \
    "export rejects symlink path components"
  check_contains "tools/release/export.sh" \
    'rm -rf -- "$excluded_target"' \
    "export removes paths from shared exclusion list"
fi

# Wave: data-charter-public-sanitize
check_file "docs/governance/data-charter.md" 3000
check_contains "docs/governance/data-charter.md" "内部決定記録（非公開）" "data charter replaces internal references"
check_contains "docs/governance/data-charter.md" "**非接触原則（本憲章の第一原則）**" "data charter keeps non-contact principle heading"
check_contains "docs/governance/data-charter.md" "## 5. 任意性・consent・削除・保管" "data charter keeps optionality section"
check_contains "docs/governance/data-charter.md" "## 7. スポンサー独立性と COI" "data charter keeps COI section"
check_contains "docs/governance/data-charter.md" "## 9. 非営利 data steward への移行条件" "data charter keeps nonprofit steward transition section"

data_charter_removed_ref_pivot="pivot-""decision"
data_charter_removed_ref_zagumi="zagumi-""research"
for forbidden in "$data_charter_removed_ref_pivot" "$data_charter_removed_ref_zagumi"; do
  if grep -qF -- "$forbidden" "docs/governance/data-charter.md"; then
    bad "docs/governance/data-charter.md still references internal document: $forbidden"
  else
    ok
  fi
done

for f in TERMS.md docs/telemetry.md docs/data-policy.md docs/collaborator-招待手順.md; do
  check_contains "$f" "docs/governance/data-charter.md" "data charter reference remains in $f"
  check_relative_links "$f"
done

no_placeholder "docs/governance/data-charter.md"

# Wave: pivot-terms-licensing
check_file "TERMS.md" 3000
check_file "docs/data-policy.md" 1500
check_file "docs/licensing-tiers.md" 1500
check_contains "TERMS.md" "collaborator" "terms collaborator condition"
if grep -qF -- "外販しない" "TERMS.md" || grep -qF -- "外販しません" "TERMS.md"; then
  ok
else
  bad "TERMS.md missing expected content: no external sale wording"
fi
check_contains "TERMS.md" "支援者単位" "terms supporter-level license"
check_contains "TERMS.md" "行政書士法" "terms administrative scrivener law scope"
if grep -qF -- "発効日" "TERMS.md" || grep -qF -- "DRAFT" "TERMS.md"; then
  ok
else
  bad "TERMS.md missing expected content: effective date or draft marker"
fi
check_contains "docs/data-policy.md" "外販" "data policy external-sale wording"
check_contains "docs/licensing-tiers.md" "支援者単位" "licensing tiers supporter-level license"
check_contains "docs/licensing-tiers.md" "result-report" "licensing tiers result-report model"
check_contains "docs/licensing-tiers.md" "任意提出" "licensing tiers optional result-report"
check_contains "docs/licensing-tiers.md" "データ提供なしで同等機能" "licensing tiers B2B no-data same-function path"
check_contains "TERMS.md" "外販" "terms external-sale consistency"
check_contains "docs/data-policy.md" "外販" "data policy external-sale consistency"

# Wave: pivot-onboarding-setup
check_file "docs/onboarding/00-はじめに.md" 1000
check_file "docs/onboarding/01-githubアカウント作成.md" 1000
check_file "docs/onboarding/02-claude-codeセットアップ.md" 1000
check_file "docs/onboarding/03-このキットを自分のものにする.md" 1000
check_file ".claude/commands/setup.md" 3000
if [ "$(sed -n '1p' ".claude/commands/setup.md")" = "---" ] &&
   sed -n '2,/^---$/p' ".claude/commands/setup.md" | grep -q '^description:'; then
  ok
else
  bad ".claude/commands/setup.md missing YAML frontmatter description"
fi
check_contains ".claude/commands/setup.md" "/start" "setup command leads to start"
check_contains ".claude/commands/setup.md" "TERMS.md" "setup command references terms"
check_contains ".claude/commands/setup.md" "docs/data-policy.md" "setup command references data policy"
check_contains ".claude/commands/setup.md" "result-report 任意提出" "setup command checks result-report optional submission"
check_contains ".claude/commands/setup.md" "旧 collaborator 招待モデルは撤回済み" "setup command retires collaborator invite"
check_contains "CLAUDE.md" "/setup" "CLAUDE workflow references setup"
check_contains "docs/manual.md" "/setup" "manual references setup"
check_contains "CLAUDE.md" "docs/onboarding/" "CLAUDE references onboarding docs"
check_contains "docs/manual.md" "docs/onboarding/00-はじめに.md" "manual references onboarding start"
check_contains "docs/manual.md" "TERMS.md" "manual references terms"
check_contains "docs/manual.md" "docs/data-policy.md" "manual references data policy"

# Wave: pivot-collaborator-dataloop-docs
check_file "docs/collaborator-招待手順.md" 1500
check_file "docs/改善ループ.md" 1500
check_contains "docs/collaborator-招待手順.md" "result-report" "result-report guide uses result-report term"
check_contains "docs/collaborator-招待手順.md" "任意" "result-report guide states optionality"
check_contains "docs/collaborator-招待手順.md" "docs/governance/data-charter.md" "result-report guide references data charter"
check_contains "docs/collaborator-招待手順.md" "TERMS.md" "result-report guide references terms"
check_contains "docs/collaborator-招待手順.md" "allowlist" "result-report guide summarizes allowlist"
check_contains "docs/collaborator-招待手順.md" "denylist" "result-report guide summarizes denylist"
check_contains "docs/collaborator-招待手順.md" "consent" "result-report guide covers consent"
check_contains "docs/collaborator-招待手順.md" "削除" "result-report guide covers deletion"
check_contains "docs/改善ループ.md" "外販しない" "improvement loop no external sale condition"
check_contains "docs/改善ループ.md" "キット品質の改善" "improvement loop quality improvement purpose"
check_contains "docs/改善ループ.md" "result-report" "improvement loop uses result-report"
check_contains "docs/改善ループ.md" "allowlist" "improvement loop respects allowlist"

for f in \
  TERMS.md \
  docs/data-policy.md \
  docs/licensing-tiers.md \
  docs/onboarding/00-はじめに.md \
  docs/onboarding/01-githubアカウント作成.md \
  docs/onboarding/02-claude-codeセットアップ.md \
  docs/onboarding/03-このキットを自分のものにする.md \
  .claude/commands/setup.md \
  docs/collaborator-招待手順.md \
  docs/改善ループ.md; do
  no_placeholder "$f"
done

# Wave: spec-assets-wiring
for json_file in \
  schemas/subsidy-spec.schema.json \
  schemas/company-profile.schema.json \
  schemas/application-record.schema.json \
  schemas/taxonomy-v1.json \
  specs/jizokuka-20/jizokuka-20.json \
  specs/jizokuka-20/jizokuka-20.confirmation.json; do
  check_file "$json_file" 1
  check_json "$json_file"
done

check_contains "schemas/subsidy-spec.schema.json" "schema_version" "subsidy spec schema_version field"
check_contains "schemas/subsidy-spec.schema.json" "deliverables" "subsidy spec deliverables field"
check_contains "schemas/subsidy-spec.schema.json" "clauses" "subsidy spec clauses field"
check_contains "schemas/subsidy-spec.schema.json" "predicate" "subsidy spec predicate definition"
check_contains "schemas/subsidy-spec.schema.json" "schedule" "subsidy spec schedule field"
check_contains "schemas/subsidy-spec.schema.json" "source_clauses" "subsidy spec source_clauses references"

check_contains "schemas/company-profile.schema.json" "entity_type" "company profile entity_type field"
check_contains "schemas/company-profile.schema.json" "industry_class" "company profile industry_class field"
check_contains "schemas/company-profile.schema.json" "employees" "company profile employees field"
check_contains "schemas/company-profile.schema.json" "certifications" "company profile certifications field"
check_contains "schemas/company-profile.schema.json" "plans" "company profile plans field"

check_contains "schemas/application-record.schema.json" "record_id" "application record record_id field"
check_contains "schemas/application-record.schema.json" "result" "application record result field"
check_contains "schemas/application-record.schema.json" "lessons" "application record lessons field"
check_contains "schemas/application-record.schema.json" "next_actions" "application record next_actions field"

check_contains "schemas/taxonomy-v1.json" "taxonomy_version" "taxonomy version field"
check_contains "specs/jizokuka-20/jizokuka-20.confirmation.json" '"confirmed_by": "provider"' "jizokuka provider confirmation"
check_spec_confirmation_binding "specs/jizokuka-20/jizokuka-20.json" "specs/jizokuka-20/jizokuka-20.confirmation.json"

check_file "specs/README.md" 2000
check_contains "specs/README.md" "同梱 spec" "specs README explains bundled spec"
check_contains "specs/README.md" "優先" "specs README precedence rule"
check_contains "specs/README.md" "input/spec/" "specs README input spec override path"
check_contains "specs/README.md" "confirmation" "specs README confirmation report"
check_contains "specs/README.md" "spec_sha256" "specs README sha binding"
check_contains "specs/README.md" "provider" "specs README provider-confirmed bundled specs"
check_relative_links "specs/README.md"
no_placeholder "specs/README.md"

# Wave: check-spec-engine
check_file "tools/check-spec.sh" 100
check_file "tools/lib/check_spec.py" 8000

if [ "$(sed -n '1p' "tools/check-spec.sh")" = "#!/bin/bash" ]; then
  ok
else
  bad "tools/check-spec.sh must be a bash wrapper"
fi

check_contains "tools/check-spec.sh" "set -u" "check-spec wrapper uses set -u"
check_contains "tools/check-spec.sh" "lib/check_spec.py" "check-spec wrapper invokes Python engine"

if grep -qF -- "import requests" "tools/lib/check_spec.py"; then
  bad "tools/lib/check_spec.py must not import requests"
else
  ok
fi

if grep -qF -- "import yaml" "tools/lib/check_spec.py"; then
  bad "tools/lib/check_spec.py must not import yaml"
else
  ok
fi

if bash tools/check-spec.sh specs/jizokuka-20/jizokuka-20.json >/dev/null 2>&1; then
  ok
else
  bad "tools/check-spec.sh must pass on specs/jizokuka-20/jizokuka-20.json"
fi

# Wave: check-drafts-engine
check_file "tools/check-drafts.sh" 100
check_file "tools/lib/check_drafts.py" 7000

if [ "$(sed -n '1p' "tools/check-drafts.sh")" = "#!/bin/bash" ]; then
  ok
else
  bad "tools/check-drafts.sh must be a bash wrapper"
fi

check_contains "tools/check-drafts.sh" "set -u" "check-drafts wrapper uses set -u"
check_contains "tools/check-drafts.sh" "lib/check_drafts.py" "check-drafts wrapper invokes Python engine"
check_contains "tools/lib/check_drafts.py" "Character count rule" "check-drafts documents character count rule"
check_contains "tools/lib/check_drafts.py" "## 叩き台" "check-drafts requires draft heading"
check_contains "tools/lib/check_drafts.py" "[要確認]" "check-drafts counts need-check markers"

if grep -qF -- "import requests" "tools/lib/check_drafts.py"; then
  bad "tools/lib/check_drafts.py must not import requests"
else
  ok
fi

if grep -qF -- "import yaml" "tools/lib/check_drafts.py"; then
  bad "tools/lib/check_drafts.py must not import yaml"
else
  ok
fi

if bash tools/check-drafts.sh tools/fixtures/spec/good-spec.json tools/fixtures/drafts/drafts-partial >/dev/null 2>&1; then
  ok
else
  bad "tools/check-drafts.sh must exit 0 when only WARN coverage lines are present"
fi

# Wave: test-check-spec-fixtures
check_file "tools/lib/predicate.py" 4000
check_file "tools/test-check-spec.sh" 2000

for json_file in \
  tools/fixtures/spec/good-spec.json \
  tools/fixtures/spec/good-spec.confirmation.json \
  tools/fixtures/spec/missing-required-key.json \
  tools/fixtures/spec/duplicate-id.json \
  tools/fixtures/spec/bad-id-pattern.json \
  tools/fixtures/spec/no-application-deadline.json \
  tools/fixtures/spec/bad-due-event.json \
  tools/fixtures/spec/bad-source-document.json \
  tools/fixtures/spec/bad-source-documents-fields.json \
  tools/fixtures/spec/bad-category-tag.json \
  tools/fixtures/spec/bonus-missing.json \
  tools/fixtures/spec/bonus-missing.confirmation.json \
  tools/fixtures/spec/confirmation-open-item.json \
  tools/fixtures/spec/confirmation-open-item.confirmation.json \
  tools/fixtures/spec/direct-bypass-confirmed.json \
  tools/fixtures/spec/direct-bypass-confirmed.confirmation.json \
  tools/fixtures/spec/stale-sha.json \
  tools/fixtures/spec/stale-sha.confirmation.json \
  tools/fixtures/profiles/shougyou-5.json \
  tools/fixtures/profiles/seizou-25.json \
  tools/fixtures/profiles/unknown-emp.json; do
  check_file "$json_file" 1
  check_json "$json_file"
done

check_contains "tools/lib/predicate.py" "def eval_predicate" "predicate evaluator entry point"
check_contains "tools/lib/predicate.py" "UNKNOWN" "predicate supports unknown"
check_contains "tools/lib/predicate.py" "op == \"gt\"" "predicate supports gt"
check_contains "tools/lib/predicate.py" "op == \"lt\"" "predicate supports lt"
check_contains "tools/test-check-spec.sh" "good-spec.json" "check-spec fixture test includes good spec"
check_contains "tools/test-check-spec.sh" "specs/jizokuka-20/jizokuka-20.json" "check-spec fixture test includes bundled spec"
check_contains "tools/test-check-spec.sh" "size-limit" "predicate fixture test uses jizokuka size-limit"

if grep -qF -- "import requests" "tools/lib/predicate.py"; then
  bad "tools/lib/predicate.py must not import requests"
else
  ok
fi

if grep -qF -- "import yaml" "tools/lib/predicate.py"; then
  bad "tools/lib/predicate.py must not import yaml"
else
  ok
fi

if bash tools/test-check-spec.sh >/dev/null 2>&1; then
  ok
else
  bad "tools/test-check-spec.sh must pass"
fi

no_placeholder "tools/lib/predicate.py"
no_placeholder "tools/test-check-spec.sh"

# Wave: test-check-drafts-fixtures
check_file "tools/test-check-drafts.sh" 2000

for fixture_file in \
  tools/fixtures/drafts/drafts-good/section-1.md \
  tools/fixtures/drafts/drafts-good/section-2.md \
  tools/fixtures/drafts/drafts-overflow/section-2.md \
  tools/fixtures/drafts/drafts-no-frontmatter/section-1.md \
  tools/fixtures/drafts/drafts-unknown-ids/unknown.md \
  tools/fixtures/drafts/drafts-no-heading/section-1.md \
  tools/fixtures/drafts/drafts-partial/section-1.md; do
  check_file "$fixture_file" 1
  no_placeholder "$fixture_file"
done

check_contains "tools/fixtures/spec/good-spec.json" '"max_chars": 30' "good spec includes 30-char draft fixture section"
check_contains "tools/test-check-drafts.sh" "drafts-good" "check-drafts fixture test includes good drafts"
check_contains "tools/test-check-drafts.sh" "drafts-overflow" "check-drafts fixture test includes overflow drafts"
check_contains "tools/test-check-drafts.sh" "drafts-no-frontmatter" "check-drafts fixture test includes no-frontmatter drafts"
check_contains "tools/test-check-drafts.sh" "drafts-unknown-ids" "check-drafts fixture test includes unknown-id drafts"
check_contains "tools/test-check-drafts.sh" "drafts-no-heading" "check-drafts fixture test includes no-heading drafts"
check_contains "tools/test-check-drafts.sh" "drafts-partial" "check-drafts fixture test includes partial drafts"
check_contains "tools/test-check-drafts.sh" "^WARN:" "check-drafts fixture test asserts coverage warning"

if bash tools/test-check-drafts.sh >/dev/null 2>&1; then
  ok
else
  bad "tools/test-check-drafts.sh must pass"
fi

no_placeholder "tools/test-check-drafts.sh"

# Wave: cmd-ingest-guidelines
check_file ".claude/commands/ingest-guidelines.md" 6000

if [ "$(sed -n '1p' ".claude/commands/ingest-guidelines.md")" = "---" ] &&
   sed -n '2,/^---$/p' ".claude/commands/ingest-guidelines.md" | grep -q '^description:'; then
  ok
else
  bad ".claude/commands/ingest-guidelines.md missing YAML frontmatter description"
fi

check_contains ".claude/commands/ingest-guidelines.md" "input/guidelines/" "ingest saves original guidelines"
check_contains ".claude/commands/ingest-guidelines.md" "document_id" "ingest assigns document ids"
check_contains ".claude/commands/ingest-guidelines.md" "source_documents[].url_or_path" "ingest uses schema source document locator"
check_contains ".claude/commands/ingest-guidelines.md" "schemas/subsidy-spec.schema.json" "ingest reads subsidy spec schema"
check_contains ".claude/commands/ingest-guidelines.md" "input/spec/<subsidy_id>.json" "ingest writes draft spec path"
check_contains ".claude/commands/ingest-guidelines.md" "status" "ingest controls spec status"
check_contains ".claude/commands/ingest-guidelines.md" "draft" "ingest starts with draft status"
check_contains ".claude/commands/ingest-guidelines.md" "1 clause = 1 論点" "ingest extraction one-clause rule"
check_contains ".claude/commands/ingest-guidelines.md" "verbatim text" "ingest requires verbatim source text"
check_contains ".claude/commands/ingest-guidelines.md" "source_clauses" "ingest requires source clause references"
check_contains ".claude/commands/ingest-guidelines.md" "input/spec/<subsidy_id>.confirmation.json" "ingest writes confirmation path"
check_contains ".claude/commands/ingest-guidelines.md" "confirmation" "ingest mentions confirmation"
check_contains ".claude/commands/ingest-guidelines.md" "state=open" "ingest starts confirmation items open"
check_contains ".claude/commands/ingest-guidelines.md" "突合" "ingest delegates reconciliation"
check_contains ".claude/commands/ingest-guidelines.md" "/confirm-spec" "ingest routes reconciliation to confirm-spec"
check_contains ".claude/commands/ingest-guidelines.md" "confirmed" "ingest describes later confirmed status"
check_contains ".claude/commands/ingest-guidelines.md" "spec_sha256" "ingest describes later spec sha binding"
check_contains ".claude/commands/ingest-guidelines.md" "bash tools/check-spec.sh" "ingest runs check-spec"
check_contains ".claude/commands/ingest-guidelines.md" "input/current-application.json" "ingest writes current application"
check_contains ".claude/commands/ingest-guidelines.md" "state=spec_draft" "ingest sets spec_draft state"
check_contains ".claude/commands/ingest-guidelines.md" '次の作業は `/confirm-spec`' "ingest routes to confirm-spec next"
check_contains ".claude/commands/ingest-guidelines.md" "作成者は顧客本人" "ingest customer author guardrail"
check_contains ".claude/commands/ingest-guidelines.md" "数値は推測しない" "ingest no guessed numbers guardrail"
check_contains ".claude/commands/ingest-guidelines.md" "[要確認]" "ingest unknown facts marker"
check_contains ".claude/commands/ingest-guidelines.md" "募集要項が正" "ingest official guidelines priority"
check_contains ".claude/commands/ingest-guidelines.md" "育成層" "ingest output stays in user layer"
check_contains "docs/manual.md" "/ingest-guidelines" "manual references ingest-guidelines"
no_placeholder ".claude/commands/ingest-guidelines.md"
no_placeholder "docs/manual.md"

# Wave: cmd-plan-deliverables
check_file ".claude/commands/plan-deliverables.md" 6000

if [ "$(sed -n '1p' ".claude/commands/plan-deliverables.md")" = "---" ] &&
   sed -n '2,/^---$/p' ".claude/commands/plan-deliverables.md" | grep -q '^description:'; then
  ok
else
  bad ".claude/commands/plan-deliverables.md missing YAML frontmatter description"
fi

check_contains ".claude/commands/plan-deliverables.md" "input/current-application.json" "plan-deliverables reads current application"
check_contains ".claude/commands/plan-deliverables.md" "current-application.json" "plan-deliverables mentions current-application.json"
check_contains ".claude/commands/plan-deliverables.md" "input/deliverables.md" "plan-deliverables writes deliverables view"
check_contains ".claude/commands/plan-deliverables.md" "REGENERABLE VIEW" "plan-deliverables declares regenerable view"
check_contains ".claude/commands/plan-deliverables.md" "再生成" "plan-deliverables explains regeneration"
check_contains ".claude/commands/plan-deliverables.md" "chosen_funding" "plan-deliverables requires chosen funding"
check_contains ".claude/commands/plan-deliverables.md" "state=spec_confirmed" "plan-deliverables routes spec_confirmed to subsidy-fit"
check_contains ".claude/commands/plan-deliverables.md" "state" "plan-deliverables updates application state"
check_contains ".claude/commands/plan-deliverables.md" "planned" "plan-deliverables sets planned state"
check_contains ".claude/commands/plan-deliverables.md" "AIと作る成果物" "plan-deliverables AI deliverables section"
check_contains ".claude/commands/plan-deliverables.md" "人がやることリスト" "plan-deliverables human task list"
check_contains ".claude/commands/plan-deliverables.md" "添付チェックリスト" "plan-deliverables attachment checklist"
check_contains ".claude/commands/plan-deliverables.md" "締切カレンダー" "plan-deliverables deadline calendar"
check_contains ".claude/commands/plan-deliverables.md" "hard flag" "plan-deliverables hard deadline flag"
check_contains ".claude/commands/plan-deliverables.md" "relative" "plan-deliverables relative schedule handling"
check_contains ".claude/commands/plan-deliverables.md" "required_if" "plan-deliverables evaluates required_if"
check_contains ".claude/commands/plan-deliverables.md" "produced_by=ai_draftable" "plan-deliverables filters AI draftable outputs"
check_contains ".claude/commands/plan-deliverables.md" "produced_by=human_only" "plan-deliverables includes human-only work"
check_contains ".claude/commands/plan-deliverables.md" "produced_by=external" "plan-deliverables includes external work"
check_contains ".claude/commands/plan-deliverables.md" "type=attachment" "plan-deliverables includes attachments"
check_contains ".claude/commands/plan-deliverables.md" "issuer" "plan-deliverables shows issuer"
check_contains ".claude/commands/plan-deliverables.md" "due_event_id" "plan-deliverables shows due event"
check_contains ".claude/commands/plan-deliverables.md" "format" "plan-deliverables shows attachment format"
check_contains ".claude/commands/plan-deliverables.md" "upload_target" "plan-deliverables shows upload target"
check_contains ".claude/commands/plan-deliverables.md" "作成者は顧客本人" "plan-deliverables customer author guardrail"
check_contains ".claude/commands/plan-deliverables.md" "行政書士法" "plan-deliverables legal guardrail"
check_contains ".claude/commands/plan-deliverables.md" "数値は推測しない" "plan-deliverables no guessed numbers guardrail"
check_contains ".claude/commands/plan-deliverables.md" "[要確認]" "plan-deliverables unknown facts marker"
check_contains ".claude/commands/plan-deliverables.md" "募集要項が正" "plan-deliverables official requirements priority"
check_contains ".claude/commands/plan-deliverables.md" '出力先は `input/`' "plan-deliverables output stays in input"
check_contains "docs/manual.md" "/plan-deliverables" "manual references plan-deliverables"
no_placeholder ".claude/commands/plan-deliverables.md"
no_placeholder "docs/manual.md"

# Wave: cmd-verify
check_file ".claude/commands/verify.md" 6000

if [ "$(sed -n '1p' ".claude/commands/verify.md")" = "---" ] &&
   sed -n '2,/^---$/p' ".claude/commands/verify.md" | grep -q '^description:'; then
  ok
else
  bad ".claude/commands/verify.md missing YAML frontmatter description"
fi

check_contains ".claude/commands/verify.md" "input/current-application.json" "verify reads current application"
check_contains ".claude/commands/verify.md" "spec_path" "verify requires spec_path"
check_contains ".claude/commands/verify.md" "input/drafts/<subsidy_id>/" "verify uses subsidy draft directory"
check_contains ".claude/commands/verify.md" "bash tools/check-spec.sh" "verify runs check-spec"
check_contains ".claude/commands/verify.md" "bash tools/check-drafts.sh" "verify runs check-drafts"
check_contains ".claude/commands/verify.md" "input/checks/verify-report.md" "verify writes verify report"
check_contains ".claude/commands/verify.md" "verify-report.md" "verify mentions verify report"
check_contains ".claude/commands/verify.md" "spec_check" "verify report includes spec_check"
check_contains ".claude/commands/verify.md" "draft_check" "verify report includes draft_check"
check_contains ".claude/commands/verify.md" "draft_bodies_sha256" "verify report includes draft hash"
check_contains ".claude/commands/verify.md" "draft_hash_algorithm" "verify report includes hash algorithm"
check_contains ".claude/commands/verify.md" "generated_at" "verify report includes generated_at"
check_contains ".claude/commands/verify.md" "sha256 over draft body regions" "verify documents hash algorithm"
check_contains ".claude/commands/verify.md" "files sorted by path ascending" "verify documents file ordering"
check_contains ".claude/commands/verify.md" "joined with \\\\n---\\\\n" "verify documents hash joiner"
check_contains ".claude/commands/verify.md" "python3" "verify uses python3 stdlib"
check_contains ".claude/commands/verify.md" "## 叩き台" "verify hashes draft body region"
check_contains ".claude/commands/verify.md" "セクション別の字数" "verify summarizes per-section chars"
check_contains ".claude/commands/verify.md" "coverage gaps" "verify summarizes coverage gaps"
check_contains ".claude/commands/verify.md" "[要確認] total" "verify summarizes need-check total"
check_contains ".claude/commands/verify.md" 'state` が `drafting` または `verified`' "verify requires drafting or verified state"
check_contains ".claude/commands/verify.md" "state=planned" "verify routes planned state to draft-section"
check_contains ".claude/commands/verify.md" "/draft-section" "verify routes draft creation before verification"
check_contains ".claude/commands/verify.md" "state=fit_done" "verify routes fit_done state to plan-deliverables"
check_contains ".claude/commands/verify.md" "/plan-deliverables" "verify routes planning before verification"
check_contains ".claude/commands/verify.md" "state=intake_done" "verify routes intake_done state to subsidy-fit"
check_contains ".claude/commands/verify.md" "/subsidy-fit" "verify routes fit check before verification"
check_contains ".claude/commands/verify.md" "state=spec_confirmed" "verify routes spec_confirmed state to intake"
check_contains ".claude/commands/verify.md" "/intake" "verify routes intake before verification"
check_contains ".claude/commands/verify.md" 'state` が欠落' "verify routes missing state to spec selection"
check_contains ".claude/commands/verify.md" "state=verified" "verify sets verified state"
check_contains ".claude/commands/verify.md" "再実行" "verify explains rerun after draft edits"
check_contains ".claude/commands/verify.md" "作成者は顧客本人" "verify customer author guardrail"
check_contains ".claude/commands/verify.md" "行政書士法" "verify legal guardrail"
check_contains ".claude/commands/verify.md" "数値は推測しない" "verify no guessed numbers guardrail"
check_contains ".claude/commands/verify.md" "[要確認]" "verify unknown facts marker"
check_contains ".claude/commands/verify.md" "募集要項が正" "verify official requirements priority"
check_contains ".claude/commands/verify.md" '出力先は `input/`' "verify output stays in input"
check_contains "docs/manual.md" "/verify" "manual references verify"
no_placeholder ".claude/commands/verify.md"
no_placeholder "docs/manual.md"

# Wave: cmd-retrospect
check_file ".claude/commands/retrospect.md" 6000

if [ "$(sed -n '1p' ".claude/commands/retrospect.md")" = "---" ] &&
   sed -n '2,/^---$/p' ".claude/commands/retrospect.md" | grep -q '^description:'; then
  ok
else
  bad ".claude/commands/retrospect.md missing YAML frontmatter description"
fi

check_contains ".claude/commands/retrospect.md" "schemas/application-record.schema.json" "retrospect reads application-record schema"
check_contains ".claude/commands/retrospect.md" "application-record" "retrospect mentions application-record"
check_contains ".claude/commands/retrospect.md" "knowledge/records/" "retrospect writes records"
check_contains ".claude/commands/retrospect.md" "knowledge/lessons/" "retrospect writes lessons"
check_contains ".claude/commands/retrospect.md" "adopted" "retrospect result enum adopted"
check_contains ".claude/commands/retrospect.md" "rejected" "retrospect result enum rejected"
check_contains ".claude/commands/retrospect.md" "not_submitted" "retrospect result enum not_submitted"
check_contains ".claude/commands/retrospect.md" "pending" "retrospect result enum pending"
check_contains ".claude/commands/retrospect.md" "score" "retrospect captures score when available"
check_contains ".claude/commands/retrospect.md" "feedback_text" "retrospect captures feedback"
check_contains ".claude/commands/retrospect.md" "intake" "retrospect lessons include intake phase"
check_contains ".claude/commands/retrospect.md" "fit" "retrospect lessons include fit phase"
check_contains ".claude/commands/retrospect.md" "draft" "retrospect lessons include draft phase"
check_contains ".claude/commands/retrospect.md" "verify" "retrospect lessons include verify phase"
check_contains ".claude/commands/retrospect.md" "finalize" "retrospect lessons include finalize phase"
check_contains ".claude/commands/retrospect.md" "/draft-section" "retrospect explains next draft-section reads lessons"
check_contains ".claude/commands/retrospect.md" "/review" "retrospect explains next review reads lessons"
check_contains ".claude/commands/retrospect.md" "future result-report" "retrospect mentions future result-report"
check_contains ".claude/commands/retrospect.md" "未実装" "retrospect states result-report submission not implemented"
check_contains ".claude/commands/retrospect.md" "作成者は顧客本人" "retrospect customer author guardrail"
check_contains ".claude/commands/retrospect.md" "行政書士法" "retrospect legal guardrail"
check_contains ".claude/commands/retrospect.md" "[要確認]" "retrospect unknown facts marker"

check_file "knowledge/README.md" 2500
check_contains "knowledge/README.md" "育成層" "knowledge README explains growth layer"
check_contains "knowledge/README.md" "knowledge/records/" "knowledge README documents records"
check_contains "knowledge/README.md" "knowledge/lessons/" "knowledge README documents lessons"
check_contains "knowledge/README.md" "schemas/application-record.schema.json" "knowledge README references application-record schema"
check_contains "knowledge/README.md" "ユーザーの資産" "knowledge README user asset"
check_contains "knowledge/README.md" "コミット" "knowledge README committed asset"
check_contains "knowledge/README.md" "コア更新では触れません" "knowledge README core updates do not touch"
check_contains "knowledge/README.md" "/draft-section" "knowledge README draft-section reads lessons"
check_contains "knowledge/README.md" "/review" "knowledge README review reads lessons"
check_contains "knowledge/README.md" "result-report" "knowledge README future result-report"
check_contains "knowledge/README.md" "未実装" "knowledge README result-report not implemented"
check_contains "knowledge/README.md" "作成者は顧客本人" "knowledge README customer author guardrail"
check_contains "knowledge/README.md" "行政書士法" "knowledge README legal guardrail"
check_contains "knowledge/README.md" "[要確認]" "knowledge README unknown facts marker"

check_file "knowledge/records/.gitkeep" 1
check_file "knowledge/lessons/.gitkeep" 1

if printf '%s\n' knowledge/README.md knowledge/records/.gitkeep knowledge/lessons/.gitkeep | git check-ignore --stdin >/dev/null; then
  bad "knowledge/ must not be gitignored"
else
  ok
fi

check_contains "docs/manual.md" "/retrospect" "manual references retrospect"
no_placeholder ".claude/commands/retrospect.md"
no_placeholder "knowledge/README.md"
no_placeholder "docs/manual.md"

# Wave: cmd-intake-json-profile
check_contains ".claude/commands/intake.md" "input/company-profile.json" "intake writes company-profile JSON SSoT"
check_contains ".claude/commands/intake.md" "機械照合の正本" "intake identifies JSON as machine-matchable source of truth"
check_contains ".claude/commands/intake.md" "人間可読ビュー" "intake identifies md as human-readable view"
check_contains ".claude/commands/intake.md" "entity_type" "intake JSON includes entity_type"
check_contains ".claude/commands/intake.md" "industry_class" "intake JSON includes industry_class"
check_contains ".claude/commands/intake.md" "商業・サービス業" "intake industry_class commercial/service option"
check_contains ".claude/commands/intake.md" "宿泊・娯楽" "intake industry_class lodging/entertainment option"
check_contains ".claude/commands/intake.md" "製造業その他" "intake industry_class manufacturing/other option"
check_contains ".claude/commands/intake.md" "taxable_income_avg_3y" "intake JSON includes taxable income average"
check_contains ".claude/commands/intake.md" "past_adoption_unreported" "intake JSON includes unreported past adoption"
check_contains ".claude/commands/intake.md" "concurrent_applications" "intake JSON includes concurrent applications"
check_contains ".claude/commands/intake.md" "certifications" "intake JSON includes certifications"
check_contains ".claude/commands/intake.md" "plans" "intake JSON includes plans"
check_contains ".claude/commands/intake.md" "input/current-application.json" "intake reads current application"
check_contains ".claude/commands/intake.md" "state=spec_confirmed" "intake requires spec_confirmed current application state"
check_contains ".claude/commands/intake.md" "state=intake_done" "intake updates current application to intake_done"
check_contains ".claude/commands/intake.md" "入力は顧客の実情報" "intake retains customer-data guardrail after JSON refactor"
check_contains ".claude/commands/intake.md" "AIは整理のみ" "intake retains AI-only-organizes guardrail after JSON refactor"
check_contains ".claude/commands/intake.md" "公開リポジトリへコミットしない" "intake retains confidentiality guardrail after JSON refactor"
no_placeholder ".claude/commands/intake.md"

# Wave: cmd-subsidy-fit-spec
check_contains ".claude/commands/subsidy-fit.md" "input/company-profile.json" "subsidy-fit requires company-profile JSON"
check_contains ".claude/commands/subsidy-fit.md" "input/current-application.json" "subsidy-fit reads current application"
check_contains ".claude/commands/subsidy-fit.md" "current-application.json" "subsidy-fit mentions current-application.json"
check_contains ".claude/commands/subsidy-fit.md" "input/spec/" "subsidy-fit prefers input spec"
check_contains ".claude/commands/subsidy-fit.md" "specs/" "subsidy-fit falls back to bundled specs"
check_contains ".claude/commands/subsidy-fit.md" "spec を読み込み" "subsidy-fit reads spec as source"
check_contains ".claude/commands/subsidy-fit.md" "status" "subsidy-fit checks spec status"
check_contains ".claude/commands/subsidy-fit.md" "confirmed" "subsidy-fit requires confirmed spec"
check_contains ".claude/commands/subsidy-fit.md" "state=intake_done" "subsidy-fit requires intake_done state"
check_contains ".claude/commands/subsidy-fit.md" "eligibility.rules[]" "subsidy-fit drives matching from rules"
check_contains ".claude/commands/subsidy-fit.md" "kind=exclude" "subsidy-fit maps exclude rules"
check_contains ".claude/commands/subsidy-fit.md" "kind=mandatory" "subsidy-fit maps mandatory rules"
check_contains ".claude/commands/subsidy-fit.md" "kind=scoring" "subsidy-fit maps scoring rules"
check_contains ".claude/commands/subsidy-fit.md" "python3 tools/lib/predicate.py" "subsidy-fit runs predicate evaluator"
check_contains ".claude/commands/subsidy-fit.md" "predicate.py" "subsidy-fit mentions predicate.py"
check_contains ".claude/commands/subsidy-fit.md" "true" "subsidy-fit documents true result"
check_contains ".claude/commands/subsidy-fit.md" "false" "subsidy-fit documents false result"
check_contains ".claude/commands/subsidy-fit.md" "unknown" "subsidy-fit documents unknown result"
check_contains ".claude/commands/subsidy-fit.md" "source_clauses" "subsidy-fit quotes source clauses"
check_contains ".claude/commands/subsidy-fit.md" "clauses[].text" "subsidy-fit quotes clause text"
check_contains ".claude/commands/subsidy-fit.md" "採択可能性" "subsidy-fit does not assert acceptance probability"
check_contains ".claude/commands/subsidy-fit.md" "funding.add_ons[]" "subsidy-fit reads funding add-ons"
check_contains ".claude/commands/subsidy-fit.md" "add_ons[].required_rules" "subsidy-fit honors add-on required rules"
check_contains ".claude/commands/subsidy-fit.md" "funding.combinations[]" "subsidy-fit honors combination caps"
check_contains ".claude/commands/subsidy-fit.md" "chosen_funding" "subsidy-fit records chosen funding"
check_contains ".claude/commands/subsidy-fit.md" '"base": true' "subsidy-fit chosen funding base"
check_contains ".claude/commands/subsidy-fit.md" "addon_ids" "subsidy-fit chosen funding add-ons"
check_contains ".claude/commands/subsidy-fit.md" "state" "subsidy-fit updates application state"
check_contains ".claude/commands/subsidy-fit.md" "fit_done" "subsidy-fit sets fit_done state"
check_contains ".claude/commands/subsidy-fit.md" "input/subsidy-fit.md" "subsidy-fit writes fit memo"
check_contains ".claude/commands/subsidy-fit.md" "/ingest-guidelines" "subsidy-fit routes missing spec to ingest"
check_contains ".claude/commands/subsidy-fit.md" "/plan-deliverables" "subsidy-fit routes next step to plan-deliverables"
check_contains ".claude/commands/subsidy-fit.md" "作成者は顧客本人" "subsidy-fit retains customer author guardrail"
check_contains ".claude/commands/subsidy-fit.md" "行政書士法" "subsidy-fit retains legal guardrail"
check_contains ".claude/commands/subsidy-fit.md" "要件・数値は募集要項が正" "subsidy-fit retains official requirements priority"
check_contains ".claude/commands/subsidy-fit.md" "[要確認]" "subsidy-fit retains unknown facts marker"
no_placeholder ".claude/commands/subsidy-fit.md"

# Wave: cmd-draft-section-spec
check_contains ".claude/commands/draft-section.md" "input/current-application.json" "draft-section reads current application"
check_contains ".claude/commands/draft-section.md" "current-application.json" "draft-section mentions current-application.json"
check_contains ".claude/commands/draft-section.md" "state=planned" "draft-section routes unplanned state"
check_contains ".claude/commands/draft-section.md" "/plan-deliverables" "draft-section routes to plan-deliverables"
check_contains ".claude/commands/draft-section.md" "spec_path" "draft-section uses spec path"
check_contains ".claude/commands/draft-section.md" "produced_by=ai_draftable" "draft-section filters AI draftable deliverables"
check_contains ".claude/commands/draft-section.md" "deliverables[]" "draft-section reads spec deliverables"
check_contains ".claude/commands/draft-section.md" "sections[]" "draft-section reads spec sections"
check_contains ".claude/commands/draft-section.md" "review_criteria" "draft-section quotes review criteria"
check_contains ".claude/commands/draft-section.md" "input/drafts/" "draft-section writes drafts directory"
check_contains ".claude/commands/draft-section.md" "input/drafts/<subsidy_id>/<section_id>.md" "draft-section deterministic draft path"
check_contains ".claude/commands/draft-section.md" "## 叩き台" "draft-section uses counted draft body heading"
check_contains ".claude/commands/draft-section.md" "deliverable_id" "draft-section frontmatter deliverable id"
check_contains ".claude/commands/draft-section.md" "section_id" "draft-section frontmatter section id"
check_contains ".claude/commands/draft-section.md" "drafted_at" "draft-section frontmatter drafted timestamp"
check_contains ".claude/commands/draft-section.md" "knowledge/lessons/" "draft-section reads lessons"
check_contains ".claude/commands/draft-section.md" "state" "draft-section updates application state"
check_contains ".claude/commands/draft-section.md" "drafting" "draft-section sets drafting state"
check_contains ".claude/commands/draft-section.md" "bash tools/check-spec.sh" "draft-section can check confirmed spec"
check_contains ".claude/commands/draft-section.md" "/verify" "draft-section routes next to verify"
check_contains ".claude/commands/draft-section.md" "これは叩き台、確定は顧客本人" "draft-section retains draft guardrail after spec refactor"
check_contains ".claude/commands/draft-section.md" "数値根拠なき主張は [要確認]" "draft-section retains evidence guardrail after spec refactor"
no_placeholder ".claude/commands/draft-section.md"

# Wave: cmd-review-refocus
check_contains ".claude/commands/review.md" "/verify" "review routes mechanical checks to verify"
check_contains ".claude/commands/review.md" "字数・網羅・参照整合" "review separates mechanical draft checks"
check_contains ".claude/commands/review.md" "clause_id" "review requires clause ids for guideline judgments"
check_contains ".claude/commands/review.md" "quoted_text" "review requires quoted text for clause verification"
check_contains ".claude/commands/review.md" "clauses[].text" "review verifies against spec clause text"
check_contains ".claude/commands/review.md" "完全一致の部分文字列" "review requires exact substring quotes"
check_contains ".claude/commands/review.md" "NFKC" "review documents normalization before quote matching"
check_contains ".claude/commands/review.md" "捏造リスク" "review flags unlocatable quotes as fabrication risk"
check_contains ".claude/commands/review.md" "定性レビュー" "review is qualitative"
check_contains ".claude/commands/review.md" "input/reviews/" "review keeps output in reviews directory"
no_placeholder ".claude/commands/review.md"

# Wave: cmd-finalize-verify-gate
check_contains ".claude/commands/finalize.md" "input/checks/verify-report.md" "finalize requires verify report"
check_contains ".claude/commands/finalize.md" "verify-report.md" "finalize mentions verify report"
check_contains ".claude/commands/finalize.md" "spec_check=green" "finalize requires green spec check"
check_contains ".claude/commands/finalize.md" "draft_check=green" "finalize requires green draft check"
check_contains ".claude/commands/finalize.md" "draft_bodies_sha256" "finalize checks draft body hash"
check_contains ".claude/commands/finalize.md" "最新 draft" "finalize prevents stale draft checks"
check_contains ".claude/commands/finalize.md" "再計算" "finalize recomputes draft hash"
check_contains ".claude/commands/finalize.md" "/verify" "finalize routes stale checks to verify"
check_contains ".claude/commands/finalize.md" "input/current-application.json" "finalize reads current application"
check_contains ".claude/commands/finalize.md" "state=finalized" "finalize sets finalized state"
check_contains ".claude/commands/finalize.md" "input/deliverables.md" "finalize uses deliverables view"
check_contains ".claude/commands/finalize.md" "AIと作る成果物の最終確認" "finalize checks AI deliverables"
check_contains ".claude/commands/finalize.md" "人がやること消し込み" "finalize checks human task completion"
check_contains ".claude/commands/finalize.md" "hard 締切" "finalize checks hard deadlines"
check_contains "docs/manual.md" "draft_bodies_sha256" "manual finalize explains draft hash gate"
no_placeholder ".claude/commands/finalize.md"
no_placeholder "docs/manual.md"

# Wave: cmd-setup-start-refresh
check_contains ".claude/commands/setup.md" "python3" "setup checks python3 availability"
check_contains ".claude/commands/setup.md" "python3 --version" "setup runs python3 version self-check"
check_contains ".claude/commands/setup.md" "tools/check-*.sh" "setup explains python3 powers check scripts"
check_contains ".claude/commands/setup.md" "公式インストーラー" "setup points missing python3 to official installer"
check_contains ".claude/commands/start.md" "/ingest-guidelines" "start references ingest-guidelines flow"
check_contains ".claude/commands/start.md" "/plan-deliverables" "start references plan-deliverables flow"
check_contains ".claude/commands/start.md" "/verify" "start references verify flow"
check_contains ".claude/commands/start.md" "/retrospect" "start references retrospect flow"
check_contains ".claude/commands/start.md" "input/current-application.json" "start references current application state file"
check_contains ".claude/commands/start.md" "specs/" "start references bundled specs entry"
check_contains ".claude/commands/start.md" "育成層" "start explains growth layer"
check_contains ".claude/commands/start.md" "knowledge/" "start references knowledge directory"
check_contains ".claude/commands/start.md" "my-*" "start references my-* commands"
no_placeholder ".claude/commands/setup.md"
no_placeholder ".claude/commands/start.md"

# Wave: two-layer-update-core
check_file "core-manifest.json" 1000
check_json "core-manifest.json"
check_contains "core-manifest.json" "\"tools/validate.sh\"" "core manifest includes validate"

if VALIDATE_INTERNAL_ONLY_PATHS="${INTERNAL_ONLY_PATHS[*]}" python3 - <<'PY'
import json
import os
import pathlib
import sys

root = pathlib.Path(".")
internal_only = os.environ.get("VALIDATE_INTERNAL_ONLY_PATHS", "").split()
manifest = json.loads(pathlib.Path("core-manifest.json").read_text(encoding="utf-8"))
errors = []

def is_internal_only(rel):
    for entry in internal_only:
        if rel == entry or rel.startswith(f"{entry}/"):
            return True
    return False

paths = manifest.get("core_paths")
if "manifest_version" not in manifest:
    errors.append("manifest_version missing")
if not isinstance(paths, list) or not paths:
    errors.append("core_paths must be a non-empty array")
    paths = []

seen = set()
for raw in paths:
    if not isinstance(raw, str):
        errors.append(f"non-string core path: {raw!r}")
        continue
    rel = raw
    pure = pathlib.PurePosixPath(rel)
    if not rel or rel.strip() != rel:
        errors.append(f"invalid whitespace in core path: {rel!r}")
    if "\\" in rel:
        errors.append(f"backslash in core path: {rel}")
    if pure.is_absolute() or any(part in ("", ".", "..") for part in pure.parts):
        errors.append(f"core path must be normalized relative path: {rel}")
    if any(ch in rel for ch in "*?[]"):
        errors.append(f"glob syntax in core path: {rel}")
    if rel.startswith("input/") or rel == "input":
        errors.append(f"input path must not be core: {rel}")
    if rel.startswith("knowledge/") or rel == "knowledge":
        errors.append(f"knowledge path must not be core: {rel}")
    if is_internal_only(rel):
        errors.append(f"internal-only path must not be core: {rel}")
    if rel.startswith(".claude/commands/my-") or "/my-" in rel:
        errors.append(f"my-* command path must not be core: {rel}")
    if rel == ".update-core-state.json":
        errors.append(".update-core-state.json must not be core")
    if rel in seen:
        errors.append(f"duplicate core path: {rel}")
    seen.add(rel)
    path = root / rel
    if not path.is_file():
        errors.append(f"core path is not an existing regular file: {rel}")

expected = set()
for base in (".claude/commands", "schemas", "specs", "tools", "templates", "docs"):
    for path in (root / base).rglob("*"):
        if not path.is_file():
            continue
        if "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        rel = path.as_posix()
        if is_internal_only(rel):
            continue
        if rel.startswith(".claude/commands/my-"):
            continue
        expected.add(rel)
expected.update({
    ".gitattributes",
    "AGENTS.md",
    "CLAUDE.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "LICENSE",
    "NOTICE",
    "ROADMAP.md",
    "README.md",
    "SECURITY.md",
    "TERMS.md",
    "TRADEMARK.md",
    "core-manifest.json",
})

for rel in sorted(expected - seen):
    errors.append(f"core manifest missing current core file: {rel}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok
else
  bad "core-manifest.json core_paths invalid"
fi

check_file "tools/update-core.sh" 400
check_file "tools/lib/update_core.py" 8000
check_file "tools/test-update-core.sh" 5000
check_contains "tools/update-core.sh" "--dry-run" "update-core documents dry-run"
check_contains "tools/update-core.sh" "--apply" "update-core documents apply"
check_contains "tools/lib/update_core.py" "user-modified" "update-core implements user-modified status"
check_contains "tools/lib/update_core.py" ".update-core-state.json" "update-core stores previous state"
check_contains "tools/test-update-core.sh" "--dry-run" "update-core test exercises dry-run"
check_contains "tools/test-update-core.sh" "--apply" "update-core test exercises apply"
check_contains "tools/test-update-core.sh" "user-modified" "update-core test exercises user modified skip"

if [ "${SAITA_UPDATE_CORE_NESTED_VALIDATE:-0}" = "1" ]; then
  ok
elif bash tools/test-update-core.sh >/dev/null; then
  ok
else
  bad "tools/test-update-core.sh failed"
fi

no_placeholder "core-manifest.json"
no_placeholder "tools/update-core.sh"
no_placeholder "tools/lib/update_core.py"
no_placeholder "tools/test-update-core.sh"
no_placeholder "docs/manual.md"

# Wave: docs-growing-guide-and-manual
check_file "docs/ハーネスの育て方.md" 3000
check_contains "docs/ハーネスの育て方.md" "core-manifest.json" "growing guide explains core manifest"
check_contains "docs/ハーネスの育て方.md" "update-core.sh" "growing guide explains update-core"
check_contains "docs/ハーネスの育て方.md" "my-" "growing guide explains my-* commands"
check_contains "docs/ハーネスの育て方.md" "knowledge/" "growing guide explains knowledge layer"
check_contains "docs/ハーネスの育て方.md" "育成層" "growing guide explains growth layer"
check_contains "docs/ハーネスの育て方.md" "dry-run" "growing guide explains dry-run before apply"

check_contains "docs/manual.md" "/ingest-guidelines" "manual includes ingest-guidelines in new flow"
check_contains "docs/manual.md" "/plan-deliverables" "manual includes plan-deliverables in new flow"
check_contains "docs/manual.md" "/verify" "manual includes verify in new flow"
check_contains "docs/manual.md" "/retrospect" "manual includes retrospect in new flow"
check_contains "docs/manual.md" "入口A" "manual explains entry A"
check_contains "docs/manual.md" "入口B" "manual explains entry B"
check_contains "docs/manual.md" "current-application.json" "manual explains current application state"
check_contains "docs/manual.md" "docs/ハーネスの育て方.md" "manual references growing guide"

check_contains "README.md" "ingest-guidelines" "README mentions ingest-guidelines"
check_contains "README.md" "retrospect" "README mentions retrospect"
check_contains "README.md" "schemas/" "README mentions schemas"
check_contains "README.md" "specs/" "README mentions specs"
check_contains "README.md" "knowledge/" "README mentions knowledge"
check_contains "README.md" "core-manifest.json" "README mentions core manifest"

check_contains "docs/faq.md" "spec とは何か" "FAQ explains spec"
check_contains "docs/faq.md" "confirmation" "FAQ explains confirmation"
check_contains "docs/faq.md" "current-application.json" "FAQ explains current application"
check_contains "docs/faq.md" "update-core" "FAQ explains update-core"
check_contains "docs/faq.md" "knowledge/" "FAQ explains knowledge"

check_contains "templates/補助金要件マッピング.md" "JSON spec が機械照合の正本" "requirement mapping positions spec as machine SSoT"
check_contains "templates/補助金要件マッピング.md" "spec field" "requirement mapping maps spec fields"

check_relative_links "README.md"
check_relative_links "docs/manual.md"
check_relative_links "docs/faq.md"
no_placeholder "docs/ハーネスの育て方.md"

# Wave: worked-example-v2
check_file "examples/worked-example/pack/spec.sample.json" 4000
check_file "examples/worked-example/pack/spec.sample.confirmation.json" 500
check_file "examples/worked-example/current-application.sample.json" 300
check_file "examples/worked-example/drafts-sample/current-challenge.md" 100
check_file "examples/worked-example/drafts-sample/short-summary.md" 100
check_file "examples/worked-example/verify-report.sample.md" 1000
check_file "examples/worked-example/record.sample.json" 500

for json_file in \
  examples/worked-example/pack/spec.sample.json \
  examples/worked-example/pack/spec.sample.confirmation.json \
  examples/worked-example/current-application.sample.json \
  examples/worked-example/record.sample.json; do
  check_json "$json_file"
done

check_contains "examples/worked-example/pack/spec.sample.json" '"schema_version": "2.0"' "worked example spec v2 schema version"
check_contains "examples/worked-example/pack/spec.sample.json" '"status": "confirmed"' "worked example spec confirmed status"
check_contains "examples/worked-example/pack/spec.sample.json" '"event_kind": "application_deadline"' "worked example spec application deadline"
check_contains "examples/worked-example/pack/spec.sample.json" '"max_chars": 30' "worked example spec includes 30-char section"
check_contains "examples/worked-example/pack/spec.sample.json" '"predicate"' "worked example spec includes predicate"
check_contains "examples/worked-example/pack/spec.sample.json" '"deliverable_id": "plan-doc"' "worked example spec plan deliverable"
check_contains "examples/worked-example/pack/spec.sample.json" '"deliverable_id": "estimate-attachment"' "worked example spec attachment deliverable"
check_contains "examples/worked-example/pack/spec.sample.confirmation.json" "spec_sha256" "worked example confirmation pins spec sha"
check_contains "examples/worked-example/pack/spec.sample.confirmation.json" '"state": "confirmed"' "worked example confirmation items confirmed"
check_spec_confirmation_binding "examples/worked-example/pack/spec.sample.json" "examples/worked-example/pack/spec.sample.confirmation.json"

check_contains "examples/worked-example/current-application.sample.json" '"state": "verified"' "worked example current application verified"
check_contains "examples/worked-example/current-application.sample.json" '"chosen_funding"' "worked example current application chosen funding"
check_contains "examples/worked-example/current-application.sample.json" "draft_bodies_sha256" "worked example current application draft hash"
check_contains "examples/worked-example/drafts-sample/current-challenge.md" "deliverable_id: plan-doc" "worked example draft frontmatter deliverable"
check_contains "examples/worked-example/drafts-sample/current-challenge.md" "section_id: current-challenge" "worked example current-challenge section id"
check_contains "examples/worked-example/drafts-sample/current-challenge.md" "## 叩き台" "worked example current-challenge draft body"
check_contains "examples/worked-example/drafts-sample/short-summary.md" "section_id: short-summary" "worked example short-summary section id"
check_contains "examples/worked-example/drafts-sample/short-summary.md" "## 叩き台" "worked example short-summary draft body"

check_contains "examples/worked-example/verify-report.sample.md" '```json' "worked example verify report fenced json header"
check_contains "examples/worked-example/verify-report.sample.md" '"spec_check": "green"' "worked example verify report green spec"
check_contains "examples/worked-example/verify-report.sample.md" '"draft_check": "green"' "worked example verify report green drafts"
check_contains "examples/worked-example/verify-report.sample.md" "draft_bodies_sha256" "worked example verify report draft hash"
check_contains "examples/worked-example/record.sample.json" '"result": "pending"' "worked example record pending result"
check_contains "examples/worked-example/record.sample.json" '"lessons"' "worked example record lessons"
check_contains "examples/worked-example/README.md" "/retrospect" "worked example README mentions retrospect"
check_contains "examples/worked-example/README.md" "spec.sample.json" "worked example README mentions sample spec"
check_contains "examples/worked-example/README.md" "verify-report.sample.md" "worked example README mentions verify report"

if bash tools/check-spec.sh examples/worked-example/pack/spec.sample.json >/dev/null 2>&1; then
  ok
else
  bad "tools/check-spec.sh must pass on examples/worked-example/pack/spec.sample.json"
fi

if bash tools/check-drafts.sh examples/worked-example/pack/spec.sample.json examples/worked-example/drafts-sample >/dev/null 2>&1; then
  ok
else
  bad "tools/check-drafts.sh must pass on examples/worked-example/drafts-sample"
fi

if actual_worked_hash="$(bash tools/draft-hash.sh examples/worked-example/pack/spec.sample.json examples/worked-example/drafts-sample 2>/dev/null)" && python3 - "$actual_worked_hash" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(".")
actual = sys.argv[1]
app = json.loads((root / "examples/worked-example/current-application.sample.json").read_text(encoding="utf-8"))
report_text = (root / "examples/worked-example/verify-report.sample.md").read_text(encoding="utf-8")
match = re.match(r"\A```json\n(.*?)\n```\n", report_text, re.S)
if not match:
    print("verify report must start with fenced json", file=sys.stderr)
    raise SystemExit(1)
report = json.loads(match.group(1))

if app.get("draft_bodies_sha256") != actual or report.get("draft_bodies_sha256") != actual:
    print("draft_bodies_sha256 mismatch across current application, report, and drafts", file=sys.stderr)
    raise SystemExit(1)
PY
then
  ok
else
  bad "worked example draft hash mismatch"
fi

for f in \
  examples/worked-example/README.md \
  examples/worked-example/pack/spec.sample.json \
  examples/worked-example/pack/spec.sample.confirmation.json \
  examples/worked-example/current-application.sample.json \
  examples/worked-example/drafts-sample/current-challenge.md \
  examples/worked-example/drafts-sample/short-summary.md \
  examples/worked-example/verify-report.sample.md \
  examples/worked-example/record.sample.json; do
  no_placeholder "$f"
done

# Wave: review3-fixes
check_contains "tools/lib/update_core.py" "previous_hash is None" "update-core first-run classifies unknown local differences as user-modified"
check_contains "tools/lib/update_core.py" "--force-file" "update-core warning explains force-file override"
check_contains "tools/test-update-core.sh" "FIRST-RUN" "update-core test covers first-run local edits"
check_contains "tools/test-update-core.sh" "WARN: skipped user-modified docs/manual.md" "update-core first-run skip assertion"

check_contains "tools/lib/check_spec.py" "required_confirmation_field_paths" "check-spec derives confirmation coverage paths"
check_contains "tools/lib/check_spec.py" "missing or empty source_clauses" "check-spec requires fact-bearing source clauses"
check_contains "tools/lib/check_spec.py" "validate_predicate" "check-spec validates predicate AST shape"
check_contains "tools/lib/check_spec.py" "unknown depends_on reference" "check-spec validates deliverable depends_on references"
check_contains "tools/lib/check_spec.py" "DOCUMENT_ID_RE" "check-spec uses schema-compatible document id pattern"
check_contains "tools/lib/predicate.py" "VALID_OPS" "predicate evaluator rejects invalid operators as unknown"
check_contains "tools/lib/predicate.py" "and items else UNKNOWN" "predicate evaluator treats empty all/any as unknown"
check_contains "tools/test-check-spec.sh" "assert_check_spec_fails_with" "check-spec tests assert expected substrings"
check_contains "tools/test-check-spec.sh" "not-unknown" "predicate Kleene not unknown test"
check_contains "tools/test-check-spec.sh" "predicate-invalid-empty-all" "predicate invalid AST fixture test"

for f in \
  tools/fixtures/spec/confirmation-missing-path.json \
  tools/fixtures/spec/confirmation-missing-path.confirmation.json \
  tools/fixtures/spec/source-clauses-empty.json \
  tools/fixtures/spec/bad-depends-on.json \
  tools/fixtures/spec/predicate-kleene.json \
  tools/fixtures/spec/predicate-invalid-empty-all.json \
  tools/fixtures/spec/predicate-invalid-empty-any.json \
  tools/fixtures/spec/predicate-invalid-missing-value.json; do
  check_file "$f" 100
  check_json "$f"
  no_placeholder "$f"
done

check_contains "tools/fixtures/spec/good-spec.confirmation.json" "deliverables.deliverable-1.sections.section-1.max_chars" "good spec confirmation covers section max chars"
check_contains "examples/worked-example/pack/spec.sample.confirmation.json" "funding.base_award" "worked example confirmation covers funding base"
check_contains "examples/worked-example/pack/spec.sample.confirmation.json" "deliverables.plan-doc.sections.current-challenge.max_chars" "worked example confirmation covers all limited sections"
check_contains "specs/jizokuka-20/jizokuka-20.confirmation.json" "mirasapo-guide" "jizokuka confirmation note explains mirasapo basis"
if grep -qF -- "status=draftの理由" "specs/jizokuka-20/jizokuka-20.confirmation.json"; then
  bad "jizokuka confirmation note must not describe confirmed spec as status=draft"
else
  ok
fi

check_contains ".claude/commands/verify.md" "spec_sha256" "verify report records spec hash"
check_contains ".claude/commands/verify.md" "spec_version" "verify report records spec version"
check_contains ".claude/commands/finalize.md" "spec_sha256" "finalize recomputes spec hash"
check_contains ".claude/commands/finalize.md" "bash tools/check-spec.sh <spec_path>" "finalize reruns check-spec on current spec"
check_contains "examples/worked-example/verify-report.sample.md" "spec_sha256" "worked example verify report records spec hash"
check_contains "examples/worked-example/verify-report.sample.md" "spec_version" "worked example verify report records spec version"

if [ "${SAITA_UPDATE_CORE_NESTED_VALIDATE:-0}" = "1" ]; then
  ok
elif bash tools/test-update-core.sh >/dev/null; then
  ok
else
  bad "tools/test-update-core.sh failed after review3 fixes"
fi

if bash tools/test-check-spec.sh >/dev/null; then
  ok
else
  bad "tools/test-check-spec.sh failed after review3 fixes"
fi

# Wave: e2e-fixes
check_file "tools/draft-hash.sh" 300
check_contains "core-manifest.json" "\"tools/draft-hash.sh\"" "core manifest includes draft-hash"
check_contains ".claude/commands/verify.md" "tools/draft-hash.sh" "verify uses draft-hash script"
check_contains ".claude/commands/finalize.md" "tools/draft-hash.sh" "finalize uses draft-hash script"
check_contains "tools/lib/check_drafts.py" "next same-level" "check-drafts stops body at next same-level heading"
check_contains "tools/lib/check_drafts.py" "draft_bodies_sha256" "check-drafts exposes shared draft hash"
check_contains "tools/fixtures/drafts/drafts-good/section-2.md" "## 顧客本人が確認・修正する点" "draft fixture covers post-body heading"
check_contains "tools/fixtures/spec/good-spec.json" "\"optional\": true" "good spec fixture includes optional section"
check_contains "tools/test-check-drafts.sh" "optional section" "check-drafts test covers optional section without WARN"
check_contains "schemas/subsidy-spec.schema.json" "\"optional\"" "schema supports optional section flag"
check_contains "specs/jizokuka-20/jizokuka-20.json" "\"optional\": true" "jizokuka optional section marked"
check_contains "specs/jizokuka-20/jizokuka-20.confirmation.json" "funding.combinations.invoice+wage-increase" "confirmation combination field path is id-based"
check_contains "tools/lib/check_spec.py" "unconfirmed required item" "check-spec reports open required confirmations clearly"
check_contains "tools/lib/check_spec.py" "invalid confirmation state" "check-spec still rejects unknown confirmation states"
check_contains ".claude/commands/ingest-guidelines.md" 'max_chars` または `max_pages` が `null` ではないセクション' "ingest confirmation guidance matches checker limited sections"
check_contains ".gitignore" "__pycache__/" "gitignore excludes python cache"

if draft_hash="$(bash tools/draft-hash.sh examples/worked-example/pack/spec.sample.json examples/worked-example/drafts-sample 2>/dev/null)" && [[ "$draft_hash" =~ ^[0-9a-f]{64}$ ]]; then
  ok
else
  bad "tools/draft-hash.sh must output one 64-hex hash on worked example"
fi

if spec_output="$(bash tools/check-spec.sh tools/fixtures/spec/good-spec.json 2>&1)" && printf '%s\n' "$spec_output" | grep -q '^OK:'; then
  ok
else
  bad "tools/check-spec.sh green output must include OK"
fi

if drafts_output="$(bash tools/check-drafts.sh tools/fixtures/spec/good-spec.json tools/fixtures/drafts/drafts-good 2>&1)" && printf '%s\n' "$drafts_output" | grep -q '^OK:' && ! printf '%s\n' "$drafts_output" | grep -q '^WARN:'; then
  ok
else
  bad "tools/check-drafts.sh green output must include OK and skip optional-section WARN"
fi

# Wave: flow-reorder-core
check_file ".claude/commands/select-subsidy.md" 3000

if [ "$(sed -n '1p' ".claude/commands/select-subsidy.md")" = "---" ] &&
   sed -n '2,/^---$/p' ".claude/commands/select-subsidy.md" | grep -q '^description:'; then
  ok
else
  bad ".claude/commands/select-subsidy.md missing YAML frontmatter description"
fi

check_contains ".claude/commands/select-subsidy.md" "specs/<id>.json" "select-subsidy selects bundled spec path"
check_contains ".claude/commands/select-subsidy.md" "input/current-application.json" "select-subsidy writes current application"
check_contains ".claude/commands/select-subsidy.md" "state=spec_confirmed" "select-subsidy initializes spec_confirmed"
check_contains ".claude/commands/select-subsidy.md" '"chosen_funding": null' "select-subsidy leaves chosen funding null"
check_contains ".claude/commands/select-subsidy.md" "/intake" "select-subsidy routes next to intake"
check_contains ".claude/commands/select-subsidy.md" "作成者は顧客本人" "select-subsidy customer author guardrail"
check_contains ".claude/commands/select-subsidy.md" "行政書士法" "select-subsidy legal guardrail"
check_contains ".claude/commands/select-subsidy.md" "[要確認]" "select-subsidy unknown facts marker"

check_contains ".claude/commands/intake.md" "spec 駆動" "intake describes spec-driven hearing"
check_contains ".claude/commands/intake.md" "confirmed spec を読み込み" "intake instructs reading confirmed spec"
check_contains ".claude/commands/intake.md" "eligibility.rules[]" "intake prioritizes rules-driven company facts"
check_contains ".claude/commands/intake.md" "scope=profile" "intake prioritizes profile predicate keys"
check_contains ".claude/commands/intake.md" "kind=scoring" "intake prioritizes scoring items"
check_contains ".claude/commands/intake.md" "選択済み補助金の spec エコー" "intake replaces subsidy-field section with spec echo"
check_contains ".claude/commands/intake.md" "state=spec_confirmed" "intake precondition is spec_confirmed"
check_contains ".claude/commands/intake.md" "intake_done" "intake writes intake_done state"
check_contains ".claude/commands/intake.md" "/select-subsidy" "intake routes missing bundled spec selection"

check_contains ".claude/commands/ingest-guidelines.md" '次の作業は `/confirm-spec`' "ingest next command is confirm-spec"
check_contains ".claude/commands/ingest-guidelines.md" '会社プロフィールはこの後の `/intake`' "ingest no longer recommends intake before spec"
check_contains ".claude/commands/subsidy-fit.md" "state=intake_done" "subsidy-fit precondition is intake_done"
check_contains ".claude/commands/plan-deliverables.md" "state=intake_done" "plan-deliverables routes intake_done to subsidy-fit"
check_contains ".claude/commands/draft-section.md" "state=intake_done" "draft-section routes intake_done to subsidy-fit and planning"
check_contains ".claude/commands/verify.md" "/select-subsidy" "verify routes missing current application to select-subsidy"
check_contains ".claude/commands/finalize.md" "/select-subsidy" "finalize routes missing current application to select-subsidy"
check_contains ".claude/commands/retrospect.md" "state=spec_confirmed" "retrospect documents new first state for next applications"

check_contains "docs/manual.md" "/select-subsidy" "manual references select-subsidy"
check_contains "docs/manual.md" "spec_draft → spec_confirmed → intake_done → fit_done → planned → drafting → verified → finalized" "manual includes spec_draft state flow"
check_contains "core-manifest.json" "\".claude/commands/select-subsidy.md\"" "core manifest includes select-subsidy"

no_placeholder ".claude/commands/select-subsidy.md"
no_placeholder ".claude/commands/intake.md"
no_placeholder ".claude/commands/ingest-guidelines.md"
no_placeholder "templates/intake-questionnaire.md"
no_placeholder "docs/manual.md"

# Wave: flow-reorder-docs
check_in_order "README.md" "README quickstart uses spec-first flow" \
  '入口A: `/select-subsidy`' \
  '入口B: `/ingest-guidelines`' \
  '→ `/confirm-spec`' \
  '→ `/build-pack`' \
  '→ `/intake`' \
  '→ `/subsidy-fit`' \
  '→ `/plan-deliverables`' \
  '→ `/draft-section`' \
  '→ `/review`' \
  '→ `/verify`' \
  '→ `/finalize`' \
  '→ `/retrospect`'

check_in_order "README.md" "README flow table uses spec-first flow" \
  '| `/start`' \
  '| 入口A: `/select-subsidy`' \
  '| 入口B: `/ingest-guidelines`' \
  '| `/confirm-spec`' \
  '| `/build-pack`' \
  '| `/intake`' \
  '| `/subsidy-fit`' \
  '| `/plan-deliverables`' \
  '| `/draft-section`' \
  '| `/review`' \
  '| `/verify`' \
  '| `/finalize`' \
  '| `/retrospect`'

check_in_order "CLAUDE.md" "CLAUDE workflow uses spec-first flow" \
  '2. `/start`' \
  '3. `/select-subsidy` または `/ingest-guidelines`' \
  '4. `/confirm-spec`' \
  '5. `/build-pack`' \
  '6. `/intake`' \
  '7. `/subsidy-fit`' \
  '8. `/plan-deliverables`' \
  '9. `/draft-section`' \
  '10. `/review`' \
  '11. `/verify`' \
  '12. `/finalize`' \
  '13. `/retrospect`'

check_in_order "docs/manual.md" "manual table uses spec-first flow" \
  '| 0A | 入口A: `/select-subsidy`' \
  '| 0B | 入口B: `/ingest-guidelines`' \
  '| 0C | `/confirm-spec`' \
  '| 0D | `/build-pack`' \
  '| 1 | `/intake`' \
  '| 2 | `/subsidy-fit`' \
  '| 3 | `/plan-deliverables`' \
  '| 4 | `/draft-section`' \
  '| 5 | `/review`' \
  '| 6 | `/verify`' \
  '| 7 | `/finalize`' \
  '| 8 | `/retrospect`'

check_in_order "docs/manual.md" "manual command explanations use spec-first flow" \
  '### `/select-subsidy`' \
  '### `/ingest-guidelines`' \
  '### `/confirm-spec`' \
  '### `/build-pack`' \
  '### `/intake`' \
  '### `/subsidy-fit`' \
  '### `/plan-deliverables`' \
  '### `/draft-section`' \
  '### `/review`' \
  '### `/verify`' \
  '### `/finalize`' \
  '### `/retrospect`'

check_in_order "docs/faq.md" "FAQ command order uses spec-first flow" \
  '基本の順番は `/start` → 入口A: `/select-subsidy`、または 入口B: `/ingest-guidelines`' \
  '→ `/confirm-spec`' \
  '→ `/build-pack`' \
  '→ `/intake`' \
  '→ `/subsidy-fit`' \
  '→ `/plan-deliverables`' \
  '→ `/draft-section`' \
  '→ `/review`' \
  '→ `/verify`' \
  '→ `/finalize`' \
  '→ `/retrospect`'

check_in_order "docs/補助金の選び方.md" "subsidy-selection doc routes to spec before intake" \
  '`/select-subsidy`' \
  '`/ingest-guidelines`' \
  '`/confirm-spec`' \
  '`/build-pack`' \
  '`/intake`' \
  '`/subsidy-fit`'

check_in_order "docs/design/harness-ingest-loop.md" "design section 1 uses spec-first state transition" \
  '入口A: /select-subsidy' \
  '入口B: /ingest-guidelines' \
  'state=spec_draft' \
  '/confirm-spec ─' \
  'state=spec_confirmed' \
  '/build-pack ─' \
  '/intake ─' \
  'state=intake_done' \
  '/subsidy-fit'

check_in_order "docs/onboarding/00-はじめに.md" "onboarding overview uses spec-first flow" \
  '→ /start' \
  '入口A: /select-subsidy' \
  '入口B: /ingest-guidelines' \
  '→ /confirm-spec' \
  '→ /build-pack' \
  '→ /intake' \
  '→ /subsidy-fit' \
  '→ /plan-deliverables' \
  '→ /draft-section' \
  '→ /review' \
  '→ /verify' \
  '→ /finalize'

check_in_order "docs/テンプレートrepoの使い方.md" "template usage note uses spec-first flow" \
  '`/start`' \
  '`/select-subsidy`' \
  '`/ingest-guidelines`' \
  '`/confirm-spec`' \
  '`/build-pack`' \
  '`/intake`' \
  '`/subsidy-fit`' \
  '`/plan-deliverables`' \
  '`/draft-section`' \
  '`/review`' \
  '`/verify`' \
  '`/finalize`'

check_contains "README.md" "state=spec_confirmed" "README flow records spec_confirmed before intake"
check_contains "README.md" "state=intake_done" "README flow records intake_done after intake"
check_contains "docs/faq.md" "state=intake_done" "FAQ state list includes intake_done"
check_contains "docs/design/harness-ingest-loop.md" "state          spec_draft|spec_confirmed|intake_done|fit_done|planned|drafting|verified|finalized" "design current-application states use new order"
check_contains "docs/design/harness-ingest-loop.md" "spec_draft → spec_confirmed → intake_done → fit_done → planned → drafting → verified → finalized" "design state transition uses new order"

if grep -qF -- '基本の順番は `/start` → `/intake`' "docs/faq.md"; then
  bad "docs/faq.md still starts command order with /intake"
else
  ok
fi

if grep -qF -- '迷わなければ `/intake`' "README.md"; then
  bad "README.md still starts quickstart flow with /intake"
else
  ok
fi

if grep -qF -- '迷わなければ `/intake`' "docs/テンプレートrepoの使い方.md"; then
  bad "template usage note still starts flow with /intake"
else
  ok
fi

if grep -qF -- '注: 下記 §1 の図・状態遷移' "docs/design/harness-ingest-loop.md"; then
  bad "design doc still contains stale section-1 old-order note"
else
  ok
fi

# Wave: collaborator-residue-cleanup
check_contains "docs/collaborator-招待手順.md" '旧 `collaborator` 招待手順の置き換え' "retired collaborator guide is repurposed"
check_contains "docs/collaborator-招待手順.md" "非提出でも、ローカルで動く slash command" "result-report guide states core works without submission"
check_contains "docs/collaborator-招待手順.md" 'docs/governance/data-charter.md` §4-5' "result-report guide links charter sections"
check_contains "docs/collaborator-招待手順.md" 'TERMS.md` 第2条' "result-report guide links terms section 2"
check_contains "docs/licensing-tiers.md" "事業者直販" "licensing tiers direct business layer"
check_contains "docs/licensing-tiers.md" "支援者・B2B" "licensing tiers supporter B2B layer"
check_contains "docs/licensing-tiers.md" "提供側を利用者の private repo に共同作業者として招待することは利用条件ではありません" "licensing tiers rejects collaborator condition"
check_contains ".claude/commands/setup.md" '非提出を理由に `/start` への案内を止めない' "setup does not block on result-report non-submission"
check_contains "CLAUDE.md" "result-report 任意提出" "CLAUDE setup flow mentions result-report optional submission"
check_contains "docs/manual.md" "提供側を private repo に招待することは利用条件ではありません" "manual rejects collaborator condition"
check_contains "docs/onboarding/00-はじめに.md" "result-report 任意提出" "onboarding overview mentions result-report optional submission"
check_contains "docs/onboarding/01-githubアカウント作成.md" "提供側をあなたの private repo に共同作業者として招待することは利用条件ではありません" "GitHub onboarding rejects collaborator condition"
check_contains "docs/onboarding/03-このキットを自分のものにする.md" "result-report 任意提出" "repo onboarding mentions result-report optional submission"
check_contains "docs/改善ループ.md" "任意 result-report" "improvement loop uses optional result-report"

for f in \
  CLAUDE.md \
  docs/manual.md \
  docs/onboarding/00-はじめに.md \
  docs/onboarding/01-githubアカウント作成.md \
  docs/onboarding/03-このキットを自分のものにする.md \
  .claude/commands/setup.md \
  docs/licensing-tiers.md \
  docs/collaborator-招待手順.md; do
  if grep -qF -- "collaborator 招待確認" "$f" ||
     grep -qF -- "collaborator 未招待" "$f" ||
     grep -qF -- "collaborator 受入れ | **必須**" "$f" ||
     grep -qF -- "collaborator 受入れを利用条件" "$f" ||
     grep -qF -- "private repo の collaborator として招待していただきます" "$f"; then
    bad "$f still presents collaborator invite as a condition"
  else
    ok
  fi
done

# Wave: charter-artifacts-license-governance
check_contains "core-manifest.json" '"TRADEMARK.md"' "core manifest includes trademark policy"
check_contains "core-manifest.json" '"CONTRIBUTING.md"' "core manifest includes contributing guide"
check_contains "core-manifest.json" '"NOTICE"' "core manifest includes notice"
check_contains "core-manifest.json" '"docs/telemetry.md"' "core manifest includes telemetry disclosure"

check_file "TRADEMARK.md" 500
check_contains "TRADEMARK.md" "サイタくん" "trademark policy names Saita-kun"
check_contains "TRADEMARK.md" "商標" "trademark policy states trademark"
check_contains "TRADEMARK.md" "Apache-2.0" "trademark policy distinguishes Apache-2.0"
check_contains "TRADEMARK.md" "別レイヤー" "trademark policy separates license and trademark layers"

check_file "CONTRIBUTING.md" 500
check_contains "CONTRIBUTING.md" "DCO" "contributing guide requires DCO"
check_contains "CONTRIBUTING.md" "Signed-off-by" "contributing guide requires sign-off"
check_contains "CONTRIBUTING.md" "CLA" "contributing guide mentions CLA"
check_contains "CONTRIBUTING.md" "採用しません" "contributing guide rejects CLA"

check_file "NOTICE" 80
check_contains "NOTICE" "サイタくん (saita-kun-planner)" "notice names product"
check_contains "NOTICE" "日本補助金支援機構株式会社" "notice names copyright holder"
check_contains "NOTICE" "TRADEMARK.md" "notice references trademark policy"

check_file "docs/telemetry.md" 1000
check_contains "docs/telemetry.md" "任意" "telemetry disclosure states optional submission"
check_contains "docs/telemetry.md" "allowlist に相当する収集項目" "telemetry disclosure states allowlist"
check_contains "docs/telemetry.md" "何を集めないか（denylist）" "telemetry disclosure states denylist"
check_contains "docs/telemetry.md" "削除" "telemetry disclosure covers deletion"
check_contains "docs/telemetry.md" "consent" "telemetry disclosure covers consent"

check_contains "README.md" "TRADEMARK.md" "README deliverables include trademark policy"
check_contains "README.md" "CONTRIBUTING.md" "README deliverables include contributing guide"
check_contains "README.md" "NOTICE" "README deliverables include notice"
check_contains "README.md" "docs/telemetry.md" "README deliverables include telemetry disclosure"
check_contains "TERMS.md" '配布ライセンス（コード・テンプレの使用許諾）は `LICENSE` を参照' "TERMS keeps license pointer"

# Wave: reference-and-contradiction-pass
reference_scan_fail=0
for forbidden_ref in "docs/strategy/" "pivot-decision" "wave-plans" "harness-backlog"; do
  hits=$(grep -RFn --exclude='public-release-plan.md' -- "$forbidden_ref" docs README.md TERMS.md 2>/dev/null || true)
  if [ "$VALIDATE_INTERNAL_MODE" = "1" ] && [ -n "$hits" ]; then
    filtered_hits=""
    while IFS= read -r hit_line; do
      [ -n "$hit_line" ] || continue
      hit_path="${hit_line%%:*}"
      if ! is_internal_only_path "$hit_path"; then
        filtered_hits="${filtered_hits}${hit_line}"$'\n'
      fi
    done <<< "$hits"
    hits="${filtered_hits%$'\n'}"
  fi
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    reference_scan_fail=1
  fi
done
if [ "$reference_scan_fail" = "0" ]; then
  ok
else
  bad "public docs still reference removed internal planning documents"
fi

check_contains "TERMS.md" "result-report は任意提出です" "terms states result-report optionality"
check_contains "TERMS.md" "非提出でも、中核ハーネス" "terms states core works without result-report"
check_contains "TERMS.md" "公式サービスの付加価値" "terms ties benefits to added value"
check_contains "docs/data-policy.md" "result-report は任意提出です" "data policy states result-report optionality"
check_contains "docs/data-policy.md" "非提出でも、ローカルで動く中核ハーネス" "data policy states core works without result-report"
check_contains "docs/telemetry.md" "非提出でも、ハーネスのローカル機能" "telemetry states local features work without result-report"
check_contains "docs/licensing-tiers.md" "非提出でも中核機能は使える" "licensing tiers states core works without result-report"
check_contains "docs/collaborator-招待手順.md" "これは非提出者を中核機能から除外する条件ではありません" "result-report guide rejects condition wording"
check_contains "docs/faq.md" "result-report を出さないと使えないのか" "FAQ covers result-report optionality"
check_contains "docs/faq.md" "採否データ提出を無料利用の必須条件にするものではありません" "FAQ rejects result-data condition"
check_contains "docs/ハーネスの育て方.md" "採否データ提出をキット利用の必須条件にするものではありません" "growth guide rejects result-data condition"
check_contains "docs/design/カスタマージャーニー-01-接点.md" "採否データ提供をキット利用条件にしません" "customer journey rejects result-data condition"
no_placeholder "TERMS.md"
no_placeholder "docs/data-policy.md"
no_placeholder "docs/telemetry.md"
no_placeholder "docs/licensing-tiers.md"
no_placeholder "docs/collaborator-招待手順.md"
no_placeholder "docs/改善ループ.md"
no_placeholder "docs/design/harness-ingest-loop.md"
no_placeholder "docs/design/カスタマージャーニー-01-接点.md"
no_placeholder "docs/faq.md"
no_placeholder "docs/ハーネスの育て方.md"

# Wave: oss-community-files
check_contains "core-manifest.json" '"SECURITY.md"' "core manifest includes security policy"
check_contains "core-manifest.json" '"CODE_OF_CONDUCT.md"' "core manifest includes code of conduct"

check_file "SECURITY.md" 1000
check_contains "SECURITY.md" "Private Vulnerability Reporting" "security policy names GitHub private reporting"
check_contains "SECURITY.md" "info@subsidy-support.tech" "security policy contact email"
check_contains "SECURITY.md" "対象範囲" "security policy scope section"
check_contains "SECURITY.md" "対象外" "security policy out-of-scope section"
check_contains "SECURITY.md" "受領確認: 7日以内" "security policy response target"
check_contains "SECURITY.md" "公開までの非開示" "security policy disclosure request"

check_file "CODE_OF_CONDUCT.md" 3000
check_contains "CODE_OF_CONDUCT.md" "Contributor Covenant" "code of conduct names Contributor Covenant"
check_contains "CODE_OF_CONDUCT.md" "info@subsidy-support.tech" "code of conduct contact email"
check_contains "CODE_OF_CONDUCT.md" "私たちの誓約" "code of conduct pledge section"
check_contains "CODE_OF_CONDUCT.md" "執行ガイドライン" "code of conduct enforcement guidelines"

check_file ".github/PULL_REQUEST_TEMPLATE.md" 500
check_contains ".github/PULL_REQUEST_TEMPLATE.md" "Signed-off-by" "PR template DCO sign-off checklist"
check_contains ".github/PULL_REQUEST_TEMPLATE.md" "tools/validate.sh" "PR template validate checklist"
check_contains ".github/PULL_REQUEST_TEMPLATE.md" "機微情報" "PR template confidentiality checklist"

check_file ".github/ISSUE_TEMPLATE/bug.md" 500
check_contains ".github/ISSUE_TEMPLATE/bug.md" "name:" "bug issue template frontmatter name"
check_contains ".github/ISSUE_TEMPLATE/bug.md" "about:" "bug issue template frontmatter about"
check_contains ".github/ISSUE_TEMPLATE/bug.md" "機密情報" "bug issue template confidentiality caution"

check_file ".github/ISSUE_TEMPLATE/feature.md" 500
check_contains ".github/ISSUE_TEMPLATE/feature.md" "name:" "feature issue template frontmatter name"
check_contains ".github/ISSUE_TEMPLATE/feature.md" "about:" "feature issue template frontmatter about"
check_contains ".github/ISSUE_TEMPLATE/feature.md" "機密情報" "feature issue template confidentiality caution"

check_file ".github/ISSUE_TEMPLATE/config.yml" 100
check_contains ".github/ISSUE_TEMPLATE/config.yml" "blank_issues_enabled: true" "issue template config allows blank issues"
check_contains ".github/ISSUE_TEMPLATE/config.yml" "SECURITY.md" "issue template config points to security policy"

check_contains "CONTRIBUTING.md" "CODE_OF_CONDUCT.md" "contributing links code of conduct"
check_contains "CONTRIBUTING.md" "SECURITY.md" "contributing links security policy"

no_placeholder "SECURITY.md"
no_placeholder "CODE_OF_CONDUCT.md"
no_placeholder ".github/PULL_REQUEST_TEMPLATE.md"
no_placeholder ".github/ISSUE_TEMPLATE/bug.md"
no_placeholder ".github/ISSUE_TEMPLATE/feature.md"
no_placeholder ".github/ISSUE_TEMPLATE/config.yml"
no_placeholder "CONTRIBUTING.md"

# Wave: ci-workflows-and-gitleaks
check_file ".github/workflows/validate.yml" 250
check_contains ".github/workflows/validate.yml" "name: validate" "validate workflow name"
check_contains ".github/workflows/validate.yml" "push:" "validate workflow runs on push"
check_contains ".github/workflows/validate.yml" "pull_request:" "validate workflow runs on pull_request"
check_contains ".github/workflows/validate.yml" "actions/checkout@v6" "validate workflow checks out repository"
check_contains ".github/workflows/validate.yml" "bash tools/validate.sh" "validate workflow runs local validation"
check_contains ".github/workflows/validate.yml" "CI の実走検証は GitHub 上（private repo push 後、設計書 §4.2 手順4）でのみ可能" "validate workflow documents GitHub-only execution check"

check_file ".github/workflows/gitleaks.yml" 300
check_contains ".github/workflows/gitleaks.yml" "name: gitleaks" "gitleaks workflow name"
check_contains ".github/workflows/gitleaks.yml" "push:" "gitleaks workflow runs on push"
check_contains ".github/workflows/gitleaks.yml" "pull_request:" "gitleaks workflow runs on pull_request"
check_contains ".github/workflows/gitleaks.yml" "actions/checkout@v6" "gitleaks workflow checks out repository"
check_contains ".github/workflows/gitleaks.yml" "fetch-depth: 0" "gitleaks workflow scans full history"
check_contains ".github/workflows/gitleaks.yml" "gitleaks_8.30.1_linux_x64.tar.gz" "gitleaks workflow installs fixed CLI version"
check_contains ".github/workflows/gitleaks.yml" "./gitleaks git --no-banner --redact --config .gitleaks.toml" "gitleaks workflow runs CLI scan"
check_contains ".github/workflows/gitleaks.yml" "CI の実走検証は GitHub 上（private repo push 後、設計書 §4.2 手順4）でのみ可能" "gitleaks workflow documents GitHub-only execution check"

check_file ".gitleaks.toml" 300
check_contains ".gitleaks.toml" "useDefault = true" "gitleaks extends default rules"
check_contains ".gitleaks.toml" "taxable_income_avg_3y" "gitleaks allowlist covers taxable income predicate key"
check_contains ".gitleaks.toml" "specs/jizokuka-20" "gitleaks allowlist is scoped to bundled spec"
check_contains ".gitleaks.toml" 'condition = "AND"' "gitleaks allowlist requires both path and regex"
check_contains ".gitleaks.toml" "entropy誤検知であり秘密情報ではない" "gitleaks allowlist reason explains false positive"
no_placeholder ".github/workflows/validate.yml"
no_placeholder ".github/workflows/gitleaks.yml"
no_placeholder ".gitleaks.toml"

# Wave: readme-oss-reframe
check_contains "README.md" "license-Apache--2.0" "README has Apache-2.0 license badge"
check_contains "README.md" "actions/workflows/validate.yml/badge.svg" "README has validate CI badge"
check_contains "README.md" "saita-kun/saita-kun-planner" "README names public GitHub org and repo"
check_contains "README.md" "## このリポジトリの使い方（Use this template）" "README has Use this template section"
check_contains "README.md" "/setup" "README template usage starts with setup"
check_contains "README.md" "tools/update-core.sh" "README explains update-core upstream update path"
check_contains "README.md" '本家 `saita-kun/saita-kun-planner` がコア層の正史' "README states upstream is canonical"
check_contains "README.md" "## なぜ無料で公開するのか" "README has mission section"
check_contains "README.md" "情報の非対称性" "README explains mission problem"
check_contains "README.md" "支援がなくても自分で申請できる状態" "README states self-serve mission"
check_contains "README.md" "GUI ラッパー" "README welcomes GUI wrappers"
check_contains "README.md" "白ラベル UI" "README welcomes white-label UI"
check_contains "README.md" "AI は利用者持ち込み（BYO）" "README states BYO AI"
check_contains "README.md" "現在のキットは Claude Code に特化" "README avoids overclaiming non-Claude support"
check_contains "README.md" "SECURITY.md" "README links security policy"
check_contains "README.md" "CODE_OF_CONDUCT.md" "README links code of conduct"
check_contains "README.md" "TERMS.md" "README links terms"
check_relative_links "README.md"
no_placeholder "README.md"

# Wave: public-roadmap
check_file "ROADMAP.md" 1200
if [ "$(grep -c '^## ' ROADMAP.md)" -eq 5 ]; then
  ok
else
  bad "ROADMAP.md must have exactly five level-2 sections"
fi
check_contains "ROADMAP.md" "## 採択後モジュール" "roadmap adoption-after module section"
check_contains "ROADMAP.md" "## spec レジストリの公共財化" "roadmap spec registry section"
check_contains "ROADMAP.md" "## 補助金パックの拡充" "roadmap subsidy pack expansion section"
check_contains "ROADMAP.md" "## 公募要領改訂の監視パイプライン" "roadmap revision monitoring section"
check_contains "ROADMAP.md" "## 政策提言" "roadmap policy proposal section"
check_contains "README.md" "ROADMAP.md" "README links roadmap"
check_contains "docs/faq.md" "ROADMAP.md" "FAQ links roadmap"
check_contains "core-manifest.json" '"ROADMAP.md"' "core manifest includes roadmap"
no_placeholder "ROADMAP.md"

# Wave: pack-builder-doc
check_file "docs/design/harness-pack-builder.md" 3000
check_contains "docs/design/harness-pack-builder.md" "## 1. 補助金パックの構造" "pack builder design pack structure heading"
check_contains "docs/design/harness-pack-builder.md" "### 2.1 resolver 規約（全コマンド共通）" "pack builder design resolver heading"
check_contains "docs/design/harness-pack-builder.md" "### 6.4 CLI 仕様（check-spec）" "pack builder design check-spec CLI heading"
check_contains "docs/design/harness-pack-builder.md" "## 11. スキーマ changelog" "pack builder design schema changelog heading"
check_contains "docs/design/harness-ingest-loop.md" "harness-pack-builder.md" "ingest loop links pack builder design"
no_placeholder "docs/design/harness-pack-builder.md"

# Wave: repo-structure-doc
check_file "docs/design/repo-structure.md" 3000
check_contains "docs/design/repo-structure.md" "## 0. 決定（原則）" "repo structure design decision heading"
check_contains "docs/design/repo-structure.md" "**repo は育成単位、補助金パックは配布単位、完成環境は生成物。**" "repo structure design core principle"
check_contains "docs/design/repo-structure.md" "## 1. 採らなかった案: 補助金ごとにリポジトリを分割する" "repo structure design rejected split heading"
check_contains "docs/design/repo-structure.md" "パックレジストリ" "repo structure design pack registry direction"
check_contains "docs/design/repo-structure.md" "生成 starter" "repo structure design generated starter direction"
check_contains "docs/design/repo-structure.md" "harness-pack-builder.md" "repo structure design links pack builder"
check_contains "docs/design/harness-pack-builder.md" '配布アーキテクチャの方向（repo＝育成単位・パック＝配布単位・完成環境＝生成物）は `docs/design/repo-structure.md` を正とする。' "pack builder section 12 links repo structure design"
if [ "$VALIDATE_INTERNAL_MODE" = "1" ]; then
  if grep -F -- "18. **spec レジストリ**" docs/design/harness-backlog.md | grep -qF -- "[repo-structure.md](repo-structure.md)"; then
    ok
  else
    bad "harness-backlog item 18 must link repo-structure design"
  fi
fi
check_contains "core-manifest.json" '"docs/design/repo-structure.md"' "core manifest includes repo structure design"
no_placeholder "docs/design/repo-structure.md"

# Wave: spec-draft-gate
check_file "schemas/spec-confirmation.schema.json" 1000
check_json "schemas/spec-confirmation.schema.json"
check_contains "schemas/spec-confirmation.schema.json" "spec_path" "spec confirmation schema spec_path"
check_contains "schemas/spec-confirmation.schema.json" "spec_version" "spec confirmation schema spec_version"
check_contains "schemas/spec-confirmation.schema.json" "spec_sha256" "spec confirmation schema spec_sha256"
check_contains "schemas/spec-confirmation.schema.json" "confirmed_by" "spec confirmation schema confirmed_by"
check_contains "schemas/spec-confirmation.schema.json" "confirmed_at" "spec confirmation schema confirmed_at"
check_contains "schemas/spec-confirmation.schema.json" "field_path" "spec confirmation schema item field_path"
check_contains "schemas/spec-confirmation.schema.json" "source_clauses" "spec confirmation schema source clauses"
check_contains "schemas/spec-confirmation.schema.json" "predicate_state" "spec confirmation schema predicate state"
check_contains "schemas/spec-confirmation.schema.json" "confirmed_via" "spec confirmation schema confirmed_via"
check_contains "schemas/spec-confirmation.schema.json" "shown_page" "spec confirmation schema shown page"
check_contains "tools/lib/check_spec.py" "--gate" "check-spec CLI gate option"
check_contains "tools/lib/check_spec.py" "READINESS:" "check-spec readiness output"
check_contains "tools/lib/check_spec.py" "predicate_state pending" "check-spec confirm gate predicate pending"
check_contains "tools/lib/check_spec.py" "predicate_state mismatch" "check-spec confirm gate predicate mismatch"
check_contains "tools/lib/check_spec.py" "confirmation spec_path mismatch" "check-spec draft confirmation spec_path match"
check_contains "tools/test-check-spec.sh" "gate-green-draft" "check-spec gate green fixture test"
check_contains "tools/test-check-spec.sh" "gate-open-remaining" "check-spec gate open fixture test"
check_contains "tools/test-check-spec.sh" "gate-predicate-pending" "check-spec gate predicate pending fixture test"
check_contains "tools/test-check-spec.sh" "gate-predicate-mismatch" "check-spec gate predicate mismatch fixture test"
check_contains "tools/test-check-spec.sh" "coverage-missing-draft" "check-spec draft confirmation coverage fixture test"
check_contains "core-manifest.json" "\"schemas/spec-confirmation.schema.json\"" "core manifest includes spec confirmation schema"
for f in \
  tools/fixtures/spec/gate-green-draft.json \
  tools/fixtures/spec/gate-green-draft.confirmation.json \
  tools/fixtures/spec/gate-open-remaining.json \
  tools/fixtures/spec/gate-open-remaining.confirmation.json \
  tools/fixtures/spec/gate-predicate-pending.json \
  tools/fixtures/spec/gate-predicate-pending.confirmation.json \
  tools/fixtures/spec/gate-predicate-mismatch.json \
  tools/fixtures/spec/gate-predicate-mismatch.confirmation.json \
  tools/fixtures/spec/coverage-missing-draft.json \
  tools/fixtures/spec/coverage-missing-draft.confirmation.json; do
  check_file "$f" 100
  check_json "$f"
  check_contains "core-manifest.json" "\"$f\"" "core manifest includes $f"
done
if bash tools/test-check-spec.sh >/dev/null 2>&1; then
  ok
else
  bad "tools/test-check-spec.sh failed after spec-draft-gate"
fi
no_placeholder "schemas/spec-confirmation.schema.json"
no_placeholder "docs/design/harness-ingest-loop.md"

# Wave: clause-verbatim
check_contains "schemas/subsidy-spec.schema.json" "extract_path" "subsidy spec source_documents extract_path"
check_contains "tools/lib/check_spec.py" "extract_path" "check-spec handles source document extract_path"
check_contains "tools/lib/check_spec.py" "normalize_verbatim_text" "check-spec normalizes verbatim text"
check_contains "tools/lib/check_spec.py" "clause verbatim mismatch" "check-spec reports verbatim mismatch"
check_contains "tools/lib/check_spec.py" "verbatim coverage" "check-spec readiness reports verbatim coverage"
check_contains "tools/test-check-spec.sh" "verbatim-match" "check-spec test covers verbatim match fixture"
check_contains "tools/test-check-spec.sh" "verbatim-mismatch" "check-spec test covers verbatim mismatch fixture"
for f in \
  tools/fixtures/spec/verbatim-match.json \
  tools/fixtures/spec/verbatim-match.confirmation.json \
  tools/fixtures/spec/verbatim-mismatch.json \
  tools/fixtures/spec/verbatim-mismatch.confirmation.json; do
  check_file "$f" 100
  check_json "$f"
  check_contains "core-manifest.json" "\"$f\"" "core manifest includes $f"
done
for f in \
  tools/fixtures/spec/verbatim-match.extract.md \
  tools/fixtures/spec/verbatim-mismatch.extract.md; do
  check_file "$f" 20
  check_contains "core-manifest.json" "\"$f\"" "core manifest includes $f"
  no_placeholder "$f"
done
if bash tools/test-check-spec.sh >/dev/null 2>&1; then
  ok
else
  bad "tools/test-check-spec.sh failed after clause-verbatim"
fi
no_placeholder "tools/lib/check_spec.py"

# Wave: pdf-intake-flow
check_contains ".claude/commands/ingest-guidelines.md" "extract" "ingest explains extract generation"
check_contains ".claude/commands/ingest-guidelines.md" "ページアンカー" "ingest requires page anchors"
check_contains ".claude/commands/ingest-guidelines.md" "スポットチェック" "ingest requires spot check"
check_contains ".claude/commands/ingest-guidelines.md" "要約禁止" "ingest forbids summarized source extraction"
check_contains ".claude/commands/ingest-guidelines.md" "source_documents[].extract_path" "ingest records extract_path"
check_contains ".claude/commands/ingest-guidelines.md" "input/guidelines/<name>.extract.md" "ingest writes extract md next to original"
check_contains ".claude/commands/ingest-guidelines.md" "Web ページしかない場合" "ingest handles web pasted original"
check_contains ".claude/commands/ingest-guidelines.md" "スキャン画像などで読めない場合" "ingest handles unreadable scanned originals"
check_contains ".claude/commands/ingest-guidelines.md" "無作為に 3 clause" "ingest spot-checks three random clauses"
check_contains ".claude/commands/setup.md" "pdftotext" "setup optionally detects pdftotext"
check_contains ".claude/commands/setup.md" "pdftotext は任意" "setup marks pdftotext optional"
check_contains ".claude/commands/setup.md" "必須要件は python3 と bash" "setup keeps required tools unchanged"
no_placeholder ".claude/commands/ingest-guidelines.md"
no_placeholder ".claude/commands/setup.md"

# Wave: cmd-confirm-spec
check_file ".claude/commands/confirm-spec.md" 6000
if [ "$(sed -n '1p' ".claude/commands/confirm-spec.md")" = "---" ] &&
   sed -n '2p' ".claude/commands/confirm-spec.md" | grep -q '^description:' &&
   [ "$(sed -n '3p' ".claude/commands/confirm-spec.md")" = "---" ]; then
  ok
else
  bad ".claude/commands/confirm-spec.md must have YAML frontmatter with description only"
fi
check_contains ".claude/commands/confirm-spec.md" "作成者は顧客本人" "confirm-spec customer author guardrail"
check_contains ".claude/commands/confirm-spec.md" "行政書士法" "confirm-spec legal guardrail"
check_contains ".claude/commands/confirm-spec.md" "数値は推測しない" "confirm-spec no guessed numbers"
check_contains ".claude/commands/confirm-spec.md" "[要確認]" "confirm-spec unknown marker"
check_contains ".claude/commands/confirm-spec.md" "募集要項が正" "confirm-spec official requirements priority"
check_contains ".claude/commands/confirm-spec.md" "AI が confirmed を代行しない" "confirm-spec no AI confirmation agency"
check_contains ".claude/commands/confirm-spec.md" "input/" "confirm-spec writes only input"
check_contains ".claude/commands/confirm-spec.md" "進捗" "confirm-spec progress dashboard"
check_contains ".claude/commands/confirm-spec.md" "チェックポイント" "confirm-spec checkpoint save"
check_contains ".claude/commands/confirm-spec.md" "--gate confirm" "confirm-spec runs confirm gate"
check_contains ".claude/commands/confirm-spec.md" "spec_draft" "confirm-spec handles spec_draft state"
check_contains ".claude/commands/confirm-spec.md" "state=spec_confirmed" "confirm-spec promotes to spec_confirmed"
check_contains ".claude/commands/confirm-spec.md" "confirmed_via" "confirm-spec records audit confirmation path"
check_contains ".claude/commands/confirm-spec.md" "shown_page" "confirm-spec records shown page"
check_contains ".claude/commands/confirm-spec.md" "predicate_state" "confirm-spec records predicate state"
check_contains ".claude/commands/confirm-spec.md" "1 件だけ直す" "confirm-spec recovery single item"
check_contains ".claude/commands/confirm-spec.md" "版違い" "confirm-spec recovery version mismatch"
check_contains ".claude/commands/confirm-spec.md" "リセット" "confirm-spec recovery reset warning"
check_contains ".claude/commands/ingest-guidelines.md" "state=spec_draft" "ingest initializes spec_draft"
check_contains ".claude/commands/ingest-guidelines.md" "/confirm-spec" "ingest points to confirm-spec"
check_contains "docs/manual.md" "/confirm-spec" "manual references confirm-spec"
check_contains "core-manifest.json" "\".claude/commands/confirm-spec.md\"" "core manifest includes confirm-spec"

for cmd in select-subsidy intake subsidy-fit plan-deliverables draft-section review verify finalize; do
  check_contains ".claude/commands/${cmd}.md" "state=spec_draft" "${cmd} routes spec_draft"
  check_contains ".claude/commands/${cmd}.md" "突合が未完了です。/confirm-spec を実行してください" "${cmd} tells user to run confirm-spec"
  check_contains ".claude/commands/${cmd}.md" "status=draft" "${cmd} detects draft status after confirmation"
  check_contains ".claude/commands/${cmd}.md" "同一 subsidy_id のパック形" "${cmd} detects stale flat bundled path"
done

no_placeholder ".claude/commands/confirm-spec.md"

# Wave: pack-checker
check_file "schemas/subsidy-pack.schema.json" 1000
check_contains "schemas/subsidy-pack.schema.json" "derived_from_spec_sha256" "subsidy pack schema tracks semantic stale notes"
check_file "tools/check-pack.sh" 100
if [ "$(sed -n '1p' "tools/check-pack.sh")" = "#!/bin/bash" ]; then
  ok
else
  bad "tools/check-pack.sh must be a bash wrapper"
fi
check_contains "tools/check-pack.sh" "set -u" "check-pack wrapper uses set -u"
check_contains "tools/check-pack.sh" "lib/check_pack.py" "check-pack wrapper invokes Python engine"
check_file "tools/lib/check_pack.py" 8000
check_contains "tools/lib/check_pack.py" "parse_limited_frontmatter" "check-pack uses limited frontmatter parser"
check_contains "tools/lib/check_pack.py" "derived_from_spec_sha256 mismatch" "check-pack detects stale notes"
check_contains "tools/lib/check_pack.py" "unsupported file in pack dir" "check-pack bans non-data files"
check_contains "tools/lib/check_pack.py" "examples note missing source:" "check-pack requires examples sources"
if grep -Eq 'import (requests|yaml)' tools/lib/check_pack.py; then
  bad "tools/lib/check_pack.py must not import third-party modules"
else
  ok
fi
check_file "tools/test-check-pack.sh" 4000
check_contains "tools/test-check-pack.sh" "missing-required-key" "check-pack test covers missing required key"
check_contains "tools/test-check-pack.sh" "sha-mismatch" "check-pack test covers sha mismatch"
check_contains "tools/test-check-pack.sh" "stale-derived" "check-pack test covers derived stale"
check_contains "tools/test-check-pack.sh" "bad-clause" "check-pack test covers unknown clause"
check_contains "tools/test-check-pack.sh" "unsupported-file" "check-pack test covers non-md/json file"
check_file "tools/fixtures/packs/green/pack.json" 1000
check_file "tools/fixtures/packs/green/notes/review-lens.md" 200
check_contains "tools/fixtures/packs/green/pack.json" "derived_from_spec_sha256" "green pack fixture records derived spec sha"
check_contains "tools/fixtures/packs/green/notes/review-lens.md" "[clause:" "green pack fixture note cites clauses"
if bash tools/test-check-pack.sh >/dev/null 2>&1; then
  ok
else
  bad "tools/test-check-pack.sh must pass"
fi
no_placeholder "schemas/subsidy-pack.schema.json"
no_placeholder "tools/check-pack.sh"
no_placeholder "tools/lib/check_pack.py"
no_placeholder "tools/test-check-pack.sh"
no_placeholder "tools/fixtures/packs/green/pack.json"
no_placeholder "tools/fixtures/packs/green/pack-fixture.json"
no_placeholder "tools/fixtures/packs/green/pack-fixture.confirmation.json"
no_placeholder "tools/fixtures/packs/green/notes/review-lens.md"
no_placeholder "tools/fixtures/packs/green/notes/scoring-strategy.md"
no_placeholder "tools/fixtures/packs/green/notes/sections/plan--overview.md"

# Wave: cmd-build-pack
check_file ".claude/commands/build-pack.md" 6000
if [ "$(sed -n '1p' ".claude/commands/build-pack.md")" = "---" ] &&
   sed -n '2p' ".claude/commands/build-pack.md" | grep -q '^description:' &&
   [ "$(sed -n '3p' ".claude/commands/build-pack.md")" = "---" ]; then
  ok
else
  bad ".claude/commands/build-pack.md must have YAML frontmatter with description only"
fi
check_contains ".claude/commands/build-pack.md" "作成者は顧客本人" "build-pack customer author guardrail"
check_contains ".claude/commands/build-pack.md" "行政書士法" "build-pack legal guardrail"
check_contains ".claude/commands/build-pack.md" "数値は推測しない" "build-pack no guessed numbers"
check_contains ".claude/commands/build-pack.md" "[要確認]" "build-pack unknown marker"
check_contains ".claude/commands/build-pack.md" "募集要項が正" "build-pack official requirements priority"
check_contains ".claude/commands/build-pack.md" "input/spec/<subsidy_id>/" "build-pack writes to input spec pack dir"
check_contains ".claude/commands/build-pack.md" "review-lens" "build-pack creates review-lens note"
check_contains ".claude/commands/build-pack.md" "scoring-strategy" "build-pack creates scoring-strategy note"
check_contains ".claude/commands/build-pack.md" "sections/<deliverable_id>--<section_id>.md" "build-pack creates section notes"
check_contains ".claude/commands/build-pack.md" "examples.md" "build-pack handles optional examples note"
check_contains ".claude/commands/build-pack.md" "[clause:" "build-pack requires clause refs"
check_contains ".claude/commands/build-pack.md" "境界" "build-pack states boundary discipline"
check_contains ".claude/commands/build-pack.md" "derived_from_spec_sha256" "build-pack records note source sha"
check_contains ".claude/commands/build-pack.md" "sha256" "build-pack records file shas"
check_contains ".claude/commands/build-pack.md" "bash tools/check-pack.sh" "build-pack runs check-pack"
check_contains ".claude/commands/build-pack.md" "書き方メモを作る" "build-pack uses customer-facing wording"
check_contains ".claude/commands/build-pack.md" "コア層は書き換えない" "build-pack does not edit core layer"
check_contains ".claude/commands/draft-section.md" "解決済みパックの notes" "draft-section reads resolved pack notes"
check_contains ".claude/commands/draft-section.md" "該当 section-note と review-lens" "draft-section uses section-note and review-lens"
check_contains ".claude/commands/draft-section.md" "境界規律: notes 中で clause 引用のない記述は一般知見扱い" "draft-section states notes boundary discipline"
check_contains ".claude/commands/draft-section.md" "同梱パックの notes へ加筆したい場合は knowledge/lessons/ へ" "draft-section routes bundled notes additions to lessons"
check_contains ".claude/commands/review.md" "解決済みパックの notes" "review reads resolved pack notes"
check_contains ".claude/commands/review.md" "review-lens を追加" "review adds review-lens perspective"
check_contains ".claude/commands/review.md" "境界規律: notes 中で clause 引用のない記述は一般知見扱い" "review states notes boundary discipline"
check_contains ".claude/commands/review.md" "同梱パックの notes へ加筆したい場合は knowledge/lessons/ へ" "review routes bundled notes additions to lessons"
check_contains "core-manifest.json" "\".claude/commands/build-pack.md\"" "core manifest includes build-pack"
check_contains "docs/manual.md" "/build-pack" "manual references build-pack"
no_placeholder ".claude/commands/build-pack.md"

# Wave: jizokuka-pack
jizokuka_spec="specs/jizokuka-20/jizokuka-20.json"
jizokuka_confirmation="specs/jizokuka-20/jizokuka-20.confirmation.json"
jizokuka_pack="specs/jizokuka-20/pack.json"

check_file "$jizokuka_spec" 1000
check_json "$jizokuka_spec"
check_file "$jizokuka_confirmation" 1000
check_json "$jizokuka_confirmation"
check_file "$jizokuka_pack" 1000
check_json "$jizokuka_pack"

check_contains "$jizokuka_spec" '"spec_version": 3' "jizokuka spec version bumped for portal_url metadata"
if python3 - "$jizokuka_spec" <<'PY' >/dev/null 2>&1; then
import json
import sys

spec = json.load(open(sys.argv[1], encoding="utf-8"))
portal_url = spec.get("portal_url")
if not isinstance(portal_url, str) or not portal_url.startswith("https://"):
    raise SystemExit(1)
PY
  ok
else
  bad "jizokuka spec portal_url must be a non-null https URL"
fi
check_contains "$jizokuka_spec" '"portal_url": "https://www.chusho.meti.go.jp/koukai/hojyokin/kobo/2026/260527002.html"' "jizokuka spec portal URL points to D5 official portal"
check_contains "$jizokuka_spec" '"event_id": "application-start"' "jizokuka spec records application start event"
check_contains "$jizokuka_spec" '"event_kind": "other"' "jizokuka application start event uses other kind"
check_contains "$jizokuka_spec" '"date": "2026-11-05"' "jizokuka application start date"
check_contains "$jizokuka_spec" '"schedule-001"' "jizokuka application start source clause"
check_contains "$jizokuka_confirmation" '"spec_path": "specs/jizokuka-20/jizokuka-20.json"' "jizokuka confirmation points to packed spec"
check_contains "$jizokuka_confirmation" '"spec_version": 3' "jizokuka confirmation version bumped"
check_contains "$jizokuka_confirmation" "変更は portal_url 追加のみ" "jizokuka confirmation records D4 portal_url-only audit note"
check_contains "$jizokuka_confirmation" '"confirmed_by": "provider"' "jizokuka confirmation remains provider confirmed"
check_contains "$jizokuka_confirmation" '"predicate_state": "encoded"' "jizokuka confirmation records encoded predicates"
check_contains "$jizokuka_confirmation" '"predicate_state": "not_encodable"' "jizokuka confirmation records not-encodable predicates"
check_spec_confirmation_binding "$jizokuka_spec" "$jizokuka_confirmation"

if python3 - "$jizokuka_spec" "$jizokuka_confirmation" <<'PY' >/dev/null 2>&1; then
import json
import sys

spec = json.load(open(sys.argv[1], encoding="utf-8"))
confirmation = json.load(open(sys.argv[2], encoding="utf-8"))
rules = {
    rule["rule_id"]: ("encoded" if rule.get("predicate") is not None else "not_encodable")
    for rule in spec.get("eligibility", {}).get("rules", [])
}
items = {item.get("field_path"): item for item in confirmation.get("items", [])}
for rule_id, expected_state in rules.items():
    item = items.get(f"eligibility.rules.{rule_id}")
    if not item or item.get("predicate_state") != expected_state:
        raise SystemExit(1)
for item in confirmation.get("items", []):
    if item.get("state") == "confirmed" and (
        not item.get("confirmed_at") or item.get("confirmed_via") != "group-table"
    ):
        raise SystemExit(1)
PY
  ok
else
  bad "jizokuka confirmation must mark every rule predicate_state and audit confirmed items"
fi

for note_file in \
  specs/jizokuka-20/notes/review-lens.md \
  specs/jizokuka-20/notes/scoring-strategy.md \
  specs/jizokuka-20/notes/sections/keiei-keikaku--kigyo-gaiyo.md \
  specs/jizokuka-20/notes/sections/keiei-keikaku--kokyaku-needs-shijo-doko.md \
  specs/jizokuka-20/notes/sections/keiei-keikaku--jisha-shohin-service-tsuyomi.md \
  specs/jizokuka-20/notes/sections/keiei-keikaku--keiei-hoshin-mokuhyo-plan.md \
  specs/jizokuka-20/notes/sections/hojo-jigyo-keikaku--hojo-jigyo-mei.md \
  specs/jizokuka-20/notes/sections/hojo-jigyo-keikaku--hanro-kaitaku-torikumi.md \
  specs/jizokuka-20/notes/sections/hojo-jigyo-keikaku--gyomu-koritsuka-torikumi.md \
  specs/jizokuka-20/notes/sections/hojo-jigyo-keikaku--hojo-jigyo-koka.md; do
  check_file "$note_file" 200
  check_contains "$note_file" "[clause:" "jizokuka provider note cites clauses: $note_file"
  no_placeholder "$note_file"
done

check_contains "$jizokuka_pack" '"built_by": "provider"' "jizokuka pack built by provider"
check_contains "$jizokuka_pack" '"spec_version": 3' "jizokuka pack spec version follows spec"
check_contains "$jizokuka_pack" '"derived_from_spec_sha256"' "jizokuka pack records note semantic source sha"
check_contains ".claude/commands/select-subsidy.md" "specs/<id>/<id>.json" "select-subsidy enumerates pack-form bundled specs"
check_contains ".claude/commands/select-subsidy.md" "specs/<id>.json" "select-subsidy keeps flat-form residual compatibility"
check_contains ".claude/commands/select-subsidy.md" "### 2. 原本入手" "select-subsidy adds original document acquisition step"
check_contains ".claude/commands/select-subsidy.md" "shasum -a 256 <file>" "select-subsidy pins sha256 command"
check_contains ".claude/commands/select-subsidy.md" '不一致なら版違いとして入口B（`/ingest-guidelines`）へ' "select-subsidy routes hash mismatch to entry B"
check_contains ".claude/commands/select-subsidy.md" '`/build-pack`（推奨）または `/intake`' "select-subsidy routes next to build-pack or intake"
check_contains ".claude/commands/confirm-spec.md" '`/build-pack`（推奨）または `/intake`' "confirm-spec routes next to build-pack or intake"
check_contains "specs/README.md" "specs/<subsidy_id>/<subsidy_id>.json" "specs README documents packed bundled spec path"
check_contains "specs/README.md" "残留平置き" "specs README documents residual flat specs"
check_contains "specs/README.md" "## 原本の入手と版一致の確認" "specs README documents original document acquisition"
check_contains "specs/README.md" "portal_url" "specs README explains portal URL"
check_contains "specs/README.md" "shasum -a 256 <file>" "specs README documents sha256 check"
check_contains "specs/README.md" '入口Bの `/ingest-guidelines`' "specs README routes hash mismatch to entry B"
check_contains "specs/README.md" "商工会議所地区と商工会地区" "specs README notes chamber/society page split"
check_contains "core-manifest.json" "\"specs/jizokuka-20/pack.json\"" "core manifest includes jizokuka pack"
check_contains "core-manifest.json" "\"specs/jizokuka-20/notes/review-lens.md\"" "core manifest includes jizokuka review note"
check_contains "core-manifest.json" "\"specs/jizokuka-20/notes/scoring-strategy.md\"" "core manifest includes jizokuka scoring note"
if grep -qF -- "\"specs/jizokuka-20.json\"" core-manifest.json ||
   grep -qF -- "\"specs/jizokuka-20.confirmation.json\"" core-manifest.json; then
  bad "core-manifest.json must not keep old flat jizokuka spec entries"
else
  ok
fi

if bash tools/check-pack.sh specs/jizokuka-20 >/dev/null 2>&1; then
  ok
else
  bad "tools/check-pack.sh must pass on specs/jizokuka-20"
fi

no_placeholder "$jizokuka_spec"
no_placeholder "$jizokuka_confirmation"
no_placeholder "$jizokuka_pack"

# Wave: profile-chusho-class
check_contains "schemas/company-profile.schema.json" "chusho_kihonho_class" "company profile chusho kihonho class field"
check_contains "schemas/company-profile.schema.json" "卸売業" "company profile chusho enum wholesale"
check_contains "schemas/company-profile.schema.json" "小売業" "company profile chusho enum retail"
check_contains "schemas/company-profile.schema.json" "サービス業" "company profile chusho enum service"
check_contains "schemas/company-profile.schema.json" "中小企業基本法系" "company profile chusho description"
if python3 - "schemas/company-profile.schema.json" <<'PY' >/dev/null 2>&1; then
import json
import sys

schema = json.load(open(sys.argv[1], encoding="utf-8"))
field = schema.get("properties", {}).get("chusho_kihonho_class", {})
expected = {"製造業その他", "卸売業", "小売業", "サービス業", None}
if set(field.get("enum", [])) != expected:
    raise SystemExit(1)
if "chusho_kihonho_class" in schema.get("required", []):
    raise SystemExit(1)
if field.get("type") != ["string", "null"]:
    raise SystemExit(1)
PY
  ok
else
  bad "schemas/company-profile.schema.json chusho_kihonho_class must be optional enum|null"
fi
check_contains ".claude/commands/intake.md" "chusho_kihonho_class" "intake includes chusho profile key"
check_contains ".claude/commands/intake.md" "中小企業基本法" "intake asks chusho kihonho class"
check_contains ".claude/commands/intake.md" "資本金・従業員数のしきい値" "intake asks capital and employee threshold combination"
check_contains ".claude/commands/intake.md" "\"chusho_kihonho_class\": null" "intake JSON example includes chusho key"
check_contains "tools/fixtures/spec/predicate-kleene.json" "chusho-service-capital-employees" "predicate fixture includes chusho rule"
check_contains "tools/test-check-spec.sh" "chusho-service-ok.json" "predicate test covers chusho true"
check_contains "tools/test-check-spec.sh" "chusho-retail-false.json" "predicate test covers chusho false"
check_contains "tools/test-check-spec.sh" "chusho-unknown-null.json" "predicate test covers chusho unknown"
for profile_fixture in \
  tools/fixtures/profiles/chusho-service-ok.json \
  tools/fixtures/profiles/chusho-retail-false.json \
  tools/fixtures/profiles/chusho-unknown-null.json; do
  check_file "$profile_fixture" 1
  check_json "$profile_fixture"
  check_contains "$profile_fixture" "chusho_kihonho_class" "chusho profile fixture has class key: $profile_fixture"
  no_placeholder "$profile_fixture"
done
check_contains "core-manifest.json" "\"tools/fixtures/profiles/chusho-service-ok.json\"" "core manifest includes chusho true fixture"
check_contains "core-manifest.json" "\"tools/fixtures/profiles/chusho-retail-false.json\"" "core manifest includes chusho false fixture"
check_contains "core-manifest.json" "\"tools/fixtures/profiles/chusho-unknown-null.json\"" "core manifest includes chusho unknown fixture"
if bash tools/test-check-spec.sh >/dev/null 2>&1; then
  ok
else
  bad "tools/test-check-spec.sh must pass after profile-chusho-class"
fi
no_placeholder "schemas/company-profile.schema.json"
no_placeholder ".claude/commands/intake.md"
no_placeholder "tools/fixtures/spec/predicate-kleene.json"
no_placeholder "tools/test-check-spec.sh"

# Wave: docs-pack-flow
check_contains "docs/manual.md" '入口B: `/ingest-guidelines`' "manual documents staged entry B ingest"
check_contains "docs/manual.md" '`/confirm-spec`' "manual documents confirm-spec"
check_contains "docs/manual.md" '`/build-pack`' "manual documents build-pack"
check_contains "docs/manual.md" "spec_draft → spec_confirmed" "manual state list includes spec_draft"
check_contains "docs/manual.md" "補助金パック" "manual explains subsidy pack"
check_contains "docs/manual.md" "書き方メモ" "manual explains writing notes"
check_contains "docs/manual.md" "書き方メモに書かれた一般的な助言は、募集要項の数値や要件の根拠にはなりません" "manual states writing-note boundary"

for user_doc in README.md docs/manual.md docs/faq.md docs/補助金の選び方.md .claude/commands/start.md CLAUDE.md; do
  check_contains "$user_doc" "/confirm-spec" "user doc references confirm-spec: $user_doc"
  check_contains "$user_doc" "/build-pack" "user doc references build-pack: $user_doc"
  check_contains "$user_doc" "書き方メモ" "user doc uses writing-note wording: $user_doc"
done

check_contains "README.md" "state=spec_draft" "README entry B records spec_draft"
check_contains "README.md" "補助金パック" "README mentions subsidy pack"
check_contains "CLAUDE.md" "補助金パック" "CLAUDE workflow mentions subsidy pack"
check_contains "CLAUDE.md" "state=spec_draft" "CLAUDE workflow mentions spec_draft"
check_contains ".claude/commands/start.md" "state=spec_draft" "start routes spec_draft"
check_contains ".claude/commands/start.md" '`/ingest-guidelines` → `/confirm-spec` → `/build-pack`' "start documents staged entry B and build-pack"
check_contains "docs/補助金の選び方.md" "同梱の補助金パック" "subsidy selection mentions bundled pack"
check_contains "docs/補助金の選び方.md" '`/ingest-guidelines` → `/confirm-spec`' "subsidy selection documents entry B split"

check_contains "docs/faq.md" "## 突合が長い・途中でやめたい" "FAQ has long confirmation interruption entry"
check_contains "docs/faq.md" "## 公募要領の版が変わったら" "FAQ has guideline version-change entry"
check_contains "docs/faq.md" "## 書き方メモとは何か" "FAQ has writing-note entry"
check_contains "docs/faq.md" '| `spec_draft` | `/confirm-spec` |' "FAQ resume table includes spec_draft"
check_contains "docs/faq.md" "state=spec_draft" "FAQ explains spec_draft resume"

check_contains "docs/ハーネスの育て方.md" "同梱パック" "growing guide classifies bundled pack"
check_contains "docs/ハーネスの育て方.md" "自作パック" "growing guide classifies user pack"
check_contains "docs/ハーネスの育て方.md" "input/spec/<subsidy_id>/" "growing guide user pack path"
check_contains "docs/ハーネスの育て方.md" "残留ファイル" "growing guide residual file handling"
check_contains "docs/ハーネスの育て方.md" "手動で削除" "growing guide optional manual deletion"
check_contains "docs/ハーネスの育て方.md" ".gitignore" "growing guide gitignore adjustment"
check_contains "docs/ハーネスの育て方.md" "コミットしたいパックだけを明示的に許可" "growing guide scoped gitignore option"

check_contains "docs/onboarding/03-このキットを自分のものにする.md" "公募要領 PDF" "onboarding asks user to place guideline PDF"
check_contains "docs/onboarding/03-このキットを自分のものにする.md" "input/guidelines/" "onboarding guideline input path"
check_contains "docs/onboarding/03-このキットを自分のものにする.md" "/ingest-guidelines" "onboarding points to ingest"
check_contains "docs/onboarding/03-このキットを自分のものにする.md" "/confirm-spec" "onboarding points to confirm-spec"

check_contains "docs/design/harness-ingest-loop.md" "spec_draft → spec_confirmed" "ingest-loop design state transition includes spec_draft"
check_contains "docs/design/harness-ingest-loop.md" "/confirm-spec ─────────" "ingest-loop design includes confirm-spec stage"
check_contains "docs/design/harness-ingest-loop.md" "/build-pack ───────────" "ingest-loop design includes build-pack stage"
check_contains "docs/design/harness-ingest-loop.md" "harness-pack-builder.md" "ingest-loop design references pack-builder source"
check_contains "docs/design/harness-ingest-loop.md" "突合確認は行わず" "ingest-loop design narrows ingest responsibility"
check_contains "docs/design/harness-ingest-loop.md" "confirmed spec から review-lens" "ingest-loop design documents build-pack notes"

check_contains "docs/テンプレートrepoの使い方.md" "/confirm-spec" "template usage doc references confirm-spec"
check_contains "docs/テンプレートrepoの使い方.md" "/build-pack" "template usage doc references build-pack"
check_contains "docs/テンプレートrepoの使い方.md" "書き方メモ" "template usage doc references writing notes"

for public_flow_doc in README.md docs/manual.md docs/faq.md docs/補助金の選び方.md .claude/commands/start.md CLAUDE.md; do
  if grep -qE 'pack\.json|checker|predicate' "$public_flow_doc"; then
    bad "$public_flow_doc must not expose internal pack-builder terms"
  else
    ok
  fi
done
no_placeholder "README.md"
no_placeholder "docs/manual.md"
no_placeholder "docs/faq.md"
no_placeholder "docs/ハーネスの育て方.md"
no_placeholder "docs/onboarding/03-このキットを自分のものにする.md"
no_placeholder "docs/テンプレートrepoの使い方.md"
no_placeholder "docs/補助金の選び方.md"
no_placeholder "docs/design/harness-ingest-loop.md"

# Wave: worked-example-pack
check_file "examples/worked-example/pack/pack.json" 500
check_json "examples/worked-example/pack/pack.json"
check_file "examples/worked-example/pack/notes/review-lens.md" 500
check_contains "examples/worked-example/pack/pack.json" '"path": "spec.sample.json"' "worked example pack points to sample spec"
check_contains "examples/worked-example/pack/pack.json" '"path": "spec.sample.confirmation.json"' "worked example pack points to sample confirmation"
check_contains "examples/worked-example/pack/pack.json" '"path": "notes/review-lens.md"' "worked example pack lists review-lens note"
check_contains "examples/worked-example/pack/pack.json" "derived_from_spec_sha256" "worked example pack records note source sha"
check_contains "examples/worked-example/pack/notes/review-lens.md" "subsidy_id: worked-sample" "worked example note limited frontmatter subsidy id"
check_contains "examples/worked-example/pack/notes/review-lens.md" "kind: review-lens" "worked example note limited frontmatter kind"
check_contains "examples/worked-example/pack/notes/review-lens.md" "[clause:" "worked example note cites clauses"
check_contains "examples/worked-example/pack/notes/review-lens.md" "合成データ" "worked example note states synthetic data"
check_contains "examples/worked-example/README.md" "bash tools/check-pack.sh examples/worked-example/pack" "worked example README documents check-pack"
if bash tools/check-pack.sh examples/worked-example/pack >/dev/null 2>&1; then
  ok
else
  bad "tools/check-pack.sh must pass on examples/worked-example/pack"
fi
if grep -qF -- "examples/worked-example" core-manifest.json; then
  bad "core-manifest.json must not include examples/worked-example"
else
  ok
fi
no_placeholder "examples/worked-example/pack/pack.json"
no_placeholder "examples/worked-example/pack/notes/review-lens.md"

# Wave: sponsor-page-and-boundary-faq
check_file "docs/sponsorship.md" 2000
check_contains "docs/sponsorship.md" "独立性宣言" "sponsorship starts with independence declaration"
check_contains "docs/sponsorship.md" "スポンサー資金は推薦順位・診断結果に一切影響しません" "sponsorship no influence declaration"
check_contains "docs/sponsorship.md" "data-charter の COI ファイアウォール" "sponsorship references data charter COI"
check_contains "docs/sponsorship.md" "25万円" "sponsorship tier 25万"
check_contains "docs/sponsorship.md" "100万円" "sponsorship tier 100万"
check_contains "docs/sponsorship.md" "200万円" "sponsorship tier 200万"
check_contains "docs/sponsorship.md" "非機能的便益" "sponsorship non-functional benefits only"
check_contains "docs/sponsorship.md" "データ維持インフラ" "sponsorship public infrastructure narrative"
check_contains "docs/sponsorship.md" "公募要領の改訂追随" "sponsorship supports guideline revision tracking"
check_contains "docs/sponsorship.md" "spec の鮮度" "sponsorship supports spec freshness"
check_contains "docs/sponsorship.md" "info@subsidy-support.tech" "sponsorship contact email"
check_contains "docs/sponsorship.md" "申請代行" "sponsorship excludes application agency"
check_contains "docs/sponsorship.md" "代理提出" "sponsorship excludes proxy submission"
check_contains "core-manifest.json" '"docs/sponsorship.md"' "core manifest includes sponsorship page"
check_contains "docs/faq.md" "## 境界線FAQ: 行政書士法との関係" "FAQ has administrative scrivener boundary heading"
check_contains "docs/faq.md" "自己完結型ソフト" "FAQ explains self-contained software boundary"
check_contains "docs/faq.md" "非接触原則" "FAQ explains non-contact principle"
check_contains "docs/faq.md" "## 境界線FAQ: 個人情報と result-report" "FAQ has personal data boundary heading"
check_contains "docs/faq.md" "利用者の repo にのみ存在" "FAQ explains input stays in user repo"
check_contains "docs/faq.md" "allowlist 限定" "FAQ explains result-report allowlist"
check_contains "docs/faq.md" "## 境界線FAQ: 補助金ビジネス批判への見解" "FAQ has subsidy business criticism heading"
check_contains "docs/faq.md" "支援業者が悪なのではありません" "FAQ states support providers are not the problem"
check_contains "docs/faq.md" "支援なしでは回らない" "FAQ names structural complexity problem"
check_contains "docs/faq.md" "無料の公共財" "FAQ states public-good stance"
check_relative_links "docs/sponsorship.md"
no_placeholder "docs/sponsorship.md"
no_placeholder "docs/faq.md"

# Wave: terms-draft-lift
for effective_doc in \
  TERMS.md \
  docs/data-policy.md \
  docs/telemetry.md \
  docs/licensing-tiers.md \
  docs/collaborator-招待手順.md \
  docs/governance/data-charter.md; do
  check_contains "$effective_doc" "発効日: 2026-07-05" "effective date after legal gate: $effective_doc"
done

# Wave: checker-strictness-review-p2
check_contains "tools/lib/check_pack.py" "PACK_KEYS" "check-pack validates top-level allowed keys"
check_contains "tools/lib/check_pack.py" "LISTED_FILE_KEYS" "check-pack validates spec/confirmation entry allowed keys"
check_contains "tools/lib/check_pack.py" "NOTE_ENTRY_KEYS" "check-pack validates notes entry allowed keys"
check_contains "tools/lib/check_pack.py" "unexpected key:" "check-pack reports additionalProperties violations"
check_contains "tools/lib/check_pack.py" "note frontmatter duplicate key:" "check-pack rejects duplicate limited frontmatter keys"
check_contains "tools/lib/check_pack.py" "check_examples_source_blocks" "check-pack checks examples source per heading block"
check_contains "tools/test-check-pack.sh" "top-level-extra-key" "check-pack test covers top-level extra key"
check_contains "tools/test-check-pack.sh" "spec-entry-extra-key" "check-pack test covers spec entry extra key"
check_contains "tools/test-check-pack.sh" "confirmation-entry-extra-key" "check-pack test covers confirmation entry extra key"
check_contains "tools/test-check-pack.sh" "note-entry-extra-key" "check-pack test covers note entry extra key"
check_contains "tools/test-check-pack.sh" "examples-second-block-no-source" "check-pack test covers examples block-level source"
check_contains "tools/test-check-pack.sh" "duplicate-frontmatter-key" "check-pack test covers duplicate frontmatter key"

check_contains "tools/lib/check_spec.py" "ISO8601_LIKE_RE" "check-spec validates confirmation confirmed_at format"
check_contains "tools/lib/check_spec.py" "confirmation.spec_sha256 must be a 64-character lowercase hex string" "check-spec validates confirmation sha format"
check_contains "tools/lib/check_spec.py" "confirmation.confirmed_at must look like ISO8601" "check-spec validates confirmation timestamp format"
check_contains "tools/test-check-spec.sh" "confirmation-missing-fixed-fields" "check-spec test covers missing fixed confirmation keys"
check_contains "tools/test-check-spec.sh" "confirmation-invalid-fixed-fields" "check-spec test covers invalid fixed confirmation values"

for strict_fixture in \
  tools/fixtures/spec/confirmation-missing-fixed-fields.json \
  tools/fixtures/spec/confirmation-missing-fixed-fields.confirmation.json \
  tools/fixtures/spec/confirmation-invalid-fixed-fields.json \
  tools/fixtures/spec/confirmation-invalid-fixed-fields.confirmation.json; do
  check_file "$strict_fixture" 1
  check_json "$strict_fixture"
  no_placeholder "$strict_fixture"
done

if bash tools/test-check-pack.sh >/dev/null 2>&1; then
  ok
else
  bad "tools/test-check-pack.sh must pass after checker-strictness-review-p2"
fi

if bash tools/test-check-spec.sh >/dev/null 2>&1; then
  ok
else
  bad "tools/test-check-spec.sh must pass after checker-strictness-review-p2"
fi

# Wave: kit-5-windows-git
check_contains "README.md" "## 動作環境" "README has runtime environment section"
check_contains "README.md" "動作確認済みの環境は macOS / Linux" "README states verified OS scope"
check_contains "README.md" "Windows はフル Windows 対応としては動作確認していません" "README is honest about Windows scope"
check_contains "README.md" "WSL を推奨" "README recommends WSL for Windows"
check_contains "README.md" "Git Bash と python3" "README documents Git Bash plus python3 fallback"

check_contains "docs/onboarding/02-claude-codeセットアップ.md" "動作確認済み: macOS / Linux" "onboarding setup states verified OS scope"
check_contains "docs/onboarding/02-claude-codeセットアップ.md" "Windows は WSL 推奨、または Git Bash + python3 導入が必要" "onboarding setup states Windows requirement"
check_contains "docs/onboarding/02-claude-codeセットアップ.md" "## git のインストール" "onboarding setup has git install section"
check_contains "docs/onboarding/02-claude-codeセットアップ.md" "git --version" "onboarding setup checks git version"
check_contains "docs/onboarding/02-claude-codeセットアップ.md" "xcode-select --install" "onboarding setup covers macOS git install"
check_contains "docs/onboarding/02-claude-codeセットアップ.md" "Git for Windows" "onboarding setup covers Git for Windows"
check_contains "docs/onboarding/02-claude-codeセットアップ.md" "https://git-scm.com/" "onboarding setup points to official Git site"
check_contains "docs/onboarding/02-claude-codeセットアップ.md" "パッケージマネージャ" "onboarding setup covers Linux package managers"

check_contains "docs/onboarding/03-このキットを自分のものにする.md" "git --version" "repo onboarding checks git before clone"
check_contains "docs/onboarding/03-このキットを自分のものにする.md" "git が入っているか確認" "repo onboarding has git presence branch"
check_contains "docs/onboarding/03-このキットを自分のものにする.md" "02-claude-codeセットアップ.md" "repo onboarding points missing git to setup doc"
check_in_order "docs/onboarding/03-このキットを自分のものにする.md" "repo onboarding checks git before git clone" \
  "git --version" \
  "git clone <コピーした URL>"

check_contains "docs/faq.md" "## Windows で動きますか" "FAQ has Windows section"
check_contains "docs/faq.md" "動作確認済みの環境は macOS / Linux" "FAQ states verified OS scope"
check_contains "docs/faq.md" "Windows はフル Windows 対応としては確認していません" "FAQ is honest about Windows scope"
check_contains "docs/faq.md" "WSL を推奨" "FAQ recommends WSL"
check_contains "docs/faq.md" "Git Bash + python3" "FAQ documents Git Bash plus python3 fallback"
check_contains "docs/faq.md" "py -3 --version" "FAQ mentions Windows Python launcher fallback"

check_contains ".claude/commands/setup.md" "python --version" "setup checks python fallback"
check_contains ".claude/commands/setup.md" "py -3 --version" "setup checks Windows py launcher fallback"
check_contains ".claude/commands/setup.md" "Python 3.x" "setup requires Python 3.x in fallback"
check_contains ".claude/commands/setup.md" "tools 実行時" "setup explains tools command read-through"
check_contains ".claude/commands/setup.md" "python3 --version" "setup keeps python3 pin"
check_contains ".claude/commands/setup.md" "tools/check-*.sh" "setup keeps tools checker pin"
check_contains ".claude/commands/setup.md" "公式インストーラー" "setup keeps official installer pin"

# Wave: kit-12-permissions
check_file ".claude/settings.json" 1
check_json ".claude/settings.json"

if python3 - <<'PY' >/dev/null 2>&1; then
import json
import pathlib

expected = [
    "Bash(python3 --version)",
    "Bash(command -v pdftotext)",
    "Bash(bash tools/check-spec.sh:*)",
    "Bash(bash tools/check-drafts.sh:*)",
    "Bash(bash tools/check-pack.sh:*)",
    "Bash(bash tools/draft-hash.sh:*)",
    "Bash(python3 tools/lib/predicate.py:*)",
]
settings = json.loads(pathlib.Path(".claude/settings.json").read_text(encoding="utf-8"))
actual = settings.get("permissions", {}).get("allow")
raise SystemExit(0 if actual == expected else 1)
PY
  ok
else
  bad ".claude/settings.json permissions.allow must exactly match read-only checker allowlist"
fi

for forbidden_permission in '"Write' '"Edit' '"Bash"' 'WebFetch'; do
  if grep -qF -- "$forbidden_permission" ".claude/settings.json"; then
    bad ".claude/settings.json must not include dangerous permission: $forbidden_permission"
  else
    ok
  fi
done

check_contains "core-manifest.json" "\".claude/settings.json\"" "core manifest includes settings"
check_contains "docs/faq.md" "## 許可を求められたら" "FAQ permission prompt section"
check_contains "docs/faq.md" "tools/check-*.sh" "FAQ explains bundled checker scripts"
check_contains "docs/faq.md" "読み取り専用" "FAQ explains checker read-only safety"
check_contains "docs/faq.md" "ファイル書き込みなし" "FAQ explains no file writes"
check_contains "docs/faq.md" "ネットワーク送信なし" "FAQ explains no network sending"
check_contains "docs/faq.md" "機能縮退" "FAQ explains degraded checks on denial"
check_contains "docs/faq.md" ".claude/settings.json" "FAQ explains settings pre-approval"
check_contains "docs/faq.md" "7 エントリ" "FAQ pins permission allowlist count"
check_contains "docs/faq.md" "workspace trust" "FAQ explains workspace trust"
check_contains "docs/faq.md" ".claude/settings.local.json" "FAQ directs user-specific permissions to local settings"

check_contains "docs/onboarding/03-このキットを自分のものにする.md" "Finder" "onboarding explains macOS Finder placement"
check_contains "docs/onboarding/03-このキットを自分のものにする.md" "エクスプローラー" "onboarding explains Windows Explorer placement"
check_contains "docs/onboarding/03-このキットを自分のものにする.md" "公募要領 PDF をそこへドラッグ" "onboarding explains PDF drag operation"
check_contains "docs/onboarding/03-このキットを自分のものにする.md" "input/guidelines/" "onboarding keeps guidelines path"

if python3 - <<'PY' >/dev/null 2>&1; then
import pathlib
import re

text = pathlib.Path(".claude/commands/start.md").read_text(encoding="utf-8")
match = re.search(r"^## 顧客に尋ねること\n(?P<section>.*?)(?=^## )", text, re.S | re.M)
if not match:
    raise SystemExit(1)
questions = re.findall(r"^\d+\. ", match.group("section"), re.M)
raise SystemExit(0 if len(questions) == 3 else 1)
PY
  ok
else
  bad ".claude/commands/start.md must have exactly 3 customer questions"
fi

check_contains ".claude/commands/start.md" '1. 対象にしたい補助金の公式募集要項、または同梱 `specs/` と照合できる資料はありますか。' "start customer question 1"
check_contains ".claude/commands/start.md" '2. 同梱 `specs/` の対象回を使えそうですか。それとも `/ingest-guidelines` で自分の募集要項から spec を作りますか。' "start customer question 2"
check_contains ".claude/commands/start.md" '3. spec 確定後に会社概要、売上、従業員数、投資予定、見積書などの自社資料を `input/` に置く準備はありますか。' "start customer question 3"

# Wave: ai-discovery-entry-pr1
check_file "README.en.md" 1000
check_file "docs/ai-agent-guide.md" 3000

if python3 - <<'PY'; then
import pathlib
import re


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def h2_sections(text):
    headings = list(re.finditer(r"^## .+$", text, re.M))
    result = []
    for index, heading in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        result.append((heading.group(0), text[heading.start():end]))
    return result


readme = pathlib.Path("README.md").read_text(encoding="utf-8")
sections = h2_sections(readme)
require(sections, "README has no H2 sections")
first_heading, first_section = sections[0]
require(first_heading == "## AI に手伝ってもらって始める（推奨）", "one-paste section is not first")
normalized_lines = [re.sub(r"^> ?", "", line) for line in first_section.splitlines()]
one_paste = [
    "補助金申請の事業計画書の叩き台を自分で作りたい。",
    "https://raw.githubusercontent.com/saita-kun/saita-kun-planner/main/docs/ai-agent-guide.md",
    "を読んで、その手順どおりに私を案内してください。",
]
require(
    any(normalized_lines[index:index + 3] == one_paste for index in range(len(normalized_lines) - 2)),
    "one-paste lines are not an exact consecutive block",
)
require("AI が上記 URL を閲覧できない場合" in first_section, "missing URL fallback condition")
require("あなた自身がブラウザで URL を開き" in first_section, "missing browser fallback")
require("表示された本文をチャットに貼り付け" in first_section, "missing paste fallback")

preamble = readme[:readme.index("\n## ")]
trust = "中小企業・個人事業主が、自分の Claude Code で補助金申請用の事業計画書の叩き台を作るためのキットです。キット本体は無料の OSS（Apache-2.0）ですが、利用には Claude Code の契約環境が必要です。申請代行ではありません。"
require(trust in preamble, "exact trust statement is not in the README introduction")
blocks = [block.strip() for block in re.split(r"\n\s*\n", preamble) if block.strip()]
prose = [
    block for block in blocks
    if not block.startswith("#")
    and not block.startswith("[")
    and not block.startswith("<!--")
]
intro = "\n\n".join(prose[:2])
for term in ("持続化補助金", "事業計画書", "テンプレート", "無料"):
    require(term in intro, f"missing intro term: {term}")
free_section = next((body for heading, body in sections if heading == "## なぜ無料で公開するのか"), "")
require("自分で申請" in free_section, "free-publication section lacks self-application wording")
require("版を固定したい場合" in first_section, "missing pinned-version guidance")
require(
    re.search(
        r"https://raw\.githubusercontent\.com/saita-kun/saita-kun-planner/(?:v[0-9]+\.[0-9]+\.[0-9]+|[0-9a-f]{7,40})/docs/ai-agent-guide\.md",
        first_section,
    ),
    "missing tag/commit-pinned guide URL",
)
PY
  ok
else
  bad "README AI entry assertions failed (AC-1.1 through AC-1.5)"
fi

if python3 - <<'PY'; then
import pathlib
import re


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def section(text, heading):
    match = re.search(rf"^{re.escape(heading)}\n(?P<body>.*?)(?=^## |\Z)", text, re.M | re.S)
    require(match is not None, f"missing section: {heading}")
    return match.group(0)


def contains_all(text, values, label):
    for value in values:
        require(value in text, f"{label} missing {value!r}")


guide = pathlib.Path("docs/ai-agent-guide.md").read_text(encoding="utf-8")
first_h2 = guide.index("\n## ")
metadata = guide[:first_h2]
contains_all(
    metadata,
    ("guide_version: 1.0.0", "更新日: 2026-07-17", "canonical repo: `saita-kun/saita-kun-planner`"),
    "guide metadata",
)
s0 = metadata + section(guide, "## S0 現在状態の検出と前提確認")
contains_all(
    s0,
    (
        "URL から取得できない AI",
        "表示された本文をチャットに貼り付け",
        "Claude Code の契約があるか",
        "無理に進めず",
        "https://github.com/saita-kun/saita-kun-planner/tree/main/docs/onboarding",
        "ここで案内を終了",
        "利用者の端末上の、セッション終了後もファイルが残る永続ファイルシステム",
        "代読案内モード",
        "自分の環境に clone しません",
        "core-manifest.json",
        ".claude/commands/",
        "gh repo view --json isPrivate,nameWithOwner,templateRepository,viewerPermission",
        "private であること",
        "saita-kun/saita-kun-planner` **ではない",
        "viewerPermission` が書込可能",
        "次の 3 条件をすべて満たす場合のみ、S3",
        "public だった、canonical 本体だった、確認できず不明だった場合",
        "この repo には機密情報を書き込まないでください",
        "S1 → S2",
        "`Private` ラベル",
        "目視で確認",
    ),
    "S0",
)
s1 = section(guide, "## S1 作業用 repo 作成の本人同意")
contains_all(
    s1,
    (
        "repo 名",
        "<owner>/<repo>",
        "必ず private",
        "clone 先の絶対パス",
        "指定パスがまだ存在しないこと",
        "親ディレクトリに書き込みできること",
        "同意なく外部サービスに repo を作成しないでください。",
    ),
    "S1",
)
s2 = section(guide, "## S2 repo 作成と clone")
contains_all(
    s2,
    (
        "gh auth status",
        'gh repo clone <owner>/<repo> "<承認済みの絶対パス>"',
        "repo は GitHub 上に作成済みで、手元への clone だけが失敗している",
        "`gh` がない・未認証・代読案内モードで、**利用者がまだ repo を作っていない場合**",
        "`gh` がない・未認証で、**利用者が既に自分の作業 repo を作成済みの場合**",
        "Use this template",
        "代読案内モード",
    ),
    "S2",
)
create_blocks = [
    block.strip()
    for block in re.findall(r"```bash\n(.*?)```", s2, re.S)
    if "gh repo create" in block
]
require(len(create_blocks) == 1, "S2 must have one gh repo create command block")
require(
    create_blocks[0] == "gh repo create <owner>/<repo> --template saita-kun/saita-kun-planner --private",
    "gh repo create command must be exact and must not use --clone",
)
s3 = section(guide, "## S3 新しい Claude Code セッションへの引き渡し")
contains_all(
    s3,
    ("clone したディレクトリをルートとして", "新しい Claude Code セッション", "現在のセッションの役目はここで終了"),
    "S3",
)
s4 = section(guide, "## S4 最初のコマンド")
setup_pos = s4.find("/setup")
start_pos = s4.find("/start")
require(0 <= setup_pos < start_pos, "S4 command order must be /setup then /start")

guardrails = section(guide, "## 全体で守るガードレール")
contains_all(
    guardrails,
    ("作成主体は利用者本人", "作成代行・代理提出", "数値・要件を推測しません", "[要確認]", "現行の公募回"),
    "guide guardrails",
)
expectations = section(guide, "## 最初の 30 分で得られるもの（正直な期待値）")
contains_all(
    expectations,
    ("対象補助金が同梱 spec にあり", "対象補助金が未定、または資料が未準備", "30 分で申請書や事業計画書が完成するとは案内しない"),
    "guide expectations",
)

for target in re.findall(r"\]\(([^)]+)\)", guide):
    require(
        target.startswith("https://github.com/saita-kun/saita-kun-planner/")
        or target.startswith("https://raw.githubusercontent.com/saita-kun/saita-kun-planner/"),
        f"relative Markdown link in guide: {target}",
    )
visible = re.sub(r"```.*?```", "", guide, flags=re.S)
visible = re.sub(
    r"\[[^\]]+\]\(https://(?:github\.com|raw\.githubusercontent\.com)/"
    r"saita-kun/saita-kun-planner/[^)]+\)",
    "",
    visible,
)
visible = re.sub(
    r"https://(?:github\.com|raw\.githubusercontent\.com)/saita-kun/saita-kun-planner/[^\s)>]+",
    "",
    visible,
)
bare_docs = re.findall(r"(?<![\w.-])docs/[^\s`)>]+", visible)
require(not bare_docs, f"bare docs path in guide prose: {bare_docs}")
root_documents = {
    path.name
    for path in pathlib.Path(".").iterdir()
    if path.is_file()
    and (path.suffix.lower() in {".md", ".markdown"} or path.name in {"LICENSE", "NOTICE"})
}
root_document_pattern = re.compile(
    r"(?<![\w.-])(?:"
    + "|".join(re.escape(name) for name in sorted(root_documents, key=len, reverse=True))
    + r")(?![\w.-])"
)
bare_root_documents = sorted(set(root_document_pattern.findall(visible)))
require(
    not bare_root_documents,
    f"bare root document reference in guide prose: {bare_root_documents}",
)
require("必ず private" in guide, "guide lacks mandatory private wording")
require("private を推奨" not in guide, "guide retains recommended-private wording")
PY
  ok
else
  bad "AI agent guide state-machine assertions failed (AC-2.1 through AC-2.4)"
fi

for setup_anchor in \
  'input/setup-state.json' \
  'setup_state_version' \
  'setup_completed_at' \
  'terms_sha256' \
  'data_policy_sha256' \
  'result_report_choice' \
  'TERMS.md' \
  'docs/data-policy.md' \
  'shasum -a 256' \
  'すべての確認項目が green で、利用者本人の利用規約への同意を確認した後にのみ'; do
  check_contains ".claude/commands/setup.md" "$setup_anchor" "setup-state anchor: $setup_anchor"
done

if python3 - <<'PY'; then
import json
import pathlib
import re


def require(condition, message):
    if not condition:
        raise SystemExit(message)


setup = pathlib.Path(".claude/commands/setup.md").read_text(encoding="utf-8")
json_blocks = re.findall(r"^```json[ \t]*\n(.*?)^```[ \t]*$", setup, re.M | re.S)
documents = []
for index, raw in enumerate(json_blocks):
    try:
        document = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"setup fenced JSON block {index + 1} is invalid: {exc}")
    if isinstance(document, dict) and "setup_state_version" in document:
        documents.append(document)

require(len(documents) == 1, "setup must contain exactly one setup-state fenced JSON object")
setup_state = documents[0]
expected_keys = {
    "setup_state_version",
    "setup_completed_at",
    "terms_sha256",
    "data_policy_sha256",
    "result_report_choice",
}
require(
    set(setup_state) == expected_keys,
    f"setup-state keys mismatch: {sorted(set(setup_state) ^ expected_keys)}",
)
version = setup_state["setup_state_version"]
require(type(version) is int and version == 1, "setup_state_version must be integer 1")
PY
  ok
else
  bad "setup-state fenced JSON contract failed (AC-3.1)"
fi

for preflight_anchor in \
  '/setup` 以外のすべての slash command' \
  'input/setup-state.json' \
  '存在しない' \
  'JSON として読めない' \
  'terms_sha256' \
  'data_policy_sha256' \
  '一致しない' \
  '/setup` の実行（または再実行）'; do
  check_contains "CLAUDE.md" "$preflight_anchor" "common setup preflight anchor: $preflight_anchor"
done

if python3 - <<'PY'; then
import pathlib
import re


def require(condition, message):
    if not condition:
        raise SystemExit(message)


standard = {
    "build-pack.md", "confirm-spec.md", "draft-section.md", "finalize.md",
    "ingest-guidelines.md", "intake.md", "plan-deliverables.md", "retrospect.md",
    "review.md", "select-subsidy.md", "start.md", "subsidy-fit.md", "verify.md",
}
command_dir = pathlib.Path(".claude/commands")
actual = {path.name for path in command_dir.glob("*.md")}
required = standard | {"setup.md"}
require(required <= actual, f"required command missing: {sorted(required - actual)}")
for name in sorted(standard):
    text = (command_dir / name).read_text(encoding="utf-8")
    require(text.startswith("---\n"), f"{name}: missing frontmatter")
    end = text.find("\n---\n", 4)
    require(end >= 0, f"{name}: unclosed frontmatter")
    body = text[end + 5:].strip()
    blocks = [block.strip() for block in re.split(r"\n\s*\n", body) if block.strip()]
    command_name = name[:-3]
    require(blocks and blocks[0] == f"# /{command_name}", f"{name}: command heading position")
    require(len(blocks) > 1 and blocks[1].startswith("**preflight（setup ゲート）**:"), f"{name}: preflight is not first paragraph")
    contains = blocks[1]
    for anchor in ("CLAUDE.md", "input/setup-state.json", "欠損・破損・sha256 不一致", "/setup"):
        require(anchor in contains, f"{name}: preflight missing {anchor}")


def h2_section(path, heading):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    match = re.search(rf"^{re.escape(heading)}\n(?P<body>.*?)(?=^## |\Z)", text, re.M | re.S)
    require(match is not None, f"{path}: missing {heading}")
    return match.group("body")


entry_sections = (
    ("README.md", "## このリポジトリの使い方（Use this template）"),
    ("README.md", "## 5分クイックスタート"),
    ("docs/テンプレートrepoの使い方.md", "## 2. clone して Claude Code で開く"),
)
for path, heading in entry_sections:
    body = h2_section(path, heading)
    numbered_steps = [
        line for line in body.splitlines() if re.match(r"^\d+\.\s+", line)
    ]
    instruction_text = "\n".join(numbered_steps) if numbered_steps else body
    position = -1
    for anchor in ("clone", "新しい Claude Code セッション", "/setup", "/start"):
        next_position = instruction_text.find(anchor, position + 1)
        require(next_position > position, f"{path} {heading}: sequence breaks at {anchor}")
        position = next_position
PY
  ok
else
  bad "setup preflight position or entry sequence failed (AC-3.3 / AC-3.4)"
fi

if python3 - <<'PY'; then
import pathlib
import re


def require(condition, message):
    if not condition:
        raise SystemExit(message)


for path in ("README.md", "docs/補助金の選び方.md"):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    match = re.search(
        r"^#{2,3} .*対象の補助金がまだ決まっていない場合.*\n(?P<body>.*?)(?=^#{2,3} |\Z)",
        text,
        re.M | re.S,
    )
    require(match is not None, f"{path}: missing undecided-subsidy section")
    body = match.group(0)
    web_pos = body.find("Jグランツ」の Web 検索")
    mcp_pos = body.find("jgrants-mcp-server")
    require(0 <= web_pos < mcp_pos, f"{path}: J-Grants Web search must precede MCP")
    for anchor in (
        "技術検証を目的として公開されているサンプルコード",
        "安定性・継続的な保守・検索性は保証されない",
        "https://github.com/digital-go-jp/jgrants-mcp-server",
        "提携・公認の関係はありません",
        "Jグランツ API の利用規約",
        "制度事実",
        "必ず公式の公募要領で再確認",
        "入口B `/ingest-guidelines` に投入するのは",
        "公式公募要領",
    ):
        require(anchor in body, f"{path}: J-Grants section missing {anchor!r}")
require("jGrants" not in pathlib.Path("docs/補助金の選び方.md").read_text(encoding="utf-8"), "legacy jGrants spelling remains")
PY
  ok
else
  bad "J-Grants discovery assertions failed (AC-4.1 / AC-4.2 / AC-4.4)"
fi

for english_legal_sentence in \
  'The applicant is the sole author of the application.' \
  'The AI assists with organizing information and drafting; it is not a filing agent and does not submit anything.' \
  'The AI must not guess numbers or requirements.' \
  'Unverified information is marked with [要確認] (a machine-readable marker; do not translate it).' \
  'The official call-for-applications documents always take precedence.' \
  'Completion and submission decisions are made only by the applicant.'; do
  check_contains "README.en.md" "$english_legal_sentence" "English legal invariant: $english_legal_sentence"
done
check_contains "README.en.md" "Your working repository must be private." "English README requires private work repo"

if python3 - <<'PY'; then
import pathlib
import re
import sys

sys.path.insert(0, "tools/lib")
import check_forbidden_phrases as checker


def require(condition, message):
    if not condition:
        raise SystemExit(message)


english = pathlib.Path("README.en.md").read_text(encoding="utf-8")
headings = re.findall(r"^## (.+)$", english, re.M)
required = ["What it is", "Who it is for", "Quickstart", "Legal scope", "License", "Language notice"]
require(all(heading in headings for heading in required), "English README required heading missing")
quickstart = re.search(r"^## Quickstart\n(?P<body>.*?)(?=^## |\Z)", english, re.M | re.S)
require(quickstart is not None, "English Quickstart missing")
one_paste = [
    "I want to draft a business plan for a Japanese subsidy application myself.",
    "Read https://raw.githubusercontent.com/saita-kun/saita-kun-planner/main/docs/ai-agent-guide.md",
    "and guide me through it, following its steps.",
]
quickstart_lines = [re.sub(r"^> ?", "", line) for line in quickstart.group("body").splitlines()]
require(
    any(
        quickstart_lines[index:index + 3] == one_paste
        for index in range(len(quickstart_lines) - 2)
    ),
    "English one-paste lines are not an exact consecutive block",
)
hits, _ = checker.find_forbidden(english, "README.en.md")
require(not [hit for hit in hits if hit.language == "en"], "English prohibited claim found")
language = re.search(r"^## Language notice\n(?P<body>.*?)(?=^## |\Z)", english, re.M | re.S)
require(language is not None, "Language notice missing")
require("Japanese [README.md]" in language.group(0) and "canonical document" in language.group(0), "Japanese canonical notice missing")
require("operational workflow is Japanese" in language.group(0), "Japanese workflow notice missing")

readme = pathlib.Path("README.md").read_text(encoding="utf-8")
preamble = readme[:readme.index("\n## ")]
require(re.search(r"\[[^\]]*English[^\]]*\]\(README\.en\.md\)", preamble), "English README link is not in README preamble")
PY
  ok
else
  bad "English README assertions failed (AC-5.2 / AC-5.3 / AC-5.5 / AC-5.6)"
fi

for forbidden_checker_file in \
  tools/lib/export-excluded-paths.txt \
  tools/lib/check_forbidden_phrases.py \
  tools/forbidden-phrase-allowlist.json \
  tools/fixtures/forbidden/cases.json \
  tools/fixtures/forbidden/legal-negative.json \
  tools/fixtures/forbidden/adversarial.json \
  tools/test-forbidden-phrases.sh; do
  check_file "$forbidden_checker_file" 1
  no_placeholder "$forbidden_checker_file"
done
for forbidden_fixture in \
  tools/forbidden-phrase-allowlist.json \
  tools/fixtures/forbidden/cases.json \
  tools/fixtures/forbidden/legal-negative.json \
  tools/fixtures/forbidden/adversarial.json; do
  check_json "$forbidden_fixture"
done

if bash tools/test-forbidden-phrases.sh >/dev/null; then
  ok
else
  bad "tools/test-forbidden-phrases.sh failed (AC-5.3 / AC-6.2 through AC-6.4)"
fi

if python3 tools/lib/check_forbidden_phrases.py; then
  ok
else
  bad "forbidden phrase checker rejected public customer text (AC-6.5)"
fi

if python3 - <<'PY'; then
import pathlib
import sys

sys.path.insert(0, "tools/lib")
import check_forbidden_phrases as checker

root = pathlib.Path(".")
forbidden_literals = (
    "公式 MCP",
    "デジタル庁提供",
    "デジタル庁が公式に提供",
    "private を推奨",
    "private にすることを推奨",
    "Private を推奨",
    "private repo での管理を推奨します",
    "公開 repo に置く場合",
)
hits = []
for relative_path in checker.repository_text_paths(root):
    text = (root / relative_path).read_text(encoding="utf-8")
    for literal in forbidden_literals:
        if literal in text:
            hits.append((relative_path, literal))
if hits:
    for path, literal in hits:
        print(f"{path}: {literal}")
    raise SystemExit(1)
PY
  ok
else
  bad "export customer text retains prohibited J-Grants/private wording (AC-4.3 / AC-7.1)"
fi

check_contains "README.md" "作業用 repo は必ず private にしてください" "README mandates private work repo"
check_contains "docs/テンプレートrepoの使い方.md" "作業用 repo は必ず private にしてください" "template guide mandates private work repo"

if python3 - <<'PY'; then
import json
import pathlib


manifest = json.loads(pathlib.Path("core-manifest.json").read_text(encoding="utf-8"))
core_paths = manifest.get("core_paths")
if not isinstance(core_paths, list):
    raise SystemExit("core_paths must be an array")
required = {
    ".gitattributes",
    "README.en.md",
    "docs/ai-agent-guide.md",
    "tools/lib/export-excluded-paths.txt",
    "tools/lib/check_forbidden_phrases.py",
    "tools/forbidden-phrase-allowlist.json",
    "tools/fixtures/forbidden/cases.json",
    "tools/fixtures/forbidden/legal-negative.json",
    "tools/fixtures/forbidden/adversarial.json",
    "tools/test-forbidden-phrases.sh",
}
members = set(core_paths)
missing = sorted(required - members)
if missing:
    raise SystemExit(f"core manifest missing PR-1 paths: {missing}")
PY
  ok
else
  bad "core manifest PR-1 array membership failed"
fi

# AC-15 explicitly pins placeholder coverage for PR-1 shipped documents.
no_placeholder "README.en.md"
no_placeholder "docs/ai-agent-guide.md"

# Wave: trust-freshness-pr2
CANONICAL_ADOPTER_ISSUE_URL="https://github.com/saita-kun/saita-kun-planner/issues/new?template=adopter-entry.yml"

check_file "ADOPTERS.md" 1000
check_contains "ADOPTERS.md" "補助金の採択者一覧ではありません" "ADOPTERS is not an awardee list"
check_contains "ADOPTERS.md" "$CANONICAL_ADOPTER_ISSUE_URL" "ADOPTERS canonical Issue route"
check_contains "CONTRIBUTING.md" "$CANONICAL_ADOPTER_ISSUE_URL" "CONTRIBUTING canonical adopter Issue route"
for adopters_anchor in \
  "本人または掲載の権限を持つ者のみ" \
  "制度の正式名称・公募回・年度・地域" \
  "申請中の情報" \
  "申請本文" \
  "個人情報" \
  "具体的数値" \
  "採否・採択率は記載できません" \
  "公認" \
  "提携" \
  "認定" \
  "自己申告" \
  "運営は内容を検証しません" \
  "掲載は推薦・認定・成果の保証ではありません" \
  "掲載の削除依頼" \
  "完全には消えません" \
  "アカウント名と別の名称" \
  "投稿した GitHub アカウント" \
  "公開されます"; do
  check_contains "ADOPTERS.md" "$adopters_anchor" "ADOPTERS rule: $adopters_anchor"
done

if python3 - <<'PY'; then
import pathlib
import re


adopters = pathlib.Path("ADOPTERS.md").read_text(encoding="utf-8")
preamble = adopters.split("\n## ", 1)[0]
if "補助金の採択者一覧ではありません" not in preamble:
    raise SystemExit("ADOPTERS definition must be in the preamble")

readme = pathlib.Path("README.md").read_text(encoding="utf-8")
section = re.search(
    r"^## 標準ファイルとコミュニティ導線\n(?P<body>.*?)(?=^## |\Z)",
    readme,
    re.M | re.S,
)
if section is None or "[ADOPTERS.md](ADOPTERS.md)" not in section.group("body"):
    raise SystemExit("README community section must contain the ADOPTERS row")
PY
  ok
else
  bad "ADOPTERS preamble / README community row assertions failed (AC-9.1 / AC-9.4)"
fi

check_file ".github/ISSUE_TEMPLATE/adopter-entry.yml" 1000
check_file "tools/lib/check_trust_freshness.py" 10000
check_contains "tools/lib/check_trust_freshness.py" "class YamlSubsetParser" "stdlib Issue Form YAML subset parser"
check_contains "tools/lib/check_trust_freshness.py" "spec_resolver.resolve_bundled_specs" "freshness validation uses shared resolver"
check_contains "tools/lib/check_trust_freshness.py" "check_spec.check_confirmation_spec_reference" "freshness validation checks confirmation spec path and version binding"
check_contains "tools/lib/check_trust_freshness.py" "check_spec.check_confirmation_sha" "freshness validation checks confirmation spec sha binding"
check_contains "tools/test-check-spec.sh" "trust-freshness/stale-spec-sha" "freshness validation test covers stale confirmation sha fixture"
for trust_binding_json in \
  tools/fixtures/trust-freshness/stale-spec-sha/freshness-stale-sha/pack.json \
  tools/fixtures/trust-freshness/stale-spec-sha/freshness-stale-sha/freshness-stale-sha.json \
  tools/fixtures/trust-freshness/stale-spec-sha/freshness-stale-sha/freshness-stale-sha.confirmation.json; do
  check_file "$trust_binding_json" 1
  check_json "$trust_binding_json"
  check_contains "core-manifest.json" "\"$trust_binding_json\"" "core manifest includes $trust_binding_json"
  no_placeholder "$trust_binding_json"
done
if python3 tools/lib/check_trust_freshness.py adopter-form >/dev/null; then
  ok
else
  bad "adopter Issue Form YAML structure invalid (AC-10.1 through AC-10.4)"
fi

if python3 tools/lib/check_trust_freshness.py freshness-table >/dev/null; then
  ok
else
  bad "spec freshness table does not match provider-confirmed canonical packs (AC-11.1 / AC-11.2)"
fi
check_contains "README.md" "同梱 spec には原本突合日を明記しています" "README mentions bundled spec source-check dates"
check_contains "README.md" "[specs/README.md](specs/README.md)" "README links freshness table"
check_contains "README.md" "制度の正本は常に公式の募集要項です" "README keeps official guidelines authoritative"

check_contains "tools/lib/check_spec.py" "def evaluate_application_deadlines" "single deadline evaluator"
check_contains "tools/lib/check_spec.py" "deadline_evaluations = evaluate_application_deadlines" "checker evaluates deadlines once"
check_contains "tools/lib/check_spec.py" "if gate == \"select\"" "select gate dispatch"
check_contains "tools/lib/check_spec.py" "provider confirmation requires spec.round" "provider round requirement"
check_contains "tools/lib/check_spec.py" "provider confirmation requires spec.portal_url" "provider portal requirement"
check_contains "tools/lib/spec_resolver.py" "def resolve_bundled_specs" "shared bundled spec resolver"
check_contains "tools/test-check-spec.sh" "2026-12-15T17:00:00+09:00" "deadline equality boundary test"
check_contains "tools/test-check-spec.sh" "pack-flat-conflict" "resolver pack/flat precedence test"

for select_anchor in \
  "bash tools/check-spec.sh --list-bundled" \
  "bash tools/check-spec.sh <spec> --gate select" \
  "入口Aの候補から除外" \
  "入口B（\`/ingest-guidelines\`）" \
  "live で原本を再確認"; do
  check_contains ".claude/commands/select-subsidy.md" "$select_anchor" "select-subsidy freshness instruction: $select_anchor"
done

for trust_json in \
  tools/fixtures/spec/deadline-past.json \
  tools/fixtures/spec/deadline-start-past-future.json \
  tools/fixtures/spec/deadline-multiple-partial.json \
  tools/fixtures/spec/deadline-date-only.json \
  tools/fixtures/spec/deadline-time.json \
  tools/fixtures/spec/provider-null-round.json \
  tools/fixtures/spec/provider-null-round.confirmation.json \
  tools/fixtures/spec/provider-null-portal-url.json \
  tools/fixtures/spec/provider-null-portal-url.confirmation.json \
  tools/fixtures/spec/provider-missing-item-confirmed-at.json \
  tools/fixtures/spec/provider-missing-item-confirmed-at.confirmation.json \
  tools/fixtures/spec/provider-invalid-item-confirmed-at.json \
  tools/fixtures/spec/provider-invalid-item-confirmed-at.confirmation.json \
  tools/fixtures/spec/provider-customer-null-boundary.json \
  tools/fixtures/bundled-resolver/flat-duplicate/one.json \
  tools/fixtures/bundled-resolver/flat-duplicate/two.json \
  tools/fixtures/bundled-resolver/pack-flat-conflict/resolver-conflict.json \
  tools/fixtures/bundled-resolver/pack-flat-conflict/canonical/pack.json \
  tools/fixtures/bundled-resolver/pack-flat-conflict/canonical/resolver-conflict-pack.json \
  tools/fixtures/bundled-resolver/pack-duplicate/one/pack.json \
  tools/fixtures/bundled-resolver/pack-duplicate/one/one.json \
  tools/fixtures/bundled-resolver/pack-duplicate/two/pack.json \
  tools/fixtures/bundled-resolver/pack-duplicate/two/two.json \
  tools/fixtures/bundled-resolver/stable-order/alpha.json \
  tools/fixtures/bundled-resolver/stable-order/zeta.json; do
  check_file "$trust_json" 1
  check_json "$trust_json"
  no_placeholder "$trust_json"
done

if python3 - <<'PY'; then
import json
import pathlib


required = {
    "ADOPTERS.md",
    ".github/ISSUE_TEMPLATE/adopter-entry.yml",
    "tools/lib/spec_resolver.py",
    "tools/lib/check_trust_freshness.py",
}
required.update(
    path.as_posix()
    for base in (
        pathlib.Path("tools/fixtures/bundled-resolver"),
    )
    for path in base.rglob("*")
    if path.is_file()
)
required.update(
    path.as_posix()
    for path in pathlib.Path("tools/fixtures/spec").glob("deadline-*.json")
)
required.update(
    path.as_posix()
    for path in pathlib.Path("tools/fixtures/spec").glob("provider-*.json")
)
manifest = json.loads(pathlib.Path("core-manifest.json").read_text(encoding="utf-8"))
members = set(manifest.get("core_paths", []))
missing = sorted(required - members)
if missing:
    raise SystemExit(f"core manifest missing PR-2 paths: {missing}")
PY
  ok
else
  bad "core manifest PR-2 array membership failed (AC-13.1)"
fi

# AC-15 explicitly pins placeholder coverage for PR-2 shipped documents.
no_placeholder "ADOPTERS.md"
no_placeholder ".github/ISSUE_TEMPLATE/adopter-entry.yml"
no_placeholder "specs/README.md"
no_placeholder "tools/lib/spec_resolver.py"
no_placeholder "tools/lib/check_trust_freshness.py"

# Wave: public-decision-records — design invariants published for operating AIs.
# Each record must exist with the decision/constraints/violation structure, and
# AGENTS.md / CLAUDE.md must route operating AIs to the directory.
check_file "docs/design/decisions/README.md" 500
for dr_file in \
  docs/design/decisions/dr-001-one-paste-url-main-fixed.md \
  docs/design/decisions/dr-002-setup-gate-entry-unification.md \
  docs/design/decisions/dr-003-no-eligibility-judgement.md \
  docs/design/decisions/dr-004-upstream-independent-self-run.md \
  docs/design/decisions/dr-005-pitfall-to-check-promotion.md \
  docs/design/decisions/dr-006-forbidden-expression-check-self-contained.md \
  docs/design/decisions/dr-007-spec-freshness-machine-gate.md \
  docs/design/decisions/dr-008-adopters-canonical-issue-only.md
do
  check_file "$dr_file" 500
  check_contains "$dr_file" "## 決定" "decision record has decision section: $dr_file"
  check_contains "$dr_file" "## 制約（運用 AI が守ること）" "decision record has constraints section: $dr_file"
  check_contains "$dr_file" "## 違反例" "decision record has violation-examples section: $dr_file"
  check_contains "$dr_file" "内部決定記録（非公開）" "decision record cites internal source generically: $dr_file"
  no_placeholder "$dr_file"
done
check_contains "docs/design/decisions/README.md" "dr-008-adopters-canonical-issue-only.md" "decisions index lists all records"
no_placeholder "docs/design/decisions/README.md"
check_contains "AGENTS.md" "docs/design/decisions/" "AGENTS.md routes agents to decision records"
check_contains "CLAUDE.md" "docs/design/decisions/" "CLAUDE.md routes operating AIs to decision records"
# Continuity-policy anchors: the invariants live where operators actually read.
check_contains "docs/design/repo-structure.md" "decisions/dr-004-upstream-independent-self-run.md" "repo-structure states upstream-independence invariant"
check_contains "ROADMAP.md" "docs/design/decisions/dr-004-upstream-independent-self-run.md" "ROADMAP marks registry as convenience layer with DR-004 link"
check_contains "ROADMAP.md" "生命線ではありません" "ROADMAP says registry is not a lifeline"
check_contains "docs/改善ループ.md" "design/decisions/dr-005-pitfall-to-check-promotion.md" "improvement loop documents pitfall promotion path"
check_contains "docs/改善ループ.md" "## 落とし穴の昇格経路" "improvement loop has pitfall promotion section"
# Business-judgement docs stay internal: the records may cite them only as the
# generic phrase above, never by internal path.
for dr_file in docs/design/decisions/*.md; do
  if grep -qE "docs/strategy/|wave-plans\.md|harness-backlog\.md|pivot-decision\.md|docs/plans/" "$dr_file"; then
    bad "decision record references internal-only path: $dr_file"
  else
    ok
  fi
done

echo "=== validate: $PASS pass / $FAIL fail ==="
[ "$FAIL" -eq 0 ]
