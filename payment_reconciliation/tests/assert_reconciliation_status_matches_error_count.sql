select *
from {{ ref('fct_payment_reconciliation') }}
where
    (error_count = 0 and reconciliation_status != 'MATCHED')
    or
    (error_count > 0 and reconciliation_status != 'ERROR')
