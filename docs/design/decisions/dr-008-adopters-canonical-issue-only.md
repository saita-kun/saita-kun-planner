# DR-008: ADOPTERS 掲載は canonical repo の Issue フォーム経由のみ

> 種別: 設計不変条件 ／ 状態: 有効 ／ 決定日: 2026-07-17 ／ 決定者: DRI ／ 出典: 内部決定記録（非公開）

## 決定

`ADOPTERS.md` への掲載・削除依頼は、**canonical repo（`saita-kun/saita-kun-planner`）の Issue フォーム（`adopter-entry.yml`）経由のみ**とする。public repo への直接 PR は受け付けない。メンテナが開発正本に反映（コミットメッセージに Issue 番号 = provenance）し、次回 export で public に反映する。

## 理由

- 開発正本と public（export 反映先）の分離構造上、public への直接 PR を受けると両者の整合が壊れる。
- テンプレート複製では Issue フォームごと利用者 repo にコピーされるため、フォーム冒頭で「canonical repo でのみ受け付ける」ことを明示しないと、複製先に掲載依頼が漂着する。

## 制約（運用 AI が守ること）

- 掲載導線は canonical repo の new-issue 絶対 URL のみを案内する（相対リンクにしない）。
- **匿名性を謳わない**: 投稿した GitHub アカウントは Issue 上で公開される。表示名はアカウント名と別にできる、という正確な表現を維持する。
- フォームで再特定リスクのある情報を収集しない: 補助金カテゴリは粗い選択式（任意・「非公開」選択肢あり）とし、制度の正式名称・公募回・年度・地域・申請中の情報は入力しない旨を明記したまま保つ。
- 同意チェック（掲載・アカウント公開・体裁編集と Apache-2.0 配布物への収載許諾・投稿権限の表明）を削らない。
- 削除依頼経路と「Issue を閉じても GitHub の公開履歴・通知・複製からは完全には消えない」という撤回限界の明示を維持する。
- 反映 SLA を配布物に書かない（運用約束を配布物に固定しない）。

## 違反例

- 「コントリビュートしやすく」するため public repo で ADOPTERS への直接 PR を受け付ける。
- フォームに公募回・地域の入力欄を追加する。
- 「匿名で掲載できます」という文言に書き換える。

## 関連

- `ADOPTERS.md` ／ `.github/ISSUE_TEMPLATE/adopter-entry.yml` ／ `CONTRIBUTING.md`
