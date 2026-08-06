"""
Generates the `customers` table.

Two things this needs to set up for later stages, neither of which is a
real database column:

  1. `signup_date` spread uniformly across the *entire* order window
     (not clustered) — this is what makes cohort/retention analysis
     possible later; without continuous signups every customer would be
     in the same cohort.

  2. A hidden "segment" per customer (one_time / occasional / loyal),
     drawn from config.CUSTOMER_SEGMENTS. It's returned as a separate
     dict rather than a DataFrame column because it's not part of the
     `customers` table — it only exists to tell generators/orders.py how
     many orders that customer should place.
"""

import pandas as pd

from config import CUSTOMER_SEGMENTS, CITIES, NUM_CUSTOMERS, ORDER_START, ORDER_END
from config import fake, random, random_date


def generate_customers():
    """
    Returns:
        (customers_df, segment_by_customer)
        segment_by_customer maps customer_id -> "one_time"|"occasional"|"loyal"
    """
    segments = list(CUSTOMER_SEGMENTS.keys())
    weights = [CUSTOMER_SEGMENTS[s]["weight"] for s in segments]

    rows = []
    segment_by_customer = {}

    for customer_id in range(1, NUM_CUSTOMERS + 1):
        segment = random.choices(segments, weights=weights, k=1)[0]
        segment_by_customer[customer_id] = segment

        signup = random_date(ORDER_START, ORDER_END)

        rows.append({
            "customer_id": customer_id,
            "first_name": fake.first_name(),
            "last_name": fake.last_name(),
            "email": fake.unique.email(),
            "phone": fake.numerify("###-###-####"),
            "address": fake.street_address(),
            "city": random.choice(CITIES),
            "state": fake.state_abbr(),
            "signup_date": signup,
            "age": random.randint(18, 80),
            "sex": random.choice(["M", "F"]),
        })

    return pd.DataFrame(rows), segment_by_customer
