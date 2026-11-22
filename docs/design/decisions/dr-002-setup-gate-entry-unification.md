# DR-002: `/setup` はゲート・入口手順は統一・全コマンド preflight

> 種別: 設計不変条件 ／ 状態: 有効 ／ 決定日: 2026-07-17 ／ 決定者: DRI ／ 出典: 内部決定記録（非公開）

## 決定

`/setup` は利用規約同意・データポリシー確認の**ゲート**であり、完了状態を版つきで `input/setup-state.json` に記録する。`/setup` 以外のすべての slash command は作業前にこの状態を preflight 確認し、不在・破損・sha256 不一致なら作業に進まず `/setup` を案内する。入口手順はすべての文書で `clone → 新規セッション → /setup → /start` に統一する。

## 理由

- 同意確認がゲートになっていないと、利用条件（TERMS / data-policy）への同意という法務前提が迂回可能になる。
- `/start` だけで確認する方式は、直接コマンド実行で迂回できるため不十分。全コマンド preflight が必要。
- 規約改定時は sha256 不一致で自動的に再同意フローへ入る設計であり、この照合を弱めると改定が届かない。

## 制約（運用 AI が守ること）

- 新しい slash command を追加するときは、冒頭に preflight の1行参照を置く。
- 手順を列挙する節（README・使い方文書・guide）では `/setup` と `/start` が両方あり、`/setup` が先であること（validate.sh が節単位で検査）。
- `input/setup-state.json` のスキーマ（`setup_state_version` / `terms_sha256` / `data_policy_sha256` / `result_report_choice`）を互換なく変えない。`input/` は gitignore 済みで顧客ローカルに留める。
- setup-state を AI が自動生成して同意をスキップしない。

## 違反例

- 「クイックスタートを短くする」ため `/setup` を省いて `/start` 直行の手順を書く。
- preflight のないコマンドを追加する。
- sha256 照合を「毎回面倒」としてバージョン番号比較などに緩める。

## 関連

- [DR-003](dr-003-no-eligibility-judgement.md)（法務ガードレール）
- `CLAUDE.md` 共通不変条件 ／ `.claude/commands/setup.md`
