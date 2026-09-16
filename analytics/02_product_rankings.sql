SELECT
    p.product_id,
    p.name,
    p.category_name,
    SUM(f.net_amount)   AS total_revenue,
    SUM(f.profit_amount)   AS total_profit,
    SUM(f.quantity)     AS total_quantity_sold,
    RANK()  OVER (ORDER BY SUM(f.net_amount) DESC) AS revenue_rank,
    RANK() OVER (ORDER BY SUM(f.profit_amount)DESC) AS profit_rank,
    RANK() OVER (ORDER BY SUM(f.quantity) DESC) AS quantity_rank 
FROM dw.fact_sales f
JOIN dw.dim_product p ON p.product_key = f.product_key
WHERE f.order_status <> 'cancelled'
GROUP BY p.product_id, p.name, p.category_name
ORDER BY revenue_rank;    

WITH ranked AS (
    SELECT
        p.category_name,
        p.brand,
        p.product_id,
        p.name,
        SUM(f.net_amount)   AS revenue,
        ROW_NUMBER() OVER (PARTITION BY p.brand ORDER BY SUM(f.net_amount) DESC) AS rank_in_category
    FROM dw.fact_sales f
    JOIN dw.dim_product p on p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled' and p.brand = 'Craftwell'
    GROUP BY p.category_name,p.product_id, p.name,p.brand

)
SELECT * FROM ranked
WHERE rank_in_category <= 5
ORDER BY category_name, rank_in_category;

WITH brand_rank AS (
    SELECT
        p.brand,
        p.category_name,
        p.product_id,
        p.name,
        SUM(f.net_amount) AS revenue,
        ROW_NUMBER() OVER (PARTITION BY p.brand ORDER BY SUM(f.net_amount) DESC) AS rank_in_brand
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY p.brand, p.category_name, p.product_id, p.name
)
SELECT * FROM brand_rank
WHERE rank_in_brand <= 5
ORDER BY brand, rank_in_brand;

WITH brand_category_revenue AS (
    SELECT
        p.category_name,
        p.brand,
        SUM(f.net_amount)    AS brand_revenue,
        SUM(f.profit_amount) AS brand_profit,
        SUM(f.quantity)      AS brand_units,
        COUNT(DISTINCT p.product_id) AS product_count
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY p.category_name, p.brand
),
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY category_name ORDER BY brand_revenue DESC) AS rank_in_category
    FROM brand_category_revenue
)
SELECT *
FROM ranked
WHERE rank_in_category <= 5
ORDER BY category_name, rank_in_category;

WITH monthly_rank AS (
    SELECT
        DATE_TRUNC('month', d.full_date)::date AS month_start,
        p.product_id, p.name,
        SUM(f.net_amount) AS revenue,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', d.full_date) ORDER BY SUM(f.net_amount) DESC) AS month_rank
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY month_start, p.product_id, p.name
)
SELECT
    curr.month_start, curr.product_id, curr.name,
    curr.month_rank AS rank_this_month,
    prev.month_rank AS rank_last_month,
    prev.month_rank - curr.month_rank AS rank_improvement   -- positive = moved up
FROM monthly_rank curr
LEFT JOIN monthly_rank prev
    ON curr.product_id = prev.product_id
    AND prev.month_start = curr.month_start - INTERVAL '1 month'
ORDER BY curr.month_start, rank_improvement DESC NULLS LAST;