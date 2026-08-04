with error_types as (
  select *
  from unnest([
    struct(1 as category_sort_order, 'データ欠損' as error_category, 1 as sort_order,
           'is_payment_missing' as error_code, '決済データ欠損' as error_reason),
    struct(1, 'データ欠損', 2,
           'is_merchant_missing', '加盟店マスタ欠損'),
    struct(1, 'データ欠損', 3,
           'is_fee_rate_missing', '手数料率欠損'),
    struct(1, 'データ欠損', 4,
           'is_settlement_missing', '精算データ欠損'),

    struct(2, '処理状態異常', 5,
           'is_settlement_not_completed', '精算未完了'),

    struct(3, 'データ不一致', 6,
           'is_order_payment_amount_mismatch', '注文・決済金額不一致'),
    struct(3, 'データ不一致', 7,
           'is_merchant_mismatch', '加盟店不一致'),
    struct(3, 'データ不一致', 8,
           'is_gross_amount_mismatch', '決済・精算総額不一致'),
    struct(3, 'データ不一致', 9,
           'is_fee_amount_mismatch', '手数料額不一致'),
    struct(3, 'データ不一致', 10,
           'is_net_amount_mismatch', '入金額不一致'),

    struct(4, '日時不正', 11,
           'is_payment_datetime_invalid', '決済日時不正'),
    struct(4, '日時不正', 12,
           'is_settlement_datetime_invalid', '精算日時不正')
  ])
),

error_counts as (
  select
    error_code,
    count(*) as error_count
  from `payment-recon-mart.marts.fct_reconciliation_errors`
  group by error_code
)

select
  error_types.category_sort_order,
  error_types.error_category,
  error_types.sort_order,
  error_types.error_code,
  error_types.error_reason,
  coalesce(error_counts.error_count, 0) as error_count
from error_types
left join error_counts
  using (error_code)