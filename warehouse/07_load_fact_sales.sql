
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
   
    TO_CHAR(o.order_date, 'YYYYMMDD')::INT   AS date_key,

    dc.customer_key,
    dp.product_key,
    ds.store_key,

    COALESCE(de.employee_key, -1)            AS employee_key,

    o.order_id,                              -- degenerate dimension
    o.status                                 AS order_status,
    o.channel,

   
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

