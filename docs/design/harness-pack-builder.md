# 設計: 補助金パックと builder 工程（3層ハーネス構造）

> 本ファイルは saita-kun-planner の「補助金パック（L2）とその生成機構（builder）」の設計正本。
> 決定日: 2026-07-04（DRI: 代表）。`docs/design/harness-ingest-loop.md`（spec 駆動ループ設計）の拡張・一部改訂。
> レビュー1（Codex 設計レビュー、P1 5件・P2 7件・P3 2件）反映済み（2026-07-05）。
> 公開版では、利用者が把握すべき設計原則と現行の構造だけを記録する。

## 0. 前提（DRI 決定 2026-07-04）

1. **3層ハーネス構造を正式採用する**。
   - **L1 共通ハーネス** = 実行系（slash command・状態機械・検証器・スキーマ・マニュアル）に加え、**「補助金パックを作るための機構（builder）」を内蔵**する。
   - **L2 補助金パック** = 補助金ごとの構造化データ一式。機械層（spec + confirmation）と定性層（書き方メモ = notes）を 1 ディレクトリに束ねる。同梱パック（提供側作成）と、利用者が自分の対象補助金用に生成するパックは**同じ構造・同じ機構**で作る。
   - **L3 育成層** = 既存どおり `input/`・`knowledge/`・`.claude/commands/my-*.md`。上流更新不可侵。
2. **L2 にコードを置かない**。実行系は L1 に一本化し、補助金ごとの差分はすべてデータが運ぶ。パック内に `.md` / `.json` 以外のファイルが存在したら検証器が FAIL にする（原則の機械化）。
3. **昇格（draft → confirmed）は必ず機械ゲートを通る**。遷移条件をコマンド（AI の善意）ではなく検証器 `check-spec --gate confirm` が守る。
4. **利用者向けの新しい語彙は「補助金パック」と「書き方メモ」の 2 語だけ**。pack.json・checker・predicate・L1/L2/L3 は利用者向けドキュメントの語彙にしない。新コマンドの利用者向け説明は `/confirm-spec` =「募集要項との突合確認」、`/build-pack` =「書き方メモを作る」とし、内部機構名を持ち込まない。
5. **スキーマ変更はすべて additive-optional** とし、`schema_version "2.0"` を維持する（§11 changelog）。既存の confirmed spec・顧客の平置き `input/spec/<id>.json` は後方互換で受理し続ける。

## 1. 補助金パックの構造

```
# 同梱パック（コア層。core-manifest.json にファイル単位で列挙、update-core 配布対象）
specs/<subsidy_id>/
├─ <subsidy_id>.json               # v2 spec（status=confirmed 必須）
├─ <subsidy_id>.confirmation.json  # confirmed_by=provider
├─ pack.json                       # パックマニフェスト（構成ファイルの sha256 台帳）
└─ notes/                          # 書き方メモ（定性層）
   ├─ review-lens.md               # 審査で見られる観点（clause 引用必須）
   ├─ scoring-strategy.md          # 加点・枠選択の戦略（clause 引用必須）
   ├─ sections/<deliverable_id>--<section_id>.md  # セクション別の書き方ノート（内容がある分のみ）
   └─ examples.md                  # 参考事例（任意。各事例に source: 必須）

# 利用者生成パック（育成層。input/ は gitignore 済み＝コミットされない）
input/spec/<subsidy_id>/           # 同構造。confirmation は confirmed_by=applicant
input/spec/<subsidy_id>.json       # 旧平置き形式（後方互換として受理し続ける）
input/guidelines/<name>.extract.md # 原本のページアンカー付き抽出テキスト（§7）
```

- ファイル名は従来の `<subsidy_id>.json` / `<subsidy_id>.confirmation.json` を維持する。confirmation の解決規約（spec と同じ stem + `.confirmation.json`）が無改修で使えるため。
- 同梱パックは `specs/` 配下に置く。新しいトップレベルディレクトリは作らない（core-manifest 完全性スキャンの対象ディレクトリ集合を変えないため）。
- 利用者生成パックを `input/`（gitignore 側）に置く理由: (a) 既存の受け渡し契約（`input/spec/` 優先・current-application の spec_path・ingest の出力先）を安定に保つ、(b) scoring-strategy には自社の狙い・弱みが混ざるため既定で非コミットが安全、(c) パックは「当該公募回の作業成果物」であり、長期資産化は `/retrospect` が `knowledge/` に落とすという既存の役割分担と一致する。コミットして残したい利用者向けには、private repo で .gitignore を自分で調整する選択肢を `docs/ハーネスの育て方.md` に記載する。

## 2. 解決順（precedence）と resolver 規約

同一 `subsidy_id` に対して、spec・confirmation・notes を次の順で解決する。

1. `input/spec/<subsidy_id>/`（利用者パック）
2. `input/spec/<subsidy_id>.json`（利用者平置き・後方互換。notes なし）
3. `specs/<subsidy_id>/`（同梱パック）
4. `specs/<subsidy_id>.json`（同梱平置き。移行期・コア更新後の残留を想定した後方互換。パック形より常に劣後）

- `knowledge/lessons/` は優先解決の対象ではなく、従来どおり `/draft-section` `/review` が**常時追加で読む**文脈（L3）。
- この解決順は `specs/README.md` と各コマンドの記載を更新して正とする。

### 2.1 resolver 規約（全コマンド共通）

- すべてのコマンド・検証系は spec / confirmation / notes の発見に上記の共通解決手順を使う（コマンド md には解決手順を同一文言で記載し、validate が文言を検査する）。`/select-subsidy` の候補列挙は `specs/<id>/<id>.json`（パック形）と `specs/<id>.json`（平置き）の両形式を対象にし、同一 `subsidy_id` が両形式で存在する場合はパック形を採用する。
- **同梱平置きの残留への対処**: `tools/update-core.sh` は manifest から消えたファイルを削除しない。このため同梱 spec をパックへ移行した後も、既存利用者の環境には旧 `specs/<id>.json` が残り得る。resolver がパック形を常に優先することで残留ファイルは無害化される。`docs/ハーネスの育て方.md` に「コア更新後の残留ファイルと手動削除の任意手順」を記載する。
- **current-application の stale パス**: `spec_path` が旧同梱平置きパスを指したまま同一 `subsidy_id` のパック形が存在する場合、各コマンドの前提チェックはそれを検出し、`spec_path` の付け替え（またはパック形での再選択）を案内する。

## 3. pack.json（schemas/subsidy-pack.schema.json 新設）

```json
{
  "pack_version": 1,
  "subsidy_id": "<id>",
  "spec_version": 1,
  "built_at": "YYYY-MM-DDTHH:MM:SS+09:00",
  "built_by": "provider | applicant",
  "spec":         { "path": "<id>.json", "sha256": "..." },
  "confirmation": { "path": "<id>.confirmation.json", "sha256": "..." },
  "notes": [
    { "path": "notes/review-lens.md", "kind": "review-lens", "sha256": "...",
      "derived_from_spec_sha256": "..." }
  ]
}
```

- `notes[].kind` enum: `review-lens` / `scoring-strategy` / `section-note` / `examples`。
- sha256 台帳により「ファイルが後から書き換えられた」stale（列挙 sha256 と実ファイルの不一致）を機械検知する（confirmation の `spec_sha256` と同じ確立パターンの水平展開）。
- **semantic stale の検知**: `notes[].derived_from_spec_sha256` は「その note がどの spec 内容から作られたか」を記録する。現在の `spec.sha256` と一致しない note は check-pack が FAIL にする（spec を直したのに notes を再生成していない状態の検知）。`/build-pack` が生成・更新時に機械記入する。
- `built_at` は offset 付き ISO 8601 を必須とする（タイムゾーンは固定しない。例は `+09:00`）。
- パスはパックディレクトリからの相対パスのみ許可（外部参照禁止）。

## 4. 出典規律と check-pack

新設 `tools/check-pack.sh`（実体 `tools/lib/check_pack.py`、python3 標準ライブラリのみ）がパックを検証する。

### 4.1 notes の書式

- 各 note は frontmatter 必須: `subsidy_id` / `kind`（section-note のみ `deliverable_id`・`section_id` も必須）。
- frontmatter は **限定形式**とする: 先頭行 `---` と終了行 `---` に挟まれた `key: スカラー値` の行のみ（ネスト・リスト・複数行値は不可）。python3 標準ライブラリの行パースで読める範囲に制限し、YAML パーサは使わない。
- 制度事実（数値・要件・締切・様式）への言及は、本文中の `[clause: <clause_id>]` 記法で spec の clauses に紐付ける。
- clause 引用のない記述は「一般知見」扱いであり、数値・要件の根拠に使ってはならない（§5.4 境界規律）。

### 4.2 FAIL / WARN 表

| 判定 | 条件 |
|---|---|
| FAIL | pack.json の必須キー欠落・スキーマ不一致 |
| FAIL | pack.json 列挙ファイルの不存在・sha256 不一致（stale） |
| FAIL | notes entry の `derived_from_spec_sha256` が pack.json の `spec.sha256` と不一致（semantic stale） |
| FAIL | spec の status が confirmed でない、または check-spec が FAIL |
| FAIL | confirmation の `spec_sha256` と pack.json の `spec.sha256` の不一致 |
| FAIL | note の frontmatter 欠落・kind 不正・subsidy_id 不一致 |
| FAIL | section-note の `deliverable_id` / `section_id` が spec に実在しない |
| FAIL | `[clause: X]` の X が spec の clauses に実在しない |
| FAIL | review-lens / scoring-strategy / 各 section-note に clause 引用が 0 件 |
| FAIL | examples.md の事例に `source:` がない |
| FAIL | パックディレクトリ内に `.md` / `.json` 以外のファイルが存在（L2 コード禁止） |
| WARN | 数値・制度事実らしい行（万円・%・以内・締切・上限 等）に同一行の `[clause:]` も `[要確認]` もない |

- 定性ノートの「戦略・書き方アドバイス」自体には出典を強制できないため、機械で守る線は「参照は必ず実在」「note 単位で最低 1 引用」「数値行は出典か [要確認]」に引く。文章品質の評価は `/review` の定性領域であり機械ゲート化しない。

## 5. builder 工程（コマンドフローと状態機械）

### 5.1 状態遷移（spec_draft を追加）

```
spec_draft → spec_confirmed → intake_done → fit_done → planned → drafting → verified → finalized
```

- **`spec_draft` を新設**する。`/ingest-guidelines` 完了時に `input/current-application.json` を `state=spec_draft` で初期化する（従来は confirmed 到達まで state ファイルが作られず、突合を中断すると全コマンドが案内不能＝迷子になっていた。その根治）。
- 入口A `/select-subsidy` は従来どおり直接 `spec_confirmed`（同梱パックは confirmed 済みのため）。`intake` 以降の遷移は不変。
- 下流コマンドの前提チェックに分岐を 1 行追加する: 「`state=spec_draft` の場合は突合が未完了です。`/confirm-spec` を実行してください（残り件数は confirmation を参照）」。

**`state=spec_draft` 時の current-application 契約**:

```json
{
  "subsidy_id": "<draft spec の subsidy_id>",
  "spec_path": "input/spec/<id>/<id>.json または input/spec/<id>.json（draft spec を指してよい）",
  "spec_version": "<draft spec の実値>",
  "chosen_funding": null,
  "state": "spec_draft",
  "updated_at": "..."
}
```

- キー構成は既存契約と同一（新キーは追加しない）。confirmation は「spec と同じ stem + `.confirmation.json`」の既存規約で解決するため `confirmation_path` キーは設けない。
- `spec_path` が draft spec（status=draft）を指すのは `state=spec_draft` のときだけ許される。`spec_confirmed` 以降で status=draft の spec を指していたら各コマンドの前提チェックが FAIL 扱いにして `/confirm-spec` へ誘導する。
- **旧環境からの復旧**: state ファイルが無いのに `input/spec/` に draft spec が存在する場合（旧 ingest の中断残骸）、`/confirm-spec` の前提チェックがそれを検出し、「この draft から再開するか」を確認のうえ `state=spec_draft` で current-application を初期化してから突合に入る。

### 5.2 工程分割（入口B を 2 コマンド + 任意 1 コマンドに）

```
/ingest-guidelines（既存名を維持・役割を縮小）
  原本保存・document_id 採番・sha256・extract.md 生成（§7）・draft spec 生成・
  confirmation 全 item 機械列挙（state=open）・抽出スポットチェック（§7.2）
  → current-application を state=spec_draft で初期化 → /confirm-spec へ誘導

/confirm-spec（新設）
  突合・昇格の専用コマンド。§5.3 の UX 仕様
  → check-spec --gate confirm green → status=confirmed → spec_sha256 固定
  → state=spec_confirmed → /intake へ誘導

/build-pack（新設。state が spec_confirmed 以降ならいつでも・推奨）
  notes 4 種の草案生成（[clause:] 記法を強制）→ pack.json 生成 → check-pack green
  → 出力先 input/spec/<subsidy_id>/（パック形へ整理）
```

- `/ingest-guidelines` は改名しない。抽出規律（1 clause = 1 論点・verbatim・数値推測禁止・source_clauses 必須）は従来どおり本コマンドが持つ。
- `/build-pack` は任意（notes なしでも /draft-section は動く）だが推奨。同梱パック相当の作業環境を自分の補助金に対して持てる状態がゴール。

### 5.3 /confirm-spec の UX 仕様

1. **冒頭で必ず進捗ダッシュボード**を表示する（全体件数・グループ別の confirmed/open/na・前回の中断点）。
2. items は `field_path` プレフィックスで自動グループ化する（`schedule.*` / `eligibility.rules.*` / `funding.*` / `deliverables.*` / 字数制限系）。スキーマ変更は不要。
3. **グループ単位の一括表**を提示する。各行 = spec 値 + 原本 verbatim 引用 + ページ番号。利用者は「表のとおりで OK / n 行目が違う」で応答し、相違行・不明行だけ 1 件ずつの個別対話に降格する。値を直す場合は draft spec を修正し当該 item を open に戻す。
4. **グループ処理ごとに confirmation を保存**する（チェックポイント）。毎グループ末尾に「ここで中断しても再開できます。再開は /confirm-spec」と明示する。
5. eligibility の rule item には **predicate_state**（§6.2）を判定・記録する。
6. 全必須 item が confirmed/na になったら**昇格シーケンス**を実行する（順序固定）:
   (1) draft のまま `bash tools/check-spec.sh <spec> --gate confirm` を実行し green（昇格前 readiness の機械確認。この時点では `spec_sha256` は未固定でよい）
   (2) spec の `status` を `confirmed` に更新して保存
   (3) 保存後の spec ファイルの SHA-256 を計算し、confirmation の `spec_sha256`・`confirmed_by`・`confirmed_at` を記入
   (4) 通常モードの `bash tools/check-spec.sh <spec>` を再実行して green（confirmed 系検査 = SHA 一致・open 残無しの最終確認）
   (5) current-application を `state=spec_confirmed` に更新
   ※ `--gate confirm` は「draft に対する昇格前検査」であり、SHA 固定の検査は昇格後の通常モードが担う。この分担により「status=confirmed 保存 → SHA 計算」の順序と検査が衝突しない。
7. **回復導線 3 分岐**を同コマンド内に明記する: (a) 1 件だけ直したい → item 単位で open に戻して再確認、(b) 原本の版違いに気づいた → `spec_version` を増分して `/ingest-guidelines` を新版原本で再実行 → 再突合、(c) 系統的な抽出失敗 → `/ingest-guidelines` 再実行（「確認済み N 件がリセットされます」と警告してから）。
8. 法務ガードレール: 一括表は「まとめて見せる」ためのものであり、AI が confirmed を代行しない。各行に原本 verbatim 引用とページを必ず表示し、確認の主体は利用者本人。

### 5.4 notes の参照（/draft-section・/review）

- `/draft-section` は「使う情報」に解決済みパックの notes（該当 section-note と review-lens）を追加し、骨子作成前に該当セクションのコツを引用提示する。
- `/review` は review-lens の観点をレビュー観点に追加する。
- **境界規律**: notes 中で clause 引用のない記述は一般知見扱いとし、数値・要件の根拠には使わない。数値・要件の根拠は従来どおり spec の clauses のみ。この規律は両コマンドと各 note 冒頭に明記する。
- 同梱パックの notes へ利用者が書き足したい場合は、notes を直接編集せず `knowledge/lessons/` へ誘導する（update-core の user-modified 衝突を避ける。利用者自身のパック `input/spec/<id>/notes/` は自由に編集してよい）。

## 6. 品質ゲート（check-spec の段階化）

新しい checker は check-pack（§4）のみとし、spec 側は既存 `tools/lib/check_spec.py` を段階化して拡張する（呼び出し口 `tools/check-spec.sh` は互換維持）。

### 6.1 ゲート表

| ゲート | 契機 | FAIL | WARN / レポート |
|---|---|---|---|
| check-spec（draft への適用拡張） | ingest 直後・随時 | 既存の構造・参照整合に加え、confirmation が併存する場合: 必須 field_path の網羅欠落・field_path 重複・state 値不正・spec_path 不一致 | **readiness report を常時出力**: confirmed/open/na 件数、predicate カバレッジ（mandatory+exclude 中の encoded 率）、prose×ai_draftable セクションの max_chars null 率、verbatim 照合カバレッジ、source_documents の sha256 null 件数 |
| **check-spec --gate confirm（新設・昇格前検査）** | /confirm-spec の昇格シーケンス (1)、**draft に対して実行** | 上記すべて + 必須 item の open 残存 + mandatory/exclude rule item の predicate_state が pending または欠落 + extract を持つ document 由来 clause の verbatim 不一致（§7.3）。`spec_sha256` の一致は**要求しない**（未固定のため。固定後の検査は昇格シーケンス (4) の通常モードが担う） | — |
| check-spec（confirmed・既存） | 昇格後・/verify | 既存のまま（spec_sha256 不一致・open 残存・網羅欠落） | readiness report は confirmed でも表示 |
| check-pack（新設） | /build-pack・validate（同梱パック分） | §4.2 | §4.2 |

- **カバレッジ率は FAIL にしない**。原本に上限記載がない場合の `max_chars: null` や predicate 化不能は正しい姿であり、率での FAIL は捏造を誘発する。機械で守る線は「率のレポート」+「明示判断の記録の強制（predicate_state）」。

### 6.2 predicate_state（confirmation の rule item に追加）

- eligibility の rule に対応する confirmation item に `predicate_state` を追加する。enum: `encoded`（predicate を書いた）/ `not_encodable`（構造上書けないと判断した）/ `pending`（未判断）。
- `--gate confirm` は pending・欠落を FAIL にする。「predicate を書けるのに省略した」が構造的に消え、`not_encodable` はスキーマギャップの検出信号として蓄積される。
- **predicate との整合検査**（--gate confirm 時および confirmed 通常検査時）: `encoded` なのに対応 rule の `predicate` が null → FAIL。`not_encodable` なのに `predicate` が non-null → FAIL（判断記録と実体の矛盾）。item の `state` が `na` の rule item は predicate_state を要求しない（対象外の rule のため）。
- **confirmed 通常検査でも predicate_state を要求する**（2026-07-05 コードレビュー P1 で是正）: 当初は後方互換のため通常モードで要求しない設計だったが、それでは `status` を直接 confirmed に書き換えて昇格ゲートをバイパスできる偽陰性が残る（fake-green 防止の設計思想に反する）。confirmed spec の confirmation に mandatory/exclude rule item の predicate_state が欠落・pending・実体矛盾の場合は FAIL とする。ゲート導入前に confirmed 化された古い confirmation はこの検査で FAIL になるが、それは「predicate 判断の記録がない確認」であり `/confirm-spec` での再突合を促す挙動が安全側で正しい（同梱パックは移行時に付与済み）。

### 6.3 spec-confirmation.schema.json（新設）

- confirmation はこれまでスキーマレスだった。正本スキーマ `schemas/spec-confirmation.schema.json` を新設し、check_spec が構造検査に使う（python3 標準ライブラリで実装。外部の jsonschema ライブラリは使わない）。
- フィールド: `spec_path` / `spec_version` / `spec_sha256` / `confirmed_by`（applicant|provider）/ `confirmed_at` / `items[]{field_path, source_clauses[], state(confirmed|open|na), note, predicate_state?}`。
- **draft 段階の null 許容**: `spec_sha256`・`confirmed_by`・`confirmed_at` は昇格シーケンス (3) で固定されるフィールドであり、spec の `status=draft` の間は null を許容する（非 null なら enum/形式検査は行う）。`status=confirmed` では非 null 必須（2026-07-05 E2E で draft への過剰厳格を検出し是正）。
- **突合の監査フィールド**（optional、/confirm-spec が記入）: item に `confirmed_at`（確認時刻）/ `confirmed_via`（`group-table` = 一括表で確認 | `individual` = 個別対話で確認）/ `shown_page`（提示した原本ページ）を持てる。グループ一括方式でも「いつ・どの方式で・どのページを見て確認したか」を後から追跡できるようにする（本人突合の実質の記録）。

### 6.4 CLI 仕様（check-spec）

- 呼び出し: `bash tools/check-spec.sh <spec.json> [--gate confirm]`。wrapper は引数をそのまで `tools/lib/check_spec.py` に渡す。
- `check_spec.py` は argparse 化する: 位置引数 `spec_path`（従来互換）+ optional `--gate {confirm}`。従来の 1 引数呼び出しの挙動・出力は変えない。
- exit code: 0 = pass（WARN があっても 0）/ 1 = FAIL あり。
- readiness report は stdout に `READINESS:` プレフィックスの行で出力する（例: `READINESS: confirmation 31/34 confirmed, 3 open`、`READINESS: predicate coverage 4/15 encoded`）。機械可読とログ可読を両立する。

## 7. 原本（PDF）取込の責務

### 7.1 3 段構え

| 状況 | 利用者の操作 | 責務 |
|---|---|---|
| PDF がある（標準） | `input/guidelines/` にそのまま保存 | AI（利用者の Claude Code）が直接読み、`input/guidelines/<name>.extract.md` を生成する。`## p.N` のページアンカー必須・verbatim 転記・要約禁止。`extract_path` に記録 |
| Web ページしかない | 該当本文を md に貼り付けて保存 | 貼り付け原文が原本代理。URL を source_documents に記録し、**貼り付け md 自体を `extract_path` に記録**（verbatim 照合の対象になる） |
| スキャン画像等で読めない | 事務局の HTML/Word 版を探す。なければ該当章のみ貼り付け | 読めた範囲 + `[要確認]` で進める。貼り付け分は上と同様 `extract_path` に記録 |

- `pdftotext` 等の変換ツールは**同梱しない**（環境要件 python3 + bash を変えない）。インストール済み環境では抽出テキストの照合材料として任意併用できる旨を `/setup` の環境チェックに追記する（任意検出・非必須）。
- スキーマは `source_documents[]` に optional の `extract_path`（string|null）を追加する（§11）。

### 7.2 スポットチェック（抽出直後の儀式）

- `/ingest-guidelines` は抽出完了時に無作為に 3 clause を選び、「原本の p.X を開いて、この文がそのまま載っているか確認してください」と利用者に依頼する。不一致が出たら該当 document の抽出をやり直す。
- 全数の忠実性検査は突合（/confirm-spec）自体が担うため、追加の機構は置かない。

### 7.3 verbatim 照合（機械）

- `extract_path` を持つ document 由来の clause について、clause の原文が extract テキストの部分文字列であることを検証する（NFKC 正規化 + 全空白除去後の substring 一致）。**PDF 抽出・貼り付け md のどちらの経路でも `extract_path` が記録されていれば照合対象**とする。
- **照合の needle は `raw_text` を優先し、無ければ `text`**。表組みでは `text`（読み順の正規化 verbatim）が extract の線形化順と一致しないことがあり、原本への出所を証明するフィールドは原本ママの `raw_text` が正（2026-07-05 E2E で実証: 表由来 11 clause が text では不一致、raw_text では全一致）。
- **haystack は extract からタイトル行（`# `）とページアンカー行（`## p.N`）を除去してから正規化**する。ページ跨ぎの clause はアンカー挿入で連続性が切れるため（同 E2E で実証）。
- 通常モードでは WARN + カバレッジ報告、`--gate confirm` では FAIL。`extract_path` のない document 由来の clause は対象外（過去データとの互換のみ。新規 ingest では全 document に `extract_path` を記録することを標準とする）。
- この照合は「clause と extract の相互整合（後からの改変・転記ずれの検知）」を保証する。原本そのものへの忠実性は §7.2 のスポットチェックと突合が担う、という分担を明記する。

## 8. predicate 強化（company-profile の追加キー）

- `schemas/company-profile.schema.json` に `chusho_kihonho_class` を additive 追加する。enum: `製造業その他` / `卸売業` / `小売業` / `サービス業` / null。中小企業基本法系の業種区分で、自治体・中規模以上の補助金の適格性判定（資本金・従業員のしきい値組合せ）を predicate で書けるようにする。
- 既存 `industry_class`（小規模事業者判定の 3 区分）は**変更しない**。用途が異なる別キーとして共存する。
- `/intake` は spec 駆動ヒアリングのため、新キーを参照する spec が対象のときだけ質問が増える（既存利用者の体験は不変）。
- 対象外（backlog）: みなし大企業の資本構成の構造化、賃上げ・認定計画のフィールド細分化、複数様式・大型補助金向けの全面拡張。

## 9. 提供側のパック量産手順

1. 作業用 repo（本家の clone または worktree）で `/ingest-guidelines` → `/confirm-spec` → `/build-pack` を実行する（利用者と同じ機構。builder は 1 系統）。
2. 生成された `input/spec/<id>/` を `specs/<id>/` に移設し、confirmation の `confirmed_by` を `provider`、pack.json の `built_by` を `provider` にする。
3. `core-manifest.json` にパックの全ファイルを追記し、`tools/validate.sh` に同梱パックの check-pack green アサーションを追加する。
4. 公開スクラブ: パックに固有の内部情報・実在企業の情報を書かない（notes は制度原本と一般知見のみで書く）。

## 10. E2E 受け入れ基準（builder 一気通貫）

実在の公募要領 1 件（入口B実証で使用済みの自治体系公募要領）を新工程で通す。

- `/ingest-guidelines`: extract.md（ページアンカー付き）生成・readiness report が出ること・state=spec_draft で current-application が作られること。
- `/confirm-spec`: グループ一括表の提示回数 8 回以下で全必須 item が confirmed/na に到達・全 rule item に predicate_state 付与・`--gate confirm` green・昇格後 state=spec_confirmed。
- `/build-pack`: notes 4 種（該当分）+ pack.json 生成・check-pack green。
- 残課題（原本に記載がない事項）は na または `[要確認]` として記録され、推測で埋められていないこと。
- 回帰テストは合成ミニ fixture（`tools/fixtures/`）に固定する。実在公募要領の実データはコア層にコミットしない（gitignore 領域に留める）。

## 11. スキーマ changelog（schema_version 2.0 を維持、すべて additive-optional）

| 対象 | 変更 | 発効 |
|---|---|---|
| subsidy-spec.schema.json | `source_documents[].extract_path`（string|null、optional。PDF 抽出・貼り付けの両経路で記録） | 本設計 |
| spec-confirmation.schema.json | 新設（§6.3。items[].predicate_state / confirmed_at / confirmed_via / shown_page は optional） | 本設計 |
| subsidy-pack.schema.json | 新設（§3） | 本設計 |
| company-profile.schema.json | `chusho_kihonho_class`（enum|null、optional）を追加 | 本設計 |

- 既存 confirmed spec（同梱・利用者作成とも）はそのまま valid。`--gate confirm` を通す場合のみ predicate_state の付与が必要。

## 12. やらないこと（本設計のスコープ外）

- spec レジストリ（配信 API・公開 data repo）の実装。pack.json をレジストリ配布単位になり得る形にするまでに留める。配布アーキテクチャの方向（repo＝育成単位・パック＝配布単位・完成環境＝生成物）は `docs/design/repo-structure.md` を正とする。
- 公募要領改訂の監視・自動追随（stale 検知は sha 台帳まで）。
- 大型補助金向けスキーマの全面対応（§8 の 1 キーのみ）。
- result-report 送信・採択後フェーズ実運用・複数申請の並行管理（既存設計の据え置き）。
- notes の内容品質の AI 評価ゲート（機械検証は出典規律・参照整合・sha 台帳まで）。
- `packs/` トップレベルディレクトリの新設（`specs/` 配下で実現する）。
- `/ingest-guidelines` の改名、利用者の平置き `input/spec/<id>.json` の強制移行。

## 13. 変更 surface と story 対応

| story id | owner | 依存 | 内容 |
|---|---|---|---|
| pack-builder-design-doc | claude | — | 本設計書の追加と validate 導線（core-manifest 登録・見出しアサーション・harness-ingest-loop からの相互リンク） |
| spec-draft-gate | codex | design | check_spec.py の argparse 化（§6.4）・draft 適用拡張・readiness report・`--gate confirm`（predicate_state 整合検査含む）・spec-confirmation.schema.json 新設・fixtures/test。**manifest + validate wave を同 story 内で更新** |
| clause-verbatim-check | codex | gate | extract_path 追加（PDF・貼り付け両経路）・verbatim 照合・fixtures。manifest + validate wave |
| pdf-intake-flow | codex | verbatim | ingest-guidelines の 3 段構え・extract.md・スポットチェック・setup の任意検出。validate wave |
| cmd-confirm-spec | claude | gate | /confirm-spec 新設（昇格シーケンス 5 段・監査フィールド記入・回復 3 分岐・旧環境からの復旧）・ingest 縮小（state=spec_draft 初期化・current-application 契約 §5.1）・下流コマンドの spec_draft 分岐と stale パス検出（§2.1）・validate ルーティング系アサート更新。manifest + validate wave |
| pack-schema-and-checker | claude | design | subsidy-pack.schema.json（derived_from_spec_sha256 含む）・check-pack.sh・check_pack.py（限定 frontmatter パーサ）・test・fixtures。manifest + validate wave |
| cmd-build-pack | claude | confirm-spec, checker | /build-pack 新設。manifest + validate wave |
| jizokuka-pack-migration | codex | checker | 同梱 spec のパック化・provider notes・spec_version 増分と再 confirm（predicate_state 付与）・**resolver 規約（§2.1）を select-subsidy と全下流コマンドに反映**・validate の path 参照更新・specs/README 改訂（残留平置きの扱い含む） |
| profile-chusho-class | codex | gate | company-profile 追加キー・**intake の JSON 例と質問文・profile fixtures・predicate の三値評価 test・validate assertion を同 story に含める** |
| docs-refresh-pack-flow | codex | 主要実装後 | マニュアル・FAQ・育て方（残留ファイル節・gitignore 調整の選択肢）・onboarding・README・CLAUDE.md・harness-ingest-loop.md の改訂（利用者向け呼称は §0-4 に従う） |
| worked-example-pack | codex | build-pack | worked-example のパック例（合成データ） |

- **story 共通規約**: 新規ファイルを作る story は、その story 内で `core-manifest.json` への登録と `tools/validate.sh` の対応アサーション追加まで行う（story 完了時点で validate green を保つ）。依存順は「schema/checker → manifest/validate → command/docs」に寄せる。
- `docs/design/harness-ingest-loop.md` §1 の状態遷移・§4 コマンド表は本設計（spec_draft・工程分割）を正として改訂し、本ファイルと相互リンクする。
