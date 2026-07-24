# DR-007: spec 鮮度は機械ゲートで判定する

> 種別: 設計不変条件 ／ 状態: 有効 ／ 決定日: 2026-07-17 ／ 決定者: DRI ／ 出典: 内部決定記録（非公開）

## 決定

同梱 spec の鮮度は、**表示（鮮度表）と機械ゲート（`bash tools/check-spec.sh <spec> --gate select`）の両方**で扱う。`/select-subsidy` は候補 spec ごとに gate を実行し、失敗した spec は入口A候補から除外して「公式サイト確認 → 入口B」を案内する。AI の注意書きだけで鮮度を扱わない。

## 理由

- 鮮度が失われた spec は無料でも有害（締切切れの制度を案内する事故）。「AI が気をつけて確認する」では決定論的に防げない。
- deadline 評価は WARN（期限切れ告知）と gate の**二重定義を作らない**: 共通 evaluator を1つ定義し両方が使う。判定の食い違いは信頼を壊す。
- 鮮度表は「単一の突合日」表示で全体が新鮮に見える誤読をさせない（突合日の範囲＋件数内訳＋provider 最終確認日＋版固定済み資料数で表示）。

## 制約（運用 AI が守ること）

- deadline 評価関数は `check_spec.py` 内の共通 evaluator に一本化する。時刻の扱い（`time` あり: 基準日時 > 締切日時で経過、締切時刻ちょうどは未経過／`time` null: 日付単位で当日は未経過／JST +09:00 前提）を変更する場合は fixtures を更新する。
- 基準日時は `--now <ISO8601日時>` で注入可能に保つ（決定論的テストのため）。
- bundled spec は `round`・`portal_url`・全 `items[].confirmed_at` を必須とする（checker で強制。スキーマ自体は変えず、顧客の自作 spec では null 可のまま）。
- canonical spec の解決（pack 優先・重複 ID は黙って選ばず FAIL）は `tools/lib/` の共通 resolver に従う。

## 違反例

- `/select-subsidy` の台本に「締切に注意してください」と書くだけで gate 実行を外す。
- 鮮度表を「最終更新: 7/1」の1値表示に簡略化する。
- gate 用に別の日付判定ロジックを新設する（evaluator 二重化）。

## 関連

- [DR-004](dr-004-upstream-independent-self-run.md)／[DR-005](dr-005-pitfall-to-check-promotion.md)
- `specs/README.md`（鮮度表）／ `tools/lib/check_spec.py` ／ `tools/test-check-spec.sh`
