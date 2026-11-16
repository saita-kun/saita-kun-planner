```json
{
  "spec_check": "green",
  "draft_check": "green",
  "spec_path": "examples/worked-example/pack/spec.sample.json",
  "spec_version": 1,
  "spec_sha256": "4a5fea06f3645a0eb76ee5f357faed860e64888ada1038806a236f914afd0ef6",
  "draft_bodies_sha256": "8a742dd87950d18efe6e98cf163c9a0286d9aee1a9a849f12d1fbfa6f4127b0d",
  "coverage_inputs_sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
  "draft_hash_algorithm": "sha256 over draft body regions (same extraction+normalization as check-drafts and draft-hash.sh; ## 叩き台 to next same-level ## heading or EOF), files sorted by path ascending, joined with \\n---\\n",
  "generated_at": "2026-07-02T12:34:56+09:00"
}
```

# verify report

## 対象

| 項目 | 内容 |
| --- | --- |
| subsidy_id | worked-sample |
| spec_path | examples/worked-example/pack/spec.sample.json |
| spec_version | 1 |
| spec_sha256 | 4a5fea06f3645a0eb76ee5f357faed860e64888ada1038806a236f914afd0ef6 |
| drafts_dir | examples/worked-example/drafts-sample |
| current_application | examples/worked-example/current-application.sample.json |

## check-spec.sh

```text
OK: spec checks passed
```

## check-drafts.sh

```text
INFO: [要確認] total: 0
INFO: [要確認] in draft bodies: 0
INFO: [要確認] in draft body: plan-doc/current-challenge 0
INFO: chars: plan-doc/current-challenge 61/260
INFO: [要確認] in draft body: plan-doc/short-summary 0
INFO: chars: plan-doc/short-summary 17/30
INFO: coverage_inputs_sha256: 4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945
OK: draft checks passed
```

## セクション別の字数

| draft | deliverable_id | section_id | section_name | count | max_chars | result |
| --- | --- | --- | --- | ---: | ---: | --- |
| drafts-sample/current-challenge.md | plan-doc | current-challenge | 現状課題 | 61 | 260 | green |
| drafts-sample/short-summary.md | plan-doc | short-summary | 短文要約 | 17 | 30 | green |

## coverage gaps

なし。`produced_by=ai_draftable` かつ `required=true` の section は、2 件とも `drafts-sample/` に存在します。

## `[要確認]` total

- 本文に残っている `[要確認]`: 0（`plan-doc/current-challenge` 0・`plan-doc/short-summary` 0）
- ファイル全体の `[要確認]` total: 0（雛形の定型行を含む件数）

## 判定

`spec_check=green` かつ `draft_check=green` で、`spec_sha256` は `examples/worked-example/pack/spec.sample.json` の file bytes と一致しています。これは機械検証のサンプルであり、申請書の完成保証ではありません。実際の申請では、募集要項、見積書、添付書類、作成主体を顧客本人が確認してください。

## 次にやること

- `review-note.sample.md` の指摘を、重大度の高いものから顧客本人が直します。直した後は `/review` を全 draft 対象でやり直し、続けて `/verify` を再実行します。
- 実作業では `input/checks/verify-report.md` に `spec_path`、`spec_version`、`spec_sha256`、`draft_bodies_sha256`、`coverage_inputs_sha256` を記録します。このサンプルには coverage の条件判定入力がないため、最後のハッシュは空の snapshot に対応します。
- draft を 1 文字でも直したら、`/verify` を再実行して `draft_bodies_sha256` を更新します。
- `required_if` が参照する会社プロフィールや申請情報のキーを変更したら、`/verify` を再実行します。`/finalize` は同じ引数で draft 検査を再実行し、`coverage_inputs_sha256` が一致しない旧結果を失効扱いにします。
- `/finalize` では、`spec_sha256` が最新 spec の再計算値と一致し、さらに `bash tools/check-spec.sh <spec_path>` が green であることも確認します。
