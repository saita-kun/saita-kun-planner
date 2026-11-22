# review

架空の補助金 `quotes-fixture` に対する検査用の fixture です。quoted_text が clauses[].text に存在しません。

## clause-verifier チェック

| 判断 | clause_id | quoted_text | clauses[].text 内の完全一致 | 判定 | リスク |
| --- | --- | --- | --- | --- | --- |
| 補助上限の確認 | clause-1 | 補助上限額は100万円 | 一致 | green | 低 |
