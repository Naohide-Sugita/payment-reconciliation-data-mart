select
  e.order_id,
  e.payment_id,
  e.settlement_id,
  e.merchant_id,
  e.error_reason,
  e.order_amount,
  e.payment_amount,
  e.gross_amount,
  e.payment_amount as expected_gross_amount,
  e.actual_fee_amount,
  e.expected_fee_amount,
  e.actual_net_amount as net_amount,
  e.expected_net_amount,
  r.settlement_status,
  e.ordered_at,
  e.paid_at,
  e.settled_at
from `payment-recon-mart.marts.fct_reconciliation_errors` as e
left join `payment-recon-mart.marts.fct_payment_reconciliation` as r
  on e.order_id = r.order_id
order by
  e.order_id,
  e.error_code
