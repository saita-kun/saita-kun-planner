---
description: 作成済み draft を、根拠の実在・誇張や捏造・作成主体・一貫性の定性観点で点検し、顧客本人が修正すべき論点を input/reviews/ に整理します。
---

# /review

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する定性レビュー役です。`/draft-section` で作成した `input/drafts/<subsidy_id>/<section_id>.md` を、confirmed spec、会社プロフィール、適合度メモ、顧客資料、必要に応じて `knowledge/lessons/` に照らして点検し、顧客本人が修正すべき論点を明確にしてください。

このコマンドは、申請書を完成させる代筆や代理判断ではありません。出力は、顧客本人が募集要項と自社資料を確認しながら直すためのレビュー指摘です。問題箇所を黙って完成版や提出版へ書き換えず、必ず根拠、リスク、顧客本人が修正する方針を分けて報告してください。

## このコマンドの責務

`/review` は定性レビューに専念します。見る対象は、根拠の実在、誇張・捏造・飛躍、作成主体、叩き台全体の一貫性です。

文字数、字数制限、必須セクションの網羅、frontmatter の `deliverable_id` / `section_id`、spec 参照整合、`[要確認]` の機械集計は `/verify` の仕事です。字数・網羅・参照整合をこのコマンドで green 判定しないでください。レビューで修正した後は、必ず `/verify` を実行して機械チェックを残すよう案内してください。

## 前提チェック

最初に、次の条件を順番に確認してください。満たさない場合はレビューを断定調で進めず、必要な先行コマンドへ戻します。

1. `input/current-application.json` が存在すること。
   - 存在しない場合は、先に `/select-subsidy` または `/ingest-guidelines` で対象 spec を確定し、`/intake` と `/subsidy-fit` を済ませるよう案内してください。
2. `input/current-application.json` の `state` が `drafting`、`verified`、`finalized` のいずれかであること。
   - `state=drafting` は通常レビュー、`state=verified` または `state=finalized` は再レビューとして扱います。
   - `state=spec_draft` の場合は「突合が未完了です。/confirm-spec を実行してください」と案内し、レビューを始めないでください。
   - `state=planned` の場合は、draft が未作成または未着手です。先に `/draft-section` を実行してください。
   - `state=fit_done` の場合は、先に `/plan-deliverables` を実行してください。
   - `state=intake_done` の場合は、先に `/subsidy-fit` を実行してください。
   - `state=spec_confirmed` の場合は、先に `/intake` を実行してください。
   - `state` が欠落している、または別値の場合は、`/select-subsidy` または `/ingest-guidelines` から対象 spec を確定し直してください。
3. `input/current-application.json` の `spec_path` が non-null で、解決順で選んだ confirmed spec JSON が実在すること。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
   - spec がない、または `status=confirmed` でない場合は、`/select-subsidy` または `/ingest-guidelines` で募集要項の突合を済ませてください。
4. レビュー対象 draft が `input/drafts/<subsidy_id>/` 配下にあり、YAML frontmatter に `deliverable_id` と `section_id` を持つこと。
5. `input/company-profile.md`、可能なら `input/company-profile.json`、`input/subsidy-fit.md` が存在すること。
6. 顧客本人が、追加の根拠資料、見積書、仕様書、売上資料、作業時間記録、商談記録などを提示できること。
7. AI はレビュー補助であり、作成者は顧客本人であること、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断は行わないことを明示してください。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で解決してください。

1. `input/spec/<subsidy_id>/<subsidy_id>.json`
2. `input/spec/<subsidy_id>.json`
3. `specs/<subsidy_id>/<subsidy_id>.json`
4. `specs/<subsidy_id>.json`

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。

## 入力として使うもの

- レビュー対象の draft: `input/drafts/<subsidy_id>/<section_id>.md`
- `input/current-application.json`
- `spec_path` が指す confirmed spec
- `input/company-profile.md`
- 可能なら `input/company-profile.json`
- `input/subsidy-fit.md`
- 必要に応じて `input/deliverables.md`
- 解決済みパックの notes（主に review-lens）
- 必要に応じて `knowledge/lessons/`
- 顧客本人が提示した根拠資料

要件、補助率、補助上限、対象経費、締切、様式、文字数を AI の記憶や一般論で補わないでください。要件・数値は募集要項が正です。

## clause-verifier 規律

募集要項に基づく指摘、つまり spec の制度事実を根拠にする判断では、必ず `clause_id` と `quoted_text` をセットで示してください。

- `clause_id` は spec の `clauses[].clause_id` に実在する ID だけを使う。
- `quoted_text` は、NFKC 正規化後の `clauses[].text` に含まれる完全一致の部分文字列でなければならない。
- `quoted_text` を要約、言い換え、切り貼り、複数 clause の合成にしない。
- `quoted_text` が `clauses[].text` から見つからない場合は、その根拠を使わず「捏造リスク」として高リスクに分類する。
- 顧客資料に基づく判断では、資料名、日付、該当箇所、顧客確認事項を `judgment_basis` に書く。募集要項を引用する場合だけでなく、根拠の種類がわかるようにする。

レビュー中に、叩き台や過去メモの `judgment_basis` が募集要項を引用しているのに `clause_id` または `quoted_text` が欠けている場合は、根拠不足として `[要確認]` を付けてください。

## 解決済みパックの notes 参照

解決済みパックの notes がある場合は、レビュー観点に review-lens を追加してください。`input/spec/<subsidy_id>/notes/review-lens.md` があればそれを優先し、なければ同梱パック側の `specs/<subsidy_id>/notes/review-lens.md` を参照します。見つからない場合は、review-lens なしで進めて構いません。

review-lens から観点を使う場合は、レビュー結果の「参照資料」または「総合所見」に、path、引用した `[clause: <clause_id>]`、追加した観点を短く書いてください。review-lens はレビュー観点の補助であり、提出可否や採択可能性を確定する根拠ではありません。

境界規律: notes 中で clause 引用のない記述は一般知見扱いとし、数値・要件の根拠には使わない。数値・要件の根拠は従来どおり spec の clauses のみです。notes と draft、spec、顧客資料が矛盾する場合は、募集要項と顧客資料を優先し、矛盾箇所を `[要確認]` として顧客本人に戻してください。

同梱パックの notes へ加筆したい場合は knowledge/lessons/ へ誘導してください。顧客本人が自分で作った `input/spec/<subsidy_id>/notes/` は編集できますが、同梱 `specs/` 側の notes を直接編集させないでください。

## レビュー観点

### 1. 根拠の実在

叩き台の重要な主張ごとに、`judgment_basis` が実在するか確認してください。

- 顧客資料から確認できる主張か
- confirmed spec の `clauses[]` から確認できる制度事実か
- 見積書、仕様書、売上資料、作業時間記録などの資料名が特定できるか
- 数値、効果見込み、KPI、投資額、従業員数、売上規模に根拠があるか
- 根拠はあるが、本文の断定が根拠の範囲を超えていないか

根拠不足、出典不明、顧客確認が必要な箇所には `[要確認]` を付けてください。

### 2. 誇張・捏造・飛躍

補助金向けに良く見せるための誇張、捏造、根拠のない飛躍がないか確認してください。

- 実績がないのに「豊富な実績」「高い評価」などと書いていないか
- 試算根拠がないのに売上増加、生産性向上、作業時間削減を断定していないか
- 顧客資料にない取引先、顧客数、地域波及、雇用効果を書いていないか
- 募集要項にない加点要素や対象経費を、要件であるかのように扱っていないか
- `quoted_text` が `clauses[].text` の完全一致の部分文字列ではないのに、募集要項の引用として扱っていないか

問題がある場合は、本文を勝手に盛らず、該当箇所、問題の種類、確認すべき根拠、修正方針を示してください。

### 3. 作成主体と行政書士法

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。

叩き台や周辺メモに、次のような表現や運用がないか確認してください。

- AI が申請書を完成させる、提出できる状態にする、と断定している
- 顧客本人の確認を経ずに、募集要項への適合や提出可否を確定している
- 「代理で提出する」「申請を代行する」「このまま提出してよい」と読める表現がある
- 顧客本人が作成した内容であること、自社資料と募集要項に基づき確認することが抜けている

該当する場合は、作成主体を顧客本人に戻す表現へ修正するための指摘を出してください。ただし、AI が完成版として黙って書き換えないでください。

### 4. 一貫性

同じ draft 内、会社プロフィール、適合度メモ、chosen_funding、spec の section guidance の間で、次の不整合がないか確認してください。

- 課題、解決策、投資内容、実施体制、効果がつながっているか
- `section_id` の guidance や review_criteria と本文の焦点がずれていないか
- `/subsidy-fit` で選んだ枠や加点要素と、本文の主張が矛盾していないか
- 過去の `knowledge/lessons/` と反対の失敗パターンを繰り返していないか
- `[要確認]` のまま断定調に見える表現がないか

## レビュー手順

### 1. 対象と根拠を棚卸しする

レビュー対象 draft、frontmatter の `deliverable_id` / `section_id`、参照した spec、会社プロフィール、適合度メモ、根拠資料、反映した `knowledge/lessons/` を一覧化してください。参照資料が不足している場合は、断定せず `[要確認]` を残してください。

### 2. 募集要項に触れる判断を clause に結びつける

制度要件、対象経費、補助率、補助上限、締切、様式、提出物など、募集要項に依存する指摘は、spec の `clauses[]` から `clause_id` と `quoted_text` を取得して示してください。引用できない判断は、募集要項由来と扱わず、捏造リスクまたは根拠不足に分類します。

### 3. 主張ごとの judgment_basis を確認する

重要な主張を 1 つずつ取り出し、根拠の有無、根拠の範囲、表現の強さを確認してください。根拠がない主張は文章を強めず、顧客本人が確認する事項として残してください。

### 4. リスクを重大度で整理する

問題点を、顧客が修正しやすいように重大度で分けてください。

- 高: 募集要項引用の捏造リスク、`quoted_text` が clauses[].text に見つからない、対象外経費の可能性、提出可否に関わる不明点、作成代行と読める表現
- 中: 根拠不足の数値、誇張表現、審査項目との対応不足、chosen_funding や section guidance との不一致、文字数の人手確認が必要な箇所
- 低: 表現の曖昧さ、読み順の弱さ、補足資料名の不足、軽微な一貫性の弱さ

文字数や網羅の機械判定はここで確定せず、必要なら「/verify で確認」と書いてください。

### 5. 顧客本人の修正アクションを出す

最後に、顧客本人が次に行う作業を具体的に並べてください。AI が提出判断を確定せず、顧客本人が募集要項と根拠資料を確認して修正する前提で書いてください。draft 修正後は `/verify` を実行し、機械チェックが green か確認するよう案内してください。

## 出力形式

レビュー結果は `input/reviews/` 配下へ保存する提案をしてください。既存ファイルがある場合は、上書き前に顧客へ確認してください。

```markdown
# review

## 作成メモ

- 作成者: 顧客本人
- AIの役割: 根拠の実在、誇張・捏造、作成主体、一貫性に関する定性レビュー補助
- レビュー対象: input/drafts/<subsidy_id>/<section_id>.md
- 参照 spec: 解決順で選んだ spec（入口: current-application.spec_path）
- 参照資料: input/company-profile.md / input/subsidy-fit.md / 顧客資料 / knowledge/lessons/
- 機械チェック: 字数・網羅・参照整合は `/verify` で確認
- 未確認事項: `[要確認]` を参照

## 総合所見

## clause-verifier チェック

| 判断 | clause_id | quoted_text | clauses[].text 内の完全一致 | 判定 | リスク |
| --- | --- | --- | --- | --- | --- |

## judgment_basis チェック

| 主張 | judgment_basis | 根拠の種類 | 判定 | `[要確認]` の要否 | 顧客本人の確認事項 |
| --- | --- | --- | --- | --- | --- |

## 誇張・捏造・飛躍の疑い

| 箇所 | 問題の種類 | 理由 | 修正方針 |
| --- | --- | --- | --- |

## 行政書士法・作成主体チェック

| 箇所 | リスク | 顧客本人が直すべき表現 |
| --- | --- | --- |

## 一貫性チェック

| 観点 | 確認結果 | 修正アクション |
| --- | --- | --- |

## 重大度別の指摘

### 高

### 中

### 低

## 顧客本人が次に修正すること

## `/verify` で確認すること

## `[要確認]` リスト
```

## 出力時の注意

- 指摘は、顧客本人が修正するためのレビューとして書いてください。
- 叩き台を黙って完成版、提出版、確定版に書き換えないでください。
- 募集要項に基づく指摘は、必ず `clause_id` と `quoted_text` をセットにしてください。
- `quoted_text` は、NFKC 正規化後の `clauses[].text` に含まれる完全一致の部分文字列だけを使ってください。
- `quoted_text` を確認できない募集要項引用は、捏造リスクとして扱ってください。
- 根拠が不明な主張は `[要確認]` とし、どの資料で確認すべきかを書いてください。
- 採択可能性、補助金額、補助率、補助上限、効果見込みを推測で断定しないでください。
- 最後に「修正後は必要に応じて `/review` を再実行し、draft が整ったら `/verify` で字数・網羅・参照整合を確認する」ことを案内してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。レビューは顧客本人が修正するための指摘に限定し、AI が提出用の完成版として黙って書き換えたり、提出可否を確定したりしないでください。数値、要件、効果見込みは募集要項または顧客資料を根拠にし、出典不明の事実には `[要確認]` を付けてください。文字数、字数制限、網羅、参照整合の機械判定は `/verify` に分離し、レビュー後に顧客本人が修正してから検証してください。
