# コントリビュートガイド（サイタくん）

> 本ガイドは `docs/governance/data-charter.md` §3 を親規範とする派生文書です（`derived_from: docs/governance/data-charter.md`）。

サイタくん（saita-kun-planner）への貢献を歓迎します。本リポジトリは補助金申請の自走ハーネス（slash commands・スキーマ・検証ゲート・マニュアル）を配布する **public OSS template repo** です。

## 関連ポリシー

- 行動規範は [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) を確認してください。
- セキュリティ脆弱性の私的報告は [SECURITY.md](SECURITY.md) の手順に従ってください。
- 利用・派生事例の掲載は [ADOPTERS.md](ADOPTERS.md) を確認してください。掲載申告は canonical repo の Issue フォーム（<https://github.com/saita-kun/saita-kun-planner/issues/new?template=adopter-entry.yml>）からのみ受け付けます（公開 repo は内部正本から一括生成されるため、ADOPTERS.md への直接 PR は次回更新で消えます）。

## ライセンスと著作権

- 貢献は本リポジトリの配布ライセンス（`LICENSE`、**Apache License 2.0**）の下で受け入れられます。
- **CLA（Contributor License Agreement）は採用しません。** 著作権は各コントリビュータが保持します。単一主体に著作権を集約しないことで、全コントリビュータの合意なしに独断で proprietary へ再ライセンスできない構造（rug-pull 耐性）を保ちます。

## DCO（Developer Certificate of Origin）— 必須

CLA の代わりに **DCO 1.1** を必須とします。DCO は著作権の譲渡・集約ではなく、「あなたがその貢献を提出する権利を持つこと」を証明する軽量な仕組みです（Linux kernel 由来）。

各コミットに `Signed-off-by` 行を付けてください。`-s` フラグで自動付与されます。

```bash
git commit -s -m "your message"
```

これにより次の行がコミットメッセージ末尾に入ります。

```
Signed-off-by: あなたの名前 <you@example.com>
```

sign-off は [DCO 1.1](https://developercertificate.org/) の文言（自分に権利がある／適切なライセンスで提出できる、等）に同意したことを意味します。

- **注意（プライバシー）**: `Signed-off-by` の氏名・メールは公開 git 履歴に永久に残ります。公開してよい名前・アドレスを使ってください。
- sign-off のないコミットを含む PR はマージできません（`dcoapp/app` の status check で検査します）。

## 貢献の進め方

1. Issue で変更内容を先に共有すると齟齬が減ります。
2. fork して feature ブランチで作業します。
3. **構造ゲートを緑に保つ**: 変更後に `bash tools/validate.sh` が exit 0 であることを確認してください。コマンド・スキーマ・docs を追加/変更した場合は、`tools/validate.sh` に対応するアサーションを追加します（構造の完全性を担保するゲートです）。
4. コミットに `-s`（DCO sign-off）を付けます。
5. PR を作成します。

## 変更の性質に関する規律

- 本リポジトリは補助金申請者・支援者向けの実プロダクトです。**補助金の事実・数値を捏造しない**でください（要件・数値は公式募集要項が正）。
- 行政書士法ガードレール（作成者は顧客本人、AI は補助のみ、申請代行・代理提出をしない）を各コマンドで維持してください。
- ブランド名「サイタくん」の使用は `TRADEMARK.md` に従ってください。
