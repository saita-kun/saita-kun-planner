# サイタくん公開準備設計書

作成: 2026-07-03 / ステータス: **P0 裁定済み（2026-07-03）** — 実装（Ralph 起票）着手可（§8 参照）
正本: 本書（公開準備フェーズの SSoT）/ 関連: `docs/governance/data-charter.md`・`docs/design/harness-ingest-loop.md`

---

## 0. 位置づけと記述規律

本書は、local-only の本リポジトリを **public OSS template repo** として世に出すための設計と実行計画の正本である。スコープは公開準備〜ソフトローンチ〜フルローンチまで。result-report 実装・spec レジストリ構築は別フェーズ（本書の対象外、§7.5 ロードマップに将来項目として掲載）。

記述規律（本書自体の公開安全性）:

- 本書は公開 tree に残る前提で書く。**機微実値は書かない**（個人名・持分・内部 KPI 値・競合の名指し財務値・除去対象語の実リスト）。それらは internal アーカイブ（非公開、§2.1）で管理し、本書からは「internal 管理」とだけ参照する。
- 本書は除去対象パスを名指しする必要があるため、R1/R3 の負のアサーション（§6）では本書を検査対象から除外する（`grep --exclude` 指定）。

## 1. 公開の定義と不可逆性

- 「公開」= (1) 初の public GitHub repo 作成（現状リモート未設定）+ (2) visibility を public にする操作（flip）。
- **flip は不可逆**。public 化した瞬間から fork/clone が可能になり、以後どれだけ早く private に戻しても複製の存在は否定できない。**ソフトローンチ（告知なし公開）も同じく不可逆**であり、「告知しないから安全」ではない。
- したがって flip の実行は DRI 本人に限定し、§9 の go-live 最小チェックリスト全項目 green を条件とする（DRI カード #1）。

## 2. 公開前の重大判断

### 2.1 内部文書の分離設計

**推奨（DRI カード #4・#5 で確定）**: 内部戦略文書を公開 tree から**完全排除**し、現リポジトリ全体（全履歴・全ブランチ）を private アーカイブ repo（例: `saita-kun-internal`。以下 internal アーカイブ）として保全する。

- 排除対象（internal-remove）: `docs/strategy/` 全4本、`docs/design/pivot-decision.md`、`docs/design/wave-plans.md`、`docs/design/harness-backlog.md`。事業判断の内部推論・調査資料であり、template 利用者に必要な成果物ではない。
- `docs/governance/data-charter.md` は**公開維持（サニタイズのみ）**。TERMS・telemetry 等の親規範として validate が参照を強制しており、非接触原則・COI・非営利移行条項の公開こそが信頼の核だからである。サニタイズ内容は R2（個人名の役割名化・内部文書参照の除去・法人内部事項の注記除去）。
- 旧データ回収モデル（撤回済み）を記述した文書は internal 側で superseded（現行の正は data-charter の非接触原則+result-report）と明記し、公開側には現行原則のみを残す。
- 技術的制約: `tools/validate.sh` は docs/ 全ファイル⇔core-manifest の双方向登録を強制し、対象文書を名指しで内容検査している。このため分離は「ファイル削除 + manifest エントリ削除 + 該当アサーション削除 + 負のアサーション追加」を**単一 story（R1）で不可分に**行う。分割すると中間状態で validate が赤くなり、自律ループが意図しない復元をしかねない。

### 2.2 履歴方針 = fresh-start（clean initial commit）

**推奨（DRI カード #5）**: 公開 repo は履歴を持ち込まず、スクラブ完了後の tree を単一の initial commit（`Signed-off-by` 付き）として作る。

手順: P1/P2 完了後、`git archive` で tracked ファイルのみを新ディレクトリへ export → `git init` → 単一コミット → private repo へ push（§4）。

根拠:

1. 内部文書は履歴の全域に存在し、**コミットメッセージ自体にも事業文脈が含まれる**（実履歴で確認済み）。tree のスクラブだけでは漏れる。
2. `git filter-repo` による履歴洗浄は rename 追跡漏れ・メッセージ洗浄漏れの残留リスクがあり、「漏れがないこと」の証明が困難。公開が不可逆である以上、証明容易性で fresh-start が優位。
3. template repo は「Use this template」で利用者側の履歴が新規化されるため、公開履歴の利用者価値がほぼない。
4. `git archive` は tracked のみを対象とするため、untracked の `input/` 実データ（E2E 検証データ等）の混入を**構造的に**防げる。

代替案（同一 repo 継続 + filter-repo 洗浄）は、リポジトリ連続性が必要になった場合のみ再検討する。不採用理由: 上記 1・2 に加え、gitignore 済み内部ディレクトリへの誤 `git add -f` 一発で公開事故になる恒常リスクを残すため。

### 2.3 DRAFT 文書の扱い

**推奨（DRI カード #6）**: DRAFT 注記付き文書 7本（`TERMS.md` / `docs/data-policy.md` / `docs/telemetry.md` / `docs/licensing-tiers.md` / `docs/collaborator-招待手順.md` / `docs/governance/data-charter.md` / `docs/design/wave-plans.md`※）は、**DRAFT バナー付きのまま公開する**。

- バナー（「DRI 法務レビュー pass 前は適用しない」）自体が、未発効の規約を発効済みと誤認させないための防衛線であり、透明性原則とも整合する。
- 法務ゲート pass 後に R8 で解除（発効日付与+validate の DRAFT 検査差し替え）。それまで法務ゲートは**フルローンチ（スポンサー課金・クラファン開始）の blocking** であって、ソフトローンチの blocking にはしない。
- ※ `wave-plans.md` は internal-remove 対象のため公開版には含まれない。

### 2.4 文書間矛盾の処置表と disposition 表

公開前に解消すべき既知の矛盾（公開側の正は常に **data-charter** とする）:

| # | 矛盾 | 処置 | 担当 |
|---|---|---|---|
| 1 | 旧データ回収モデル文書（strategy 2本）が現行の非接触原則と正面矛盾 | internal-remove（R1）+ internal 側で superseded 明記 | R1 / 人間 |
| 2 | 旧文書の撤退 KPI 記述が現行決定（当面設定せず）と不整合 | internal-remove で公開対象外に。内部指標は internal 管理 | R1 |
| 3 | 「採否データ提供が利用条件」と「任意・非提出でも中核機能可」の言い回し揺れ | 公開文書は charter §5「任意・非提出でも中核機能は全機能使用可」に統一 | R3 |
| 4 | web 公示クロールの適法性が内部検討中のまま | 公開ブロッカーにしない。internal 課題として別トラック（DRI カード #10） | — |

docs/ 全ファイルの disposition（P0 で DRI が確定。★=本書の推奨）:

| 分類 | ファイル |
|---|---|
| **internal-remove**（公開 tree から排除） | `docs/strategy/business-design.md` / `docs/strategy/data-loop-design.md` / `docs/strategy/monetization-research-2026-07-02.md` / `docs/strategy/zagumi-research-2026-07-03.md` / `docs/design/pivot-decision.md` / `docs/design/wave-plans.md` / `docs/design/harness-backlog.md` |
| **public-sanitize**（公開維持・要修正） | `docs/governance/data-charter.md`（R2） / `docs/design/harness-ingest-loop.md`（R3: 内部参照除去） / `docs/design/カスタマージャーニー-01-接点.md`（R3: 同） / `docs/faq.md`（R3 言い回し統一 + R7 境界線3節追加） |
| **public-keep**（そのまま公開） | `docs/manual.md` / `docs/テンプレートrepoの使い方.md` / `docs/ハーネスの育て方.md` / `docs/事業計画書の構成.md` / `docs/改善ループ.md` / `docs/法務とスコープ.md` / `docs/補助金の選び方.md` / `docs/data-policy.md` / `docs/telemetry.md` / `docs/licensing-tiers.md` / `docs/collaborator-招待手順.md`（result-report ガイドに改称済みの現行版） / `docs/onboarding/` 全4本 / 本書 |

## 3. リポジトリ衛生 & OSS 標準ファイル（不足分のみ）

整備済み（再作業しない）: `LICENSE`（Apache-2.0）/ `NOTICE` / `TRADEMARK.md` / `CONTRIBUTING.md`（CLA なし・DCO 必須）/ `docs/telemetry.md` / issue テンプレ（feedback）。

| 追加物 | 要点 | story |
|---|---|---|
| `SECURITY.md` | 私的報告経路（GitHub Private Vulnerability Reporting + 連絡先メール。メールは DRI カード #7） | R4 |
| `CODE_OF_CONDUCT.md` | Contributor Covenant 2.1 日本語版。連絡先は SECURITY と同一 | R4 |
| `.github/PULL_REQUEST_TEMPLATE.md` | DCO `Signed-off-by` チェック項目 + `bash tools/validate.sh` 緑宣言欄 | R4 |
| `.github/ISSUE_TEMPLATE/` 拡充 | bug / feature / config.yml（既存 feedback は維持） | R4 |
| `.github/workflows/validate.yml` | push/PR で `bash tools/validate.sh` | R5 |
| `.github/workflows/gitleaks.yml` | 秘密情報スキャン CI | R5 |
| `.gitleaks.toml` | 既知の誤検知（`specs/jizokuka-20/jizokuka-20.json` の predicate キー名）の allowlist、理由コメント付き | R5 |
| README 二層化 + mission 節 | 顧客向け導入は保持しつつ「Use this template」手順・標準ファイル導線・mission 節（§7.5）を追加。BYO AI の現状は Claude Code 特化と正直に明示（過大表示回避） | R6 |
| `ROADMAP.md` | §7.5 の 5 項目 | R9 |
| `.gitignore` へ `.ralph/` 追加 | 開発ハーネス内部状態を公開 tree から恒久排除（§4 運用モデル） | R1 |

## 4. 公開メカニクスと運用モデル

### 4.1 公開後の運用モデル

> ＜2026-07-08 注記＞ 本節の「public repo = canonical 開発拠点（本家=正史）」は 2026-07-06 の監査裁定で撤回。現行は **internal repo = SSoT（開発正本）+ `tools/release/export.sh` による検証済み export を公開 repo へ反映する方式**（戦略・プラン文書は internal に保持し、export 時に除去する）。本節は旧設計の記録として残す。

**public repo = canonical 開発拠点（本家=正史）**とする。private 開発 repo + public export 方式は、public が派生物化して外部 PR・issue・fork との整合が崩れるため採らない。

- `.ralph/`（自律開発ループの状態ファイル）は**公開に含めない**。公開 repo では `.gitignore` に登録し、開発機のローカル worktree にのみ untracked で置く。validate は `.ralph/` を走査しないため gate に影響しない。template 複製（既定ブランチの全ファイルが利用者 repo にコピーされる仕様）にも載らない。
- 内部文書の今後の置き場は internal アーカイブ repo。公開 repo に内部推論を書かない規律を維持する。
- 「Use this template」で作られた利用者 repo は履歴が新規化されるため、上流更新の配布は `tools/update-core.sh` + `core-manifest.json` が生命線（README で明示、既存設計どおり）。

### 4.2 公開手順書（P3、すべて Ralph 外・人間実行）

1. GitHub **org 作成**（法人保有 = data-charter §2 の一元保有原則。org 名は DRI カード #2）
2. **fresh-start export**: main の tree を `git archive` で export → 不要物の最終確認 → `git init` → 単一 initial commit（`Signed-off-by` 付与）
   ＜2026-07-08 注記: export は `tools/release/export.sh` で実施（4ゲート: 禁止物不在・sentinel 0 hit・validate 緑・gitleaks clean を fail-closed で通過した tree のみ生成）。手動 copy-paste 手順は廃止＞
3. org 配下に **private repo** として push（main のみ。他ブランチは push しない）
4. GitHub Actions（validate / gitleaks）が **green** になることを private 段階で確認 — CI はローカルで検証できないため、これが唯一の事前検証機会
5. **dcoapp/app** をインストールし、**branch protection**（required checks: validate / DCO / gitleaks）を設定
6. §9 go-live チェックリストを DRI が全件確認 → **DRI go/no-go（カード #1）**
7. **public flip**（DRI 本人が実行）
8. flip 直後: **Template repository 有効化**（「Include all branches」は OFF）→ topics・description 設定 → social preview 画像設定
9. ドメイン取得・README/LP からの導線設定（任意、フルローンチまでに）

## 5. フェーズ計画

| Phase | 目的 | 検証可能なゴール | blocking | 主体 |
|---|---|---|---|---|
| **P0 判断確定** | DRI カードの P0 分（#2〜#6）裁定 + internal アーカイブ複製 | 全 P0 カードに裁定記録がある。アーカイブ repo が存在し全履歴・全ブランチを含む | blocking | DRI |
| **P1 公開スクラブ** | 内部文書の排除・manifest/validate 手術・矛盾解消・サニタイズ | `bash tools/validate.sh` exit 0。除去対象語 grep 0 hit（本書除く）。gitleaks clean | blocking | Ralph（R1-R3） |
| **P2 OSS 標準整備** | 標準ファイル・CI 定義・README/ROADMAP | validate exit 0（新規アサーション込み）。§3 の追加物が全て存在 | blocking | Ralph（R4-R6, R9） |
| **P3 公開メカニクス** | §4.2 の手順実行 → flip → template 化 | §9 チェックリスト全 green。public URL で CI green・「Use this template」ボタン表示 | blocking | 人間（Ralph 外） |
| **P4 ソフトローンチ検証** | 告知なし公開で配布 readiness を実証 | 第三者 1 名以上が template→`/setup`→`/verify` で叩き台生成まで到達。DCO check が実 PR で発火。SECURITY 報告経路の疎通確認 | フルローンチの前提 | 人間 + Ralph（修正 story） |
| **P5 フルローンチ** | クラファン・スポンサー・告知の一回性イベント | クラファン公開。スポンサー申込導線が法務ゲート pass 済みで稼働。LP/LINE/X 告知実施 | 非 blocking（公開後） | 人間 + Ralph（R7, R8） |

## 6. Ralph story 分解と Ralph 外作業台帳

実装は Ralph 自律ループ（`.ralph/prd.json` に story 起票 → `bash ~/.claude/ralph/ralph.sh --repo saita-kun-planner` → validate 緑ゲート → 収束後 Codex 3段階レビュー、P1 指摘はブロック）で行う。acceptance は本 repo の型どおり「(N) 手順 + validate.sh の WAVE EXTENSION POINT 以下へのアサーション追加 + `bash tools/validate.sh` exits 0 + No placeholders」で締める。**起票は P0 裁定後**（除去対象語リスト・org 名等の裁定値を acceptance に埋め込むため）。

| story | phase | 概要 | acceptance 骨子 |
|---|---|---|---|
| **R1 `public-scrub-internal-docs`** | P1 | 内部文書 7本の排除と validate/manifest の一括手術（**不可分の単一 story**） | 7本を `git rm`。core-manifest から 7 エントリ削除。validate.sh の該当 Wave（名指し内容検査）を削除。`.gitignore` に `.ralph/` 追加。**負のアサーション**: 7 パスが存在しないこと・docs/ 全体（本書除く）に除去対象語（DRI 確定リスト、internal 管理）が 0 hit |
| **R2 `data-charter-public-sanitize`** | P1 | data-charter の公開サニタイズ | 個人名→役割名（DRI 等）。内部文書参照→「内部決定記録（非公開）」表記。法人内部事項の注記除去。非接触原則・レイヤー分離・allowlist/denylist・COI・非営利移行条項は維持。TERMS/telemetry 等からの参照リンク不断 |
| **R3 `reference-and-contradiction-pass`** | P1 | 内部参照の全除去と言い回し統一 | harness-ingest-loop・カスタマージャーニー等から内部文書への参照を除去。採否データの言い回しを charter §5（任意）に統一。負のアサーション: 公開 docs（本書除く）に `docs/strategy/`・排除済み文書名への参照が 0 hit |
| **R4 `oss-community-files`** | P2 | SECURITY / CoC / PR・issue テンプレ | §3 のとおり。各ファイル存在+必須文字列（報告経路・`Signed-off-by` 等）+ README/CONTRIBUTING からのリンク |
| **R5 `ci-workflows-and-gitleaks`** | P2 | CI 定義と secrets allowlist | workflows 2本 + `.gitleaks.toml`。CI の実走検証は P3（Ralph 外）である旨を acceptance に明記 |
| **R6 `readme-oss-reframe`** | P2 | README 二層化 + mission 節 | 「Use this template」手順・標準ファイル導線・mission 節（§7.5）・BYO の現状明示。org/repo 名は P0 裁定値（**P0 完了が前提**） |
| **R9 `public-roadmap`** | P2 | ROADMAP.md 新設 | §7.5 の 5 項目見出し + README/faq からのリンク不断。非 blocking だがソフトローンチ時同梱を推奨 |
| **R7 `sponsor-page-and-boundary-faq`** | P5 | スポンサー案内 + 境界線 FAQ | `docs/sponsorship.md`（§7.1）+ faq に境界線 3 節（§7.4）。tier 金額・独立性宣言・3 節見出しの存在検査 |
| **R8 `terms-draft-lift`** | P5（法務 pass 後） | DRAFT バナー解除 | 法務 pass 済み文書のバナーを発効日表記へ。validate の DRAFT 必須検査を「発効日 or DRAFT のいずれか必須」へ差し替え。**法務ゲート pass が確認されるまで `blocked:true` で起票** |

**Ralph 外作業台帳**（network OFF の制約上 story にできないもの。実行主体は人間/DRI）:

org 作成 / fresh-start export・push / public flip / template 有効化 / dcoapp インストール / branch protection / topics・description・social preview / ドメイン取得・DNS / **商標出願（第9類+第42類）** / TERMS 等の法務レビュー / HP 特商法表記（サブスク稼働中の欠落対応、saita-kun-web 側）/ クラファン・LP・LINE・X（saita-kun-web 側）/ internal アーカイブ複製 / `.ralph/prd.json` の説明文サニタイズ（公開対象外だが整合のため推奨）

## 7. ローンチ資産

### 7.1 法人スポンサーページ（`docs/sponsorship.md`、R7）

- L1 年間 tier: 25万 / 100万 / 200万円（目安）。返礼は名前・ロゴ掲載等の非機能的便益に限定。
- **独立性宣言を最上部に**: スポンサー資金は推薦順位・診断結果に一切影響しない（data-charter の COI ファイアウォール参照）。
- ナラティブ: 「スポンサーが支えるのは**データ維持インフラ**（公募要領の改訂追随・spec の鮮度）」— 推薦を売らずに協賛意義を成立させる公共財フレーミング。

### 7.2 クラファン設計（Ghost 型・一回性認知イベント）

- 位置づけ: 資金調達の主軸ではなく、公開ローンチの認知イベント + スポンサー枠の先行販売。
- **個別申請支援をリターンにしない**（非接触原則・行政書士法の境界を侵すため禁忌）。物理リターンも作らない（前例で制作・配送が本体作業を侵食）。手数料・ドロップで調達額の 15% 程度が目減りする前提で設計。
- ストレッチゴール案: **補助金パック追加**（持続化に続き、ものづくり / IT導入 / 省力化の spec 化）。金額が積むほど公共財が増える構図で、リターン依存を避ける。
- 境界線 FAQ（§7.4）をキャンペーンページに先出しし、批判の先回りをする。
- プラットフォーム・時期・詳細リターンは DRI カード #12。

### 7.3 既存チャネル

- saita-kun-web（HP）: LP に OSS 公開の告知セクション・repo/スポンサーページへの導線を追加。特商法表記の整備（DRI カード #11）を先行。
- LINE 公式（既存配信）: 公開告知 1 本 + 固定リッチメニュー導線。配信は既存規約どおり推薦順位の販売ではないことを維持。
- X: ローンチ告知はガードレール準拠（断言形・煽り禁止・問いかけ形式禁止）。

### 7.4 境界線 FAQ（`docs/faq.md` に 3 節追加、R7）

先回りすべき批判と公開スタンス:

1. **行政書士法**: 本キットは利用者自身が自分の AI で自分の書類を作る自己完結型ソフトであり、提供側は書類作成に一切関与しない（非接触原則）。代行・代書は行わない。
2. **個人情報**: `input/`（利用者の実データ）は利用者の repo にのみ存在し、提供側は構造上アクセスできない。result-report は任意・allowlist 限定・非提出でも全機能利用可。
3. **補助金ビジネス批判**: 「支援業者が悪なのではなく、支援なしでは回らない制度の複雑さが問題」というスタンスを明示。本プロジェクトは制度の複雑さという摩擦を無料の公共財で埋め、支援がなくても申請できる状態を作る。

## 7.5 公開ミッションとロードマップ

### mission 節（README、R6）

- **課題**: 補助金は情報の非対称性が大きい。存在を知らない・公募要領が読み解けない・書けない、の各段階で小規模事業者ほど不利になる。
- **ミッション**: 情報の非対称性を解消し、**支援がなくても自分で申請できる状態**を作る。
- **アプローチ**: AI が使うハーネス（構造化 spec + 検証器 + 手順）を OSS の公共財として配る。AI は利用者持ち込み（BYO）。エンジン+ラッパー前提 — 本 repo はエンジンであり、GUI ラッパー・白ラベル UI が上に生えることを歓迎する（スキーマ/spec のデファクト標準化を狙う）。
- **信頼原則**: 原文引用に基づく解釈（spec は公募要領と突合）/ 実態と乖離した「盛り」を作らないインタビュー設計 / 提出は必ず人間が行う（完全自動化しない）。

### ROADMAP.md（R9、5 項目）

1. **採択後モジュール**（交付申請・実績報告・証憑・期限管理）— 申請者が最も挫折する工程。現行スコープ「提出できる状態まで」の**将来拡張**として掲載（着手判断は別途 = DRI カード #14）
2. **spec レジストリの公共財化** — 構造化補助金フィードの生データ無料公開（決定済み方針）。データライセンスの明示（CC-BY / CDLA 等)は次フェーズで検討。配布アーキテクチャの方向（公開 data repo + パック導入 + 生成 starter）は `docs/design/repo-structure.md` が正（2026-07-17）
3. **補助金パックの拡充** — 持続化 → ものづくり / IT導入 / 省力化（クラファンのストレッチゴールと連動）
4. **公募要領改訂の監視パイプライン** — 公募回ごとの改訂を検知して spec を追随させる仕組み。鮮度が失われたデータは無料でも有害であり、ここがプロジェクトの本体
5. **政策提言** — 匿名集計（k 匿名性の閾値は data-charter §6）の公開を通じ、「AI でここまで簡素化できた」という実証データを制度側の簡素化提言につなげる二段構え

## 8. DRI カード化候補一覧

判断は本書に埋め込まず、以下をカードとして DRI キューに登録する。#2〜#6 が **P0（実装着手の前提）**。**#2〜#6 は 2026-07-03 に DRI 裁定済み**（裁定値は各行の推奨欄に追記）。

| # | タイトル | urgency | 推奨 |
|---|---|---|---|
| 1 | 公開 go/no-go（public flip 実行） | urgent（P3 末） | §9 全 green を条件に承認。flip は DRI 本人が実行 |
| 2 | GitHub org 名・repo 名・保有アカウント | urgent（P0） | **裁定済み**: org = `saita-kun`（法人保有）・repo 名 `saita-kun-planner` 維持 |
| 3 | 商標出願の実行（第9類+第42類。35/41類の要否） | 裁定済み（公開後タスク化） | **裁定済み**: 公開後に出願（冒認出願リスクは DRI 受容。§11 参照） |
| 4 | サニタイズ範囲・除去対象語リストの確定 | urgent（P0） | **裁定済み**: リスト確定（`.ralph/public-scrub-sentinel-words.txt`、非公開領域）。追加発見は追記+報告のみ |
| 5 | 履歴方針 = fresh-start の承認 | urgent（P0） | **裁定済み**: fresh-start 承認（§2.2 のとおり） |
| 6 | DRAFT 文書を DRAFT 明示のまま公開するか | urgent（P0） | **裁定済み**: バナー付き公開を承認（§2.3 のとおり） |
| 7 | SECURITY 連絡先メール | normal（P2 前） | security@ 系エイリアスの新設を推奨 |
| 8 | `.ralph/` の将来公開（building in public） | low（公開後） | 当面非公開。フルローンチ後に再評価 |
| 9 | 採否データの言い回し統一（charter §5 を正とする） | normal（P1） | 「任意・非提出でも中核機能可」に統一 |
| 10 | web 公示クロールの適法性判断 | normal（公開と独立） | 公開ブロッカーにしない。internal 課題として別トラック |
| 11 | 特商法表記・スポンサー申込導線の法務確認 | normal（P5 blocking） | スポンサー課金・クラファン開始前に pass 必須 |
| 12 | クラファンのプラットフォーム・時期・リターン設計 | normal（P4 中） | §7.2 のとおり。ソフトローンチ安定後に日程確定 |
| 13 | 公開ミッションのトーン | normal（P2 前） | 建設的フレーミング（§7.5）を推奨。内部ミッションの攻撃的表現は公開文書に出さない |
| 14 | 採択後モジュールのスコープ入り時期 | low（公開後） | ROADMAP 掲載のみで公開。着手はソフトローンチの反応を見て判断 |

## 9. go-live 最小チェックリスト

**これが全て green になるまで公開しない**。flip 直前に DRI が全件確認する。

1. 公開対象 tree に `docs/strategy/`・`pivot-decision.md`・`wave-plans.md`・`harness-backlog.md`・`.ralph/` が存在しない
2. 除去対象語 grep（DRI 確定リスト）が tree 全体で 0 hit（本書の除外指定を含め設定どおり）
3. gitleaks が公開対象で clean（`.gitleaks.toml` allowlist 適用。履歴は initial commit 1 個なので tree スキャンで完結）
4. `bash tools/validate.sh` exit 0（ローカル）かつ private repo の GitHub Actions で green
5. `LICENSE` / `NOTICE` / `TRADEMARK.md` / `CONTRIBUTING.md` / `SECURITY.md` / `CODE_OF_CONDUCT.md` / PR・issue テンプレ / README「Use this template」節が存在
6. DRAFT 対象文書すべてにバナーが残存している（意図した公開状態であることの確認）
7. dcoapp/app インストール済み + branch protection（validate / DCO / gitleaks を required checks）設定済み
8. push 対象が main のみ（余剰ブランチなし）。`input/` 実データが含まれていない（`git archive` 方式で構造保証）
9. （対象外に変更）商標出願は DRI 裁定 2026-07-03 により公開後実施へ。冒認出願リスクの受容は §11 リスク台帳に記録
10. org 名・repo 名・SECURITY 連絡先が DRI 裁定値と一致
11. DRI の公開承認記録（日付・対象 commit hash）を internal アーカイブに記載済み
12. flip 直後手順（template 有効化 / topics・description / social preview / README 内 URL の実在確認)のメモ準備済み

## 10. ローンチ方式の推奨: ソフトローンチ先行

**推奨**: P3 で告知なしに public 化 → 2〜4 週間の P4 検証 → クラファン開始をもってフルローンチ（P5）。

根拠:

1. クラファンは「一回性の認知イベント」であり撃ち直せない。repo 公開直後の技術的初期不良（CI・template 複製・DCO・オンボーディングの躓き）と認知の山を重ねるのは一回性資産の浪費。
2. 配布 readiness は、第三者が実際に template から叩き台まで到達して初めて実証される（launch readiness = 配布 readiness）。P4 がその実証装置。
3. 公開自体の不可逆リスク（スクラブ漏れ等）を、注目が集まる前の低トラフィック期間に発見・修正できる。
4. 前例（Ghost 型）もプロダクト実在が先、クラファンは認知の点火として機能した。

ただし**ソフトでも public は public**。第三者の fork・名称の露出は告知の有無と無関係に始まるため、除去対象語スクラブ（§9-1,2）はソフトローンチの blocking である。商標出願は DRI 裁定（2026-07-03）により公開後実施となった（冒認出願リスクを受容。フルローンチ前の出願完了を推奨タスクとして維持）。

## 11. リスク台帳

| リスク | 影響 | 手当 |
|---|---|---|
| ソフトローンチの「取り消せる」誤認 | スクラブ漏れが恒久露出 | §1 に不可逆性明記。flip 前チェックリストが唯一の防衛線 |
| コミットメッセージ経由の内部情報漏洩 | tree 監査だけでは検出不能 | fresh-start（§2.2）で構造的に解決 |
| R1 の分割実行による中間赤 | 自律ループが意図しない復元 | 不可分の単一 story として起票（§6） |
| 除去の検査が「存在検査」しかない | 復活・混入を検出できない | 負のアサーション（0 hit 検査）を validate に恒久追加。既存の残滓一掃 Wave が先例 |
| CI がローカルで検証できない | 公開後に CI 赤が露出 | private repo 段階で green 確認してから flip（§4.2-4） |
| template 複製で利用者履歴が新規化 | 上流更新が届かない誤解 | update-core + core-manifest が配布経路であることを README 明示 |
| BYO の過大表示 | 「どの AI でも動く」との誤解 | 現状は Claude Code 特化と正直に明示（R6） |
| 日本語ファイル名の環境差 | 一部環境で文字化け報告 | 既知の制約として FAQ に 1 行（非 blocking） |
| スポンサー導線と非接触原則の混同 | 「推薦を売っている」との誤解 | 独立性宣言の先出し（§7.1）+ COI 開示 |
| データ鮮度の劣化 | 「腐った公共財」化 | 改訂監視パイプラインを ROADMAP の中核に据える（§7.5） |
| 公開後の商標出願（先願主義下の冒認出願） | 第三者出願により名称・ブランド変更を強いられる可能性 | DRI 裁定で受容（2026-07-03）。フルローンチ前の出願完了を推奨タスクとして維持 |

---

付記: 本書の実装 story 起票（`.ralph/prd.json`）は P0 裁定後に行う。裁定値（org 名・除去対象語リスト・SECURITY 連絡先）が acceptance に必要なためである。
