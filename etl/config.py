"""
Shared configuration for the data generators.

Every generator module imports from here so there's exactly one place to
change dataset size, date ranges, or seeding — instead of duplicating
constants across files and having them drift out of sync.
"""

import os
import random
from datetime import date, timedelta

from faker import Faker

# --------------------------------------------------------------------------
# Sizing knobs
# --------------------------------------------------------------------------
SEED = 42

NUM_STORES = 15
NUM_CUSTOMERS = 5_000
NUM_PRODUCTS = 500
NUM_EMPLOYEES_PER_STORE = (8, 15)   # (min, max) staff per store
TARGET_ORDERS = 100_000

# --------------------------------------------------------------------------
# Date ranges
# --------------------------------------------------------------------------
# Order history window. No order can fall before the later of
# (store.opened_date, ORDER_START) — enforced in generators/orders.py.
ORDER_END = date.today()
ORDER_START = ORDER_END - timedelta(days=365 * 3)

# Stores can open anywhere in the 5 years before ORDER_END, but always with
# at least ~60 days of runway before ORDER_END so every store has some
# order history to generate against.
STORE_OPEN_EARLIEST = ORDER_END - timedelta(days=365 * 5)
STORE_OPEN_LATEST = ORDER_END - timedelta(days=60)

# --------------------------------------------------------------------------
# Customer segments — how many orders a customer places is driven by which
# segment they're randomly assigned to. Shared between customers.py (which
# assigns the segment) and orders.py (which uses it to decide order counts).
# --------------------------------------------------------------------------
CUSTOMER_SEGMENTS = {
    "one_time": {"weight": 0.50, "order_range": (1, 1)},
    "occasional": {"weight": 0.35, "order_range": (10, 30)},
    "loyal": {"weight": 0.15, "order_range": (40, 150)},
}
# Expected total orders ≈ NUM_CUSTOMERS * (0.5*1 + 0.35*20 + 0.15*95) ≈ 109k
# for the defaults above — comfortably past TARGET_ORDERS, so the cap in
# generators/orders.py is what actually determines the final row count,
# not a shortfall from too few eligible orders.

CITIES = [
    "Austin", "Denver", "Seattle", "Chicago", "Atlanta", "Portland",
    "Nashville", "Phoenix", "Boston", "Minneapolis", "Charlotte",
    "San Diego", "Kansas City", "Columbus", "Raleigh",
]

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "sample_data")

# --------------------------------------------------------------------------
# Seeding — do this once, at import time, so every generator module shares
# the same reproducible random state regardless of import order.
# --------------------------------------------------------------------------
random.seed(SEED)
Faker.seed(SEED)
fake = Faker()
Faker.seed(SEED)


def random_date(start: date, end: date) -> date:
    """Uniform random date in [start, end], inclusive."""
    if start >= end:
        return start
    delta_days = (end - start).days
    return start + timedelta(days=random.randint(0, delta_days))


def ensure_output_dir():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
