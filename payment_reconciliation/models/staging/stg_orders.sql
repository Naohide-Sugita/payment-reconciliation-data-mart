select
    trim(order_id) as order_id,
    trim(merchant_id) as merchant_id,
    safe_cast(order_amount as int64) as order_amount,
    safe_cast(ordered_at as timestamp) as ordered_at
from {{ source('raw', 'orders') }}