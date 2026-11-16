# knowledge/ — 申請後の学びを残す育成層

`knowledge/` は、補助金申請を重ねるたびに、顧客本人の repo の中で育つ「育成層」です。`input/` が今回作業中の会社情報、spec、draft、検査結果を置く作業領域であるのに対し、`knowledge/` は申請後の結果、講評、反省、次回に活かす学びを残す長期資産です。

このディレクトリはユーザーの資産としてコミットする前提です。テンプレート側のコア更新では触れません。`.claude/commands/`、`schemas/`、`specs/`、`tools/`、`docs/` が更新されても、`knowledge/` に蓄積した記録は顧客本人の repo に残し続けます。

## 置くもの

### `knowledge/records/`

`/retrospect` が、1 回の申請イベントごとに JSON を作ります。

ファイル名:

```text
knowledge/records/<subsidy_id>-<round>.json
```

この JSON は `schemas/application-record.schema.json` に従います。主な内容は次の通りです。

- `record_id`
- `subsidy_id`
- `spec_version`
- `round`
- `chosen_addons`
- `submitted_at`
- `result`（`adopted` / `rejected` / `not_submitted` / `pending`）
- `score`
- `feedback_text`
- `lessons`
- `next_actions`
- `created_at`

採点、講評、不採択理由、提出日などは、顧客本人が持つ公式通知、事務局連絡、支援機関の記録に基づく場合だけ書きます。分からない数値や講評は推測せず、`null` または `[要確認]` として扱います。

### `knowledge/lessons/`

`/retrospect` が、同じ申請イベントの自由記述メモを作ります。

ファイル名:

```text
knowledge/lessons/<subsidy_id>-<round>.md
```

ここには、フェーズ別の学びを人間が読みやすい形で残します。

- `intake` — 会社情報、数値根拠、見積、証憑を集める段階の学び
- `fit` — 除外要件、必須要件、加点要素、狙う枠を判断する段階の学び
- `draft` — 事業計画書の叩き台を作る段階の学び
- `verify` — 字数、必須セクション、`[要確認]`、coverage gaps を検査する段階の学び
- `finalize` — 添付、様式、期限、提出前確認を整える段階の学び

次回の `/draft-section` と `/review` は、`knowledge/lessons/` に過去の学びがあれば読み、叩き台作成やレビュー時の重点観点に反映します。たとえば「対象経費の根拠資料が遅れた」「課題と投資内容の接続が弱かった」「字数制限を後で直す負担が大きかった」といった学びを、次回の作業に引き継ぎます。

## コア更新との関係

`knowledge/` は育成層です。テンプレート repo の上流更新、将来の `tools/update-core.sh`、コアコマンドの改善では、`knowledge/` を上書きしない前提です。

このため、`knowledge/` には顧客本人の判断で残したい学びを置いてください。支援者や提供側に渡すための場所ではなく、まずは顧客本人が次回申請を良くするための記録です。

## 将来の result-report について

将来、任意の result-report 提出機能を作る場合は、`knowledge/records/*.json` から必要部分を抜粋 export する想定です。この repo では送信機能は未実装です。`/retrospect` は外部送信、GitHub issue 投稿、API 送信、メール送信を行いません。

## ガードレール

作成者は顧客本人です。AI は振り返りの整理、構造化、次回論点の洗い出しを補助するだけで、申請代行、代理提出、本人に代わる完成判断、採択可能性の断定は行いません。行政書士法に抵触する行為はしません。

`knowledge/` はコミットする前提の領域です。会社名、個人名、取引先名、金額、講評、内部事情などが含まれるため、作業 repo は必ず private にしてください。共有用の抜粋を作る場合は、会社名・金額・個人情報を匿名化した別ファイルを使ってください。

数値は推測しません。採否、採点、講評、提出日、補助率、補助上限、対象経費、審査コメントなどは、顧客本人の資料または公式資料に基づく場合だけ記録してください。出典不明の事実、根拠が不足している主張、顧客確認が必要な情報には `[要確認]` を付けます。
