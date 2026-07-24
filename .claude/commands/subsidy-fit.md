---
description: 確認済み spec と company-profile JSON を照合し、3段階 matching・三値評価・狙う枠を input/subsidy-fit.md に整理します。
---

# /subsidy-fit

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する整理役です。`input/company-profile.json` を機械照合の正本、`input/company-profile.md` を人間可読ビューとして読み、確認済み subsidy spec と照合して `input/subsidy-fit.md` を作成してください。

このコマンドは、採択可能性を断定するものではありません。目的は、顧客本人が確認済み spec と公式の募集要項に沿って検討できるように、除外要件、必須要件、加点要素、不足準備、狙う枠を見える化することです。

## このコマンドでの一次情報

- 制度事実の正本は confirmed spec です。必ず spec を読み込み、`eligibility.rules[]`、`funding`、`bonus_items[]`、`clauses[]`、`source_clauses[]` を根拠にしてください。
- 募集要項は一次情報ですが、このコマンドでは貼り付け本文を直接の正本にしません。募集要項をまだ spec 化していない場合は、先に `/ingest-guidelines` で `input/spec/` に confirmed spec を作ってください。
- 公式資料と spec が食い違う疑いがある場合は、募集要項を優先し、spec の再確認を案内してください。
- 要件・数値は募集要項が正です。spec や会社プロフィールから確認できない内容、顧客判断が必要な内容には `[要確認]` を付けてください。

## 前提チェック

次の順に確認してください。前提を満たさない場合は `input/subsidy-fit.md` を作らず、先行作業へ案内します。

1. `input/company-profile.json` が存在すること。
   - 存在しない場合は、`input/current-application.json` の `state=spec_confirmed` を確認してから、先に `/intake` を実行してください。
   - `input/company-profile.md` もあれば、人間可読ビューとして照合の説明に使ってください。
2. `input/current-application.json` が存在すること。
   - 存在しない場合は、同梱 spec を使うなら `/select-subsidy`、顧客本人の募集要項から作るなら `/ingest-guidelines` を先に実行してください。
3. `input/current-application.json` の `state` が `intake_done` であること。
   - `state=spec_draft` の場合は「突合が未完了です。/confirm-spec を実行してください」と案内し、適合確認を始めないでください。
   - `state=spec_confirmed` の場合は、対象 spec は確定済みですが会社情報が未整理です。先に `/intake` を実行してください。
   - `state=fit_done`、`planned`、`drafting`、`verified`、`finalized` で再実行する場合は、後続の成果物、draft、verify report が古くなる可能性を顧客本人に伝え、必要なら再実行後に `/plan-deliverables` 以降をやり直してください。
   - `state` が欠けている、または別の値の場合は、`/select-subsidy` または `/ingest-guidelines` から対象 spec を確定し、`/intake` を完了して `intake_done` にしてください。
4. confirmed spec が選択されていること。
   - `input/current-application.json` の `spec_path` が non-null で実在する場合は、それを入口に、下の解決順で選んだ spec を使います。
   - `spec_path` がない場合、このコマンドでは初期化しません。`input/spec/` に顧客が作成・確認した spec があるなら `/ingest-guidelines` の完了状態を確認し、同梱 `specs/` を使うなら `/select-subsidy` を実行してください。
   - `input/spec/` と `specs/` は候補の置き場です。`/subsidy-fit` は `current-application.json` に記録済みの spec を読みます。
   - どちらにも対象がない場合は、公式募集要項から `/ingest-guidelines` を実行するよう案内してください。
5. 選んだ spec の `status` が `confirmed` であること。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
   - `status=draft` の spec は使いません。confirmation report で原本突合を済ませてください。
6. 可能なら、選んだ spec に対して `bash tools/check-spec.sh <spec>` を実行し、green であることを確認してください。
   - FAIL が出た場合は、適合確認へ進まず、spec または confirmation の不整合を直してください。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で解決してください。

1. `input/spec/<subsidy_id>/<subsidy_id>.json`
2. `input/spec/<subsidy_id>.json`
3. `specs/<subsidy_id>/<subsidy_id>.json`
4. `specs/<subsidy_id>.json`

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。

## spec 未選択時の案内

`input/current-application.json` に spec が未設定の場合、このコマンド内で補助金を選ばないでください。入口Aとして同梱 `specs/` を使う場合は `/select-subsidy`、入口Bとして顧客本人の公式募集要項から `input/spec/` を作る場合は `/ingest-guidelines` へ戻します。どちらの入口も、照合に進む前に次のような `state=spec_confirmed` の受け渡し状態を作ります。

```json
{
  "subsidy_id": "<spec.subsidy_id>",
  "spec_path": "<選択した spec のパス>",
  "spec_version": <spec.spec_version>,
  "chosen_funding": null,
  "state": "spec_confirmed",
  "updated_at": "YYYY-MM-DDTHH:MM:SS+09:00"
}
```

この時点の状態は state=spec_confirmed です。まだ会社情報ヒアリング、適合確認、枠選択は終わっていないため、`chosen_funding` は `null` のままにします。次に `/intake` を実行し、会社プロフィールを作って `state=intake_done` にしてから、この `/subsidy-fit` に戻ってください。

既存の `subsidy_id`、`spec_path`、`spec_version` が別の補助金を指している場合は、上書き前に必ず顧客へ確認してください。複数申請の同時管理は MVP では扱わず、現在の申請 1 件だけを `current-application.json` で管理します。

## 入力として使うもの

- `input/company-profile.json`
- `input/company-profile.md`
- `input/current-application.json`
- 解決順で選んだ confirmed spec
- 必要に応じて、spec の `source_clauses[]` が参照する `clauses[]`
- 必要に応じて `templates/補助金要件マッピング.md`

ブログ、まとめ記事、SNS、過去公募の記憶、AI の一般知識で要件や数値を補わないでください。

## 進め方

以下の順に作業してください。判断の根拠は必ず `source_clauses` と `clauses[].text` で示し、根拠が薄い場合は断定しないでください。

### 1. spec の前提を整理する

spec から、少なくとも次の項目を抽出してください。確認できない項目は `[要確認]` とします。

- `subsidy_id`
- 補助金名、公募回、`spec_version`
- spec のパス、`status`
- `source_documents[]`
- 主要な `schedule[]`
- `funding.base_award`
- `funding.add_ons[]`
- `funding.combinations[]`
- 主要な `eligible_expenses[]`
- `deliverables[]` の概要

各項目には、可能な限り `source_clauses` と対応する `clauses[].text` の短い引用を付けてください。引用は制度事実の根拠であり、文章を飾るために使わないでください。

### 2. saita-kun の 3段階 explainable matching で確認する

顧客本人が判断しやすいように、次の 3段階 explainable matching で適合理由を説明してください。

1. 除外条件に当たらないか
2. 必須要件を満たしているか
3. 審査上の強みや加点要素を示せるか

この 3段階は、spec の `eligibility.rules[].kind` を使って機械的に分けます。

- `kind=exclude` → 除外要件チェック
- `kind=mandatory` → 必須要件チェック
- `kind=scoring` → 加点要素

spec に `kind=scoring` の rule が少ない場合でも、`bonus_items[]` と `eligibility.rules[]` の関連を確認し、加点要素として整理してください。ただし、加点になると断定せず、証憑や顧客確認が必要な項目は `[要確認]` にします。

### 3. predicate.py による三値評価

各 rule に `predicate` がある場合は、次のコマンドで deterministic evaluator を実行してください。

```bash
python3 tools/lib/predicate.py <spec> <rule_id> input/company-profile.json
```

評価結果は `true`、`false`、`unknown` の三値です。扱いは次の通りです。

| rule kind | true | false | unknown |
| --- | --- | --- | --- |
| exclude | 除外条件に該当する可能性。根拠付きで明示し、申請継続前に顧客確認 | 除外条件には該当しないと読める。根拠付きで記録 | 顧客確認リスト行き `[要確認]` |
| mandatory | 満たす(根拠付き) | 未充足または未充足可能性として明示 | 顧客確認リスト行き `[要確認]` |
| scoring | 活かせる可能性あり。ただし証憑を確認 | 活かせない、または現時点で根拠不足 | 顧客確認リスト行き `[要確認]` |

rule の `predicate` が `null` の場合は、機械評価をせず `unknown` として扱い、`verification` と `source_clauses` を読んで顧客確認事項に落としてください。`false` を都合よく「問題なし」に変換しないでください。除外 rule では `false` が「除外に該当しない可能性」を意味し、必須 rule では `false` が「未充足」を意味します。

各 judgment には、必ず次を入れてください。

- `rule_id`
- `kind`
- predicate 評価結果
- 判定ラベル
- `source_clauses`
- 対応する `clauses[].text` の短い引用
- 会社プロフィール側の根拠
- 次に顧客が確認すること

採択可能性、採択率、採択見込み、補助金額の確定、補助率の適用可否を断定してはいけません。

### 4. 除外要件チェック

`eligibility.rules[]` のうち `kind=exclude` の rule をすべて確認してください。

- predicate がある rule は `predicate.py` の三値評価を使います。
- predicate がない rule は、spec の `verification` と `clauses[]` を引用し、顧客確認に回します。
- `true` または `unknown` の項目は、申請継続前の重要論点として上部にも再掲してください。
- 会社プロフィールに該当値がない場合は、推測せず `[要確認]` にしてください。

判定は、`該当可能性あり / 該当なしと読める / [要確認]` のいずれかで整理してください。

### 5. 必須要件チェック

`eligibility.rules[]` のうち `kind=mandatory` の rule をすべて確認してください。

- predicate がある rule は `predicate.py` の三値評価を使います。
- predicate がない rule は、`verification`、`source_clauses`、会社プロフィール、顧客資料の有無を照合します。
- 枠や特例に関係する rule も、後続の `chosen_funding` 判断に必要なので落とさないでください。

各項目について、`満たす / 未充足可能性 / [要確認]` の判定、根拠、次に必要な確認を記録してください。

### 6. 加点要素を整理する

`kind=scoring` の rule と `bonus_items[]` を確認してください。加点・審査観点は、会社プロフィールと照合して「活かせる可能性」「証憑が必要」「現時点では根拠不足」に分けます。

加点項目は、顧客が狙うかどうかを決める材料です。AI が勝手に選択せず、必要書類、宣誓、実施負担、未達時リスク、`source_clauses` を見せて顧客本人に確認してください。

### 7. 狙う枠を選ぶ

適合確認の後、`funding.base_award` と `funding.add_ons[]` を読み、今回の申請で狙う枠を顧客本人と相談してください。

1. base は原則として `chosen_funding.base=true` として扱います。ただし、base 自体に未充足がある場合は `[要確認]` を残します。
2. 各 add-on について、`add_ons[].required_rules` に挙がる rule の判定を確認します。
3. required rule が `未充足` または `[要確認]` の add-on は、選択候補にしてよいかを顧客に確認し、リスクを明記します。
4. `funding.combinations[]` を読み、選んだ `addon_ids[]` の組み合わせ上限や併用条件を確認します。
5. `rate_override` や `max_amount_delta` は spec の値だけを表示し、実際の補助金額は見積・対象経費・募集要項確認が必要であることを明記します。

決定内容は、次の形で `input/current-application.json` に記録してください。

```json
"chosen_funding": {
  "base": true,
  "addon_ids": []
}
```

顧客が add-on を選ぶ場合は `addon_ids` に spec の `addon_id` だけを入れてください。自由記述の枠名を入れないでください。

### 8. 不足準備を洗い出す

次のものを具体的に並べてください。

- `unknown` になった predicate の確認事項
- predicate が `null` のため顧客確認が必要な rule
- add-on 選択に必要な証憑、宣誓、添付
- `source_clauses` を見直すべき条文
- 会社プロフィール JSON の `null` を埋めるために必要な資料
- 見積書、仕様書、売上資料、賃金台帳、認定書、支援機関確認など
- `/plan-deliverables` に進む前に解消したい論点

## 出力形式

適合度メモは、原則として `input/subsidy-fit.md` に作成してください。既存ファイルがある場合は、上書き前に顧客へ確認してください。

```markdown
# subsidy-fit

## 作成メモ

- 作成者: 顧客本人
- AIの役割: confirmed spec と会社プロフィールの照合、論点整理、不足点の明示
- 一次情報: 公式の募集要項
- 正本: spec
- 未確認事項: `[要確認]` を参照

## 対象補助金

| 項目 | 内容 |
| --- | --- |
| subsidy_id |  |
| spec_path |  |
| spec_version |  |
| spec_status |  |

## spec から読み取った前提

## 3段階 explainable matching

### 1. 除外条件に当たらないか

### 2. 必須要件を満たしているか

### 3. 審査上の強みや加点要素を示せるか

## 除外要件チェック

| rule_id | 判定 | predicate | source_clauses | 募集要項の根拠 | 会社プロフィール側の根拠 | 次の確認 |
| --- | --- | --- | --- | --- | --- | --- |

## 必須要件チェック

| rule_id | 判定 | predicate | source_clauses | 募集要項の根拠 | 会社プロフィール側の根拠 | 次の確認 |
| --- | --- | --- | --- | --- | --- | --- |

## 加点要素

| rule_id / bonus_id | 活かせる可能性 | source_clauses | 根拠 | 不足準備 |
| --- | --- | --- | --- | --- |

## 狙う枠

```json
{
  "base": true,
  "addon_ids": []
}
```

## funding の確認

| 項目 | 内容 | source_clauses | 注意 |
| --- | --- | --- | --- |

## 不足準備

## 事業計画書へ反映すべき論点

## `[要確認]` リスト
```

空欄を残さず、該当値がない場合は `null`、`該当なし`、または `[要確認]` のいずれかで表現してください。根拠がない事実を補わないでください。

## current-application の更新

`input/subsidy-fit.md` を作成し、狙う枠を顧客本人が確認したら、`input/current-application.json` を更新してください。

- `subsidy_id`、`spec_path`、`spec_version` は、使用した spec と一致させる。
- `chosen_funding` に `{base:true, addon_ids:[...]}` を記録する。
- `state` を `fit_done` にする。
- `updated_at` を現在時刻に更新する。
- 必要なら `subsidy_fit_path: "input/subsidy-fit.md"` を追加する。

`chosen_funding` が未決定の場合は `state=fit_done` にしないでください。顧客本人が枠を選べない状態なら、`[要確認]` を残して止めます。

## 出力時の注意

- 判定は、顧客本人が募集要項と spec を読んで判断するための補助情報として書いてください。
- 採択可能性、補助金額、補助率、補助上限、対象経費、締切、文字数を推測で断定しないでください。
- 募集要項の文言、spec の `source_clauses`、会社プロフィールのどれに根拠があるかを分けてください。
- spec にない一般論を要件として扱わないでください。
- `input/company-profile.json` の値が null の場合は、predicate 評価を unknown として扱い、`[要確認]` にしてください。
- 公式の募集要項と spec が食い違う疑いがある場合は、募集要項を優先し、`/ingest-guidelines` で再突合するよう案内してください。
- 最後に「次は `/plan-deliverables` で成果物マニフェストを再生成する」ことを案内してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断は行いません。要件・数値は募集要項が正です。推測で補わず、出典不明の事実や確認が必要な項目には `[要確認]` を付けてください。提出判断、完成判断、官公署への提出は顧客本人が行います。
