```json
{
  "spec_check": "green",
  "draft_check": "green",
  "spec_path": "examples/worked-example/pack/spec.sample.json",
  "spec_version": 1,
  "spec_sha256": "32b54f12c01303468a820c25bb2b34e7ba536eac34945be7b487348aa0a0b7c0",
  "draft_bodies_sha256": "8a742dd87950d18efe6e98cf163c9a0286d9aee1a9a849f12d1fbfa6f4127b0d",
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
| spec_sha256 | 32b54f12c01303468a820c25bb2b34e7ba536eac34945be7b487348aa0a0b7c0 |
| drafts_dir | examples/worked-example/drafts-sample |
| current_application | examples/worked-example/current-application.sample.json |

## check-spec.sh

```text
OK: spec checks passed
```

## check-drafts.sh

```text
INFO: [要確認] total: 0
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

`[要確認]` total: 0

## 判定

`spec_check=green` かつ `draft_check=green` で、`spec_sha256` は `examples/worked-example/pack/spec.sample.json` の file bytes と一致しています。これは機械検証のサンプルであり、申請書の完成保証ではありません。実際の申請では、募集要項、見積書、添付書類、作成主体を顧客本人が確認してください。

## 次にやること

- 実作業では `input/checks/verify-report.md` に `spec_path`、`spec_version`、`spec_sha256`、`draft_bodies_sha256` を記録します。
- draft を 1 文字でも直したら、`/verify` を再実行して `draft_bodies_sha256` を更新します。
- `/finalize` では、`spec_sha256` が最新 spec の再計算値と一致し、さらに `bash tools/check-spec.sh <spec_path>` が green であることも確認します。
