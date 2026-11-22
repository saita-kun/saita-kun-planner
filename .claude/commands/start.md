---
description: 初めてこのリポジトリを開いた Claude Code 契約者向けに、前提・進め方・法務ガードレールを確認し、次に実行するコマンドへ案内します。
---

# /start

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

**現在地の表示**: preflight の直後に `bash tools/progress.sh show --phase resume --command start` を実行し、出力の全行をそのまま示してください（`/start` は、作業を再開するときの入口です）。この表示が完了時の表示を兼ねるので、`/start` の終わりにもう一度出す必要はありません。出力の最後に示される図（`input/progress.html`）をブラウザで開くと、全工程のどこまで済んだかを一覧できることも伝えます。言い換え・要約はしません（CLAUDE.md の「現在地の表示」）。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する初回案内役です。顧客が迷わず `/ingest-guidelines` → `/confirm-spec` → `/build-pack`（読み取り済みの同梱データがある補助金では、最初の 2 つの代わりに `/select-subsidy`）で対象 spec と書き方メモを整え、その spec を軸に `/intake` へ進めるように、前提、作業順、必要な入力、法務ガードレールを短く確認してください。

このコマンドは、申請書を作るための実作業を始める前のオリエンテーションです。会社情報のヒアリング、募集要項からの spec 化、要件照合、成果物計画、事業計画書セクションの作成、レビュー、機械検証、提出前チェック、振り返りは、後続の slash command で行います。

どの段階でも、いま何をすべきか分からなくなったら `/start` を実行すると、現在の状態と次のコマンドを確認できます。

## 最初に確認すること

1. 顧客が Claude Code 契約者であり、このリポジトリを Claude Code で開いていることを確認してください。
2. このリポジトリは、顧客本人が補助金申請用の事業計画書の叩き台を作るための作業環境であることを説明してください。
3. 公式の募集要項、自社資料、見積書、売上資料、投資計画などの実情報を顧客本人が確認しながら進める前提を伝えてください。
4. 数値や要件は推測しないこと、出典不明の事実や顧客確認が必要な項目には `[要確認]` を付けることを伝えてください。
5. 作業状態は `input/current-application.json` に記録され、`state`、`spec_path`、`chosen_funding` を後続コマンドが引き継ぐことを説明してください。
6. 詳細な手順は `docs/manual.md` にまとまっていることを案内してください。

## 進行中の申請の期限

`input/current-application.json` がある場合は `bash tools/check-spec.sh --resolve-application --current-application input/current-application.json` で spec を解決し、解決できたら `bash tools/check-spec.sh <spec> --gate select` を実行してください。現在地の案内に `INFO: 残り <N> 日` の行と期限に関する WARN をそのまま含めます（期限と無関係な WARN の見せ方は `/confirm-spec` の規律に従います）。gate が FAIL でも案内自体は止めず、有効な申請締切が残っていない場合は締切を過ぎている事実と、公式サイトで現行の公募回を確認する必要を伝えます。その他の FAIL は内容を示し、期限経過と混同しないでください。AI は間に合うかどうかを断定しません。spec が解決できない場合は期限を推測せず `[要確認]` とします。この確認のために状態ファイルを作成・更新しないでください。

## 案内する作業順

次の順番を、顧客が実行できる形で案内してください。補助金の制度定義は spec を正本にし、公式募集要項から確認できない数値や要件は `[要確認]` として残します。

1. 公募要領から読み込む（標準）: `/ingest-guidelines` — 標準の入口です。補助金の種類を問わず使えます。顧客本人が持つ公式募集要項を `input/guidelines/` に置き、draft spec と confirmation 項目を作って `state=spec_draft` にします。
2. `/confirm-spec` — draft spec と募集要項原本を顧客本人が突合確認し、green になってから `state=spec_confirmed` にします。
   - 同梱データを使う（近道）: `/select-subsidy` — 近道です。同梱 `specs/` に、対象補助金・公募回が一致する読み取り済みの confirmed spec がある場合だけ、1 と 2 の代わりに使えます。`input/current-application.json` を `state=spec_confirmed` にします。
3. `/build-pack` — confirmed spec から補助金パックを整え、後続の `/draft-section` と `/review` が参照する書き方メモを作ります。
4. `/intake` — confirmed spec を読み、`eligibility.rules[]` や scoring が参照する会社情報を優先してヒアリングし、`input/company-profile.md` と `input/company-profile.json` を作って `state=intake_done` にします。
5. `/subsidy-fit` — confirmed spec と会社プロフィールを照合し、除外要件、必須要件、加点要素、減点項目、不足準備、狙う枠 `chosen_funding`（特例未決定なら `null`）を `input/current-application.json` に記録します。未決定時は `/subsidy-fit` の「狙う枠を選ぶ」に従います。
6. `/plan-deliverables` — confirmed spec と `chosen_funding` から、AI と作る成果物、人がやること、添付、締切を `input/deliverables.md` に整理します。
7. `/draft-section` — spec の `deliverables[]` / `sections[]` から 1 セクションを選び、`input/drafts/<subsidy_id>/<section_id>.md` に `## 叩き台` を作ります。
8. `/review` — 叩き台の定性レビューを行い、`clause_id`、`quoted_text`、根拠不足、誇張、行政書士法上の作成主体を点検します。
9. `/verify` — `bash tools/check-spec.sh` と `bash tools/check-drafts.sh` を実行し、字数、必須セクション、coverage gaps、`[要確認]`、draft 本文ハッシュを `input/checks/verify-report.md` に記録します。
10. `/finalize` — verify が green で、`draft_bodies_sha256` が最新 draft と一致することを確認し、提出前チェックリストを顧客本人の最終確認に回し、転記用の提出用まとめも生成します。spec の定義で必須と判定されたセクションの draft が欠ける場合は停止します。本人が別に作ると明示したセクションは人の作業として記録しますが、draft が 0 件なら `/finalize` は使えません。`/plan-deliverables` の一覧（`input/deliverables.md`）で提出前の確認をしてください。現在の draft 全件を含み本文ハッシュが一致するレビュー記録 1 件と、その同じファイルの引用照合の合格も必須です。本文修正後は全件を `/review` で再点検してください。
11. `/retrospect` — 提出後または採否判明後に、結果、講評、学び、次回アクションを `knowledge/records/` と `knowledge/lessons/` に残します。

## 入口の選び方

- 標準は公募要領から読み込む入口です。申請したい補助金の公式募集要項を `/ingest-guidelines` で読み込み、読み込み後は `/confirm-spec` で突合確認することを伝えてください。補助金の種類と公募回を問いません。
- 同梱 `specs/` に対象補助金・公募回・様式が一致する confirmed spec があり、顧客本人が公式募集要項と照合して違和感がない場合に限り、近道として同梱データを使う入口（近道）の `/select-subsidy` に進めます。別の公募回、別制度、または同梱 spec と公式資料に差がある可能性がある場合は、公募要領から読み込む入口を使います。
- `/build-pack` は confirmed spec 以降に実行する推奨ステップです。書き方メモは申請書本文ではなく、叩き台作成とレビューの補助資料だと説明してください。
- どちらの場合も、公式募集要項が正です。spec は作業のための構造化ビューであり、顧客本人の確認を置き換えません。

## 育成層

`knowledge/` は、申請結果や講評、次回に活かす学びを顧客本人の repo に残す育成層です。`/retrospect` で `knowledge/records/` と `knowledge/lessons/` を増やすと、次回の `/draft-section` や `/review` が過去の弱点や改善点を参照できます。

将来、顧客本人が自分用の `my-*` commands を `.claude/commands/` に追加する場合も、コアコマンドとは分けて扱ってください。`my-*` commands は顧客固有の運用メモや社内手順を反映するための拡張であり、公式募集要項、spec、`input/current-application.json` の根拠を置き換えるものではありません。

## 顧客に尋ねること

オリエンテーションでは、次の質問だけを行い、回答に応じて次のコマンドを案内してください。ここでは長いヒアリングを始めず、必要なら `/intake` に進めてください。

1. 対象にしたい補助金の公式募集要項（PDF など）は手元にありますか。
2. その募集要項を `/ingest-guidelines` で読み込みますか。同梱 `specs/` に同じ補助金・公募回の読み取り済みデータがある場合は、`/select-subsidy` でそれを使うこともできます。
3. spec 確定後に会社概要、売上、従業員数、投資予定、見積書などの自社資料を `input/` に置く準備はありますか。

## 回答に応じた案内

- 顧客本人の募集要項から spec を作るなら、次に `/ingest-guidelines` を案内し、その後 `/confirm-spec` へ進むことを伝えてください。
- 同梱 `specs/` の読み取り済みデータを使うなら、次に `/select-subsidy` を案内してください。
- `input/current-application.json` がすでにある場合、次に実行するコマンドは、冒頭で示した現在地の表示（道具の出力の `次のコマンド:` と `やり直しが必要:` の行）に従って案内してください。`state` の値から独自に次のコマンドを決めないでください（道具は `state` だけでなく、レビュー記録や検査記録が現在の本文と一致しているかも見ています）。`次にすること:` の行は、コマンドではなく本人が行うことなので、そのまま伝えます。`任意:` の行は未実施の任意の工程の表示で、実行の勧めではありません（同梱の書き方メモがある場合は、不足を補いたいときだけ `/build-pack` を使います。同梱のメモが無い場合は `/intake` の前に作ることを勧めます）。
- まだ対象補助金を選べていない場合は、公式情報源で募集要項、対象者、対象経費、補助率、補助上限、締切を確認してから、`/ingest-guidelines` で spec を作るか、同梱 `specs/` に一致するデータがあればそれを使うよう案内してください。確認できない数値や要件は `[要確認]` として扱ってください。
- 作業全体の流れを知りたい顧客には、`docs/manual.md` を先に読むよう案内してください。

## 出力形式

顧客に対して、次の形式で短く案内してください。

```markdown
# 初回案内

## このキットでできること

## 進め方

1. 公募要領から読み込む（標準）: /ingest-guidelines
2. /confirm-spec
   - 同梱データを使う（近道）: /select-subsidy（1 と 2 の代わり）
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
- `input/current-application.json` がある場合は、途中再開の位置を現在地の表示（道具の出力）で示してください。`state` を読んで独自に判断しません。
- 最後に、迷わなければ手元の募集要項なら `/ingest-guidelines`、同梱 spec なら `/select-subsidy` から始めること、進行中の申請がある場合は現在地の表示が示す次のコマンドへ進むこと、全体像を確認したい場合は `docs/manual.md` を読むことを案内してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/start` は作業開始前の案内に限定し、提出判断や要件充足の確定は行いません。数値、要件、文字数、補助率、補助上限、添付資料、提出期限は公式の募集要項または顧客資料を根拠にし、出典不明の事実には `[要確認]` を付けてください。
