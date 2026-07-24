# FAQ

この FAQ は、Claude Code 契約者が saita-kun-planner を clone して使うときにつまずきやすい点をまとめたものです。補助金申請用の事業計画書は、顧客本人が公式の募集要項と自社資料を確認しながら作成します。AI は補助、壁打ち、整理役であり、申請代行や代理提出は行いません。

数値、要件、文字数、補助率、補助上限、対象経費、提出期限、添付資料は、必ず公式の募集要項または顧客本人の資料を根拠にしてください。確認できない内容は推測せず `[要確認]` として残します。

将来の拡張方向は [ROADMAP.md](../ROADMAP.md) にまとめています。

## Windows で動きますか

動作確認済みの環境は macOS / Linux です。Windows はフル Windows 対応としては確認していません。

Windows で使う場合は WSL を推奨します。WSL 内では Linux と同じように git、bash、python3、Claude Code を用意して進めます。

WSL を使わない場合は、Git Bash + python3 を前提にしてください。Git Bash は Git for Windows に同梱されていますが、案内する配布元は公式の <https://git-scm.com/> のみにしてください。Python は `python3 --version`、`python --version`、Windows の場合は `py -3 --version` の順に確認し、3.x が確認できるコマンドを `/setup` や tools 実行時の読み替えに使います。

どの方法でも、`/setup` で環境セルフチェックを行い、足りないものがあれば公式配布元または OS の公式手順で入れてから再実行してください。

## 許可を求められたら

Claude Code がコマンド実行の許可を求めることがあります。このキットで事前許可しているのは、`tools/check-*.sh`、`tools/draft-hash.sh`、条件判定用の同梱 Python スクリプトなど、キット同梱の検証スクリプトを動かすための read-only 検証系コマンドだけです。

これらの検証は、募集要項 spec、叩き台、補助金パック、draft 本文ハッシュをローカルで確認するために使います。検証スクリプトは読み取り専用で、ファイル書き込みなし、ネットワーク送信なしの前提です。

拒否した場合、check が走らず検証が機能縮退します。これは静かに壊れた状態で進めないための仕組みなので、内容を確認したうえで許可することを推奨します。

`.claude/settings.json` が事前許可している範囲は 7 エントリです。対象は `python3 --version`、`pdftotext` の存在確認、`bash tools/check-spec.sh:*`、`bash tools/check-drafts.sh:*`、`bash tools/check-pack.sh:*`、`bash tools/draft-hash.sh:*`、条件判定用の同梱 Python スクリプト実行に限られます。

初回に workspace trust として、このフォルダを信頼するか確認するダイアログが出ることがあります。`.claude/settings.json` の事前許可は、このダイアログで内容を確認して信頼した後に有効になります。信頼しない場合でも、必要なコマンドを都度確認しながら使えます。

利用者固有の許可を追加する場合は、`.claude/settings.json` ではなく `.claude/settings.local.json` に書いてください。`.claude/settings.local.json` は git 管理外なので、キット更新との衝突を避けられます。

## slash command が出てこない

Claude Code で `/intake` や `/review` などの slash command が候補に出てこない場合は、まず開いている場所を確認してください。

1. clone したこのリポジトリのルートフォルダを Claude Code で開いているか確認します。
2. `.claude/commands/` がリポジトリ直下にあるか確認します。
3. `.claude/commands/start.md`、`.claude/commands/select-subsidy.md`、`.claude/commands/ingest-guidelines.md`、`.claude/commands/confirm-spec.md`、`.claude/commands/build-pack.md`、`.claude/commands/intake.md`、`.claude/commands/subsidy-fit.md`、`.claude/commands/plan-deliverables.md`、`.claude/commands/draft-section.md`、`.claude/commands/review.md`、`.claude/commands/verify.md`、`.claude/commands/finalize.md`、`.claude/commands/retrospect.md` が存在するか確認します。
4. コマンド名は `/start` のように slash から入力します。ファイル名の `.md` は入力しません。
5. 別のフォルダを Claude Code で開いている場合は、このリポジトリを開き直してから再度 slash command を確認します。

それでも表示されない場合は、手作業で該当する command ファイルを開き、本文の指示を Claude Code に貼り付けて進めることもできます。ただし、作成者は顧客本人であり、数値や要件を AI に推測させない点は同じです。

## `input/` に何を置けばよいか

`input/` は、顧客本人の会社情報、募集要項メモ、見積書メモ、投資計画、売上資料、従業員数、既存実績、レビュー対象の叩き台などを置く作業場所です。顧客の機密情報を扱うため、公開リポジトリにコミットしない前提で使ってください。

最初に置くと進めやすいものは次のとおりです。

- `input/company-profile.md` — `/intake` が作る会社プロフィール。
- `input/company-profile.json` — `/subsidy-fit` が機械照合に使う会社プロフィールの正本。
- `input/current-application.json` — 今どの補助金・spec・状態で進んでいるかを後続コマンドに渡す状態ファイル。
- `input/guidelines/` — `/ingest-guidelines` で使う公式募集要項 PDF、貼り付け本文、抽出テキストを置く場所。
- `input/spec/` — `/ingest-guidelines` と `/confirm-spec` が作る顧客本人用の spec と、`/build-pack` が作る補助金パック。
- `input/spec/<subsidy_id>/notes/` — confirmed spec から作る書き方メモ。
- `input/subsidy-fit.md` — `/subsidy-fit` が作る適合度メモ。
- `input/deliverables.md` — `/plan-deliverables` が作る成果物、人がやること、添付、締切の一覧。
- `input/drafts/` — `/draft-section` で作ったセクション別の叩き台。
- `input/reviews/` — `/review` の指摘メモ。
- `input/checks/verify-report.md` — `/verify` が作る spec/draft 検証レポート。
- 募集要項、様式、FAQ、審査項目の抜粋メモ。
- 見積書、仕様書、売上資料、作業時間記録、顧客数、商談記録など、主張の根拠になる資料の要約。

実ファイルを置くか、内容を Markdown に要約するかは作業しやすい方法で構いません。どちらの場合も、資料名、日付、出典、どの数値を使ったかが後から追えるようにしてください。根拠資料が見つからない主張は `[要確認]` とします。

## コマンドの実行順を迷ったら

基本の順番は `/start` → 入口A: `/select-subsidy`、または 入口B: `/ingest-guidelines` → `/confirm-spec` → `/build-pack` → `/intake` → `/subsidy-fit` → `/plan-deliverables` → `/draft-section` → `/review` → `/verify` → `/finalize` → `/retrospect` です。現在は募集要項または同梱 spec を先に confirmed spec として確定し、その spec が求める会社情報を `/intake` で聞く流れを標準にしています。

`/start` は初回案内です。全体像、必要な入力、法務ガードレールを確認します。

入口Aは、同梱 `specs/` の confirmed spec が対象補助金・公募回・様式に合う場合です。顧客本人が公式募集要項と見比べて問題なければ、`/select-subsidy` で `input/current-application.json` を `state=spec_confirmed` にします。書き方メモを整えるなら `/build-pack`、すぐ会社情報へ進むなら `/intake` に進みます。

入口Bは、顧客本人が持つ公式募集要項から `/ingest-guidelines` で draft spec と confirmation 項目を作り、`/confirm-spec` で原本と突合確認する場合です。最新版、別の公募回、別制度、または同梱 spec と公式資料に差がありそうな場合はこちらを使います。`state=spec_draft` の間は突合が未完了なので、次は `/confirm-spec` です。

`/build-pack` は、confirmed spec から補助金パックを整え、書き方メモを作る推奨ステップです。書き方メモは叩き台本文ではなく、`/draft-section` と `/review` が参照する補助資料です。

`/intake` は confirmed spec に沿った会社情報の整理です。会社概要、事業内容、沿革、従業員数、売上規模、課題、投資計画に加え、spec の `eligibility.rules[]` や scoring 項目が参照する会社情報を優先して `input/company-profile.md` と `input/company-profile.json` にまとめ、`state=intake_done` にします。

`/subsidy-fit` は confirmed spec と会社プロフィールの照合です。除外要件、必須要件、加点要素、不足準備、狙う枠 `chosen_funding` を整理し、要件や数値が確認できない箇所に `[要確認]` を付けます。

`/plan-deliverables` は、AI と作る成果物、人がやること、添付資料、締切を `input/deliverables.md` に整理します。

`/draft-section` は 1 セクションだけの叩き台作成です。事業概要、現状課題、事業内容、実施体制、スケジュール、資金計画、効果・KPI のうち、顧客本人が選んだセクションを作ります。

`/review` は根拠と作成主体の定性点検です。募集要項の条文に対応する `clause_id`、`quoted_text`、`judgment_basis`、誇張、捏造、`[要確認]`、行政書士法上の作成主体リスクを確認します。

`/verify` は機械検証です。`bash tools/check-spec.sh` と `bash tools/check-drafts.sh` を実行し、字数、必須セクション、coverage gaps、`[要確認]`、draft 本文ハッシュを `input/checks/verify-report.md` に記録します。

`/finalize` は提出前チェックです。verify green と最新 draft の一致、見出し、文字数、様式、添付資料、期限、顧客本人の最終確認を整理します。提出は顧客本人の責任と判断で行います。

`/retrospect` は提出後または採否判明後の振り返りです。結果、講評、学び、次回アクションを `knowledge/records/` と `knowledge/lessons/` に残します。

途中で戻っても問題ありません。たとえば `/review` で根拠不足が見つかった場合は、`/intake` の情報を補い、必要なら `/subsidy-fit` で募集要項との対応を確認してから、同じセクションを再度 `/draft-section` で整えます。

## spec とは何か

spec は、公式募集要項を Claude Code と検証ツールが扱いやすい JSON に構造化したものです。対象者要件、除外要件、必須要件、加点要素、補助率、補助上限、提出物、締切、事業計画書セクション、文字数、根拠条文などを、`schemas/subsidy-spec.schema.json` に沿って表します。

同梱の `specs/` は、提供側が確認済みとして入れている bundled spec です。顧客本人の手元にある公式募集要項と対象回・様式が一致する場合の出発点になります。今回の公式資料から自分で作る場合は、`/ingest-guidelines` で `input/spec/` に spec を作ります。詳しくは [specs/README.md](../specs/README.md) を参照してください。

spec は機械照合の正本ですが、制度そのものの正本ではありません。公式募集要項、公募要領、様式、FAQ、事務局案内と食い違う場合は、必ず公式資料を優先します。確認できない項目は `[要確認]` のままにしてください。

## confirmation とは何か

confirmation は、spec の各重要項目が公式募集要項のどこに基づくかを顧客本人が突合した記録です。`/ingest-guidelines` はまず `state=open` の確認項目を作り、`/confirm-spec` で顧客本人が原文と照合して `confirmed` または `na` にします。

confirmed spec では、confirmation の `spec_sha256` が spec 本体の SHA-256 と一致している必要があります。これは「確認した spec と、後続コマンドが読む spec が同じ内容か」を守るためです。spec を編集したら confirmation も作り直すか再確認し、`bash tools/check-spec.sh <spec_path>` を通してください。

## current-application.json は何をしているか

`input/current-application.json` は、今の申請案件の状態を後続コマンドに渡す小さな状態ファイルです。主に次の情報を持ちます。

| キー | 役割 |
| --- | --- |
| `state` | `spec_draft`、`spec_confirmed`、`intake_done`、`fit_done`、`planned`、`drafting`、`verified`、`finalized` などの現在地 |
| `subsidy_id` | 対象にしている補助金 spec の ID |
| `spec_path` | 読むべき confirmed spec のパス |
| `spec_version` | spec の版 |
| `chosen_funding` | `/subsidy-fit` で選んだ基本枠・加点枠 |
| `drafts_dir` | `/draft-section` が出力する draft ディレクトリ |

途中再開で迷ったら、`current-application.json` の `state` を見てください。

| state | 次に実行するコマンド |
| --- | --- |
| `spec_draft` | `/confirm-spec` |
| `spec_confirmed` | `/build-pack` をまだ実行していなければ推奨。その後 `/intake` |
| `intake_done` | `/subsidy-fit` |
| `fit_done` | `/plan-deliverables` |
| `planned` | `/draft-section` |
| `drafting` | `/review` または次の `/draft-section` |
| `verified` | `/finalize` |
| `finalized` | 提出後または採否判明後に `/retrospect` |

## 突合が長い・途中でやめたい

`/confirm-spec` は、募集要項と draft spec の突合確認をグループごとに保存します。途中で時間切れになった場合は、そのまま中断して構いません。再開するときは `input/current-application.json` の `state=spec_draft` を確認し、もう一度 `/confirm-spec` を実行してください。

突合中に分からない行がある場合は、AI に推測で confirmed にさせず、該当行を open のまま残すか、顧客本人が公式募集要項、FAQ、事務局、支援機関で確認してください。確認できない数値や要件は `[要確認]` として扱います。

## 公募要領の版が変わったら

公募要領、様式、FAQ、審査項目の版が変わった場合は、古い spec をそのまま使い続けないでください。新しい原本を `input/guidelines/` に保存し、必要に応じて `/ingest-guidelines` からやり直します。その後、`/confirm-spec` で新版の原本と突合し、confirmed spec にしてから `/build-pack`、`/intake` 以降へ進みます。

すでに draft や review がある場合でも、公式資料の版が変わると、文字数、対象経費、補助率、補助上限、添付資料、締切が変わることがあります。差分が小さそうに見えても、顧客本人が原本で確認するまで断定しないでください。

## 書き方メモとは何か

書き方メモは、confirmed spec から作る補助資料です。審査で見られる観点、加点や狙う枠の注意、セクション別に最初に確認することをまとめ、後続の `/draft-section` と `/review` が参照します。

書き方メモは申請書本文ではなく、公式募集要項そのものでもありません。書き方メモにある一般的な助言は、数値や要件の根拠には使いません。補助率、補助上限、対象経費、文字数、締切、添付資料などは、必ず公式募集要項と confirmed spec を優先してください。

## update-core はいつ使うか

`tools/update-core.sh` は、上流テンプレート repo の改善を自分の作業 repo に取り込むためのツールです。`core-manifest.json` に載っているコア層だけを対象にし、`input/`、`knowledge/`、`.claude/commands/my-*.md` は触れません。

GitHub の `Use this template` で作った repo には、通常 upstream remote が最初からありません。上流を別フォルダに clone するか、release を別フォルダに展開してから、まず dry-run します。

```bash
bash tools/update-core.sh --dry-run ../saita-kun-planner-upstream
```

差分を確認して問題なければ apply します。

```bash
bash tools/update-core.sh --apply ../saita-kun-planner-upstream
```

詳しい二層モデル、`my-*` コマンド、`user-modified` の扱いは [ハーネスの育て方](ハーネスの育て方.md) を参照してください。

## knowledge/ は何を入れるか

`knowledge/` は、提出後または採否判明後に育つ長期資産です。`/retrospect` が `knowledge/records/` に JSON 記録を、`knowledge/lessons/` に人間が読める学びを作ります。

次回の `/draft-section` と `/review` は、`knowledge/lessons/` を読み、過去の弱点や改善点を反映します。たとえば「対象経費の根拠資料が不足した」「効果・KPI の数値根拠が弱かった」「添付資料の準備が遅れた」といった学びを、次回の叩き台作成やレビュー観点に使えます。

ただし、knowledge は過去の申請から得た学びであり、今回の募集要項を置き換えるものではありません。今回の spec や公式資料と食い違う場合は、今回の公式資料を優先し、判断が必要な箇所には `[要確認]` を付けてください。

## result-report を出さないと使えないのか

いいえ。result-report は任意提出です。非提出でも、ローカルで動く slash command、schema、spec、検証ツール、manual、template などの中核ハーネスはすべて使えます。

提出した場合、公式フィード接続、update-core、最新 spec 受領などの公式サービスの付加価値に紐づくことがあります。これは採否データ提出を無料利用の必須条件にするものではありません。B2B/有料契約では、result-report を出さずに同等機能を使える道を残します。

送る場合も、対象は `docs/governance/data-charter.md` §4 の allowlist に限られます。申請本文、事業計画書本文、`input/` の生データ、prompt、AI 応答、生ログは送りません。詳しくは [データの扱いについて](data-policy.md) と [データ提供について](telemetry.md) を確認してください。

## 境界線FAQ: 行政書士法との関係

saita-kun-planner は、利用者自身が自分の repo と自分の Claude Code で、自分の申請書類の叩き台を作る自己完結型ソフトです。提供側は利用者の `input/`、叩き台、申請本文の作成に関与しない非接触原則を守ります。

このキットは申請代行、代書、代理提出、本人に代わる完成判断を行いません。AI が出すのは、顧客本人が公式募集要項と自社資料で確認し、修正するための作業メモや叩き台です。行政書士法上の不安がある場合は、行政書士、補助金事務局、公的支援機関へ確認してください。

## 境界線FAQ: 個人情報と result-report

`input/` は利用者の repo にのみ存在する作業場所です。会社情報、見積書メモ、売上資料、従業員数、申請本文、叩き台などの実データを置く場合も、提供側は構造上アクセスできません。公開 repo に機密情報を入れない運用は、利用者本人が確認してください。

result-report は任意提出であり、非提出でも中核機能は使えます。提出する場合も allowlist 限定で、申請本文、事業計画書本文、`input/` の生データ、prompt、AI 応答、生ログは対象外です。個別の result-report をスポンサーや第三者へ渡すこともありません。

## 境界線FAQ: 補助金ビジネス批判への見解

補助金申請の支援業者が悪なのではありません。問題は、支援なしでは回らないほど制度、募集要項、様式、添付、締切、審査観点が複雑になり、情報の非対称性が小規模事業者ほど重くのしかかることです。

saita-kun-planner は、その摩擦を無料の公共財で埋めるための OSS ハーネスです。公式募集要項を構造化し、顧客本人が自社資料と照合しながら叩き台を作れる状態を増やします。専門家の支援が必要な場面は残りますが、支援がなくても申請準備に着手できる基盤を広げることを目指します。

## 行政書士法に関するよくある誤解

このキットは、補助金申請書の作成代行サービスではありません。作成者は顧客本人です。AI は補助、壁打ち、整理役であり、行政書士法に抵触する申請代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。

「AI が文章案を出したら、作成者が AI になるのではないか」と不安になる場合があります。このキットでの位置づけは、顧客本人が自社資料と募集要項を確認しながら、AI の出した叩き台を修正する作業です。顧客本人が根拠を確認し、不要な表現を削り、必要な情報を補い、最終的な内容を判断します。

「このまま提出してよいか」と AI に聞くのは避けてください。AI は提出可否を確定しません。代わりに、`/review` で不足根拠、募集要項との不一致、文字数、添付資料、誇張、`[要確認]` の残りを洗い出し、顧客本人が修正します。

不安がある場合は、行政書士、商工会議所、商工会、よろず支援拠点、補助金事務局など、適切な専門家や公的支援機関へ相談してください。このキットは専門家判断の代替ではありません。

## 補助金が見つからない

対象にする補助金がまだ決まっていない場合は、先に [補助金の選び方](補助金の選び方.md) を読んでください。J-Net21、jGrants、自治体や省庁、補助金事務局などの公式情報源を使い、募集要項、対象者、対象経費、補助率、補助上限、締切、添付資料、審査項目を確認します。

補助金名だけを見て事業計画書を書き始めるのは避けてください。公式の募集要項が手元にない状態では、`/subsidy-fit` で適合度を確認できず、事業計画書の叩き台にも `[要確認]` が多く残ります。

候補が複数ある場合は、次のように整理してから、同梱 spec を使うなら `/select-subsidy`、自分の募集要項から spec を作るなら `/ingest-guidelines` に進む候補を選びます。

| 観点 | 確認すること |
| --- | --- |
| 対象者 | 自社の所在地、業種、規模、法人形態、創業時期が対象に入りそうか |
| 対象事業 | 投資計画が募集要項の対象事業に合うか |
| 対象経費 | 見積予定の経費が対象経費に入るか |
| 締切 | 申請締切、事業実施期間、事前登録、添付資料の準備が間に合うか |
| 審査観点 | 課題、解決策、実現性、効果、数値根拠を自社資料で説明できるか |

どの補助金も合わない可能性がある場合は、無理に申請先を決めず、投資計画、時期、対象経費、地域、事業フェーズを見直してください。採択可能性や補助額を AI に推測させるのではなく、公式情報と支援機関への確認を優先します。

## `[要確認]` が多すぎる

`[要確認]` が多いのは、失敗ではありません。補助金申請では、根拠がないまま断定するほうが危険です。まずは `[要確認]` を次の 3 種類に分けてください。

- 募集要項で確認するもの: 対象者、対象経費、補助率、補助上限、文字数、様式、期限、添付資料。
- 自社資料で確認するもの: 売上、従業員数、投資額、見積額、顧客数、作業時間、既存実績。
- 顧客本人が判断するもの: 事業の優先順位、投資時期、自己負担の可否、提出前の最終判断。

分類できたら、募集要項、自社資料、顧客本人の判断の順に根拠を補ってください。根拠が補えない主張は、断定表現を弱めるか、計画書から外す候補にします。

## どこまで Claude Code に頼ってよいか

Claude Code には、情報整理、質問リスト作成、募集要項との対応表、文章の叩き台、根拠不足の指摘、表現のわかりやすさ確認を依頼できます。

一方で、次のことは Claude Code に任せないでください。

- 実在しない数値や実績を補うこと。
- 公式募集要項にない要件や加点を作ること。
- 採択可能性、補助額、補助率、補助上限を根拠なしに断定すること。
- 顧客本人に代わって提出可否を判断すること。
- 官公署や補助金事務局へ代理提出すること。

迷った場合は、`/review` で根拠と作成主体を点検し、必要に応じて専門家や公的支援機関に確認してください。
