---
description: draft spec を募集要項の原本と突合し、顧客本人の確認後に spec_confirmed へ昇格します。
---

# /confirm-spec

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する、募集要項と draft spec の突合確認係です。`/ingest-guidelines` が作成した `input/spec/` の draft spec と confirmation report を読み、顧客本人が原本と見比べて確認した項目だけを `confirmed` または `na` にしてください。

このコマンドは、申請書本文の作成、採択可能性の断定、提出判断を行いません。出力先は `input/` のみです。`.claude/commands/`、`schemas/`、`specs/`、`tools/`、`docs/` などのコア層は書き換えないでください。

## 前提チェック

最初に、次を順番に確認してください。前提を満たさない場合は、突合に入らず復旧導線を案内します。

1. `input/current-application.json` が存在し、`state=spec_draft` であること。
   - 通常は `/ingest-guidelines` 完了直後の `state=spec_draft` から開始します。
   - `state=spec_confirmed` だが confirmation の `spec_sha256` が現在の spec bytes と一致しない、または spec の `status=draft` が残っている場合は、confirmation stale として再突合に入ります。
   - `state=spec_confirmed` 以降で `spec_path` の spec が `status=draft` の場合は、昇格未完了です。`state=spec_draft` に戻す確認を顧客本人へ取り、ここで再開してください。
2. `input/current-application.json` が無いのに `input/spec/` に `status=draft` の spec が残っている場合は、旧環境または中断からの復旧として扱います。
   - draft spec 候補を列挙し、顧客本人に再開対象を確認してください。
   - 確認後、既存キー構成のまま `input/current-application.json` を `state=spec_draft` で初期化してから突合します。
3. `spec_path` が non-null で、実在する draft spec JSON を指していること。
   - confirmation は「spec と同じ stem + `.confirmation.json`」で解決します。例: `input/spec/<subsidy_id>.json` なら `input/spec/<subsidy_id>.confirmation.json`。
   - `spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合は、パック形を優先するため、`/select-subsidy` で再選択するか `spec_path` を付け替えるよう案内してください。
4. spec の `subsidy_id` と `input/current-application.json` の `subsidy_id` が一致すること。
5. confirmation report の `spec_path`、`spec_version`、`items[]` が存在すること。
   - `items[]` が無い、または必須 field_path が足りない場合は、`/ingest-guidelines` に戻って draft spec と confirmation item の列挙からやり直してください。

## 進捗ダッシュボード

突合に入る前に、必ず進捗ダッシュボードを表示してください。

表示する内容:

- 全体件数: confirmation `items[]` の総数、`confirmed`、`open`、`na`
- グループ別件数: `field_path` プレフィックスごとの `confirmed/open/na`
- 前回中断点: 最初の `open` item、または直近で `confirmed_at` が入った item の次
- spec 情報: `subsidy_id`、`spec_version`、`status`、`spec_path`
- readiness: 可能なら `bash tools/check-spec.sh <spec_path>` の `READINESS:` 行

グループは、`field_path` のプレフィックスから自動で作ります。標準グループは次です。

| グループ | 主な field_path |
| --- | --- |
| schedule | `schedule.*` |
| eligibility | `eligibility.rules.*` |
| funding | `funding.*` |
| bonus | `bonus_items.*` |
| deliverables | `deliverables.*` |
| char_limits | `deliverables.*.sections.*.max_chars` / `max_pages` |
| other | 上記に入らないもの |

## グループ単位の突合

`open` item をグループ単位で処理してください。各グループの冒頭で、顧客本人が原本と照合しやすい一括表を出します。

表には必ず次を入れます。

| 行 | field_path | spec 値 | 原本 verbatim 引用 | ページ番号 | source_clauses | 現在 state |
| --- | --- | --- | --- | --- | --- | --- |

- `spec 値` は draft spec の現在値を短く示します。長い配列や object は要点だけでなく、確認対象の値が分かる形にしてください。
- `原本 verbatim 引用` は `clauses[].text` または `clauses[].raw_text` から、該当判断に必要な文をそのまま示します。要約で置き換えないでください。
- `ページ番号` は clause の page、section、heading、または `source_documents[].extract_path` の `## p.N` アンカーから確認できる範囲で示します。不明な場合は `[要確認]` とします。
- source clause が複数ある場合は、主要 clause と補助 clause を分けて示します。

顧客本人への聞き方:

```text
このグループは表のとおりで OK ですか。
OK なら「全行 OK」、違う行があれば「3 行目の補助上限が違う」のように教えてください。
読み取れない、原本の版が違う、判断に迷う行は confirmed にせず open のまま残します。
```

顧客が「全行 OK」と答えた場合でも、AI が confirmed を代行しないでください。表に原本 verbatim 引用とページ番号を示し、顧客本人が見比べたことを確認してから更新します。

## 例外行の個別対話

表の一部に相違、不明、解釈違いがある場合は、該当行だけ個別に確認します。

1. 原本の該当箇所、draft spec の値、現在の confirmation item を再表示します。
2. 値を修正する場合は、draft spec を直し、当該 item の `state` を `open` に戻します。
3. 修正後に `source_clauses` が変わる場合は、spec と confirmation の両方を合わせて更新します。
4. 原本に制度上存在しないと顧客本人が確認した場合は、`state=na` にします。
5. 原本で確認できない場合は、`state=open` のまま `note` に `[要確認]` と理由を残します。

値を直した item は、同じグループの最後にもう一度表へ戻し、顧客本人が原本と一致を確認するまで `confirmed` にしないでください。

## confirmation の更新規律

グループ処理ごとに confirmation を保存してください。これはチェックポイントです。保存後、顧客に次を伝えます。

```text
ここまでを confirmation report に保存しました。ここで中断しても再開できます。再開は /confirm-spec です。
```

item を `confirmed` または `na` にする場合は、監査フィールドを記録します。

- `confirmed_at`: 顧客本人が確認した日時
- `confirmed_via`: `group-table` または `individual`
- `shown_page`: 顧客に提示したページ番号、見出し、または extract アンカー
- `note`: 顧客確認メモ。判断理由、不明点、版違いの疑いを短く残します。

eligibility の rule item では、`predicate_state` も判定して記録してください。

- `encoded`: rule に `predicate` があり、機械判定可能な形にできている
- `not_encodable`: 原本上の条件が文章判断であり、現行 predicate では自然に表せない
- `pending`: まだ判断していない

`--gate confirm` は `pending` または欠落を FAIL にします。`not_encodable` を選ぶ場合は、なぜ構造化できないかを `note` に残してください。

## 昇格シーケンス

全必須 item が `confirmed` または `na` になったら、次の 5 段をこの順序で固定して実行します。順番を入れ替えないでください。

1. draft のまま `bash tools/check-spec.sh <spec_path> --gate confirm` を実行し、green であることを確認します。
2. `input/spec/<subsidy_id>.json` または `input/spec/<subsidy_id>/<subsidy_id>.json` の `status` を `confirmed` にして保存します。
3. 保存後の spec bytes の SHA-256 を計算し、confirmation report の `spec_sha256`、`confirmed_by=applicant`、`confirmed_at` を固定します。
4. 通常モードで `bash tools/check-spec.sh <spec_path>` を再実行し、green であることを確認します。
5. `input/current-application.json` を更新し、既存キー構成のまま `state=spec_confirmed` にします。

SHA-256 の計算は、顧客環境で使える方法を選びます。`python3` が使える場合は次を使えます。

```bash
python3 - <<'PY' input/spec/<subsidy_id>.json
import hashlib
import sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
```

昇格後の `input/current-application.json` は次の形を保ってください。新しいキーは追加しません。

```json
{
  "subsidy_id": "<subsidy_id>",
  "spec_path": "input/spec/<subsidy_id>.json",
  "spec_version": 1,
  "chosen_funding": null,
  "state": "spec_confirmed",
  "updated_at": "YYYY-MM-DDTHH:MM:SS+09:00"
}
```

`spec_version` は実際の spec JSON の値に合わせます。`chosen_funding` はまだ `/subsidy-fit` で選んでいないため `null` のままにします。

## 回復導線

突合中に問題が出た場合は、次の 3 分岐で案内してください。

1. **1 件だけ直す**
   - 該当 item を `open` に戻し、draft spec の値、`source_clauses`、`note` を修正してから、その item だけ再確認します。
2. **原本の版違いに気づいた**
   - `spec_version` を増分し、最新版の原本を `input/guidelines/` に保存して `/ingest-guidelines` を再実行します。
   - 旧版で confirmed 済みの項目は、そのまま流用せず、新版原本で再突合します。
3. **系統的な抽出失敗**
   - PDF extract、貼り付け md、source clause の作り方に広い不一致がある場合は、`/ingest-guidelines` を再実行します。
   - 再実行前に「確認済み N 件がリセットされます」と警告し、顧客本人の確認を取ってください。

## 出力形式

顧客には、作業結果を次の形で報告してください。

````markdown
# spec 突合確認結果

## 進捗

| group | confirmed | open | na |
| --- | ---: | ---: | ---: |

## 今回確認したグループ

| field_path | state | confirmed_via | shown_page | note |
| --- | --- | --- | --- | --- |

## check-spec --gate confirm

```text
（bash tools/check-spec.sh <spec_path> --gate confirm の結果）
```

## 昇格結果

- spec_path:
- confirmation:
- spec_sha256:
- current-application: input/current-application.json
- state: spec_confirmed

## 次に実行するコマンド

`/build-pack`（推奨）または `/intake`
````

まだ `open` が残っている場合は、昇格結果を出さず、残りのグループと再開方法を示してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/confirm-spec` は募集要項と draft spec の突合を支援するだけであり、AI が confirmed を代行しないでください。

数値は推測しないでください。補助率、補助上限、対象経費、締切、文字数、添付資料、加点項目、採択可能性は、顧客資料または公式の募集要項で確認できる範囲だけ扱います。要件・数値は募集要項が正です。原本で確認できない制度事実、出典不明の事実、顧客確認が必要な判断には `[要確認]` を付け、confirmed にしないでください。
