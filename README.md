# saita-kun-planner

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![validate](https://github.com/saita-kun/saita-kun-planner/actions/workflows/validate.yml/badge.svg)](https://github.com/saita-kun/saita-kun-planner/actions/workflows/validate.yml)
<!-- validate CI バッジは public repo と workflow が存在した後に描画されます。公開前は 404 になることがあります。 -->

[English](README.en.md)

中小企業・個人事業主が、自分の Claude Code で補助金申請用の事業計画書の叩き台を作るためのキットです。キット本体は無料の OSS（Apache-2.0）ですが、利用には Claude Code の契約環境が必要です。申請代行ではありません。

小規模事業者持続化補助金などの公式公募要領を一次情報として、構造化 spec、検証器、手順、テンプレートを組み合わせた GitHub テンプレート repo です。事業計画書のテンプレートを無料で埋めるだけの雛形集ではなく、公募要領との突合・自社情報の整理・叩き台づくり・機械検証までを、申請者本人が作成主体のまま進められる作業環境です。

## AI に手伝ってもらって始める（推奨）

お使いの AI アシスタント（Claude Code / Claude / ChatGPT など）に、次の文をそのまま貼り付けてください。

> 補助金申請の事業計画書の叩き台を自分で作りたい。
> https://raw.githubusercontent.com/saita-kun/saita-kun-planner/main/docs/ai-agent-guide.md
> を読んで、その手順どおりに私を案内してください。

AI が、前提の確認、作業用 repo の準備、最初のコマンドの実行までを案内します（案内台本は [docs/ai-agent-guide.md](docs/ai-agent-guide.md)）。

お使いの AI が上記 URL を閲覧できない場合は、あなた自身がブラウザで URL を開き、表示された本文をチャットに貼り付けてください。

版を固定したい場合は、`https://raw.githubusercontent.com/saita-kun/saita-kun-planner/v1.0.0/docs/ai-agent-guide.md` のように、タグまたはコミット ID を指定した URL も使えます（既定は最新版の main）。

対象は Claude Code 契約者です。Claude Code の slash commands、同梱の [CLAUDE.md](CLAUDE.md)、[docs/manual.md](docs/manual.md)、テンプレートを使い、公式の募集要項と自社資料を照合しながら、顧客本人が作成主体として事業計画書を整えていきます。

## 何ができるか

- 公式の募集要項を一次情報として読み込み、`/confirm-spec` で顧客本人が原本と突合して confirmed spec にできます。
- confirmed spec から補助金パックを整え、後続の作成・レビューで参照する書き方メモを作れます。
- confirmed spec が求める会社情報、事業内容、課題、投資計画、効果見込みを `input/` に整理できます。
- confirmed spec と会社プロフィールを照合し、除外要件、必須要件、加点要素、不足準備、狙う枠を確認できます。
- AI と作る成果物、人がやること、添付資料、締切を `input/deliverables.md` に整理できます。
- 事業計画書を spec の 1 セクションずつ、補助金審査で見られる「課題、解決策、実現性、効果、数値根拠」の流れで叩き台化できます。
- 作成した叩き台について、根拠不足、誇張、条文引用、`[要確認]`、行政書士法上の作成主体リスクを点検できます。
- `tools/check-spec.sh` と `tools/check-drafts.sh` で、文字数、必須セクション、coverage gaps、draft 本文ハッシュを検証できます。
- 提出前に、verify green、様式、添付資料、期限、顧客本人による最終確認をチェックリスト化できます。
- `/retrospect` で採否や講評から得た学びを `knowledge/` に残し、次回の `/draft-section` と `/review` に活かせます。

この repo は、申請書を自動で完成させるものではありません。AI は補助、壁打ち、整理役です。最終的な内容確認、修正、提出判断は顧客本人が行います。

## 対象の補助金がまだ決まっていない場合

国の補助金の電子申請システム「Jグランツ」の Web 検索（<https://www.jgrants-portal.go.jp/>）で、公募中の補助金を業種や地域から探せます。まずはここで候補を見つけるのが確実です。

AI から補助金を検索したい場合は、[`jgrants-mcp-server`](https://github.com/digital-go-jp/jgrants-mcp-server) を利用する方法もあります。配布元 README では、本実装を、技術検証を目的として公開されているサンプルコードであり、安定性・継続的な保守・検索性は保証されない、としています（出典: <https://github.com/digital-go-jp/jgrants-mcp-server>）。利用は Jグランツ API の利用規約（出典表示を含む）に従ってください。なお、本キットとデジタル庁・Jグランツの間に提携・公認の関係はありません。

どの経路で見つけた場合も、制度事実（対象者、補助率、補助上限、締切、様式）は必ず公式の公募要領で再確認してください。入口B `/ingest-guidelines` に投入するのは、その公式公募要領そのものです。候補の絞り方は [docs/補助金の選び方.md](docs/補助金の選び方.md) を参照してください。

## このリポジトリの使い方（Use this template）

公開元は [saita-kun/saita-kun-planner](https://github.com/saita-kun/saita-kun-planner) です。利用者はこの repo を直接編集するのではなく、GitHub の `Use this template` から自分の作業用 repo を作って使います。

1. GitHub の `Use this template` ボタンから、自分の GitHub アカウントまたは組織に repo を作ります。
2. 補助金申請では会社情報、見積、売上、投資計画などの機密情報を扱うため、作業用 repo は必ず private にしてください。
3. 作成した自分の repo を作業端末に clone します。
4. clone したフォルダをルートとして、新しい Claude Code セッションを開きます。
5. まず `/setup` を実行し、green になったら `/start` へ進みます。

`Use this template` で複製した repo は git 履歴が新規化されます。そのため、上流の更新は git の履歴追跡ではなく、[tools/update-core.sh](tools/update-core.sh) と [core-manifest.json](core-manifest.json) で取り込みます。本家 `saita-kun/saita-kun-planner` がコア層の正史であり、利用者 repo の `input/`、`knowledge/`、`my-*` は利用者側の育成層として残す設計です。

## なぜ無料で公開するのか

補助金には情報の非対称性があります。そもそも制度の存在を知らない、公募要領を読み解けない、読み解けても事業計画書として書けない、という段階ごとに小規模事業者ほど不利になりがちです。

saita-kun-planner のミッションは、その非対称性を減らし、支援がなくても自分で申請できる状態を作ることです。申請者本人が公式の公募要領と自社の実情報を確認しながら、AI を補助役として叩き台を作れるように、構造化 spec、検証器、手順、テンプレートを OSS の公共財として配ります。

この repo はエンジンです。GUI ラッパー、白ラベル UI、業種別の追加テンプレート、自治体別の補助金パックなどが上に生えることを歓迎します。スキーマと spec の扱いが揃えば、補助金情報を読む AI ハーネスのデファクト標準化にもつながります。

信頼原則はシンプルです。spec は公募要領の原文と突合すること、インタビュー設計は実態と乖離した「盛り」を作らないこと、提出は必ず人間が行うことです。AI は申請者の代わりに提出判断をしません。

## AI は利用者持ち込みです

AI は利用者持ち込み（BYO）です。現在のキットは Claude Code に特化しており、`.claude/commands/`、`CLAUDE.md`、Claude Code の作業体験を前提にしています。

将来的に別のエディタ、エージェント、GUI から同じ schema/spec を使うことは歓迎しますが、この README が保証する利用体験は Claude Code で clone した repo を開き、slash command を実行する流れです。

## 動作環境

動作確認済みの環境は macOS / Linux です。bash、git、python3、Claude Code が使える端末での利用を前提にしています。

Windows はフル Windows 対応としては動作確認していません。Windows で使う場合は WSL を推奨します。WSL を使わない場合は、Git Bash と python3 を導入し、`/setup` で案内される環境チェックを通してから進めてください。

## 対象

このキットは Claude Code 契約者に特化しています。次の状態の人向けです。

- GitHub からテンプレート repo を自分の作業用 repo として用意できる。
- clone したフォルダを Claude Code で開ける。
- Claude Code の slash command を使って、`/setup` → `/start` から順に作業できる。
- 公式の募集要項、自社資料、見積書、売上資料、投資計画などを自分で確認できる。
- 補助金申請用の事業計画書について、提出文書そのものではなく、自分で修正する叩き台を作りたい。

Claude Code を使わない一般的な文書テンプレート集ではありません。`.claude/commands/` にある slash commands を前提に、Claude Code 内で段階的に作業する設計です。

## 提供物

- [docs/manual.md](docs/manual.md) — セットアップから `/finalize` までの中心マニュアル。
- [docs/ai-agent-guide.md](docs/ai-agent-guide.md) — repo の外にいる AI アシスタントが、利用者を作業開始まで案内するための台本。
- [README.en.md](README.en.md) — English summary（日本語 README が正本）。
- [CLAUDE.md](CLAUDE.md) — この repo を開いた Claude Code が守る作業方針と法務ガードレール。
- [LICENSE](LICENSE) — Apache-2.0 の配布ライセンス。
- [core-manifest.json](core-manifest.json) — 上流更新で扱うコア層ファイルの正本。
- [NOTICE](NOTICE) — Apache-2.0 の NOTICE と商標参照。
- [ROADMAP.md](ROADMAP.md) — 採択後モジュール、spec レジストリ、補助金パック拡充などの将来方向。
- [TRADEMARK.md](TRADEMARK.md) — 「サイタくん」商標の使用ポリシー。
- [CONTRIBUTING.md](CONTRIBUTING.md) — DCO sign-off を含む貢献ルール。
- [SECURITY.md](SECURITY.md) — 脆弱性の私的報告経路と対象範囲。
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — コミュニティ行動規範。
- [TERMS.md](TERMS.md) — 利用条件、法務スコープ、result-report の任意性。
- [docs/telemetry.md](docs/telemetry.md) — 任意 result-report の収集項目、非収集項目、consent、削除手順。
- [.claude/commands/start.md](.claude/commands/start.md) — 初回案内。
- [.claude/commands/select-subsidy.md](.claude/commands/select-subsidy.md) — 同梱 spec を使う補助金選択。
- [.claude/commands/ingest-guidelines.md](.claude/commands/ingest-guidelines.md) — 公式募集要項の保存、draft spec 化、confirmation 項目の作成。
- [.claude/commands/confirm-spec.md](.claude/commands/confirm-spec.md) — draft spec と募集要項原本の突合確認。
- [.claude/commands/build-pack.md](.claude/commands/build-pack.md) — confirmed spec から書き方メモを作り、補助金パックを整える。
- [.claude/commands/intake.md](.claude/commands/intake.md) — confirmed spec に沿った会社情報と投資計画の整理。
- [.claude/commands/subsidy-fit.md](.claude/commands/subsidy-fit.md) — 募集要項との適合確認。
- [.claude/commands/plan-deliverables.md](.claude/commands/plan-deliverables.md) — 成果物、人がやること、添付、締切の一覧化。
- [.claude/commands/draft-section.md](.claude/commands/draft-section.md) — 1 セクションずつの叩き台作成。
- [.claude/commands/review.md](.claude/commands/review.md) — 根拠、文字数、誇張、作成主体の点検。
- [.claude/commands/verify.md](.claude/commands/verify.md) — spec/draft の機械検証と verify report 作成。
- [.claude/commands/finalize.md](.claude/commands/finalize.md) — 提出前チェックリスト化。
- [.claude/commands/retrospect.md](.claude/commands/retrospect.md) — 提出後・採否判明後の学びの構造化。
- [schemas/](schemas/) — company profile、subsidy spec、application record などの JSON schema。
- [specs/](specs/) — 提供側が確認済みとして同梱する bundled spec。同梱 spec には原本突合日を明記しています（[specs/README.md](specs/README.md) の鮮度表）。制度の正本は常に公式の募集要項です。
- [knowledge/](knowledge/) — `/retrospect` で育つ申請結果・学びの保存場所。
- [templates/](templates/) — ヒアリング、要件マッピング、事業計画書セクション作成の雛形。
- [docs/補助金の選び方.md](docs/補助金の選び方.md) — 対象補助金を選ぶ前の確認手順。
- [docs/事業計画書の構成.md](docs/事業計画書の構成.md) — 標準セクションごとの審査観点。
- [docs/ハーネスの育て方.md](docs/ハーネスの育て方.md) — コア層、育成層、`my-*` コマンド、上流更新の運用ガイド。
- [docs/テンプレートrepoの使い方.md](docs/テンプレートrepoの使い方.md) — `Use this template` から自分の private 作業 repo を用意する手順。
- [docs/法務とスコープ.md](docs/法務とスコープ.md) — 作成主体、申請代行ではない範囲、数値・要件確認の扱い。
- [docs/faq.md](docs/faq.md) — slash command、`input/`、法務上の誤解に関する FAQ。
- [examples/worked-example/](examples/worked-example/) — 架空サンプルの一連の成果物。

## 標準ファイルとコミュニティ導線

- [LICENSE](LICENSE) — コード、テンプレート、ドキュメントの配布ライセンス。
- [TRADEMARK.md](TRADEMARK.md) — 「サイタくん」名称と商標の扱い。
- [CONTRIBUTING.md](CONTRIBUTING.md) — issue、pull request、DCO sign-off のルール。
- [SECURITY.md](SECURITY.md) — 脆弱性を公開 issue ではなく私的に報告するための案内。
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — 参加者間の行動規範。
- [TERMS.md](TERMS.md) — 利用条件、非接触原則、作成主体、result-report の任意性。
- [docs/telemetry.md](docs/telemetry.md) — 収集する可能性がある任意 result-report の allowlist / denylist。
- [ADOPTERS.md](ADOPTERS.md) — 利用・派生事例の一覧（補助金の採択者一覧ではありません）。掲載申告は [Issue フォーム](https://github.com/saita-kun/saita-kun-planner/issues/new?template=adopter-entry.yml) から。

## 5分クイックスタート

1. GitHub で `Use this template` を押し、自分の作業用リポジトリを作ります。詳しい手順は [docs/テンプレートrepoの使い方.md](docs/テンプレートrepoの使い方.md) を確認してください。AI に案内してもらう場合は冒頭の「AI に手伝ってもらって始める」を使ってください。
2. 機密情報を扱うため、作業用リポジトリは必ず private にしてください。
3. 作業端末でリポジトリを git clone します。
4. clone したフォルダをルートとして、新しい Claude Code セッションを開きます。
5. まず `/setup` を実行し、green になったら `/start` を実行します。
6. 迷わなければ 入口A: `/select-subsidy`、または 入口B: `/ingest-guidelines` → `/confirm-spec` → `/build-pack` → `/intake` → `/subsidy-fit` → `/plan-deliverables` → `/draft-section` → `/review` → `/verify` → `/finalize` → `/retrospect` の順に進めます。

初回に全体像を確認したい場合は、先に [docs/manual.md](docs/manual.md) を読んでください。補助金そのものが未定の場合は、[docs/補助金の選び方.md](docs/補助金の選び方.md) で公式情報源と候補の絞り方を確認してから、同梱 spec を使うなら `/select-subsidy`、自分の募集要項から作るなら `/ingest-guidelines` → `/confirm-spec` に進みます。

## 基本フロー

| コマンド | 目的 | 主な出力 |
| --- | --- | --- |
| `/start` | 前提、進め方、法務ガードレールを確認する | 次に実行するコマンドの案内 |
| 入口A: `/select-subsidy` | 対象補助金・公募回が合う bundled spec を選び、公式募集要項と照合する | `input/current-application.json`、`state=spec_confirmed` |
| 入口B: `/ingest-guidelines` | 公式募集要項を保存し、draft spec と confirmation 項目を作る | `input/spec/<subsidy_id>.json`、confirmation、`state=spec_draft` |
| `/confirm-spec` | draft spec と募集要項原本を顧客本人が突合確認する | `status=confirmed`、`state=spec_confirmed` |
| `/build-pack` | confirmed spec から書き方メモを作り、補助金パックを整える | `input/spec/<subsidy_id>/` |
| `/intake` | confirmed spec が求める会社情報、事業内容、課題、投資計画を整理する | `input/company-profile.md`、`input/company-profile.json`、`state=intake_done` |
| `/subsidy-fit` | confirmed spec と自社情報を照合する | `input/subsidy-fit.md`、`chosen_funding`、`state=fit_done` |
| `/plan-deliverables` | 成果物、人がやること、添付、締切を整理する | `input/deliverables.md` |
| `/draft-section` | 事業計画書の 1 セクションを叩き台化する | `input/drafts/<subsidy_id>/<section_id>.md` |
| `/review` | 根拠、条文引用、誇張、`[要確認]`、作成主体を定性点検する | 顧客本人が直すべきレビュー指摘 |
| `/verify` | spec/draft 契約、文字数、coverage gaps、draft 本文ハッシュを検証する | `input/checks/verify-report.md` |
| `/finalize` | verify green、様式、添付、期限、提出前確認を整理する | 提出前チェックリスト |
| `/retrospect` | 結果、講評、学び、次回アクションを残す | `knowledge/records/`、`knowledge/lessons/` |

`/draft-section` は一度で全文を完成させるためのコマンドではありません。顧客本人が選んだ 1 セクションだけを作り、`/review` で根拠と募集要項への適合を確認し、`/verify` で機械検証しながら進めます。

コア層と育成層、`knowledge/`、`my-*` コマンド、上流更新の扱いは [docs/ハーネスの育て方.md](docs/ハーネスの育て方.md) を参照してください。

## `input/` の扱い

`input/` は、顧客本人の会社情報、募集要項メモ、見積書メモ、投資計画、売上資料、従業員数、既存実績、作成中の叩き台を置く作業場所です。`.gitignore` でコミット対象から外しています。

実データを公開リポジトリへ入れないでください。共有や相談が必要な場合も、会社名、取引先名、金額、個人情報、未公開計画などの取り扱いを顧客本人が確認してください。

## 法務ディスクレーマ

作成者は顧客本人です。AI は補助、壁打ち、整理役であり、申請代行ではありません。行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。

数値は推測しません。売上、従業員数、投資額、補助率、補助上限、採択率、効果見込み、KPI、文字数、対象経費、提出期限、添付資料は、顧客の資料または公式の募集要項で確認してください。出典不明の事実、根拠が不足している主張、顧客確認が必要な情報には `[要確認]` を付けます。

公式の募集要項、様式、FAQ、審査項目とこの repo の説明が食い違う場合は、必ず公式資料を優先してください。不安がある場合は、行政書士、商工会議所、商工会、よろず支援拠点、補助金事務局など、適切な専門家や公的支援機関へ確認してください。

詳しい範囲は [docs/法務とスコープ.md](docs/法務とスコープ.md) を確認してください。
