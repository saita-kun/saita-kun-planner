# AI アシスタント向け案内台本（ai-agent-guide）

guide_version: 1.0.0 / 更新日: 2026-07-17 / canonical repo: `saita-kun/saita-kun-planner`（<https://github.com/saita-kun/saita-kun-planner>）

この文書は、saita-kun-planner の**外側にいる AI アシスタント**（Claude Code、Claude、ChatGPT など）に向けた案内台本です。利用者（補助金申請者本人）から「この文書の手順どおりに案内して」と依頼されたら、あなた（AI アシスタント）は以下の状態 S0 → S4 を順に進め、利用者を「自分の作業用 repo で最初のコマンドを実行できる状態」まで連れて行ってください。

- この台本の範囲は **S4（最初のコマンド）まで**です。作業内容そのもの（spec 突合・事業計画書の叩き台づくり）は、clone した repo に同梱されている作業方針文書（<https://github.com/saita-kun/saita-kun-planner/blob/main/CLAUDE.md>）と slash command が正です。この台本はそこに踏み込みません。
- あなたがこの文書を URL から取得できない AI の場合の代替経路: 利用者自身にブラウザで <https://raw.githubusercontent.com/saita-kun/saita-kun-planner/main/docs/ai-agent-guide.md> を開いてもらい、表示された本文をチャットに貼り付けてもらってください。
- この文書内のリポジトリ内ファイルへの参照は、すべて GitHub 上の絶対 URL です（あなたが clone 前に読むことを想定しているため）。

## 全体で守るガードレール

どの状態でも、次を守ってください。

- **作成主体は利用者本人です**。あなたは情報整理・壁打ち・案内の補助役であり、申請書の作成代行・代理提出・本人に代わる完成判断はしません。
- **数値・要件を推測しません**。補助率、補助上限、締切、対象者などの制度事実は、公式の公募要領でしか確定できません。出典を確認できない情報には `[要確認]` を付けます。
- 公募回には期限があります。作業が進んだ段階で、対象補助金の**現行の公募回**を公式サイトで確認する工程（同梱の鮮度チェック）がキット側にあります。あなたの案内段階では「古い情報の可能性が常にある」前提で断定を避けてください。
- 利用者の同意なく、外部サービスに repo やアカウントを作成しません。

## S0 現在状態の検出と前提確認

最初に、いまどの状態にいるかを確認します。**順番に確認し、当てはまる分岐に従ってください。**

1. **すでにキットの clone の中にいる場合**（作業ディレクトリに `core-manifest.json` と `.claude/commands/` がある）:
   そのまま作業を始めてはいけません。**その repo が安全な作業場所かを先に確認**します。`gh` CLI が使えるなら次を実行してください。

   ```bash
   gh repo view --json isPrivate,nameWithOwner,templateRepository,viewerPermission
   ```

   次の 3 条件をすべて満たす場合のみ、S3（新しいセッションでの作業開始）へ進んでください。
   - `isPrivate` が true（**private であること**）
   - `nameWithOwner` が `saita-kun/saita-kun-planner` **ではない**こと（canonical 本体を作業場所にしない）
   - `viewerPermission` が書込可能（WRITE / MAINTAIN / ADMIN）であること

   1 つでも満たさない場合（public だった、canonical 本体だった、確認できず不明だった場合を含む）は、**「この repo には機密情報を書き込まないでください」と利用者に警告**し、S1 → S2 で自分の private 作業 repo を作る手順に進んでください。`gh` が使えない場合は、GitHub のリポジトリページ上部に `Private` ラベルが表示されているかを利用者に目視で確認してもらってください。

2. **利用者がまだ何も作っていない場合**: 次の前提を利用者に確認してください。
   - **Claude Code の契約があるか**。このキットの作業体験は Claude Code の slash command を前提にしています。契約がない場合は、無理に進めず、正直にそのことを伝えたうえで、費用や準備の一覧を <https://github.com/saita-kun/saita-kun-planner/tree/main/docs/onboarding> で確認してもらい、ここで案内を終了してください。
   - **GitHub アカウントがあるか**。ない場合は作成が必要です（無料プランで足ります）。
3. **利用者がすでに自分の作業 repo を作成済みで、まだ clone していない場合**（本人がそう言っている場合）: repo を重複作成しないでください。利用者に `<owner>/<repo>` を確認し、それを**引数に明示して**照会します（引数なしの `gh repo view` は「現在のディレクトリの repo」を見るため、clone 前には使えません）。

   ```bash
   gh repo view <owner>/<repo> --json isPrivate,nameWithOwner,templateRepository,viewerPermission
   ```

   上記 1. と同じ 3 条件（private / canonical 本体でない / 書込権限）を確認したら、S1 の 4.（clone 先の絶対パスの同意・不存在・親ディレクトリ書込可否の確認）を経てから、S2 の clone（後半）→ S3 へ進んでください。
4. **あなた自身の実行環境を判定してください**。あなたが「**利用者の端末上の、セッション終了後もファイルが残る永続ファイルシステム**」でコマンドを実行できる場合のみ、以降の手順を自分で実行してかまいません（操作モード）。そうでない場合 — たとえばあなたが Web ブラウザ上のチャット AI である、またはクラウド上の一時的なサンドボックスで動いている場合 — は**代読案内モード**に切り替えてください。代読案内モードでは、あなたは手順を一段階ずつ読み上げて利用者に実行してもらう役に徹し、**自分の環境に clone しません**（一時環境に clone しても、利用者のローカルの Claude Code に引き渡せないためです）。

## S1 作業用 repo 作成の本人同意

repo を作成する前に、次の 4 点を利用者に提示し、**明示的な同意**を得てください（代読案内モードでも同じ内容を口頭確認してください）。

1. **repo 名**（例: `my-subsidy-plan`）
2. **所有者**: `<owner>/<repo>` の形で明示します（owner は利用者個人のアカウントか、利用者の組織か）。
3. **必ず private にすること**。補助金申請では会社情報・売上・投資計画などの機密情報を扱うためです。
4. **clone 先の絶対パス**（例: `/Users/<名前>/projects/my-subsidy-plan`）。指定パスがまだ存在しないこと、親ディレクトリに書き込みできることを事前に確認してください。

**同意なく外部サービスに repo を作成しないでください。**

## S2 repo 作成と clone

操作モードの場合、作成と clone を**分けて**実行します（1 コマンドにまとめると、S1 で合意した所有者や clone 先が反映されないためです）。

1. 認証確認:

   ```bash
   gh auth status
   ```

2. repo 作成（S1 で合意した `<owner>/<repo>` を明示。**`--clone` は付けません**）:

   ```bash
   gh repo create <owner>/<repo> --template saita-kun/saita-kun-planner --private
   ```

3. clone（S1 で合意した絶対パスへ）:

   ```bash
   gh repo clone <owner>/<repo> "<承認済みの絶対パス>"
   ```

   clone 先のパスは必ず引用符で囲んでください（パスに空白が含まれる場合の失敗を防ぐため）。

- **2. が成功して 3. が失敗した場合**: 「repo は GitHub 上に作成済みで、手元への clone だけが失敗している」という現在の状態を利用者に明示してから、再試行または下記 UI 手順への切り替えを案内してください。黙って repo を作り直さないでください。
- `gh` がない・未認証・代読案内モードで、**利用者がまだ repo を作っていない場合**は、GitHub の Web UI で行います: テンプレートページ（<https://github.com/saita-kun/saita-kun-planner>）で `Use this template` → `Create a new repository` を選び、owner と repo 名を設定し、**Private を選択**して作成 → 作成した repo を `git clone`（または GitHub Desktop）で S1 の clone 先へ取得、の順に一段階ずつ案内してください。
- `gh` がない・未認証で、**利用者が既に自分の作業 repo を作成済みの場合**（S0 の 3.）: 新しい repo を作らないでください。利用者に GitHub 上でその repo のページを開いてもらい、`Private` ラベルを目視確認のうえ、`Code` ボタンから clone 用 URL を取得して `git clone`（または GitHub Desktop）で S1 の clone 先へ取得する手順を案内してください。
- うまくいかない場合は、エラーメッセージを推測で握りつぶさず、利用者向け手順 <https://github.com/saita-kun/saita-kun-planner/blob/main/docs/テンプレートrepoの使い方.md> を案内してください。

## S3 新しい Claude Code セッションへの引き渡し

clone が完了したら、利用者に次を案内してください。

- **clone したディレクトリをルートとして、新しい Claude Code セッションを開いてください**。同梱の作業方針文書（<https://github.com/saita-kun/saita-kun-planner/blob/main/CLAUDE.md>）は、セッションの起点が repo のルートにあるときに読み込まれます。
- **この文書を読んでいる現在のセッションの役目はここで終了です**。以降の作業は、新しいセッション側の同梱作業方針文書と slash command が引き継ぎます。

## S4 最初のコマンド

新しいセッションで、次の順に実行するよう案内してください（この順序は固定です）。

1. `/setup` — 環境セルフチェックと利用規約の同意確認を行います。
2. `/setup` が green になったら `/start` — キットの全体像・作業順・法務ガードレールを確認し、入口A（同梱 spec）/ 入口B（自分の公募要領から spec 化）へ進みます。

## 最初の 30 分で得られるもの（正直な期待値）

利用者に過大な期待を持たせないでください。状況により、最初の 30 分で到達できるのは次のいずれかです。

- **対象補助金が同梱 spec にあり、公式公募要領と自社資料が手元にある場合**: `/setup` → `/start` → `/select-subsidy` → `/intake` 着手まで。対象補助金の spec 確認と、自社情報の整理開始・不足情報リストの入手。
- **対象補助金が未定、または資料が未準備（入口Bを含む）の場合**: 環境確認の完了と、公式資料の収集リスト（何をどこから入手するか）まで。

どちらの場合も、**30 分で申請書や事業計画書が完成するとは案内しないでください**。事業計画書の叩き台は、その後 `/draft-section` で 1 セクションずつ作り、`/review` と `/verify` で確認しながら進めるものです。

## うまくいかないとき

- よくある質問: <https://github.com/saita-kun/saita-kun-planner/blob/main/docs/faq.md>
- 非エンジニア向けの初回準備: <https://github.com/saita-kun/saita-kun-planner/tree/main/docs/onboarding>
- テンプレート repo の使い方: <https://github.com/saita-kun/saita-kun-planner/blob/main/docs/テンプレートrepoの使い方.md>
