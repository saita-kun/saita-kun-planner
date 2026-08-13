# 同梱 spec の扱い

`specs/` は、補助金ごとの制度定義を v2 schema で構造化した **同梱 spec** の置き場です。同梱 spec は、募集要項の本文、締切、対象者、対象経費、提出物、審査観点、条文根拠を Claude Code が機械的に参照できるようにした JSON です。

## 同梱 spec の鮮度（原本突合の記録）

提供側確認済み（provider confirmed）の同梱パックについて、原本突合の記録を明示します。制度の正本は常に公式の募集要項であり、公募回が変わると下記は古くなります。作業前に `bash tools/check-spec.sh <spec> --gate select` で締切の有効性を必ず確認してください。

| spec id | 公募回 | 個別項目の突合日（範囲・件数） | provider 最終確認日 | 版固定資料数 | 出典 |
| --- | --- | --- | --- | --- | --- |
| jizokuka-20 | 第20回公募 | 2026-07-05〜2026-07-05（confirmed 67 / na 0） | 2026-07-10 | sha256 固定 1 / 全 2（live 再確認必須） | [中小企業庁 公募要領ページ](https://www.chusho.meti.go.jp/koukai/hojyokin/kobo/2026/260527002.html) |

- 「個別項目の突合日」は confirmation の `items[].confirmed_at` の範囲です。単一の日付で「全体がその日に検証された」ことを意味しません。
- 「版固定資料数」は `source_documents[].sha256` が記録されている資料の数です。sha256 固定できない Web 資料（例: `mirasapo-guide`）は、内容が変わり得るため **live 再確認必須**です。`/select-subsidy` の確認手順で原本を直接確認してください。

このディレクトリの spec は、顧客が補助金申請用の事業計画書の叩き台を自分で作るための補助資料です。AI は spec を読んで整理や文章案作成を支援しますが、作成者は顧客本人であり、提出可否の判断や提出行為は顧客本人が行います。公式の募集要項と spec が食い違う場合は、必ず公式の募集要項を優先してください。

同梱するパックは、代表的・利用の多い補助金の少数に絞る方針です（全補助金の同梱はしません）。同梱されていない補助金は `/ingest-guidelines` → `/confirm-spec` → `/build-pack` で自分のパックを作れます。パック配布の拡充方向は [ROADMAP.md](../ROADMAP.md) を参照してください。

## 優先順位

同じ `subsidy_id` の spec が複数ある場合、優先順位は次の通りです。

1. `input/spec/<subsidy_id>/` — 顧客本人が作った補助金パック。spec、confirmation、書き方メモを同じディレクトリで扱います。
2. `input/spec/<subsidy_id>.json` — 顧客本人が作った旧平置き spec。後方互換として読みます。
3. `specs/<subsidy_id>/` — 提供側が確認済みとして同梱する補助金パック。
4. `specs/<subsidy_id>.json` — 同梱の旧平置き spec。移行期や core 更新後の残留ファイルだけを想定した後方互換です。

`input/spec/` は顧客側で作成・確認した spec または補助金パックの置き場です。顧客が最新の募集要項を確認して `input/spec/` に置いた場合は、同梱済みの `specs/` よりも `input/spec/` を正として扱います。これは、募集要項の改定や地域版の差分を顧客の手元で反映できるようにするためです。

`specs/` の同梱パックは、初期状態で使える参照用の制度定義です。まだ `input/spec/` に顧客確認済み spec がないときの入口として使います。同一 `subsidy_id` で `specs/<subsidy_id>/` と `specs/<subsidy_id>.json` の両方が存在する場合は、必ずパック形 `specs/<subsidy_id>/<subsidy_id>.json` を採用してください。

## 残留平置き spec の扱い

core 更新では、manifest から外れた旧ファイルを自動削除しません。そのため、過去の利用者環境には `specs/<subsidy_id>.json` と `specs/<subsidy_id>.confirmation.json` が残ることがあります。resolver はパック形を優先するため、残留平置き spec は通常の作業では無視されます。混乱を避けたい場合だけ、顧客本人が内容を確認したうえで旧平置きファイルを手動削除してください。

## 原本の入手と版一致の確認

同梱 spec に `portal_url` がある場合は、その公式ページを入口にして公募要領の原本を入手してください。たとえば `jizokuka-20` の `portal_url` は中小企業庁の第20回公募要領公開ページで、商工会議所地区と商工会地区の配布ページへ辿るための親ページです。

原本ファイルを入手したら、手元で SHA-256 を計算し、spec の `source_documents[].sha256` と一致するか確認してください。macOS/Linux では次を使えます。

```bash
shasum -a 256 <file>
```

ハッシュが一致する場合だけ、同梱 spec と同じ原本版として扱います。不一致の場合は、配布ページや公募要領の版が違う可能性があるため、入口Bの `/ingest-guidelines` で顧客本人の原本から `input/spec/` を作ってください。

小規模事業者持続化補助金は、商工会議所地区と商工会地区で配布ページが別系統になることがあります。親ページ、地区別ページ、PDF 本体のどれを見ているかを区別し、最終的には `source_documents[].sha256` と原本ファイルのハッシュ一致を優先してください。

## confirmation report

各 spec には、対応する confirmation report を置きます。

- spec: `specs/jizokuka-20/jizokuka-20.json`
- confirmation report: `specs/jizokuka-20/jizokuka-20.confirmation.json`

confirmation report は、spec の各フィールドがどの条文・原本ページに基づくかを確認した記録です。`spec_sha256` には、確認時点の spec ファイル本体の SHA-256 が入ります。spec を後から編集すると SHA-256 が変わるため、古い confirmation report は stale とみなします。再確認せずに `status=confirmed` のまま使わないでください。

同梱 spec は提供側が確認済みのため、confirmation report の `confirmed_by` は `provider` です。顧客が `input/spec/` に自分で作った spec を置く場合は、原本と突合したうえで confirmation report を作り、確認者を `applicant` として扱います。

## 同梱ファイル

- [jizokuka-20/jizokuka-20.json](jizokuka-20/jizokuka-20.json) — 小規模事業者持続化補助金 第20回公募の v2 spec
- [jizokuka-20/jizokuka-20.confirmation.json](jizokuka-20/jizokuka-20.confirmation.json) — 上記 spec の provider confirmation report
- [jizokuka-20/pack.json](jizokuka-20/pack.json) — spec、confirmation、書き方メモの sha256 台帳
- [jizokuka-20/notes/review-lens.md](jizokuka-20/notes/review-lens.md) — 審査観点の書き方メモ
- [jizokuka-20/notes/scoring-strategy.md](jizokuka-20/notes/scoring-strategy.md) — 特例・加点の確認観点
- [subsidy-spec.schema.json](../schemas/subsidy-spec.schema.json) — 制度定義 spec の正本スキーマ
- [company-profile.schema.json](../schemas/company-profile.schema.json) — 顧客企業情報の機械照合用スキーマ
- [application-record.schema.json](../schemas/application-record.schema.json) — 採否・学びを残す育成層 record のスキーマ
- [taxonomy-v1.json](../schemas/taxonomy-v1.json) — 補助金カテゴリ taxonomy

設計上の位置づけは [docs/design/harness-ingest-loop.md](../docs/design/harness-ingest-loop.md) の「3. スキーマ設計」を参照してください。
