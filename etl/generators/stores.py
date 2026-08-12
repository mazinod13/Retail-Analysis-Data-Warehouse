"""
Generates the `stores` table.

The one thing that matters here for downstream data: `opened_date` has to
leave enough room before ORDER_END for the store to actually have order
history. STORE_OPEN_EARLIEST/LATEST in config.py encode that constraint â€”
every store opens at least 60 days before ORDER_END.
"""

import pandas as pd

from config import CITIES, NUM_STORES, STORE_OPEN_EARLIEST, STORE_OPEN_LATEST
from config import fake, random, random_date


def generate_stores():
    rows = []

    # Prefer distinct cities per store; only repeat a city if we need more
    # stores than we have cities in the list.
    used_cities = random.sample(CITIES, k=min(NUM_STORES, len(CITIES)))
    while len(used_cities) < NUM_STORES:
        used_cities.append(random.choice(CITIES))

    for store_id, city in enumerate(used_cities[:NUM_STORES], start=1):
        opened = random_date(STORE_OPEN_EARLIEST, STORE_OPEN_LATEST)
        rows.append({
            "store_id": store_id,
            "name": f"{city} {fake.street_suffix()} Store",
            "phone": fake.numerify("###-###-####"),
            "city": city,
            "opened_date": opened,
            "manager": fake.name(),
        })

    return pd.DataFrame(rows)
