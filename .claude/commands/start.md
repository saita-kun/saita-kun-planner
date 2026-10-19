---
description: 初めてこのリポジトリを開いた Claude Code 契約者向けに、前提・進め方・法務ガードレールを確認し、次に実行するコマンドへ案内します。
---

# /start

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する初回案内役です。顧客が迷わず `/select-subsidy`、または `/ingest-guidelines` → `/confirm-spec` → `/build-pack` で対象 spec と書き方メモを整え、その spec を軸に `/intake` へ進めるように、前提、作業順、必要な入力、法務ガードレールを短く確認してください。

このコマンドは、申請書を作るための実作業を始める前のオリエンテーションです。会社情報のヒアリング、募集要項からの spec 化、要件照合、成果物計画、事業計画書セクションの作成、レビュー、機械検証、提出前チェック、振り返りは、後続の slash command で行います。

## 最初に確認すること

1. 顧客が Claude Code 契約者であり、このリポジトリを Claude Code で開いていることを確認してください。
2. このリポジトリは、顧客本人が補助金申請用の事業計画書の叩き台を作るための作業環境であることを説明してください。
3. 公式の募集要項、自社資料、見積書、売上資料、投資計画などの実情報を顧客本人が確認しながら進める前提を伝えてください。
4. 数値や要件は推測しないこと、出典不明の事実や顧客確認が必要な項目には `[要確認]` を付けることを伝えてください。
5. 作業状態は `input/current-application.json` に記録され、`state`、`spec_path`、`chosen_funding` を後続コマンドが引き継ぐことを説明してください。
6. 詳細な手順は `docs/manual.md` にまとまっていることを案内してください。

## 案内する作業順

次の順番を、顧客が実行できる形で案内してください。補助金の制度定義は spec を正本にし、公式募集要項から確認できない数値や要件は `[要確認]` として残します。

0. 入口A: `/select-subsidy` — 同梱 `specs/` の confirmed spec が対象回と一致する場合に選び、`input/current-application.json` を `state=spec_confirmed` にします。
1. 入口B: `/ingest-guidelines` — 顧客本人が持つ公式募集要項を `input/guidelines/` に置き、draft spec と confirmation 項目を作って `state=spec_draft` にします。
2. `/confirm-spec` — draft spec と募集要項原本を顧客本人が突合確認し、green になってから `state=spec_confirmed` にします。
3. `/build-pack` — confirmed spec から補助金パックを整え、後続の `/draft-section` と `/review` が参照する書き方メモを作ります。
4. `/intake` — confirmed spec を読み、`eligibility.rules[]` や scoring が参照する会社情報を優先してヒアリングし、`input/company-profile.md` と `input/company-profile.json` を作って `state=intake_done` にします。
5. `/subsidy-fit` — confirmed spec と会社プロフィールを照合し、除外要件、必須要件、加点要素、不足準備、狙う枠 `chosen_funding` を `input/current-application.json` に記録します。
6. `/plan-deliverables` — confirmed spec と `chosen_funding` から、AI と作る成果物、人がやること、添付、締切を `input/deliverables.md` に整理します。
7. `/draft-section` — spec の `deliverables[]` / `sections[]` から 1 セクションを選び、`input/drafts/<subsidy_id>/<section_id>.md` に `## 叩き台` を作ります。
8. `/review` — 叩き台の定性レビューを行い、`clause_id`、`quoted_text`、根拠不足、誇張、行政書士法上の作成主体を点検します。
9. `/verify` — `bash tools/check-spec.sh` と `bash tools/check-drafts.sh` を実行し、字数、必須セクション、coverage gaps、`[要確認]`、draft 本文ハッシュを `input/checks/verify-report.md` に記録します。
10. `/finalize` — verify が green で、`draft_bodies_sha256` が最新 draft と一致することを確認し、提出前チェックリストを顧客本人の最終確認に回します。
11. `/retrospect` — 提出後または採否判明後に、結果、講評、学び、次回アクションを `knowledge/records/` と `knowledge/lessons/` に残します。

## 入口の選び方

- 同梱 `specs/` に対象補助金・公募回・様式が一致する confirmed spec があり、顧客本人が公式募集要項と照合して違和感がない場合は、入口Aとして `/select-subsidy` に進めます。
- 最新の募集要項、別の公募回、別制度、または同梱 spec と公式資料に差がある可能性がある場合は、入口Bとして `/ingest-guidelines` を案内し、読み込み後は `/confirm-spec` で突合確認することを伝えてください。
- `/build-pack` は confirmed spec 以降に実行する推奨ステップです。書き方メモは申請書本文ではなく、叩き台作成とレビューの補助資料だと説明してください。
- どちらの場合も、公式募集要項が正です。spec は作業のための構造化ビューであり、顧客本人の確認を置き換えません。

## 育成層

`knowledge/` は、申請結果や講評、次回に活かす学びを顧客本人の repo に残す育成層です。`/retrospect` で `knowledge/records/` と `knowledge/lessons/` を増やすと、次回の `/draft-section` や `/review` が過去の弱点や改善点を参照できます。

将来、顧客本人が自分用の `my-*` commands を `.claude/commands/` に追加する場合も、コアコマンドとは分けて扱ってください。`my-*` commands は顧客固有の運用メモや社内手順を反映するための拡張であり、公式募集要項、spec、`input/current-application.json` の根拠を置き換えるものではありません。

## 顧客に尋ねること

オリエンテーションでは、次の質問だけを行い、回答に応じて次のコマンドを案内してください。ここでは長いヒアリングを始めず、必要なら `/intake` に進めてください。

1. 対象にしたい補助金の公式募集要項、または同梱 `specs/` と照合できる資料はありますか。
2. 同梱 `specs/` の対象回を使えそうですか。それとも `/ingest-guidelines` で自分の募集要項から spec を作りますか。
3. spec 確定後に会社概要、売上、従業員数、投資予定、見積書などの自社資料を `input/` に置く準備はありますか。

## 回答に応じた案内

- 同梱 `specs/` を使うなら、次に `/select-subsidy` を案内してください。
- 顧客本人の募集要項から spec を作るなら、次に `/ingest-guidelines` を案内し、その後 `/confirm-spec` へ進むことを伝えてください。
- `input/current-application.json` がすでにあり、`state=spec_draft` なら `/confirm-spec`、`state=spec_confirmed` なら `/build-pack` を未実行なら推奨してから `/intake`、`state=intake_done` なら `/subsidy-fit`、`state=fit_done` なら `/plan-deliverables`、`state=planned` または `state=drafting` なら `/draft-section` または `/review`、`state=verified` なら `/finalize` を案内してください。
- まだ対象補助金を選べていない場合は、公式情報源で募集要項、対象者、対象経費、補助率、補助上限、締切を確認してから、同梱 `specs/` を使うか `/ingest-guidelines` で spec を作るよう案内してください。確認できない数値や要件は `[要確認]` として扱ってください。
- 作業全体の流れを知りたい顧客には、`docs/manual.md` を先に読むよう案内してください。

## 出力形式

顧客に対して、次の形式で短く案内してください。

```markdown
# 初回案内

## このキットでできること

## 進め方

1. 入口A: /select-subsidy または 入口B: /ingest-guidelines
2. /confirm-spec
3. /build-pack
4. /intake
5. /subsidy-fit
6. /plan-deliverables
7. /draft-section
8. /review
9. /verify
10. /finalize
11. /retrospect

## 状態ファイル

## 育成層

## いま確認したいこと

## 次に実行するコマンド

## 法務・根拠の注意
```

## 出力時の注意

- 初回案内では、申請書本文を作り始めないでください。
- 顧客本人の実情報をまだ確認していない段階で、補助金への適合、採択可能性、補助額、補助率、補助上限、効果見込みを断定しないでください。
- 公式募集要項を確認できない要件や数値は、一般論で補わず `[要確認]` としてください。
- `input/` に置く情報は顧客の機密情報を含む可能性があるため、公開リポジトリへコミットしない前提で扱うよう伝えてください。
- `input/current-application.json` がある場合は、現在の `state` を読んで途中再開の位置を判断してください。
- 最後に、迷わなければ同梱 spec なら `/select-subsidy`、手元の募集要項なら `/ingest-guidelines` から始めること、`state=spec_draft` なら `/confirm-spec`、`state=spec_confirmed` になったら必要に応じて `/build-pack` を実行してから `/intake` へ進むこと、全体像を確認したい場合は `docs/manual.md` を読むことを案内してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/start` は作業開始前の案内に限定し、提出判断や要件充足の確定は行いません。数値、要件、文字数、補助率、補助上限、添付資料、提出期限は公式の募集要項または顧客資料を根拠にし、出典不明の事実には `[要確認]` を付けてください。
