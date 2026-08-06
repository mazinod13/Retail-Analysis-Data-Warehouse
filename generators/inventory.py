"""
Generates the `inventory` table.

Simplest generator in the set: every store carries every product (a full
store x product grid), each with a random stock quantity and — 90% of the
time — a recent restock date within the last 90 days. The other 10% get
NULL, since `last_restock_date` is nullable in the schema (a product that's
never been restocked, e.g. newly listed).
"""

from datetime import timedelta

import pandas as pd

from config import ORDER_END
from config import random, random_date


def generate_inventory(stores_df, products_df):
    rows = []
    inventory_id = 1
    for store_id in stores_df["store_id"]:
        for product_id in products_df["product_id"]:
            has_restock = random.random() < 0.9
            rows.append({
                "inventory_id": inventory_id,
                "store_id": store_id,
                "product_id": product_id,
                "quantity": random.randint(0, 200),
                "last_restock_date": (
                    random_date(ORDER_END - timedelta(days=90), ORDER_END)
                    if has_restock else None
                ),
            })
            inventory_id += 1
    return pd.DataFrame(rows)
