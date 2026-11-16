# review

架空の補助金 `quotes-fixture` に対する検査用の fixture です。空白の有無だけが原本と違います。

## clause-verifier チェック

| 判断 | clause_id | quoted_text | clauses[].text 内の完全一致 | 判定 | リスク |
| --- | --- | --- | --- | --- | --- |
| 補助率の確認 | clause-2 | 補助率は 対象経費の 3分の2以内 | 一致 | green | 低 |
