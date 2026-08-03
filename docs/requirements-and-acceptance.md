# 要件・受入基準

- 文書版: v0.3
- 更新日: 2026-08-03
- 対象: MVP v0.1.0
- 対象モデル: `fct_payment_reconciliation`

## 1. 目的

注文、決済、精算が別データとして管理される決済業務を想定し、注文単位でデータを照合して、不一致の有無と理由を確認できるデータマートを構築する。

この成果物では、決済運用で発生し得る不一致を業務ルールとして定義し、BigQuery、dbt、SQL、dbt testへ落とし込めることを示す。

## 2. 想定利用者と利用場面

利用者は決済・精算の運用担当者を想定する。

- 照合対象の注文を確認する
- `MATCHED`と`ERROR`を識別する
- `ERROR`となった注文の異常フラグを確認する
- SQL変更後も同じ判定結果が得られることをテストする

## 3. 対象範囲

### 3.1 対象

- 固定の疑似CSV 4種類を`dbt seed`でBigQueryへ投入する
- stagingモデルで項目名と型を整える
- 注文を母集団として、成功した決済、加盟店マスタ、精算を結合する
- 注文単位で12種類の異常を判定する
- 異常件数と総合照合結果を出力する
- dbtの汎用テストと独自SQLテストで品質を検証する
- `dbt build --full-refresh`で一連処理を再現する

### 3.2 対象外

- GCS、APIなどからの継続的なデータ取込
- 日次スケジュール実行
- 増分更新、遅延到着、実データの再投入制御
- 取込履歴、バッチ監視、障害通知
- 本番規模の性能、可用性、災害対策
- 実在企業・顧客のデータ利用

> 本書の「再実行」は固定seedを用いた全件再構築を指す。増分更新や本番取込の冪等性を意味しない。

## 4. 入力データ要件

| データ | 粒度 | 主キー | 主な項目 | 用途 |
|---|---|---|---|---|
| merchants | 1加盟店 | `merchant_id` | `merchant_name`, `fee_rate` | 加盟店名と手数料率の参照 |
| orders | 1注文 | `order_id` | `merchant_id`, `order_amount`, `ordered_at` | 照合の母集団 |
| payments | 1決済 | `payment_id` | `order_id`, `payment_amount`, `payment_status`, `settlement_batch_id`, `paid_at` | 注文に対応する決済 |
| settlements | 1精算 | `settlement_id` | `settlement_batch_id`, `merchant_id`, `gross_amount`, `fee_amount`, `net_amount`, `settlement_status`, `settled_at` | 決済に対応する精算 |

入力はヘッダー付きUTF-8 CSVとし、金額は日本円の整数、手数料率は小数で扱う。

## 5. 機能要件

| ID | 要件 |
|---|---|
| FR-01 | 4種類の固定CSVをBigQueryのrawデータとして投入できること |
| FR-02 | rawデータを4つのstagingビューへ整形できること |
| FR-03 | 注文を母集団とし、`payment_status = 'SUCCESS'`の決済だけを照合対象として結合できること |
| FR-04 | 決済と精算を`settlement_batch_id`で関連付けられること |
| FR-05 | 注文単位で12種類の異常フラグを算出できること |
| FR-06 | 12フラグの合計を`error_count`として保持し、0件なら`MATCHED`、1件以上なら`ERROR`と判定できること |
| FR-07 | 汎用テストと独自SQLテストにより、キー、必須値、許容値、参照整合性、照合結果の整合性を検証できること |

## 6. 照合・異常判定要件

| ID | 出力フラグ | 異常条件 |
|---|---|---|
| REC-01 | `is_payment_missing` | 成功した決済が存在しない |
| REC-02 | `is_merchant_missing` | 注文の`merchant_id`に対応する加盟店マスタが存在しない |
| REC-03 | `is_fee_rate_missing` | 加盟店マスタは存在するが`fee_rate`が設定されていない |
| REC-04 | `is_order_payment_amount_mismatch` | 決済は存在するが、注文金額と決済金額が一致しない |
| REC-05 | `is_settlement_missing` | 決済は存在するが、対応する精算が存在しない |
| REC-06 | `is_settlement_not_completed` | 精算は存在するが、`settlement_status`が`COMPLETED`ではない |
| REC-07 | `is_merchant_mismatch` | 注文の加盟店と精算の加盟店が一致しない |
| REC-08 | `is_gross_amount_mismatch` | 決済金額と精算総額が一致しない |
| REC-09 | `is_fee_amount_mismatch` | 実際の手数料と`round(payment_amount * fee_rate)`が一致しない |
| REC-10 | `is_net_amount_mismatch` | 実際の入金額と`payment_amount - expected_fee_amount`が一致しない |
| REC-11 | `is_payment_datetime_invalid` | 注文日時または決済日時がない、または決済日時が注文日時より前 |
| REC-12 | `is_settlement_datetime_invalid` | 決済日時または精算日時がない、または精算日時が決済日時より前 |

1つの注文に複数の異常がある場合は、各フラグを独立して保持する。業務上の異常が意図どおり検知されたこと自体はdbt実行失敗としない。

## 7. 出力データ要件

`fct_payment_reconciliation`は1注文1行とし、次を保持する。

- 注文、決済、精算、加盟店の識別情報
- 注文金額、決済金額、精算総額、手数料、入金額
- 注文日時、決済日時、精算日時
- 計算上の手数料と入金額
- 12種類の異常フラグ
- `error_count`
- `reconciliation_status`

## 8. 受入基準

| ID | 確認内容 | 合格条件 | 証跡 |
|---|---|---|---|
| AC-01 | raw取込 | `dbt seed --full-refresh`が成功し、4つのseedがBigQueryへ作成される | dbt実行結果 |
| AC-02 | staging生成 | 4つのstagingビューが作成され、各seedを参照できる | dbt実行結果、BigQuery |
| AC-03 | 照合結果生成 | `fct_payment_reconciliation`が作成され、サンプル8注文が1注文1行で出力される | BigQueryの件数・主キー確認 |
| AC-04 | 異常フラグ | 12フラグがNULLにならず、SQLで定義した各条件に従って判定される | dbt汎用テスト、モデルSQL |
| AC-05 | 集約判定 | `error_count`が12フラグの合計と一致する | 独自SQLテスト |
| AC-06 | 総合状態 | `error_count = 0`なら`MATCHED`、1以上なら`ERROR`となる | 独自SQLテスト |
| AC-07 | 固定ケース | O001～O008の`error_count`と`reconciliation_status`が定義済み期待値と一致する | 独自SQLテスト |
| AC-08 | 品質テスト | 汎用34件、独自SQL 3件の計37件がすべて合格する | `dbt test`結果 |
| AC-09 | 一連実行 | `dbt build --full-refresh`でseed、model、testの46件がすべて成功する | dbt実行結果 |
| AC-10 | 再実行 | 同じ固定CSVで全件再構築しても、行数、`error_count`、`reconciliation_status`が変化しない | 再実行前後の比較 |
| AC-11 | 公開安全性 | 実在データ、認証情報、秘密鍵、個人情報が公開リポジトリに含まれない | 公開前レビュー |

## 9. 完了判定

P-02は次を満たした時点で完了とする。

- 本書が現在のSQL、seed、YAML、READMEと矛盾しない
- 旧構想にあった入金、GCS、増分更新、遅延到着、AirflowをMVP要件として扱っていない
- 12種類の異常条件が実装上のフラグ名と対応している
- 正常、異常、全件再構築による再実行の受入基準が定義されている
