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

## 補助金パックの貢献

補助金パックは、公式資料を構造化した spec、provider confirmation、構成ファイルを記録した `pack.json`、書き方メモをまとめたものです。提出先は canonical repo（`saita-kun/saita-kun-planner`）の PR とし、対象のパック ID（`subsidy_id`）と公募回を明記してください。

### 提出物と品質基準

1. `specs/<subsidy_id>/` に spec・同名 stem の confirmation・`pack.json`・`notes/` を揃えます。パックには `.md` / `.json` だけを置き、実行コードや顧客の実データを含めません。
2. 公式原本突合を行い、公式 URL・資料版・該当ページと spec の各値を結ぶ照合票を PR 本文またはコメントに残します。必要な欄と担当分担は[受入レビュー手順](docs/design/pack-contribution-review.md)に従ってください。
3. 制度の数値・要件は公式原本を優先し、推測しません。出典不明の事実には `[要確認]` を付け、未確認の必須項目は `open` のままにします。書き方メモの制度事実には `[clause: <clause_id>]`、参考事例には `source:` を付けます。
4. 作成者と別のメンテナが再照合し、疑義があれば保留にします。provider confirmation は提供側の確認記録です。提供側が確認を終えてから `confirmed_by=provider` として confirmed 化し、貢献者の自己申告だけでは昇格させません。
5. レビュー手順のコマンド例に従い、昇格前の `bash tools/check-spec.sh "$SPEC_PATH" --gate confirm`、昇格後の `bash tools/check-spec.sh "$SPEC_PATH"` と `bash tools/check-pack.sh "$PACK_DIR"` を実行し、結果を PR に記録します。FAIL は修正し、WARN も根拠と対応を記録します。機械検査の成功だけで公式原本との一致が証明されるわけではありません。
6. 同梱する全ファイルを `core-manifest.json` に列挙し、`bash tools/validate.sh` と `tools/test-*.sh` の全検査を通します。各コミットには上記の DCO sign-off が必要です。

申請書の作成者は顧客本人で、AI は補助のみです。パックへの貢献・受入は、申請代行・代理提出を行うことではありません。適格性・採否を判定せず、成果を保証しません。

### パック貢献クレジット

- 掲載は任意です。本人同意を canonical PR に記録したうえで、**公開表示名・パック ID・canonical PR URL** の3点を、その PR の受入記録に掲載します。DCO sign-off はクレジット掲載への同意として扱いません。
- メールアドレスや顧客情報はクレジットに含めません。PR の投稿アカウント・公開履歴は残ります。訂正・削除の希望は同じ canonical PR で受け付けますが、履歴・通知・複製から完全には消せません。
- `pack.json` にクレジット用のキーを追加しません。クレジットは貢献の記録であり、制度の公認・推薦・採択実績を表すものではありません。
- [ADOPTERS.md](ADOPTERS.md) は利用・派生事例の自己申告です。パック貢献クレジットとは別で、自動転記しません。利用表明の掲載・削除依頼は既存の canonical Issue フォームだけで受け付けます。

## 変更の性質に関する規律

- 本リポジトリは補助金申請者・支援者向けの実プロダクトです。**補助金の事実・数値を捏造しない**でください（要件・数値は公式募集要項が正）。
- 行政書士法ガードレール（作成者は顧客本人、AI は補助のみ、申請代行・代理提出をしない）を各コマンドで維持してください。
- ブランド名「サイタくん」の使用は `TRADEMARK.md` に従ってください。
