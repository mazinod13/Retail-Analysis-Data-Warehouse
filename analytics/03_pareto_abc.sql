--Top products by net sales
WITH product_revenue AS (
    SELECT
        p.product_id,
        p.name,
        p.category_name,
        SUM(f.net_amount) AS revenue,
        SUM(f.profit_amount) AS profit,
        SUM(f.quantity) AS quantity,
        SUM(f.gross_amount) AS gross,
        SUM(f.discount_amount) AS discount
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY p.product_key,p.name
),
cum AS (
    SELECT
        *,
        SUM(revenue) OVER (ORDER BY revenue DESC) AS running_total,
        SUM(revenue) OVER () AS grand_total,
        ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rank_position,
        COUNT(*) OVER () AS total_products
    FROM product_revenue    
)
SELECT
    product_id,
    name,
    category_name,
    revenue,
    rank_position,
    ROUND(100.0 * running_total / grand_total, 1) AS cumulutaive_pct,
    ROUND(100.0 * rank_position / total_products, 1) AS pct_of_products,
    CASE
        WHEN running_total / grand_total <=  0.80  THEN 'A'
        WHEN running_total / grand_total <=  0.95  THEN 'B'
        ELSE 'c'
    END as abc_class
FROM cum
ORDER BY revenue DESC;        

--Top products by gross sales
WITH product_gross AS (
    SELECT
        p.product_id,
        p.name,
        p.category_name,
        SUM(f.gross_amount) AS gross
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY p.product_key,p.name
),
cum AS (
    SELECT
        *,
        SUM(gross) OVER (ORDER BY gross DESC) AS running_total,
        SUM(gross) OVER () AS grand_total,
        ROW_NUMBER() OVER (ORDER BY gross DESC) AS rank_position,
        COUNT(*) OVER () AS total_products
    FROM product_gross    
)
SELECT
    product_id,
    name,
    category_name,
    gross,
    rank_position,
    ROUND(100.0 * running_total / grand_total, 1) AS cumulutaive_pct,
    ROUND(100.0 * rank_position / total_products, 1) AS pct_of_products,
    CASE
        WHEN running_total / grand_total <=  0.80  THEN 'A'
        WHEN running_total / grand_total <=  0.95  THEN 'B'
        ELSE 'c'
    END as abc_class
FROM cum
ORDER BY gross DESC;     

-- Top products by profit
WITH product_profit AS (
    SELECT
        p.product_id,
        p.name,
        p.category_name,
        SUM(f.profit_amount) AS profit
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY p.product_key,p.name
),
cum AS (
    SELECT
        *,
        SUM(profit) OVER (ORDER BY profit DESC) AS running_total,
        SUM(profit) OVER () AS grand_total,
        ROW_NUMBER() OVER (ORDER BY profit DESC) AS rank_position,
        COUNT(*) OVER () AS total_products
    FROM product_profit    
)
SELECT
    product_id,
    name,
    category_name,
    profit,
    rank_position,
    ROUND(100.0 * running_total / grand_total, 1) AS cumulutaive_pct,
    ROUND(100.0 * rank_position / total_products, 1) AS pct_of_products,
    CASE
        WHEN running_total / grand_total <=  0.80  THEN 'A'
        WHEN running_total / grand_total <=  0.95  THEN 'B'
        ELSE 'c'
    END as abc_class
FROM cum
ORDER BY profit DESC;        

--Top products by quantity sold
WITH product_quantity AS (
    SELECT
        p.product_id,
        p.name,
        p.category_name,
        SUM(f.quantity) AS quantity
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY p.product_key,p.name
),
cum AS (
    SELECT
        *,
        SUM(quantity) OVER (ORDER BY quantity DESC) AS running_total,
        SUM(quantity) OVER () AS grand_total,
        ROW_NUMBER() OVER (ORDER BY quantity DESC) AS rank_position,
        COUNT(*) OVER () AS total_products
    FROM product_quantity  
)
SELECT
    product_id,
    name,
    category_name,
    quantity,
    rank_position,
    ROUND(100.0 * running_total / grand_total, 1) AS cumulutaive_pct,
    ROUND(100.0 * rank_position / total_products, 1) AS pct_of_products,
    CASE
        WHEN running_total / grand_total <=  0.80  THEN 'A'
        WHEN running_total / grand_total <=  0.95  THEN 'B'
        ELSE 'c'
    END as abc_class
FROM cum
ORDER BY quantity DESC;      

--Top products by discount amount
WITH product_discount AS (
    SELECT
        p.product_id,
        p.name,
        p.category_name,
        SUM(f.discount_amount) AS discount
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY p.product_key,p.name
),
cum AS (
    SELECT
        *,
        SUM(discount) OVER (ORDER BY discount DESC) AS running_total,
        SUM(discount) OVER () AS grand_total,
        ROW_NUMBER() OVER (ORDER BY discount DESC) AS rank_position,
        COUNT(*) OVER () AS total_products
    FROM product_discount 
)
SELECT
    product_id,
    name,
    category_name,
    discount,
    rank_position,
    ROUND(100.0 * running_total / grand_total, 1) AS cumulutaive_pct,
    ROUND(100.0 * rank_position / total_products, 1) AS pct_of_products,
    CASE
        WHEN running_total / grand_total <=  0.80  THEN 'A'
        WHEN running_total / grand_total <=  0.95  THEN 'B'
        ELSE 'c'
    END as abc_class
FROM cum
ORDER BY discount DESC;      

--Top customer 
WITH customer_pareto AS (
    -- aggregate across ALL historical customer_key versions — no is_current filter
    SELECT
        c.customer_id,
        SUM(f.net_amount)      AS total_revenue,
        SUM(f.gross_amount)    AS total_gross,
        SUM(f.profit_amount)   AS total_profit,
        SUM(f.quantity)        AS total_quantity,
        SUM(f.discount_amount) AS total_discount
    FROM dw.fact_sales f
    JOIN dw.dim_customer c ON c.customer_key = f.customer_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY c.customer_id
),
current_attrs AS (
    SELECT customer_id, full_name, address, age, sex
    FROM dw.dim_customer
    WHERE is_current
),
cum AS (
    SELECT
        cp.*,
        ca.full_name, ca.address, ca.age, ca.sex,

        SUM(total_revenue)  OVER (ORDER BY total_revenue DESC)  AS running_revenue_total,
        SUM(total_revenue)  OVER ()                              AS grand_total_revenue,
        ROW_NUMBER()        OVER (ORDER BY total_revenue DESC)  AS revenue_rank,

        SUM(total_gross)    OVER (ORDER BY total_gross DESC)    AS running_gross_total,
        SUM(total_gross)    OVER ()                              AS grand_total_gross,
        ROW_NUMBER()        OVER (ORDER BY total_gross DESC)    AS gross_rank,

        SUM(total_profit)   OVER (ORDER BY total_profit DESC)   AS running_profit_total,
        SUM(total_profit)   OVER ()                              AS grand_total_profit,
        ROW_NUMBER()        OVER (ORDER BY total_profit DESC)   AS profit_rank,

        SUM(total_quantity) OVER (ORDER BY total_quantity DESC) AS running_quantity_total,
        SUM(total_quantity) OVER ()                              AS grand_total_quantity,
        ROW_NUMBER()        OVER (ORDER BY total_quantity DESC) AS quantity_rank,

        SUM(total_discount) OVER (ORDER BY total_discount DESC) AS running_discount_total,
        SUM(total_discount) OVER ()                              AS grand_total_discount,
        ROW_NUMBER()        OVER (ORDER BY total_discount DESC) AS discount_rank
    FROM customer_pareto cp
    JOIN current_attrs ca ON ca.customer_id = cp.customer_id
)
SELECT
    customer_id, full_name, address, age, sex,
    total_revenue, total_gross, total_profit, total_quantity, total_discount,
    revenue_rank, gross_rank, profit_rank, quantity_rank, discount_rank,

    ROUND(100.0 * running_revenue_total  / grand_total_revenue, 1)  AS cum_pct_revenue,
    ROUND(100.0 * running_gross_total    / grand_total_gross, 1)    AS cum_pct_gross,
    ROUND(100.0 * running_profit_total   / grand_total_profit, 1)   AS cum_pct_profit,
    ROUND(100.0 * running_quantity_total / grand_total_quantity, 1) AS cum_pct_quantity,
    ROUND(100.0 * running_discount_total / grand_total_discount, 1) AS cum_pct_discount,

    CASE WHEN running_revenue_total  / grand_total_revenue  <= 0.80 THEN 'A'
         WHEN running_revenue_total  / grand_total_revenue  <= 0.95 THEN 'B' ELSE 'C' END AS abc_class_revenue,
    CASE WHEN running_profit_total   / grand_total_profit   <= 0.80 THEN 'A'
         WHEN running_profit_total   / grand_total_profit   <= 0.95 THEN 'B' ELSE 'C' END AS abc_class_profit,
    CASE WHEN running_quantity_total / grand_total_quantity <= 0.80 THEN 'A'
         WHEN running_quantity_total / grand_total_quantity <= 0.95 THEN 'B' ELSE 'C' END AS abc_class_quantity
FROM cum
ORDER BY total_revenue DESC;


--daily-pareto
WITH daily_revenue AS (
    SELECT
        d.full_date,
        d.day_name,
        d.is_weekend,
        SUM(f.net_amount) AS revenue
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY d.full_date, d.day_name, d.is_weekend
),
cum AS (
    SELECT
        *,
        SUM(revenue) OVER (ORDER BY revenue DESC)   AS running_total,
        SUM(revenue) OVER ()                          AS grand_total,
        ROW_NUMBER() OVER (ORDER BY revenue DESC)    AS rank_position,
        COUNT(*) OVER ()                              AS total_days
    FROM daily_revenue
)
SELECT
    full_date, day_name, is_weekend, revenue, rank_position,
    ROUND(100.0 * running_total / grand_total, 1) AS cum_pct_revenue,
    ROUND(100.0 * rank_position / total_days, 1)   AS pct_of_days,
    CASE
        WHEN running_total / grand_total <= 0.80 THEN 'A'
        WHEN running_total / grand_total <= 0.95 THEN 'B'
        ELSE 'C'
    END AS day_class
FROM cum
ORDER BY revenue DESC;

--monthly-pareto
WITH monthly_revenue AS (
    SELECT
        d.fiscal_year,
        d.fiscal_quarter,
        DATE_TRUNC('month', d.full_date)::date AS month_start,
        SUM(f.net_amount) AS revenue
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY d.fiscal_year, d.fiscal_quarter, month_start
),
cum AS (
    SELECT
        *,
        SUM(revenue) OVER (ORDER BY revenue DESC)   AS running_total,
        SUM(revenue) OVER ()                          AS grand_total,
        ROW_NUMBER() OVER (ORDER BY revenue DESC)    AS rank_position,
        COUNT(*) OVER ()                              AS total_months
    FROM monthly_revenue
)
SELECT
    month_start, fiscal_year, fiscal_quarter, revenue, rank_position,
    ROUND(100.0 * running_total / grand_total, 1) AS cum_pct_revenue,
    ROUND(100.0 * rank_position / total_months, 1) AS pct_of_months,
    CASE
        WHEN running_total / grand_total <= 0.80 THEN 'A'
        WHEN running_total / grand_total <= 0.95 THEN 'B'
        ELSE 'C'
    END AS month_class
FROM cum
ORDER BY revenue DESC;

--quarter-pareto
WITH quarterly_product_revenue AS (
    SELECT
        d.fiscal_year,
        d.fiscal_quarter,
        p.product_key,
        p.name,
        SUM(f.net_amount) AS revenue
    FROM dw.fact_sales f
    JOIN dw.dim_date d    ON d.date_key = f.date_key
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY d.fiscal_year, d.fiscal_quarter, p.product_key, p.name
),
cum AS (
    SELECT
        *,
        SUM(revenue) OVER (PARTITION BY fiscal_year, fiscal_quarter ORDER BY revenue DESC) AS running_total,
        SUM(revenue) OVER (PARTITION BY fiscal_year, fiscal_quarter)                         AS quarter_total
    FROM quarterly_product_revenue
),
classified AS (
    SELECT
        fiscal_year, fiscal_quarter, product_key, name, revenue,
        CASE
            WHEN running_total / quarter_total <= 0.80 THEN 'A'
            WHEN running_total / quarter_total <= 0.95 THEN 'B'
            ELSE 'C'
        END AS abc_class
    FROM cum
)
SELECT
    curr.fiscal_year, curr.fiscal_quarter, curr.product_key, curr.name,
    curr.revenue, curr.abc_class AS class_this_quarter,
    prev.abc_class AS class_prev_quarter,
    CASE
        WHEN prev.abc_class IS NULL THEN 'New this quarter'
        WHEN prev.abc_class = curr.abc_class THEN 'Stable'
        WHEN (CASE prev.abc_class WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END)
           > (CASE curr.abc_class WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END) THEN 'Upgraded'
        ELSE 'Downgraded'
    END AS movement
FROM classified curr
LEFT JOIN classified prev
    ON curr.product_key = prev.product_key
    AND (
        (curr.fiscal_quarter > 1 AND prev.fiscal_year = curr.fiscal_year AND prev.fiscal_quarter = curr.fiscal_quarter - 1)
        OR (curr.fiscal_quarter = 1 AND prev.fiscal_year = curr.fiscal_year - 1 AND prev.fiscal_quarter = 4)
    )
ORDER BY curr.fiscal_year, curr.fiscal_quarter, curr.revenue DESC;