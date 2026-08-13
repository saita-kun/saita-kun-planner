# 02. Claude Code のセットアップ

このキットは、あなたのパソコンの **Claude Code**（ターミナルで動く AI アシスタント）で操作します。ここでは契約とインストールを行います。

## 必要なもの

- パソコン（動作確認済み: macOS / Linux。Windows は WSL 推奨、または Git Bash + python3 導入が必要）
- GitHub アカウント（→ `01-githubアカウント作成.md`）
- Claude Code の契約
- git（`git clone` でこのキットを手元に持ってくるために使います）

## git のインストール

すでに入っているかは、ターミナルで `git --version` を実行して確認します。バージョン番号が表示されれば次へ進めます。

- **macOS**: `xcode-select --install` を実行し、Xcode Command Line Tools を入れます。インストール後に `git --version` を再確認します。
- **Windows**: WSL を使う場合は、WSL 内の Linux として git を入れます。Git Bash で進める場合は、Git Bash 同梱の Git for Windows を公式配布元 <https://git-scm.com/> から入れます。Git Bash だけでなく python3 も使える状態にしてください。
- **Linux**: Ubuntu / Debian なら `sudo apt install git`、Fedora なら `sudo dnf install git` など、利用中のディストリビューションのパッケージマネージャで入れます。

## 手順

1. **契約**：<https://claude.com/claude-code> を開き、Claude Code が使えるプランに登録します。
2. **インストール**：公式の案内に従って Claude Code をインストールします（ターミナルに `claude` というコマンドが入ります）。
3. **初回起動**：ターミナルで `claude` と入力して起動し、画面の指示に従ってログインします。
4. **動作確認**：`claude` が起動し、対話できれば成功です。

> インストール方法の最新手順は公式ドキュメントが正です。バージョンにより画面が変わることがあります。

## 用語のミニ解説

- **ターミナル**：文字でパソコンに指示を出す画面。macOS は「ターミナル」、Linux は標準の端末、Windows は WSL の端末または Git Bash を使います。
- **slash command（スラッシュコマンド）**：Claude Code に `/intake` のように `/` で始まる指示を出す機能。このキットはこの仕組みを使います。

## 次のステップ

`03-このキットを自分のものにする.md` に進み、キットを自分の repo にして Claude Code で開きます。
