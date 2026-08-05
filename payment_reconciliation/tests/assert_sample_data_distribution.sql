with expected as (

    select * from unnest([
        struct('total_orders' as metric, 200 as expected_value),
        struct('matched_orders', 173),
        struct('error_orders', 27),
        struct('is_payment_missing', 6),
        struct('is_merchant_missing', 1),
        struct('is_fee_rate_missing', 1),
        struct('is_order_payment_amount_mismatch', 4),
        struct('is_settlement_missing', 5),
        struct('is_settlement_not_completed', 3),
        struct('is_merchant_mismatch', 1),
        struct('is_gross_amount_mismatch', 1),
        struct('is_fee_amount_mismatch', 2),
        struct('is_net_amount_mismatch', 1),
        struct('is_payment_datetime_invalid', 1),
        struct('is_settlement_datetime_invalid', 1),
        struct('error_detail_rows', 27)
    ])

),

reconciliation as (

    select *
    from {{ ref('fct_payment_reconciliation') }}

),

actual as (

    select 'total_orders' as metric, count(*) as actual_value
    from reconciliation

    union all

    select 'matched_orders', countif(reconciliation_status = 'MATCHED')
    from reconciliation

    union all

    select 'error_orders', countif(reconciliation_status = 'ERROR')
    from reconciliation

    union all

    select 'is_payment_missing', countif(is_payment_missing)
    from reconciliation

    union all

    select 'is_merchant_missing', countif(is_merchant_missing)
    from reconciliation

    union all

    select 'is_fee_rate_missing', countif(is_fee_rate_missing)
    from reconciliation

    union all

    select 'is_order_payment_amount_mismatch',
        countif(is_order_payment_amount_mismatch)
    from reconciliation

    union all

    select 'is_settlement_missing', countif(is_settlement_missing)
    from reconciliation

    union all

    select 'is_settlement_not_completed',
        countif(is_settlement_not_completed)
    from reconciliation

    union all

    select 'is_merchant_mismatch', countif(is_merchant_mismatch)
    from reconciliation

    union all

    select 'is_gross_amount_mismatch', countif(is_gross_amount_mismatch)
    from reconciliation

    union all

    select 'is_fee_amount_mismatch', countif(is_fee_amount_mismatch)
    from reconciliation

    union all

    select 'is_net_amount_mismatch', countif(is_net_amount_mismatch)
    from reconciliation

    union all

    select 'is_payment_datetime_invalid',
        countif(is_payment_datetime_invalid)
    from reconciliation

    union all

    select 'is_settlement_datetime_invalid',
        countif(is_settlement_datetime_invalid)
    from reconciliation

    union all

    select 'error_detail_rows', count(*)
    from {{ ref('fct_reconciliation_errors') }}

)

select
    expected.metric,
    expected.expected_value,
    actual.actual_value
from expected
left join actual
    using (metric)
where actual.actual_value is distinct from expected.expected_value
