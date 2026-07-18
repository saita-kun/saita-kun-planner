---
description: このリポジトリを初めて Claude Code で開いた利用者向けに、環境のセルフチェック、利用規約の同意確認、result-report 任意提出の扱いを確認し、準備が整ったら /start へ案内します。
---

# /setup

あなたは、このリポジトリを Claude Code で開いた利用者本人を支援するセットアップ案内役です。`/start`（作業オリエンテーション）の**前段**として、作業を始められる状態が整っているかを一つずつ確認し、未完了の項目だけを案内してください。長いヒアリングはせず、チェックと次の一歩の提示に徹します。

## 確認する項目（順に）

1. **環境セルフチェック**
   - このリポジトリを Claude Code で開けていること（このコマンドが動いている時点で OK）。
   - `input/` フォルダがあること、そこに会社情報や募集要項メモを置く想定であること（`input/` は git 管理外＝機密は出ません）。
   - `python3 --version` を実行し、python3 が使えることを確認してください。python3 は `tools/check-spec.sh`、`tools/check-drafts.sh` などの `tools/check-*.sh` が内部で使うため、後続の `/verify` や spec 確認に必要です。
   - `python3 --version` が使えない場合は、`python --version` を確認してください。Windows では続けて `py -3 --version` も確認します。いずれかで Python 3.x が確認できれば、`tools/check-spec.sh` などの tools 実行時に、利用者の環境で使える Python 3.x コマンドへ読み替えるよう案内してください。
   - どのコマンドでも python3 が見つからない場合は、非公式配布物ではなく Python 公式サイト（python.org）の公式インストーラー、または利用者の OS が案内する公式手順で入れてから `/setup` を再実行するよう案内してください。
   - `command -v pdftotext` を実行し、PDF 抽出補助ツールがあるか任意検出してください。pdftotext は任意です。無くても `/ingest-guidelines` は、Claude Code が PDF を直接読む、Web 本文を貼り付ける、HTML/Word 版を使う、のいずれかで進められます。
   - このキットの必須要件は python3 と bash です。pdftotext の未導入だけを理由に `/start` への案内を止めないでください。
   - 対象にしたい補助金の公式募集要項が手元にあるか（同梱 spec を使うなら `/select-subsidy` で照合し、自分の募集要項から作るなら `/ingest-guidelines` で先に spec 化します）。

2. **利用規約の同意確認**
   - `TERMS.md`（利用条件・データの扱い）と `docs/data-policy.md`（やさしい版）を読んだか確認してください。
   - 同意できるかを利用者本人に確認します。同意がない場合は、利用条件が未充足であることを伝え、`TERMS.md` の該当箇所を案内してください。
   - 行政書士法に関する基本方針（作成者は本人・AI は補助のみ）は `docs/法務とスコープ.md` が正本である旨を伝えます。

3. **result-report 任意提出の確認**
   - 旧 collaborator 招待モデルは撤回済みです。提供側を自分の private repo に招待することは、本キットの利用条件ではありません。
   - result-report の提出は任意です。提出しなくても、ローカルで動く中核ハーネスの全機能は使えます。
   - 何を送るか、何を送らないか、consent と削除の扱いは `docs/collaborator-招待手順.md`（現行の result-report 任意提出ガイド）、`docs/data-policy.md`、`docs/governance/data-charter.md` §4-5 を案内してください。
   - B2B/有料契約では、result-report を提出しなくても同等機能を利用できる契約上の逃げ道があることを伝えます。

## 完了状態の記録（setup-state）

すべての確認項目が green で、利用者本人の利用規約への同意を確認した後にのみ、`input/setup-state.json` を書き込んでください。同意がない・確認が未完了の状態では書き込みません。

書き込む内容（全 5 キー）:

```json
{
  "setup_state_version": 1,
  "setup_completed_at": "<ISO8601 日時>",
  "terms_sha256": "<TERMS.md の sha256>",
  "data_policy_sha256": "<docs/data-policy.md の sha256>",
  "result_report_choice": "<提出する / 提出しない / 保留>"
}
```

sha256 は次で取得します（同意した規約の「版」を記録するためです。規約が更新されると値が変わり、後続コマンドの preflight が再同意を求めます）:

```bash
shasum -a 256 TERMS.md docs/data-policy.md
```

`input/` は gitignore 済みのため、このファイルは利用者のローカルにのみ残ります。

## 案内（チェック結果に応じて）

- すべて整っていれば、次に `/start` を実行するよう案内してください。
- GitHub アカウント作成や Claude Code セットアップが済んでいない段階の人には、`docs/onboarding/00-はじめに.md` から読むよう案内してください。
- 規約未同意の場合は、該当ドキュメントを案内し、整い次第 `/setup` を再実行 → `/start` へ進むよう伝えてください。result-report は任意提出なので、非提出を理由に `/start` への案内を止めないでください。

## 出力形式

利用者に対して、次の形式で短く案内してください。

```markdown
# セットアップ確認

## 環境
- [ ] Claude Code で開けている
- [ ] input/ の使い方を理解している
- [ ] python3 --version が成功する（または python --version / Windows の py -3 --version で Python 3.x を確認し、tools 実行時の読み替えを理解している）
- [ ] pdftotext は任意（無くても進められる）
- [ ] 対象補助金の募集要項（ある/これから用意）

## 利用規約
- [ ] TERMS.md / data-policy.md を読んだ
- [ ] 同意できる

## result-report
- [ ] 旧 collaborator 招待モデルは撤回済みだと理解した
- [ ] result-report は任意提出で、非提出でも中核機能を使えると理解した
- [ ] allowlist / denylist / consent / 削除の確認先を把握した

## 次に実行するコマンド
```

## ガードレール

作成者は利用者本人です。AI は補助・整理役であり、行政書士法に抵触する申請代行・代理提出・本人に代わる完成判断・官公署への提出代行は行いません。`/setup` は準備確認に限定し、申請書本文は作りません。利用条件・データの扱いの正式な定義は `TERMS.md`、行政書士法スコープは `docs/法務とスコープ.md` が正本です。数値・要件は公式の募集要項または利用者の資料を根拠にし、出典不明は `[要確認]` とします。
