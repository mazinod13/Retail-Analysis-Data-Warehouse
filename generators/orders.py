"""
Generates `orders` and `order_items` together.

They're built together, not as two separate passes, for one reason:
`orders.total_amount` has to equal the real sum of that order's line
items. If you generated orders first with a random total and order_items
second, the numbers would never line up. So for every order we build, we
immediately build its line items and sum them into total_amount.

This module also owns the three "make it look real" behaviors:
  - seasonality: a weighted (year, month) calendar biases order_date
    toward November/December.
  - status: recent orders skew toward pending/confirmed; only orders old
    enough to have "resolved" become delivered/cancelled.
  - Pareto demand: line items are sampled using each product's
    popularity_weight (from products.py), so demand concentrates on a
    subset of the catalog without hard-coding which products.
"""

from datetime import date, timedelta

import pandas as pd

from config import ORDER_START, ORDER_END, TARGET_ORDERS, CUSTOMER_SEGMENTS
from config import random, random_date

CHANNELS = ["in-store", "online"]
CHANNEL_WEIGHTS = [0.6, 0.4]


# --------------------------------------------------------------------------
# Seasonality
# --------------------------------------------------------------------------
def build_seasonal_calendar(start: date, end: date):
    """List of (year, month, weight) covering every month in [start, end].
    Nov/Dec get weight 3.0, everything else weight 1.0."""
    months = []
    cursor = date(start.year, start.month, 1)
    while cursor <= end:
        weight = 3.0 if cursor.month in (11, 12) else 1.0
        months.append((cursor.year, cursor.month, weight))
        cursor = date(cursor.year + 1, 1, 1) if cursor.month == 12 \
            else date(cursor.year, cursor.month + 1, 1)
    return months


def seasonal_random_date(start: date, end: date, calendar):
    """Pick a date in [start, end], biased toward Nov/Dec via `calendar`."""
    candidates = [
        (y, m, w) for (y, m, w) in calendar
        if date(y, m, 1) <= end and date(y, m, 28) >= start
    ]
    if not candidates:
        return random_date(start, end)

    weights = [c[2] for c in candidates]
    year, month, _ = random.choices(candidates, weights=weights, k=1)[0]

    month_start = date(year, month, 1)
    next_month = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
    month_end = next_month - timedelta(days=1)

    lo, hi = max(month_start, start), min(month_end, end)
    return random_date(lo, hi) if lo <= hi else random_date(start, end)


# --------------------------------------------------------------------------
# Status
# --------------------------------------------------------------------------
def pick_status(order_date: date):
    """Recent orders haven't had time to resolve; older ones have.

    NOTE: the schema's CHECK constraint (schema/01_create_tables.sql) uses
    'completed', not 'confirmed' — docs/schema.dbml and database.md say
    'confirmed', which doesn't match and would be rejected on load. This
    follows the actual SQL constraint; update the docs to match, or swap
    this back if 'confirmed' was the intended value and the SQL is wrong.
    """
    days_old = (ORDER_END - order_date).days
    if days_old < 3:
        return random.choices(["pending", "completed"], weights=[0.6, 0.4], k=1)[0]
    if days_old < 10:
        return random.choices(
            ["completed", "shipped", "delivered"], weights=[0.2, 0.5, 0.3], k=1
        )[0]
    return random.choices(["delivered", "cancelled"], weights=[0.92, 0.08], k=1)[0]


# --------------------------------------------------------------------------
# Main generator
# --------------------------------------------------------------------------
def generate_orders_and_items(customers_df, segment_by_customer, stores_df,
                               employees_by_store, products_df):
    calendar = build_seasonal_calendar(ORDER_START, ORDER_END)
    store_ids = stores_df["store_id"].tolist()
    opened_by_store = dict(zip(stores_df["store_id"], stores_df["opened_date"]))

    product_ids = products_df["product_id"].tolist()
    product_weights = products_df["popularity_weight"].tolist()
    price_by_product = dict(zip(products_df["product_id"], products_df["unit_price"]))

    signup_by_customer = dict(zip(customers_df["customer_id"], customers_df["signup_date"]))

    order_rows, item_rows = [], []
    order_id, item_id, orders_built = 1, 1, 0

    # Shuffle so we're not always exhausting the cap on the same slice of
    # customers (e.g. all the low-customer-id "loyal" ones first).
    customer_ids = customers_df["customer_id"].tolist()
    random.shuffle(customer_ids)

    for customer_id in customer_ids:
        if orders_built >= TARGET_ORDERS:
            break

        segment = segment_by_customer[customer_id]
        lo, hi = CUSTOMER_SEGMENTS[segment]["order_range"]
        n_orders = random.randint(lo, hi)

        earliest_possible = max(signup_by_customer[customer_id], ORDER_START)
        if earliest_possible > ORDER_END:
            continue  # signed up too late to have any valid order date

        for _ in range(n_orders):
            if orders_built >= TARGET_ORDERS:
                break

            store_id = random.choice(store_ids)
            store_floor = max(earliest_possible, opened_by_store[store_id])
            if store_floor > ORDER_END:
                continue  # this store/customer pairing has no valid window

            order_date = seasonal_random_date(store_floor, ORDER_END, calendar)
            channel = random.choices(CHANNELS, weights=CHANNEL_WEIGHTS, k=1)[0]
            # Online orders have no salesperson — leave employee_id null
            # rather than inventing a fake "web" employee (see README).
            employee_id = None if channel == "online" \
                else random.choice(employees_by_store[store_id])
            status = pick_status(order_date)

            # ---- line items ----
            # Over-sample (n_items * 3) then de-dupe, because random.choices
            # allows repeats and order_items needs distinct products per
            # order (uq_order_product constraint).
            n_items = random.randint(1, 5)
            candidates = random.choices(
                product_ids, weights=product_weights,
                k=min(n_items * 3, len(product_ids)),
            )
            chosen = []
            for p in candidates:
                if p not in chosen:
                    chosen.append(p)
                if len(chosen) == n_items:
                    break

            order_total = 0.0
            for product_id in chosen:
                quantity = random.randint(1, 5)
                unit_price = price_by_product[product_id]
                # ~20% of line items carry a small discount.
                discount = round(unit_price * random.uniform(0.05, 0.2), 2) \
                    if random.random() < 0.2 else 0.0
                discount = min(discount, unit_price - 0.01)  # keep line value positive

                item_rows.append({
                    "order_item_id": item_id,
                    "order_id": order_id,
                    "product_id": product_id,
                    "quantity": quantity,
                    "unit_price": unit_price,
                    "discount": discount,
                })
                order_total += quantity * unit_price - discount
                item_id += 1

            order_rows.append({
                "order_id": order_id,
                "customer_id": customer_id,
                "store_id": store_id,
                "employee_id": employee_id,
                "order_date": order_date,
                "channel": channel,
                "status": status,
                "total_amount": round(order_total, 2),
            })

            order_id += 1
            orders_built += 1

    return pd.DataFrame(order_rows), pd.DataFrame(item_rows)
