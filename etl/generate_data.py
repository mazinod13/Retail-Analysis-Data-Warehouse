import os
import random
from datetime import date , timedelta

import pandas as pd
from faker import Faker

SEED = 42
NUM_STORES = 20
NUM_CUSTOMERS = 5_000
NUM_PRODUCTS = 500
NUM_EMPLOYEES_PER_STORE = (8,15)
TARGET_ORDERS =100_000

ORDER_END = date.today()
ORDER_START = ORDER_END - timedelta(days=365 * 3)

STORE_OPEN_EARLIEST = ORDER_END - timedelta(days=365 * 5)
STORE_OPEN_LATEST = ORDER_END - timedelta(days=60)
 
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "sample_data")
 
random.seed(SEED)
Faker.seed(SEED)
fake = Faker()
Faker.seed(SEED)

CITIES = [
  "Kathmandu",
  "Pokhara",
  "Lalitpur",
  "Bharatpur",
  "Biratnagar",
  "Birgunj",
  "Janakpur",
  "Ghorahi",
  "Hetauda",
  "Dhangadhi",
  "Tulsipur",
  "Itahari",
  "Nepalgunj",
  "Butwal",
  "Dharan",
  "Kalaiya",
  "Jeetpur Simara",
  "Bhaktapur",
  "Kirtipur",
  "Siddharthanagar",
  "Damak",
  "Birtamod",
  "Vyas",
  "Ratnanagar",
  "Tansen",
  "Birendranagar"
]


def random_date(start: date, end: date) -> date:
    """Uniform random date in [start, end]."""
    if start >= end:
        return start
    delta_days = (end - start).days
    return start + timedelta(days=random.randint(0, delta_days))


def ensure_output_dir():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
 
CATEGORY_TREE = {
    "Electronics": ["Laptops", "Phones", "Headphones", "Cameras", "Tablets"],
    "Home & Kitchen": ["Cookware", "Small Appliances", "Furniture", "Bedding"],
    "Apparel": ["Men's Clothing", "Women's Clothing", "Shoes", "Accessories"],
    "Sports & Outdoors": ["Fitness Equipment", "Camping Gear", "Cycling"],
    "Toys & Games": ["Board Games", "Action Figures", "Puzzles"],
    "Beauty & Personal Care": ["Skincare", "Haircare", "Fragrance"],
    "Books": ["Fiction", "Non-Fiction", "Children's Books"],
    "Office Supplies": ["Stationery", "Printers & Ink", "Organization"],
}


def generate_categories():
    rows = []
    cat_id = 1
    leaf_ids = []
 
    for parent_name, children in CATEGORY_TREE.items():
        parent_id = cat_id
        rows.append({"category_id": parent_id, "name": parent_name,
                      "parent_category_id": None})
        cat_id += 1
 
        for child_name in children:
            rows.append({"category_id": cat_id, "name": child_name,
                          "parent_category_id": parent_id})
            leaf_ids.append(cat_id)
            cat_id += 1
 
    return pd.DataFrame(rows), leaf_ids

def generate_stores():
    rows = []
    used_cities = random.sample(CITIES, k=min(NUM_STORES, len(CITIES)))
    # If we need more stores than cities, allow repeats after the shuffle.
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
 
 
# Customer segments control how many orders each customer will place.
# Weighted so the base is one-time buyers, with a long tail of loyal repeat
# customers — this is what makes churn/retention analysis meaningful.
CUSTOMER_SEGMENTS = {
    "one_time": {"weight": 0.50, "order_range": (1, 1)},
    "occasional": {"weight": 0.35, "order_range": (10, 30)},
    "loyal": {"weight": 0.15, "order_range": (40, 150)},
}
# Expected orders ≈ 5000 * (0.5*1 + 0.35*20 + 0.15*95) ≈ 109k, comfortably
# past TARGET_ORDERS so the cap in generate_orders_and_items is what
# actually determines the final count (~100k), not a shortfall.
 
 
def generate_customers():
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
 
    # Pareto popularity: rank products, weight by 1/rank^1.2 so the top
    # ~20% of products soak up roughly 80% of demand once used as sampling
    # weights for order_items, without forcing an exact split every time.
    ranks = df["product_id"].sample(frac=1, random_state=SEED).reset_index(drop=True)
    weight_by_rank = {pid: 1 / (i + 1) ** 1.2 for i, pid in enumerate(ranks)}
    df["popularity_weight"] = df["product_id"].map(weight_by_rank)
 
    return df
 
 
def generate_employees(stores_df):
    rows = []
    employee_id = 1
    employees_by_store = {}  # store_id -> list of employee_ids
 
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
 
        # Rest of the staff report to the store manager, hired any time
        # after the store opened.
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
 
 
# --------------------------------------------------------------------------
# Seasonality: build a weighted calendar of (year, month) pairs across the
# order window, with Nov/Dec weighted up so order volume visibly spikes
# for the holidays.
# --------------------------------------------------------------------------
def build_seasonal_calendar(start: date, end: date):
    months = []
    cursor = date(start.year, start.month, 1)
    while cursor <= end:
        weight = 3.0 if cursor.month in (11, 12) else 1.0
        months.append((cursor.year, cursor.month, weight))
        if cursor.month == 12:
            cursor = date(cursor.year + 1, 1, 1)
        else:
            cursor = date(cursor.year, cursor.month + 1, 1)
    return months
 
 
def seasonal_random_date(start: date, end: date, calendar):
    """Pick a date in [start, end] biased toward Nov/Dec via `calendar`."""
    candidates = [(y, m, w) for (y, m, w) in calendar
                  if date(y, m, 1) <= end and
                  date(y, m, 28) >= start]
    if not candidates:
        return random_date(start, end)
 
    years = [c[0] for c in candidates]
    monthsn = [c[1] for c in candidates]
    weights = [c[2] for c in candidates]
    year, month, _ = random.choices(candidates, weights=weights, k=1)[0]
 
    month_start = date(year, month, 1)
    next_month = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
    month_end = next_month - timedelta(days=1)
 
    lo = max(month_start, start)
    hi = min(month_end, end)
    if lo > hi:
        return random_date(start, end)
    return random_date(lo, hi)
 
 
CHANNELS = ["in-store", "online"]
CHANNEL_WEIGHTS = [0.6, 0.4]
 
STATUS_CHOICES = ["pending", "confirmed", "shipped", "delivered", "cancelled"]
 
 
def pick_status(order_date: date):
    """Recent orders skew toward in-progress statuses; older orders have
    had time to resolve into delivered/cancelled."""
    days_old = (ORDER_END - order_date).days
    if days_old < 3:
        return random.choices(
            ["pending", "confirmed"], weights=[0.6, 0.4], k=1)[0]
    if days_old < 10:
        return random.choices(
            ["confirmed", "shipped", "delivered"], weights=[0.2, 0.5, 0.3], k=1)[0]
    # Fully resolved by now.
    return random.choices(
        ["delivered", "cancelled"], weights=[0.92, 0.08], k=1)[0]
 
 
def generate_orders_and_items(customers_df, segment_by_customer, stores_df,
                               employees_by_store, products_df):
    calendar = build_seasonal_calendar(ORDER_START, ORDER_END)
    store_ids = stores_df["store_id"].tolist()
    opened_by_store = dict(zip(stores_df["store_id"], stores_df["opened_date"]))
 
    product_ids = products_df["product_id"].tolist()
    product_weights = products_df["popularity_weight"].tolist()
    price_by_product = dict(zip(products_df["product_id"], products_df["unit_price"]))
 
    signup_by_customer = dict(zip(customers_df["customer_id"], customers_df["signup_date"]))
 
    order_rows = []
    item_rows = []
    order_id = 1
    item_id = 1
    orders_built = 0
 
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
            continue
 
        for _ in range(n_orders):
            if orders_built >= TARGET_ORDERS:
                break
 
            store_id = random.choice(store_ids)
            store_floor = max(earliest_possible, opened_by_store[store_id])
            if store_floor > ORDER_END:
                continue  # this store/customer pairing can't have a valid date
 
            order_date = seasonal_random_date(store_floor, ORDER_END, calendar)
            channel = random.choices(CHANNELS, weights=CHANNEL_WEIGHTS, k=1)[0]
 
            if channel == "online":
                employee_id = None
            else:
                employee_id = random.choice(employees_by_store[store_id])
 
            status = pick_status(order_date)
 
            # Line items: 1-5 distinct products, weighted by popularity so
            # demand naturally concentrates on a small share of the catalog.
            n_items = random.randint(1, 5)
            chosen_products = random.choices(
                product_ids, weights=product_weights, k=min(n_items * 3, len(product_ids))
            )
            # de-dupe while preserving order, then trim to n_items
            seen = []
            for p in chosen_products:
                if p not in seen:
                    seen.append(p)
                if len(seen) == n_items:
                    break
 
            order_total = 0.0
            for product_id in seen:
                quantity = random.randint(1, 5)
                unit_price = price_by_product[product_id]
                # ~20% of line items get a small discount
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
 
 
PAYMENT_METHODS = ["cash", "card", "wallet", "bank_transfer"]
PAYMENT_METHOD_WEIGHTS = [0.15, 0.55, 0.2, 0.1]
 
# Orders in these statuses have actually been paid for.
PAID_STATUSES = {"confirmed", "shipped", "delivered"}
 
 
def generate_payments(orders_df):
    rows = []
    payment_id = 1
    for order in orders_df.itertuples(index=False):
        if order.status not in PAID_STATUSES:
            continue  # pending/cancelled orders have no payment yet
        paid_at_date = order.order_date + timedelta(days=random.randint(0, 2))
        paid_at = pd.Timestamp(paid_at_date) + pd.Timedelta(
            hours=random.randint(8, 21), minutes=random.randint(0, 59)
        )
        rows.append({
            "payment_id": payment_id,
            "order_id": order.order_id,
            "method": random.choices(PAYMENT_METHODS, weights=PAYMENT_METHOD_WEIGHTS, k=1)[0],
            "amount": order.total_amount,
            "paid_at": paid_at,
        })
        payment_id += 1
    return pd.DataFrame(rows)
 
 
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
 
    # Drop the helper column before writing — it's not a real DB column.
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