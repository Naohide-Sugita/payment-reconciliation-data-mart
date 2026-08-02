import csv
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = PROJECT_DIR / "seeds"


merchants = [
    {
        "merchant_id": "M001",
        "merchant_name": "青葉ストア",
        "fee_rate": 0.03,
    },
    {
        "merchant_id": "M002",
        "merchant_name": "みどり商店",
        "fee_rate": 0.035,
    },
    {
        "merchant_id": "M003",
        "merchant_name": "さくら電器",
        "fee_rate": 0.04,
    },
]


orders = [
    {
        "order_id": "O001",
        "merchant_id": "M001",
        "order_amount": 10000,
        "ordered_at": "2026-07-01 10:00:00",
    },
    {
        "order_id": "O002",
        "merchant_id": "M001",
        "order_amount": 5000,
        "ordered_at": "2026-07-01 11:00:00",
    },
    {
        "order_id": "O003",
        "merchant_id": "M002",
        "order_amount": 8000,
        "ordered_at": "2026-07-02 09:30:00",
    },
    {
        "order_id": "O004",
        "merchant_id": "M002",
        "order_amount": 12000,
        "ordered_at": "2026-07-02 14:00:00",
    },
    {
        "order_id": "O005",
        "merchant_id": "M003",
        "order_amount": 20000,
        "ordered_at": "2026-07-03 10:15:00",
    },
    {
        "order_id": "O006",
        "merchant_id": "M003",
        "order_amount": 15000,
        "ordered_at": "2026-07-03 16:20:00",
    },
    {
        "order_id": "O007",
        "merchant_id": "M001",
        "order_amount": 3000,
        "ordered_at": "2026-07-04 12:00:00",
    },
    {
        "order_id": "O008",
        "merchant_id": "M002",
        "order_amount": 10000,
        "ordered_at": "2026-07-04 15:30:00",
    },
]


payments = [
    {
        "payment_id": "P001",
        "order_id": "O001",
        "payment_amount": 10000,
        "payment_status": "SUCCESS",
        "settlement_batch_id": "B001",
        "paid_at": "2026-07-01 10:01:00",
    },
    {
        # 注文額と決済額が不一致
        "payment_id": "P002",
        "order_id": "O002",
        "payment_amount": 4500,
        "payment_status": "SUCCESS",
        "settlement_batch_id": "B002",
        "paid_at": "2026-07-01 11:01:00",
    },
    {
        # 決済失敗
        "payment_id": "P003",
        "order_id": "O003",
        "payment_amount": 8000,
        "payment_status": "FAILED",
        "settlement_batch_id": "",
        "paid_at": "2026-07-02 09:31:00",
    },
    # O004は決済データ自体が存在しない
    {
        # 成功した決済はあるが入金データが存在しない
        "payment_id": "P005",
        "order_id": "O005",
        "payment_amount": 20000,
        "payment_status": "SUCCESS",
        "settlement_batch_id": "B005",
        "paid_at": "2026-07-03 10:16:00",
    },
    {
        # 入金額が手数料計算結果と不一致
        "payment_id": "P006",
        "order_id": "O006",
        "payment_amount": 15000,
        "payment_status": "SUCCESS",
        "settlement_batch_id": "B006",
        "paid_at": "2026-07-03 16:21:00",
    },
    {
        "payment_id": "P007",
        "order_id": "O007",
        "payment_amount": 3000,
        "payment_status": "SUCCESS",
        "settlement_batch_id": "B007",
        "paid_at": "2026-07-04 12:01:00",
    },
    {
        "payment_id": "P008",
        "order_id": "O008",
        "payment_amount": 10000,
        "payment_status": "SUCCESS",
        "settlement_batch_id": "B008",
        "paid_at": "2026-07-04 15:31:00",
    },
]


settlements = [
    {
        "settlement_id": "S001",
        "settlement_batch_id": "B001",
        "merchant_id": "M001",
        "gross_amount": 10000,
        "fee_amount": 300,
        "net_amount": 9700,
        "settlement_status": "COMPLETED",
        "settled_at": "2026-07-05 09:00:00",
    },
    {
        "settlement_id": "S002",
        "settlement_batch_id": "B002",
        "merchant_id": "M001",
        "gross_amount": 4500,
        "fee_amount": 135,
        "net_amount": 4365,
        "settlement_status": "COMPLETED",
        "settled_at": "2026-07-05 09:05:00",
    },
    # B005は入金データ自体が存在しない
    {
        "settlement_id": "S006",
        "settlement_batch_id": "B006",
        "merchant_id": "M003",
        "gross_amount": 15000,
        "fee_amount": 600,
        "net_amount": 14300,
        "settlement_status": "COMPLETED",
        "settled_at": "2026-07-06 09:00:00",
    },
    {
        "settlement_id": "S007",
        "settlement_batch_id": "B007",
        "merchant_id": "M001",
        "gross_amount": 3000,
        "fee_amount": 90,
        "net_amount": 2910,
        "settlement_status": "COMPLETED",
        "settled_at": "2026-07-06 09:05:00",
    },
    {
        "settlement_id": "S008",
        "settlement_batch_id": "B008",
        "merchant_id": "M002",
        "gross_amount": 10000,
        "fee_amount": 350,
        "net_amount": 9650,
        "settlement_status": "COMPLETED",
        "settled_at": "2026-07-06 09:10:00",
    },
]


def write_csv(filename, rows):
    output_path = OUTPUT_DIR / filename

    with output_path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    print(f"Created: {output_path}")


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    write_csv("merchants.csv", merchants)
    write_csv("orders.csv", orders)
    write_csv("payments.csv", payments)
    write_csv("settlements.csv", settlements)


if __name__ == "__main__":
    main()