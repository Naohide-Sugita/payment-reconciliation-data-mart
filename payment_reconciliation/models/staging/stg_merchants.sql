select
    trim(merchant_id) as merchant_id,
    trim(merchant_name) as merchant_name,
    safe_cast(fee_rate as numeric) as fee_rate
from {{ source('raw', 'merchants') }}