# result-report 任意提出ガイド

> この文書は、旧 `collaborator` 招待手順の置き換えです。
> 2026-07-02 の result-report 化と 2026-07-03 のデータ憲章整備により、提供側 GitHub アカウントや org をあなたの private repo に招待する方式は撤回されました。
> 正式な条件は `TERMS.md` 第2条、親規範は `docs/governance/data-charter.md` §4-5、やさしい説明は `docs/data-policy.md` を参照してください。
> **発効日: 2026-07-05**

## 先に結論

- 提供側を private repo の共同作業者として受け入れる必要はありません。
- result-report は任意提出です。非提出でも、ローカルで動く slash command、schema、検証ゲート、manual などの中核機能は使えます。
- 提出する場合も、送るのは採否結果と構造化メタデータだけです。申請本文、事業計画書本文、`input/` の生データ、prompt、AI 応答、生ログは送りません。
- 提出前に JSON プレビューを確認し、consent version を記録します。削除請求に使う ID / receipt も発行します。

## result-report とは

result-report は、提出後または採否判明後に、キット改善のため任意で提出できる狭いレポートです。`/retrospect` が作る `knowledge/records/` の application-record から、データ憲章で許可された項目だけを抜き出す想定です。現時点でこの repo には外部送信機能はありません。

用途は、当面は **キット品質の改善**（prompt、テンプレート、要件マッピング、ドキュメントの改善）と、将来のマッチング品質改善に限定します。個別の result-report を第三者、スポンサー、B2B 顧客へ渡しません。公開する場合は、個社がわからないように秘匿処理した集計だけにします。

## 任意性

result-report を提出しなくても、中核ハーネスは使えます。中核ハーネスとは、この repo 内でローカル実行する slash command、schema、spec、検証ツール、manual、template です。

任意提出者には、公式フィード接続、update-core、最新 spec 受領などの継続的な公式サービスの付加価値を紐づけることがあります。これは非提出者を中核機能から除外する条件ではありません。B2B/有料契約では、result-report を提出しなくても同等機能を利用できる契約上の逃げ道を残します。

## allowlist / denylist の要約

`docs/governance/data-charter.md` §4 が正本です。ここでは要点だけ示します。

| 区分 | 送るもの / 送らないもの |
| --- | --- |
| 送るもの（allowlist） | `report_id`、`schema_version`、`core_version`、提出月、補助金 ID/名称/回、採否結果、申請額・採択額のレンジ、都道府県または地方ブロック、業種分類、従業員数・売上・事業年数などのレンジ、eligibility の boolean/enum 評価、validate の pass/fail や schema errors |
| 送らないもの（denylist） | 申請本文、事業計画書本文、叩き台本文、会社名、代表者名、住所詳細、電話、メール、URL、法人番号、口座/税務情報、添付資料、`input/` 配下のファイル、prompt、AI 応答、対話ログ、生ログ、Git remote、端末ユーザー名 |

自由記述欄は原則禁止です。金額や従業員数なども、生値ではなく band/enum として扱います。

## consent と提出前確認

result-report を提出する実装が入った場合は、次の順で確認します。

1. 送信前に JSON プレビューを表示します。
2. 利用者本人が、送られる項目が allowlist 内に収まっているか確認します。
3. `--consent result-report-vYYYY-MM-DD` または対話確認で consent version を記録します。
4. ドライランでは送信せず、内容だけを表示します。
5. 初回実行時は、何を集めるか、誰が集めるか、無効化方法、詳細 URL を告知します。告知前には一切送信しません。

士業・支援者が顧客本人または法人を代表して result-report を提出する場合は、本人/法人を代表して consent する権限を取得済みであることが前提です。

## 削除・撤回

提出時に削除用 ID / receipt を発行します。削除したい場合は、その ID / receipt を添えて、提供側の削除請求窓口へ連絡します。

削除請求があった場合、raw store から該当 result-report と紐付け情報を削除します。すでに公開・集計済みのスナップショットは遡及変更しませんが、次回の再集計から除外します。

## 旧方式について

旧方式では、事業者直販の利用条件として private repo への共同作業者招待を想定していました。この方式は撤回済みです。現行の正本は `TERMS.md` 第2条と `docs/governance/data-charter.md` §4-5 です。迷った場合は、旧説明ではなくこれらを優先してください。
