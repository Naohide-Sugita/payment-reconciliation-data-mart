select
    trim(payment_id) as payment_id,
    trim(order_id) as order_id,
    safe_cast(payment_amount as int64) as payment_amount,
    upper(trim(payment_status)) as payment_status,
    nullif(trim(settlement_batch_id), '') as settlement_batch_id,
    safe_cast(paid_at as timestamp) as paid_at
from {{ source('raw', 'payments') }}