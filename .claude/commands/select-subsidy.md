---
description: 同梱 specs/ から対象補助金の confirmed spec を選び、current-application を spec_confirmed で初期化します。
---

# /select-subsidy

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する、同梱 spec の選択係です。顧客本人が公式募集要項と見比べながら、`specs/<id>/<id>.json` の bundled pack spec または残留互換の `specs/<id>.json` を今回の対象として使えるか確認し、使える場合だけ `input/current-application.json` を `state=spec_confirmed` で初期化してください。

このコマンドは入口Aです。顧客本人が持つ公式募集要項から自分用の spec を作る場合は、入口Bとして `/ingest-guidelines` を使います。会社情報のヒアリングは、対象 spec が決まった後に `/intake` で行います。

## 最初に確認すること

1. 作成者は顧客本人であり、AI は補助・壁打ち・整理役であることを伝えてください。
2. 同梱 `specs/` は作業用の構造化ビューであり、制度そのものの正本は公式の募集要項であることを伝えてください。
3. 顧客本人が、対象補助金名、公募回、様式、締切、対象者、対象経費が自分の手元の公式資料と一致するか確認できる状態か聞いてください。
4. 一致しない、または最新版か不安がある場合は、このコマンドで初期化せず `/ingest-guidelines` で顧客本人の募集要項から `input/spec/` を作るよう案内してください。
5. 既存の `input/current-application.json` がある場合は、別の補助金を上書きしないよう、現在の `subsidy_id`、`spec_path`、`state` を見せてから続行可否を確認してください。
   - `state=spec_draft` の場合は「突合が未完了です。/confirm-spec を実行してください」と案内し、同梱 spec で上書きする前に顧客本人へ確認してください。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
   - `spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合は、パック形を優先するため、`spec_path` を付け替えるか、このコマンドでパック形を再選択するよう案内してください。

## 手順

### 1. 同梱 spec 候補を列挙する

候補の列挙には、次の機械列挙を使ってください（パック優先・重複 ID 検出を機械側で保証します）。

```bash
bash tools/check-spec.sh --list-bundled
```

出力（安定ソート済みの repo 相対 spec パス・1行1件）を候補一覧の正とします。コマンドが失敗した場合（重複 `subsidy_id` 等）は、エラー内容を顧客に示し、手動で候補を推測しないでください。各候補について、少なくとも次を読み取ります。

- `subsidy_id`
- `name`
- `round`
- `spec_version`
- `status`
- `source_documents[]`
- `schedule[]` の主要締切

候補を表示するときは、`status=confirmed` のものだけを入口Aの候補にしてください。`status=draft` のものがあれば、入口Aでは使わず、顧客本人の原本突合が必要であることを説明します。

さらに、候補 spec ごとに締切の有効性を機械判定してください。

```bash
bash tools/check-spec.sh <spec> --gate select
```

gate が失敗した spec（有効な申請締切が残っていない）は、公募回が終了している可能性が高いため、**入口Aの候補から除外**してください。そのうえで、公式サイト（`portal_url`）で現行の公募回を確認し、現行回の公募要領から入口B（`/ingest-guidelines`）で spec を作るよう案内します。gate の判定を AI の推測で上書きしないでください。

### 2. 原本入手

候補 spec に `portal_url` がある場合は、まずその公式ページから公募要領の原本を入手してもらってください。`portal_url` が無い場合、または公式ページから同じ資料に辿れない場合は、顧客本人が持つ公式資料を使って入口B（`/ingest-guidelines`）へ進むよう案内します。

原本ファイルを入手したら、顧客環境で SHA-256 を計算して `source_documents[].sha256` と照合してもらってください。macOS/Linux では次を使えます。

```bash
shasum -a 256 <file>
```

計算結果が `source_documents[].sha256` と一致する場合だけ、入口Aの同梱 spec 候補として次へ進みます。不一致なら版違いとして入口B（`/ingest-guidelines`）へ進み、今回の公式資料から `input/spec/` を作ってください。AI が「一致している」と断定せず、顧客本人が原本とハッシュを見比べた結果を確認してください。

`source_documents[].sha256` が記録されていない資料（版を固定できない Web ページ等）は、ハッシュ照合ができません。その資料は必ず **live で原本を再確認**してもらってください（内容が公開後に変わっている可能性があるため）。

### 3. 公式募集要項との一致を顧客本人に確認する

顧客に、候補 spec の補助金名、公募回、資料名、主要締切が、自分の手元の公式募集要項と一致するか確認してもらってください。AI が「一致している」と断定しないでください。

確認観点:

- 対象補助金名と公募回
- 募集要項または公募要領の版
- 申請締切、事業実施期間、実績報告期限
- 対象者、対象経費、補助率、補助上限
- 申請様式と事業計画書のセクション
- 添付資料、外部発行書類、支援機関確認

どれか 1 つでも不一致または不明があれば、`[要確認]` とし、`/ingest-guidelines` で今回の公式資料から `input/spec/` を作るよう案内してください。

### 4. check-spec を実行する

選んだ bundled spec に対して、可能なら次を実行してください。

```bash
bash tools/check-spec.sh specs/<id>/<id>.json
```

旧同梱平置きしか存在しない補助金では、互換パスとして `bash tools/check-spec.sh specs/<id>.json` を使ってください。ただし同一 `subsidy_id` のパック形が存在する場合は必ず `specs/<id>/<id>.json` を使います。

FAIL が出た場合は `input/current-application.json` を作らず、表示された不整合を直すか、`/ingest-guidelines` で顧客本人の募集要項から spec を作るよう案内してください。

### 5. current-application を spec_confirmed で初期化する

顧客本人が「この同梱 spec を今回の対象として使う」と確認し、check-spec が green であれば、`input/current-application.json` を作成または更新してください。

```json
{
  "subsidy_id": "<spec.subsidy_id>",
  "spec_path": "specs/<id>/<id>.json",
  "spec_version": 1,
  "chosen_funding": null,
  "state": "spec_confirmed",
  "updated_at": "YYYY-MM-DDTHH:MM:SS+09:00"
}
```

`spec_version` は選んだ spec の実際の値を入れてください。`chosen_funding` はまだ `/subsidy-fit` で選んでいないため `null` のままにします。会社情報はまだ聞いていないので、このコマンドでは `input/company-profile.md` や `input/company-profile.json` を作りません。

## 出力形式

顧客には次の形式で短く報告してください。

````markdown
# 同梱 spec 選択結果

## 選んだ spec

| 項目 | 内容 |
| --- | --- |
| subsidy_id |  |
| spec_path | specs/<id>/<id>.json |
| spec_version |  |
| status | confirmed |

## 公式募集要項との確認

## check-spec.sh

```text
（bash tools/check-spec.sh の結果）
```

## current-application

- path: input/current-application.json
- state: spec_confirmed
- chosen_funding: null

## 次に実行するコマンド

`/build-pack`（推奨）または `/intake`
````

## 出力時の注意

- 同梱 spec と公式募集要項が食い違う場合は、必ず公式募集要項を優先してください。
- 補助率、補助上限、締切、対象経費、提出物、文字数は推測せず、spec と公式資料の一致を顧客本人に確認してもらってください。
- `input/current-application.json` がすでに別の補助金を指している場合は、確認なしに上書きしないでください。
- 入口Aで同梱 notes をそのまま使う場合は `/intake` に進めます。新しく notes を作る、または確認済み spec からパックを再生成する場合は `/build-pack` を推奨します。
- 次の `/intake` では、ここで選んだ spec の `eligibility.rules[]` や scoring 項目が参照する会社情報を優先してヒアリングします。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/select-subsidy` は同梱 spec の選択と `current-application.json` の初期化だけを支援します。要件・数値は募集要項が正であり、出典不明の事実や顧客確認が必要な項目には `[要確認]` を付けてください。
