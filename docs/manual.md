# saita-kun-planner マニュアル

## 概要

saita-kun-planner は、補助金申請者が自分の Claude Code を使い、補助金申請用の事業計画書の叩き台を作るためのスターターキットです。公式の募集要項、会社情報、投資計画、数値根拠を整理し、補助金の審査観点に沿って「課題、解決策、実現性、効果」をつないだ文章案を作ることを支援します。

このキットは、申請書を自動で完成させるものではありません。AI は材料整理、論点の洗い出し、文章案の作成、根拠不足の指摘を補助します。最終的な内容確認、修正、提出判断は顧客本人が行います。

## 前提

このリポジトリは Claude Code 契約者向けです。Claude Code の slash command、`CLAUDE.md`、必要に応じた subagent を使える環境で作業することを前提にしています。

作業を始める前に、GitHub からこのリポジトリを git clone できること、clone したリポジトリを Claude Code で開けること、補助金の公式募集要項や自社資料を手元で確認できることを確認してください。顧客の会社情報や募集要項メモは `input/` に置く想定ですが、機密情報を公開リポジトリに入れないよう注意してください。

GitHub や Claude Code の操作に慣れていない場合は、先に `docs/onboarding/00-はじめに.md` から順番に確認してください。利用条件とデータの扱いは `TERMS.md` と `docs/data-policy.md` にまとめています。

## セットアップ

1. GitHub でこのリポジトリを自分の作業用リポジトリとして用意します。`Use this template` から private repo を作る手順は `docs/テンプレートrepoの使い方.md` を参照してください。
2. 作業端末で git clone します。
3. clone したフォルダを Claude Code で開きます。
4. 公式募集要項、候補補助金の資料、会社情報、投資計画、見積書メモなど、事業計画書の材料になる情報を `input/` に保存します。
5. 初回は Claude Code で `/setup` を実行し、環境セルフチェック、利用規約同意、result-report 任意提出の扱いを確認します。
6. `/setup` で準備が整ったら `/start` を実行して全体像を確認し、その後、同梱 spec を使うなら `/select-subsidy`、自分の募集要項から spec を作るなら `/ingest-guidelines` から進めます。

`input/` は顧客データを置く場所です。会社名、売上、従業員数、投資額、見積額、補助対象経費、提出期限などの数値は、必ず顧客の資料または公式募集要項に基づいて入力してください。AI が不明な数値を推測して埋めることはありません。

## 新しい基本フロー

現在の標準フローは、先に「入口A/B」で募集要項または同梱 spec を confirmed spec として確定し、その spec が求める会社情報を `/intake` で聞く順番です。入口Bは `/ingest-guidelines` で draft spec を作り、`/confirm-spec` で募集要項と突合してから confirmed spec に昇格します。新状態遷移は `spec_draft → spec_confirmed → intake_done → fit_done → planned → drafting → verified → finalized` です。

| 順番 | コマンド・入口 | 目的 | 主な状態・出力 |
| --- | --- | --- | --- |
| 0A | 入口A: `/select-subsidy` | 対象補助金・公募回が同梱 spec と合う場合に使う | `input/current-application.json` の `state=spec_confirmed` |
| 0B | 入口B: `/ingest-guidelines` | 顧客本人の公式募集要項から draft spec を作る | `input/spec/<subsidy_id>.json`、confirmation、`state=spec_draft` |
| 0C | `/confirm-spec` | draft spec を募集要項の原本と突合し、顧客本人の確認後に昇格する | confirmation 更新、`status=confirmed`、`state=spec_confirmed` |
| 0D | `/build-pack` | confirmed spec から書き方メモを作る | `input/spec/<subsidy_id>/` の補助金パック |
| 1 | `/intake` | confirmed spec が参照する会社情報を優先して整理する | `input/company-profile.md`、`input/company-profile.json`、`state=intake_done` |
| 2 | `/subsidy-fit` | confirmed spec と会社プロフィールを照合する | `input/subsidy-fit.md`、`chosen_funding`、`state=fit_done` |
| 3 | `/plan-deliverables` | 成果物、人がやること、添付、締切を一覧化する | `input/deliverables.md`、`state=planned` |
| 4 | `/draft-section` | spec の 1 セクションだけを叩き台化する | `input/drafts/<subsidy_id>/<section_id>.md`、`state=drafting` |
| 5 | `/review` | 根拠、誇張、条文引用、作成主体を定性レビューする | `input/reviews/` |
| 6 | `/verify` | spec と draft の機械検証を行う | `input/checks/verify-report.md`、`draft_bodies_sha256`、`state=verified` |
| 7 | `/finalize` | verify green と最新 draft を確認して提出前チェックを作る | 提出前チェックリスト、`state=finalized` |
| 8 | `/retrospect` | 提出後・採否判明後の学びを残す | `knowledge/records/`、`knowledge/lessons/` |

`input/current-application.json` は、今どの補助金・spec・狙う枠で作業しているかを後続コマンドへ渡す状態ファイルです。主に `state`、`subsidy_id`、`spec_path`、`spec_version`、`chosen_funding`、`drafts_dir` を持ちます。`state=spec_draft` の場合は突合が未完了なので、次は `/confirm-spec` です。途中再開するときは、まずこのファイルの `state` を見て、次に実行するコマンドを判断してください。

補助金パックは、1 つの補助金・公募回について、確認済みの制度情報と書き方メモをひとまとまりにした作業セットです。同梱の補助金パックは早く始めるための出発点で、顧客本人が自分の募集要項から作る補助金パックは `input/spec/` 側に置かれます。

書き方メモは、審査で見られる観点、加点や狙う枠の注意、セクション別の書き方のコツをまとめた補助資料です。叩き台本文ではなく、後続の `/draft-section` と `/review` が参照する材料です。書き方メモに書かれた一般的な助言は、募集要項の数値や要件の根拠にはなりません。数値や要件は、必ず公式募集要項と confirmed spec を優先してください。

同梱 spec は作業を早く始めるための構造化ビューですが、公式募集要項の代替ではありません。対象回や様式が違う場合、または顧客本人の手元の募集要項が最新の場合は、入口Bとして `/ingest-guidelines` で自分の `input/spec/` を作り、`/confirm-spec` で突合確認してから進んでください。

コア層と育成層、`my-*` コマンド、`knowledge/`、上流更新の考え方は [docs/ハーネスの育て方.md](ハーネスの育て方.md) にまとめています。

## 使い方

### `/setup`

`/setup` は、Claude Code でこのリポジトリを開いた直後に実行する準備確認コマンドです。環境セルフチェック、`TERMS.md` / `docs/data-policy.md` の同意確認、result-report 任意提出の扱いを確認し、準備が整ったら `/start` へ案内します。旧 collaborator 招待モデルは撤回済みであり、提供側を private repo に招待することは利用条件ではありません。

### `/start`

`/start` は、`/setup` 後に実行する作業オリエンテーションです。このキットの前提、作業順、必要な入力、法務ガードレールを確認し、同梱 spec を使うなら `/select-subsidy`、自分の募集要項から spec を作るなら `/ingest-guidelines`、全体像を読みたい場合は `docs/manual.md` へ案内します。

### `/select-subsidy`

`/select-subsidy` は、同梱 `specs/` の confirmed spec を今回の対象として使う入口Aです。顧客本人が公式募集要項と公募回・様式・主要締切を見比べ、一致すると確認できる場合だけ `input/current-application.json` を `state=spec_confirmed` で初期化します。書き方メモを整えるなら `/build-pack`、すぐ会社情報へ進むなら `/intake` で、選んだ spec が必要とする会社情報を優先して整理します。

### `/ingest-guidelines`

`/ingest-guidelines` は、顧客本人が入手した公式の募集要項を `input/guidelines/` に保存し、`schemas/subsidy-spec.schema.json` に従って draft spec と confirmation report を作るコマンドです。締切、要件、補助率、補助上限、提出物、字数制限などを原本から抽出し、`input/current-application.json` を `state=spec_draft` にします。数値や要件は推測せず、確認できない項目は `[要確認]` として残し、原本突合は次の `/confirm-spec` で行います。

### `/confirm-spec`

`/confirm-spec` は、`/ingest-guidelines` が作成した draft spec と confirmation report を、公式募集要項の原文と突合するコマンドです。顧客本人が原本を見て確認した item だけを `confirmed` または `na` にし、`bash tools/check-spec.sh <spec_path> --gate confirm` が green になってから `status=confirmed` と `state=spec_confirmed` へ昇格します。突合が未完了の `state=spec_draft` では、`/intake` 以降へ進みません。

### `/build-pack`

`/build-pack` は、confirmed spec から「書き方メモ」を作るコマンドです。審査で見られる観点、加点や狙う枠の注意、セクション別の書き方のコツを `input/spec/<subsidy_id>/notes/` にまとめます。書き方メモは叩き台本文ではなく、後続の `/draft-section` と `/review` が参照する補助資料です。数値や要件の根拠は募集要項と confirmed spec を優先し、根拠がない制度事実は `[要確認]` として残します。

### `/intake`

`/intake` は、confirmed spec を読んでから、会社概要、事業内容、沿革、従業員数、売上規模、現状課題、投資計画などを整理するコマンドです。Claude Code が `eligibility.rules[]` や scoring 項目で必要な会社情報を優先して質問し、顧客本人が答えた実情報をもとに、後続工程で使う会社プロフィールを `input/company-profile.md` と `input/company-profile.json` にまとめ、`input/current-application.json` を `state=intake_done` に更新します。

### `/subsidy-fit`

`/subsidy-fit` は、confirmed spec と `input/company-profile.md` / `input/company-profile.json` を照合し、除外要件、必須要件、加点要素、不足準備を確認するコマンドです。補助率、補助上限、対象経費、提出期限、文字数、添付資料などは募集要項を一次情報とし、資料から確認できない内容には `[要確認]` を付けます。自分で作った最新 spec を使う場合は、先に `/ingest-guidelines` で原本との突合を済ませてから `/intake` を実行してください。

### `/plan-deliverables`

`/plan-deliverables` は、`/subsidy-fit` で決めた `chosen_funding` と確認済み spec をもとに、`input/deliverables.md` を再生成するコマンドです。AI と作る成果物、人がやることリスト、添付チェックリスト、締切カレンダーをまとめ、後続の `/draft-section` でどの section を作るかを選びやすくします。このファイルは正本ではなく再生成可能なビューであり、手動の進捗チェックや消し込みは `/finalize` の提出前チェックリストで行います。

### `/draft-section`

`/draft-section` は、事業計画書の 1 セクションだけを選んで叩き台化するコマンドです。`/intake` で整理した実情報と `/subsidy-fit` の適合度メモをもとに、課題、解決策、実現性、効果、数値根拠がつながる文章案を作ります。出力は提出用の完成版ではなく、顧客本人が確認し、修正し、根拠を補うための叩き台です。

セクションごとの目的、補助金審査での見られ方、書く順番、数値根拠の置き方、ありがちな減点を先に確認したい場合は、`docs/事業計画書の構成.md` を参照してください。

### `/review`

`/review` は、作成したセクションを募集要項と照合し、要件充足、文字数、根拠、誇張、出典不明の事実、`[要確認]` の残り、行政書士法上の作成主体の表現を点検するコマンドです。問題点を顧客本人が直せるように指摘し、AI が申請書を代理で完成判断することはありません。

### `/verify`

`/verify` は、確認済み spec と `input/drafts/<subsidy_id>/` の draft を機械検証するコマンドです。`bash tools/check-spec.sh` と `bash tools/check-drafts.sh` を実行し、spec/draft の検査結果、セクション別の字数、coverage gaps、`[要確認]` total、draft 本文ハッシュを `input/checks/verify-report.md` に保存します。両方の検査が green の場合だけ `input/current-application.json` を `state=verified` にし、draft を編集したら再実行が必要であることを明示します。

### `/finalize`

`/finalize` は、`input/checks/verify-report.md` の `spec_check` と `draft_check` が green で、`draft_bodies_sha256` が最新 draft の再計算値と一致することを確認してから、見出し、文字数、様式、添付資料、期限、提出前チェックを整える最後の確認コマンドです。`input/deliverables.md` をもとに AI と作る成果物、人がやること、添付、hard 締切を消し込み、顧客本人が募集要項、様式、添付資料、数値、作成主体を最終確認します。提出は顧客本人の責任と判断で行います。

### `/retrospect`

`/retrospect` は、提出後または採否判明後に、今回の結果、講評、フェーズ別の学び、次回アクションを `knowledge/records/` と `knowledge/lessons/` に構造化するコマンドです。`knowledge/` は顧客本人の repo に残る育成層であり、次回の `/draft-section` と `/review` が `knowledge/lessons/` を読んで、過去の弱点や採択・不採択から得た学びを反映します。将来の任意 result-report 提出が実装される場合は、この記録からの抜粋 export として扱う想定ですが、現時点で送信機能はありません。

## コア更新

このキットは、上流のテンプレート repo で slash command、schema、spec、検証ツール、docs が改善されることがあります。自分の作業 repo に取り込む前に、上流 repo を別フォルダへ clone または更新し、この repo 側で `bash tools/update-core.sh --dry-run <上流repoのパス>` を実行してください。`core-manifest.json` に列挙されたコア層ファイルだけについて、`new`、`changed`、`unchanged`、`user-modified` の状態を表示します。詳しい考え方は [docs/ハーネスの育て方.md](ハーネスの育て方.md) を参照してください。

反映する場合は `bash tools/update-core.sh --apply <上流repoのパス>` を実行します。`input/`、`knowledge/`、`.claude/commands/my-*.md` は育成層なので更新対象になりません。顧客本人がコアファイルを編集していて、前回更新時の状態とも上流とも違う場合は `user-modified` としてスキップされます。どうしても上流版で上書きするファイルだけ、内容を確認したうえで `--force-file <path>` を指定してください。

## 法務上の注意

作成者は顧客本人です。AI は補助、壁打ち、整理役であり、申請書の作成代行者ではありません。行政書士法に抵触する申請代行、代理提出、本人に代わる完成判断、官公署への提出代行はしません。

数値は推測しないでください。売上、従業員数、投資額、補助率、補助上限、採択率、効果見込み、KPI などは、顧客の資料または公式の募集要項に基づかない限り断定しません。出典不明の事実、根拠が不足している主張、顧客確認が必要な情報には `[要確認]` を付けます。

募集要項の定義が最優先です。対象者、対象経費、補助率、補助上限、提出期限、添付書類、様式指定、審査項目、文字数指定について、このマニュアルや AI の説明と募集要項が食い違う場合は、必ず募集要項を優先してください。

作成主体、申請代行ではない範囲、税理士法や行政書士法などの専門業務に踏み込まない扱いは、[docs/法務とスコープ.md](法務とスコープ.md) で確認してください。

## つまずいたら

slash command が表示されない、`input/` に何を置けばよいかわからない、実行順を迷う、行政書士法上どこまで AI に頼ってよいかわからない場合は、`docs/faq.md` を参照してください。

補助金そのものをまだ選べていない場合は、`docs/補助金の選び方.md` を参照し、公式情報源で募集要項を確認してから、同梱 spec を使うなら `/select-subsidy`、自分の募集要項から作るなら `/ingest-guidelines` → `/confirm-spec` に進んでください。制度名、締切、対象者、対象経費、補助率、補助上限などを確認できない状態では、事業計画書の叩き台にも `[要確認]` が多く残ります。

一連の流れを先に見たい場合は、`examples/worked-example/` の架空サンプルを参照してください。実在する会社や補助金ではなく、`/select-subsidy` または `/ingest-guidelines`、`/intake`、`/subsidy-fit`、`/draft-section`、`/review` の成果物がどの粒度でつながるかを確認するための教材です。
