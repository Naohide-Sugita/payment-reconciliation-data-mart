# 要件・受入基準

## 1. 目的

注文、決済、精算が別々に管理される決済業務を想定し、注文単位でデータを照合して、不一致の有無と理由を確認できるデータマートを構築する。

決済運用で発生し得る不一致を業務ルールとして定義し、BigQuery、dbt、SQL、dbt testによって再現・検証できることを目的とする。

## 2. 想定利用者と利用場面

決済・精算の運用担当者による、以下の利用を想定する。

- 注文単位の照合結果を確認する
- 正常取引と異常取引を識別する
- 異常の種類と対象取引を確認する
- エラー種別ごとの発生状況を可視化する
- SQL変更後も判定結果が維持されることを自動テストで確認する

## 3. 対象範囲

### 3.1 対象

- 合成CSVを`dbt seed`でBigQueryへ投入する
- stagingモデルで項目名とデータ型を整える
- 注文を母集団として、決済、加盟店、精算データを結合する
- 注文単位で12種類の異常を判定する
- 注文単位の照合結果を出力する
- 異常フラグをエラー種別ごとの明細へ変換する
- Looker Studioでエラー種別ごとの件数を可視化する
- dbtの汎用テストと独自SQLテストで品質を検証する
- GitHub Actionsでdbtの一連処理を自動検証する
- 同じ入力データから照合結果を再構築できるようにする

### 3.2 対象外

- GCSやAPIなどからの継続的なデータ取込
- 日次スケジュール実行
- 増分更新、遅延到着、実データの再投入制御
- 取込履歴、バッチ監視、障害通知
- 本番規模の性能、可用性、災害対策
- 実在企業、顧客、取引のデータ利用

本書における再実行は、合成CSVを用いた全件再構築を指す。増分更新や本番取込における冪等性は対象としない。

## 4. 入力データ要件

| データ | 粒度 | 主キー | 主な項目 | 用途 |
|---|---|---|---|---|
| merchants | 1加盟店 | `merchant_id` | `merchant_name`, `fee_rate` | 加盟店名と手数料率の参照 |
| orders | 1注文 | `order_id` | `merchant_id`, `order_amount`, `ordered_at` | 照合の母集団 |
| payments | 1決済 | `payment_id` | `order_id`, `payment_amount`, `payment_status`, `settlement_batch_id`, `paid_at` | 注文に対応する決済 |
| settlements | 1精算 | `settlement_id` | `settlement_batch_id`, `merchant_id`, `gross_amount`, `fee_amount`, `net_amount`, `settlement_status`, `settled_at` | 決済に対応する精算 |

入力データは、以下の条件を満たすものとする。

- ヘッダー付きUTF-8 CSVであること
- 金額は日本円の整数として扱うこと
- 手数料率は小数として扱うこと
- 実在する企業、顧客、取引の情報を含まないこと
- 正常取引および12種類すべての異常を再現できること
- 各テストケースの期待結果を定義できること

## 5. 機能要件

| ID | 要件 |
|---|---|
| FR-01 | 4種類の合成CSVをBigQueryへ投入できること |
| FR-02 | rawデータを4つのstagingビューへ整形できること |
| FR-03 | 注文を母集団とし、成功した決済を照合対象として結合できること |
| FR-04 | 決済と精算を`settlement_batch_id`で関連付けられること |
| FR-05 | 注文単位で12種類の異常フラグを算出できること |
| FR-06 | 異常フラグの合計を`error_count`として保持できること |
| FR-07 | `error_count`に基づいて`MATCHED`または`ERROR`と判定できること |
| FR-08 | 異常がある注文を、注文とエラー種別の組み合わせによる明細へ変換できること |
| FR-09 | Looker Studioで12種類のエラー件数を確認できること |
| FR-10 | dbt testにより、入力データ、モデル、照合結果の品質を検証できること |
| FR-11 | GitHub Actionsでdbtの一連処理を自動実行できること |

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

1つの注文に複数の異常がある場合は、各フラグを独立して保持する。

業務上の異常が意図どおり検出されたこと自体は、dbtの実行失敗としない。

## 7. 出力データ要件

### 7.1 注文単位の照合結果

`fct_payment_reconciliation`は1注文1行とし、以下を保持する。

- 注文、決済、精算、加盟店の識別情報
- 注文金額、決済金額、精算総額、手数料、入金額
- 注文日時、決済日時、精算日時
- 計算上の手数料と入金額
- 12種類の異常フラグ
- `error_count`
- `reconciliation_status`

### 7.2 エラー明細

`fct_reconciliation_errors`は1注文・1エラー種別につき1行とし、以下を保持する。

- `order_id`
- `error_code`
- `error_reason`

複数の異常がある注文は、異常の種類ごとに複数行へ展開する。

正常な注文はエラー明細へ出力しない。

### 7.3 可視化

Looker Studioでは、以下を確認できることとする。

- 12種類のエラー種別
- エラー種別ごとの発生件数
- 発生件数が0件のエラー種別

可視化用の集計は、`fct_reconciliation_errors`を参照するBigQueryカスタムクエリで行う。

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
- 合成データの期待結果と実際の照合結果が一致すること

## 9. 受入基準

| ID | 確認内容 | 合格条件 | 証跡 |
|---|---|---|---|
| AC-01 | raw取込 | 4種類の合成CSVがBigQueryへ作成される | dbt実行結果 |
| AC-02 | staging生成 | 4つのstagingビューが作成され、各seedを参照できる | dbt実行結果、BigQuery |
| AC-03 | 注文単位の出力 | `fct_payment_reconciliation`が1注文1行で出力される | dbt test、BigQuery |
| AC-04 | 異常フラグ | 12種類の異常フラグが定義された条件に従って判定される | モデルSQL、dbt test |
| AC-05 | 集約判定 | `error_count`が12種類の異常フラグの合計と一致する | 独自SQLテスト |
| AC-06 | 総合状態 | `error_count = 0`なら`MATCHED`、1以上なら`ERROR`となる | 独自SQLテスト |
| AC-07 | 異常パターン | 12種類すべての異常について、対応する合成データと期待結果が定義されている | seed、期待結果、独自SQLテスト |
| AC-08 | 期待結果 | 注文単位の照合結果が定義済みの期待結果と一致する | 独自SQLテスト |
| AC-09 | エラー明細 | 異常フラグが立った注文だけが、エラー種別ごとの明細として出力される | dbt test、BigQuery |
| AC-10 | エラーコード | エラー明細に定義された12種類以外の`error_code`が含まれない | dbt test |
| AC-11 | 可視化 | Looker Studioで12種類のエラー件数を0件を含めて確認できる | Looker Studio |
| AC-12 | 自動テスト | dbtの汎用テストと独自SQLテストがすべて合格する | dbt実行結果 |
| AC-13 | CI | GitHub Actionsでdbtの一連処理が正常終了する | GitHub Actions |
| AC-14 | 再実行 | 同じ入力データから再構築した場合も照合結果が変化しない | 再実行前後の比較 |
| AC-15 | 公開安全性 | 認証情報、秘密鍵、個人情報、実在取引データが公開リポジトリに含まれない | 公開前レビュー |