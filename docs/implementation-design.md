# 実装設計

関連資料：[要件・受入基準](requirements-and-acceptance.md)

## 1. 目的

注文・決済・加盟店・精算の合成CSVをBigQueryへ取り込み、注文単位で照合する仕組みを示す。

照合結果からエラー明細を作成し、エラー種別ごとの発生件数を可視化する。

## 2. 全体構成

```mermaid
flowchart LR
    CSV["合成CSV"]
    RAW["raw"]
    STG["staging"]
    REC["照合結果"]
    ERR["エラー明細"]
    BI["Looker Studio"]

    CSV --> RAW
    RAW --> STG
    STG --> REC
    REC --> ERR
    ERR --> BI
```

| 構成要素 | 役割 |
|---|---|
| dbt Core | CSVの投入、データ変換、テスト |
| BigQuery | raw、staging、martsの保持 |
| GitHub Actions | 変更時の自動テスト |
| Looker Studio | エラー件数の可視化 |

## 3. データ処理

| 処理 | 内容 |
|---|---|
| raw投入 | 合成CSVを`dbt seed`でBigQueryへ投入する |
| staging整形 | 文字列、数値、日時、ステータスを扱いやすい形式に整える |
| 照合 | 注文を基準に、決済・加盟店・精算を結合する |
| 異常判定 | 金額、状態、日時、データ欠落などを判定する |
| エラー明細化 | 注文単位の異常フラグを、エラー種別ごとの行へ変換する |
| 可視化 | エラー種別ごとの件数をLooker Studioで表示する |

## 4. データモデル

| レイヤー | モデル | 役割 |
|---|---|---|
| raw | `merchants` | 加盟店データ |
| raw | `orders` | 注文データ |
| raw | `payments` | 決済データ |
| raw | `settlements` | 精算データ |
| staging | `stg_merchants` | 加盟店データの整形 |
| staging | `stg_orders` | 注文データの整形 |
| staging | `stg_payments` | 決済データの整形 |
| staging | `stg_settlements` | 精算データの整形 |
| marts | `fct_payment_reconciliation` | 1注文1行の照合結果 |
| marts | `fct_reconciliation_errors` | 1注文・1エラー種別につき1行のエラー明細 |

処理規模が小さく、独立して再利用する中間処理もないため、intermediate層は設けない。

## 5. 照合方法

注文を基準に、成功した決済、加盟店マスタ、精算データをLEFT JOINする。

LEFT JOINを使うことで、関連データが存在しない注文も照合対象に残し、異常として検出する。

| 結合先 | 結合条件 |
|---|---|
| 決済 | 注文ID |
| 加盟店マスタ | 加盟店ID |
| 精算 | 精算バッチID |

注文に紐づかない決済や精算の検出は対象外とする。

## 6. 異常判定

以下の12種類を判定する。

| エラーコード | 判定内容 |
|---|---|
| `PAYMENT_MISSING` | 成功した決済がない |
| `MERCHANT_MISSING` | 加盟店マスタがない |
| `FEE_RATE_MISSING` | 手数料率がない |
| `ORDER_PAYMENT_AMOUNT_MISMATCH` | 注文金額と決済金額が一致しない |
| `SETTLEMENT_MISSING` | 精算データがない |
| `SETTLEMENT_NOT_COMPLETED` | 精算が完了していない |
| `MERCHANT_MISMATCH` | 注文と精算の加盟店が一致しない |
| `GROSS_AMOUNT_MISMATCH` | 決済金額と精算総額が一致しない |
| `FEE_AMOUNT_MISMATCH` | 実際の手数料と期待手数料が一致しない |
| `NET_AMOUNT_MISMATCH` | 実際の入金額と期待入金額が一致しない |
| `PAYMENT_DATETIME_INVALID` | 決済日時が不正 |
| `SETTLEMENT_DATETIME_INVALID` | 精算日時が不正 |

1つの注文に複数の異常がある場合は、すべての異常を保持する。

異常がなければ`MATCHED`、1件以上あれば`ERROR`とする。

## 7. エラー明細

`fct_reconciliation_errors`では、照合結果のうち異常がある項目だけを行として出力する。

| 項目 | 内容 |
|---|---|
| `order_id` | 異常が発生した注文 |
| `error_code` | エラーの種類 |
| `error_reason` | エラー内容の説明 |

正常な注文は出力しない。複数の異常がある注文は、エラー種別ごとに複数行を出力する。

## 8. テスト

dbt testで以下を確認する。

- IDにNULLや重複がないこと
- ステータスやエラーコードが定義した値であること
- 注文単位の照合結果が1注文1行であること
- 異常フラグの合計と`error_count`が一致すること
- `error_count`と照合状態が一致すること
- 合成データの期待結果と実際の判定結果が一致すること
- エラー明細と注文単位の異常フラグが対応すること

合成データに意図的な異常が含まれていても、期待した異常として検出できていればテスト成功とする。

## 9. 実行方法

```powershell
cd payment_reconciliation
dbt seed --full-refresh
dbt run --full-refresh
dbt test
```

GitHub Actionsでも同じ順序で実行し、変更によって照合結果が崩れていないことを確認する。

## 10. 対象外

- APIやGCSからの継続的なデータ取込
- 日次スケジュール実行
- 増分更新
- 障害通知や自動復旧
- 注文に紐づかない決済・精算の検出
- 本番規模の性能設計