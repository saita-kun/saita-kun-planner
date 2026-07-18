---
description: 確認済み spec と current-application から input/deliverables.md を再生成し、AI成果物・人の作業・添付・締切を整理します。
---

# /plan-deliverables

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する、成果物計画の整理役です。確認済みの subsidy spec と `input/current-application.json` を読み、申請に向けて「何を AI と作るか」「顧客本人が何を準備するか」「添付物は何か」「締切はいつか」を `input/deliverables.md` にまとめてください。

このコマンドの目的は、後続の `/draft-section`、`/review`、`/verify`、`/finalize` が同じ成果物一覧を参照できるようにすることです。申請書本文を完成させたり、提出判断を代わりに行ったりしません。

## 使う場面

- `/subsidy-fit` で対象補助金との適合を確認し、狙う枠を `chosen_funding` に記録した後
- confirmed spec の `deliverables[]` と `schedule[]` から、作るもの・人がやること・添付・締切を一覧化したいとき
- 事業計画書の各セクションを `/draft-section` で作り始める前に、成果物全体を固定したいとき
- spec や `chosen_funding` を更新したため、`input/deliverables.md` を再生成したいとき

出力はすべて `input/`（育成層）に置いてください。`.claude/commands/`、`schemas/`、`specs/`、`tools/` などのコア層は書き換えないでください。

## 前提チェック

最初に、次の条件を順番に確認してください。条件を満たさない場合は `input/deliverables.md` を作らず、該当する先行コマンドへ案内します。

1. `input/current-application.json` が存在すること。
   - 存在しない場合は、対象補助金の spec が未確定です。同梱 spec を使うなら `/select-subsidy`、顧客本人の募集要項から作るなら `/ingest-guidelines` を先に実行し、その後 `/intake` と `/subsidy-fit` を済ませてください。
2. `input/current-application.json` の `state` が `fit_done`、`planned`、`drafting`、`verified`、`finalized` のいずれかであること。
   - `state=spec_draft` の場合は「突合が未完了です。/confirm-spec を実行してください」と案内し、成果物計画を作らないでください。
   - `state=spec_confirmed` の場合は、会社情報ヒアリングが未完了です。先に `/intake` を実行し、`state=intake_done` にしてください。
   - `state=intake_done` の場合は、適合確認と狙う枠の選択が未完了です。先に `/subsidy-fit` を実行し、`chosen_funding` を決めてください。
3. `spec_path` が non-null で、実在する confirmed spec を指していること。
   - `spec_path` が null、またはファイルが存在しない場合は、公式募集要項から `/ingest-guidelines` で作るか、同梱 `specs/` を `/select-subsidy` で選び直してください。
4. `chosen_funding` が non-null であること。
   - `chosen_funding` が null の場合は、今回どの枠・上乗せを狙うか未決定です。`/subsidy-fit` へ戻ってください。
5. spec の `status` が `confirmed` であること。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
   - `status=draft` の spec は使わないでください。confirmation report で原本突合を済ませてから進めます。
6. 可能なら、`spec_path` が指すファイルに対して `bash tools/check-spec.sh` を実行し、green であることを確認してください。
   - FAIL が出た場合は、成果物計画へ進まず、spec または confirmation の不整合を直してください。

`input/current-application.json` と spec の `subsidy_id`、`spec_version` が食い違う場合は止めてください。同じ補助金・同じ spec 版を見ていることが、このコマンドの前提です。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で解決してください。

1. `input/spec/<subsidy_id>/<subsidy_id>.json`
2. `input/spec/<subsidy_id>.json`
3. `specs/<subsidy_id>/<subsidy_id>.json`
4. `specs/<subsidy_id>.json`

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。

## 読み取る情報

次の情報だけを根拠にしてください。

- `input/current-application.json`
- `spec_path` が指す confirmed spec
- 必要に応じて、required_if の評価に使う `input/company-profile.json` または `input/company-profile.md`

ブログ、過去公募の記憶、一般論、AI の推測で成果物や締切を足さないでください。制度上の事実は spec と、その `source_clauses` が参照する募集要項の条文に基づけます。

## required_if の扱い

`deliverables[]` の `required_if` は、`chosen_funding` を含む `input/current-application.json` を使って評価してください。

- `required_if=null` かつ `required=true` の成果物は、今回の必須成果物として含めます。
- `required_if` が true の成果物は、今回の必須成果物として含めます。
- `required_if` が false の成果物は、今回の狙いでは対象外として扱います。ただし、顧客が確認しやすいように「対象外候補」に短く残しても構いません。
- `required_if` が unknown の成果物は、提出漏れを避けるため必ず含め、項目名と理由に `[要確認]` を付けてください。

述語の `scope=application` は `input/current-application.json` から読みます。たとえば `chosen_funding.base`、`chosen_funding.addon_ids` を参照します。`scope=profile` が含まれる場合は会社プロフィールを確認し、値が欠けていれば unknown としてください。unknown を都合よく false にしないでください。

## 生成する内容

`input/deliverables.md` は REGENERABLE VIEW です。正本は spec と `input/current-application.json` であり、この Markdown は何度でも再生成できる一覧です。ファイル冒頭に、次の趣旨を明記してください。

- このファイルは auto-generated / 再生成可能なビューである。
- 手動の進捗チェック、消し込み、最終確認は `/finalize` の提出前チェックリストで行う。
- このファイルに手で進捗チェックを付けても、正本は更新されない。

### 1. AIと作る成果物

spec の `deliverables[]` から `produced_by=ai_draftable` の成果物を抽出し、成果物単位でまとめてください。

各成果物には、少なくとも次を表示します。

- `deliverable_id`
- 成果物名
- `type`
- `phase`
- `format`
- `upload_target`
- `due_event_id` と、その `schedule[]` 上の日付または相対期限
- `required` / `required_if` の評価結果
- `source_clauses`

その下に `sections[]` を並べ、各セクションについて次を表示してください。

- `section_id`
- セクション名
- `kind`
- `max_chars`
- `max_pages`
- `guidance`
- `review_criteria`
- `source_clauses`

`max_chars` や `max_pages` が null の場合は、未制限と断定せず「spec 上は null。募集要項・様式側の指定を再確認」と書き、必要なら `[要確認]` を付けてください。

### 2. 人がやることリスト

type=procedure、または `produced_by=human_only` / `produced_by=external` の成果物を、人がやることリストとしてまとめてください。`type=attachment` のものは後続の添付チェックリストにも出します。

各項目には、少なくとも次を表示します。

- `deliverable_id`
- 作業名
- `type`
- `produced_by`
- `issuer`
- `format`
- `due_event_id`
- `due_event_id` に対応する `schedule[]` の日付、時刻、timezone、hard flag
- `depends_on`
- `evidence_needed`
- `source_clauses`

`issuer` が null の場合は「顧客本人が準備」と表示します。`produced_by=external` の場合は、発行主体、依頼期限、受領後の提出先を分けてください。外部発行書類を AI が作れる成果物のように扱わないでください。

### 3. 添付チェックリスト

`type=attachment` の成果物を、添付チェックリストとしてまとめてください。

各添付物には、少なくとも次を表示します。

- `deliverable_id`
- 添付名
- `format`
- `upload_target`
- `due_event_id`
- 期限の日付または相対期限
- `produced_by`
- `issuer`
- `evidence_needed`
- `source_clauses`

`format` または `upload_target` が null の場合は、空欄のままにせず「spec 上は null。募集要項・申請システムで確認」と書き、`[要確認]` を付けてください。

### 4. 締切カレンダー

spec の `schedule[]` 全件を、可能な限り日付順に並べてください。

各イベントには、少なくとも次を表示します。

- `event_id`
- イベント名
- `event_kind`
- `phase`
- `date`
- `starts_at`
- `ends_at`
- `time`
- `timezone`
- `hard` flag
- `relative`
- `source_clauses`

並べ方は次の通りです。

1. `date` があるイベントを日付順に並べる。
2. `starts_at` または `ends_at` だけがあるイベントは、その日付で並べる。
3. `relative` だけのイベントは、具体日付が未確定のため、日付ありイベントの後に置き、`anchor` と `offset_days` と `direction` を表示する。
4. `hard=true` は「失権・提出不可につながる可能性がある硬い期限」として明示する。
5. `hard=false` でも軽視せず、根拠条文を示す。

相対期限は具体日付に変換しないでください。交付決定日など anchor が未確定の場合は、「anchor 確定後に再計算」と書き、必要なら `[要確認]` を付けます。

## 出力形式

`input/deliverables.md` は、次の構成で作成してください。

```markdown
# 成果物マニフェスト

## 作成メモ

- このファイルは auto-generated / 再生成可能なビューです。
- 正本: spec と input/current-application.json
- 手動の進捗チェック: /finalize の提出前チェックリストで行う
- 作成者: 顧客本人
- AIの役割: 成果物、作業、添付、締切の整理
- 未確認事項: [要確認] を参照

## 対象申請

| 項目 | 内容 |
| --- | --- |
| subsidy_id |  |
| spec_path |  |
| spec_version |  |
| chosen_funding |  |
| state_before |  |

## AIと作る成果物

### 成果物: 

| 項目 | 内容 |
| --- | --- |
| deliverable_id |  |
| type |  |
| phase |  |
| format |  |
| upload_target |  |
| due_event_id |  |
| 期限 |  |
| required_if 評価 |  |
| source_clauses |  |

#### sections

| section_id | name | kind | max_chars | max_pages | guidance | review_criteria | source_clauses |
| --- | --- | --- | --- | --- | --- | --- | --- |

## 人がやることリスト

| deliverable_id | 作業名 | type | produced_by | issuer | due_event_id | 期限 | hard | format | depends_on | evidence_needed | source_clauses |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## 添付チェックリスト

| deliverable_id | 添付名 | format | upload_target | due_event_id | 期限 | produced_by | issuer | evidence_needed | source_clauses |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## 締切カレンダー

| event_id | name | event_kind | phase | date | starts_at | ends_at | relative | time | timezone | hard | source_clauses |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## required_if が [要確認] の項目

## 対象外候補

## 次に実行するコマンド

`/draft-section`
```

空欄を残さず、該当値がない場合は `null`、`該当なし`、または `[要確認]` のいずれかで表現してください。根拠がない事実を補わないでください。

## current-application の更新

`input/deliverables.md` を作成または再生成したら、`input/current-application.json` を更新してください。

- `state` を `planned` にする。
- `updated_at` を現在時刻に更新する。
- `subsidy_id`、`spec_path`、`spec_version`、`chosen_funding` は、確認なしに別の値へ変えない。
- 生成した manifest のパスを記録するフィールドを追加できる場合は、`deliverables_path: "input/deliverables.md"` を追加する。

すでに `state=drafting`、`state=verified`、`state=finalized` だった場合でも、deliverables view の再生成により後続成果物の前提が変わる可能性があります。`state=planned` に戻したうえで、顧客に `/draft-section` 以降を再確認する必要があると明示してください。

## 出力時の注意

- `input/deliverables.md` は再生成可能なビューです。ここに手で進捗チェックを付けさせないでください。
- 手動の消し込み、添付確認、提出前確認は `/finalize` の提出前チェックリストで扱います。
- spec にない成果物、締切、添付資料、外部発行書類を追加しないでください。
- `required_if` が unknown の成果物は、提出漏れ防止のため含めて `[要確認]` としてください。
- 期限は募集要項が正です。spec と募集要項が食い違う疑いがあれば、公式募集要項を確認するよう案内してください。
- 出力先は `input/`（育成層）のみです。コア層のファイルを変更しないでください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/plan-deliverables` は confirmed spec と `current-application.json` から成果物、作業、添付、締切を整理するだけです。数値は推測しないでください。出典不明の事実、原本で確認できない締切、添付条件、字数、対象枠には `[要確認]` を付けてください。要件・数値は募集要項が正であり、最終的な確認と提出判断は顧客本人が行います。
