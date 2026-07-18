---
description: confirmed spec と drafts を機械検証し、draft 本文ハッシュ付きの verify-report を input/checks/ に作成します。
---

# /verify

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する機械検証係です。確認済み spec と `input/drafts/<subsidy_id>/` の draft を検査し、`input/checks/verify-report.md` に機械可読な結果と人間が読める要約を保存してください。

このコマンドの目的は、`/review` で直した draft が、spec の構造、字数制限、必要セクション、`[要確認]` 残数の観点で機械的に点検済みであることを記録することです。申請書本文の内容を完成判断したり、提出可否を代わりに決めたりしません。

## 使う場面

- `/draft-section` と `/review` を実行し、提出物の draft が `input/drafts/<subsidy_id>/` にそろってきたとき
- `/finalize` に進む前に、spec と draft の機械チェックを残したいとき
- draft を直した後、以前の検証結果が古くなっていないか確認したいとき

出力先は `input/` のみです。`input/checks/verify-report.md` と、両方の検査が green の場合に限る `input/current-application.json` の状態更新以外は変更しないでください。`.claude/commands/`、`schemas/`、`specs/`、`tools/` などのコア層は書き換えないでください。

## 前提チェック

最初に、次の条件を順番に確認してください。条件を満たさない場合でも、可能な範囲で `input/checks/verify-report.md` に fail と理由を残し、`state=verified` にはしません。

1. `input/current-application.json` が存在すること。
   - 存在しない場合は、対象補助金と spec が未確定です。同梱 spec を使うなら `/select-subsidy`、顧客本人の募集要項から作るなら `/ingest-guidelines` へ戻るよう案内してください。
2. `input/current-application.json` の `state` が `drafting` または `verified` であること。
   - `state=drafting` は初回検証、`state=verified` は draft 修正なしの再検証として扱います。
   - `state=spec_draft` の場合は「突合が未完了です。/confirm-spec を実行してください」と案内し、`state=verified` にはしないでください。
   - `state=planned` の場合は、draft が未作成または未着手です。先に `/draft-section` を実行してください。
   - `state=fit_done` の場合は、先に `/plan-deliverables` を実行してください。
   - `state=intake_done` の場合は、先に `/subsidy-fit` を実行してください。
   - `state=spec_confirmed` の場合は、先に `/intake` を実行してください。
   - `state` が欠落している、または別値の場合は、`/select-subsidy` または `/ingest-guidelines` から対象 spec を確定し直してください。
3. `input/current-application.json` の `spec_path` が non-null で、解決順で選んだ spec JSON が実在すること。
   - `spec_path` が null または存在しない場合は、`/ingest-guidelines` または `/select-subsidy` からやり直してください。
4. `input/current-application.json` の `subsidy_id` が non-null であること。
5. draft ディレクトリ `input/drafts/<subsidy_id>/` が存在し、少なくとも 1 つの `*.md` を含むこと。
   - draft がない場合は、先に `/draft-section` で作成してください。
6. spec の `subsidy_id` と `current-application.json` の `subsidy_id` が一致すること。
7. spec の `status` が `confirmed` であること。
   - spec_confirmed 以降で `spec_path` の spec が `status=draft` の場合は、confirmation が未昇格または stale です。`/confirm-spec` で再突合してください。
   - `status=draft` の spec は検証対象にせず、confirmation report で原本突合を済ませてください。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で解決してください。

1. `input/spec/<subsidy_id>/<subsidy_id>.json`
2. `input/spec/<subsidy_id>.json`
3. `specs/<subsidy_id>/<subsidy_id>.json`
4. `specs/<subsidy_id>.json`

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。

`current-application.json` から値を取り出すときは、外部依存を使わず `python3` 標準ライブラリで行ってください。

```bash
python3 -c 'import json, sys; data=json.load(open("input/current-application.json", encoding="utf-8")); print(data.get("spec_path") or ""); print(data.get("subsidy_id") or "")'
```

## 実行する検査

### 1. spec を検査する

`spec_path` が指すファイルに対して、必ず次を実行してください。

```bash
bash tools/check-spec.sh <spec>
```

終了コードが 0 なら `spec_check` は `green`、0 以外なら `fail` です。FAIL 行は `verify-report.md` の人間向け要約にそのまま載せてください。spec が fail の場合は、draft が整っていても `state=verified` にしないでください。

あわせて、検査したその時点の spec bytes から `spec_sha256` を計算し、spec 内の `spec_version` と `spec_path` と一緒に `verify-report.md` の先頭 json に記録してください。これにより、`/verify` 後に spec や confirmation が更新された状態で `/finalize` へ進むことを防ぎます。

```bash
python3 -c 'import hashlib,json,pathlib,sys; p=pathlib.Path(sys.argv[1]); data=json.load(open(p, encoding="utf-8")); print(str(p)); print(data.get("spec_version")); print(hashlib.sha256(p.read_bytes()).hexdigest())' <spec>
```

### 2. draft を検査する

次を実行してください。

```bash
bash tools/check-drafts.sh <spec> input/drafts/<subsidy_id>/
```

終了コードが 0 なら `draft_check` は `green`、0 以外なら `fail` です。WARN 行は coverage gaps、INFO 行は `[要確認]` total として `verify-report.md` の要約に載せてください。WARN は draft_check を fail にしませんが、顧客本人が不足セクションを確認できるように残してください。

### 3. draft 本文ハッシュを計算する

`draft_bodies_sha256` は、`tools/check-drafts.sh` と同じ本文抽出・正規化ルールで計算してください。

- 対象ファイルは `input/drafts/<subsidy_id>/` 直下の `*.md`
- ファイルは path 昇順で並べる
- 各ファイルの本文領域は、最初の `## 叩き台` 見出しより下から、次の同階層 `## ` 見出しまたは EOF まで
- 本文領域の各行は前後空白を除去し、改行を取り除いて連結する
- 連結後に NFKC 正規化する
- 各ファイルの正規化済み本文を `\n---\n` で結合し、その UTF-8 bytes の SHA-256 を取る

ハッシュ計算は、`tools/check-drafts.sh` と同じ本文抽出ロジックを使う `tools/draft-hash.sh` を呼び出してください。`<spec>` と `input/drafts/<subsidy_id>/` は実際の path に置き換えます。

```bash
bash tools/draft-hash.sh <spec> input/drafts/<subsidy_id>/
```

このコマンドは成功時に 64 桁 hex を 1 行だけ出します。非 0 で終了した場合は、`draft_check=fail` として扱い、本文抽出に失敗したファイルを人間向け要約に明記してください。`draft_bodies_sha256` には、`tools/draft-hash.sh` が表示した 64 桁 hex を入れます。ただし、その report は verified 扱いにしません。

## `verify-report.md` の形式

`input/checks/` がなければ作成し、`input/checks/verify-report.md` を上書き前に顧客へ確認してください。report は必ず fenced json block から開始します。json block には次のキーを入れてください。

````markdown
```json
{
  "spec_check": "green",
  "draft_check": "green",
  "spec_path": "input/spec/<subsidy_id>.json",
  "spec_version": 1,
  "spec_sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
  "draft_bodies_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "draft_hash_algorithm": "sha256 over draft body regions (same extraction+normalization as check-drafts and draft-hash.sh; ## 叩き台 to next same-level ## heading or EOF), files sorted by path ascending, joined with \\n---\\n",
  "generated_at": "2026-07-02T12:34:56+09:00"
}
```

# verify report

## 対象

| 項目 | 内容 |
| --- | --- |
| subsidy_id |  |
| spec_path |  |
| spec_version |  |
| spec_sha256 |  |
| drafts_dir | input/drafts/<subsidy_id>/ |
| current_application | input/current-application.json |

## check-spec.sh

```text
（bash tools/check-spec.sh <spec> の出力）
```

## check-drafts.sh

```text
（bash tools/check-drafts.sh <spec> input/drafts/<subsidy_id>/ の出力）
```

## セクション別の字数

| draft | deliverable_id | section_id | section_name | count | max_chars | result |
| --- | --- | --- | --- | ---: | ---: | --- |

## coverage gaps

## `[要確認]` total

## 判定

## 次にやること
````

`generated_at` は ISO8601 の現在時刻にしてください。例:

```bash
python3 -c 'import datetime; print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))'
```

## 人間向け要約に含める内容

### セクション別の字数

draft ごとに frontmatter の `deliverable_id` と `section_id` を読み、spec の `deliverables[].sections[]` と照合して、本文文字数と `max_chars` を表にしてください。字数の数え方は `check-drafts.sh` と同じです。

- `max_chars=null` の場合は `制限なし` と断定せず、「spec 上は null。募集要項・様式で再確認」と書く
- 超過した場合は `result=fail`
- 制限内の場合は `result=green`
- frontmatter 不備、未知の id、`## 叩き台` 見出しなしは `result=fail`

### coverage gaps

`check-drafts.sh` の `WARN:` 行をそのまま転記してください。WARN は提出前に顧客本人が確認すべき不足候補です。WARN がなければ「なし」と書いてください。

### `[要確認]` total

`check-drafts.sh` の `INFO: [要確認] total:` を転記してください。bare `要確認` の INFO が出た場合も残してください。`[要確認]` が残っていても機械検査としては FAIL ではありませんが、顧客本人が内容確定前に確認すべき項目です。

### 判定

- `spec_check=green` かつ `draft_check=green` の場合だけ、機械検証は全緑です。
- どちらかが `fail` の場合は、`input/current-application.json` の `state` を変更せず、該当 FAIL を直してから `/verify` を再実行するよう案内してください。
- WARN や `[要確認]` がある場合は、機械的には green でも、顧客本人が内容確認を続ける必要があると明記してください。

## `current-application.json` の更新

両方の検査が green の場合だけ、`input/current-application.json` を更新してください。

- `state` を `verified` にする
- `verify_report_path` を `input/checks/verify-report.md` にする
- `draft_bodies_sha256` に report と同じ値を入れる
- `verified_at` と `updated_at` を ISO8601 で入れる
- `subsidy_id`、`spec_path`、`spec_version`、`chosen_funding` は確認なしに変更しない

更新例:

```bash
python3 - <<'PY'
import datetime
import json
import pathlib

path = pathlib.Path("input/current-application.json")
data = json.loads(path.read_text(encoding="utf-8"))
now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
data["state"] = "verified"
data["verify_report_path"] = "input/checks/verify-report.md"
data["draft_bodies_sha256"] = "ここに report と同じ 64 桁 hex を入れる"
data["verified_at"] = now
data["updated_at"] = now
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
```

`state=verified` にした後でも、draft を 1 文字でも編集したら `draft_bodies_sha256` が変わります。draft 編集、spec 更新、confirmation 更新、`input/drafts/<subsidy_id>/` のファイル追加・削除をした場合は、必ず `/verify` を再実行してください。

## 出力時の注意

- `verify-report.md` は検査記録であり、申請書の完成保証ではありません。
- 機械検査が green でも、募集要項の読み違い、根拠資料不足、表現の誇張、作成主体の問題は `/review` と顧客本人の確認で直してください。
- spec と draft にない制度事実、締切、補助率、補助上限、対象経費、添付資料を推測で追加しないでください。
- FAIL を隠して green と書かないでください。`bash tools/check-spec.sh` と `bash tools/check-drafts.sh` の終了コードを優先してください。
- 出力先は `input/` のみです。コア層を書き換えないでください。
- 最後に、全緑なら次は `/finalize`、fail があれば該当箇所を直して `/verify` 再実行、と案内してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/verify` は機械検証と記録作成に限定し、提出可否や採択可能性を断定しません。数値は推測しないでください。出典不明の事実、根拠が不足している主張、顧客確認が必要な情報には `[要確認]` を付けてください。要件・数値は募集要項が正であり、最終的な確認と提出判断は顧客本人が行います。
