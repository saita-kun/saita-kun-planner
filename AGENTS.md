# AGENTS.md — saita-kun-planner（Ralph / Codex 向け作業規範）

このリポジトリは **顧客に配布する成果物**（GitHub テンプレート repo）。顧客は
Claude Code を契約しており、これを clone して自分の Claude Code で「補助金申請用の
事業計画書の叩き台」を自走生成する。書く相手は「Claude Code を持つ補助金申請者」。

## プロダクト要点
- ICP: **Claude Code 契約者**（前提として明記してよい。Claude Code ネイティブ機能 ——
  slash command / CLAUDE.md / subagent —— を活用する）。
- スコープ: **補助金申請特化**。一般論ではなく、補助金の審査観点に沿った事業計画書の
  叩き台づくりを支援する。
- 提供形態: `.claude/commands/` の slash command ＋ 同梱 `CLAUDE.md` ＋ `docs/manual.md`。
- 顧客フロー: clone → 新規セッション → /setup → /start → 入口A(/select-subsidy) or 入口B(/ingest-guidelines → /confirm-spec) → /build-pack → /intake → /subsidy-fit → /plan-deliverables → /draft-section → /review → /verify → /finalize → /retrospect。

## 法務ガードレール（必須・全コマンド横断で厳守）
- **作成者は顧客本人**。AI は補助・壁打ちのみ。行政書士法に抵触する「申請代行・代理提出」
  はしない／促さない。各コマンドと CLAUDE.md・manual にこの趣旨を明記する。
- **数値は推測しない**。出典不明の事実には `[要確認]` を付ける。募集要項の定義（文字数・
  要件）を最優先する。捏造防止（judgment_basis / 根拠の明示）を /review に組み込む。

## Definition of Done（このループの green 判定）
- **`bash tools/validate.sh` が exit 0**。各 Wave は自分の成果に対応する構造アサーションを
  `tools/validate.sh` の WAVE EXTENSION POINT 以降に**追加**する（既存アサーションを弱めない）。
- shipped ファイルに `TODO`/`FIXME`/`lorem` 等のプレースホルダを残さない。
- 文章は日本語（顧客向け）。`tools/validate.sh` 内のコメントは英語。slash command は
  frontmatter（`description`）＋手順＋ガードレール注記を持つ。

## やってはいけないこと
- `git add/commit/push` は **しない**（Ralph harness が green 確認後に commit する）。
- network 依存・新規 dependency 追加はしない。リポ外コマンド・破壊的操作はしない。
- 顧客の実データを repo にコミットしない（`input/` は gitignore 済み）。
