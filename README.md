# Retail Analytics Data Warehouse

An end-to-end data project I'm building to learn how a real analytics stack fits together: a normalized OLTP database that mimics a retail chain's operational system, an ETL pipeline that loads it into a dimensional warehouse, advanced SQL analytics on top, and finally a BI dashboard.

I'm building this in phases and documenting the decisions as I go, including the ones I got wrong the first time.

---

## Architecture

```
OLTP (3NF)  →  ETL  →  Star Schema Warehouse  →  Reporting Views  →  Dashboard
```

| Layer | What it does | Status |
|---|---|---|
| OLTP schema | Normalized transactional tables — the "source system" | Done |
| Synthetic data | ~5k customers, ~500 products, ~100k orders over 3 years | In progress |
| Star schema | Fact and dimension tables for analytics | Planned |
| ETL | Incremental load from OLTP into the warehouse | Planned |
| Analytics SQL | Window functions, CTEs, recursive queries, cohort analysis | Planned |
| Optimization | Index tuning with before/after execution plans | Planned |
| Views & procedures | Reporting layer, stored procedures, triggers | Planned |
| Dashboard | Power BI / Metabase on top of the views | Planned |

---

## Tech stack

- **PostgreSQL 16** — database
- **Python 3** (`faker`, `pandas`, `psycopg2`) — data generation and ETL
- **dbdiagram.io / DBML** — schema as version-controlled code, diagram generated from it
- **VS Code** with the DBML ERD extension for previewing the diagram while editing

---

## Repository structure

```
├── docs/                  # ERD diagram + DBML source, design notes
├── schema/                # OLTP DDL
├── etl/                   # Data generation and load scripts
├── sample_data/           # Generated CSVs (gitignored — reproducible from the script)
├── analytics/             # Advanced SQL queries
├── optimization/          # Index experiments and execution plans
├── dashboard/             # Dashboard file and screenshots
```

---

## Phase 1 — OLTP schema (done)

The operational schema is normalized to 3NF across nine tables:

`categories` · `stores` · `customers` · `products` · `employees` · `orders` · `order_items` · `inventory` · `payments`

![ER Diagram](docs/diagram-1785843237164.png)

The schema is written as DBML in [docs/schema.dbml](docs/schema.dbml) so it lives in version control and the diagram is generated from it rather than drawn by hand. The DDL is in [schema/01_create_tables.sql](schema/01_create_tables.sql).

### Design decisions

**`order_items` stores its own `unit_price`.** My first instinct was to join back to `products` for the price, but that breaks the moment a product's price changes — every historical order would silently be revalued. Storing the price at the time of sale keeps history correct.

**`categories.parent_category_id` is self-referencing.** This gives me a real category hierarchy (Electronics → Laptops) instead of a flat list. It also sets up the recursive CTE work later, where I want to roll sales up through every level of the tree.

**`employees.manager_id` is nullable and self-referencing.** It has to be nullable — the top-level manager has nobody above them, so a `NOT NULL` constraint would make the first row impossible to insert. Same recursive structure as categories, applied to an org chart.

**`orders.employee_id` is nullable.** Online orders have no salesperson attached. Rather than inventing a fake "web" employee, I let the column be null and treat it as a genuine absence.

**Composite unique constraints where the grain demands it.** `order_items` is unique on `(order_id, product_id)` — the same product shouldn't appear twice on one order; the quantity should increase instead. `inventory` is unique on `(store_id, product_id)` for the same reason: one stock row per product per store.

**`ON DELETE CASCADE` only on truly dependent rows.** Order items and payments cascade from `orders` because they have no meaning without the parent order. Nothing cascades from `customers` or `products` — deleting those should fail loudly rather than quietly destroying sales history.

**Check constraints on every domain column.** Quantities must be positive, prices and discounts non-negative, and `status` and `channel` are restricted to a known set of values. I'd rather the database reject bad data than discover it during analysis.

---

## Phase 2 — Synthetic data (in progress)

Realistic data matters more than I expected: uniformly random data makes every analytical query return a flat, boring result. The generator in [etl/generate_data.py](etl/generate_data.py) deliberately builds in the patterns I'll want to detect later:

- **Seasonality** — order volume spikes in November and December.
- **Pareto product demand** — roughly 20% of products drive 80% of revenue, using weighted sampling rather than uniform choice.
- **Mixed customer behavior** — one-time buyers, occasional shoppers, and loyal repeat customers, so churn and retention are actually measurable.
- **Continuous signups** across three years, which is what makes cohort analysis possible.
- **Referential realism** — no order predates its store's opening date, and online orders carry no employee.

Everything is seeded (`random.seed(42)`, `Faker.seed(42)`) so the dataset is reproducible. Generated CSVs are gitignored — anyone cloning the repo regenerates them by running the script.

---

## Getting started

```bash
# 1. Create the database
createdb retail_warehouse_db

# 2. Build the OLTP schema
psql -d retail_warehouse_db -f schema/01_create_tables.sql

# 3. Configure the connection (create a .env file in the project root)
DATABASE_URL=postgresql://<user>:<password>@127.0.0.1:5432/retail_warehouse_db

# 4. Install dependencies and generate data
pip install -r requirements.txt
python etl/generate_data.py
```

---

## What's next

- [x] Normalized OLTP schema with constraints and ER diagram
- [ ] Synthetic data generation and bulk load
- [ ] Star schema warehouse (`fact_sales`, `dim_date`, `dim_customer` as SCD Type 2, `dim_product`, `dim_store`)
- [ ] Incremental ETL with data quality checks
- [ ] Advanced SQL: window functions, RFM segmentation, recursive category rollups, cohort retention
- [ ] Index tuning with before/after `EXPLAIN ANALYZE` comparisons
- [ ] Stored procedures, triggers, and reporting views
- [ ] Dashboard built on the reporting views
