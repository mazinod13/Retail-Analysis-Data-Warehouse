SELECT
    COALESCE(p.parent_category_name, 'ALL_CATEGORIES') AS parent_category,
    COALESCE(p.category_name, 'subtotal')            AS category,
    GROUPING(p.parent_category_name) AS is_grand_total,
    GROUPING(p.category_name)        AS is_subtotal,
    SUM(f.net_amount)   AS net_revenue,
    SUM(f.profit_amount) AS profit,
    SUM(f.quantity)     AS units,
    COUNT(DISTINCT f.order_id) AS orders
FROM dw.fact_sales f
JOIN dw.dim_product p ON p.product_key = f.product_key
WHERE f.order_status <> 'cancelled'
GROUP BY ROLLUP (p.parent_category_name, p.category_name)
ORDER BY GROUPING(p.parent_category_name),   -- grand total (1) sinks to the bottom
         p.parent_category_name,
         GROUPING(p.category_name) DESC,     -- subtotal (1) rises above children (0)
         SUM(f.net_amount) DESC;



SELECT
    p.parent_category_name AS parent_category,
    p.category_name        AS category,
    SUM(f.net_amount)      AS net_revenue,
    SUM(f.profit_amount)   AS profit,
    ROUND(100.0 * SUM(f.profit_amount)
          / NULLIF(SUM(f.net_amount), 0), 1)                         AS margin_pct,
    ROUND(100.0 * (SUM(f.gross_amount) - SUM(f.net_amount))
          / NULLIF(SUM(f.gross_amount), 0), 1)                       AS discount_pct,
    RANK() OVER (ORDER BY SUM(f.net_amount)    DESC)                 AS revenue_rank,
    RANK() OVER (ORDER BY SUM(f.profit_amount) DESC)                 AS profit_rank,
    RANK() OVER (ORDER BY SUM(f.profit_amount) DESC)
      - RANK() OVER (ORDER BY SUM(f.net_amount) DESC)                AS rank_gap
FROM dw.fact_sales f
JOIN dw.dim_product p ON p.product_key = f.product_key
WHERE f.order_status <> 'cancelled'
GROUP BY p.parent_category_name, p.category_name
ORDER BY rank_gap DESC, net_revenue DESC;