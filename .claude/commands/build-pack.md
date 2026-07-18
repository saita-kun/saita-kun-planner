---
description: confirmed spec から書き方メモを作り、input/spec/<subsidy_id>/ に補助金パックを完成させます。
---

# /build-pack

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する、書き方メモ作成係です。確認済み spec から、審査観点やセクション別の書き方メモを作り、`input/spec/<subsidy_id>/` にまとめてください。

顧客への説明では「書き方メモを作る」と言ってください。`pack.json`、checker、manifest、resolver などの内部機構名は、実行ログやファイル作成手順では扱って構いませんが、顧客向けの本文説明の中心にしないでください。

このコマンドは、申請書本文を作るものではありません。後続の `/draft-section` と `/review` が参照できる制度別の書き方メモを整える作業です。出力先は `input/spec/<subsidy_id>/` のみです。`.claude/commands/`、`schemas/`、`specs/`、`tools/`、`docs/` などのコア層は書き換えないでください。

## 前提チェック

最初に、次を順番に確認してください。満たさない場合は書き方メモを作らず、先行コマンドへ戻します。

1. `input/current-application.json` が存在すること。
   - 存在しない場合は、同梱 spec を使うなら `/select-subsidy`、顧客本人の募集要項から作るなら `/ingest-guidelines` と `/confirm-spec` へ戻るよう案内してください。
2. `state` が `spec_confirmed`、`intake_done`、`fit_done`、`planned`、`drafting`、`verified`、`finalized` のいずれかであること。
   - `state=spec_draft` の場合は「突合が未完了です。/confirm-spec を実行してください」と案内し、書き方メモを作らないでください。
3. `subsidy_id` と `spec_path` が non-null であること。
4. 解決済み spec が存在し、`status=confirmed` であること。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
5. 対応する confirmation report が存在し、`bash tools/check-spec.sh <spec_path>` が green であること。
6. 既存の `input/spec/<subsidy_id>/notes/` または `input/spec/<subsidy_id>/pack.json` がある場合は、上書き前に顧客本人へ確認してください。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で解決してください。

1. `input/spec/<subsidy_id>/<subsidy_id>.json`
2. `input/spec/<subsidy_id>.json`
3. `specs/<subsidy_id>/<subsidy_id>.json`
4. `specs/<subsidy_id>.json`

`input/current-application.json` の `spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先します。`spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合は、パック形を優先するため、`spec_path` の付け替えを案内してください。

書き方メモの最終出力先は必ず `input/spec/<subsidy_id>/` です。解決済み spec が `specs/` または `input/spec/<subsidy_id>.json` にある場合は、顧客本人に確認したうえで、spec と confirmation を `input/spec/<subsidy_id>/<subsidy_id>.json` と `input/spec/<subsidy_id>/<subsidy_id>.confirmation.json` にコピーしてください。コピー後の confirmation は、`spec_path` を新しい spec path に合わせます。`spec_sha256` はコピー後の spec bytes から再計算し、必要なら更新してください。

コピーや更新が終わったら、可能なら `input/current-application.json` の `spec_path` を `input/spec/<subsidy_id>/<subsidy_id>.json` に更新し、`state` は変更せず `updated_at` だけ現在時刻にしてください。

## 作る書き方メモ

`notes/` には、次の 4 種を作ります。内容がないものを無理に作らないでください。

1. `notes/review-lens.md`
   - 審査で見られる観点、除外要件や必須要件の注意、書類全体を見直すときの観点を書きます。
   - spec の `clauses`、`deliverables[].sections[].review_criteria`、mandatory / exclude rules を主な材料にしてください。
2. `notes/scoring-strategy.md`
   - 加点、狙う枠、上乗せ、審査で強調しやすい接続を整理します。
   - spec の `bonus_items[]`、`eligibility.rules[]` の `kind=scoring`、`funding.add_ons[]`、`funding.combinations[]` を主な材料にしてください。
3. `notes/sections/<deliverable_id>--<section_id>.md`
   - `produced_by=ai_draftable` の成果物について、内容がある section だけ作ります。
   - spec の `sections[].guidance`、`review_criteria`、`source_clauses`、関連する `clauses` を材料にしてください。
4. `notes/examples.md`
   - 任意です。公式資料や顧客本人が提示した出典付き事例がある場合だけ作ってください。
   - 出典のない事例、実在企業を連想させる事例、AI が作ったそれらしい事例は書かないでください。

## notes の限定 frontmatter

各 note は必ず先頭に限定 frontmatter を置いてください。ネスト、リスト、複数行値は使わず、`key: value` のスカラー行だけにします。

`review-lens`:

```markdown
---
subsidy_id: <subsidy_id>
kind: review-lens
---
```

`scoring-strategy`:

```markdown
---
subsidy_id: <subsidy_id>
kind: scoring-strategy
---
```

`section-note`:

```markdown
---
subsidy_id: <subsidy_id>
kind: section-note
deliverable_id: <deliverable_id>
section_id: <section_id>
---
```

`examples`:

```markdown
---
subsidy_id: <subsidy_id>
kind: examples
---
```

## 境界規律

各 note の本文冒頭に、次の趣旨を明記してください。

> 境界規律: clause 引用のない記述は一般知見扱いであり、数値・要件の根拠には使いません。数値・要件の根拠は spec の clauses のみです。

制度事実、数値、締切、対象経費、補助率、補助上限、文字数、様式、添付資料に触れる行には、同じ行に `[clause: <clause_id>]` を付けてください。根拠が spec の clauses にないが顧客確認が必要な行は `[要確認]` を付けてください。`review-lens`、`scoring-strategy`、各 `section-note` は、少なくとも 1 つの `[clause: <clause_id>]` を含めます。

`[clause: <clause_id>]` の `<clause_id>` は、spec の `clauses[].clause_id` に実在する ID だけを使ってください。要約した記憶や過去公募の知識を、条文根拠のように扱わないでください。

## 作成手順

### 1. pack dir を準備する

`input/spec/<subsidy_id>/` を作り、解決済み spec と confirmation をこのディレクトリへそろえてください。ファイル名は次の形にします。

- `input/spec/<subsidy_id>/<subsidy_id>.json`
- `input/spec/<subsidy_id>/<subsidy_id>.confirmation.json`
- `input/spec/<subsidy_id>/notes/`
- `input/spec/<subsidy_id>/pack.json`

既存ファイルがある場合は、差分の要点を見せてから上書き可否を確認してください。

### 2. spec から材料を棚卸しする

次を読み、書き方メモに使う材料を一覧化してください。

- `clauses[]`: 制度事実の真実源
- `eligibility.rules[]`: exclude / mandatory / scoring の区分、`text`、`source_clauses`
- `funding.base_award`、`funding.add_ons[]`、`funding.combinations[]`
- `bonus_items[]`
- `deliverables[]` と `sections[]`: `guidance`、`review_criteria`、`source_clauses`
- `schedule[]`: hard deadline や相対期限

材料一覧には、必ず対応する `clause_id` を付けてください。`source_clauses` がない制度事実は根拠不足として `[要確認]` にし、notes へ断定的に入れないでください。

### 3. review-lens を作る

`notes/review-lens.md` には、後続の `/review` が使う観点を入れます。

含める観点:

- 作成主体と提出判断を顧客本人に戻す観点
- 除外要件、必須要件、対象外経費、添付漏れなどの高リスク観点
- section の `review_criteria` から見える審査観点
- `schedule[]` の hard deadline に関する注意
- 誇張、根拠不足、`[要確認]` の扱い

制度事実の行には `[clause: <clause_id>]` を付けてください。

### 4. scoring-strategy を作る

`notes/scoring-strategy.md` には、加点や狙う枠の考え方を整理します。

含める観点:

- `bonus_items[]` の名称、条件、根拠 clause
- `kind=scoring` の rule
- `funding.add_ons[]` と `funding.combinations[]` の注意
- 顧客本人が `/subsidy-fit` で確認すべき不足準備

採択可能性、補助金額、採択率、効果見込みは推測しないでください。spec に根拠がない加点の断定は `[要確認]` にします。

### 5. section-note を作る

`produced_by=ai_draftable` の各 deliverable について、`sections[]` を見ます。`guidance`、`review_criteria`、`source_clauses` のいずれかに実質的な内容がある section だけ、`notes/sections/<deliverable_id>--<section_id>.md` を作成してください。

section-note には、次を入れてください。

- この section で最初に確認すること
- 課題、解決、実現性、効果、数値根拠のどこを強く見るべきか
- `guidance` と `review_criteria` の要点
- 使える clause と、使ってはいけない推測の境界
- 顧客本人が資料で埋めるべき箇所

section-note は、叩き台本文ではありません。後続の `/draft-section` が骨子を作る前に読む書き方メモです。

### 6. examples は任意で作る

`notes/examples.md` は、公式資料または顧客本人が提示した出典付きの例がある場合だけ作ってください。各事例には `source:` 行を置きます。

```markdown
## 事例名

source: <公式資料名、顧客提示資料名、または該当 clause>

- 使える観点:
- 使ってはいけない推測:
```

出典がない場合は `examples.md` を作らず、`pack.json` の `notes` にも入れないでください。

### 7. pack.json を生成する

`pack.json` には、spec、confirmation、作成した notes の sha256 を機械記入してください。`built_by` は `applicant`、`built_at` は offset 付き ISO8601 にします。notes の `derived_from_spec_sha256` は、現在の spec bytes の SHA-256 と同じ値にします。

形は次です。

```json
{
  "pack_version": 1,
  "subsidy_id": "<subsidy_id>",
  "spec_version": 1,
  "built_at": "2026-07-05T12:34:56+09:00",
  "built_by": "applicant",
  "spec": {
    "path": "<subsidy_id>.json",
    "sha256": "<sha256>"
  },
  "confirmation": {
    "path": "<subsidy_id>.confirmation.json",
    "sha256": "<sha256>"
  },
  "notes": [
    {
      "path": "notes/review-lens.md",
      "kind": "review-lens",
      "sha256": "<sha256>",
      "derived_from_spec_sha256": "<spec_sha256>"
    }
  ]
}
```

sha256 の計算は、顧客環境で使える標準ツールを使ってください。`python3` が使える場合は標準ライブラリだけで計算できます。

```bash
python3 -c 'import hashlib, pathlib, sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' input/spec/<subsidy_id>/<subsidy_id>.json
```

### 8. check-pack を green にする

最後に、必ず次を実行してください。

```bash
bash tools/check-pack.sh input/spec/<subsidy_id>/
```

FAIL が出た場合は、次のどれかを直してから再実行してください。

- `pack.json` の必須キー、path、sha256、`derived_from_spec_sha256`
- confirmation の `spec_sha256` と `spec_path`
- note frontmatter の `subsidy_id` / `kind` / `deliverable_id` / `section_id`
- 実在しない `[clause: <clause_id>]`
- clause 引用がない `review-lens`、`scoring-strategy`、`section-note`
- 数値・制度事実らしい行に `[clause:]` も `[要確認]` もない WARN

`check-pack` が green になるまで、書き方メモを完成扱いにしないでください。WARN だけの場合も、顧客本人に残す理由を説明し、直せるものは直してください。

## 出力形式

顧客には、次の形で短く報告してください。

````markdown
# 書き方メモ作成結果

## 作成した場所

- input/spec/<subsidy_id>/

## 作成した書き方メモ

| kind | path | 参照した主な clause |
| --- | --- | --- |
| review-lens | notes/review-lens.md |  |
| scoring-strategy | notes/scoring-strategy.md |  |
| section-note | notes/sections/<deliverable_id>--<section_id>.md |  |

## check-pack

```text
（bash tools/check-pack.sh input/spec/<subsidy_id>/ の結果）
```

## 次に実行するコマンド

`/intake`、または作業が進んでいる場合は `/draft-section` / `/review`
````

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。

数値は推測しないでください。補助率、補助上限、対象経費、締切、文字数、添付資料、加点項目、採択可能性、効果見込みは、顧客資料または公式の募集要項で確認できる範囲だけ扱います。要件・数値は募集要項が正です。原本で確認できない制度事実、出典不明の事実、顧客確認が必要な判断には `[要確認]` を付けてください。

書き方メモは、事業計画書本文ではありません。本文作成、内容確定、提出判断は顧客本人が行います。
