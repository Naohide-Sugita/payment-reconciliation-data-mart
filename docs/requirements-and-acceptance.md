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

- 動作確認用のサンプルCSVのBigQueryへの投入とStagingモデルでの整形
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

入力項目、入力時のデータ型およびカラムテストは`schema.yml`で管理し、詳細は[dbt Docs](https://naohide-sugita.github.io/payment-reconciliation-data-mart/)で確認する。

## 5. Staging整形要件

Stagingモデルでは、Rawデータの業務上の意味を維持したまま、後続モデルで照合、計算およびテストに利用できる形式へ標準化する。

| 対象 | 整形要件 |
|---|---|
| 文字列 | ID、名称、ステータスなどの前後空白を除去する |
| ステータス | 決済状態および精算状態を大文字へ統一する |
| 金額 | 注文金額、決済金額、精算総額、手数料額、入金額を`INT64`型へ変換する |
| 手数料率 | 加盟店の手数料率を`NUMERIC`型へ変換する |
| 日時 | 注文日時、決済日時、精算日時を`TIMESTAMP`型へ変換する |
| 空文字 | 決済データの空の精算バッチIDをNULLへ変換する |
| 変換エラー | 数値または日時へ変換できない値は、処理全体を失敗させずNULLとして扱う |

カラム単位のデータ型、整形内容およびテストは、各Stagingモデルのdbt Docsで確認する。

- [`stg_merchants`](https://naohide-sugita.github.io/payment-reconciliation-data-mart/#!/model/model.payment_reconciliation.stg_merchants)
- [`stg_orders`](https://naohide-sugita.github.io/payment-reconciliation-data-mart/#!/model/model.payment_reconciliation.stg_orders)
- [`stg_payments`](https://naohide-sugita.github.io/payment-reconciliation-data-mart/#!/model/model.payment_reconciliation.stg_payments)
- [`stg_settlements`](https://naohide-sugita.github.io/payment-reconciliation-data-mart/#!/model/model.payment_reconciliation.stg_settlements)

## 6. 機能要件

| ID | 要件 |
|---|---|
| FR-01 | 4種類の動作確認用サンプルCSVをBigQueryへ投入できること |
| FR-02 | Rawデータを4つのStagingビューとして参照し、5章のStaging整形要件に従って標準化できること |
| FR-03 | 注文を母集団とし、成功した決済を照合対象として結合できること |
| FR-04 | 決済と精算を`settlement_batch_id`で関連付けられること |
| FR-05 | 注文単位で4分類・12種類の異常フラグを算出できること |
| FR-06 | 異常フラグの合計を`error_count`として保持できること |
| FR-07 | `error_count`に基づいて`MATCHED`または`ERROR`と判定できること |
| FR-08 | 異常がある注文を、注文とエラー種別の組み合わせによる明細へ変換できること |
| FR-09 | Looker Studioで4分類・12種類のエラー件数を0件を含めて確認し、異常注文の原因調査に必要な17項目を確認できること |
| FR-10 | dbt testにより、入力データ、モデル、照合結果の品質を検証できること |
| FR-11 | GitHub Actionsでdbtの一連処理とdbt Docs生成を自動実行できること |

## 7. 照合・異常判定要件

| 分類 | ID | エラーコード | エラー理由 | 異常条件 |
|---|---|---|---|---|
| データ欠損 | REC-01 | `is_payment_missing` | 決済データ欠損 | 成功した決済が存在しない |
| データ欠損 | REC-02 | `is_merchant_missing` | 加盟店マスタ欠損 | 注文の加盟店IDに対応するマスタが存在しない |
| データ欠損 | REC-03 | `is_fee_rate_missing` | 手数料率欠損 | 加盟店マスタは存在するが手数料率がない |
| データ欠損 | REC-04 | `is_settlement_missing` | 精算データ欠損 | 決済は存在するが対応する精算がない |
| 処理状態異常 | REC-05 | `is_settlement_not_completed` | 精算未完了 | 精算状態が`COMPLETED`ではない |
| データ不一致 | REC-06 | `is_order_payment_amount_mismatch` | 注文・決済金額不一致 | 注文金額と決済金額が一致しない |
| データ不一致 | REC-07 | `is_merchant_mismatch` | 加盟店不一致 | 注文側と精算側の加盟店が一致しない |
| データ不一致 | REC-08 | `is_gross_amount_mismatch` | 決済・精算総額不一致 | 決済金額と精算総額が一致しない |
| データ不一致 | REC-09 | `is_fee_amount_mismatch` | 手数料額不一致 | 実際の手数料と期待手数料が一致しない |
| データ不一致 | REC-10 | `is_net_amount_mismatch` | 入金額不一致 | 実際の入金額と期待入金額が一致しない |
| 日時不正 | REC-11 | `is_payment_datetime_invalid` | 決済日時不正 | 注文・決済日時がない、または時系列が逆 |
| 日時不正 | REC-12 | `is_settlement_datetime_invalid` | 精算日時不正 | 決済・精算日時がない、または時系列が逆 |

分類、エラー理由、表示順は[Looker Studio用エラー種別サマリクエリ](../payment_reconciliation/analyses/looker_studio_error_type_summary.sql)と一致させる。

1つの注文に複数の異常がある場合は、各フラグを独立して保持する。業務上の異常が意図どおり検出されたこと自体は、dbtの実行失敗としない。

## 8. 出力データ要件

### 8.1 注文単位の照合結果

`fct_payment_reconciliation`は1注文1行とし、識別情報、金額、日時、計算値、12種類の異常フラグ、`error_count`、`reconciliation_status`を保持する。

### 8.2 エラー明細

`fct_reconciliation_errors`は1注文・1エラー種別につき1行とする。正常な注文は出力せず、複数の異常がある注文は異常の種類ごとに複数行へ展開する。

原因調査に使用できるよう、次の17項目を保持する。

| 区分 | 項目 |
|---|---|
| 識別情報 | `order_id`、`merchant_id`、`merchant_name`、`payment_id`、`settlement_id` |
| エラー情報 | `error_code`、`error_reason` |
| 金額 | `order_amount`、`payment_amount`、`gross_amount`、`actual_fee_amount`、`expected_fee_amount`、`actual_net_amount`、`expected_net_amount` |
| 日時 | `ordered_at`、`paid_at`、`settled_at` |

出力カラムの完全な定義は[`fct_reconciliation_errors`のdbt Docs](https://naohide-sugita.github.io/payment-reconciliation-data-mart/#!/model/model.payment_reconciliation.fct_reconciliation_errors)を参照する。

### 8.3 可視化

Looker Studioでは、照合サマリとエラー明細を確認できることとする。

照合サマリでは、4分類・12種類のエラー種別ごとの件数を0件も含めて表示する。集計には[`looker_studio_error_type_summary.sql`](../payment_reconciliation/analyses/looker_studio_error_type_summary.sql)を使用する。

エラー明細では、異常が検出された注文について、注文・決済・精算の識別情報、エラー理由、照合対象の金額、精算状態、注文・決済・精算日時を表示する。明細の生成には[`looker_studio_reconciliation_error_details.sql`](../payment_reconciliation/analyses/looker_studio_reconciliation_error_details.sql)を使用する。`fct_reconciliation_errors`を基礎とし、`fct_payment_reconciliation`から精算状態を取得して、画面表示用の17項目を出力する。

## 9. 品質要件

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

## 10. 受入基準

| ID | 確認内容 | 合格条件 | 確認方法・確認先 |
|---|---|---|---|
| AC-01 | Raw取込 | 4種類の動作確認用サンプルCSVがBigQueryのRawテーブルとして作成される | `payment_reconciliation/seeds/*.csv`、GitHub Actionsの`Load seed data`、BigQueryのRawテーブル |
| AC-02 | Staging生成・整形 | 4つのStagingビューが作成され、文字列、ステータス、数値、日時および空文字が5章の要件に従って標準化される | `payment_reconciliation/models/staging/stg_*.sql`、各Stagingモデルのdbt Docs、BigQueryのStagingビュー |
| AC-03 | 注文単位の出力 | `fct_payment_reconciliation`が1注文1行で出力される | `payment_reconciliation/models/marts/schema.yml`の`not_null`・`unique`テスト、BigQueryの`fct_payment_reconciliation` |
| AC-04 | 異常フラグ | 4分類・12種類の異常フラグが7章の条件に従って判定される | `payment_reconciliation/models/marts/fct_payment_reconciliation.sql`、`payment_reconciliation/tests/assert_expected_reconciliation_results.sql`、dbt test実行結果 |
| AC-05 | 集約判定 | `error_count`が12種類の異常フラグの合計と一致する | `payment_reconciliation/tests/assert_error_count_matches_flags.sql`、dbt test実行結果 |
| AC-06 | 総合状態 | `error_count = 0`なら`MATCHED`、1以上なら`ERROR`となる | `payment_reconciliation/tests/assert_reconciliation_status_matches_error_count.sql`、dbt test実行結果 |
| AC-07 | 異常パターン | 12種類すべての異常について、対応するサンプルデータと期待結果が定義されている | `payment_reconciliation/seeds/*.csv`、`payment_reconciliation/tests/assert_expected_reconciliation_results.sql`、dbt test実行結果 |
| AC-08 | 期待結果 | 注文単位の照合結果が定義済みの期待結果と一致する | `payment_reconciliation/tests/assert_expected_reconciliation_results.sql`、dbt test実行結果 |
| AC-09 | エラー明細 | 異常フラグが立った注文だけが、エラー種別ごとの明細として出力される | `payment_reconciliation/models/marts/fct_reconciliation_errors.sql`、`payment_reconciliation/models/marts/schema.yml`、BigQueryの`fct_reconciliation_errors` |
| AC-10 | エラーコード | エラー明細に定義された12種類以外の`error_code`が含まれない | `payment_reconciliation/models/marts/schema.yml`の`accepted_values`テスト、dbt test実行結果 |
| AC-11 | 可視化 | Looker Studioで4分類・12種類のエラー件数を0件を含めて確認でき、異常注文の原因調査に必要な17項目をエラー明細で確認できる | Looker Studio、`payment_reconciliation/analyses/looker_studio_error_type_summary.sql`、`payment_reconciliation/analyses/looker_studio_reconciliation_error_details.sql` |
| AC-12 | 自動テスト | dbtの汎用テストと独自SQLテストがすべて合格する | GitHub Actionsの`Run 37 tests`実行ログ、`payment_reconciliation/models/**/schema.yml`、`payment_reconciliation/tests/*.sql` |
| AC-13 | CI | GitHub Actionsでdbt処理とdbt Docs生成が正常終了する | `.github/workflows/dbt-ci.yml`、GitHub Actionsの`dbt CI`実行履歴 |
| AC-14 | 再実行 | 同じ入力データから全件再構築した場合も照合結果が変化しない | `dbt seed --full-refresh`、`dbt run --full-refresh`、`dbt test`の再実行結果 |
| AC-15 | 公開 | dbt DocsをGitHub Pagesで閲覧できる | [公開dbt Docs](https://naohide-sugita.github.io/payment-reconciliation-data-mart/)、GitHub Actionsの`deploy-dbt-docs`実行履歴 |
| AC-16 | 公開安全性 | 認証情報、秘密鍵、個人情報、実在取引データがリポジトリおよび公開物に含まれない | `.gitignore`、`.github/workflows/dbt-ci.yml`、公開リポジトリ、公開dbt Docsのレビュー |
