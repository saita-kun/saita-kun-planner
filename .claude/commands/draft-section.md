---
description: confirmed spec の deliverables[].sections[] から選んだ 1 セクションだけを、frontmatter 付き draft として作成します。
---

# /draft-section

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する文章化の壁打ち役です。`input/current-application.json`、confirmed spec、`input/company-profile.md`、`input/subsidy-fit.md`、必要に応じて `input/deliverables.md` を読み、顧客本人が選んだ 1 セクションだけを叩き台化してください。

このコマンドは、申請書全体を完成させるものではありません。出力は提出用の完成版ではなく、顧客本人が確認、修正、加筆、削除し、募集要項と自社資料に照らして確定するための叩き台です。

## 前提チェック

最初に、次の条件を順番に確認してください。条件を満たさない場合は draft を作らず、該当する先行コマンドへ案内します。

1. `input/current-application.json` が存在すること。
   - 存在しない場合は、まず同梱 spec を使うなら `/select-subsidy`、顧客本人の募集要項から作るなら `/ingest-guidelines` で current application を `state=spec_confirmed` にしてください。
2. `input/current-application.json` の `state` が `planned`、`drafting`、`verified`、`finalized` のいずれかであること。
   - `state=spec_draft` の場合は「突合が未完了です。/confirm-spec を実行してください」と案内し、draft を作らないでください。
   - `state=spec_confirmed` の場合は、先に `/intake` を実行して会社プロフィールを作り、`state=intake_done` にしてください。
   - `state=intake_done` の場合は、先に `/subsidy-fit` と `/plan-deliverables` を実行してください。
   - `state=fit_done` の場合は、成果物一覧が未生成です。先に `/plan-deliverables` を実行し、`state=planned` にしてください。
   - `state` が不明または欠けている場合は、`/plan-deliverables` へ戻って前提を整えてください。
3. `spec_path` が non-null で、実在する confirmed spec JSON を指していること。
   - `spec_path` がない、またはファイルが存在しない場合は、`/select-subsidy` または `/ingest-guidelines` で confirmed spec を選び直してください。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
4. `subsidy_id` が non-null で、spec の `subsidy_id` と一致すること。
   - 食い違う場合は、別の申請案件を混ぜている可能性があるため止めてください。
5. `input/company-profile.md` と、可能なら `input/company-profile.json` が存在すること。
   - 存在しない場合は、confirmed spec を読んだうえで先に `/intake` を実行してください。
6. `input/subsidy-fit.md` が存在すること。
   - 存在しない場合は、先に `/subsidy-fit` で confirmed spec と会社プロフィールを照合してください。
7. 可能なら `bash tools/check-spec.sh <spec_path>` を実行し、spec が green であることを確認してください。

すでに `state=verified` または `state=finalized` の申請で draft を新規作成または更新する場合は、以前の `/verify` や `/finalize` の結果が古くなることを顧客本人へ伝えてください。draft 作成後は `state=drafting` に戻し、後で `/verify` を再実行します。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で解決してください。

1. `input/spec/<subsidy_id>/<subsidy_id>.json`
2. `input/spec/<subsidy_id>.json`
3. `specs/<subsidy_id>/<subsidy_id>.json`
4. `specs/<subsidy_id>.json`

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。

## 使う情報

次の情報だけを根拠にしてください。

- `input/current-application.json`
- `spec_path` が指す confirmed spec
- `input/company-profile.md`
- 必要に応じて `input/company-profile.json`
- `input/subsidy-fit.md`
- 必要に応じて `input/deliverables.md`
- 解決済みパックの notes（該当 section-note と review-lens）
- `knowledge/lessons/` にある過去申請の学び
- 顧客本人が提示した見積書、仕様書、売上資料、作業時間記録、顧客数、商談記録などの根拠資料

ブログ、過去公募の記憶、AI の一般知識で、要件、数値、補助率、補助上限、文字数、対象経費を補わないでください。要件・数値は募集要項が正です。

## セクションメニューの作り方

顧客に候補を出す前に、spec の `deliverables[]` から `produced_by=ai_draftable` の成果物だけを抽出してください。そのうえで、各 deliverable の `sections[]` をメニュー化します。

各候補には、必ず次を表示してください。

- `deliverable_id`
- deliverable の `name`
- `section_id`
- section の `name`
- `kind`
- `max_chars`
- `max_pages`
- `guidance`
- `review_criteria`
- `source_clauses`

`name`、`max_chars`、`guidance`、`review_criteria` は、spec の値を要約で置き換えず、顧客が確認できるように引用してください。`max_chars=null` の場合は「spec 上は null。募集要項・様式側で再確認」と書き、文字数制限なしと断定しないでください。

メニューは、顧客本人に今回作る 1 セクションを選んでもらうためのものです。複数セクションを一度に作らず、必要ならこのコマンドを繰り返してください。

## knowledge/lessons/ の反映

`knowledge/lessons/` に Markdown ファイルがある場合は、draft 作成前に読み、今回の `subsidy_id`、`deliverable_id`、`section_id`、または draft phase に関係する学びを探してください。

反映するときは、次を守ってください。

- 関係する lesson があれば、叩き台の前に「今回反映した knowledge/lessons/」としてファイル名と反映内容を短く列挙する。
- 関係しない lesson は、無理に本文へ混ぜず「今回は直接反映なし」と書く。
- lesson の内容が古い募集要項や別制度に依存している可能性があれば、断定せず `[要確認]` とする。
- knowledge は顧客本人の育成層です。コア層のファイルへ転記したり、上書きしたりしない。

## 解決済みパックの notes 参照

解決済みパックの notes がある場合は、骨子を作る前に該当 section-note と review-lens を読んでください。`input/spec/<subsidy_id>/notes/` があればそれを優先し、なければ同梱パック側の `specs/<subsidy_id>/notes/` を参照します。見つからない場合は、notes なしで進めて構いません。

対象セクションの section-note がある場合は、叩き台の前に「今回参照した書き方メモ」として、path、kind、引用した `[clause: <clause_id>]`、本文へ反映する観点を短く提示してください。review-lens は、課題、解決、実現性、効果、数値根拠の骨子を作る前の確認観点として使います。

境界規律: notes 中で clause 引用のない記述は一般知見扱いとし、数値・要件の根拠には使わない。数値・要件の根拠は従来どおり spec の clauses のみです。notes の記述が spec の `clauses[]`、`guidance`、`review_criteria`、顧客資料と矛盾する場合は、notes ではなく募集要項と spec を優先し、該当箇所に `[要確認]` を付けてください。

同梱パックの notes へ加筆したい場合は knowledge/lessons/ へ誘導してください。顧客本人が自分で作った `input/spec/<subsidy_id>/notes/` は編集できますが、同梱 `specs/` 側の notes を直接編集させないでください。

## 進め方

### 1. 対象セクションを確定する

spec 由来のメニューから、顧客本人に `deliverable_id` と `section_id` を 1 つ選んでもらってください。顧客が自然文で選んだ場合でも、必ず spec 上の ID に突合してください。

選ばれた `deliverable_id` / `section_id` が spec に存在しない場合は draft を作らず、正しい候補から選び直してもらいます。

### 2. 根拠を分けて読む

対象セクションに関係する情報を、次の種類に分けて整理してください。

- spec の section 契約: `name`、`max_chars`、`guidance`、`review_criteria`、`source_clauses`
- 会社プロフィールから確認できる顧客の実情報
- `input/subsidy-fit.md` から確認できる除外要件チェック、必須要件チェック、加点要素、不足準備、狙う枠
- `knowledge/lessons/` から今回反映する学び
- 根拠が足りず、顧客本人の確認が必要な事項

根拠がないまま補助金向けに良く見せる文章へ膨らませないでください。顧客の実情報、confirmed spec、募集要項の条文から言えることだけを使ってください。

### 3. 補助金審査観点で骨子を作る

対象セクションの `guidance` と `review_criteria` を最優先し、その範囲で次の流れを使って骨子を作ってください。

1. 課題: なぜ補助事業が必要なのか
2. 解決: 何を導入、実施、改善するのか
3. 実現性: 誰が、いつ、どの体制と資金で実行するのか
4. 効果: 売上、生産性、作業時間、品質、販路、雇用、地域波及など何が改善するのか
5. 数値根拠: その効果や投資額を支える資料、実績、見積、試算は何か

すべてのセクションに 5 要素を無理に入れる必要はありません。ただし、課題、解決、実現性、効果、数値根拠のつながりが切れている場合は、本文とは別に不足点として指摘してください。

### 4. `## 叩き台` 以下に本文を書く

出力ファイルでは、本文領域を必ず `## 叩き台` 見出しの下に置いてください。`tools/check-drafts.sh` は、この見出しより下から次の同階層 `## ` 見出しまたは EOF までを字数カウントします。

`max_chars` が整数の場合は、その範囲に収まるように書いてください。`max_chars=null` の場合でも長文化せず、顧客が様式に貼り付けて調整しやすい分量にしてください。未確認の数値、資料未確認の効果、募集要項との対応が不明な要件には `[要確認]` を付けてください。

### 5. 顧客本人が直すべき点を添える

叩き台の後に、顧客本人が次に確認すべき事項を具体的に出してください。

- 募集要項で再確認する見出し、文字数、必須記載事項
- spec の `review_criteria` に照らして弱い箇所
- 顧客の資料で確認する売上、従業員数、投資額、効果見込み、KPI
- 見積書、仕様書、売上資料、作業時間記録など追加で必要な根拠
- 表現が強すぎる、根拠が薄い、審査項目との対応が弱い箇所
- 次に `/review` と `/verify` で点検したほうがよい観点

## 出力先とファイル形式

draft は `input/drafts/<subsidy_id>/<section_id>.md` に保存してください。`<subsidy_id>` は `input/current-application.json` の値、`<section_id>` は spec の値を使います。既存ファイルがある場合は、上書き前に顧客へ確認してください。

ファイルは必ず YAML frontmatter から開始し、`deliverable_id`、`section_id`、`drafted_at` を入れてください。`drafted_at` は ISO8601 の現在時刻にします。`subsidy_id` と `spec_version` も追記して構いませんが、`tools/check-drafts.sh` が突合に使う必須キーは `deliverable_id` と `section_id` です。

```markdown
---
deliverable_id: jizokuka-keiei-keikaku
section_id: kokyaku-needs-shijo-doko
drafted_at: 2026-07-02T12:34:56+09:00
---

# kokyaku-needs-shijo-doko

## 作成メモ

- 作成者: 顧客本人
- AIの役割: 1 セクションの叩き台作成と不足点の明示
- 対象補助金: input/current-application.json の subsidy_id
- 参照資料: input/company-profile.md / input/subsidy-fit.md / confirmed spec
- deliverable_id: jizokuka-keiei-keikaku
- section_id: kokyaku-needs-shijo-doko
- 未確認事項: `[要確認]` を参照

## spec から引用した section 契約

| 項目 | 内容 |
| --- | --- |
| name |  |
| max_chars |  |
| guidance |  |
| review_criteria |  |
| source_clauses |  |

## 今回反映した knowledge/lessons/

## 使った根拠

### 会社プロフィール側の根拠

### 募集要項・適合度メモ側の根拠

## 叩き台

対象セクション 1 つだけの文章案を書きます。

## 顧客本人が確認・修正する点

## `[要確認]` リスト
```

上の例の ID は説明用です。実際には、選んだ spec の `deliverable_id` と `section_id` をそのまま使ってください。

## current-application の更新

draft を作成または更新できたら、`input/current-application.json` を更新してください。

- `state` を `drafting` にする。
- `updated_at` を ISO8601 の現在時刻にする。
- `subsidy_id`、`spec_path`、`spec_version`、`chosen_funding` は確認なしに変更しない。
- 可能なら `drafts_dir: "input/drafts/<subsidy_id>/"` を追加する。
- `state=verified` または `state=finalized` から戻した場合は、以前の検証結果や提出前チェックが古くなったことを顧客本人に明示する。

## 出力時の注意

- 1 回の実行で作るのは、顧客が選んだ 1 セクションだけです。
- 文章案は、顧客本人が編集するための叩き台です。完成版、提出版、確定版として扱わないでください。
- spec の `guidance` と `review_criteria` を優先し、募集要項に指定見出し、文字数、様式がある場合はそれを最優先してください。
- 数値根拠なき主張は [要確認] としてください。
- 不明点を補助金向けの一般論で埋めないでください。
- 出力先は `input/drafts/` 配下だけです。`.claude/commands/`、`schemas/`、`specs/`、`tools/`、`docs/` などのコア層を書き換えないでください。
- 最後に「次は `/review` で根拠、文字数、誇張、作成主体を点検し、その後 `/verify` で spec/draft 契約を検査する」ことを案内してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断は行いません。これは叩き台、確定は顧客本人が行います。数値根拠なき主張は [要確認] とし、募集要項または顧客資料で確認できない数値や要件を推測しないでください。
