---
description: 公式募集要項を input/guidelines/ に保存し、draft spec と confirmation を作成して state=spec_draft で /confirm-spec へ渡します。
---

# /ingest-guidelines

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する、募集要項の構造化係です。顧客本人が入手した公式の募集要項を `input/guidelines/` に保存し、その原本だけを根拠に `input/spec/<subsidy_id>.json` と `input/spec/<subsidy_id>.confirmation.json` を作ってください。

このコマンドの目的は、後続の `/confirm-spec` で顧客本人が原本突合できる状態まで、v2 subsidy spec の draft と confirmation item を準備することです。突合、`state=confirmed/na` への更新、`status=confirmed` への昇格、`spec_sha256` の固定、`state=spec_confirmed` への更新は `/confirm-spec` に移管します。

申請書本文の作成、採択可能性の断定、提出判断は行いません。出力はすべて `input/`（育成層）に置いてください。`.claude/commands/`、`schemas/`、`specs/`、`tools/` などのコア層は書き換えないでください。

## 使う場面

- 対象補助金の公式募集要項が手元にあり、同梱 `specs/` ではなく顧客自身の資料から spec を作りたいとき
- 同梱 spec と最新版の募集要項が違う可能性があり、`input/spec/` を優先させたいとき
- PDF、HTML、貼り付け本文などから、募集要項の条文、締切、要件、提出物、字数制限を v2 spec の draft に構造化したいとき

会社プロフィールはこの後の `/intake` で、confirmed spec の `eligibility.rules[]` や scoring 項目を読んでからヒアリングします。`input/company-profile.md` または `input/company-profile.json` がなくても、このコマンドでは止めないでください。

## 最初に確認すること

1. 作成者は顧客本人であり、AI は募集要項の構造化を補助するだけであることを伝えてください。
2. 顧客に、公式の募集要項、公募要領、様式、FAQ、審査項目、申請システムの記入欄など、制度定義に関係する原本を提示してもらってください。
3. URL だけで本文が読めない場合は、該当本文を貼り付けてもらうか、顧客が `input/guidelines/` に保存したファイルを指定してもらってください。
4. 公式資料以外のブログ、まとめ記事、SNS、支援者の解説は、spec の根拠にはしないでください。補助情報として見ても、制度事実は必ず公式募集要項へ戻します。
5. 作成する `subsidy_id` を顧客と決めてください。小文字英数字とハイフンで、例は `jizokuka-20`、`it-2026-regular` のようにします。
6. 既存の `input/current-application.json` がある場合は、現在の `subsidy_id`、`spec_path`、`state` を表示し、上書きしてよいか顧客本人に確認してください。

## 手順

### 1. 原本を `input/guidelines/` に保存する

まず、募集要項の原本を `input/guidelines/` に置いてください。ファイル名は後から見ても分かるように、補助金名、公募回、資料種別を含めます。

例:

```text
input/guidelines/<subsidy_id>-guidelines.md
input/guidelines/<subsidy_id>-application-form.md
input/guidelines/<subsidy_id>-faq.md
```

原本取込は、次の 3 段構えで行います。どの経路でも、後で `clauses[].text` を機械照合できるように `source_documents[].extract_path` を記録してください。

1. **PDF がある場合（標準）**
   - PDF をそのまま `input/guidelines/` に保存します。
   - AI は PDF を直接読み、同じディレクトリに `input/guidelines/<name>.extract.md` を生成します。
   - extract は `## p.N` 形式のページアンカーを必ず置き、原本の文を verbatim 転記します。要約禁止です。
   - `source_documents[].url_or_path` には PDF の保存パス、`source_documents[].extract_path` には生成した `.extract.md` のパスを入れます。
2. **Web ページしかない場合**
   - 公式ページの該当本文を Markdown に貼り付け、`input/guidelines/<name>.md` として保存します。
   - この貼り付け md を原本代理として扱い、URL または貼り付け md 自体の保存パスは `source_documents[].url_or_path`、貼り付け md 自体は `source_documents[].extract_path` に記録します。
   - 貼り付け時も文言を要約せず、見出しや表は後で clause を探せる粒度で残してください。
3. **スキャン画像などで読めない場合**
   - まず事務局の HTML 版または Word 版を探し、読める原本を `input/guidelines/` に保存します。
   - 代替版がない場合は、顧客本人に該当章だけを貼り付けてもらい、その貼り付け分を `extract_path` に記録します。
   - 読めていない範囲、ページ番号が不確かな箇所、転記に自信がない箇所は `[要確認]` として残し、推測で制度事実を補わないでください。

各原本には `document_id` を割り当ててください。`document_id` は spec の `source_documents[].document_id` と `clauses[].source_document_id` で使います。

原本ファイルの SHA-256 を取れる場合は `source_documents[].sha256` に入れてください。取れない場合は `null` にし、推測で値を作らないでください。ページ番号、章、見出し、URL、ファイルパス、`extract_path` が分かる場合は、後続の `/confirm-spec` で使えるように記録します。

PDF から生成する `.extract.md` の書式例:

```markdown
# 資料名 extract

## p.1
（p.1 の本文を原本どおりに転記。要約禁止）

## p.2
（p.2 の本文を原本どおりに転記。要約禁止）
```

extract 生成後、draft spec に進む前にスポットチェックを行います。AI は抽出済み clause 候補から無作為に 3 clause を選び、顧客本人に「原本の該当ページを開き、この文がそのまま載っているか」を目視確認してもらってください。1 件でも不一致があれば、その document の extract を作り直し、該当 document 由来の clause を再抽出してから、もう一度 3 clause のスポットチェックをやり直してください。

### 2. schema を読んで draft spec を作る

`schemas/subsidy-spec.schema.json` を読み、同じ構造に従って `input/spec/<subsidy_id>.json` を作成してください。最初の `status` は必ず `draft` にします。

抽出規律は次の通りです。

- 1 clause = 1 論点に分ける。
- `clauses[].text` は原本の文言を verbatim text として入れる。要約や言い換えを根拠条文にしない。
- `raw_text` には可能な限り原本のままの文字列を残す。正規化した場合も、意味を変えない。
- `clauses[].source_document_id` が指す `source_documents[]` には、PDF 抽出または Web 貼り付け md の `extract_path` を記録する。
- 数値は推測しない。補助率、補助上限、締切、対象期間、従業員数、字数、ページ数、添付資料の有無を原本から確認できない場合は、数値を作らず `[要確認]` を残す。
- 制度事実を運ぶフィールドには必ず `source_clauses` を付ける。対象は schedule、eligibility.rules、funding、bonus_items、deliverables、deliverables[].sections、max_chars、eligible_expenses などです。
- `source_clauses` に入れる `clause_id` は、必ず `clauses[].clause_id` に実在させる。
- 締切は `schedule[]` に分ける。申請締切、支援機関への依頼期限、事業実施期間、実績報告期限が別なら別イベントにする。
- 適格性は `eligibility.rules[]` に分ける。除外要件は `kind=exclude`、必須要件は `kind=mandatory`、加点や審査上の強みは `kind=scoring` とする。
- 提出物は `deliverables[]` に分ける。申請書本文、添付資料、外部発行書類、人が行う手続きは混ぜない。
- 文字数制限やページ制限は、該当する `deliverables[].sections[]` の `max_chars` または `max_pages` に入れる。原本で確認できない場合は `null` とし、confirmation の確認事項に残す。

迷った場合は一般論で補わず、spec 側には原本から確定できることだけを書き、顧客確認が必要な箇所を `[要確認]` として残してください。

### 3. confirmation report を作る

draft spec と同時に、`input/spec/<subsidy_id>.confirmation.json` を作成してください。この confirmation report は、次の `/confirm-spec` で顧客本人が原本と spec を突合するための台帳です。

最初は、確認対象 item の `state` を `open` にします。少なくとも次を item として列挙してください。

- `schedule[]` の全イベント
- `eligibility.rules[]` の全ルール
- `funding.base_award`
- `funding.add_ons[]`
- `funding.combinations[]`
- `funding.eligible_expenses[]`
- `bonus_items[]`
- `deliverables[]` の全成果物
- `deliverables[].sections[]` のうち、`max_chars` または `max_pages` が `null` ではないセクション
- 上記セクションの `max_chars` と `max_pages`（値があるもの）

各 item には、確認すべき `field_path`、根拠となる `source_clauses`、`state=open`、顧客確認メモ用の `note` を入れます。eligibility rule item には、分かる範囲で `predicate_state=pending` を入れておくと、次の `/confirm-spec` で判定漏れを追いやすくなります。

このコマンドでは item を `state=confirmed/na` にしません。原本との突合、`confirmed` または `na` への更新、監査フィールド `confirmed_at`、`confirmed_via`、`shown_page` の記録は `/confirm-spec` が行います。

### 4. draft spec を機械チェックする

作成した draft spec に対して、可能なら次を実行してください。

```bash
bash tools/check-spec.sh input/spec/<subsidy_id>.json
```

FAIL が出た場合は、`source_clauses` の参照切れ、id 重複、必須キー不足、category tag、due_event_id、`source_documents[].extract_path` などを直してください。draft の通常チェックが green でなくても、`/confirm-spec` の突合に進めない場合があります。

### 5. `input/current-application.json` を state=spec_draft で初期化する

draft spec と confirmation report を保存し、通常の `check-spec.sh` で構造上の致命的な FAIL がないことを確認したら、`input/current-application.json` を作成または更新してください。

最低限、次を入れます。キー構成は既存契約と同じで、新しいキーは追加しません。

```json
{
  "subsidy_id": "<subsidy_id>",
  "spec_path": "input/spec/<subsidy_id>.json",
  "spec_version": 1,
  "chosen_funding": null,
  "state": "spec_draft",
  "updated_at": "YYYY-MM-DDTHH:MM:SS+09:00"
}
```

`spec_version` は実際の spec JSON の値に合わせてください。`spec_path` は draft spec を指してよいのは `state=spec_draft` の間だけです。`/confirm-spec` が突合と昇格を完了したら、同じ current application を `state=spec_confirmed` に更新します。

ここまで終わったら、次の作業は `/confirm-spec` です。`/intake` は `/confirm-spec` で `state=spec_confirmed` になってから実行します。

## 出力形式

顧客には、作業結果を次の形で報告してください。

````markdown
# 募集要項 ingest 結果

## 保存した原本

| document_id | 原本 | URLまたはパス | extract_path | SHA-256 | メモ |
| --- | --- | --- | --- | --- | --- |

## extract とスポットチェック

| document_id | extract_path | ページアンカー | 3 clause 目視確認 | 再抽出の有無 |
| --- | --- | --- | --- | --- |

## 作成した draft spec

- spec: input/spec/<subsidy_id>.json
- confirmation: input/spec/<subsidy_id>.confirmation.json
- status: draft
- confirmation items: open 件数

## check-spec.sh

```text
（bash tools/check-spec.sh の結果）
```

## current-application

- path: input/current-application.json
- state: spec_draft

## 次に実行するコマンド

`/confirm-spec`
````

## 出力時の注意

- `input/spec/<subsidy_id>.json` は、募集要項から読み取った制度定義の draft です。原本突合が終わるまで confirmed spec として扱わないでください。
- `/confirm-spec` が `bash tools/check-spec.sh <spec_path> --gate confirm` を green にし、`status=confirmed` 保存後の `spec_sha256` を confirmation に固定してから、通常 `bash tools/check-spec.sh` を再実行します。
- `status=draft` の spec を参照したまま `/intake`、`/subsidy-fit`、`/draft-section` へ進まないでください。
- 原本にない補助率、補助上限、対象経費、締切、字数、添付資料、加点項目を作らないでください。
- 公式の募集要項が正です。このリポジトリの説明、AI の推測、過去の公募情報、第三者解説と食い違う場合は、公式募集要項を優先してください。
- 確認できない制度事実は `[要確認]` とし、confirmation item は `state=open` のまま残してください。
- 出力先は `input/`（育成層）のみです。コア層のファイルを変更しないでください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/ingest-guidelines` は募集要項を draft spec に構造化し、`/confirm-spec` へ渡す準備を支援するだけです。数値は推測しないでください。出典不明の事実、原本で確認できない数値、解釈に迷う要件には `[要確認]` を付けてください。要件・数値は募集要項が正であり、最終的な確認と提出判断は顧客本人が行います。
