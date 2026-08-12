"""
Generates the `inventory` table.

Simplest generator in the set: every store carries every product (a full
store x product grid), each with a random stock quantity and â€” 90% of the
time â€” a recent restock date within the last 90 days. The other 10% get
NULL, since `last_restock_date` is nullable in the schema (a product that's
never been restocked, e.g. newly listed).
"""

from datetime import timedelta

import pandas as pd

from config import ORDER_END,STOCK_TIERS
from config import random, random_date


def generate_inventory(stores_df, products_df):
    rows = []
    inventory_id = 1
    tier_names = list(STOCK_TIERS)
    tier_weights = [STOCK_TIERS[t]["weight"] for t in tier_names]
    tier = random.choices(tier_names, weights=tier_weights, k=1)[0]
    for store_id in stores_df["store_id"]:
        for product_id in products_df["product_id"]:
            has_restock = random.random() < 0.9
            rows.append({
                "inventory_id": inventory_id,
                "store_id": store_id,
                "product_id": product_id,
                "quantity": random.randint(*STOCK_TIERS[tier]["quantity_range"]),
                "last_restock_date": (
                    random_date(ORDER_END - timedelta(days=90), ORDER_END)
                    if has_restock else None
                ),
            })
            inventory_id += 1
    return pd.DataFrame(rows)
