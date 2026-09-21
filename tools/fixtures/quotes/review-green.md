# review

架空の補助金 `quotes-fixture` に対する検査用の fixture です。

## clause-verifier チェック

| 判断 | clause_id | quoted_text | clauses[].text 内の完全一致 | 判定 | リスク |
| --- | --- | --- | --- | --- | --- |
| 補助上限の確認 | clause-1 | 補助上限額は50万円 | 一致 | green | 低 |
| 補助率の確認 | clause-2 | `対象経費の3分の2以内` | 一致 | green | 低 |
| 顧客資料だけに基づく判断 | - | - | - | green | 低 |

## judgment_basis チェック

| 主張 | judgment_basis | 根拠の種類 | 判定 | `[要確認]` の要否 | 顧客本人の確認事項 |
| --- | --- | --- | --- | --- | --- |
| 投資額の妥当性 | 見積書（架空） | 顧客資料 | green | 不要 | 見積書の日付 |
