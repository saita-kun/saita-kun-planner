---
audience: ai
---
# 補助金パックの受入レビュー

公式原本との照合票と機械検査結果を canonical PR に残し、作成者と別のメンテナが再照合して受入可否を記録する。機械検査の成功は原本の正確性・適格性・採否の証明ではない。

## 実行仕様

### 提出物・担当

| 担当 | 必須作業 |
| --- | --- |
| 貢献者（作成者） | `specs/<subsidy_id>/` の spec・confirmation・`pack.json`・`notes/`、照合票、検査結果を canonical PR に提出。各コミットに DCO sign-off を付ける |
| 作成者と別のメンテナ | 公式原本を開き直して全必須項目を再照合。差分・WARN の扱いと受入可否を PR に記録 |
| 提供側メンテナ | 再照合完了後に provider confirmation を確定し、confirmed 化・配布列挙・最終検査を行う。再照合担当との兼任は可 |

- 提出先は canonical repo（`saita-kun/saita-kun-planner`）の PR。パック ID（`subsidy_id`）・公募回・変更対象と変更理由を明記する。
- パックは `.md` / `.json` のみとし、実行コード・顧客の申請本文・個人情報を含めない。公式資料の再配布は提出権限を確認し、原本一式を無条件に PR 添付しない。
- 公式原本突合では募集要項・様式・訂正資料の版を確認する。数値は推測せず、出典不明の事実は `[要確認]` とし、確認できるまで必須項目を `open` に保つ。
- 書き方メモの制度事実は `[clause: <clause_id>]` で spec の実在する clause に結ぶ。一般知見を制度事実の根拠にせず、参考事例には `source:` を記録する。
- 申請書の作成者は顧客本人、AI は補助のみ。申請代行・代理提出を行わず、適格性・採否を判定しない。

### 照合票

PR 本文またはコメントに、対象 spec のパス・`spec_version`・レビュー対象 commit SHA を書き、以下の欄を持つ表を置く。1行は1つの `field_path` と根拠箇所の組とし、根拠が複数なら行を分ける。更新時も変更箇所だけでなく全必須項目を確認する。

| 公式 URL | 資料版 | SHA または再確認日時 | ページ・節 | field_path | 原本値 | spec 値 | 確認者 | 確認日 | 判定 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

- 公式 URL は発行元の原本へのリンク、資料版は公募回・版番号または改訂日を記録する。
- SHA は原本バイト列の SHA-256。固定できない Web ページ等はタイムゾーン付き再確認日時を記録する。これは spec の `spec_sha256` とは別の証跡である。
- ページ・節には条項と `clause_id` も付ける。原本値と spec 値には単位・対象期間・比較条件も記録し、空欄で一致扱いにしない。
- `field_path` は confirmation の `items[].field_path` と対応させる。`source_clauses` と原本の引用を結び、対象外の `na` も根拠を記録する。
- 確認者は作成者・再照合担当を区別し、それぞれの確認日を記録する。判定は「一致・不一致・保留・対象外（根拠必須）」から選ぶ。
- 原本の版違い・未確認・疑義があれば受入を保留し、該当 item を `open` に戻す。未解決のまま confirmed 化しない。修正後は再照合と検査を繰り返す。

### 昇格前の検査

以下のコマンドは repo ルートで実行する。`PACK_DIR` は対象の `specs/<subsidy_id>`、`SPEC_PATH` はその中の `<subsidy_id>.json` に設定する。confirmation の `spec_path` も移設後のパスに合わせる。実在の値を設定してから実行し、検査結果を PR に記録する。

再照合後、提供側が draft のまま全必須 item を `confirmed` または根拠付き `na` にし、要件の `predicate_state` を確定して次を実行する。

```bash
bash tools/check-spec.sh "$SPEC_PATH" --gate confirm
```

### 提供側による confirmed 化と最終検査

1. 昇格前検査が exit 0 になってから、提供側が spec の `status=confirmed` を保存する。貢献者の自己申告や AI の出力だけで provider confirmation を確定しない。
2. 保存後の spec の SHA-256 を計算し、confirmation の `spec_sha256`・`spec_version`・`spec_path` を一致させ、`confirmed_by=provider` とタイムゾーン付き `confirmed_at` を記録する。同梱 spec は `registry.origin=bundled`、`round`・`portal_url`、全 `items[].confirmed_at`（日付）を確認する。
3. spec を基に書き方メモを再確認してから、`pack.json` の `built_by=provider`・`spec_version`・`built_at` と、spec・confirmation・notes の SHA-256、notes の `derived_from_spec_sha256` を更新する。ハッシュの更新だけで内容の再確認を省略しない。
4. 次の通常検査を実行する。両方 exit 0、パック検査の `OK: pack checks passed` を確認する。FAIL は修正し、WARN は公式原本に戻って対応と根拠を記録する。

```bash
bash tools/check-spec.sh "$SPEC_PATH"
bash tools/check-pack.sh "$PACK_DIR"
```

5. 同梱する全ファイルを [core-manifest.json](../../core-manifest.json) に列挙し、`bash tools/validate.sh` と `tools/test-*.sh` 全件の成功を確認する。原本の版や内容を変更したら照合票・confirmation・notes も更新し、再照合と検査をやり直す。
6. 再照合担当が PR に「受入可・修正依頼・保留」の判定、根拠、未解決事項、検査対象 commit SHA とコマンド出力を記録する。受入可の後も merge・公開は既存の承認手順に従う。

### クレジットと利用表明

- 本人同意を canonical PR に記録した場合だけ、公開表示名・パック ID・canonical PR URL を同 PR の受入記録に掲載する。DCO sign-off と掲載同意は別で、同意がなければクレジットを掲載しない。
- `pack.json` にクレジット用のキーを追加しない。メールアドレス・顧客情報は掲載しない。クレジットは公認・推薦・採択実績を意味しない。
- 訂正・削除は同じ canonical PR で受け付けるが、公開履歴・通知・複製から完全には消せない。
- [CONTRIBUTING.md](../../CONTRIBUTING.md#パック貢献クレジット) と [ADOPTERS.md](../../ADOPTERS.md#掲載方法) は役割を分ける。利用表明へ自動転記しない。ADOPTERS の掲載・削除依頼は [canonical Issue フォーム](https://github.com/saita-kun/saita-kun-planner/issues/new?template=adopter-entry.yml)のみ。

## 経緯・根拠

- [パック構造・昇格順序](harness-pack-builder.md)を受入レビューに適用する。schema や確認済み状態の機械ゲートは変更しない。
- [DR-003](decisions/dr-003-no-eligibility-judgement.md)の作成主体と数値の規律、[DR-008](decisions/dr-008-adopters-canonical-issue-only.md)の申告経路を維持する。
- 本手順のテストは文書契約と合成パックでのコマンド実行を検証する。個別制度の公式原本との一致は受入レビューで確認する。
