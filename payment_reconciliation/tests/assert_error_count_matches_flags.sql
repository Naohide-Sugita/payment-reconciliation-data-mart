select *
from {{ ref('fct_payment_reconciliation') }}
where error_count != (
    cast(is_payment_missing as int64)
    + cast(is_merchant_missing as int64)
    + cast(is_fee_rate_missing as int64)
    + cast(is_order_payment_amount_mismatch as int64)
    + cast(is_settlement_missing as int64)
    + cast(is_settlement_not_completed as int64)
    + cast(is_merchant_mismatch as int64)
    + cast(is_gross_amount_mismatch as int64)
    + cast(is_fee_amount_mismatch as int64)
    + cast(is_net_amount_mismatch as int64)
    + cast(is_payment_datetime_invalid as int64)
    + cast(is_settlement_datetime_invalid as int64)
)
