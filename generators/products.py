"""
Generates the `products` table.

The important trick here is `popularity_weight`: each product gets a
Zipf-like weight (1/rank^1.2 after a random shuffle of ranks). This column
is NOT part of the real schema — generate_data.py drops it before writing
products.csv. It exists purely so generators/orders.py can use it as a
sampling weight when picking which products go into an order.

Sampling with these weights, over many orders, is what produces the
"20% of products drive ~80% of revenue" pattern organically — nobody has
to hard-code which specific products are "popular".
"""

import pandas as pd

from config import NUM_PRODUCTS, SEED
from config import fake, random

BRANDS = [
    "Nordic", "Vantage", "Lumen", "Craftwell", "Everstone", "Pinnacle",
    "Northgate", "BlueOrbit", "Solace", "Ironvale", "Meridian", "Fernwood",
    "Cobalt & Co", "Trailhead", "Highline",
]


def generate_products(leaf_category_ids):
    rows = []
    for product_id in range(1, NUM_PRODUCTS + 1):
        cost = round(random.uniform(3, 400), 2)
        markup = random.uniform(1.3, 2.8)  # retail markup over cost
        unit_price = round(cost * markup, 2)

        rows.append({
            "product_id": product_id,
            "category_id": random.choice(leaf_category_ids),
            "name": f"{fake.word().capitalize()} {fake.word().capitalize()}",
            "brand": random.choice(BRANDS),
            "unit_price": unit_price,
            "cost": cost,
        })

    df = pd.DataFrame(rows)

    # Shuffle product ids into a random rank order, then assign weight by
    # rank so popularity isn't correlated with product_id / price / brand —
    # it's genuinely arbitrary which products end up "popular".
    ranks = df["product_id"].sample(frac=1, random_state=SEED).reset_index(drop=True)
    weight_by_rank = {pid: 1 / (i + 1) ** 1.2 for i, pid in enumerate(ranks)}
    df["popularity_weight"] = df["product_id"].map(weight_by_rank)

    return df
