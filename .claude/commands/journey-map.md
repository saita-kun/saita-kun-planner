---
description: 確認済み spec から、その補助金の申請工程フローチャート（参考図 HTML）を input/journey/ に生成します。
---

# /journey-map

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する、申請工程の見取り図係です。顧客本人が確認を終えた spec（`status=confirmed`）から、その補助金に固有の申請工程フローチャート HTML を生成し、これから何がどの順で起きるのか、顧客自身は何をするのかを一望できるようにします。

この成果物は**提出物ではありません**。全体の流れをつかむための参考図です。日付・手続き・要件の正は、常に公式の公募要領です。

## 使う場面

- `/confirm-spec` または `/select-subsidy` で spec が確認済みになった直後に、申請から採択後までの全体像を顧客と共有したいとき
- `/subsidy-fit` や `/plan-deliverables` の前後で、顧客本人がやること、外部の窓口で行うこと、締切を俯瞰したいとき

## 前提

- `input/current-application.json` が存在し、`state` が `spec_confirmed` 以降であること。まだの場合（`spec_draft` など）は、このコマンドの作業に進まず `/confirm-spec`（または `/select-subsidy`）を案内してください。
- 参照する spec は、下の解決順で選んだ confirmed spec です。`current-application.spec_path` は入口として扱いますが、同じ `subsidy_id` のパック形が存在する場合はパック形を優先します。
- `bash tools/check-spec.sh <解決済みspec>` が green で、confirmation の `spec_sha256` が現在の spec bytes と一致していること。FAIL の場合は工程図を生成せず、`/confirm-spec` または `/select-subsidy` に戻ってください。

## spec / confirmation / notes の解決順

同じ `subsidy_id` の spec は、次の順で最初に見つかったものに解決してください。

1. 利用者側 spec: `input/spec/` のパック形（`pack.json` の `spec.path` が指す spec）、なければ平置き `input/spec/<subsidy_id>.json`
2. 同梱 spec: `bash tools/check-spec.sh --list-bundled` の出力から `subsidy_id` が一致する spec パス（パック優先・重複 ID の FAIL・安定ソートを機械側で保証）

同梱 spec の候補を `specs/` の目視や推測で選ばないでください。`--list-bundled` が失敗した場合（重複 `subsidy_id` 等）は、エラー内容を顧客に示して停止してください。

`current-application.spec_path` は入口として使いますが、同一 subsidy_id のパック形が存在する場合はパック形を優先し、`spec_path` の付け替えを案内してください。`spec_path` が旧同梱平置きパス（例: `specs/<subsidy_id>.json`）を指し、同一 subsidy_id のパック形が上記の解決結果に存在する場合は、パック形を優先するため、`spec_path` を付け替えるか `/select-subsidy` で再選択するよう案内してください。古い平置き spec のまま工程図を生成しないでください。

## 手順

### 1. 対象 spec の確認

`input/current-application.json` を読み、`subsidy_id`、入口の `spec_path`、`state`、解決済み spec path を顧客に表示してから進めてください。`state` が `spec_confirmed` 以降でない、spec の `status` が `confirmed` でない、または `bash tools/check-spec.sh <解決済みspec>` が FAIL する場合は、工程図を生成せず `/confirm-spec` または `/select-subsidy` を案内してください。

### 2. フローの機械生成（derive）

```bash
bash tools/journey-map.sh derive <入口spec_path> --current-application input/current-application.json --out input/journey/<subsidy_id>-flow.json
```

`<入口spec_path>` には `current-application.spec_path` を渡してください。derive は、共有 resolver の解決順と confirmed spec 検証を通したうえで、spec の構造化フィールド（提出物・日程）だけから、その補助金に固有の工程を決定的に導出します。`NG:` が出た場合は spec 側の不備なので、`bash tools/check-spec.sh <解決済みspec>` と `/confirm-spec` を先に green にしてから再実行してください。

### 3. AI 補完（条文引用が必須）

spec の `clauses[]` を読み、**構造化フィールドに現れない申請者本人の工程**（例: 口頭審査、面談、説明会への参加）が条文に明記されている場合に限り、flow JSON に工程を追加します。

- 追加する工程は `origin: "ai"` とし、根拠条文の `clause_ids` を必ず入れてください。引用が空のままでは render が拒否します。
- 挿入位置では前工程の `next` を繋ぎ替え、one-way（後戻り矢印なし）を保ってください。
- ラベルは平易な日本語の業務名にしてください。ファイル名、コマンド名、`[要確認]` などのキット内部用語を図に持ち込まないでください。
- 条文で確認できない工程は追加しないでください。推測で工程を作ることは禁止です。
- 既存の工程（`origin: "kit"` / `"derived"`）のラベル・説明文・レーン・種類・出典・工程どうしのつながりは書き換えないでください。削除や飛ばし矢印の追加もできません（いずれも render が拒否します）。あなたが伝えたい補足は、自分が追加する `origin: "ai"` の工程の説明文に書いてください。
- 工程を追加した場合は、顧客に「条文◯◯（節名）に基づき『…』の工程を追加しました」と根拠つきで報告してください。追加しなかった場合は、その旨だけ伝えれば十分です。

### 4. 描画（render）

```bash
bash tools/journey-map.sh render input/journey/<subsidy_id>-flow.json --current-application input/current-application.json --out input/journey/<subsidy_id>-journey.html
```

render は描画の前に、flow がスキーマに適合していること、すべての工程の出典（提出物 ID・日程 ID・条文 ID）が spec に実在することを機械検証します。`NG:` の場合は HTML を出力しないので、NG 行に沿って flow JSON を修正して再実行してください。検証を緩めたり、出典のない工程を通そうとしたりしないでください。

### 5. 顧客への案内

- 生成した HTML をブラウザで開くよう案内してください（ファイルをダブルクリックで開けます）。
- この図は参考図であり提出物ではないこと、日付・手続きの正は公募要領であることを必ず伝えてください。
- 図の読み方も一言添えてください: 色つき（琥珀色）の工程は顧客本人が確認・実行する工程、破線の囲みは採択された後の工程、ひし形は分かれ道です。

## 出力

- `input/journey/<subsidy_id>-flow.json` — 工程データ（AI 補完の追記先）
- `input/journey/<subsidy_id>-journey.html` — フローチャート本体
- 出力先は `input/`（育成層）のみです。`.claude/commands/`、`schemas/`、`specs/`、`templates/`、`tools/` などのコア層は書き換えないでください。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/journey-map` は申請工程の見取り図を作るだけであり、提出書類を作るものではありません。日付・手続き・要件は推測せず、spec と公募要領で確認できる範囲だけを図にします。生成した図と公式の公募要領が食い違う場合は、必ず公募要領を優先してください。
