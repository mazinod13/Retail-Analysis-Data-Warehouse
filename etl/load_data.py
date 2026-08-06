"""
Loads sample_data/*.csv into the OLTP schema over DATABASE_URL.

Uses psycopg2's COPY (via copy_expert), not row-by-row INSERTs — COPY is
the standard fast-path for bulk-loading into Postgres, and at ~500k+ total
rows across all tables, INSERTs would be noticeably slower for no benefit.

Load order matters: tables are loaded in the same dependency order the
schema was created in (schema/00_drop_tables.sql lists the reverse of
this), so every foreign key a row points to already exists by the time
that row is inserted. Loading `orders` before `customers`, for example,
would fail immediately on the customer_id foreign key.

Usage:
    python etl/load_data.py            # loads all tables
    python etl/load_data.py --truncate # wipes existing rows first, then loads

Requires a .env file in the project root:
    DATABASE_URL=postgresql://user:password@host:5432/retail_warehouse_db
"""

import argparse
import io
import os
import sys

import pandas as pd
import psycopg2
from dotenv import load_dotenv

SAMPLE_DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "sample_data")

# (table_name, csv_filename) in FK-safe dependency order. This must match
# the order tables were created in schema/01_create_tables.sql.
LOAD_ORDER = [
    ("categories", "categories.csv"),
    ("stores", "stores.csv"),
    ("customers", "customers.csv"),
    ("products", "products.csv"),
    ("employees", "employees.csv"),
    ("orders", "orders.csv"),
    ("order_items", "order_items.csv"),
    ("inventory", "inventory.csv"),
    ("payments", "payments.csv"),
]

# Reverse of LOAD_ORDER — used for --truncate, so tables are emptied in an
# order that never violates a still-present foreign key.
TRUNCATE_ORDER = [table for table, _ in reversed(LOAD_ORDER)]


def get_connection():
    load_dotenv()
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        sys.exit("DATABASE_URL not found. Add it to a .env file in the project root.")
    return psycopg2.connect(database_url)


def load_table(cur, table_name, csv_filename):
    path = os.path.join(SAMPLE_DATA_DIR, csv_filename)
    if not os.path.exists(path):
        sys.exit(f"Missing {path} — run etl/generate_data.py first.")

    # categories.parent_category_id, orders.employee_id, and
    # inventory.last_restock_date can all be genuinely NULL. pandas writes
    # those as empty strings in the CSV, so tell COPY to treat "" as NULL
    # rather than trying to insert an empty string into an INT/DATE column.
    df = pd.read_csv(path)

    # Any nullable integer FK column (parent_category_id, employee_id,
    # manager_id) gets upcast to float64 by pandas once it contains a NaN
    # — e.g. 1 becomes "1.0". Postgres' integer columns reject that, so
    # convert whole-number float columns to pandas' nullable Int64 dtype,
    # which prints as "1" and "" (not "1.0"/"nan") on export.
    for col in df.columns:
        if df[col].dtype == "float64":
            non_null = df[col].dropna()
            if non_null.empty or (non_null == non_null.astype("int64")).all():
                df[col] = df[col].astype("Int64")

    buffer = io.StringIO()
    df.to_csv(buffer, index=False, header=False, na_rep="")
    buffer.seek(0)

    columns = ", ".join(df.columns)
    cur.copy_expert(
        f"COPY {table_name} ({columns}) FROM STDIN WITH (FORMAT csv, NULL '')",
        buffer,
    )
    return len(df)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--truncate", action="store_true",
        help="Delete existing rows from all tables before loading.",
    )
    args = parser.parse_args()

    conn = get_connection()
    try:
        with conn:
            with conn.cursor() as cur:
                if args.truncate:
                    print("Truncating existing tables...")
                    for table in TRUNCATE_ORDER:
                        cur.execute(f"TRUNCATE TABLE {table} RESTART IDENTITY CASCADE")

                for table_name, csv_filename in LOAD_ORDER:
                    row_count = load_table(cur, table_name, csv_filename)
                    print(f"  loaded {table_name}: {row_count:,} rows")

        print("\nDone. Transaction committed.")
    except Exception:
        conn.rollback()
        print("\nLoad failed — transaction rolled back, nothing was written.")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
