---
description: 最新 spec と draft に対する verify 全緑を確認し、成果物・人の作業・添付資料・期限の提出前チェックリストを作ります。
---

# /finalize

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する最終確認の整理役です。`input/checks/verify-report.md`、`input/current-application.json`、`input/deliverables.md`、確認済み spec、`input/drafts/<subsidy_id>/` を照合し、最新 spec と最新 draft に対する機械検証が全緑であることを確認してから、提出前チェックリストを作ってください。

このコマンドは提出代行ではありません。申請書を官公署へ提出したり、提出可否を顧客本人に代わって確定したりしないでください。提出は顧客本人の責任・判断で行います。AI は、`/verify` の検証結果、募集要項、成果物一覧、顧客資料に照らした確認事項の整理、見出しや文字数などの体裁整え、様式、添付資料、期限、未確認事項の洗い出しだけを補助します。

## 使う場面

- `/draft-section` と `/review` を終え、`/verify` が全緑になった後
- `input/deliverables.md` の AI 成果物、人がやること、添付、hard 締切を、提出前に顧客本人が消し込みたいとき
- draft を編集していない最新状態で、提出直前の様式・添付・期限・作成主体を確認したいとき

出力先は `input/final-checklist.md` を原則にしてください。`input/current-application.json` の状態更新以外、`.claude/commands/`、`schemas/`、`specs/`、`tools/`、`docs/` などのコア層は書き換えないでください。

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
6. `input/checks/verify-report.md` の `draft_bodies_sha256` が、いまの `input/drafts/<subsidy_id>/` から再計算した draft 本文ハッシュと一致すること。
   - 不一致なら、draft が `/verify` 後に編集されています。stale な検証結果では `/finalize` しないで、必ず `/verify` を再実行してください。
7. `input/drafts/<subsidy_id>/` が存在し、少なくとも 1 つの `*.md` draft を含むこと。
   - draft がない場合は、先に `/draft-section` で作成し、`/review` と `/verify` を済ませてください。
8. `input/deliverables.md` が存在すること。
   - ない場合は `/plan-deliverables` を実行し、成果物マニフェストを作ってから戻ってください。

9. 作成者は顧客本人であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行わないことを明示してください。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で解決してください。

1. `input/spec/<subsidy_id>/<subsidy_id>.json`
2. `input/spec/<subsidy_id>.json`
3. `specs/<subsidy_id>/<subsidy_id>.json`
4. `specs/<subsidy_id>.json`

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が `specs/<subsidy_id>.json` の旧同梱平置きパスを指し、同一 subsidy_id のパック形 `specs/<subsidy_id>/<subsidy_id>.json` が存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。

## verify-report の読み取り

`verify-report.md` は必ず fenced json block から始まります。次の要領で、先頭の json block を読み取ってください。外部依存は使わず、`python3` 標準ライブラリだけを使います。

```bash
python3 - <<'PY'
import json
import pathlib
import re
import sys

report_path = pathlib.Path("input/checks/verify-report.md")
text = report_path.read_text(encoding="utf-8")
match = re.match(r"\A```json\n(.*?)\n```\n", text, re.S)
if not match:
    print("verify-report.md の先頭 fenced json が見つかりません", file=sys.stderr)
    raise SystemExit(1)
data = json.loads(match.group(1))
for key in ("spec_check", "draft_check", "spec_path", "spec_version", "spec_sha256", "draft_bodies_sha256", "draft_hash_algorithm", "generated_at"):
    if key not in data:
        print(f"verify-report.md missing key: {key}", file=sys.stderr)
        raise SystemExit(1)
if data["spec_check"] != "green" or data["draft_check"] != "green":
    print("verify checks are not green", file=sys.stderr)
    raise SystemExit(1)
print(data["spec_path"])
print(data["spec_version"])
print(data["spec_sha256"])
print(data["draft_bodies_sha256"])
PY
```

`spec_check` と `draft_check` の両方が `green` でない場合は、見出し、文字数、様式、添付資料、期限の確認へ進まず、該当 FAIL を直して `/verify` を再実行してください。

## 最新 spec hash と check-spec 再実行

`verify-report.md` に記録された `spec_path` の file bytes から SHA-256 を再計算し、report の `spec_sha256` と一致することを確認してください。あわせて `input/current-application.json` の `spec_path`、`spec_version` と report の値が一致することを確認し、最後に現在の spec へ `bash tools/check-spec.sh <spec_path>` を再実行してください。

```bash
python3 - <<'PY'
import hashlib
import json
import pathlib
import re
import sys

app = json.load(open("input/current-application.json", encoding="utf-8"))
text = pathlib.Path("input/checks/verify-report.md").read_text(encoding="utf-8")
match = re.match(r"\A```json\n(.*?)\n```\n", text, re.S)
report = json.loads(match.group(1))
if report["spec_path"] != app.get("spec_path") or report["spec_version"] != app.get("spec_version"):
    print("verify-report.md と current-application.json の spec 情報が一致しません", file=sys.stderr)
    raise SystemExit(1)
spec_path = pathlib.Path(report["spec_path"])
actual = hashlib.sha256(spec_path.read_bytes()).hexdigest()
if actual != report["spec_sha256"]:
    print("spec_sha256 mismatch: spec が /verify 後に更新されています", file=sys.stderr)
    raise SystemExit(1)
print(report["spec_path"])
PY
bash tools/check-spec.sh <spec_path>
```

`spec_sha256` が一致しない、または `check-spec.sh` が fail の場合は、`input/final-checklist.md` を作らず `/verify` を再実行してください。

## 最新 draft hash の再計算

`draft_bodies_sha256` は `/verify` と同じ documented algorithm で再計算してください。

- 対象ファイルは `input/drafts/<subsidy_id>/` 直下の `*.md`
- ファイルは path 昇順で並べる
- 各ファイルの本文領域は、最初の `## 叩き台` 見出しより下から、次の同階層 `## ` 見出しまたは EOF まで
- 本文領域の各行は前後空白を除去し、改行を取り除いて連結する
- 連結後に NFKC 正規化する
- 各ファイルの正規化済み本文を `\n---\n` で結合し、その UTF-8 bytes の SHA-256 を取る

`input/current-application.json` から `subsidy_id` を読み、`tools/check-drafts.sh` と同じ本文抽出ロジックを使う `tools/draft-hash.sh` でハッシュを計算します。

```bash
python3 - <<'PY'
import json
app = json.load(open("input/current-application.json", encoding="utf-8"))
print(f'input/drafts/{app["subsidy_id"]}/')
PY
bash tools/draft-hash.sh <spec_path> input/drafts/<subsidy_id>/
```

再計算した値が `verify-report.md` の `draft_bodies_sha256` と一致しない場合は、draft が変わっています。`input/final-checklist.md` を作らず、顧客本人へ「最新 draft に対する verify が未完了」と説明し、`/verify` を実行してから戻ってください。

## 入力として使うもの

- `input/current-application.json`
- `input/checks/verify-report.md`
- `input/deliverables.md`
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
- `draft_bodies_sha256`
- 再計算した draft hash
- 一致判定
- `generated_at`
- `current-application.json` の `state_before`

ここが全緑かつ hash 一致でない場合は、提出前チェックリストを作りません。

### 2. 成果物マニフェストから消し込み表を作る

`input/deliverables.md` を読み、final-checklist を次の 4 つに分けて作ってください。`input/deliverables.md` は再生成可能なビューですが、提出前の消し込みは `/finalize` の `input/final-checklist.md` に残します。

1. AIと作る成果物の最終確認
   - `produced_by=ai_draftable` の成果物と sections を対象に、対応する draft、`/verify` の字数結果、`/review` の高・中リスク対応状況を確認します。
   - 見出し、文字数、様式、本文と根拠資料の整合、`[要確認]` の残りを、顧客本人が確認できる表にしてください。
2. 人がやること消し込み
   - `type=procedure`、`produced_by=human_only`、`produced_by=external` の項目を対象に、作業主体、issuer、依頼先、完了状況、残アクションを確認します。
   - 外部発行書類や支援機関確認など、AI が作れないものを AI 成果物のように扱わないでください。
3. 添付資料チェック
   - `type=attachment` の項目、見積書、仕様書、決算書、売上資料などを対象に、ファイル名、format、upload_target、本文との対応、最新版かどうかを確認します。
4. hard 締切チェック
   - spec の `schedule[]` と `input/deliverables.md` の締切カレンダーを読み、`hard=true` の期限を先頭に出します。
   - date、starts_at、ends_at、time、timezone、relative をそのまま表示し、相対期限は一般論で日付換算しません。

### 3. 見出し・文字数・様式の最終確認をする

事業計画書の見出し、設問、入力欄、順番が、募集要項や指定様式に合っているか確認してください。このリポジトリのテンプレート名と募集要項の見出し名が違う場合は、募集要項の見出しを優先してください。

確認対象には次を含めてください。

- 指定された見出しや入力欄が抜けていないか
- セクションの順序が様式に合っているか
- 表、箇条書き、ファイル名、ファイル形式などの指定に合っているか
- 文字数、ページ数、行数、PDF 化などの条件があるか
- 記入不要欄、事務局記入欄、押印欄、署名欄の扱いを顧客本人が確認できる形になっているか

文字数の機械チェックは `/verify` の `check-drafts.sh` が担当します。`/finalize` では、文字数結果を提出様式へ貼り付けるときに崩れないか、見出しや欄の分割が様式に合っているかを確認してください。

### 4. 提出直前の未解決事項をまとめる

`[要確認]` が残る場合は、提出前に何を確認すれば解消できるか、顧客本人の次アクションとして書いてください。未解決のまま提出するリスクがある場合も、提出可否を代わりに判断せず、リスクとして整理します。

締切までの残作業は、顧客本人が判断できるように次の形式で整理してください。

- 今日確認すること
- 提出前日までにそろえること
- 提出直前に再確認すること
- 事務局、支援機関、専門家へ確認したほうがよいこと

## 出力形式

`input/final-checklist.md` を作成してください。既存ファイルがある場合は、上書き前に顧客へ確認してください。

```markdown
# final-checklist

## 作成メモ

- 作成者: 顧客本人
- AIの役割: 体裁、様式、文字数、添付、期限、verify 最新性、未確認事項の整理補助
- current_application: input/current-application.json
- verify_report: input/checks/verify-report.md
- deliverables_view: input/deliverables.md
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

`input/final-checklist.md` を作成できた場合だけ、`input/current-application.json` を更新してください。verify ゲートが不成立の場合は更新しません。

- `state` を `finalized` にする
- `final_checklist_path` を `input/final-checklist.md` にする
- `finalized_at` と `updated_at` を ISO8601 で入れる
- `draft_bodies_sha256` は `verify-report.md` と再計算値が一致した値を保持する
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
data["state"] = "finalized"
data["final_checklist_path"] = "input/final-checklist.md"
data["finalized_at"] = now
data["updated_at"] = now
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
```

`state=finalized` にした後でも、draft、spec、confirmation、`input/deliverables.md` を更新した場合は、提出前チェックが古くなります。その場合は `/review`、`/verify`、`/finalize` を必要な範囲でやり直してください。

## 出力時の注意

- 体裁整えは、募集要項と指定様式に合わせるための確認補助として行ってください。
- 文章を提出用の完成版として断定的に仕上げないでください。顧客本人が最終確認、修正、提出判断を行います。
- `verify-report.md` が missing、fail、stale spec hash、または stale draft hash の場合は、`input/final-checklist.md` を作らず `/verify` へ戻してください。
- 募集要項にない数値、要件、文字数、添付資料、期限、提出方法を推測しないでください。
- `[要確認]` が残る場合は、何を見れば確認できるか、顧客本人が次に取る行動として書いてください。
- 申請代行、代理提出、本人に代わる完成判断、官公署への提出代行を示唆する表現を避けてください。
- 最後に「提出は顧客本人の責任・判断で行う」ことを明記してください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/finalize` は、最新 draft に対する verify 全緑を前提に、見出し、文字数、様式、添付資料、期限、提出前チェックリストを整理するための最終確認補助です。提出は顧客本人の責任・判断で行います。数値、要件、文字数、補助率、補助上限、添付資料、提出期限は募集要項または顧客資料を根拠にし、出典不明の事実には `[要確認]` を付けてください。
