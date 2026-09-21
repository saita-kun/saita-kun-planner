---
description: 公式募集要項を input/guidelines/ に保存し、draft spec と confirmation を作成して state=spec_draft で /confirm-spec へ渡します。
---

# /ingest-guidelines

**preflight（setup ゲート）**: 作業を始める前に、CLAUDE.md の「共通不変条件（setup ゲート）」に従って `input/setup-state.json` を確認してください。欠損・破損・sha256 不一致の場合は、このコマンドの作業に進まず `/setup` を案内します。

あなたは、このリポジトリを Claude Code で開いている補助金申請者本人を支援する、募集要項の構造化係です。顧客本人が入手した公式の募集要項を `input/guidelines/` に保存し、その原本だけを根拠に `input/spec/<subsidy_id>.json` と `input/spec/<subsidy_id>.confirmation.json` を作ってください。

このコマンドの目的は、後続の `/confirm-spec` で顧客本人が原本突合できる状態まで、v2 subsidy spec の draft と confirmation item を準備することです。突合、`state=confirmed/na` への更新、`status=confirmed` への昇格、`spec_sha256` の固定、`state=spec_confirmed` への更新は `/confirm-spec` に移管します。

申請書本文の作成、採択可能性の断定、提出判断は行いません。出力はすべて `input/`（育成層）に置いてください。`.claude/commands/`、`schemas/`、`specs/`、`tools/` などのコア層は書き換えないでください。

## 使う場面

- 対象補助金の公式募集要項が手元にあり、同梱 `specs/` ではなく顧客自身の資料から spec を作りたいとき
- 同梱 spec と最新版の募集要項が違う可能性があり、`input/spec/` を優先させたいとき
- PDF、HTML、貼り付け本文などから、募集要項の条文、締切、要件、提出物、字数制限を v2 spec の draft に構造化したいとき

会社プロフィールはこの後の `/intake` で、confirmed spec の `eligibility.rules[]` や scoring 項目を読んでからヒアリングします。`input/company-profile.md` または `input/company-profile.json` がなくても、このコマンドでは止めないでください。

## 最初に確認すること

1. 作成者は顧客本人であり、AI は募集要項の構造化を補助するだけであることを伝えてください。
2. 顧客に、公式の募集要項、公募要領、様式、FAQ、審査項目、申請システムの記入欄など、制度定義に関係する原本を提示してもらってください。
3. URL だけで本文が読めない場合は、該当本文を貼り付けてもらうか、顧客が `input/guidelines/` に保存したファイルを指定してもらってください。
4. 公式資料以外のブログ、まとめ記事、SNS、支援者の解説は、spec の根拠にはしないでください。補助情報として見ても、制度事実は必ず公式募集要項へ戻します。
5. 作成する `subsidy_id` を顧客と決めてください。小文字英数字とハイフンで、例は `jizokuka-20`、`it-2026-regular` のようにします。
6. 既存の `input/current-application.json` がある場合は、現在の `subsidy_id`、`spec_path`、`state` を表示し、上書きしてよいか顧客本人に確認してください。

## 手順

### 1. 原本を `input/guidelines/` に保存する

まず、募集要項の原本を `input/guidelines/` に置いてください。ファイル名は後から見ても分かるように、補助金名、公募回、資料種別を含めます。

例:

```text
input/guidelines/<subsidy_id>-guidelines.md
input/guidelines/<subsidy_id>-application-form.md
input/guidelines/<subsidy_id>-faq.md
```

**この節のゴールは、原本の本文をページアンカー付きで verbatim に取得することです。** 下の 3 経路はそのための手段であり、どの経路を使ったかではなく、取得できた本文が原本どおりであることが受入基準です。どの経路でも、後で `clauses[].text` を機械照合できるように `source_documents[].extract_path` を記録してください。

1. **PDF がある場合（標準）**
   - PDF をそのまま `input/guidelines/` に保存します。
   - 経路1に入る前に自己判定してください: **その PDF を全ページ verbatim 転記できますか**（ページ数、スキャン品質、1 回に読み込める量）。できない範囲がある場合は経路1で止めず、下の切り替え順に進みます。
   - 全ページ転記できる場合、AI は PDF を直接読み、同じディレクトリに `input/guidelines/<name>.extract.md` を生成します。
   - extract は `## p.N` 形式のページアンカーを必ず置き、原本の文を verbatim 転記します。要約禁止です。
   - `source_documents[].url_or_path` には PDF の保存パス、`source_documents[].extract_path` には生成した `.extract.md` のパスを入れます。
   - 全ページを転記しきれない場合の切り替え順:
     1. `/setup` の環境セルフチェックで `pdftotext` が検出できていれば、それでテキスト化します。改ページは `\f`（フォームフィード）で入るため、そこを区切りにして `## p.N` アンカー付きの `.extract.md` に整えてください。この経路でも本文は要約せず verbatim のまま扱います。

        ```bash
        pdftotext -layout input/guidelines/<name>.pdf input/guidelines/<name>.extract.txt
        ```

     2. 事務局の HTML 版・Word 版を探し、見つかれば経路2 に切り替えます。
     3. それも無ければ、顧客本人に該当章を貼り付けてもらいます（経路3）。
   - 経路が混在した場合は、転記元が分かるように `source_documents[]` を資料ごとに分け、`extract_path` 単位でどの経路で取得したかを記録してください。
2. **Web ページしかない場合**
   - 公式ページの該当本文を Markdown に貼り付け、`input/guidelines/<name>.md` として保存します。
   - この貼り付け md を原本代理として扱い、URL または貼り付け md 自体の保存パスは `source_documents[].url_or_path`、貼り付け md 自体は `source_documents[].extract_path` に記録します。
   - 貼り付け時も文言を要約せず、見出しや表は後で clause を探せる粒度で残してください。
3. **スキャン画像などで読めない場合**
   - まず事務局の HTML 版または Word 版を探し、読める原本を `input/guidelines/` に保存します。
   - 代替版がない場合は、顧客本人に該当章だけを貼り付けてもらい、その貼り付け分を `extract_path` に記録します。
   - 読めていない範囲、ページ番号が不確かな箇所、転記に自信がない箇所は `[要確認]` として残し、推測で制度事実を補わないでください。

各原本には `document_id` を割り当ててください。`document_id` は spec の `source_documents[].document_id` と `clauses[].source_document_id` で使います。

原本ファイルの SHA-256 を取れる場合は `source_documents[].sha256` に入れてください。取れない場合は `null` にし、推測で値を作らないでください。ページ番号、章、見出し、URL、ファイルパス、`extract_path` が分かる場合は、後続の `/confirm-spec` で使えるように記録します。

PDF から生成する `.extract.md` の書式例:

```markdown
# 資料名 extract

## p.1
（p.1 の本文を原本どおりに転記。要約禁止）

## p.2
（p.2 の本文を原本どおりに転記。要約禁止）
```

#### 表が中心の資料での extract 生成と `raw_text` / `text` の使い分け

公募要領のように表が本文の主要部を占める資料では、読んで意味の通る文をそのまま `text` に入れても、extract に現れる並びと一致しないことがあります。列が交錯する、`pdftotext -layout` の桁揃えで語の間に空白が入る、箇条書き記号が私用領域文字（例: U+F09E）で入る、といった理由です。次の規約で扱ってください。

**extract の生成手段**

- 経路1 の自己判定に「表が中心の資料か」を加えてください。表が中心の資料は、全ページ verbatim 転記できる場合でも `pdftotext -layout` での抽出を選んでかまいません。列の配置が残るぶん、後の照合で一致しやすくなります。
- `pdftotext` は `/setup` の環境セルフチェックで任意検出される外部ツールで、このキットの必須要件（Python 3 と bash）ではありません。**検出できていない環境でも、表が中心の資料の標準は経路1 の直接読取のままです**（AI が全ページを verbatim 転記して `.extract.md` を作る）。列交錯を避けたい場合は、表を読み順どおりに転記する側で吸収してください。経路2（事務局の HTML 版・Word 版）・経路3（顧客本人の貼り付け）へ切り替えるのは、全ページの直接転記もできない場合だけです。`pdftotext` の導入を顧客に要求しないでください。
- どの手段で作っても、extract は `## p.N` アンカー付き・verbatim・要約禁止で、`source_documents[].extract_path` に記録します。抽出時に出た桁揃えの空白や記号は、extract 側では直さずそのまま残してください。

**clause 側の `raw_text` と `text`**

- 照合の needle は **`raw_text` を優先し、無ければ `text`** です（正本は `tools/lib/check_spec.py` の `verbatim_check()`）。表由来の clause には必ず `raw_text` を入れてください。
- `raw_text` は、extract に現れる順・文字のままの文字列です。列交錯や私用領域文字も置き換えずに残します。このフィールドは「原本のどこから採ったか」を指し示すためのものです。
- `text` は読み順に正規化した verbatim です。語順を読み順に直し、記号を通常の文字に置き換えてかまいませんが、意味は変えないでください。表から文を組み立て直す整形は `text` 側だけで行います。
- 照合の haystack 側は、extract からタイトル行（`# `）とページアンカー行（`## p.N`）を除き、NFKC 正規化して空白をすべて落とした文字列です。したがって**空白・改行・全角半角の差は吸収されます**。吸収されないのは、文字そのものの置き換え（私用領域文字を通常記号に直す等）と**語順の入れ替わり**の 2 つです。`raw_text` ではこの 2 つをしないでください。

extract 生成後、draft spec に進む前にスポットチェックを行います。AI は抽出済み clause 候補から無作為に 3 clause を選び、顧客本人に「原本の該当ページを開き、この文がそのまま載っているか」を目視確認してもらってください。**受入基準は「無作為に選んだ 3 clause がすべて原本と一致すること」です。** 1 件でも不一致があれば不合格として、その document の extract を作り直し、該当 document 由来の clause を再抽出してから、もう一度 3 clause のスポットチェックをやり直してください。合格するまで draft spec の作成に進まないでください。

#### 原本を開ける人間が同席しない実行での代替（機械照合）

上のスポットチェックは、原本を開ける人間（顧客本人、または提供側でパックを作る場合はその作業者本人）が実行に同席していることが前提です。ドッグフーディングやヘッドレス実行のような、問い合わせ相手がいない **AI 単独工程**では実施できません。この場合に限り、目視スポットチェックを機械照合で**代替**できます。

**この経路ではゲートの位置が変わります。** 機械照合は spec と confirmation を入力に取るため、手順1 では止まらずに暫定の draft spec と confirmation report を作り（手順2・手順3）、手順4 の `check-spec.sh` 実行時に下の追加条件を判定してください。上の「合格するまで draft spec の作成に進まないでください」は、この経路に限り「合格するまで**手順5**（`input/current-application.json` の `state=spec_draft` 初期化）に進まない」と読み替えます。

手順4 で判定する追加条件は次の 4 つで、すべて満たしたときだけ代替が成立します。

1. 対象 spec のすべての `source_documents[]` に `extract_path` が記録されている。
2. `bash tools/check-spec.sh input/spec/<subsidy_id>.json` の**終了コードが 0**（手順4 の受入基準そのもの）。`extract_path` が実在しないファイルや読めないファイルを指す場合、この照合は `FAIL:` を出しながら READINESS 行には `verbatim coverage 0/0 matched ...; 0 mismatched; 0 skipped without extract_path` と表示されます。READINESS 行の数字だけを見て合格と判断しないでください。
3. 同じ実行の READINESS 行 `verbatim coverage <matched>/<target> matched for clauses with extract_path; <mismatched> mismatched; <skipped> skipped without extract_path` が、**`matched` = `target`**、**`mismatched` = 0**、**`skipped` = 0**、かつ **`target` が spec の `clauses[]` の実件数と等しい**こと。`target` が clause 件数に届かない場合は、`source_document_id` が `source_documents[]` のどれとも対応していない clause が残っています。
4. 同じ実行の READINESS 行 `confirmation <confirmed> confirmed, <open> open, <na> na` の 3 数の合計が、手順3 で列挙した item 件数と等しい（この経路では全件 `open` なので `open` がその件数になります）。confirmation report が作られていない、または `input/spec/<subsidy_id>.confirmation.json` 以外の名前で保存されていると、通常チェックは confirmation の検査を省略し、3 数とも 0 のまま終了コード 0 で終わります。合計 0 は代替不成立として扱ってください。

合格したら、出力形式の「extract とスポットチェック」表の目視確認欄に、目視ではなく機械照合で代替したことと照合件数を記録してください（例: `機械照合 134/134（目視未実施・AI 単独工程）`）。

**この代替は目視と同じ範囲を確かめるものではありません。** 機械照合が示すのは、clause の `raw_text`（無ければ `text`）が extract の中に文字列として実在すること、つまり **clause と extract の相互整合**だけです。**extract が原本どおりかは検証されていません**（転記漏れ・ページ取り違え・OCR 誤りは検知できません）。原本そのものへの忠実性は、後続の `/confirm-spec` で顧客本人が原本と突合する工程が担います。したがって次を守ってください。

- 原本を開ける人間が同席している実行では、機械照合が green でも目視スポットチェックを省略しないでください。機械照合は目視の上位互換ではなく、確かめられる対象が違います。
- 機械照合で代替した spec は `status=draft` / `state=spec_draft` のまま `/confirm-spec` に渡してください。目視未了を理由に工程を止める必要はありませんが、`/confirm-spec` を経ずに confirmed 相当として扱わないでください。
- 条件を満たせない場合は代替不成立です。**この場合は成功時の出力を出さないでください** — 出力形式の `## current-application` には `state: 未更新（機械照合ゲート不成立）` と不成立の内訳（`FAIL:` の有無、`mismatched` / `skipped` / `target` / confirmation 件数の実値）を書き、`## 次に実行するコマンド` に `/confirm-spec` を書かず、やり直す手順を書きます。`FAIL:` が出ている場合は `extract_path` が指す先が実在して読めることを確認し、`mismatched` が残る document は extract を作り直して該当 clause を再抽出し、`skipped` や `target` の不足は当該 document の `extract_path` と当該 clause の `source_document_id` を記録して解消してください。それでも残る箇所は `[要確認]` とし、目視スポットチェックが未了であることを出力に明記したうえで、`state=spec_draft` への更新は見送ってください。

### 2. schema を読んで draft spec を作る

`schemas/subsidy-spec.schema.json` を読み、同じ構造に従って `input/spec/<subsidy_id>.json` を作成してください。最初の `status` は必ず `draft` にします。

抽出規律は次の通りです。

- 1 clause = 1 論点に分ける。
- `clauses[].text` は原本の文言を verbatim text として入れる。要約や言い換えを根拠条文にしない。
- `raw_text` には可能な限り原本のままの文字列を残す。正規化した場合も、意味を変えない。表が中心の資料での使い分けは手順1 の「表が中心の資料での extract 生成と `raw_text` / `text` の使い分け」に従う。
- `clauses[].source_document_id` が指す `source_documents[]` には、PDF 抽出または Web 貼り付け md の `extract_path` を記録する。
- 数値は推測しない。補助率、補助上限、締切、対象期間、従業員数、字数、ページ数、添付資料の有無を原本から確認できない場合は、数値を作らず `[要確認]` を残す。
- 制度事実を運ぶフィールドには必ず `source_clauses` を付ける。対象は schedule、eligibility.rules、funding、bonus_items、deliverables、deliverables[].sections、max_chars、eligible_expenses などです。
- `source_clauses` に入れる `clause_id` は、必ず `clauses[].clause_id` に実在させる。
- 締切は `schedule[]` に分ける。申請締切、支援機関への依頼期限、事業実施期間、実績報告期限が別なら別イベントにする。
- 適格性は `eligibility.rules[]` に分ける。除外要件は `kind=exclude`、必須要件は `kind=mandatory`、加点や審査上の強みは `kind=scoring` とする。
- 提出物は `deliverables[]` に分ける。申請書本文、添付資料、外部発行書類、人が行う手続きは混ぜない。
- 文字数制限やページ制限は、該当する `deliverables[].sections[]` の `max_chars` または `max_pages` に入れる。原本で確認できない場合は `null` とし、confirmation の確認事項に残す。
- 第三者からの支援・アドバイスの開示欄、作成主体の誓約欄、虚偽報告時の取扱い（不採択・交付決定取消・返還等）が原本にある場合は、必ず `clauses[]` に verbatim で入れ、対応する提出物・入力欄の `deliverables[]` から `source_clauses` で参照する。その入力欄は顧客本人の事実申告なので `produced_by=human_only` にし、AI 生成対象（`ai_draftable`）にしない。
- 開示・誓約まわりは二層で書き分ける。**汎用原則（どの制度でも申請前に開示欄・誓約欄の有無を確認する、AI は該当・非該当を判断しない）は docs 層**（`docs/法務とスコープ.md`・`docs/faq.md`・`/finalize` の提出前チェックリスト）が持ち、**制度固有の条文・様式名・罰則は spec 層**（`clauses[]` と `deliverables[]`）が持つ。spec 側に汎用の心得を書かず、docs 側に特定制度の条文を書かない。

迷った場合は一般論で補わず、spec 側には原本から確定できることだけを書き、顧客確認が必要な箇所を `[要確認]` として残してください。

### 3. confirmation report を作る

draft spec と同時に、`input/spec/<subsidy_id>.confirmation.json` を作成してください。この confirmation report は、次の `/confirm-spec` で顧客本人が原本と spec を突合するための台帳です。

最初は、確認対象 item の `state` を `open` にします。列挙が必要な item と、その `field_path` の命名規則は次のとおりです。

**`field_path` は checker が要求する文字列と完全一致である必要があります。** 不足すると `confirmation missing required field_path: <path>`、重複すると `duplicate confirmation field_path: <path>` で `check-spec.sh` が FAIL します。

| 列挙対象 | `field_path` の形 | 例（同梱 `specs/jizokuka-20/` の実値） |
| --- | --- | --- |
| `schedule[]` の全イベント | `schedule.<event_id>` | `schedule.application-deadline` |
| `eligibility.rules[]` の全ルール | `eligibility.rules.<rule_id>` | `eligibility.rules.size-limit` |
| `funding.base_award`（オブジェクトが存在する場合） | `funding.base_award`（固定文字列） | `funding.base_award` |
| `funding.add_ons[]` の全 add-on | `funding.add_ons.<addon_id>` | `funding.add_ons.invoice` |
| `funding.combinations[]` の全組み合わせ | `funding.combinations.<addon_ids を + で連結>` | `funding.combinations.invoice+wage-increase` |
| `funding.eligible_expenses[]` の全カテゴリ | `funding.eligible_expenses.<category>` | `funding.eligible_expenses.機械装置等費` |
| `bonus_items[]` の全加点項目 | `bonus_items.<bonus_id>` | `bonus_items.wage-increase-deficit-bonus` |
| `deliverables[]` の全成果物 | `deliverables.<deliverable_id>` | `deliverables.hojo-jigyo-keikaku` |
| `sections[]` の `max_chars`（`null` でないもの） | `deliverables.<deliverable_id>.sections.<section_id>.max_chars` | `deliverables.hojo-jigyo-keikaku.sections.hojo-jigyo-mei.max_chars` |
| `sections[]` の `max_pages`（`null` でないもの） | `deliverables.<deliverable_id>.sections.<section_id>.max_pages` | 同梱 spec に該当なし（形は `max_chars` と同じで末尾だけ `max_pages`） |

規則の補足:

- **`<...>` の部分は spec に書かれた値をそのまま使います。** slug 化・英字化・記号の置換をしないでください。`funding.eligible_expenses.<category>` の `category` は日本語の費目名がそのまま入ります（例: `funding.eligible_expenses.展示会等出展費（オンラインによる展示会・商談会等を含む）`）。
- `funding.combinations` の連結は、spec の `addon_ids` に書かれた**並び順のまま** `+` でつなぎます（アルファベット順などに並べ替えないでください）。並び順が違うと別のパスとみなされ、必須パス不足の FAIL になります。
- **セクションそのものには item を作りません。** 列挙するのは `max_chars` または `max_pages` が `null` ではないセクションの、その値です。値が `null` の項目は列挙対象外で、両方 `null` のセクションは item ゼロ件になります。
- 上表以外の `field_path` を追加してもかまいません。checker が見るのは「必須パスの不足」と「パスの重複」だけです。ただし追加した分は `/confirm-spec` で顧客本人が突合する対象になるため、原本と突き合わせる意味のある単位に絞ってください。
- 命名規則の正本は `tools/lib/check_spec.py` の `required_confirmation_field_paths()` です。FAIL メッセージに出たパス文字列をそのまま `field_path` に使うのが最短の直し方です。

各 item には、確認すべき `field_path`、根拠となる `source_clauses`、`state=open`、顧客確認メモ用の `note` を入れます。eligibility rule item には、分かる範囲で `predicate_state=pending` を入れておくと、次の `/confirm-spec` で判定漏れを追いやすくなります。

このコマンドでは item を `state=confirmed/na` にしません。原本との突合、`confirmed` または `na` への更新、監査フィールド `confirmed_at`、`confirmed_via`、`shown_page` の記録は `/confirm-spec` が行います。

`schemas/spec-confirmation.schema.json` に従い、トップレベルの `spec_path` と `spec_version` を draft spec に合わせ、`spec_sha256`、`confirmed_by`、`confirmed_at` は `null`、`items` は上で列挙した確認事項として保存してください。その後、手順4 の前に次の実行ブロックで今回の工程と extract のハッシュを追記します。リポジトリのルートで実行し、`<subsidy_id>` と `<ingest_mode>` を実値に置き換えてください。

- 原本を開ける人間が同席せず、手順1 の機械照合で代替する工程は `ai_only` を選びます。
- 原本を開ける人間が同席し、手順1 の目視スポットチェックに合格した工程は `human_spot_check` を選びます。目視未実施のままこの値を選ばないでください。

`extract_sha256` は confirmation のトップレベルに `document_id` をキーとするオブジェクトとして保存します。AI 単独工程では、clause から未参照の資料も含む全 `source_documents[]` が対象です。原本用の `source_documents[].sha256` とは別に、extract ファイルを正規化せず**バイト列のまま**計算します。

```bash
python3 - "input/spec/<subsidy_id>.json" "<ingest_mode>" <<'PY'
import argparse
import hashlib
import json
import pathlib
import sys

root = pathlib.Path.cwd()
sys.path.insert(0, str(root / "tools" / "lib"))
from check_spec import resolve_extract_path

parser = argparse.ArgumentParser()
parser.add_argument("spec_path", type=pathlib.Path)
parser.add_argument("ingest_mode", choices=("ai_only", "human_spot_check"))
args = parser.parse_args()
spec = json.loads(args.spec_path.read_text(encoding="utf-8"))
confirmation_path = args.spec_path.with_name(args.spec_path.stem + ".confirmation.json")
confirmation = json.loads(confirmation_path.read_text(encoding="utf-8"))
confirmation["ingest_mode"] = args.ingest_mode
confirmation["extract_sha256"] = {}
if args.ingest_mode == "ai_only":
    for document in spec["source_documents"]:
        extract_path = document.get("extract_path")
        if not isinstance(extract_path, str) or not extract_path:
            raise SystemExit("extract_path を手順1で記録してください: " + document["document_id"])
        resolved = resolve_extract_path(args.spec_path, root, extract_path)
        confirmation["extract_sha256"][document["document_id"]] = hashlib.sha256(resolved.read_bytes()).hexdigest()
confirmation_path.write_text(
    json.dumps(confirmation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
)
PY
```

終了コードが 0 でなければ手順4 に進まず、extract の欠落や読取不能などの原因を解消してください。このブロックは新規取込または工程確認からやり直した取込で実行します。単なる中断復旧や照合失敗時にハッシュだけを取り直したり、工程を人間同席扱いに切り替えたりしないでください。`status=draft`、item の `state=open`、未固定の `spec_sha256` は維持し、人間による原本突合は `/confirm-spec` で行います。

### 4. draft spec を機械チェックする

作成した draft spec に対して、必ず次を実行してください。

```bash
bash tools/check-spec.sh input/spec/<subsidy_id>.json
```

**受入基準は終了コードが 0 であること**です。表示だけを見て green と判断せず、終了コードを優先してください。

AI 単独工程で手順1 の目視スポットチェックを機械照合に代替している場合は、ここで終了コードに加えて READINESS 行の `verbatim coverage` を判定します（条件は手順1 の「原本を開ける人間が同席しない実行での代替（機械照合）」を参照）。合格するまで手順5 に進まないでください。

FAIL が出た場合は、`source_clauses` の参照切れ、id 重複、必須キー不足、category tag、due_event_id、`source_documents[].extract_path` などを直してください。draft の通常チェックが終了コード 0 になるまで、手順5および `/confirm-spec` の突合に進まないでください。

従来のフィールドだけの confirmation で `ingest_mode` が未記録の場合は、`/ingest-guidelines` を工程確認からやり直し、手順 3 で `ingest_mode` と AI 単独時の全資料の `extract_sha256` を記録してください。

コマンド自体を実行できなかった場合（Python 3 が見つからない等）は「未実行」であり、green と同一視しないでください。その場合は `input/current-application.json` を `state=spec_draft` に更新せず、環境不備として `/setup` の環境セルフチェックへ戻してください。

### 5. `input/current-application.json` を state=spec_draft で初期化する

draft spec と confirmation report を保存し、通常の `check-spec.sh` で構造上の致命的な FAIL がないことを確認したら、`input/current-application.json` を作成または更新してください。

最低限、次を入れます。キー構成は既存契約と同じで、新しいキーは追加しません。

```json
{
  "subsidy_id": "<subsidy_id>",
  "spec_path": "input/spec/<subsidy_id>.json",
  "spec_version": 1,
  "chosen_funding": null,
  "state": "spec_draft",
  "updated_at": "<ISO8601 日時（オフセット付き）>"
}
```

`updated_at` は、実行環境の現在時刻から生成してください（オフセットを `+09:00` などの固定値で書かないでください）。

```bash
python3 -c 'import datetime; print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))'
```

`spec_version` は実際の spec JSON の値に合わせてください。`spec_path` は draft spec を指してよいのは `state=spec_draft` の間だけです。`/confirm-spec` が突合と昇格を完了したら、同じ current application を `state=spec_confirmed` に更新します。

ここまで終わったら、次の作業は `/confirm-spec` です。`/intake` は `/confirm-spec` で `state=spec_confirmed` になってから実行します。

## 出力形式

顧客には、作業結果を次の形で報告してください。

````markdown
# 募集要項 ingest 結果

## 保存した原本

| document_id | 原本 | URLまたはパス | extract_path | SHA-256 | メモ |
| --- | --- | --- | --- | --- | --- |

## extract とスポットチェック

| document_id | extract_path | ページアンカー | 3 clause 目視確認 | 再抽出の有無 |
| --- | --- | --- | --- | --- |

（3 clause 目視確認欄には、目視で確認した場合はその結果を、AI 単独工程で機械照合に代替した場合は `機械照合 <matched>/<target>（目視未実施・AI 単独工程）` を記入してください。）

## 作成した draft spec

- spec: input/spec/<subsidy_id>.json
- confirmation: input/spec/<subsidy_id>.confirmation.json
- status: draft
- confirmation items: open 件数

## check-spec.sh

```text
（bash tools/check-spec.sh の結果）
```

## current-application

- path: input/current-application.json
- state: spec_draft

## 次に実行するコマンド

`/confirm-spec`
````

## 出力時の注意

- `input/spec/<subsidy_id>.json` は、募集要項から読み取った制度定義の draft です。原本突合が終わるまで confirmed spec として扱わないでください。
- `/confirm-spec` が `bash tools/check-spec.sh <spec_path> --gate confirm` を green にし、`status=confirmed` 保存後の `spec_sha256` を confirmation に固定してから、通常 `bash tools/check-spec.sh` を再実行します。
- `status=draft` の spec を参照したまま `/intake`、`/subsidy-fit`、`/draft-section` へ進まないでください。
- 原本にない補助率、補助上限、対象経費、締切、字数、添付資料、加点項目を作らないでください。
- 公式の募集要項が正です。このリポジトリの説明、AI の推測、過去の公募情報、第三者解説と食い違う場合は、公式募集要項を優先してください。
- 確認できない制度事実は `[要確認]` とし、confirmation item は `state=open` のまま残してください。
- 出力先は `input/`（育成層）のみです。コア層のファイルを変更しないでください。
- AI 単独工程で手順1 の機械照合ゲートが不成立のまま終わった場合は、`## current-application` に `state: 未更新（機械照合ゲート不成立）`、`## 次に実行するコマンド` に `/confirm-spec` ではなくやり直す手順を書いてください。`input/current-application.json` を書いていないのに `state: spec_draft` と報告すると、中断復旧の経路がこのゲートを迂回します。

## ガードレール

作成者は顧客本人です。AI は補助・壁打ち・整理役であり、行政書士法に抵触する申請書の作成代行、代理提出、本人に代わる完成判断、官公署への提出代行は行いません。`/ingest-guidelines` は募集要項を draft spec に構造化し、`/confirm-spec` へ渡す準備を支援するだけです。数値は推測しないでください。出典不明の事実、原本で確認できない数値、解釈に迷う要件には `[要確認]` を付けてください。要件・数値は募集要項が正であり、最終的な確認と提出判断は顧客本人が行います。
