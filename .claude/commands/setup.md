---
description: このリポジトリを初めて Claude Code で開いた利用者向けに、環境のセルフチェック、利用規約の同意確認、result-report 任意提出の扱いを確認し、準備が整ったら /start へ案内します。
---

# /setup

あなたは、このリポジトリを Claude Code で開いた利用者本人を支援するセットアップ案内役です。`/start`（作業オリエンテーション）の**前段**として、作業を始められる状態が整っているかを一つずつ確認し、未完了の項目だけを案内してください。長いヒアリングはせず、チェックと次の一歩の提示に徹します。

## 確認する項目（順に）

1. **環境セルフチェック**
   - このリポジトリを Claude Code で開けていること（このコマンドが動いている時点で OK）。
   - `input/` フォルダがあること、そこに会社情報や募集要項メモを置く想定であること（`input/` は git 管理外＝機密は出ません）。
   - **ゴール: 以後の作業が通る Python 3 実行系を確定すること。** 受入基準は**次の 2 つがどちらも通ること**です。片方だけでは green にしないでください。

     ```bash
     bash tools/check-spec.sh --list-bundled   # (A) 同梱チェッカーが動く。受入基準は終了コード 0
     python3 --version                          # (B) python3 という名前で Python 3.x が返る
     ```

     (A) は `tools/check-spec.sh`、`tools/check-drafts.sh` などの `tools/check-*.sh` が動くことの実物確認です。これらの wrapper は tools 実行時に `python3` → `python` → `py -3` の順で自動判定するため、(A) は `python3` という名前が無くても exit 0 になり得ます。
     (B) が別途必要なのは、`/subsidy-fit` の `python3 tools/lib/predicate.py`、`/verify`・`/finalize`・`/retrospect` などが **`python3` を名前で直接呼ぶ**ためです。ここを green にしたまま `python3` が無いと、後続コマンドが `command not found` で止まります。
   - (A) が失敗する場合（`FAIL: Python 3 not found` や `command not found` など）は、使える Python 3 を探します。`python3 --version`、`python --version`、Windows では続けて `py -3 --version` を実行し、Python 3.x が返るものを探してください。これらは探索の手段であり、受入基準そのものではありません。この 3 つは wrapper が自動で試すため、どれも返らないなら**名前ではなく場所**で探します（バージョン付きの名前 `python3.12`、絶対パス、venv の `bin/python` などを `<候補> --version` で確認）。
   - 見つかった実行系を wrapper に使わせるには、`PLANNER_PYTHON` 環境変数に設定して (A) をもう一度実行し、exit 0 を確認します。**`PLANNER_PYTHON` に入れるのは実行ファイル 1 つ（コマンド名または絶対パス）だけ**です。`"py -3"` のように引数を付けた値は、その名前の実行ファイルを探して必ず失敗します。

     ```bash
     export PLANNER_PYTHON=python3.12
     bash tools/check-spec.sh --list-bundled
     ```

   - (B) が失敗する場合（`python` や `py -3` はあるのに `python3` という名前が無い。python.org 版を入れた Windows の Git Bash で起きます）は、**見つけた Python 3 を `python3` という名前で PATH から呼べるようにしてください**。`PLANNER_PYTHON` は wrapper にしか効かず、`python3` を直接呼ぶコマンドは救えません。

     ```bash
     mkdir -p ~/bin
     printf '#!/bin/sh\nexec py -3 "$@"\n' > ~/bin/python3   # py -3 の部分は (B) で見つけた実行系に置き換える
     chmod +x ~/bin/python3
     export PATH="$HOME/bin:$PATH"
     python3 --version
     ```

     環境変数はセッションを閉じると消えます。`PLANNER_PYTHON` も `PATH` も、毎回設定するのが面倒な場合は利用者のシェル設定ファイル（`~/.bashrc`、`~/.zshrc` など）に同じ 1 行を追加するよう案内してください。**次の slash command は別の Bash 呼び出しになるため、恒久設定にしていない場合は (A)(B) を毎セッション確認してください。**
   - どのコマンドでも Python 3.x が見つからない場合は、非公式配布物ではなく Python 公式サイト（python.org）の公式インストーラー、または利用者の OS が案内する公式手順で入れてから `/setup` を再実行するよう案内してください。
   - `command -v pdftotext` を実行し、PDF 抽出補助ツールがあるか任意検出してください。pdftotext は任意です。無くても `/ingest-guidelines` は、Claude Code が PDF を直接読む、Web 本文を貼り付ける、HTML/Word 版を使う、のいずれかで進められます。
   - このキットの必須要件は python3 と bash です。pdftotext の未導入だけを理由に `/start` への案内を止めないでください。
   - 対象にしたい補助金の公式募集要項が手元にあるか（同梱 spec を使うなら `/select-subsidy` で照合し、自分の募集要項から作るなら `/ingest-guidelines` で先に spec 化します）。

2. **応援の確認（任意・同意必須）**
   - `CLAUDE.md` の「応援の確認」節に従い、スターとフォローで応援するかを一度だけ確認します。gh 未認証の場合は何も言わずスキップします。同意の有無にかかわらずセットアップは通常どおり進めます。

3. **利用規約の同意確認**
   - `TERMS.md`（利用条件・データの扱い）と `docs/data-policy.md`（やさしい版）を読んだか確認してください。
   - 同意できるかを利用者本人に確認します。同意がない場合は、利用条件が未充足であることを伝え、`TERMS.md` の該当箇所を案内してください。
   - 行政書士法に関する基本方針（作成者は本人・AI は補助のみ）は `docs/法務とスコープ.md` が正本である旨を伝えます。

4. **result-report 任意提出の確認**
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

ここで必要なのは「`TERMS.md` と `docs/data-policy.md` の SHA-256 を求めること」です（同意した規約の「版」を記録するためです。規約が更新されると値が変わり、後続コマンドの preflight が再同意を求めます）。取得手段は顧客環境で使えるものを選んでください。このキットの必須要件である Python 3 なら、標準ライブラリだけで計算できます。

```bash
python3 -c 'import hashlib, pathlib, sys; [print(hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest(), p) for p in sys.argv[1:]]' TERMS.md docs/data-policy.md
```

OS 付属のコマンドを使う場合の例です（環境によってどちらか一方しかありません）。

```bash
shasum -a 256 TERMS.md docs/data-policy.md   # macOS など
sha256sum TERMS.md docs/data-policy.md       # 多くの Linux ディストリビューション
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
- [ ] bash tools/check-spec.sh --list-bundled が exit 0（失敗する場合は python --version / Windows の py -3 --version で Python 3.x を探し、PLANNER_PYTHON を設定して再確認）
- [ ] python3 --version が Python 3.x を返す（python3 を名前で直接呼ぶコマンドがあるため。無い場合は python3 という名前で PATH から呼べるようにする）
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
