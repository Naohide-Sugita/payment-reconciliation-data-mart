with expected as (

    select *
    from unnest([
        struct(
            'O001' as order_id,
            false as expected_is_payment_missing,
            false as expected_is_merchant_missing,
            false as expected_is_fee_rate_missing,
            false as expected_is_order_payment_amount_mismatch,
            false as expected_is_settlement_missing,
            false as expected_is_settlement_not_completed,
            false as expected_is_merchant_mismatch,
            false as expected_is_gross_amount_mismatch,
            false as expected_is_fee_amount_mismatch,
            false as expected_is_net_amount_mismatch,
            false as expected_is_payment_datetime_invalid,
            false as expected_is_settlement_datetime_invalid,
            0 as expected_error_count,
            'MATCHED' as expected_reconciliation_status
        ),
        struct(
            'O002',
            false,
            false,
            false,
            true,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            1,
            'ERROR'
        ),
        struct(
            'O003',
            true,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            1,
            'ERROR'
        ),
        struct(
            'O004',
            true,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            1,
            'ERROR'
        ),
        struct(
            'O005',
            false,
            false,
            false,
            false,
            true,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            1,
            'ERROR'
        ),
        struct(
            'O006',
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            true,
            false,
            false,
            1,
            'ERROR'
        ),
        struct(
            'O007',
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            0,
            'MATCHED'
        ),
        struct(
            'O008',
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            0,
            'MATCHED'
        )
    ])

),

actual as (

    select
        order_id,
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
        is_settlement_datetime_invalid,
        error_count,
        reconciliation_status
    from {{ ref('fct_payment_reconciliation') }}
    where order_id in (select order_id from expected)

)

select
    coalesce(expected.order_id, actual.order_id) as order_id,
    expected.* except (order_id),
    actual.* except (order_id)
from expected
full outer join actual
    using (order_id)
where
    expected.order_id is null
    or actual.order_id is null
    or actual.is_payment_missing
        is distinct from expected.expected_is_payment_missing
    or actual.is_merchant_missing
        is distinct from expected.expected_is_merchant_missing
    or actual.is_fee_rate_missing
        is distinct from expected.expected_is_fee_rate_missing
    or actual.is_order_payment_amount_mismatch
        is distinct from expected.expected_is_order_payment_amount_mismatch
    or actual.is_settlement_missing
        is distinct from expected.expected_is_settlement_missing
    or actual.is_settlement_not_completed
        is distinct from expected.expected_is_settlement_not_completed
    or actual.is_merchant_mismatch
        is distinct from expected.expected_is_merchant_mismatch
    or actual.is_gross_amount_mismatch
        is distinct from expected.expected_is_gross_amount_mismatch
    or actual.is_fee_amount_mismatch
        is distinct from expected.expected_is_fee_amount_mismatch
    or actual.is_net_amount_mismatch
        is distinct from expected.expected_is_net_amount_mismatch
    or actual.is_payment_datetime_invalid
        is distinct from expected.expected_is_payment_datetime_invalid
    or actual.is_settlement_datetime_invalid
        is distinct from expected.expected_is_settlement_datetime_invalid
    or actual.error_count
        is distinct from expected.expected_error_count
    or actual.reconciliation_status
        is distinct from expected.expected_reconciliation_status
