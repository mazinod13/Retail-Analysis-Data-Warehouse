-- ===========================================================================
-- Warehouse validation suite
-- ===========================================================================
-- Checks the loaded warehouse against the source system and against its own
-- declared invariants. Every check returns one row: what was expected, what
-- was found, and PASS/FAIL.
--
-- Run after the full load. Everything must PASS before building analytics on
-- top — a wrong dimension key produces confident, plausible, wrong numbers,
-- and those are far harder to notice than a crash.
--
--   psql -U postgres -d retail_warehouse_db -f warehouse/98_validate_warehouse.sql
-- ===========================================================================

WITH checks AS (

-- ---------------------------------------------------------------------------
-- dim_date
-- ---------------------------------------------------------------------------
SELECT 1 AS ord, 'dim_date' AS dimension, 'row count = 2191 (2021-2026 incl. leap)' AS check_name,
       '2191' AS expected, (SELECT count(*)::text FROM dw.dim_date) AS actual

UNION ALL SELECT 2, 'dim_date', 'no gaps in the date series',
       '0', (SELECT ((max(full_date) - min(full_date) + 1) - count(*))::text FROM dw.dim_date)

UNION ALL SELECT 3, 'dim_date', 'date_key matches full_date',
       '0', (SELECT count(*)::text FROM dw.dim_date
             WHERE date_key <> TO_CHAR(full_date,'YYYYMMDD')::int)

UNION ALL SELECT 4, 'dim_date', 'month_name / day_name have no padding',
       '0', (SELECT count(*)::text FROM dw.dim_date
             WHERE month_name <> btrim(month_name) OR day_name <> btrim(day_name))

UNION ALL SELECT 5, 'dim_date', 'day_of_week in 1..7 (ISODOW)',
       '0', (SELECT count(*)::text FROM dw.dim_date WHERE day_of_week NOT BETWEEN 1 AND 7)

UNION ALL SELECT 6, 'dim_date', 'is_weekend agrees with day_of_week',
       '0', (SELECT count(*)::text FROM dw.dim_date WHERE is_weekend <> (day_of_week >= 6))

UNION ALL SELECT 7, 'dim_date', 'is_leap_year agrees with actual year length',
       '0', (SELECT count(*)::text FROM (
                SELECT year, bool_or(is_leap_year) AS flagged, count(*) AS days
                FROM dw.dim_date GROUP BY year
             ) y WHERE flagged <> (days = 366))

UNION ALL SELECT 8, 'dim_date', 'fiscal year flips exactly on Jul 17',
       '2024|2025', (SELECT string_agg(fiscal_year::text, '|' ORDER BY full_date)
                     FROM dw.dim_date WHERE full_date IN ('2025-07-16','2025-07-17'))

UNION ALL SELECT 9, 'dim_date', 'fiscal quarters at Jul17/Oct17/Jan17/Apr17',
       '1|2|3|4', (SELECT string_agg(fiscal_quarter::text, '|' ORDER BY full_date)
                   FROM dw.dim_date
                   WHERE full_date IN ('2025-07-17','2025-10-17','2026-01-17','2026-04-17'))

UNION ALL SELECT 10, 'dim_date', 'covers every order date in the source',
       '0', (SELECT count(*)::text FROM public.orders o
             WHERE NOT EXISTS (SELECT 1 FROM dw.dim_date d WHERE d.full_date = o.order_date))

-- ---------------------------------------------------------------------------
-- dim_store
-- ---------------------------------------------------------------------------
UNION ALL SELECT 20, 'dim_store', 'row count matches source',
       (SELECT count(*)::text FROM public.stores), (SELECT count(*)::text FROM dw.dim_store)

UNION ALL SELECT 21, 'dim_store', 'every source store present, attributes match',
       '0', (SELECT count(*)::text FROM public.stores s
             LEFT JOIN dw.dim_store d ON d.store_id = s.store_id
             WHERE d.store_id IS NULL
                OR d.name IS DISTINCT FROM s.name
                OR d.city IS DISTINCT FROM s.city
                OR d.manager IS DISTINCT FROM s.manager
                OR d.opened_date IS DISTINCT FROM s.opened_date)

UNION ALL SELECT 22, 'dim_store', 'no duplicate natural keys',
       '0', (SELECT count(*)::text FROM (
                SELECT store_id FROM dw.dim_store GROUP BY 1 HAVING count(*) > 1) x)

-- ---------------------------------------------------------------------------
-- dim_employee
-- ---------------------------------------------------------------------------
UNION ALL SELECT 30, 'dim_employee', 'row count = source + 1 unknown member',
       (SELECT (count(*) + 1)::text FROM public.employees), (SELECT count(*)::text FROM dw.dim_employee)

UNION ALL SELECT 31, 'dim_employee', 'unknown member (-1) present',
       '1', (SELECT count(*)::text FROM dw.dim_employee WHERE employee_key = -1)

UNION ALL SELECT 32, 'dim_employee', 'every source employee present',
       '0', (SELECT count(*)::text FROM public.employees e
             WHERE NOT EXISTS (SELECT 1 FROM dw.dim_employee d WHERE d.employee_id = e.employee_id))

UNION ALL SELECT 33, 'dim_employee', 'manager_name resolves correctly (self-join)',
       '0', (SELECT count(*)::text
             FROM dw.dim_employee d
             JOIN public.employees e ON e.employee_id = d.employee_id
             LEFT JOIN public.employees m ON m.employee_id = e.manager_id
             WHERE d.manager_name IS DISTINCT FROM (m.first_name || ' ' || m.last_name))

UNION ALL SELECT 34, 'dim_employee', 'store_name populated for all real employees',
       '0', (SELECT count(*)::text FROM dw.dim_employee
             WHERE employee_key <> -1 AND store_name IS NULL)

-- ---------------------------------------------------------------------------
-- dim_product
-- ---------------------------------------------------------------------------
UNION ALL SELECT 40, 'dim_product', 'row count matches source',
       (SELECT count(*)::text FROM public.products), (SELECT count(*)::text FROM dw.dim_product)

UNION ALL SELECT 41, 'dim_product', 'prices and costs match source exactly',
       '0', (SELECT count(*)::text FROM public.products p
             LEFT JOIN dw.dim_product d ON d.product_id = p.product_id
             WHERE d.product_id IS NULL
                OR d.unit_price IS DISTINCT FROM p.unit_price
                OR d.cost IS DISTINCT FROM p.cost
                OR d.name IS DISTINCT FROM p.name
                OR d.brand IS DISTINCT FROM p.brand)

UNION ALL SELECT 42, 'dim_product', 'category_name never null',
       '0', (SELECT count(*)::text FROM dw.dim_product WHERE category_name IS NULL)

UNION ALL SELECT 43, 'dim_product', 'category_name matches source category',
       '0', (SELECT count(*)::text FROM dw.dim_product d
             JOIN public.products p ON p.product_id = d.product_id
             JOIN public.categories c ON c.category_id = p.category_id
             WHERE d.category_name IS DISTINCT FROM c.name)

UNION ALL SELECT 44, 'dim_product', 'parent_category_name matches the real parent',
       '0', (SELECT count(*)::text FROM dw.dim_product d
             JOIN public.products p ON p.product_id = d.product_id
             JOIN public.categories c ON c.category_id = p.category_id
             LEFT JOIN public.categories pc ON pc.category_id = c.parent_category_id
             WHERE d.parent_category_name IS DISTINCT FROM pc.name)

UNION ALL SELECT 45, 'dim_product', 'category_path = parent > child',
       '0', (SELECT count(*)::text FROM dw.dim_product
             WHERE parent_category_name IS NOT NULL
               AND category_path <> parent_category_name || ' > ' || category_name)

UNION ALL SELECT 46, 'dim_product', 'distinct category paths = leaf categories used',
       (SELECT count(DISTINCT category_id)::text FROM public.products),
       (SELECT count(DISTINCT category_path)::text FROM dw.dim_product)

-- ---------------------------------------------------------------------------
-- dim_customer (SCD Type 2)
-- ---------------------------------------------------------------------------
UNION ALL SELECT 50, 'dim_customer', 'distinct customers matches source',
       (SELECT count(*)::text FROM public.customers),
       (SELECT count(DISTINCT customer_id)::text FROM dw.dim_customer)

UNION ALL SELECT 51, 'dim_customer', 'exactly one current row per customer',
       '0', (SELECT count(*)::text FROM (
                SELECT customer_id FROM dw.dim_customer WHERE is_current
                GROUP BY 1 HAVING count(*) <> 1) x)

UNION ALL SELECT 52, 'dim_customer', 'every customer has a current row',
       '0', (SELECT count(*)::text FROM public.customers s
             WHERE NOT EXISTS (SELECT 1 FROM dw.dim_customer d
                               WHERE d.customer_id = s.customer_id AND d.is_current))

UNION ALL SELECT 53, 'dim_customer', 'current rows have no valid_to',
       '0', (SELECT count(*)::text FROM dw.dim_customer WHERE is_current AND valid_to IS NOT NULL)

UNION ALL SELECT 54, 'dim_customer', 'closed rows all have valid_to',
       '0', (SELECT count(*)::text FROM dw.dim_customer WHERE NOT is_current AND valid_to IS NULL)

UNION ALL SELECT 55, 'dim_customer', 'valid_from <= valid_to on every closed row',
       '0', (SELECT count(*)::text FROM dw.dim_customer
             WHERE valid_to IS NOT NULL AND valid_from > valid_to)

UNION ALL SELECT 56, 'dim_customer', 'no gaps/overlaps between consecutive versions',
       '0', (SELECT count(*)::text FROM (
                SELECT customer_id, valid_to,
                       LEAD(valid_from) OVER (PARTITION BY customer_id ORDER BY valid_from) AS next_from
                FROM dw.dim_customer) v
             WHERE next_from IS NOT NULL AND valid_to IS DISTINCT FROM next_from)

UNION ALL SELECT 57, 'dim_customer', 'current row attributes match source',
       '0', (SELECT count(*)::text FROM dw.dim_customer d
             JOIN public.customers s ON s.customer_id = d.customer_id
             WHERE d.is_current
               AND (d.city IS DISTINCT FROM s.city
                 OR d.state IS DISTINCT FROM s.state
                 OR d.email IS DISTINCT FROM s.email
                 OR d.address IS DISTINCT FROM s.address
                 OR d.full_name IS DISTINCT FROM (s.first_name || ' ' || s.last_name)))

UNION ALL SELECT 58, 'dim_customer', 'first version backdated to signup_date',
       '0', (SELECT count(*)::text FROM (
                SELECT DISTINCT ON (customer_id) customer_id, valid_from, signup_date
                FROM dw.dim_customer ORDER BY customer_id, valid_from) f
             WHERE valid_from <> signup_date)

UNION ALL SELECT 59, 'dim_customer', 'no order predates its customer''s first version',
       '0', (SELECT count(*)::text FROM public.orders o
             WHERE o.order_date < (SELECT min(valid_from) FROM dw.dim_customer d
                                   WHERE d.customer_id = o.customer_id))

-- ---------------------------------------------------------------------------
-- fact_sales
-- ---------------------------------------------------------------------------
UNION ALL SELECT 70, 'fact_sales', 'row count matches source order_items',
       (SELECT count(*)::text FROM public.order_items), (SELECT count(*)::text FROM dw.fact_sales)

UNION ALL SELECT 71, 'fact_sales', 'net revenue reconciles to source',
       (SELECT round(sum(quantity*unit_price-discount),2)::text FROM public.order_items),
       (SELECT round(sum(net_amount),2)::text FROM dw.fact_sales)

UNION ALL SELECT 72, 'fact_sales', 'gross revenue reconciles to source',
       (SELECT round(sum(quantity*unit_price),2)::text FROM public.order_items),
       (SELECT round(sum(gross_amount),2)::text FROM dw.fact_sales)

UNION ALL SELECT 73, 'fact_sales', 'net_amount = gross - discount',
       '0', (SELECT count(*)::text FROM dw.fact_sales
             WHERE net_amount <> gross_amount - discount_amount)

UNION ALL SELECT 74, 'fact_sales', 'profit_amount = net - cost',
       '0', (SELECT count(*)::text FROM dw.fact_sales
             WHERE profit_amount <> net_amount - cost_amount)

UNION ALL SELECT 75, 'fact_sales', 'gross_amount = quantity * dim unit_price',
       '0', (SELECT count(*)::text FROM dw.fact_sales f
             JOIN dw.dim_product p ON p.product_key = f.product_key
             JOIN public.order_items oi ON oi.order_id = f.order_id AND oi.product_id = p.product_id
             WHERE f.gross_amount <> f.quantity * oi.unit_price)

UNION ALL SELECT 76, 'fact_sales', 'cost_amount = quantity * dim cost',
       '0', (SELECT count(*)::text FROM dw.fact_sales f
             JOIN dw.dim_product p ON p.product_key = f.product_key
             WHERE f.cost_amount <> f.quantity * p.cost)

UNION ALL SELECT 77, 'fact_sales', 'date_key matches the order date',
       '0', (SELECT count(*)::text FROM dw.fact_sales f
             JOIN public.orders o ON o.order_id = f.order_id
             WHERE f.date_key <> TO_CHAR(o.order_date,'YYYYMMDD')::int)

UNION ALL SELECT 78, 'fact_sales', 'store_key resolves to the order''s store',
       '0', (SELECT count(*)::text FROM dw.fact_sales f
             JOIN public.orders o ON o.order_id = f.order_id
             JOIN dw.dim_store d ON d.store_key = f.store_key
             WHERE d.store_id <> o.store_id)

UNION ALL SELECT 79, 'fact_sales', 'product_key resolves to the line''s product',
       '0', (SELECT count(*)::text FROM dw.fact_sales f
             JOIN dw.dim_product p ON p.product_key = f.product_key
             WHERE NOT EXISTS (SELECT 1 FROM public.order_items oi
                               WHERE oi.order_id = f.order_id AND oi.product_id = p.product_id))

UNION ALL SELECT 80, 'fact_sales', 'SCD2: customer version valid at order date',
       '0', (SELECT count(*)::text FROM dw.fact_sales f
             JOIN public.orders o ON o.order_id = f.order_id
             JOIN dw.dim_customer d ON d.customer_key = f.customer_key
             WHERE d.customer_id <> o.customer_id
                OR o.order_date < d.valid_from
                OR (d.valid_to IS NOT NULL AND o.order_date >= d.valid_to))

UNION ALL SELECT 81, 'fact_sales', 'unknown employee used only by online orders',
       '0', (SELECT count(*)::text FROM dw.fact_sales
             WHERE employee_key = -1 AND channel <> 'online')

UNION ALL SELECT 82, 'fact_sales', 'online orders never use a real employee',
       '0', (SELECT count(*)::text FROM dw.fact_sales
             WHERE channel = 'online' AND employee_key <> -1)

UNION ALL SELECT 83, 'fact_sales', 'employee_key resolves to the order''s employee',
       '0', (SELECT count(*)::text FROM dw.fact_sales f
             JOIN public.orders o ON o.order_id = f.order_id
             JOIN dw.dim_employee d ON d.employee_key = f.employee_key
             WHERE f.employee_key <> -1 AND d.employee_id IS DISTINCT FROM o.employee_id)

UNION ALL SELECT 84, 'fact_sales', 'grain holds: no duplicate (order_id, product_key)',
       '0', (SELECT count(*)::text FROM (
                SELECT order_id, product_key FROM dw.fact_sales
                GROUP BY 1,2 HAVING count(*) > 1) x)

UNION ALL SELECT 85, 'fact_sales', 'order_status values match the source domain',
       '0', (SELECT count(*)::text FROM dw.fact_sales f
             JOIN public.orders o ON o.order_id = f.order_id
             WHERE f.order_status <> o.status OR f.channel <> o.channel)

UNION ALL SELECT 86, 'fact_sales', 'no negative quantities or gross amounts',
       '0', (SELECT count(*)::text FROM dw.fact_sales
             WHERE quantity <= 0 OR gross_amount < 0 OR discount_amount < 0)

UNION ALL SELECT 87, 'fact_sales', 'revenue by store reconciles to source',
       '0', (SELECT count(*)::text FROM (
                SELECT ds.store_id, round(sum(f.net_amount),2) AS dw_net
                FROM dw.fact_sales f JOIN dw.dim_store ds ON ds.store_key = f.store_key
                GROUP BY 1) w
             FULL JOIN (
                SELECT o.store_id, round(sum(oi.quantity*oi.unit_price-oi.discount),2) AS src_net
                FROM public.order_items oi JOIN public.orders o ON o.order_id = oi.order_id
                GROUP BY 1) s ON s.store_id = w.store_id
             WHERE w.dw_net IS DISTINCT FROM s.src_net)

UNION ALL SELECT 88, 'fact_sales', 'revenue by month reconciles to source',
       '0', (SELECT count(*)::text FROM (
                SELECT dd.year, dd.month, round(sum(f.net_amount),2) AS dw_net
                FROM dw.fact_sales f JOIN dw.dim_date dd ON dd.date_key = f.date_key
                GROUP BY 1,2) w
             FULL JOIN (
                SELECT EXTRACT(YEAR FROM o.order_date)::int AS y,
                       EXTRACT(MONTH FROM o.order_date)::int AS m,
                       round(sum(oi.quantity*oi.unit_price-oi.discount),2) AS src_net
                FROM public.order_items oi JOIN public.orders o ON o.order_id = oi.order_id
                GROUP BY 1,2) s ON s.y = w.year AND s.m = w.month
             WHERE w.dw_net IS DISTINCT FROM s.src_net)
)

SELECT dimension,
       check_name,
       expected,
       actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE '*** FAIL ***' END AS result
FROM checks
ORDER BY ord;
