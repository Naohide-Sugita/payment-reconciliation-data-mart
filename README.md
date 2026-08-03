# payment-reconciliation-data-mart

決済・注文・精算データを照合し、不一致取引を検出するデータマートです。  
BigQueryとdbtを使用し、データの取り込み、整形、照合、品質テストまでを実装しています。

## プロジェクトの目的

決済業務では、注文・決済・精算データが別々に管理されるため、以下のような不一致が発生する可能性があります。

- 注文は存在するが、決済データが存在しない
- 決済は成功しているが、精算データが存在しない
- 注文金額と決済金額が一致しない
- 決済金額と精算金額が一致しない
- 取引ステータスに矛盾がある

本プロジェクトでは、これらのデータを取引単位で統合し、照合結果と不一致理由を確認できるデータマートを構築します。

## データフロー

```text
サンプルCSV
    ↓ dbt seed
BigQuery rawデータセット
    ↓ dbt staging models
BigQuery stagingビュー
    ↓ dbt mart model
決済照合結果（fct_payment_reconciliation）
    ↓ dbt test
データ品質検証
```

## 使用技術

- BigQuery
- dbt Core
- dbt-bigquery
- SQL
- YAML
- Git / GitHub

## ディレクトリ構成

```text
payment-reconciliation-data-mart/
├── README.md
└── payment_reconciliation/
    ├── dbt_project.yml
    ├── models/
    ├── seeds/
    ├── tests/
    └── scripts/
```

## 実行方法

dbtプロジェクトのディレクトリへ移動します。

```powershell
cd payment_reconciliation
```

サンプルCSVをBigQueryへ投入します。

```powershell
dbt seed --full-refresh
```

各モデルを作成します。

```powershell
dbt run --full-refresh
```

データ品質テストを実行します。

```powershell
dbt test
```

## データモデル

| レイヤー | モデル | 種別 | 役割 |
|---|---|---|---|
| raw | merchants | テーブル | 加盟店マスタ |
| raw | orders | テーブル | 注文データ |
| raw | payments | テーブル | 決済データ |
| raw | settlements | テーブル | 精算データ |
| staging | stg_merchants | ビュー | 加盟店データの整形 |
| staging | stg_orders | ビュー | 注文データの整形 |
| staging | stg_payments | ビュー | 決済データの整形 |
| staging | stg_settlements | ビュー | 精算データの整形 |
| marts | fct_payment_reconciliation | ビュー | 注文単位の照合結果 |

## 照合ロジック

最終モデルでは、注文単位で以下の12種類の異常を判定します。

- 決済データが存在しない
- 加盟店マスタが存在しない
- 手数料率が設定されていない
- 注文金額と決済金額が一致しない
- 精算データが存在しない
- 精算が完了していない
- 注文と精算の加盟店が一致しない
- 決済金額と精算総額が一致しない
- 実際の手数料と計算上の手数料が一致しない
- 実際の入金額と計算上の入金額が一致しない
- 決済日時が注文日時より前、または必要な日時がない
- 精算日時が決済日時より前、または必要な日時がない

異常フラグの合計を`error_count`として保持し、1件以上あれば`ERROR`、0件なら`MATCHED`と判定します。

## テスト結果

合計37件のdbtテストを実装し、すべて合格しています。

### 汎用テスト：34件

- 主キーのNULL・重複検査
- 必須項目のNULL検査
- ステータスの許容値検査
- モデル間の参照整合性検査
- 精算バッチIDのNULL・重複検査
- 照合結果と異常フラグのNULL検査

### 独自SQLテスト：3件

- `error_count`が12個の異常フラグの合計と一致すること
- サンプル8注文の照合結果が期待値と一致すること
- `error_count`と`reconciliation_status`が矛盾しないこと

```text
PASS=37
WARN=0
ERROR=0
SKIP=0
TOTAL=37
```
