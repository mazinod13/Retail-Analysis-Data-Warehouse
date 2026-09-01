-- ===========================================================================
-- Load dw.fact_sales
-- ===========================================================================
-- GRAIN: one row per product line on one order. Source is order_items,
-- joined up to orders for the order-level attributes.
--
-- Every dimension must be loaded before this runs — the fact table's foreign
-- keys have nothing to resolve against otherwise.
--
-- The job of this script is SURROGATE KEY RESOLUTION: the source carries
-- natural keys (customer_id, product_id, store_id, employee_id) and the fact
-- table stores warehouse keys (customer_key, product_key, ...). Each join
-- below translates one to the other.
--
-- Two of those translations are not straightforward:
--
--   1. customer_key is resolved AS OF THE ORDER DATE, not as of now. See the
--      note on that join below — this is the entire payoff of building
--      dim_customer as Type 2.
--
--   2. employee_key falls back to the -1 unknown member for online orders,
--      which have no salesperson. The column is NOT NULL by design.
--
-- Cancelled orders are loaded, not filtered. order_status rides along so
-- reporting views can exclude them from revenue while cancellation rate
-- stays measurable.
--
-- Safe to re-run: the upsert keys on (order_id, product_key), which is the
-- declared grain, so a second run corrects measures rather than duplicating
-- rows.
-- ===========================================================================

INSERT INTO dw.fact_sales (
    date_key,
    customer_key,
    product_key,
    store_key,
    employee_key,
    order_id,
    order_status,
    channel,
    quantity,
    gross_amount,
    discount_amount,
    net_amount,
    cost_amount,
    profit_amount
)
SELECT
    -- date_key is computed rather than looked up: it IS the date in YYYYMMDD
    -- form, so a join to dim_date would buy nothing. The foreign key still
    -- enforces that the date exists in the dimension.
    TO_CHAR(o.order_date, 'YYYYMMDD')::INT   AS date_key,

    dc.customer_key,
    dp.product_key,
    ds.store_key,

    -- Online orders carry no employee_id, so the LEFT JOIN below yields NULL
    -- and this collapses it onto the unknown member.
    COALESCE(de.employee_key, -1)            AS employee_key,

    o.order_id,                              -- degenerate dimension
    o.status                                 AS order_status,
    o.channel,

    -- Measures. unit_price comes from order_items (the price at time of
    -- sale), NOT from products — the source deliberately snapshots it so
    -- that later price changes cannot revalue historical orders.
    oi.quantity,
    (oi.quantity * oi.unit_price)                        AS gross_amount,
    oi.discount                                          AS discount_amount,
    (oi.quantity * oi.unit_price - oi.discount)          AS net_amount,
    (oi.quantity * dp.cost)                              AS cost_amount,
    (oi.quantity * oi.unit_price - oi.discount
        - oi.quantity * dp.cost)                         AS profit_amount

FROM public.order_items AS oi

JOIN public.orders AS o
    ON o.order_id = oi.order_id

-- -----------------------------------------------------------------------
-- SCD Type 2 lookup: pick the customer version that was valid ON THE DAY
-- OF THE ORDER, not the version that is current now.
--
-- The validity window is half-open — [valid_from, valid_to). That matters
-- on the changeover day itself: a closed row's valid_to equals its
-- successor's valid_from, so using <= would match BOTH versions and
-- duplicate the fact row. Using < matches exactly one.
--
-- valid_to IS NULL means the version is still open, so it has no upper
-- bound to test.
--
-- This join is why dim_customer is Type 2. Swap it for `AND dc.is_current`
-- and every historical sale would be silently re-attributed to the
-- customer's present-day city.
-- -----------------------------------------------------------------------
JOIN dw.dim_customer AS dc
    ON  dc.customer_id = o.customer_id
    AND o.order_date  >= dc.valid_from
    AND (o.order_date < dc.valid_to OR dc.valid_to IS NULL)

-- Type 1 dimensions: one row per natural key, so a plain equality join.
JOIN dw.dim_product AS dp
    ON dp.product_id = oi.product_id

JOIN dw.dim_store AS ds
    ON ds.store_id = o.store_id

-- LEFT, because employee_id is legitimately NULL on online orders.
LEFT JOIN dw.dim_employee AS de
    ON de.employee_id = o.employee_id

ON CONFLICT (order_id, product_key)
DO UPDATE SET
    date_key        = EXCLUDED.date_key,
    customer_key    = EXCLUDED.customer_key,
    store_key       = EXCLUDED.store_key,
    employee_key    = EXCLUDED.employee_key,
    order_status    = EXCLUDED.order_status,
    channel         = EXCLUDED.channel,
    quantity        = EXCLUDED.quantity,
    gross_amount    = EXCLUDED.gross_amount,
    discount_amount = EXCLUDED.discount_amount,
    net_amount      = EXCLUDED.net_amount,
    cost_amount     = EXCLUDED.cost_amount,
    profit_amount   = EXCLUDED.profit_amount;


-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------
-- Row count must equal order_items exactly. Fewer means a join dropped rows;
-- more means the SCD2 window matched two versions for some order.
--
--   SELECT (SELECT count(*) FROM dw.fact_sales)   AS fact_rows,
--          (SELECT count(*) FROM public.order_items) AS source_rows;
--
-- Revenue must reconcile against the source to the cent.
--
--   SELECT (SELECT sum(net_amount) FROM dw.fact_sales) AS warehouse_net,
--          (SELECT sum(quantity * unit_price - discount) FROM public.order_items)
--                                                       AS source_net;
--
-- No order should have matched more than one customer version.
--
--   SELECT order_id, product_key, count(*) FROM dw.fact_sales
--   GROUP BY 1,2 HAVING count(*) > 1;   -- the grain constraint makes this impossible
--
-- Online orders must all point at the unknown member.
--
--   SELECT channel, count(*) FROM dw.fact_sales
--   WHERE employee_key = -1 GROUP BY 1;   -- expect only 'online'
--
-- Cancelled orders are present but excludable.
--
--   SELECT order_status, count(*), sum(net_amount) FROM dw.fact_sales
--   GROUP BY 1 ORDER BY 2 DESC;
-- ---------------------------------------------------------------------------
