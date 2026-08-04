with reconciliation as (

    select *
    from {{ ref('fct_payment_reconciliation') }}

),

unpivoted_errors as (

    select *
    from reconciliation
    unpivot (
        has_error for error_type in (
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
            is_settlement_datetime_invalid
        )
    )

)

select
    order_id,
    merchant_id,
    merchant_name,
    payment_id,
    settlement_id,

    error_type as error_code,

    case error_type
        when 'is_payment_missing'
            then '決済データ欠損'
        when 'is_merchant_missing'
            then '加盟店マスタ欠損'
        when 'is_fee_rate_missing'
            then '手数料率欠損'
        when 'is_order_payment_amount_mismatch'
            then '注文・決済金額不一致'
        when 'is_settlement_missing'
            then '精算データ欠損'
        when 'is_settlement_not_completed'
            then '精算未完了'
        when 'is_merchant_mismatch'
            then '加盟店不一致'
        when 'is_gross_amount_mismatch'
            then '決済・精算総額不一致'
        when 'is_fee_amount_mismatch'
            then '手数料額不一致'
        when 'is_net_amount_mismatch'
            then '入金額不一致'
        when 'is_payment_datetime_invalid'
            then '決済日時不正'
        when 'is_settlement_datetime_invalid'
            then '精算日時不正'
    end as error_reason,

    order_amount,
    payment_amount,
    gross_amount,
    actual_fee_amount,
    expected_fee_amount,
    actual_net_amount,
    expected_net_amount,
    ordered_at,
    paid_at,
    settled_at

from unpivoted_errors
where has_error