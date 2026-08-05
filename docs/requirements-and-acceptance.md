# 要件・受入基準

関連資料：[実装設計](implementation-design.md)

## 1. 目的

注文、決済、精算が別々に管理される決済業務を想定し、注文単位でデータを照合して、不一致の有無と理由を確認できるデータマートを構築する。

決済運用で発生し得る不一致を業務ルールとして定義し、BigQuery、dbt、SQL、dbt testによって再現・検証できることを目的とする。

## 2. 想定利用者と利用場面

決済・精算の運用担当者による、以下の利用を想定する。

- 注文単位の照合結果を確認する
- 正常取引と異常取引を識別する
- 異常の分類、種類、対象取引を確認する
- エラー種別ごとの発生状況を可視化する
- SQL変更後も判定結果が維持されることを自動テストで確認する

## 3. 対象範囲

### 3.1 対象

- 動作確認用のサンプルCSVのBigQueryへの投入とstagingモデルでの整形
- 注文を母集団とした、決済・加盟店・精算データの照合
- 4分類・12種類の異常判定
- 注文単位の照合結果とエラー種別ごとの明細の出力
- Looker Studioによる照合サマリとエラー明細の可視化
- GitHub Actions上でのdbt testによる品質検証
- dbt Docsによるテーブル・カラム仕様の公開
- 同じ入力データからの全件再構築

### 3.2 対象外

- GCSやAPIなどからの継続的なデータ取込
- 日次スケジュール実行
- 増分更新、遅延到着、実データの再投入制御
- 取込履歴、バッチ監視、障害通知、自動復旧
- 注文に紐づかない決済・精算の検出
- 本番規模の性能、可用性、災害対策
- 実在企業、顧客、取引のデータ利用

本書における再実行は、動作確認用のサンプルCSVを用いた全件再構築を指す。増分更新や本番取込における冪等性は対象としない。

## 4. 入力データ要件

| データ | 粒度 | 主キー | 用途 |
|---|---|---|---|
| merchants | 1加盟店 | `merchant_id` | 加盟店名と手数料率の参照 |
| orders | 1注文 | `order_id` | 照合の母集団 |
| payments | 1決済 | `payment_id` | 注文に対応する決済 |
| settlements | 1精算 | `settlement_id` | 決済に対応する精算 |

入力データは、以下の条件を満たすものとする。

- ヘッダー付きUTF-8 CSVであること
- 金額は日本円の整数、手数料率は小数として扱うこと
- 実在する企業、顧客、取引の情報を含まないこと
- 正常取引および12種類すべての異常を再現できること
- 各テストケースの期待結果を定義できること

項目、データ型、カラムテストは`schema.yml`で管理し、詳細は[dbt Docs](https://naohide-sugita.github.io/payment-reconciliation-data-mart/)で確認する。

## 5. 機能要件

| ID | 要件 |
|---|---|
| FR-01 | 4種類の動作確認用サンプルCSVをBigQueryへ投入できること |
| FR-02 | rawデータを4つのstagingビューへ整形できること |
| FR-03 | 注文を母集団とし、成功した決済を照合対象として結合できること |
| FR-04 | 決済と精算を`settlement_batch_id`で関連付けられること |
| FR-05 | 注文単位で4分類・12種類の異常フラグを算出できること |
| FR-06 | 異常フラグの合計を`error_count`として保持できること |
| FR-07 | `error_count`に基づいて`MATCHED`または`ERROR`と判定できること |
| FR-08 | 異常がある注文を、注文とエラー種別の組み合わせによる明細へ変換できること |
| FR-09 | Looker Studioで4分類・12種類のエラー件数を0件を含めて確認できること |
| FR-10 | dbt testにより、入力データ、モデル、照合結果の品質を検証できること |
| FR-11 | GitHub Actionsでdbtの一連処理とdbt Docs生成を自動実行できること |

## 6. 照合・異常判定要件

| 分類     | ID     | エラーコード                             | エラー理由      | 異常条件                   |
| ------ | ------ | ---------------------------------- | ---------- | ---------------------- |
| データ欠損  | REC-01 | `is_payment_missing`               | 決済データ欠損    | 成功した決済が存在しない           |
| データ欠損  | REC-02 | `is_merchant_missing`              | 加盟店マスタ欠損   | 注文の加盟店IDに対応するマスタが存在しない |
| データ欠損  | REC-03 | `is_fee_rate_missing`              | 手数料率欠損     | 加盟店マスタは存在するが手数料率がない    |
| データ欠損  | REC-04 | `is_settlement_missing`            | 精算データ欠損    | 決済は存在するが対応する精算がない      |
| 処理状態異常 | REC-05 | `is_settlement_not_completed`      | 精算未完了      | 精算状態が`COMPLETED`ではない   |
| データ不一致 | REC-06 | `is_order_payment_amount_mismatch` | 注文・決済金額不一致 | 注文金額と決済金額が一致しない        |
| データ不一致 | REC-07 | `is_merchant_mismatch`             | 加盟店不一致     | 注文側と精算側の加盟店が一致しない      |
| データ不一致 | REC-08 | `is_gross_amount_mismatch`         | 決済・精算総額不一致 | 決済金額と精算総額が一致しない        |
| データ不一致 | REC-09 | `is_fee_amount_mismatch`           | 手数料額不一致    | 実際の手数料と期待手数料が一致しない     |
| データ不一致 | REC-10 | `is_net_amount_mismatch`           | 入金額不一致     | 実際の入金額と期待入金額が一致しない     |
| 日時不正   | REC-11 | `is_payment_datetime_invalid`      | 決済日時不正     | 注文・決済日時がない、または時系列が逆    |
| 日時不正   | REC-12 | `is_settlement_datetime_invalid`   | 精算日時不正     | 決済・精算日時がない、または時系列が逆    |


分類、表示名、表示順は[Looker Studio用エラー種別サマリクエリ](../payment_reconciliation/analyses/looker_studio_error_type_summary.sql)と一致させる。

1つの注文に複数の異常がある場合は、各フラグを独立して保持する。業務上の異常が意図どおり検出されたこと自体は、dbtの実行失敗としない。

## 7. 出力データ要件

### 7.1 注文単位の照合結果

`fct_payment_reconciliation`は1注文1行とし、識別情報、金額、日時、計算値、12種類の異常フラグ、`error_count`、`reconciliation_status`を保持する。

### 7.2 エラー明細

`fct_reconciliation_errors`は1注文・1エラー種別につき1行とし、`order_id`、`error_code`、`error_reason`を保持する。正常な注文は出力せず、複数の異常がある注文は異常の種類ごとに複数行へ展開する。

出力カラムの完全な定義は[dbt Docs](https://naohide-sugita.github.io/payment-reconciliation-data-mart/)を参照する。


### 7.3 可視化

Looker Studioでは、照合サマリとエラー明細を確認できることとする。

照合サマリでは、4分類・12種類のエラー種別ごとの件数を0件も含めて表示する。集計には[`looker_studio_error_type_summary.sql`](../payment_reconciliation/analyses/looker_studio_error_type_summary.sql)を使用する。

エラー明細では、異常が検出された注文について、注文・決済・精算の識別情報、エラー内容、照合対象の金額、精算状態、注文・決済・精算日時を表示する。明細の生成には[`looker_studio_reconciliation_error_details.sql`](../payment_reconciliation/analyses/looker_studio_reconciliation_error_details.sql)を使用し、`fct_reconciliation_errors`と`fct_payment_reconciliation`を結合して原因調査に必要な17項目を出力する。

## 8. 品質要件

- 主キーがNULLまたは重複していないこと
- 必須項目がNULLでないこと
- ステータス値が定義された許容値に含まれること
- モデル間の参照整合性が維持されていること
- 12種類の異常フラグがNULLでないこと
- `error_count`が異常フラグの合計と一致すること
- `reconciliation_status`が`error_count`と矛盾しないこと
- `error_code`が定義された12種類のいずれかであること
- エラー明細が注文単位の照合結果と対応していること
- サンプルデータの期待結果と実際の照合結果が一致すること

テストの実装場所と実行方式は[実装設計](implementation-design.md#7-テスト設計)を参照する。

## 9. 受入基準

| ID | 確認内容 | 合格条件 | 確認方法・確認先 |
|---|---|---|---|
| AC-01 | raw取込 | 4種類の動作確認用サンプルCSVがBigQueryへ作成される | dbt実行結果 |
| AC-02 | staging生成 | 4つのstagingビューが作成され、各seedを参照できる | dbt実行結果、BigQuery |
| AC-03 | 注文単位の出力 | `fct_payment_reconciliation`が1注文1行で出力される | dbt test、BigQuery |
| AC-04 | 異常フラグ | 4分類・12種類の異常フラグが本書の条件に従って判定される | モデルSQL、dbt test |
| AC-05 | 集約判定 | `error_count`が12種類の異常フラグの合計と一致する | 独自SQLテスト |
| AC-06 | 総合状態 | `error_count = 0`なら`MATCHED`、1以上なら`ERROR`となる | 独自SQLテスト |
| AC-07 | 異常パターン | 12種類すべての異常について、対応するサンプルデータと期待結果が定義されている | seed、期待結果、独自SQLテスト |
| AC-08 | 期待結果 | 注文単位の照合結果が定義済みの期待結果と一致する | 独自SQLテスト |
| AC-09 | エラー明細 | 異常フラグが立った注文だけが、エラー種別ごとの明細として出力される | dbt test、BigQuery |
| AC-10 | エラーコード | エラー明細に定義された12種類以外の`error_code`が含まれない | dbt test |
| AC-11 | 可視化 | Looker Studioで4分類・12種類のエラー件数を0件を含めて確認できる | Looker Studio |
| AC-12 | 自動テスト | dbtの汎用テストと独自SQLテストがすべて合格する | dbt実行結果 |
| AC-13 | CI | GitHub Actionsでdbt処理とdbt Docs生成が正常終了する | GitHub Actions |
| AC-14 | 再実行 | 同じ入力データから再構築した場合も照合結果が変化しない | 再実行前後の比較 |
| AC-15 | 公開 | dbt DocsをGitHub Pagesで閲覧できる | GitHub Pages |
| AC-16 | 公開安全性 | 認証情報、秘密鍵、個人情報、実在取引データが公開物に含まれない | 公開前レビュー |
