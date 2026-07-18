# 設計: 募集要項⇄AI 橋渡しハーネス（subsidy-spec 駆動ループ）

> 本ファイルは saita-kun-planner の「spec 駆動ループ」設計説明。
> 決定日: 2026-07-02（DRI: 代表）。レビュー1（Codex 設計レビュー、P1 9件）反映済み。
> 公開版では、利用者が把握すべき設計原則と現行の構造だけを記録する。
> 関連設計: 補助金パックと builder 工程は [docs/design/harness-pack-builder.md](harness-pack-builder.md) を参照。

## 0. 前提（DRI 決定 2026-07-02）

1. **提供物は「クライアントが持ち込む AI が使うハーネス」**。スラッシュコマンド・スキーマ・同梱 spec・検証ゲート・マニュアルの足場一式。API キー・提供側の AI 実行・サーバ側処理は一切含まない。
2. **スコープは「提出できる状態」を作るまで**（final-checklist 全緑）。提出行為・提出代行・完成判断は提供せず、顧客本人が行う（既存キット規約と同一）。
3. **配布は public OSS template repo**。コピー・書き換えは防がず、本家=正史ポジションを取る。
4. **データ回収は result-report 任意提出の段階型**（本設計では application-record までを実装、送信は次フェーズ）。
5. **moat は構造化補助金フィード側**。MVP は spec ファイル同梱、次フェーズで spec レジストリから実行時取得へ移行。＜2026-07-17 注記（2点更新）＞ (1) 「moat」の框架は 2026-07-14 の運営方針決定により撤回。本キットの運営判断は公共の福祉（自走成功率・労力低減）と持ち出し最小を基準にし、利益・moat・競合優位を判断根拠にしない（README「なぜ無料で公開するのか」参照）。構造化補助金フィードを中核資産として公共財化する方針は維持。 (2) レジストリの形は「実行時取得」ではなく「公開 data repo からのパック導入（取得したパックを同梱パック相当として resolver で解決）」に確定。配布アーキテクチャの正本は `docs/design/repo-structure.md`。
6. **対象は 300 万円未満クラスの補助金**（持続化補助金クラスの様式構造・特例枠・加点構造に耐える）。
7. **スキーマは本ハーネス用に新規設計**（最高品質優先）。backend `subsidy.schema.json` の実証済み要素（clauses 真実源等）は素材として継承し、本リポ `schemas/subsidy-spec.schema.json` を**正本**とする。
8. **実行環境前提**: 顧客側に `python3`（標準ライブラリのみ使用）と `bash` がある。`/setup` の環境セルフチェックで確認する。AI 非依存の機械検証はこの前提で実装する。

### 0.1 2026-07-03 改訂決定: フロー順を「募集要項 → 会社情報」に変更（DRI 決定）

**決定**: 現行フロー（`/intake` 会社情報 → 補助金選択）を逆転し、**募集要項の登録・確定を先に、会社情報のヒアリングを後に**する。

**根拠**: 募集要項の `eligibility.rules[]`（除外・必須・加点）と scoring 項目が「どの会社情報を聞くべきか」を決める。spec を把握してから聞けば **spec 駆動の targeted hearing** になり、汎用の総当たりヒアリングより精度・効率が上がる。

**新フロー**:
```
/setup → /start → 補助金選択（入口A 同梱 spec ／ 入口B /ingest-guidelines で募集要項→draft spec 化 → /confirm-spec で突合）
→ /build-pack（推奨。confirmed spec から書き方メモを作る）
→ /intake（confirmed spec の rules/scoring が参照する company-profile キーを優先した spec 駆動ヒアリング）
→ /subsidy-fit → /plan-deliverables → /draft-section×n → /review → /verify → /finalize → /retrospect
```

**新状態遷移**: `spec_draft → spec_confirmed → intake_done → fit_done → planned → drafting → verified → finalized`。current-application.json は入口Aでは `spec_confirmed`、入口Bでは `/ingest-guidelines` 完了時に `spec_draft` で初期化され、`/confirm-spec` が突合完了後に `spec_confirmed` へ更新する。

**現行実装**: `/select-subsidy` または `/ingest-guidelines` → `/confirm-spec` で confirmed spec を先に確定し、必要に応じて `/build-pack` で書き方メモを作ってから `/intake` で会社情報を整理する順序に更新済み。補助金パックと工程分割の正本は [docs/design/harness-pack-builder.md](harness-pack-builder.md) とし、§1 と §4 はその状態機械に合わせる。

**変更surface（反映済み）**:
- `/intake`: 前提 state を `spec_confirmed` に。spec を読んで rules/scoring 参照キーを優先ヒアリング。末尾「想定補助金分野」節は補助金確定済みのため簡素化/除去。current-application 初期化を廃し `intake_done` 更新に。
- `/ingest-guidelines` / `/confirm-spec` / 入口A: 入口Bを読み込みと突合確認に分割。`/ingest-guidelines` は `state=spec_draft` を作り、`/confirm-spec` が confirmed へ昇格する。入口Aは従来どおり `state=spec_confirmed`。
- `/build-pack`: confirmed spec 以降の推奨工程として書き方メモを作る。
- `/start`・`/setup`・README・CLAUDE.md・docs/manual.md・docs/faq.md（実行順）・docs/補助金の選び方.md: フロー順を更新。
- `tools/validate.sh`: 順序依存アサーション（intake の「想定補助金分野」検査・cmd ループ・manual 記述）を更新。
- E2E フィクスチャ（`input/e2e-2026-07-02/`）: 新順に合わせて再実行/更新。

## 1. ユーザー体験（コアループと正規状態遷移）

```
補助金を選ぶ
  ├─ 入口A: /select-subsidy — 同梱パック（specs/<subsidy_id>/<subsidy_id>.json 優先）を選択
  └─ 入口B: /ingest-guidelines — 募集要項 PDF/URL/本文 → input/spec/<subsidy_id>.json または input/spec/<subsidy_id>/<subsidy_id>.json（status=draft）
        ↓ state=spec_draft で current-application.json を作成
/confirm-spec ───────── 人間確認ゲート: spec⇄原本 突合 → confirmation report → status=confirmed → state=spec_confirmed
/build-pack ─────────── confirmed spec から書き方メモを作る（推奨。notes なしでも下流は動く）
/intake ──────────────── confirmed spec の rules/scoring に沿った会社情報の構造化（company-profile: JSON 正本 + md ビュー）
   ↓ state=intake_done
/subsidy-fit ─────────── 3段階 explainable matching（除外→必須→加点）+ 狙う枠（base+add-ons）の記録
   ↓
/plan-deliverables ───── 成果物マニフェスト + 人がやることリスト + 締切カレンダー（再生成可能なビュー）
   ↓
/draft-section × n ───── spec の sections[] を契約に叩き台作成
   ↓
/review ──────────────── 定性レビュー（根拠・誇張・捏造・作成主体）
   ↓
/verify ──────────────── 機械検証（字数・網羅・clause 照合・[要確認] 残数）→ checks/
   ↓ （draft を直したら review/verify に戻る。verify は最新 draft に対して全緑であること）
/finalize ────────────── 提出前チェックリスト（提出は顧客本人）
   ↓ 提出・採否判明後
/retrospect ──────────── knowledge/ に学びを構造化（育成層の成長）
```

- 状態は `input/current-application.json` の `state` で管理: `spec_draft → spec_confirmed → intake_done → fit_done → planned → drafting → verified → finalized`。各コマンドは前提状態を確認し、`state=spec_draft` なら `/confirm-spec` へ誘導する。
- `/verify` は draft 本文のハッシュを checks レポートに記録し、`/finalize` は「最新 draft ハッシュに対する verify 全緑」を要求する（stale 検証の防止）。

## 2. 二層構成（SU-OS 型: 共通コア + ユーザー育成層）

| 層 | 所有 | 中身 | 上流更新 |
|----|------|------|----------|
| コア | 提供側（template 上流） | `core-manifest.json` に列挙されたファイル（`.claude/commands/` コア命名域、`schemas/`、`specs/`、`tools/`、`templates/`、`docs/`） | `tools/update-core.sh` で更新 |
| 育成層 | ユーザー | `input/`（自社データ・spec・ドラフト・current-application）、`knowledge/`（過去申請の学び）、`.claude/commands/my-*.md` | **上流更新で不変** |

- **`core-manifest.json`（新設）**: コア層ファイルの明示的 allowlist。`tools/update-core.sh`（新設）は upstream（template 元 repo）を一時取得し、manifest 記載ファイルだけを差分適用する。デフォルト `--dry-run`（差分表示のみ）、`--apply` で適用。`input/`・`knowledge/`・`my-*` は manifest に含めないことを validate.sh でアサート。ユーザーがコアを書き換えていた場合は上書きせず差分を提示して選ばせる。
- コアコマンドは育成層を必ず読む。spec は `input/spec/` が同梱 `specs/` より優先。`/draft-section` `/review` は `knowledge/lessons/` があれば反映。
- 手順の利用者向け説明は `docs/ハーネスの育て方.md`（新設）に置く。
- `input/` は gitignore 済（既存）。`knowledge/` はユーザー repo にコミットされる前提。テンプレ側は `knowledge/README.md` のみ。

## 3. スキーマ設計（新規・正本）

### 3.1 設計原則

1. **全ての主張に出所**: 制度事実を運ぶフィールドは `source_clauses[]`（clause_id 参照）を持ち、clause は原本文書（document_id + page）へ遡れる。確認ゲートは「フィールド→条文→原本」の機械的突合。
2. **成果物が一級市民**: `deliverables[]` が「何を作れば申請できるか」を直接表現し、/plan-deliverables はこれを読むだけで導出できる。
3. **適格性は三値評価の規則**: `eligibility.rules[]` は predicate AST（all/any/not + 型付き比較）で機械評価し、評価結果は `true / false / unknown` の三値。unknown は「顧客確認が必要」として扱う（断定しない既存規約と一致）。
4. **締切は1つではない**: `schedule[]` は `event_kind` enum を持ち、期間・相対日付（交付決定日起点）・時刻を表現できる。
5. **制度定義と申請イベントを混ぜない**: 採否・学びは `application-record`（育成層）に置く。result-report は record からの export（次フェーズ）。
6. **レジストリ対応**: spec は `registry` メタ（origin / fetched_at / revision / supersedes）を最初から持てる。taxonomy は同梱 JSON を正とし、schema enum との一致を検証する。

### 3.2 `schemas/subsidy-spec.schema.json`（制度定義・正本、schema_version "2.0"）

```
subsidy_id            ^[a-z0-9-]+$（必須）
schema_version        "2.0"（必須）
spec_version          整数。公募回内の改定で increment（必須）
name / round / portal_url
category_tags[]       schemas/taxonomy-v1.json の id のみ（同梱 taxonomy が正、schema enum と一致検証）
status                draft | confirmed（必須。confirmed の条件は confirmation report 全必須項目 confirmed）
registry              null | {origin, fetched_at, revision, supersedes}

source_documents[]    {document_id, title, url_or_path, sha256|null, pages|null}（必須・1件以上）

schedule[]            （必須）
  event_id / name
  event_kind          application_deadline | support_letter_deadline | estimate_deadline |
                      project_period | report_deadline | other
  date | starts_at/ends_at（YYYY-MM-DD）| relative {anchor(例 "交付決定日"), offset_days|null, direction(within_after|before)|null}
                      ※「交付決定日から30日以内」= {anchor:"交付決定日", offset_days:30, direction:"within_after"}
  time / timezone     （任意。締切時刻がある電子申請向け）
  hard                bool（過ぎたら失権）
  source_clauses[]
  ※ event_kind=application_deadline が必ず 1 件存在（check-spec が検査）

eligibility
  rules[]             （必須）
    rule_id           ^[a-z0-9-]+$、spec 内一意
    kind              exclude | mandatory | scoring
    text              要件の平易な一文
    predicate         null | AST
                      AST := {all:[AST...]} | {any:[AST...]} | {not:AST}
                           | {scope(profile|application), key, op(eq|ne|lt|lte|gt|gte|in|contains|exists), value}
                      scope=profile: key は company-profile のキー（§3.4）
                      scope=application: key は current-application のキー（例 chosen_funding.addon_ids）
                      評価は三値（true/false/unknown。参照値欠損・predicate=null は unknown）
    verification      充足をどう確認するか（書類名・手続き）
    source_clauses[]  （必須・1件以上）

funding               ★枠の加算・組合せを構造化
  base_award          {name, max_amount(万円), subsidy_rate(0-1), source_clauses[]}
  add_ons[]           {addon_id, name, max_amount_delta, required_rules[](rule_id),
                       rate_override|null, source_clauses[]}
  combinations[]      {addon_ids[], max_amount_total, source_clauses[]}（併用時の上限）
  eligible_expenses[] {category, notes, cap_amount|null, source_clauses[]}

bonus_items[]         {bonus_id, name, description, evidence_needed, source_clauses[]}

deliverables[]        （必須）
  deliverable_id      ^[a-z0-9-]+$、spec 内一意
  name
  type                form_input | document | attachment | procedure
  phase               application | post_adoption
  produced_by         ai_draftable | human_only | external
  issuer              null | 発行主体（例: 商工会議所）※external のとき必須
  required            bool
  required_if         null | predicate AST（条件付き必須。例: 特例選択時のみ）
  format              null | 様式・ファイル形式の注記
  upload_target       null | 提出先（例: 電子申請システムの様式4欄）
  due_event_id        null | schedule.event_id（この成果物固有の期限）
  sections[]          （form_input / document のみ）
    section_id / name / kind(prose|table|field) / max_chars / max_pages
    / guidance / review_criteria[] / source_clauses[]
  evidence_needed     null | 根拠資料の注記
  depends_on[]        deliverable_id
  source_clauses[]

clauses[]             ★真実源（backend 実証済み構造を継承・原本参照を強化）
  clause_id ^[A-Za-z0-9_.-]+$ / section / text(NFKC 正規化 verbatim)
  / raw_text / source_document_id（source_documents.document_id 参照）
  / page|null / source_offset{start,end}|null / topic_tags[]
  ※ 1 clause = 1 論点。source_clauses / judgment_basis の参照先は必ずここに実在

parsed_at / parsed_by（ai|human）
```

（v1 にあった `result_report` 枠は置かない。申請結果は application-record 側。）

### 3.3 確認ゲートの構造（confirmation report）

`/ingest-guidelines` は spec 生成後、`input/spec/<subsidy_id>.confirmation.json` またはパック形の confirmation を生成する:

```
spec_path / spec_version / spec_sha256 / confirmed_by(applicant|provider) / confirmed_at
items[]   {field_path, source_clauses[], state(confirmed|open|na), note}
```

- `spec_sha256` は確認時点の spec ファイルのハッシュ。spec を編集したら confirmation は stale となり、`check-spec.sh` が「status=confirmed だが spec_sha256 不一致」を FAIL にする（再確認を強制）。

- items は「確認必須フィールド」（schedule 全件・eligibility.rules 全件・funding・deliverables 全件・字数制限）を機械列挙して生成する。顧客が原本と突合しながら state を confirmed にしていく工程は `/confirm-spec` が担う。
- `check-spec.sh` は「status=confirmed の spec は、confirmation report が存在し必須 items が全て confirmed/na」を検査する（=「人間確認済み」の機械検証化）。
- 同梱 `specs/*.json` は提供側が同じ手順で確認済み（confirmed_by=provider、confirmation report を specs/ に同梱）。

### 3.4 `schemas/company-profile.schema.json`（新設・機械照合の正本）

- 正本は `input/company-profile.json`（機械照合用）。`input/company-profile.md` は人間可読ビュー（既存の見出し構成を維持、/intake が両方を生成・同期）。
- キー（predicate の profile_key が参照）: `entity_type / industry_class(商業・サービス業|宿泊・娯楽|製造業その他) / employees / capital / region / founded_year / taxable_income_avg_3y / is_subsidized_before / past_adoption_unreported(様式14未提出) / concurrent_applications[]` 等。値不明は null（= predicate 評価 unknown）＋ md 側 `[要確認]`。
- 過去採択・認定・賃上げ予定等の加点関連は `certifications[]` / `plans[]` として持つ（bonus 評価の材料。自動断定はせず提示まで）。

### 3.5 `schemas/application-record.schema.json`（申請イベント・育成層）

`/retrospect` が `knowledge/records/<subsidy_id>-<round>.json` に書く:

```
record_id / subsidy_id / spec_version / chosen_addons[] / submitted_at|null
result        adopted | rejected | not_submitted | pending
score|null / feedback_text|null
lessons[]     {lesson_id, phase(intake|fit|draft|verify|finalize), text, applies_to|null}
next_actions[]
```

`knowledge/lessons/*.md`（自由記述）と対。次回の `/draft-section` `/review` が読む。result-report（次フェーズ）はこの record からの export として定義する。

### 3.6 `input/current-application.json`（受け渡し契約・新設）

```
subsidy_id|null / spec_path|null / spec_version|null   ← spec_confirmed で non-null 化
chosen_funding null | {base:true, addon_ids[]}          ← /subsidy-fit で記録
state          spec_draft|spec_confirmed|intake_done|fit_done|planned|drafting|verified|finalized
updated_at
```

- 生成タイミング: 入口A `/select-subsidy` は subsidy_id・spec_path・spec_version を埋めて `state=spec_confirmed` で作成する。入口B `/ingest-guidelines` は draft spec を指す `state=spec_draft` で作成し、`/confirm-spec` が confirmed 昇格後に `state=spec_confirmed` へ更新する。`/intake` はこれを読み、confirmed spec が求める会社情報を整理したうえで state=intake_done に更新する。以降の各コマンドは「必須フィールドが自分の前提状態で non-null」を検査する。
- 全コマンドがこれを読み書きし、「同じ補助金・同じ枠」を見ている保証にする。複数申請の並行は MVP ではスコープ外（current は 1 件。切替は上書きで、draft 類は subsidy_id 別ディレクトリで衝突しない）。

## 4. コマンド仕様

### 新規

| コマンド | 入力 | 出力 | 要点 |
|---|---|---|---|
| `/select-subsidy` | 同梱 `specs/<id>/<id>.json`（パック形優先）または残留互換 `specs/<id>.json` + 顧客本人による公式募集要項との照合 | `input/current-application.json` | 入口A。対象補助金・公募回・様式が同梱 confirmed spec と一致する場合に state=spec_confirmed で初期化し、必要に応じて `/build-pack`、次に `/intake` へ進む |
| `/ingest-guidelines` | 募集要項 PDF/URL/貼り付け（原本は `input/guidelines/` に保存し document_id を採番） | `input/spec/<id>.json` または `input/spec/<id>/<id>.json`（draft）+ confirmation.json + `state=spec_draft` | backend parse-requirements の抽出規律を移植（1 clause=1 論点、verbatim、数値推測禁止、`[要確認]`）。突合確認は行わず、confirmation items を open で列挙して `/confirm-spec` に渡す |
| `/confirm-spec` | draft spec + confirmation + 原本抽出 | confirmed spec + confirmation 更新 + `state=spec_confirmed` | 募集要項との突合確認専用。グループ単位で保存し、`--gate confirm` green 後に status=confirmed へ昇格する |
| `/build-pack` | confirmed spec + confirmation | `input/spec/<id>/` の書き方メモ | confirmed spec から review-lens、scoring-strategy、section note を作る推奨工程。申請書本文は作らない |
| `/plan-deliverables` | confirmed spec + company-profile + current-application | `input/deliverables.md`（再生成可能ビュー） | deliverables[] から (a) AI と作る成果物（ai_draftable）、(b) 人がやることリスト（procedure/external/human_only + due_event_id）、(c) 添付チェックリスト、(d) 締切カレンダー（schedule 全件）を機械導出。required_if は chosen_funding で評価。**正本は spec + current-application、md は何度でも再生成できるビュー**（手動の進捗チェックは /finalize の final-checklist 側で扱う） |
| `/verify` | spec + `input/drafts/<subsidy_id>/` + current-application | `input/checks/verify-report.md` | `tools/check-spec.sh` + `tools/check-drafts.sh` を実行し要約。draft 本文ハッシュを記録 |
| `/retrospect` | 顧客の振り返り対話 | `knowledge/records/*.json` + `knowledge/lessons/*.md` | 採否・講評・学びを構造化。次回申請が参照 |

### 既存改修（全7本の扱いを明示）

| コマンド | 変更 |
|---|---|
| `/setup` | 環境セルフチェックに `python3` 存在確認を追加 |
| `/start` | 新フロー（入口A/B・current-application・retrospect）の案内に更新 |
| `/intake` | confirmed spec を読み、rules/scoring が参照する company-profile キーを優先ヒアリング。company-profile を JSON 正本 + md ビューの二重生成に変更（§3.4）し、state=intake_done に更新 |
| `/subsidy-fit` | spec 参照へ。3段階 matching を rules[].kind + predicate 三値評価で駆動（true=自動判定+clause 引用、unknown=顧客確認、false=除外候補として明示）。狙う枠（base+add_ons）を対話で決めて current-application に記録。spec 未確定なら `/select-subsidy` または `/ingest-guidelines` へ誘導 |
| `/draft-section` | セクション選択・字数・審査観点を spec.deliverables[].sections[] から取得。`knowledge/lessons/` 反映。出力 frontmatter に deliverable_id/section_id を記録。出力先は `input/drafts/<subsidy_id>/` |
| `/review` | 定性レビュー専念（機械チェックは /verify へ分離）。judgment_basis の quoted_text は clauses[].text の exact substring（clause-verifier 観点、W10 既定分） |
| `/finalize` | 「最新 draft ハッシュに対する /verify 全緑」を前提条件化。final-checklist は deliverables ビューの消し込み+提出手順（提出は顧客本人） |

## 5. 検証系（AI 非依存・python3 標準ライブラリ + bash wrapper）

- 実装方針: **bash は wrapper、検査本体は python3 標準ライブラリ**（json / unicodedata / re）。外部依存（jq・pip パッケージ）なし。`/setup` が python3 を確認する。
- `tools/check-spec.sh <spec.json>` — スキーマ妥当性（必須キー・id 一意性・パターン・enum）、参照整合（source_clauses→clauses、due_event_id→schedule、source_document_id→source_documents、category_tags→taxonomy-v1.json）、event_kind=application_deadline の存在、status=confirmed なら confirmation report の必須 items 全 confirmed/na
- `tools/check-drafts.sh` — draft frontmatter（deliverable_id/section_id）の spec 実在、**本文領域（`## 叩き台` 見出し下から次の同階層 `## ` 見出しまたは EOF まで）の文字数**を NFKC 正規化+改行空白規則を固定して計測し max_chars 超過検出、required×ai_draftable セクション網羅率、`[要確認]` 残数集計
- 異常系 fixture: `tools/fixtures/` に壊した spec/draft（参照切れ・字数超過・confirmed 偽装）を置き、check 群が FAIL することをテスト（`tools/test-checks.sh`）
- `tools/update-core.sh` — §2。デフォルト dry-run
- `tools/validate.sh`（既存 EXTEND） — 新規ファイル存在・参照整合・ガードレール文言・core-manifest 整合（manifest 記載ファイルが全て存在／`input/` `knowledge/` `my-*` を含まない）・コマンド md の出力先が育成層規約に従う（コアコマンドの Write 先は `input/` `knowledge/` のみ、コア層への書き込み記述が無い）。既存アサーションは弱めない

## 6. Acceptance Criteria（実装確認項目・全て機械検証可能）

- AC-1 `schemas/subsidy-spec.schema.json`・`schemas/company-profile.schema.json`・`schemas/application-record.schema.json`・`schemas/taxonomy-v1.json` が存在し、§3.2/3.4/3.5 の必須キー定義を含む（validate: キー文字列の存在アサート + check-spec の self-test）
- AC-2 `specs/jizokuka-20/jizokuka-20.json` + 同 confirmation report が新スキーマで存在し `check-spec.sh` 緑。predicate fixture として「業種別従業員数 5/20 人」規則が company-profile サンプル（商業5人以下=true / 製造25人=false / 従業員数不明=unknown）で正しく三値評価される（`tools/test-checks.sh` に含む）
- AC-3 新コマンド 4 本（ingest-guidelines / plan-deliverables / verify / retrospect）が存在し、frontmatter・手順・ガードレール文言・出力先（育成層のみ）を持つ
- AC-4 既存 7 本（setup/start/intake/subsidy-fit/draft-section/review/finalize）が §4 の通り改修され、それぞれ「current-application または spec を読む」肯定文言を持つ（grep 肯定アサーション。対象は 7 本と明示）
- AC-5 `check-spec.sh` / `check-drafts.sh` / `test-checks.sh` / `update-core.sh` が存在し、`test-checks.sh` が正常系+異常系 fixture で緑
- AC-6 worked-example に spec サンプル・confirmation・drafts（frontmatter 付き）・verify レポート例が揃い check 群で緑
- AC-7 `knowledge/README.md`・`docs/ハーネスの育て方.md`・`core-manifest.json` が存在し、manual.md が新フロー全体（入口A/B→intake→fit→plan→draft→review→verify→finalize→retrospect）と update-core を参照
- AC-8 `bash tools/validate.sh` 全緑（既存アサーションを弱めていない）

## 7. やらないこと（本件スコープ外）

- spec レジストリ（配信 API / 公開 data repo）の実装（registry メタ枠のみ確保）
- result-report の送信実装（application-record からの export として次フェーズ）
- 交付決定〜実績報告フェーズの実運用対応（schedule/deliverables の phase 枠のみ）
- 複数申請の並行管理（current-application は 1 件）
- 複数様式・高難度補助金（ものづくり等）への対応
- backend（saita-kun）への変更・v1→v2 追従

## 8. 正本宣言

補助金 spec のスキーマ正本は本リポ `schemas/subsidy-spec.schema.json`（schema_version 2.x）とする。backend `docs/schemas/subsidy.schema.json`（v1 系）は当面併存するが、新規の構造化は v2 で行い、v1→v2 は変換で追従する（次フェーズ）。v2 への変更は本設計 doc の改訂として記録する。taxonomy の正本は同梱 `schemas/taxonomy-v1.json`（backend categories.json 由来、一致検証あり）。
