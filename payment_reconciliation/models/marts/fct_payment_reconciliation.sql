with orders as (

    select *
    from {{ ref('stg_orders') }}

),

successful_payments as (

    select *
    from {{ ref('stg_payments') }}
    where payment_status = 'SUCCESS'

),

joined_data as (

    select
        orders.order_id,
        orders.merchant_id,
        merchants.merchant_name,
        orders.order_amount,
        orders.ordered_at,

        successful_payments.payment_id,
        successful_payments.payment_amount,
        successful_payments.settlement_batch_id,
        successful_payments.paid_at,

        settlements.settlement_id,
        settlements.gross_amount,
        settlements.fee_amount as actual_fee_amount,
        settlements.net_amount as actual_net_amount,
        settlements.settlement_status,
        settlements.settled_at,

        merchants.fee_rate,
        cast(
            round(successful_payments.payment_amount * merchants.fee_rate)
            as int64
        ) as expected_fee_amount,

        successful_payments.payment_amount
            - cast(
                round(successful_payments.payment_amount * merchants.fee_rate)
                as int64
            ) as expected_net_amount

    from orders

    left join successful_payments
        on orders.order_id = successful_payments.order_id

    left join {{ ref('stg_merchants') }} as merchants
        on orders.merchant_id = merchants.merchant_id

    left join {{ ref('stg_settlements') }} as settlements
        on successful_payments.settlement_batch_id
            = settlements.settlement_batch_id

)

select
    *,
    case
        when payment_id is null
            then 'NO_SUCCESSFUL_PAYMENT'

        when order_amount != payment_amount
            then 'ORDER_PAYMENT_AMOUNT_MISMATCH'

        when settlement_id is null
            then 'MISSING_SETTLEMENT'

        when actual_net_amount != expected_net_amount
            then 'SETTLEMENT_AMOUNT_MISMATCH'

        else 'MATCHED'
    end as reconciliation_status

from joined_data