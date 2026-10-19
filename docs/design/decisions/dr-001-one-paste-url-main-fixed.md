# DR-001: ワンペースト導線の URL は canonical repo の main 固定

> 種別: 設計不変条件 ／ 状態: 有効 ／ 決定日: 2026-07-17 ／ 決定者: DRI ／ 出典: 内部決定記録（非公開）

## 決定

README のワンペーストブロックが指す `docs/ai-agent-guide.md` の URL は、canonical repo（`saita-kun/saita-kun-planner`）の **main 固定の raw URL** とする。fork・配布物・update-core 配布済み README でもこの URL を書き換えない。

## 理由

- ai-agent-guide は仕様書ではなく**案内台本**。配布済み README のワンペースト文がタグ固定 URL だと、古い台本を恒久的に指し続ける害の方が大きい。
- 版の検証可能性へは、guide 冒頭の `guide_version` 自己申告と、「版を固定したい場合」としてタグ/commit 固定 URL の書式を README に併記することで応える。

## 制約（運用 AI が守ること）

- ワンペースト文の既定 URL は canonical main を維持する。fork 側の「利便性改善」として自 fork の URL に書き換えない。
- guide 冒頭の `guide_version`・更新日・canonical repo 表記を削らない。
- URL を閲覧できない AI 向けの代替経路（ユーザーが本文をチャットに貼る）の記載を README ブロックと guide 冒頭の両方に保つ。
- ワンペースト文の主語は本人（法務: 作成主体）を維持する。

## 違反例

- fork の README でワンペースト URL を自分の fork や特定タグに書き換える。
- 「バージョン管理の徹底」を理由に既定 URL をタグ固定へ変更する。
- guide_version の記載を冗長として削除する。

## 関連

- [DR-003](dr-003-no-eligibility-judgement.md)（作成主体の法務境界）
- `docs/ai-agent-guide.md` / `README.md`
