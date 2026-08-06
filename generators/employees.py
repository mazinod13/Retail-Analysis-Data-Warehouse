"""
Generates the `employees` table.

Builds a simple two-level manager hierarchy per store:
  - one store manager, hired within 30 days of the store opening,
    with manager_id = NULL (has to be nullable — see README)
  - a handful of staff, hired any time after the store opened,
    all reporting to that store's manager

This keeps the self-referencing manager_id FK realistic without needing a
deep org chart — good enough for recursive-CTE practice later, without
generating a hierarchy so deep it's hard to eyeball-check.
"""

from datetime import timedelta

import pandas as pd

from config import NUM_EMPLOYEES_PER_STORE, ORDER_END
from config import fake, random, random_date


def generate_employees(stores_df):
    """
    Returns:
        (employees_df, employees_by_store)
        employees_by_store maps store_id -> list of employee_ids at that
        store, which generators/orders.py uses to pick who handled a
        given in-store order.
    """
    rows = []
    employee_id = 1
    employees_by_store = {}

    for _, store in stores_df.iterrows():
        store_id = store["store_id"]
        opened = store["opened_date"]
        staff_count = random.randint(*NUM_EMPLOYEES_PER_STORE)

        # Store manager: hired at/near opening, no manager of their own.
        manager_id = employee_id
        rows.append({
            "employee_id": manager_id,
            "first_name": fake.first_name(),
            "last_name": fake.last_name(),
            "email": fake.unique.email(),
            "phone": fake.numerify("###-###-####"),
            "hire_date": random_date(opened, min(opened + timedelta(days=30), ORDER_END)),
            "manager_id": None,
            "store_id": store_id,
        })
        employee_id += 1
        store_employee_ids = [manager_id]

        # Everyone else reports to the store manager.
        for _ in range(staff_count - 1):
            rows.append({
                "employee_id": employee_id,
                "first_name": fake.first_name(),
                "last_name": fake.last_name(),
                "email": fake.unique.email(),
                "phone": fake.numerify("###-###-####"),
                "hire_date": random_date(opened, ORDER_END),
                "manager_id": manager_id,
                "store_id": store_id,
            })
            store_employee_ids.append(employee_id)
            employee_id += 1

        employees_by_store[store_id] = store_employee_ids

    return pd.DataFrame(rows), employees_by_store
