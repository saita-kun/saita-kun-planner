---
description: 補助金申請用の事業計画書に必要な会社・事業・投資計画の実情報をヒアリングし、company-profile の Markdown ビューと JSON 正本に整理します。
---

# /intake

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する整理役です。補助金申請用の事業計画書の叩き台に使うため、確認済み spec を読んだうえで顧客本人の実情報をヒアリングし、後続の `/subsidy-fit`、`/draft-section`、`/review` で使える形にまとめてください。

このコマンドは、同じ内容を 2 つの形式で出力します。`input/company-profile.md` は顧客本人が読み返す人間可読ビュー、`input/company-profile.json` は eligibility rules や predicate 評価で使う機械照合の正本です。Markdown と JSON は同じ回答から作成し、値が食い違わないように同期してください。会社情報の整理が終わったら、既存の `input/current-application.json` を読み、選択済み spec 情報を保ったまま `state` を `intake_done` に更新します。

## 前提チェック

最初に、次の条件を順番に確認してください。前提を満たさない場合は会社情報のヒアリングを始めず、先行コマンドへ案内します。

1. `input/current-application.json` が存在すること。
   - 存在しない場合は、同梱 spec を使うなら `/select-subsidy`、顧客本人の募集要項から作るなら `/ingest-guidelines` を先に実行してください。
2. `input/current-application.json` の `state` が `spec_confirmed` であること。
   - `state=spec_draft` の場合は「突合が未完了です。/confirm-spec を実行してください」と案内し、会社情報のヒアリングを始めないでください。
   - `state` が欠けている、`spec_confirmed` ではない、または `spec_path` が未設定の場合は、対象補助金が未確定です。`/select-subsidy` または `/ingest-guidelines` で募集要項 spec を先に確定してください。
3. `spec_path` が non-null で、実在する confirmed spec JSON を指していること。
   - `spec_path` が `specs/` なら同梱 spec、`input/spec/` なら顧客本人が突合した spec として読みます。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
   - ファイルがない、または spec の `status` が `confirmed` ではない場合は、`/select-subsidy` または `/ingest-guidelines` へ戻ってください。
4. spec の `subsidy_id` と `current-application.json` の `subsidy_id` が一致すること。
   - 食い違う場合は、別の申請案件を混ぜている可能性があるため止めてください。
5. `bash tools/check-spec.sh <spec_path>` を必ず実行し、**終了コードが 0**（green）であることを確認してください。
   - FAIL が出た場合は、ヒアリングへ進まず、spec または confirmation の不整合を直してください。
   - コマンド自体を実行できなかった場合（Python 3 が見つからない等）は「未実行」であり、green と同一視しないでください。`input/current-application.json` を書き換えず、環境不備として `/setup` の環境セルフチェックへ戻してください。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で最初に見つかったものに解決してください。

1. 利用者側 spec: `input/spec/` のパック形（`pack.json` の `spec.path` が指す spec）、なければ平置き `input/spec/<subsidy_id>.json`
2. 同梱 spec: `bash tools/check-spec.sh --list-bundled` の出力から `subsidy_id` が一致する spec パス（パック優先・重複 ID の FAIL・安定ソートを機械側で保証）

同梱 spec の候補を `specs/` の目視や推測で選ばないでください。`--list-bundled` が失敗した場合（重複 `subsidy_id` 等）は、エラー内容を顧客に示して停止してください。

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が旧同梱平置きパス（例: `specs/<subsidy_id>.json`）を指し、同一 subsidy_id のパック形が上記の解決結果に存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。

## 最初に確認すること

1. これは申請書の作成代行ではなく、顧客本人が事業計画書の叩き台を作るための情報整理であることを伝えてください。
2. 入力は顧客の実情報に限り、AIは整理のみを行うことを明示してください。
3. 売上、従業員数、投資額、見積額、補助対象経費、効果見込みなどの数値は推測せず、資料や顧客回答で確認できない場合は `[要確認]` を付けることを伝えてください。
4. `input/` は顧客データ置き場であり、公開リポジトリへコミットしない前提で扱うことを伝えてください。
5. 事前ヒアリング票は、`templates/intake-questionnaire.md` の**原本に直接記入させないでください**。`templates/` はコア層で git 管理下にあるため、原本に会社情報・売上・投資額を書くと作業 repo にコミットされ（このキットは「機密は `input/` に置く」前提です）、`update-core` でも恒久的に user-modified 扱いになって以後の上流改善を受け取れなくなります。次のように `input/` へコピーしてから記入してもらいます。

   ```bash
   cp templates/intake-questionnaire.md input/intake-questionnaire.md
   ```

   - `input/intake-questionnaire.md` が記入済みなら、その内容を読み取って不足分だけ質問してください。
   - すでに原本 `templates/intake-questionnaire.md` に記入されている場合は、先に内容を `input/intake-questionnaire.md` へ退避し、そのうえで**原本を記入前の版から index と worktree の両方に戻して**から進めてください。`git checkout -- <path>`（コミット指定なし）は index の内容を worktree に書き戻すだけなので、`git add` 済みの記入内容が index に残り、次の commit に載ります。必ずコミットを指定して戻します。

     ```bash
     git log --oneline -- templates/intake-questionnaire.md   # 記入内容が commit されているか確認する
     git checkout HEAD -- templates/intake-questionnaire.md   # 未コミット（git add 済みを含む）なら index と worktree を HEAD の内容へ戻す
     ```

   - 記入内容がすでに commit されている場合は `HEAD` にも機密が入っているため、上のコマンドでは戻せません。`git log --oneline -- templates/intake-questionnaire.md` で記入前の commit を特定し、`git checkout <記入前のcommit> -- templates/intake-questionnaire.md` で戻してください。そのうえで、**機密が commit 履歴に残り続けること**を利用者本人に伝え、この repo が private であることの確認（必要なら履歴の作り直し）を案内してください。以後の記入は必ず `input/` 側で扱います。
6. 既存の `input/company-profile.md`、`input/company-profile.json` がある場合は、上書きまたは更新の前に顧客へ確認してください。`input/current-application.json` は初期化し直さず、対象補助金と spec 情報を保って更新します。

## ヒアリング手順

以下の順に質問してください。一度に大量の質問を出さず、回答しやすい単位に分けて進めてください。不明な点は推測で補わず、`[要確認]` として残してください。

### 0. spec 駆動の優先確認

`current-application.spec_path` を入口に、解決順で選んだ confirmed spec を読み込み、会社情報として優先的に聞くべき項目を先に抽出してください。

predicate が参照するキーは spec を目視で走査せず、次のコマンドで機械的に列挙してください。spec を読み違えてキー名を作ってしまうと、`/subsidy-fit` の predicate 評価が恒常的に `unknown` になります。

```bash
bash tools/check-spec.sh <解決済みspec> --list-predicate-keys
```

出力は JSON で、`keys[]` の各要素が `scope`（`profile` は `input/company-profile.json`、`application` は `input/current-application.json` を参照）、`key`、`type`、`unit`、`description`、`referenced_by`（参照元の rule / deliverable）、`confirm_phase`（`intake` はこのコマンドで聞く項目、`plan-deliverables` は枠選択後に決まる項目）を持ちます。

- `confirm_phase` に `intake` を含む `scope=profile` のキーを、このコマンドの優先確認対象にします。`key` の名前は変えず、別名を作らないでください。`key` がドット区切り（例 `custom_metrics.score`）の場合は、`"custom_metrics.score"` というトップレベルのキーにせず、`{"custom_metrics": {"score": ...}}` のようにネストしたオブジェクトへ展開して保存します。評価器はドットをネストの区切りとして辿るため、トップレベルに平置きすると値を入れても判定が恒常的に `unknown` になります
- `declared` が `false` のキーは `schemas/company-profile.schema.json` に宣言が無い拡張項目です。`check-spec` 実行時に `predicate references undeclared profile key` の WARN も出ます。勝手に近い名前の既存キーへ寄せず、spec の記述どおりのキーで値を保持し、`[要確認]` として残してください
- `confirm_phase` が `plan-deliverables` だけのキー（`chosen_funding` 配下など）は、このコマンドでは聞きません。`/subsidy-fit` の枠選択で決まります

コマンドが実行できない場合（Python 3 が見つからない等）は「未実行」であり、目視の走査で代替したことにしないでください。環境不備として `/setup` の環境セルフチェックへ戻してください。

コマンドで拾えない次の項目は、spec を読んで補ってください。

- `kind=scoring` の rule が要求する証憑、認定、計画、実績
- `bonus_items[]` の `evidence_needed`
- `funding.add_ons[]` の `required_rules` が参照する profile 項目
- `deliverables[].sections[].guidance` や `review_criteria` が求める会社事実

抽出した項目を「この補助金で先に確認する会社情報」として顧客に見せ、`input/company-profile.json` のどのキーに入れるかを示してから質問してください。spec 駆動ヒアリングでは、`industry_class`、`employees`、`certifications`、`plans`、`concurrent_applications`、`past_adoption_unreported` など、predicate 評価に使うキーを優先します。その後で、基礎的な会社プロフィールを埋めます。

spec が `chusho_kihonho_class` を参照している場合だけ、中小企業基本法の業種区分を追加で確認してください。質問では「製造業その他・卸売業・小売業・サービス業のどれに当たるか」と「その区分に対して、募集要項が定める資本金・従業員数のしきい値の組合せを、自社資料で確認できるか」を分けて聞きます。判断できない場合は JSON を `null` にし、Markdown 側へ `[要確認]` と根拠資料名を残します。

#### 実値と有界事実の記録

「上限以下であることだけ確認済み」のような有界事実と、確認できた実値を分けて記録してください。

- **実値が不明なら数値キーは `null`** とし、上限確認だけで境界値を代入しないでください。たとえば「15 億円以下」と確認できても、実額が不明な `taxable_income_avg_3y` に `15` を入れません。
- 有界事実は別の boolean 拡張キーで表します。例の `taxable_income_avg_3y_lte_15` は「確定している（申告済みの）直近過去3年分の各年または各事業年度の課税所得の年平均額（単位: 億円）が 15 以下」という命題です。これは記録例であり、全制度共通の必須キーではありません。募集要項に合わせて対象期間・単位・比較条件を定義し、キー名だけから推定しないでください。
- boolean の `true` は命題を確認済み、`false` は反対の事実を確認済み、`null` は未確認です。この例の `false` は「15 億円を超えることを確認済み」を意味します。未確認を `false` にしないでください。
- **以下（`lte`）と未満（`lt`）を区別**してください。境界値ちょうどは「以下」には含み、「未満」には含みません。「15 億円以下」しか確認できない場合、「15 億円未満」は `null` のままです。
- `input/company-profile.md` の「根拠資料」に、キーごとに命題全文、比較演算子・境界値、単位、対象期間（対象年度・事業年度と起算点）、出典（募集要項の条文・ページと、事実を裏付ける資料名・該当箇所または顧客回答・回答日）、確認日を記録します。定義・出典が不足する命題は boolean も `null` とし、実値の不足と分けて `[要確認]` に残してください。
- 拡張キーは `--list-predicate-keys` で `declared=false` となる場合があります。未宣言キーの WARN は定義・出典を確認するための注意として扱い、既存キーへの改名や `false` への変換で消さないでください。spec がそのキーを `op=eq`・`value=true` の boolean predicate として明示的に参照するときだけ、その命題を機械照合に使います。
- **既存の数値条件は、実値が `null` なら `unknown` を維持**します。拡張キーが `true` でも、既存の条件式を自動で置換しないでください。機械照合の条件式（predicate）は明示されたキーだけを参照し、`*_max` の自動解釈や区間演算も行いません。

### 1. 事業者プロフィール

- 会社名または屋号
- 所在地
- 代表者または担当者
- 法人格または事業形態（株式会社、合同会社、個人事業主など）
- 創業年月、設立年月、沿革
- 業種、主な商品・サービス
- 小規模事業者判定に使う `industry_class`（商業・サービス業、宿泊・娯楽、製造業その他のいずれに近いか。不明なら `[要確認]`）
- spec が参照する場合のみ、中小企業基本法系の `chusho_kihonho_class`（製造業その他、卸売業、小売業、サービス業のいずれか）と、募集要項上の資本金・従業員数しきい値に対する根拠資料
- 主な顧客層、商圏、販売チャネル
- 従業員数、売上規模、主要な設備や拠点
- 資本金、直近 3 年の課税所得平均、過去の同種補助金採択歴、未報告の採択案件、同時申請中の補助金
- 取得済み認定、加点に関係しそうな計画や予定

### 2. 事業概要と強み

- 現在の事業概要
- 既存顧客に提供している価値
- 競合と比べた強み
- 技術、ノウハウ、取引先、地域性などの根拠
- 直近の実績や顧客からの反応

### 3. 現状課題

- 売上、利益、生産性、人手、設備、販路、集客、品質、業務効率などの課題
- 課題が起きている背景
- 課題を放置した場合の影響
- 課題を示す数値や事実
- 補助事業で解決したい優先課題

### 4. 投資計画

- 導入したい設備、システム、サービス、外注、広告、開発など
- 投資の目的
- 概算金額、見積書の有無、支払時期
- 補助対象になりそうな経費区分
- 実施スケジュール
- 社内体制、担当者、外部協力先

### 5. 効果と数値根拠

- 投資後に期待する売上、利益、生産性、客数、単価、作業時間、品質、雇用などの効果
- 効果見込みの根拠となる既存実績、見積、商談、試算
- KPI と測定方法
- いつまでに効果を確認するか
- 根拠が不足している数値

### 6. 選択済み補助金の spec エコー

- `current-application.json` の `subsidy_id`
- `spec_path`
- spec の `name`、`round`、`spec_version`
- spec の `source_documents[]`
- 会社プロフィールで優先確認した `eligibility.rules[]` と `source_clauses`
- scoring や加点要素のために必要な証憑、認定、計画
- まだ `input/company-profile.json` で `null` にするしかない項目

ここでは補助金を新しく探したり、分野を推測したりしません。対象補助金はすでに `/select-subsidy` または `/ingest-guidelines` で確定済みです。顧客本人が確認すべき不足情報だけを `[要確認]` として残してください。

## 出力先

ヒアリング後、`input/company-profile.md` と `input/company-profile.json` を作成または更新してください。既存ファイルがある場合は、上書き前に顧客へ確認してください。

`input/company-profile.md` は以下の構成で整理してください。既存の見出し構成は維持し、JSON 側で `null` にした未確認項目は Markdown 側の本文または `[要確認] リスト` に必ず残してください。

```markdown
# company-profile

## 作成メモ

- 作成者: 顧客本人
- AIの役割: 顧客回答の整理と不足点の明示
- 未確認事項: `[要確認]` を参照

## 事業者プロフィール

## 事業概要

## 沿革

## 商品・サービス

## 顧客・市場・商圏

## 強み・差別化要素

## 従業員・売上規模

## 現状課題

## 投資計画

## 実施体制

## 期待効果・KPI

## 選択済み補助金の spec エコー

## 根拠資料

## [要確認] リスト
```

`input/company-profile.json` は `schemas/company-profile.schema.json` に従う機械照合の正本として、次のキーを必ず持たせてください。値が不明な場合は推測せず `null` にします。配列項目は、該当なしと顧客が確認した場合だけ空配列にし、未確認の場合は Markdown 側の `[要確認] リスト` に理由を残してください。

```json
{
  "entity_type": null,
  "industry_class": null,
  "chusho_kihonho_class": null,
  "employees": null,
  "capital": null,
  "region": null,
  "founded_year": null,
  "taxable_income_avg_3y": null,
  "is_subsidized_before": null,
  "past_adoption_unreported": null,
  "concurrent_applications": null,
  "certifications": null,
  "plans": null,
  "business_summary": null,
  "updated_at": "<ISO8601 日時（オフセット付き）>"
}
```

`updated_at` は、実行環境の現在時刻から生成してください（オフセットを `+09:00` などの固定値で書かないでください）。

```bash
python3 -c 'import datetime; print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))'
```

`industry_class` は、顧客回答と募集要項上の分類を後で照合するため、次のいずれかだけを入れてください。判断できない場合は `null` とし、`input/company-profile.md` に `[要確認]` を残します。

- `商業・サービス業`
- `宿泊・娯楽`
- `製造業その他`

`chusho_kihonho_class` は、中小企業基本法系の事業規模判定で `scope=profile` の predicate が参照する場合だけ確認します。入力できる値は `製造業その他`、`卸売業`、`小売業`、`サービス業` のいずれかです。`industry_class` と似た名称でも用途が違うため、募集要項の定義と資本金・従業員数のしきい値の組合せを照合できない場合は `null` とし、Markdown 側に `[要確認]` を残してください。

JSON 作成時は、従業員数、資本金、課税所得平均、創業年などを文字列にせず、スキーマ上の数値型または `null` として扱ってください。根拠資料が未確認の数値は JSON では `null`、Markdown では `[要確認]` にします。

最後に、既存の `input/current-application.json` を更新してください。このファイルは `/select-subsidy` または `/ingest-guidelines` が `state=spec_confirmed` で作成済みである前提です。`/intake` では新規初期化や補助金の選び直しをしません。

```json
{
  "subsidy_id": "<既存値を維持>",
  "spec_path": "<既存値を維持>",
  "spec_version": "<既存値を維持>",
  "chosen_funding": null,
  "state": "intake_done",
  "updated_at": "<ISO8601 日時（オフセット付き）>"
}
```

こちらの `updated_at` も、実行環境の現在時刻から生成してください（オフセットを `+09:00` などの固定値で書かないでください）。

```bash
python3 -c 'import datetime; print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))'
```

`current-application.json` は、後続コマンドが同じ申請案件を見ていることを確認する受け渡しファイルです。`/intake` 完了時点では対象補助金と spec は確定済みなので、`subsidy_id`、`spec_path`、`spec_version` を変更せず、会社プロフィール作成が済んだことを `state=intake_done` で記録してください。

## 出力時の注意

- 顧客が回答した事実と、AIが整理した解釈を混同しないでください。
- `input/company-profile.json` は機械照合の正本、`input/company-profile.md` は人間可読ビューです。片方だけを更新せず、同じ内容に同期してください。
- JSON で `null` にした未確認項目は、Markdown 側に `[要確認]` として残してください。
- 数値には、回答、資料名、見積書名、募集要項名などの根拠を添えてください。
- 根拠のない数値や断定は避け、必要なら `[要確認]` を付けてください。
- 補助金名、補助率、補助上限、対象経費、提出期限は、公式の募集要項で確認できるまで断定しないでください。
- 最後に `input/company-profile.md`、`input/company-profile.json`、`input/current-application.json` を作成または更新したことを示し、「次は `/subsidy-fit` で confirmed spec と会社プロフィールを照合する」ことを案内してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断は行いません。入力は顧客の実情報、AIは整理のみです。`input/` は顧客の機密情報を置く場所なので、公開リポジトリへコミットしないでください。
