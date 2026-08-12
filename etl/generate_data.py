"""
Orchestrator: calls each table's generator in FK-safe dependency order and
writes the results to sample_data/*.csv.

Each generator lives in its own file under etl/generators/ — this script just
wires them together in the right order (a table's generator needs its
parent tables' data before it can run: employees needs stores, orders need
customers/stores/employees/products, etc.) and does the actual file I/O.

Run from the repo root:
    python etl/generate_data.py
"""

from config import ensure_output_dir, OUTPUT_DIR
from generators.categories import generate_categories
from generators.stores import generate_stores
from generators.customers import generate_customers
from generators.products import generate_products
from generators.employees import generate_employees
from generators.orders import generate_orders_and_items
from generators.inventory import generate_inventory
from generators.payments import generate_payments

import os


def main():
    ensure_output_dir()

    print("Generating categories...")
    categories_df, leaf_category_ids = generate_categories()

    print("Generating stores...")
    stores_df = generate_stores()

    print("Generating customers...")
    customers_df, segment_by_customer = generate_customers()

    print("Generating products...")
    products_df = generate_products(leaf_category_ids)

    print("Generating employees...")
    employees_df, employees_by_store = generate_employees(stores_df)

    print("Generating orders and order_items...")
    orders_df, order_items_df = generate_orders_and_items(
        customers_df, segment_by_customer, stores_df, employees_by_store, products_df
    )

    print("Generating inventory...")
    inventory_df = generate_inventory(stores_df, products_df)

    print("Generating payments...")
    payments_df = generate_payments(orders_df)

    # popularity_weight is a generator-internal helper column, not a real
    # products column — drop it before writing.
    products_out = products_df.drop(columns=["popularity_weight"])

    outputs = {
        "categories.csv": categories_df,
        "stores.csv": stores_df,
        "customers.csv": customers_df,
        "products.csv": products_out,
        "employees.csv": employees_df,
        "orders.csv": orders_df,
        "order_items.csv": order_items_df,
        "inventory.csv": inventory_df,
        "payments.csv": payments_df,
    }

    for filename, df in outputs.items():
        path = os.path.join(OUTPUT_DIR, filename)
        df.to_csv(path, index=False)
        print(f"  wrote {filename}: {len(df):,} rows")

    print("\nDone.")


if __name__ == "__main__":
    main()
