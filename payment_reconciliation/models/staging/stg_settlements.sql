select
    trim(settlement_id) as settlement_id,
    trim(settlement_batch_id) as settlement_batch_id,
    trim(merchant_id) as merchant_id,
    safe_cast(gross_amount as int64) as gross_amount,
    safe_cast(fee_amount as int64) as fee_amount,
    safe_cast(net_amount as int64) as net_amount,
    upper(trim(settlement_status)) as settlement_status,
    safe_cast(settled_at as timestamp) as settled_at
from {{ source('raw', 'settlements') }}