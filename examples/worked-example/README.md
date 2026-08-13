# worked-example

このディレクトリは、`/setup` → `/start` → `/intake` → `/ingest-guidelines` → `/subsidy-fit` → `/plan-deliverables` → `/draft-section` → `/review` → `/verify` → `/finalize` → `/retrospect` の流れを確認するための架空のサンプルです。実在する会社、補助金、募集要項、採択実績、申請条件を示すものではありません。

## このサンプルの位置づけ

- すべて架空のサンプルです。会社名、数値、投資内容、補助金名、要件、期限、採否、講評は実在情報ではありません。
- 実際の数値・要件は、顧客本人が各自の公式募集要項、自社資料、見積書、会計資料で `[要確認]` として確認してください。
- AI は補助・壁打ち・整理役です。作成者は顧客本人であり、申請書の作成代行、代理提出、本人に代わる完成判断は行いません。
- この例は、提出文書の完成版ではなく、spec、confirmation、draft、verify report、retrospect record がどうつながるかを示す教材です。

## ファイル構成

旧フローの読み物:

- `company-profile.sample.md` — `/intake` 後にできる会社プロフィールのサンプル
- `subsidy-fit.sample.md` — `/subsidy-fit` 後にできる適合度メモのサンプル
- `draft-section.sample.md` — `/draft-section` で 1 セクションだけ作った叩き台のサンプル
- `review-note.sample.md` — `/review` で顧客本人が修正すべき点を整理したサンプル

spec 駆動ループのサンプル:

- `spec.sample.json` — 架空補助金を v2 subsidy spec として表した小さな confirmed spec
- `spec.sample.confirmation.json` — `spec.sample.json` の `spec_sha256` に固定された confirmation report
- `pack.json` — 既存 spec/confirmation と書き方メモを束ねる、パック形の合成例
- `notes/review-lens.md` — 架空 spec の clause だけを根拠にした review-lens の書き方メモ例
- `current-application.sample.json` — 対象 spec、選んだ枠、draft hash、`state=verified` を持つ受け渡し状態
- `drafts-sample/current-challenge.md` — `plan-doc/current-challenge` の draft
- `drafts-sample/short-summary.md` — `plan-doc/short-summary` の draft。spec 側の `max_chars=30` を満たす短文例
- `verify-report.sample.md` — `/verify` が作る fenced json header 付きの検証レポート例
- `record.sample.json` — `/retrospect` が `schemas/application-record.schema.json` に沿って残す申請記録例

## 読み方

1. まず `company-profile.sample.md` を読み、顧客の実情報と `[要確認]` の残し方を確認します。
2. `pack/spec.sample.json` と `pack/spec.sample.confirmation.json` を読み、募集要項から作った spec が confirmation と SHA-256 で結び付くことを確認します。
3. `pack/pack.json` と `pack/notes/review-lens.md` を読み、confirmed spec から作った書き方メモが `[clause:]` 引用と SHA-256 台帳で結び付くことを確認します。このパック例もすべて合成データで、実在の制度・企業情報は使っていません。
4. `subsidy-fit.sample.md` と `current-application.sample.json` を読み、confirmed spec、会社プロフィール、`chosen_funding`、状態ファイルが後続コマンドへ渡る形を確認します。
5. `drafts-sample/` の 2 ファイルを読み、frontmatter の `deliverable_id` / `section_id` と `## 叩き台` 以下の本文が spec の section と対応することを確認します。
6. `draft-section.sample.md` と `review-note.sample.md` で、文章化と定性レビューの粒度を確認します。
7. `verify-report.sample.md` を読み、`bash tools/check-spec.sh examples/worked-example/pack/spec.sample.json` と `bash tools/check-drafts.sh examples/worked-example/pack/spec.sample.json examples/worked-example/drafts-sample` の結果が記録される場所を確認します。
8. `record.sample.json` を読み、`/retrospect` が提出後または結果待ちの学びを `knowledge/records/` に残す形を確認します。

実作業では、このサンプルをコピーして使うのではなく、`docs/manual.md` の手順に従って自分の `input/` 配下に実情報を整理してください。サンプルの数値や要件を実際の申請に流用しないでください。

## 検証してみる

このサンプルは、機械検証の形を確認するために次のコマンドが green になるよう作っています。

```bash
bash tools/check-spec.sh examples/worked-example/pack/spec.sample.json
bash tools/check-drafts.sh examples/worked-example/pack/spec.sample.json examples/worked-example/drafts-sample
bash tools/check-pack.sh examples/worked-example/pack
```

実際の申請では、同梱サンプルではなく顧客本人の `input/spec/` と `input/drafts/` を検証してください。機械検証が green でも、募集要項の読み違い、根拠資料不足、表現の誇張、行政書士法上の作成主体の問題は、`/review`、`/finalize`、顧客本人の確認で直します。
