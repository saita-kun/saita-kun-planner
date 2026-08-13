---
description: 提出後または採否判明後に、結果・講評・学びを knowledge/ に構造化し、次回申請に引き継ぎます。
---

# /retrospect

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する振り返り整理役です。提出後、採否判明後、または提出しなかった判断が確定した後に、今回の申請イベントを `knowledge/records/` と `knowledge/lessons/` に記録してください。

このコマンドの目的は、今回の申請で得た結果、講評、反省、次回に活かす判断基準を、ユーザー自身の repo に残る育成層として構造化することです。次回の `/draft-section` と `/review` は `knowledge/lessons/` を読み、過去の学びを踏まえて叩き台作成とレビュー観点を調整します。

## 使う場面

- 申請を提出し、結果待ちの状態を記録したいとき
- 採択または不採択の結果が判明し、講評や採点を整理したいとき
- 申請準備を進めたが、提出しない判断をした理由を次回に残したいとき
- 今回の `/intake`、`/subsidy-fit`、`/draft-section`、`/review`、`/verify`、`/finalize` で詰まった点を、次回申請の改善材料にしたいとき

出力先は `knowledge/` のみです。`input/`、`.claude/commands/`、`schemas/`、`specs/`、`tools/`、`docs/` などは書き換えないでください。`knowledge/` は `input/` と異なり、ユーザーの repo にコミットして育てる資産です。

## 前提チェック

最初に、次の順で状況を確認してください。足りない情報があっても推測で埋めず、顧客本人に確認するか、該当フィールドを `null`、自由記述側を `[要確認]` にしてください。

1. `schemas/application-record.schema.json` が存在すること。
   - この schema が `knowledge/records/<subsidy_id>-<round>.json` の構造契約です。
2. `input/current-application.json` があれば読み、`subsidy_id`、`spec_version`、`chosen_funding.addon_ids`、`state`、`verify_report_path` を確認すること。
   - `input/current-application.json` がない場合は、顧客本人に対象補助金、回、spec_version、狙った枠を確認してください。次回以降の申請では、最初に `/select-subsidy` または `/ingest-guidelines` で `state=spec_confirmed` を作り、その後 `/intake` に進む流れを案内してください。
3. `knowledge/records/` と `knowledge/lessons/` がなければ作成すること。
4. 記録ファイル名に使う `subsidy_id` と `round` を決めること。
   - `subsidy_id` は小文字英数字とハイフンに正規化してください。
   - `round` が不明な場合は、顧客に確認します。確定できない場合は `round-unknown` を使い、`knowledge/lessons/` 側に `[要確認]` として残してください。
5. 既存の `knowledge/records/<subsidy_id>-<round>.json` または `knowledge/lessons/<subsidy_id>-<round>.md` がある場合は、上書きせず、追記するか別名にするかを顧客本人に確認してください。

## 振り返りインタビュー

顧客本人に、次の順番で確認してください。答えられない項目は無理に埋めず、構造化 JSON では `null` または空配列、Markdown では `[要確認]` として残します。

### 1. 申請イベント

- 対象補助金の `subsidy_id`
- 公募回または管理用の `round`
- 使った `spec_version`
- 狙った加点、特例、上乗せ枠があれば `chosen_addons[]`
- 提出日 `submitted_at`
- 提出しなかった場合は、提出しない判断をした日と理由

`submitted_at` は `YYYY-MM-DD` 形式で、実際に提出した日だけ入れてください。未提出、結果待ち、日付不明の場合は `null` にします。

### 2. 結果

`result` は必ず次の 4 値のどれかにしてください。

- `adopted` — 採択された
- `rejected` — 不採択だった
- `not_submitted` — 最終的に提出しなかった
- `pending` — 提出済みで結果待ち

採点、審査コメント、事務局からの講評、不採択理由、支援機関からのフィードバックがある場合だけ、`score` と `feedback_text` に入れてください。入手していない点数や講評を推測しないでください。

### 3. フェーズ別の学び

各フェーズについて、少なくとも 1 回は質問してください。該当がなければ「特になし」として扱えますが、次回に効く小さな改善がないか確認してください。

- `intake` — 会社情報、売上、従業員数、投資計画、見積、根拠資料の集め方で詰まったこと
- `fit` — 除外要件、必須要件、加点要素、狙う枠、対象経費の判断で迷ったこと
- `draft` — 叩き台の構成、課題と解決策のつながり、数値根拠、事業効果の書き方で改善したいこと
- `verify` — 字数、必須セクション、`[要確認]`、coverage gaps、spec 照合で出た問題
- `finalize` — 添付資料、様式、期限、提出前チェック、最終確認で次回早めにやるべきこと

各 lesson には、`lesson_id`、`phase`、`text`、`applies_to` を持たせます。`applies_to` には関連する `section_id`、`rule_id`、`deliverable_id` が分かる場合だけ入れ、不明なら `null` にしてください。

### 4. 次回アクション

次回の申請前にやることを `next_actions[]` として整理してください。例:

- 見積書を早めに取り、対象経費ごとに根拠資料を分ける
- 公式募集要項の字数制限を spec confirmation の段階で重点確認する
- 加点要素の証憑を `/subsidy-fit` 前に集める
- `[要確認]` が残った理由を `/review` の前に潰す

期限、補助率、補助上限、採択率、審査点などの数値は、顧客本人の資料または公式通知に基づくものだけ記録してください。

## `application-record` JSON を作る

`knowledge/records/<subsidy_id>-<round>.json` を作成してください。この JSON は `schemas/application-record.schema.json` に従います。schema にないキーは追加しないでください。

必ず含めるキー:

- `record_id`
- `subsidy_id`
- `spec_version`
- `result`

可能なら含めるキー:

- `round`
- `chosen_addons`
- `submitted_at`
- `score`
- `feedback_text`
- `lessons`
- `next_actions`
- `created_at`

出力例の形は次の通りです。実際の値は顧客本人の回答と確認済み資料に合わせてください。

```json
{
  "record_id": "jizokuka-20-2026-01",
  "subsidy_id": "jizokuka-20",
  "spec_version": 1,
  "round": "2026-01",
  "chosen_addons": ["賃金引上げ枠"],
  "submitted_at": "2026-07-01",
  "result": "pending",
  "score": null,
  "feedback_text": null,
  "lessons": [
    {
      "lesson_id": "lesson-fit-1",
      "phase": "fit",
      "text": "加点要素の証憑が後半で不足したため、次回は /subsidy-fit 前に証憑リストを確認する。",
      "applies_to": null
    }
  ],
  "next_actions": [
    "次回は見積書と対象経費の対応表を /draft-section 前にそろえる。"
  ],
  "created_at": "2026-07-02T12:34:56+09:00"
}
```

JSON 作成後、最低限 `python3` 標準ライブラリで構文チェックしてください。

```bash
python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' knowledge/records/<subsidy_id>-<round>.json
```

schema 準拠を完全検証する専用ツールはこの story では未実装です。代わりに、`schemas/application-record.schema.json` の `required`、`result` enum、`lessons[].phase` enum、`additionalProperties=false` を目視で照合してください。

## 自由記述の学びを作る

`knowledge/lessons/<subsidy_id>-<round>.md` を作成してください。JSON は機械が読みやすい最小構造、Markdown は次回の顧客本人と Claude Code が読みやすい自由記述です。

推奨構成:

```markdown
# 申請振り返り: <subsidy_id> <round>

## 対応する record

- JSON: knowledge/records/<subsidy_id>-<round>.json
- result: adopted/rejected/not_submitted/pending のいずれか

## 結果と講評

## intake の学び

## fit の学び

## draft の学び

## verify の学び

## finalize の学び

## 次回 /draft-section で反映すること

## 次回 /review で重点確認すること

## next_actions

## future result-report memo
```

`future result-report memo` には、将来の任意 result-report 提出が実装された場合、この record から抜粋 export する想定であることだけを書いてください。送信機能は未実装です。外部送信、GitHub issue 投稿、API 送信、メール送信は行わないでください。

## 次回申請への引き継ぎ

最後に、顧客本人へ次の 3 点を短く伝えてください。

1. 今回の構造化記録は `knowledge/records/` に保存されたこと。
2. 自由記述の学びは `knowledge/lessons/` に保存されたこと。
3. 次回の `/draft-section` と `/review` は `knowledge/lessons/` を参照し、過去の弱点や採択・不採択から得た学びを反映すること。

`knowledge/` はユーザーの資産です。コア更新で消したり上書きしたりしない前提の領域なので、private repo で適切に管理し、必要に応じて自分で編集・追記してください。

## ガードレール

作成者は顧客本人です。AI は振り返りの整理、構造化、次回論点の洗い出しを補助するだけで、申請代行、代理提出、本人に代わる完成判断、採択可能性の断定は行いません。行政書士法に抵触する行為はしません。

採否、採点、講評、提出日、補助率、補助上限、対象経費、審査コメントなどの事実は、顧客本人の通知、公式資料、支援機関からの記録に基づく場合だけ書いてください。出典不明の事実、記憶が曖昧な内容、次回確認が必要な論点には `[要確認]` を付けてください。

`knowledge/` はユーザー repo にコミットされる前提の育成層です。会社名、個人名、取引先名、金額、講評、内部事情などが含まれる場合は、repo の公開範囲を顧客本人が確認してください。公開 repo で扱う場合は、必要に応じて匿名化してください。
