with expected as (

    select *
    from unnest([
        struct('O001' as order_id, cast(null as string) as expected_error),
        struct('O002' as order_id, 'ORDER_PAYMENT_AMOUNT_MISMATCH' as expected_error),
        struct('O003' as order_id, 'PAYMENT_MISSING' as expected_error),
        struct('O004' as order_id, 'PAYMENT_MISSING' as expected_error),
        struct('O005' as order_id, 'SETTLEMENT_MISSING' as expected_error),
        struct('O006' as order_id, 'NET_AMOUNT_MISMATCH' as expected_error),
        struct('O007' as order_id, cast(null as string) as expected_error),
        struct('O008' as order_id, cast(null as string) as expected_error)
    ])

),

actual as (

    select
        order_id,
        error_count,
        reconciliation_status,
        case
            when is_payment_missing then 'PAYMENT_MISSING'
            when is_order_payment_amount_mismatch then 'ORDER_PAYMENT_AMOUNT_MISMATCH'
            when is_settlement_missing then 'SETTLEMENT_MISSING'
            when is_net_amount_mismatch then 'NET_AMOUNT_MISMATCH'
            else null
        end as actual_error
    from {{ ref('fct_payment_reconciliation') }}

)

select
    expected.order_id,
    expected.expected_error,
    actual.actual_error,
    actual.error_count,
    actual.reconciliation_status
from expected
left join actual
    using (order_id)
where
    actual.order_id is null
    or actual.actual_error is distinct from expected.expected_error
    or actual.error_count != if(expected.expected_error is null, 0, 1)
    or actual.reconciliation_status !=
        if(expected.expected_error is null, 'MATCHED', 'ERROR')
