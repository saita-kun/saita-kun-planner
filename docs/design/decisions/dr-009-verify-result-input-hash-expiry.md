# DR-009: 検証結果は判定入力ごと固定し、変われば失効させる

> 種別: 設計不変条件 ／ 状態: 有効 ／ 決定日: 2026-11-16 ／ 決定者: DRI ／ 出典: 内部決定記録（非公開）

## 決定

`/verify` の検証結果（`verify-report.md`）には、本文のハッシュに加えて、提出物の要否を決める判定入力（`required_if` が参照する会社情報と申請の選択）のハッシュ `coverage_inputs_sha256` を記録する。`/finalize` は同じ検査をやり直して得た値と比べ、一致しなければ止めて `/verify` へ戻す。`state=finalized` の後でも `/verify` を再実行できる。

## 理由

- 検証の後に会社情報（例: 従業員数）だけを直すと、必須の提出物が変わっても、本文と spec のハッシュは変わらない。古い「抜けなし」の結果のまま提出前チェックを通ってしまう。
- state の値（`verified`・`finalized`）は「検証した」ことしか示さない。「いまの入力に対して検証した」ことは、証拠（ハッシュ）を突き合わせないと分からない。

## 制約（運用 AI が守ること）

- `coverage_inputs_sha256` の計算は `tools/lib/check_drafts.py` の 1 か所に置く。`/finalize`（`tools/lib/check_finalize.py`）と現在地の表示（`tools/lib/progress.py`）は、その関数の出力を使い、計算を複製しない。
- ハッシュの記録が無い旧い検証結果は、失効として扱う（最新とみなさない）。
- 提出前チェックと現在地の表示は、state の値だけで「済み」にしない。
- `/verify` は `verified` と `finalized` のどちらからでも再実行できるように保つ。

## 違反例

- `/finalize` の前提を「state が `verified` であること」だけに簡略化する。
- 会社情報を直した後、検証をやり直さずに `coverage_inputs_sha256` だけを書き換える。
- 現在地の表示用に、別のハッシュ計算を新しく作る。

## 関連

- [DR-007](dr-007-spec-freshness-machine-gate.md)
- `tools/lib/check_drafts.py` ／ `tools/lib/check_finalize.py` ／ `tools/test-check-drafts.sh`（`test_p95_*`）
