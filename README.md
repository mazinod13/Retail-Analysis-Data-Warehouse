# Retail Analytics Data Warehouse

An end-to-end data project I'm building to learn how a real analytics stack fits together: a normalized OLTP database that mimics a retail chain's operational system, an ETL pipeline that loads it into a dimensional warehouse, advanced SQL analytics on top, and finally a BI dashboard.

I'm building this in phases and documenting the decisions as I go, including the ones I got wrong the first time.

---

## Architecture

```
OLTP (3NF)  →  ETL  →  Star Schema Warehouse  →  Reporting Views  →  Dashboard
```

| Layer              | What it does                                               | Status      |
| ------------------ | ---------------------------------------------------------- | ----------- |
| OLTP schema        | Normalized transactional tables — the "source system"     | Done        |
| Synthetic data     | 17k customers, 500 products, 94.5k orders over 3 years     | Done        |
| Star schema        | 5 dimensions + 284.5k-row fact table, SCD Type 2 customers | Done        |
| Warehouse ETL      | Idempotent SQL loads, point-in-time key resolution         | Done        |
| Analytics SQL      | Window functions, CTEs, recursive queries, cohort analysis | In progress |
| Optimization       | Index tuning with before/after execution plans             | Planned     |
| Views & procedures | Reporting layer, stored procedures, triggers               | Planned     |
| Dashboard          | Power BI / Metabase on top of the views                    | Planned     |

---

## Tech stack

- **PostgreSQL 18** — database
- **Python 3** (`faker`, `pandas`, `psycopg2`) — data generation and ETL
- **dbdiagram.io / DBML** — schema as version-controlled code, diagram generated from it
- **VS Code** with the DBML ERD extension for previewing the diagram while editing

---

## Repository structure

```
├── docs/                  # ERD diagram + DBML source, design notes
├── schema/                # OLTP DDL (00_drop_tables.sql, 01_create_tables.sql)
├── etl/
│   ├── config.py          # All sizing knobs, date ranges, and the random seed
│   ├── generators/        # One module per table
│   ├── generate_data.py   # Orchestrator — runs generators in FK order, writes CSVs
│   └── load_data.py       # Bulk COPY into Postgres + sequence reset
├── sample_data/           # Generated CSVs (gitignored — reproducible from the script)
├── warehouse/             # Star schema DDL + numbered ETL loads
│   ├── warehouse.md       # Design rationale for every modelling decision
│   ├── 01_create_dw_tables.sql
│   ├── 02..07_load_*.sql  # dim_date → dims → fact_sales, run in order
│   └── 99_demo_scd2.sql   # Perturbs the source to exercise Type 2 versioning
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

## Phase 2 — Synthetic data (done)

**490,445 rows across nine tables**, covering three years of trading (2023-08-13 → 2026-08-12) and $313.6M in gross revenue.

| Table | Rows | | Table | Rows |
| --- | ---: | --- | --- | ---: |
| `order_items` | 284,504 | | `products` | 500 |
| `orders` | 94,534 | | `employees` | 162 |
| `payments` | 86,194 | | `categories` | 36 |
| `customers` | 17,000 | | `stores` | 15 |
| `inventory` | 7,500 | | | |

Realistic data mattered far more than I expected. My first attempt used uniform random values everywhere, and the result was useless: every analytical query returned a flat line. There was nothing to *find*. So the generator ([etl/generators/](etl/generators/)) deliberately builds in the patterns I'll want to detect later.

### The patterns, and how they're produced

**Seasonality.** A weighted calendar biases order dates toward November and December. Measured on the data: November 2025 has 6,679 orders against October's 3,261 — a 2.05× lift, in line with real retail.

**Pareto demand.** Each product gets a hidden `popularity_weight` drawn from `random.paretovariate()`, used as the weight in `random.choices` when picking line items. I never hardcode which products are popular — the concentration emerges. Result: the top 20% of products account for 86% of revenue.

**Mixed customer behavior.** Every customer is assigned a hidden segment (`one_time`, `occasional`, `loyal`, `never_bought`) that determines how many orders they place. This produces a realistic long tail — mean 6.0 orders per customer, median 1, max 40 — and 1,227 customers who signed up and never purchased. Without this spread, cohort retention and RFM segmentation would have nothing to measure.

**Referential realism.** No order predates its store's opening date or its customer's signup. Online orders (39.8%) carry no `employee_id`. Payments exist only for orders that actually resolved, and always match the order total exactly.

### Design decisions

**Hidden attributes never reach the database.** `popularity_weight`, customer segment, and stock tier all exist only in Python — they're modelling inputs, not business data. A real `products` table has no "popularity" column; popularity is something you *derive* from sales. Keeping them out of the CSVs preserves that: the analytics in later phases have to discover these patterns rather than read them off a column.

**Orders and order_items are generated together.** `orders.total_amount` has to equal the real sum of its line items. Generating them in two independent passes would guarantee they never reconcile, so each order's items are built immediately and summed into the total.

**`COPY`, not `INSERT`.** [etl/load_data.py](etl/load_data.py) bulk-loads via `psycopg2`'s `copy_expert`. At ~490k rows, row-by-row inserts would take minutes for no benefit.

**Sequences must be reset after loading.** This one caught me out. `COPY` writes explicit IDs straight into the column and never touches the `SERIAL` sequence, so after loading, every sequence was still sitting at 1 — and the first ordinary `INSERT` failed with a primary key collision. The load script now fast-forwards all nine sequences with `setval(pg_get_serial_sequence(...), MAX(id) + 1, false)`.

**Everything is seeded.** `random.seed(42)` and `Faker.seed(42)` at import time in [etl/config.py](etl/config.py), so the dataset is byte-for-byte reproducible. Generated CSVs are gitignored — anyone cloning the repo regenerates them.

**One place to tune.** Every sizing knob, date range, and distribution lives in [etl/config.py](etl/config.py). Changing the dataset size is a one-line edit, not a hunt through eight modules.

### Validating before loading

I wrote a validation pass that checks the CSVs against every schema constraint *before* attempting the load, rather than discovering violations 200k rows into a `COPY`. It covers:

- Every `VARCHAR` length limit, `CHECK` constraint, and `UNIQUE` constraint
- Referential integrity for all nine foreign keys, including the two self-referencing ones
- Business rules: `total_amount` reconciles against line items to the cent, no order predates its store or customer, online orders carry no employee, payments match order totals
- Distribution sanity: seasonality lift, Pareto concentration, orders-per-customer spread

This caught three real bugs — 3,329 orders with a `status` value the `CHECK` constraint rejects, a phantom `tier` column that didn't exist in the table, and an entirely missing customer segment that left a hole in the distribution between 1 and 9 orders.

### What went wrong along the way

**Editing a file doesn't change the database.** I fixed a bad `DEFAULT 0` / `CHECK (> 0)` contradiction in my DDL, re-ran the script, and got "relation already exists" — the tables were still there from the first run and my fix never executed. That's what [schema/00_drop_tables.sql](schema/00_drop_tables.sql) is for.

**Editing a generator doesn't change the CSVs.** Same lesson, one level up. I spent time debugging data that had been generated ten hours earlier by code I'd since changed. Now I check timestamps before trusting output.

**The first dataset was quietly broken.** It passed every constraint check but was analytically useless: order volume grew 69× across the window (because signups were spread over the *same* window as orders, so early months had almost no eligible customers), and the "occasional" segment was misconfigured to 10-30 orders instead of 2-8, leaving zero customers in the 2-8 range. Decoupling the signup window from the order window and fixing the ranges brought it down to a believable 12× growth curve with a properly filled distribution.

---

## Phase 3 — Star schema warehouse (done)

The warehouse lives in a `dw` schema alongside the OLTP tables. Full design rationale is in [warehouse/warehouse.md](warehouse/warehouse.md).

| Table | Rows | Type |
| --- | ---: | --- |
| `fact_sales` | 284,504 | Fact — grain: one product line on one order |
| `dim_customer` | 17,204 | **SCD Type 2** (17,000 current + 204 historical versions) |
| `dim_date` | 2,191 | Generated, Nepali fiscal calendar |
| `dim_product` | 500 | Type 1, category hierarchy flattened in |
| `dim_employee` | 163 | Type 1, includes an unknown member |
| `dim_store` | 15 | Type 1 |

**The grain, stated up front:** one row in `fact_sales` is one product line on one order. Everything else follows from that sentence. It's the lowest detail the source offers, so every other level — order, day, month, category, region — aggregates up from it. You can always roll up; you can never break back down.

### Why a star schema when the OLTP could already answer these questions

It could, but badly. "Revenue by category by month" against the source means joining `order_items → orders → products → categories`, then walking the category tree recursively, and repeating that work on every single query. The star pre-resolves those joins into wide, denormalized dimensions so analytical queries touch two tables instead of five. Storage and write complexity traded for read speed — a good trade when data is written once by ETL and read constantly by dashboards.

### Slowly Changing Dimension Type 2

`dim_customer` keeps history. When a tracked attribute changes, the existing row is closed (`valid_to` set, `is_current` cleared) and a new row is inserted with a fresh surrogate key.

This is the part of the project I'd point at first. Three things had to be right:

**The natural key must not be unique.** My first draft had `customer_id INT NOT NULL UNIQUE`, which makes Type 2 impossible — one customer needs many rows, one per version. Uniqueness is instead enforced by a partial unique index, which expresses what actually needs to be true:

```sql
CREATE UNIQUE INDEX uq_dim_customer_current
    ON dw.dim_customer (customer_id) WHERE is_current;
```

Many historical rows per customer, never more than one current.

**One script handles both the initial and incremental load.** Step 1 closes changed rows; step 2 inserts a current row for anyone who *doesn't have one*. That condition is true both for a customer never loaded before and for one whose row step 1 just closed — so a single `INSERT` covers both cases and there's no separate first-run path to keep in sync.

**`age` is deliberately not tracked.** It changes for everyone every year and would churn all 17,000 rows annually for no analytical benefit. A predictable change isn't a slowly changing dimension.

### Proving it works

Static generated data means the versioning branch never fires — the dimension loads correctly and produces no history at all. So [warehouse/99_demo_scd2.sql](warehouse/99_demo_scd2.sql) perturbs the source (170 relocations, 68 email changes) and the load is re-run.

Results: **204 rows closed, 204 replacements inserted.** That number is itself a check — 170 + 68 − 34 customers caught by both filters = 204, so change detection found precisely the right rows. Four invariants verified:

- Every customer still has exactly one current row
- **Zero timeline gaps** — each closed `valid_to` equals its successor's `valid_from` exactly
- Distinct customer count unchanged at 17,000
- Re-running reports `UPDATE 0 / INSERT 0` — idempotent

### Point-in-time key resolution

The reason Type 2 is worth the effort shows up in the fact load. `customer_key` is resolved as of the **order date**, not as of now:

```sql
JOIN dw.dim_customer AS dc
    ON  dc.customer_id = o.customer_id
    AND o.order_date  >= dc.valid_from
    AND (o.order_date < dc.valid_to OR dc.valid_to IS NULL)
```

**3,543 fact rows** point at superseded customer versions — sales correctly attributed to where the customer lived at the time, not where they live now. Replace that join with `AND dc.is_current` and every one of those sales gets silently rewritten.

The strict `<` is load-bearing. A closed row's `valid_to` equals its successor's `valid_from`, so `<=` would match both versions on the changeover day and duplicate the fact row. Half-open intervals `[from, to)` tile exactly.

### Other modelling decisions

**Unknown member instead of NULL keys.** 37,624 orders are online and have no salesperson. Rather than allowing a NULL foreign key — which breaks inner joins and forces every downstream query to remember an outer join — `dim_employee` carries an explicit `employee_key = -1` row labelled "Online / No Salesperson". Every fact foreign key is `NOT NULL`.

**Star, not snowflake.** The category hierarchy is flattened into `dim_product` as `category_name`, `parent_category_name`, and `category_path`. Keeping separate category tables would rebuild the OLTP normalization inside the warehouse and discard the benefit. Flattening a self-referencing hierarchy is what a recursive CTE is for, so the recursive query does real work in the ETL rather than existing as a showcase.

**Cancelled orders are loaded, not filtered.** `order_status` rides along on the fact so reporting can exclude them from revenue while cancellation rate stays measurable. Dropping them at load time would make that question permanently unanswerable.

**Derived measures are stored.** `net_amount`, `cost_amount`, and `profit_amount` are all computable from other columns. Computing once at load beats recomputing on every dashboard query.

**Idempotent loads via upsert.** Every dimension load is `INSERT ... ON CONFLICT (natural_key) DO UPDATE ... WHERE <columns> IS DISTINCT FROM EXCLUDED.<columns>`. The `IS DISTINCT FROM` guard means a re-run with unchanged source writes zero rows rather than rewriting everything and bloating the table with dead tuples. `IS DISTINCT FROM` rather than `<>` because `<>` yields NULL when either side is NULL, so a NULL→value change would go undetected.

### Reconciliation

The fact load has to tie out exactly, and it does:

| Check | Result |
| --- | --- |
| Fact rows vs source `order_items` | 284,504 = 284,504 |
| Net revenue | $313,590,190.94 = $313,590,190.94 |
| Rows on the unknown member | 112,994 — all `channel = 'online'` |

Exact row parity is the check that matters. Fewer would mean a join silently dropped rows; **more** would mean the SCD2 window matched two customer versions and double-counted revenue.

### What went wrong here

**`DELETE` and upsert don't mix.** My dimension loads started with `DELETE FROM dw.dim_<x>;` followed by a carefully written `ON CONFLICT` clause — which the delete made unreachable, since an empty table can't conflict. Worse, it regenerates surrogate keys on every run (silently repointing every fact row) and it destroyed the unknown member. That last one bit twice before I removed the deletes.

**Multiple `WITH` keywords.** My first recursive CTE attempt declared one CTE per output column, each with its own `WITH` and no `FROM` clause. A CTE is a named result set, not a variable declaration — and one that selects from nothing can't see another's columns. Ten CTEs collapsed into ten lines of a single `SELECT`.

**`#` is not a SQL comment.** That's MySQL. PostgreSQL uses `--`.

### Running it

```bash
cd warehouse
for f in 01_create_dw_tables.sql 02_load_dim_data.sql 03_load_dim_store.sql \
         04_load_dim_employee.sql 05_load_dim_product.sql \
         06_load_dim_customer.sql 07_load_fact_sales.sql; do
    psql -U postgres -d retail_warehouse_db -v ON_ERROR_STOP=1 -f "$f"
done
```

Order matters: dimensions before the fact table, or its foreign keys have nothing to resolve against.

---

## Getting started

```bash
# 1. Create the database
createdb retail_warehouse_db

# 2. Build the OLTP schema
psql -U postgres -d retail_warehouse_db -f schema/01_create_tables.sql

# 3. Configure the connection (create a .env file in the project root)
echo "DATABASE_URL=postgresql://<user>:<password>@127.0.0.1:5432/retail_warehouse_db" > .env

# 4. Install dependencies
pip install -r requirements.txt

# 5. Generate the dataset (writes sample_data/*.csv) and load it
python etl/generate_data.py
python etl/load_data.py --truncate
```

### Rebuilding the schema from scratch

`00_drop_tables.sql` drops all nine tables in reverse dependency order. It's a separate file rather than a header on the create script so it can't be run by accident once real data is loaded.

```bash
psql -U postgres -d retail_warehouse_db -v ON_ERROR_STOP=1 -f schema/00_drop_tables.sql
psql -U postgres -d retail_warehouse_db -v ON_ERROR_STOP=1 -f schema/01_create_tables.sql
```

`ON_ERROR_STOP=1` aborts on the first error instead of continuing and leaving a half-built schema.

---

## What's next

- [X] Normalized OLTP schema with constraints and ER diagram
- [X] Synthetic data generation, validation, and bulk load (490k rows)
- [X] Star schema warehouse (`fact_sales`, `dim_date`, `dim_customer` as SCD Type 2, `dim_product`, `dim_store`)
- [X] Idempotent warehouse ETL with point-in-time key resolution and reconciliation checks
- [ ] Advanced SQL: window functions, RFM segmentation, recursive category rollups, cohort retention
- [ ] Index tuning with before/after `EXPLAIN ANALYZE` comparisons
- [ ] Stored procedures, triggers, and reporting views
- [ ] Dashboard built on the reporting views
