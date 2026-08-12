"""
Generates the `payments` table.

Only orders that have actually progressed to a paid status get a payment
row â€” a 'pending' order hasn't been charged yet, and a 'cancelled' order
never went through. Generating a payment for every order regardless of
status would make it impossible to later write a meaningful "orders with
no payment" query.

paid_at is set 0-2 days after order_date with a business-hours-ish time
component, since real payments don't happen at the exact instant of the
order record being created.
"""

from datetime import timedelta

import pandas as pd

from config import random

PAYMENT_METHODS = ["cash", "card", "wallet", "bank_transfer"]
PAYMENT_METHOD_WEIGHTS = [0.15, 0.55, 0.2, 0.1]

# Orders in these statuses have actually been paid for.
# NOTE: matches the schema's CHECK constraint, which uses 'completed' â€”
# see the note in generators/orders.py::pick_status.
PAID_STATUSES = {"completed", "shipped", "delivered"}


def generate_payments(orders_df):
    rows = []
    payment_id = 1
    for order in orders_df.itertuples(index=False):
        if order.status not in PAID_STATUSES:
            continue

        paid_at_date = order.order_date + timedelta(days=random.randint(0, 2))
        paid_at = pd.Timestamp(paid_at_date) + pd.Timedelta(
            hours=random.randint(8, 21), minutes=random.randint(0, 59)
        )

        rows.append({
            "payment_id": payment_id,
            "order_id": order.order_id,
            "method": random.choices(
                PAYMENT_METHODS, weights=PAYMENT_METHOD_WEIGHTS, k=1
            )[0],
            "amount": order.total_amount,
            "paid_at": paid_at,
        })
        payment_id += 1

    return pd.DataFrame(rows)
