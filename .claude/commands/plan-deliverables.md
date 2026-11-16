---
description: 確認済み spec と current-application から input/deliverables.md を再生成し、AI成果物・人の作業・添付・締切を整理します。
---

# /plan-deliverables

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

**現在地の表示**: preflight の直後に `bash tools/progress.sh show --phase begin --command plan-deliverables` を実行し、出力の 1 行をそのまま示してください。このコマンドの作業を終えるとき（ゲートで止まる場合・本人の確認待ちで終える場合を含む）は `bash tools/progress.sh show --phase end --command plan-deliverables` を実行し、出力の全行をそのまま示してください。言い換え・要約はしません（CLAUDE.md の「現在地の表示」）。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する、成果物計画の整理役です。確認済みの subsidy spec と `input/current-application.json` を読み、申請に向けて「何を AI と作るか」「顧客本人が何を準備するか」「添付物は何か」「締切はいつか」を `input/deliverables.md` にまとめてください。

このコマンドの目的は、後続の `/draft-section`、`/review`、`/verify`、`/finalize` が同じ成果物一覧を参照できるようにすることです。申請書本文を完成させたり、提出判断を代わりに行ったりしません。

## 使う場面

- `/subsidy-fit` で対象補助金との適合を確認し、狙う枠の決定内容または特例の未決定事項を記録した後
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
   - `state=intake_done` の場合は、適合確認が未完了です。先に `/subsidy-fit` を実行し、`state=fit_done` にしてください。
3. `spec_path` が non-null で、実在する confirmed spec を指していること。
   - `spec_path` が null、またはファイルが存在しない場合は、公式募集要項から `/ingest-guidelines` で作るか、同梱 `specs/` を `/select-subsidy` で選び直してください。
4. `state` が `fit_done` 以降であれば、`chosen_funding` が `null` の場合も特例が未決定の状態として進めます。
   - 未決定事項の記録と確定期限は `/subsidy-fit` の「狙う枠を選ぶ」に従ってください。
5. spec の `status` が `confirmed` であること。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
   - `status=draft` の spec は使わないでください。confirmation report で原本突合を済ませてから進めます。
6. `spec_path` が指すファイルに対して `bash tools/check-spec.sh` を必ず実行し、**終了コードが 0**（green）であることを確認してください。
   - FAIL が出た場合は、成果物計画へ進まず、spec または confirmation の不整合を直してください。
   - コマンド自体を実行できなかった場合（Python 3 が見つからない等）は「未実行」であり、green と同一視しないでください。`input/current-application.json` を書き換えず、環境不備として `/setup` の環境セルフチェックへ戻してください。

`input/current-application.json` と spec の `subsidy_id`、`spec_version` が食い違う場合は止めてください。同じ補助金・同じ spec 版を見ていることが、このコマンドの前提です。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で最初に見つかったものに解決してください。

1. 利用者側 spec: `input/spec/` のパック形（`pack.json` の `spec.path` が指す spec）、なければ平置き `input/spec/<subsidy_id>.json`
2. 同梱 spec: `bash tools/check-spec.sh --list-bundled` の出力から `subsidy_id` が一致する spec パス（パック優先・重複 ID の FAIL・安定ソートを機械側で保証）

同梱 spec の候補を `specs/` の目視や推測で選ばないでください。`--list-bundled` が失敗した場合（重複 `subsidy_id` 等）は、エラー内容を顧客に示して停止してください。

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が旧同梱平置きパス（例: `specs/<subsidy_id>.json`）を指し、同一 subsidy_id のパック形が上記の解決結果に存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。

## 読み取る情報

次の情報だけを根拠にしてください。

- `input/current-application.json`
- `spec_path` が指す confirmed spec
- 必要に応じて、required_if の評価に使う `input/company-profile.json` または `input/company-profile.md`

ブログ、過去公募の記憶、一般論、AI の推測で成果物や締切を足さないでください。制度上の事実は spec と、その `source_clauses` が参照する募集要項の条文に基づけます。

### 成果物の判定前に聞くこと

`bash tools/check-spec.sh <解決済みspec> --list-predicate-keys` を実行し、成功した出力の `keys[]` で `confirm_phase` に `plan-deliverables` を含む `scope=profile` のキー（計画づくりの支援者の有無、融資の利用、加点の希望など）を本人に質問してください。回答を spec のキー名のまま `input/company-profile.json` と `input/company-profile.md` に記録し、ドット区切りのキーや根拠の記録は `/intake` の規律に従い、未定の答えは `null` のまま Markdown に `[要確認]` を残します。`bash tools/check-profile.sh input/company-profile.json` の終了コード 0 を確認してから `required_if` を評価し、列挙・検査が未実行または失敗なら判定を止めてください。`scope=application` の枠選択は `/subsidy-fit` に従い、会社情報へ転記しません。

## required_if の扱い

まず次を実行し、終了コード 0 と出力ファイルを確認してください。1 は spec 未確定・検査不合格、2 は入力エラーです。失敗時は state を更新せず、原因を解消します。

```bash
bash tools/build-deliverables.sh
```

道具が resolver で spec を解決し、check-spec、application binding、predicate.py の三値評価を実行します。AI が成果物ごとに CLI を呼んだり、表を手で組み立てたりする手順は不要です。`due_event_id` が null の期限は「期限未設定 [要確認]: 公式の公募要領で確認」です。条文から補完せず、参照切れは入力エラーで止めます。

生成された一覧の行は書き換えないでください。条件付き成果物の該当、UNKNOWN の解消に必要な回答、[要確認] の確認先と確認結果を本人と確かめ、本人メモは `input/deliverables-notes.md` に書いてください。このメモは道具が作成・削除しません。回答をプロフィールや枠選択へ反映したら再実行してください。

以下の振り分け・生成内容・出力形式は道具の出力を確認するための契約です。AI による一覧の編集手順ではありません。条件文は要約、言い換え、条件の追加をしないでください。

`required`（boolean・必須キー）と `required_if`（述語・省略可・null 可）の組み合わせで、次の表のとおり振り分けます。表のどの行にも当てはまらない組み合わせを、自分の判断で別の行に寄せないでください。

| `required` | `required_if` の評価 | 振り分け | 表示 |
| --- | --- | --- | --- |
| true | null または未設定 | 今回の必須成果物 | 通常表示 |
| true / false | true | 今回の必須成果物 | 通常表示 |
| true / false | false | 今回の狙いでは対象外 | 「対象外候補」に必ず残す（該当なし・判定 FALSE） |
| true / false | unknown | 提出漏れを避けるため必ず含める | 評価欄に `[要確認]` |
| false | null または未設定 | 条件付き成果物（下記） | 「条件付き（該当する場合のみ提出）」に `[要確認]` 付きで並べる |

述語の `scope=application` は `input/current-application.json` から読みます。たとえば `chosen_funding.base`、`chosen_funding.addon_ids` を参照します。`scope=profile` が含まれる場合は会社プロフィールを確認し、値が欠けていれば unknown としてください。unknown を都合よく false にしないでください。

`chosen_funding` が `null` のとき、それを `scope=application` で参照する `required_if` は `unknown` です。複合条件は既存の三値評価結果に従い、`false` に読み替えないでください。特例の未決定により `unknown` になった成果物とそのセクションは、`input/deliverables.md` の「required_if が [要確認] の項目」内に「特例を使う場合に必要になるもの `[要確認]`」として表示され、通常の成果物一覧から参照できることを確認します。特例を決めたら `/subsidy-fit` → `/plan-deliverables` をやり直すことも記載してください。

### `required=false` かつ `required_if` が null/未設定 の成果物（条件が自然文にしかない）

「該当事業者のみ」「特例申請者のみ」「グローバル枠のみ」のように、提出の条件が成果物名の括弧書きや `source_clauses` が指す条文の日本語にしか書かれていない成果物です。述語がないので機械評価できません。unknown（述語を評価しようとして参照値が欠けた状態）とは別物なので、unknown と同じ扱いにしないでください。

1. 今回の必須成果物には入れません。`required=false` は「全員が出すものではない」という spec 側の事実です。
2. 道具が `input/deliverables.md` の「条件付き（該当する場合のみ提出）」節に全件を並べ、各成果物について `deliverable_id`、成果物名、`produced_by`、`issuer`、`due_event_id` とその期限、`format`、`upload_target`、`source_clauses` を表示したことを確認します。
3. 条件の自然文は、成果物名の括弧書きと `source_clauses` が指す条文の原文が表示されていることを確認します。要約、言い換え、条件の追加をしないでください（例:「該当事業者のみ」を「再生支援を受けている場合」と書き換えない）。
4. 該当するかどうかを AI が判定しません。全件の `[要確認]` を確認し、顧客本人が該当有無を答える項目として提示します。
5. `/finalize` の提出前チェックリストで1件ずつ該当有無を確認する対象になる旨を、道具の出力に明記されていることを確認します。条件付き成果物は提出漏れが起きやすい箇所です。

### spec 側への推奨（`required_if` 化）

条件付き成果物のうち、申請者の属性か今回の申請内容から決まる条件は、spec 側で `required_if` の述語にできます。`/plan-deliverables` の実行中に spec を書き換えることはしません。条件付き成果物を出力したときに、次の切り分けを添えて `/ingest-guidelines` 側での `required_if` 化を推奨してください。

| 条件の出どころ | 例 | `required_if` 化 |
| --- | --- | --- |
| 会社プロフィール（`scope=profile`） | 従業員数、所在地、業種による該当 | できる（推奨） |
| 今回の申請内容（`scope=application`） | 枠・加算・特例の選択（`chosen_funding.base` / `chosen_funding.addon_ids`）、資金調達の方法 | できる（推奨） |
| 審査側や第三者の判断で事後に決まる | 「一定の基準を満たした事業者が対象」（口頭審査の対象化など） | できない。条件付きのまま自然文で残す |

述語で表せない条件を無理に `required_if` へ落とし込まないでください。参照値が欠けている・null であるだけなら評価は unknown になり、上の表のとおり `[要確認]` 付きで必ず含まれます。危ないのはその手前で、表せない条件を代理のキーに置き換えて述語にしてしまうことです。代理のキーは評価できてしまうので、誤った true / false が確定値として出て、`[要確認]` にも条件付きにも載らなくなります。表せないものを条件付きのまま残すのが正しい状態です。

## 生成する内容

`input/deliverables.md` は REGENERABLE VIEW です。正本は spec と `input/current-application.json` であり、この Markdown は何度でも再生成できる一覧です。ファイル冒頭に、次の趣旨があることを確認してください。

- このファイルは auto-generated / 再生成可能なビューである。
- 手動の進捗チェック、消し込み、最終確認は `/finalize` の提出前チェックリストで行う。
- 書き足しは `input/deliverables-notes.md` に保存し、一覧の行は書き換えない。

道具の出力を次の観点で本人と確認してください。

- AIと作る成果物: `produced_by=ai_draftable` の成果物と `sections[]` の字数・ページ上限を確認します。null は未制限とせず、募集要項・様式の確認先をメモします。
- 人がやることリスト: type=procedure、`produced_by=human_only` / `produced_by=external` の作業を確認します。外部発行書類の発行主体（issuer）、依頼期限、受領後の提出先を本人と確認し、回答はメモへ残します。
- 添付チェックリスト: `type=attachment` の format・upload_target・evidence_needed を確認します。null の指定は募集要項・申請システムで確認します。
- 締切カレンダー: schedule 全件の date・starts_at・ends_at・time・timezone・hard flag と source_clauses を確認します。`relative` 列は共通関数 `relative_deadline_text(event)` の表示文（例:「交付決定日から14か月以内」）で示し、日付に換算しません。null は従来どおり `[要確認]` と確認先を表示します。基準になる日が決まった後に、公式の案内で日付を確認します。hard=true の期限は本人に明示します。
- 条件付き（該当する場合のみ提出）: 自然文だけの条件を本人に1件ずつ確認し、/finalize へ引き継ぎます。`type` と `phase` の表示を必ず確認し、申請フェーズと採択後を混同しません。
- 不足・食い違いがあれば一覧を手直しせず、根拠と確認先をメモへ書き、spec の修正・再突合後に道具を再実行します。

## 出力形式

`input/deliverables.md` が次の見出しと項目を含むことを確認してください。道具は人の作業・添付にも成果物の共通列を表示し、phase ごとに分けます。

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

## 条件付き（該当する場合のみ提出）

| deliverable_id | 成果物名 | 条件（原文のまま） | type | phase | produced_by | issuer | due_event_id | 期限 | format | upload_target | source_clauses | 該当 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## 対象外候補

## 次に実行するコマンド

`/draft-section`
```

空欄を残さず、該当値がない場合は `null`、`該当なし`、または `[要確認]` のいずれかで表現してください。根拠がない事実を補わないでください。

## current-application の更新

道具の終了コード 0 と `input/deliverables.md` の生成を確認したら、`input/current-application.json` を更新してください。

- `state` を `planned` にする。
- `updated_at` を現在時刻に更新する。
- `subsidy_id`、`spec_path`、`spec_version`、`chosen_funding` は、確認なしに別の値へ変えない。
- 生成した manifest のパスを記録するフィールドを追加できる場合は、`deliverables_path: "input/deliverables.md"` を追加する。

すでに `state=drafting`、`state=verified`、`state=finalized` だった場合でも、deliverables view の再生成により後続成果物の前提が変わる可能性があります。`state=planned` に戻したうえで、顧客に `/draft-section` 以降を再確認する必要があると明示してください。

## 出力時の注意

- `input/deliverables.md` は再生成可能なビューです。ここに手で進捗チェックを付けさせないでください。
- 手動の消し込み、添付確認、提出前確認は `/finalize` の提出前チェックリストで扱います。
- spec にない成果物、締切、添付資料、外部発行書類を追加しないでください。
- `required_if` が unknown の成果物が、提出漏れ防止のため `[要確認]` 付きで含まれていることを確認してください。
- `required=false` かつ `required_if` が null/未設定 の成果物は、「条件付き（該当する場合のみ提出）」に全件が並び、条件の自然文と `[要確認]` があることを確認してください。該当有無を AI が判定しないでください。
- 期限は募集要項が正です。spec と募集要項が食い違う疑いがあれば、公式募集要項を確認するよう案内してください。
- 出力先は `input/`（育成層）のみです。コア層のファイルを変更しないでください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/plan-deliverables` は confirmed spec と `current-application.json` から成果物、作業、添付、締切を整理するだけです。数値は推測しないでください。出典不明の事実、原本で確認できない締切、添付条件、字数、対象枠には `[要確認]` を付けてください。要件・数値は募集要項が正であり、最終的な確認と提出判断は顧客本人が行います。
