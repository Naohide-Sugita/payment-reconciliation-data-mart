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
        merchants.merchant_id as merchant_master_id,
        merchants.merchant_name,
        orders.order_amount,
        orders.ordered_at,

        successful_payments.payment_id,
        successful_payments.payment_amount,
        successful_payments.settlement_batch_id,
        successful_payments.paid_at,

        settlements.settlement_id,
        settlements.merchant_id as settlement_merchant_id,
        settlements.gross_amount,
        settlements.fee_amount as actual_fee_amount,
        settlements.net_amount as actual_net_amount,
        settlements.settlement_status,
        settlements.settled_at,

        merchants.fee_rate,

        cast(
            round(
                successful_payments.payment_amount
                * merchants.fee_rate
            )
            as int64
        ) as expected_fee_amount,

        successful_payments.payment_amount
            - cast(
                round(
                    successful_payments.payment_amount
                    * merchants.fee_rate
                )
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

),

error_flags as (

    select
        *,

        payment_id is null
            as is_payment_missing,

        merchant_master_id is null
            as is_merchant_missing,

        merchant_master_id is not null
            and fee_rate is null
            as is_fee_rate_missing,

        payment_id is not null
            and order_amount is distinct from payment_amount
            as is_order_payment_amount_mismatch,

        payment_id is not null
            and settlement_id is null
            as is_settlement_missing,

        settlement_id is not null
            and settlement_status is distinct from 'COMPLETED'
            as is_settlement_not_completed,

        settlement_id is not null
            and merchant_id is distinct from settlement_merchant_id
            as is_merchant_mismatch,

        settlement_id is not null
            and payment_id is not null
            and gross_amount is distinct from payment_amount
            as is_gross_amount_mismatch,

        settlement_id is not null
            and payment_amount is not null
            and fee_rate is not null
            and actual_fee_amount is distinct from expected_fee_amount
            as is_fee_amount_mismatch,

        settlement_id is not null
            and payment_amount is not null
            and fee_rate is not null
            and actual_net_amount is distinct from expected_net_amount
            as is_net_amount_mismatch,

        payment_id is not null
            and (
                ordered_at is null
                or paid_at is null
                or paid_at < ordered_at
            )
            as is_payment_datetime_invalid,

        settlement_id is not null
            and (
                paid_at is null
                or settled_at is null
                or settled_at < paid_at
            )
            as is_settlement_datetime_invalid

    from joined_data

),

error_summary as (

    select
        *,

        if(is_payment_missing, 1, 0)
        + if(is_merchant_missing, 1, 0)
        + if(is_fee_rate_missing, 1, 0)
        + if(is_order_payment_amount_mismatch, 1, 0)
        + if(is_settlement_missing, 1, 0)
        + if(is_settlement_not_completed, 1, 0)
        + if(is_merchant_mismatch, 1, 0)
        + if(is_gross_amount_mismatch, 1, 0)
        + if(is_fee_amount_mismatch, 1, 0)
        + if(is_net_amount_mismatch, 1, 0)
        + if(is_payment_datetime_invalid, 1, 0)
        + if(is_settlement_datetime_invalid, 1, 0)
            as error_count

    from error_flags

)

select
    * except (merchant_master_id),

    case
        when error_count > 0 then 'ERROR'
        else 'MATCHED'
    end as reconciliation_status

from error_summary
