# 設計不変条件 decision records

このディレクトリは、本リポジトリ（および fork）を**運用・改変する AI が設計不変条件を壊さないため**の決定記録集です。人向けの経緯文書ではなく、「決定・制約・違反例」を構造化した運用 AI のコンテキストとして書かれています。

- 対象読者: canonical repo・fork を運用する AI（および人間のメンテナ）
- 位置づけ: ここに書かれた決定に反する変更は「改善」ではなく設計違反です。変更したい場合は canonical repo の Issue で提案してください
- 出典: 各記録の背景となる詳細な検討は内部決定記録（非公開）にあります。公開層には AI 運用に必要な設計判断のみを置きます（事業判断は含みません）

## 一覧

| ID | 決定 |
| --- | --- |
| [DR-001](dr-001-one-paste-url-main-fixed.md) | ワンペースト導線の URL は canonical repo の main 固定 |
| [DR-002](dr-002-setup-gate-entry-unification.md) | `/setup` はゲート・入口手順は統一・全コマンド preflight |
| [DR-003](dr-003-no-eligibility-judgement.md) | 適格性を「判定しない」— 叩き台生成に限定 |
| [DR-004](dr-004-upstream-independent-self-run.md) | 上流非依存で自走可能（継続性の設計不変条件） |
| [DR-005](dr-005-pitfall-to-check-promotion.md) | 落とし穴は文書でなく検査・観点へ昇格させる |
| [DR-006](dr-006-forbidden-expression-check-self-contained.md) | 禁止表現検査は自己完結・文単位判定 |
| [DR-007](dr-007-spec-freshness-machine-gate.md) | spec 鮮度は機械ゲートで判定する |
| [DR-008](dr-008-adopters-canonical-issue-only.md) | ADOPTERS 掲載は canonical repo の Issue フォーム経由のみ |

## 記録の書式

各記録は次の構造を持ちます。

- **決定**: 何を固定したか（1〜3行）
- **理由**: なぜそう固定したか（運用 AI が judgement を再現できる最小限）
- **制約（運用 AI が守ること)**: 実装・改変時に破ってはならない具体条件
- **違反例**: 「改善」に見えるが設計違反である変更の例
