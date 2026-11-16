---
description: 最新 spec と draft に対する verify 全緑を確認し、成果物・人の作業・添付資料・期限の提出前チェックリストを作ります。
---

# /finalize

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

**現在地の表示**: preflight の直後に `bash tools/progress.sh show --phase begin --command finalize` を実行し、出力の 1 行をそのまま示してください。このコマンドの作業を終えるとき（ゲートで止まる場合・本人の確認待ちで終える場合を含む）は `bash tools/progress.sh show --phase end --command finalize` を実行し、出力の全行をそのまま示してください。言い換え・要約はしません（CLAUDE.md の「現在地の表示」）。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する最終確認の整理役です。`input/checks/verify-report.md`、`input/current-application.json`、`input/deliverables.md`、確認済み spec、`input/drafts/<subsidy_id>/` を照合し、最新 spec と最新 draft に対する機械検証が全緑であることを確認してから、提出前チェックリストを作ってください。

このコマンドは提出代行ではありません。申請書を官公署へ提出したり、提出可否を顧客本人に代わって確定したりしないでください。提出は顧客本人の責任・判断で行います。AI は、`/verify` の検証結果、募集要項、成果物一覧、顧客資料に照らした確認事項の整理、見出しや文字数などの体裁整え、様式、添付資料、期限、未確認事項の洗い出しだけを補助します。

## 使う場面

- `/draft-section` と `/review` を終え、`/verify` が全緑になった後
- `input/deliverables.md` の AI 成果物、人がやること、添付、hard 締切を、提出前に顧客本人が消し込みたいとき
- draft を編集していない最新状態で、提出直前の様式・添付・期限・作成主体を確認したいとき

出力先は `input/final-checklist.md` と `input/submission-summary.md` です。`input/current-application.json` の状態更新以外、`.claude/commands/`、`schemas/`、`specs/`、`tools/`、`docs/` などのコア層は書き換えないでください。

preflight を含む前提条件・鮮度確認・必須セクション・レビュー記録のゲートのどれかで停止した場合、提出用まとめを作成・更新しません。`input/submission-summary.md` が既にある場合は、本人に「古いまとめが残っている。使わないこと」と伝えてください。

## 最初に確認すること

最初に、次の前提を順番に確認してください。ひとつでも満たさない場合は `input/final-checklist.md` を作らず、止めて `/verify` または該当する先行コマンドへ戻るよう案内します。

1. `input/current-application.json` が存在すること。
   - 存在しない場合は、現在の申請案件が未初期化です。同梱 spec を使うなら `/select-subsidy`、顧客本人の募集要項から作るなら `/ingest-guidelines` からやり直してください。
2. `input/current-application.json` の `subsidy_id`、`spec_path`、`spec_version` が non-null であること。
   - 不足している場合は `/select-subsidy` または `/ingest-guidelines` に戻って、確認済み spec と対象補助金を確定してください。
3. `input/current-application.json` の `state` が `verified` または `finalized` であること。
   - `state=spec_draft` の場合は「突合が未完了です。/confirm-spec を実行してください」と案内し、提出前チェックを作らないでください。
   - `state=drafting`、`planned`、`fit_done` などの場合は、先に `/review` と `/verify` を実行してください。
4. `input/checks/verify-report.md` が存在し、ファイル冒頭の fenced json に `spec_check=green`、`draft_check=green`、`spec_path`、`spec_version`、`spec_sha256` が記録されていること。
   - report がない、json が読めない、どちらかが `fail` の場合は、このコマンドを止めて `/verify` を再実行してください。
5. `verify-report.md` の `spec_path` と `spec_version` が `input/current-application.json` と一致し、`spec_sha256` が現在の spec file bytes から再計算した SHA-256 と一致すること。さらに、現在の spec に対して `bash tools/check-spec.sh <spec_path>` を再実行し green であること。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
   - 不一致または `check-spec.sh` fail の場合は、spec または confirmation が `/verify` 後に更新されています。stale な検証結果では `/finalize` しないで、必ず `/verify` を再実行してください。
6. `input/checks/verify-report.md` の `draft_bodies_sha256` が、いまの `input/drafts/<subsidy_id>/` から再計算した draft 本文ハッシュと一致すること。さらに、下記「required_if 判定入力の鮮度確認」で `/verify` と同じ `--profile` / `--current-application` 引数に `--require-coverage` を追加した draft 検査を再実行し、green かつ `coverage_inputs_sha256` が report と一致すること。
   - 不一致なら、draft または `required_if` の判定入力が `/verify` 後に編集されています。ハッシュのない旧 report、ハッシュが不正な report、再検査 fail も失効扱いにします。古い coverage gaps を採用せず、`input/final-checklist.md` の作成・更新や `state=finalized` への更新を止め、必ず `/verify` を再実行してください。ただし必須 draft の欠落・draft 0 件の場合は、下記「required_if 判定入力の鮮度確認」の対応に従って停止してください。
7. `input/drafts/<subsidy_id>/` が存在し、少なくとも 1 つの `*.md` draft を含むこと。
   - draft が 0 件の場合、このキットで作った draft がないため `/finalize` は使えません。全セクションを本人が別に作る場合は、`/plan-deliverables` の一覧（`input/deliverables.md`）を提出前の確認に使うよう案内して止めてください。
8. `input/deliverables.md` が存在すること。
   - ない場合は `/plan-deliverables` を実行し、成果物マニフェストを作ってから戻ってください。

9. 作成者は顧客本人であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行わないことを明示してください。
10. `input/reviews/*.md` のうち同じ 1 件が、下記の `--review-record` 検査と `check-quotes.sh` の両方で exit 0 になること。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で最初に見つかったものに解決してください。

1. 利用者側 spec: `input/spec/` のパック形（`pack.json` の `spec.path` が指す spec）、なければ平置き `input/spec/<subsidy_id>.json`
2. 同梱 spec: `bash tools/check-spec.sh --list-bundled` の出力から `subsidy_id` が一致する spec パス（パック優先・重複 ID の FAIL・安定ソートを機械側で保証）

同梱 spec の候補を `specs/` の目視や推測で選ばないでください。`--list-bundled` が失敗した場合（重複 `subsidy_id` 等）は、エラー内容を顧客に示して停止してください。

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が旧同梱平置きパス（例: `specs/<subsidy_id>.json`）を指し、同一 subsidy_id のパック形が上記の解決結果に存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。

## verify-report の読み取り

`verify-report.md` は必ず fenced json block から始まります。次のコマンドが先頭の json block を読み取り、以下の5ゲートを記載順に実行します。後続の未実行ゲートは `BLOCKED` です。

```bash
bash tools/check-finalize.sh --current-application input/current-application.json --profile input/company-profile.json
```

道具の出力を書き換えたり省いたりしないでください。出力の `checklist:` の値をすべて `input/final-checklist.md` の冒頭（タイトル行のすぐ下）へ転記します。

`coverage_inputs_sha256` がない旧 report の必須ハッシュ確認も下記「required_if 判定入力の鮮度確認」で行います。この読み取りだけで最新性を確認済みとは扱わず、鮮度確認まで必ず実行してください。

`spec_check` と `draft_check` の両方が `green` でない場合は、見出し、文字数、様式、添付資料、期限の確認へ進まず、該当 FAIL を直して `/verify` を再実行してください。

## 最新 spec hash と check-spec 再実行

このコマンドは `verify-report.md` に記録された `spec_path` の file bytes から SHA-256 を再計算し、report の `spec_sha256` との一致を確認します。あわせて `input/current-application.json` の `spec_path`、`spec_version` と report の値の一致を確認し、現在の spec に対して `bash tools/check-spec.sh <spec_path>` と同じ検査を再実行します。

`spec_sha256` が一致しない、または `check-spec.sh` が fail の場合は、`input/final-checklist.md` を作らず `/verify` を再実行してください。

## 最新 draft hash の再計算

このコマンドは `draft_bodies_sha256` を `/verify` と同じ documented algorithm で再計算します。

- 対象ファイルは `input/drafts/<subsidy_id>/` 直下の `*.md`
- ファイルは path 昇順で並べる
- 各ファイルの本文領域は、最初の `## 叩き台` 見出しより下から、次の同階層 `## ` 見出しまたは EOF まで
- 本文領域の各行は前後空白を除去し、改行を取り除いて連結する
- 連結後に NFKC 正規化する
- 各ファイルの正規化済み本文を `\n---\n` で結合し、その UTF-8 bytes の SHA-256 を取る

`check-finalize.sh` は `input/current-application.json` から `subsidy_id` を読み、`tools/draft-hash.sh` と共通の関数でハッシュを計算します。

再計算した値が `verify-report.md` の `draft_bodies_sha256` と一致しない場合は、draft が変わっています。`input/final-checklist.md` を作らず、顧客本人へ「最新 draft に対する verify が未完了」と説明し、`/verify` を実行してから戻ってください。

## required_if 判定入力の鮮度確認

このコマンドは現在の `input/company-profile.json` と `input/current-application.json` を使い、`/verify` と同じ判定入力の引数に `--require-coverage` を追加して draft 検査を再実行します。保存済みの coverage gaps が「なし」でも省略しません。下記の欠落・0 件以外で検査が fail、または判定入力ハッシュが欠落・不正・不一致なら旧結果は失効です。チェックリスト・report・state は更新せず、`state=finalized` の場合も直接 `/verify` へ戻ってください。再検証成功後に `state=verified` に戻し、提出前チェックリストを作り直します。

spec の定義に基づき、`produced_by=ai_draftable`・optional でないセクション・成果物の必須判定が TRUE の組み合わせで draft が欠けると FAIL になります。申請可否や適格性の判定ではありません。FAIL なら `input/final-checklist.md` の作成・更新と `state=finalized` への更新を止め、欠けているセクション ID を本人に示し、`/draft-section` で作るか、本人が別に作ると明示するかを選んでもらってください。作成した場合は `/verify` を再実行します。

`--waive <deliverable_id>/<section_id>` は、本人が「このセクションは自分で別に作る」と明示したセクションだけに付けます。AI の判断で付けないでください。本人の明示がある場合だけ、上記コマンドに `--waive <deliverable_id>/<section_id>` を追加して再検査します。draft が既にある場合は draft を消すか waive を外すよう本人に案内し、AI が勝手に削除しないでください。draft が 0 件なら全セクションを waive しても FAIL です。`/finalize` は使えないと伝え、`/plan-deliverables` の一覧（`input/deliverables.md`）を提出前の確認に使うよう案内して止めてください。

一致した場合も、再検査の WARN と `[要確認]` は顧客本人の確認事項として残します。必須判定が UNKNOWN の欠落は `[要確認]` つきの WARN のまま残し、判定入力が変わった場合は `/verify` で新しいハッシュと coverage gaps を同じ検査結果から記録し直してください。

## 全 draft のレビュー記録ゲート

このコマンドで `input/reviews/*.md` を 1 件ずつ検査し、記録と引用の照合が**同じファイルで両方 exit 0** になった最初の 1 件を採用します。複数の一部レビューを合算しません。通常の draft 検査にも `/verify` と同じ `--profile` / `--current-application` を渡します。

不合格なら `input/final-checklist.md` の作成・更新と `state=finalized` への更新を止めます。出力に従い、記録なし・記録が読めない・本文が変わった・一部だけ（不足 ID）・引用の照合が不合格の理由を本人に示し、全 draft 対象の `/review` へ戻してください。通常の draft 検査の FAIL も伝えます。未実行は合格と扱いません。採用したパスと `reviewed_draft_bodies_sha256` を以下の verify ゲートに転記してください。

## 入力として使うもの

- `input/current-application.json`
- `input/company-profile.json`
- `input/checks/verify-report.md`
- `input/deliverables.md`
- `input/deliverables-notes.md`（存在する場合。本人の回答・確認先・確認結果を照合し、一覧の行は書き換えない）
- `spec_path` が指す confirmed spec
- `input/drafts/<subsidy_id>/` 配下の draft
- `input/reviews/` 配下のレビュー結果
- 顧客が提示した公式の募集要項、指定様式、記入例、FAQ
- 見積書、仕様書、決算書、売上資料、従業員数資料、資金計画資料、添付予定資料

公式の募集要項、指定様式、記入例、FAQ、添付資料一覧、提出期限、提出方法は、顧客本人が最新版を確認してください。補助率、補助上限、対象経費、事業実施期間、提出期限、添付資料、文字数、ページ数、電子申請の入力欄は推測しないでください。顧客資料または公式の募集要項から確認できないものは `[要確認]` として残します。

## 進め方

### 1. verify 全緑と最新性を記録する

`input/final-checklist.md` の冒頭に、検証ゲートの結果を明記してください。

- `verify-report.md` の path
- `spec_check`
- `draft_check`
- `spec_path`
- `spec_version`
- `spec_sha256`
- 再計算した spec_sha256
- `check-spec.sh` 再実行結果
- 採用したレビューファイルのパスと `reviewed_draft_bodies_sha256`、記録・引用検査の終了コード
- `draft_bodies_sha256`
- 再計算した draft hash
- `coverage_inputs_sha256` と同じ引数での draft 再検査のハッシュ・結果
- 一致判定
- `generated_at`
- `current-application.json` の `state_before`
- 本人が明示した waive の一覧

ここが全緑かつ hash 一致でない場合は、提出前チェックリストを作りません。

### 提出用まとめを生成する

上記の前提条件と全ゲート（verify の鮮度・必須セクション・全 draft のレビュー記録と引用照合）をすべて通過した後、`input/final-checklist.md` を作る段階で、次のコマンドを実行してください。`<spec_path>` は上記で解決・検証済みの spec、`<subsidy_id>` は現在の申請案件の ID に置き換えます。AI がまとめを手で組み立てないでください。

```bash
bash tools/build-submission.sh <spec_path> input/drafts/<subsidy_id>/ --output input/submission-summary.md
```

終了コードが非 0 の場合は出力をそのまま本人に伝え、処理を停止し、`state=finalized` に進めません。古いまとめが残っている場合は使わないよう伝えます。exit 0 とファイル生成を確認できた場合だけ次へ進み、生成日時を ISO8601 で final-checklist に記録してください。

提出用まとめは申請システムへ写すための控えであり、提出物そのものではありません。写す前に本人が各セクションを読み、`[要確認]` が残っている箇所は解消してから写します。draft を直したら `/review` → `/verify` → `/finalize` をやり直して作り直し、古いまとめは使わないでください。AI はこのファイルの本文を書き換えません。

### 2. 成果物マニフェストから消し込み表を作る

`input/deliverables.md` を読み、final-checklist を次の 5 つに分けて作ってください。`input/deliverables.md` は再生成可能なビューですが、提出前の消し込みは `/finalize` の `input/final-checklist.md` に残します。

1. AIと作る成果物の最終確認
   - `produced_by=ai_draftable` の成果物と sections を対象に、対応する draft、`/verify` の字数結果、`/review` の高・中リスク対応状況を確認します。
   - 見出し、文字数、様式、本文と根拠資料の整合、`[要確認]` の残りを、顧客本人が確認できる表にしてください。
2. 人がやること消し込み
   - waive した全セクションの ID、本人が別に作ると明示した内容、担当・期限・完了確認を載せます。waive は作成済みや確認済みを意味しません。
   - `type=procedure`、`produced_by=human_only`、`produced_by=external` の項目を対象に、作業主体、issuer、依頼先、完了状況、残アクションを確認します。
   - 外部発行書類や支援機関確認など、AI が作れないものを AI 成果物のように扱わないでください。
3. 添付資料チェック
   - `type=attachment` の項目、見積書、仕様書、決算書、売上資料などを対象に、ファイル名、format、upload_target、本文との対応、最新版かどうかを確認します。
4. hard 締切チェック
   - spec の `schedule[]` と `input/deliverables.md` の締切カレンダーを読み、`hard=true` の期限を先頭に出します。
   - date、starts_at、ends_at、time、timezone、relative をそのまま表示し、相対期限は一般論で日付換算しません。
5. 条件付き成果物の該当確認
   - `input/deliverables.md` の「条件付き（該当する場合のみ提出）」節（`required=false` かつ `required_if` が null/未設定 で、条件が自然文にしかない成果物）を全件そのまま引き継ぎます。件数を減らさないでください。
   - 各行の「該当」欄を、顧客本人が「該当する」「該当しない」「未確定」のいずれかで答える欄として出します。AI が該当有無を判定しないでください。条件の自然文は `input/deliverables.md` の記載を原文のまま転記します。
   - 条件が審査側・第三者の判断で申請後に決まるもの（口頭審査の対象化など）と、`phase` が今回の申請フェーズでないもの（`post_adoption` 等）は、申請前に確定できません。これらは「未確定」を正しい回答として認め、「判定時期」欄にいつ分かるか（例: 審査結果の通知時、交付決定後）を書きます。申請前に二択を強制しないでください。
   - `type=procedure` の作業と、今回の申請フェーズでない `phase` の成果物は、申請時の提出物と分けて表示します。今回の提出物としては数えません。
   - 「該当する」と答えられた成果物は、1〜3 の各表の条件を**独立に**評価し、当てはまる表すべてに追加して通常の消し込み対象にします（`type` による一択の振り分けをしないでください）。1〜3 の条件は排他ではありません。たとえば `type=attachment` かつ `produced_by=human_only` の成果物は、担当と完了確認のために「人がやること」へ、format と upload_target の確認のために「添付資料」へ、両方に載せます。
   - 該当欄が未記入のまま残っている件数を数え、「提出直前の未解決事項」に明示します。
   - 「未確定」を提出前の未解決件数から外してよいのは、**前項で事後判定と切り分けた行だけ**です（審査側・第三者が申請後に決める条件、および `phase` が今回の申請フェーズでない行）。それらは判定時期とあわせて「採択後・審査結果後に確認すること」へ別に並べます。申請前に確定できる行（`phase` が今回の申請フェーズで、条件が顧客本人の属性・申請内容で決まるもの）に「未確定」と書かれている場合は、**未記入と同じく提出前の未解決として数えます**。締切前に解消すべき添付を「未確定」で先送りさせないためです。

### 3. 見出し・文字数・様式の最終確認をする

事業計画書の見出し、設問、入力欄、順番が、募集要項や指定様式に合っているか確認してください。このリポジトリのテンプレート名と募集要項の見出し名が違う場合は、募集要項の見出しを優先してください。

確認対象には次を含めてください。

- 指定された見出しや入力欄が抜けていないか
- セクションの順序が様式に合っているか
- 表、箇条書き、ファイル名、ファイル形式などの指定に合っているか
- 文字数、ページ数、行数、PDF 化などの条件があるか
- 記入不要欄、事務局記入欄、押印欄、署名欄の扱いを顧客本人が確認できる形になっているか
- 第三者からの支援・アドバイスの有無を申告する欄や、作成主体に関する誓約欄が様式・確認事項にあるか（制度汎用の確認項目）

文字数の機械チェックは `/verify` の `check-drafts.sh` が担当します。`/finalize` では、文字数結果を提出様式へ貼り付けるときに崩れないか、見出しや欄の分割が様式に合っているかを確認してください。

### 4. 第三者支援の開示欄・誓約欄を確認する

対象制度の公募要領と様式に、第三者からの支援・アドバイスの有無を申告する欄や、作成主体に関する誓約欄がないかを、顧客本人が原本で確認できる形に整理してください。制度汎用の確認項目です（背景は `docs/法務とスコープ.md` の「第三者支援の開示欄・誓約欄の確認」）。

- 確認済み spec に該当 clause がある場合は、`clause_id` と該当ページを引用して提示します（例: `jizokuka-20` では第三者支援の開示が `disclosure-001`、作成主体が `authorship-001`、申請書類の宣誓が `pledge-001`）。clause の守備範囲を広げて読み替えないでください。spec に該当 clause がない欄は「spec 未収載」と明示し、公募要領・様式の原本で確認するよう案内します。
- 該当欄で求められる事項（有無だけか、相手方や金額まで求めるか、どの範囲の金額かなど）は制度ごとに違います。確認済み spec の該当 clause と様式の記載事項から、その制度が求める事項だけを列挙してください。spec にも様式にも書かれていない事項を、このコマンド側で一般論として足さないでください。
- 本キットや持ち込み AI の利用が開示対象に当たるかどうかは制度側の解釈事項です。AI は該当・非該当を判断しません。判断に迷う場合は当該制度の事務局へ確認し、確認日時と回答内容をメモに残すよう案内してください。
- 未記載・虚偽記載の取扱い（不採択・交付決定取消・返還等）が公募要領に明記されている場合は、その clause を引用して顧客本人に示します。spec にその条項が無い制度で罰則を推測して書かないでください。
- この欄の記載内容は顧客本人の事実申告です。AI が代わりに書いたり推測したりせず、`[要確認]` として残してください。

### 5. 提出直前の未解決事項をまとめる

`[要確認]` が残る場合は、提出前に何を確認すれば解消できるか、顧客本人の次アクションとして書いてください。未解決のまま提出するリスクがある場合も、提出可否を代わりに判断せず、リスクとして整理します。

条件付き成果物の「該当」欄が未記入のまま残っている場合は、その件数と `deliverable_id` を「提出直前に再確認すること」に必ず挙げてください。未記入は「該当しない」ではありません。該当するのに未記入のまま提出すると、提出書類が不足したまま締切を迎えます。「未確定」と答えられた行のうち、上の手順で事後判定と切り分けた行（審査側・第三者が申請後に決める条件、今回の申請フェーズでない行）だけは、申請前に解消できないので未記入に数えず、判定時期とあわせて別に並べます。それ以外の「未確定」は提出前の未解決件数に数えます。

締切までの残作業は、顧客本人が判断できるように次の形式で整理してください。

- 今日確認すること
- 提出前日までにそろえること
- 提出直前に再確認すること
- 事務局、支援機関、専門家へ確認したほうがよいこと

## 出力形式

本人への報告には `input/final-checklist.md` と `input/submission-summary.md` のパスを載せてください。

`input/final-checklist.md` を作成してください。既存ファイルがある場合は、上書き前に顧客へ確認してください。

```markdown
# final-checklist

## 作成メモ

- 作成者: 顧客本人
- AIの役割: 体裁、様式、文字数、添付、期限、verify 最新性、未確認事項の整理補助
- current_application: input/current-application.json
- verify_report: input/checks/verify-report.md
- deliverables_view: input/deliverables.md
- 提出用まとめ: `input/submission-summary.md`（生成日時）
- 提出判断: 顧客本人が行う

## verify ゲート

| 項目 | 内容 |
| --- | --- |
| spec_check | green |
| draft_check | green |
| spec_path |  |
| spec_version |  |
| report spec_sha256 |  |
| recomputed spec_sha256 |  |
| check-spec rerun | green |
| adopted review record path |  |
| reviewed_draft_bodies_sha256 |  |
| review record / quotes check exit codes |  |
| report draft_bodies_sha256 |  |
| recomputed draft_bodies_sha256 |  |
| hash 一致 | yes |
| generated_at |  |

## 参照資料の棚卸し

| 資料 | 用途 | 確認状況 | `[要確認]` |
| --- | --- | --- | --- |

## AIと作る成果物の最終確認

| deliverable_id | section_id | draft | 見出し | 文字数 | 様式 | review対応 | 顧客本人の確認事項 |
| --- | --- | --- | --- | --- | --- | --- | --- |

## 人がやること消し込み

| deliverable_id | 作業 | produced_by | issuer | 期限 | 完了状況 | 残アクション |
| --- | --- | --- | --- | --- | --- | --- |

## 添付資料チェック

| 添付資料 | 必須/任意 | format | upload_target | 本文との対応 | 準備状況 | 顧客本人の確認事項 |
| --- | --- | --- | --- | --- | --- | --- |

## hard 締切チェック

| event_id | name | date/period/relative | time | timezone | hard | 残アクション |
| --- | --- | --- | --- | --- | --- | --- |

## 条件付き成果物の該当確認

条件が自然文にしかない成果物です。該当するかどうかは顧客本人が判断します。AI は判定しません。

| deliverable_id | 成果物名 | 条件（原文のまま） | type | phase | produced_by | issuer | 期限 | 該当（該当する/該当しない/未確定） | 判定時期 | 該当時の残アクション |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## 提出前チェックリスト

- [ ] 募集要項の最新版を確認した
- [ ] `verify-report.md` の `spec_check=green` と `draft_check=green` を確認した
- [ ] `spec_sha256` が現在の spec file bytes の再計算値と一致した
- [ ] `bash tools/check-spec.sh <spec_path>` を再実行して green だった
- [ ] `draft_bodies_sha256` が最新 draft の再計算値と一致した
- [ ] 指定様式、見出し、入力欄、文字数、ページ数に合わせた
- [ ] 対象者、対象事業、対象経費、補助率、補助上限を募集要項で確認した
- [ ] AI と作る成果物の全 draft を顧客本人が読んで修正した
- [ ] 人がやることリストの作業を消し込み、未完了があれば期限と担当を確認した
- [ ] 見積書、仕様書、決算書、売上資料などの添付資料をそろえた
- [ ] 電子申請または提出方法、締切日時、必要アカウントを確認した
- [ ] 対象制度の第三者支援の開示欄・誓約欄（第三者からの支援・アドバイスの有無、作成主体に関する確認・誓約）を公募要領・様式で確認し、該当欄がある場合は、その様式と spec の clause が求める事項を顧客本人が記載した
- [ ] 条件付き成果物（`required=false` かつ `required_if` が null/未設定）の該当有無を、顧客本人が1件ずつ「該当する」「該当しない」「未確定」で答えた
- [ ] 「該当する」と答えた条件付き成果物を、AI と作る成果物・人がやること・添付資料のうち条件に当てはまる表すべてに追加して消し込み対象にした
- [ ] `[要確認]` が残っている箇所を確認し、未解決なら提出前リスクとして把握した
- [ ] 作成者は顧客本人であり、AI は補助・壁打ち・整理役に限ることを確認した
- [ ] 提出は顧客本人の責任・判断で行うことを確認した

## 残アクション

### 今日確認すること

### 提出前日までにそろえること

### 提出直前に再確認すること

### 外部確認したほうがよいこと

## `[要確認]` リスト
```

## current-application.json の更新

提出用まとめの生成が exit 0 で完了し、`input/final-checklist.md` を作成できた場合だけ、`input/current-application.json` を更新してください。verify ゲートが不成立の場合は更新しません。

更新は下の `--record-finalized` が書き込みます。AI が手で書き込まないでください。道具が書き込む内容と、変えない内容は次のとおりです。

- `state` を `finalized` にする
- `final_checklist_path` を `input/final-checklist.md` にする
- `finalized_at` と `updated_at` を ISO8601 で入れる
- `draft_bodies_sha256` は `verify-report.md` と再計算値が一致した値を保持する
- `subsidy_id`、`spec_path`、`spec_version`、`chosen_funding` は確認なしに変更しない

全ゲートをもう一度実行してから更新します。最初の検査と同じ `--current-application`・`--profile`・本人が明示した `--waive` を渡してください。

```bash
bash tools/check-finalize.sh --current-application input/current-application.json --profile input/company-profile.json --record-finalized
```


`state=finalized` にした後でも、draft、spec、confirmation、`input/deliverables.md` を更新した場合は、提出前チェックが古くなります。その場合は `/review`、`/verify`、`/finalize` を必要な範囲でやり直してください。

完了時には、`state=finalized` は「提出前チェックを通過した」状態であり、申請書の完成や提出してよいことを意味しないと伝えてください。提出用まとめの `本文に残っている [要確認]:` の行をそのまま伝える（自分で足し算しない）。提出の前に本人が解消・確認するよう案内してください。

## 出力時の注意

- 体裁整えは、募集要項と指定様式に合わせるための確認補助として行ってください。
- 文章を提出用の完成版として断定的に仕上げないでください。顧客本人が最終確認、修正、提出判断を行います。
- `verify-report.md` が missing、fail、stale spec hash、または stale draft hash の場合は、`input/final-checklist.md` を作らず `/verify` へ戻してください。
- 募集要項にない数値、要件、文字数、添付資料、期限、提出方法を推測しないでください。
- `[要確認]` が残る場合は、何を見れば確認できるか、顧客本人が次に取る行動として書いてください。
- `input/deliverables.md` に「条件付き（該当する場合のみ提出）」節がある場合、`input/final-checklist.md` に「条件付き成果物の該当確認」節を必ず作り、全件を落とさず載せてください。該当有無を AI が埋めて件数を減らさないでください。`state=finalized` にできるのは節を作れた場合であり、該当欄が全て記入済みであることは求めません（他のチェック項目と同じく、記入は顧客本人が行います）。
- 申請代行、代理提出、本人に代わる完成判断、官公署への提出代行を示唆する表現を避けてください。
- 最後に「提出は顧客本人の責任・判断で行う」ことを明記してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/finalize` は、最新 draft に対する verify 全緑を前提に、見出し、文字数、様式、添付資料、期限、提出前チェックリストを整理するための最終確認補助です。提出は顧客本人の責任・判断で行います。数値、要件、文字数、補助率、補助上限、添付資料、提出期限は募集要項または顧客資料を根拠にし、出典不明の事実には `[要確認]` を付けてください。
