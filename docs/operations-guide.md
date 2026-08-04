# 運用手順

- 文書版：v0.1
- 更新日：2026-08-04
- 対象：MVP v0.1.0
- 関連資料：[要件・受入基準](requirements-and-acceptance.md)／[実装設計](implementation-design.md)

## 1. 目的

固定の疑似CSVから注文・決済・精算の照合結果を再構築し、処理結果と品質テストを確認する手順を定める。

本書の対象はローカルPCからdbt Coreを手動実行するMVP運用である。日次スケジュール実行、増分更新、障害通知、実データの復旧は対象外とする。

## 2. 運用対象

| レイヤー | 対象 | 正常時の結果 |
|---|---|---|
| raw | `merchants`、`orders`、`payments`、`settlements` | seed 4件が成功 |
| staging | `stg_merchants`、`stg_orders`、`stg_payments`、`stg_settlements` | model 4件が成功 |
| marts | `fct_payment_reconciliation` | model 1件が成功し、8注文を出力 |
| test | 汎用テスト、独自SQLテスト | 37件がすべてPASS |

## 3. 前提条件

- リポジトリがローカルPCに取得されている
- Python仮想環境`.venv`が作成済みである
- `dbt-bigquery`が仮想環境に導入済みである
- `profiles.yml`の接続先、認証方式、BigQueryロケーションが設定済みである
- BigQueryに`raw`、`staging`、`marts`の各データセットを作成・更新できる権限がある
- 認証情報や`profiles.yml`を公開リポジトリへcommitしない

## 4. 通常実行

### 4.1 リポジトリと仮想環境の確認

PowerShellでリポジトリ直下へ移動し、仮想環境を有効化する。

```powershell
cd C:\Users\sugi7\projects\payment-reconciliation-data-mart
.\.venv\Scripts\Activate.ps1
```

dbtプロジェクトへ移動し、接続を確認する。

```powershell
cd .\payment_reconciliation
dbt --version
dbt debug
```

`dbt debug`の接続確認が成功してからデータ処理へ進む。

### 4.2 固定CSVから全件再構築

初回実行と全件再構築では、次の順序で個別に実行する。

```powershell
dbt seed --full-refresh
dbt run --full-refresh
dbt test
```

各コマンドの終了結果を確認し、`ERROR`がある場合は次のコマンドへ進まない。

| コマンド | 成功条件 |
|---|---|
| `dbt seed --full-refresh` | `PASS=4`、`ERROR=0` |
| `dbt run --full-refresh` | `PASS=5`、`ERROR=0` |
| `dbt test` | `PASS=37`、`ERROR=0` |

`dbt build --full-refresh`単独では、既存のrawテーブルを参照してstagingがseedより先に実行される場合がある。このため、初回構築と運用上の全件再構築では`seed → run → test`の順序を明示する。

## 5. 結果確認

### 5.1 dbt実行結果

PowerShellの最終行で、実行対象がすべて成功し、`ERROR=0`であることを確認する。警告が出た場合は内容を確認し、モデルやテストの非推奨設定に起因する場合は別途修正する。

### 5.2 BigQuery上の照合結果

BigQuery Studioで、`<project_id>`を実際のGCPプロジェクトIDへ置き換えて実行する。

```sql
select
  reconciliation_status,
  count(*) as order_count
from `<project_id>.marts.fct_payment_reconciliation`
group by reconciliation_status
order by reconciliation_status;
```

合計が8注文であることを確認する。

異常注文の明細は次で確認する。

```sql
select
  order_id,
  merchant_id,
  error_count,
  reconciliation_status,
  is_payment_missing,
  is_merchant_missing,
  is_fee_rate_missing,
  is_order_payment_amount_mismatch,
  is_settlement_missing,
  is_settlement_not_completed,
  is_merchant_mismatch,
  is_gross_amount_mismatch,
  is_fee_amount_mismatch,
  is_net_amount_mismatch,
  is_payment_datetime_invalid,
  is_settlement_datetime_invalid
from `<project_id>.marts.fct_payment_reconciliation`
where reconciliation_status = 'ERROR'
order by order_id;
```

意図的に含めた業務異常が`ERROR`になること自体は処理失敗ではない。異常フラグ、`error_count`、総合状態が固定ケースの期待値と一致することを独自SQLテストで保証する。

## 6. 失敗時の切り分け

最初に失敗した工程で停止し、後続工程のエラーを原因と誤認しない。

| 症状 | 主な確認箇所 | 対応 |
|---|---|---|
| `dbt`が認識されない | 仮想環境が有効か、`dbt --version` | リポジトリ直下で`.venv`を有効化する |
| profileが見つからない | `profiles.yml`の配置とprofile名 | `dbt debug`でprofileの読込結果を確認する |
| 認証・権限エラー | GCP認証、対象プロジェクト、BigQuery権限 | 使用中の認証方式と接続先を確認し、必要最小限の権限を設定する |
| ロケーション不一致 | profileとデータセットのlocation | `asia-northeast1`など、既存データセットと同じlocationへ統一する |
| rawテーブルがない | seed実行結果、`raw`データセット | `dbt seed --full-refresh`を先に実行する |
| seedが失敗する | `seeds/*.csv`のヘッダー、文字コード、値 | 直前のCSV変更を確認し、形式を修正してseedを再実行する |
| modelが失敗する | 最初に失敗したモデル、コンパイル済みSQL | `target/compiled/`のSQLとBigQueryのエラー位置を確認する |
| testが失敗する | 失敗したテスト名、返却された行 | 汎用テストはキー・NULL・許容値、独自テストは期待結果とフラグ計算を確認する |
| 行数が8でない | `orders.csv`、JOINによる重複・欠落 | rawの注文件数、`order_id`の一意性、martのJOIN条件を順に確認する |
| 想定外の請求が懸念される | 実行対象、処理バイト、GCP予算 | 実行を停止し、BigQueryのジョブ履歴と予算アラートを確認する |

dbtの詳細な実行結果は`target/run_results.json`、コンパイル後のSQLは`target/compiled/`で確認できる。

## 7. 再実行

原因を修正した後、失敗した工程だけでなく、固定CSVから一連の整合性を確認する。

```powershell
dbt seed --full-refresh
dbt run --full-refresh
dbt test
```

再実行後は次を満たすことを確認する。

- seed 4件、model 5件、test 37件がすべて成功する
- martが8注文・1注文1行である
- 12異常フラグにNULLがない
- `error_count`が12フラグの合計と一致する
- `error_count = 0`なら`MATCHED`、1以上なら`ERROR`である
- 固定8注文の期待結果が再実行前と変わらない

この再実行は固定seedによる全件再構築であり、増分取込や遅延到着データの再処理を保証するものではない。

## 8. 変更時の確認

| 変更対象 | 必須確認 |
|---|---|
| `seeds/*.csv` | seed、全モデル、37テスト、固定ケースの期待値 |
| staging SQL | 影響する型・NULL・許容値・参照整合性テスト |
| mart SQL | 8注文1行、12フラグ、`error_count`、総合状態 |
| schema YAML | テスト件数、対象列、許容値 |
| 独自SQLテスト | 意図的な誤判定を検出できること |
| `profiles.yml`または認証 | 公開対象外であること、接続先・location・権限 |

変更後は、commitまたはpushの前に本書の全件再構築手順を実行する。P-05以降では同じ回帰確認をGitHub Actionsへ移し、自動実行する。

## 9. 公開前確認

- `git status`で意図しないファイルが追加されていない
- 認証情報、秘密鍵、実在データ、個人情報が含まれていない
- `.venv/`、`target/`、`logs/`、`profiles.yml`をcommitしていない
- README、要件・受入基準、実装設計、本書のコマンドと件数が一致している

## 10. P-04完了条件

- 接続確認、全件再構築、結果確認を手順どおり実施できる
- 最初に失敗した工程から原因を切り分けられる
- 修正後の再実行で固定8注文と37テストを確認できる
- 認証情報を公開せずに運用・復旧の考え方を説明できる
- 本番バッチ運用や増分更新を実装済みとして記載していない
