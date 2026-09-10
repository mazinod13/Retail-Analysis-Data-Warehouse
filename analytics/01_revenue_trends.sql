WITH monthly AS (
    SELECT
        DATE_TRUNC('month', d.full_date)::date AS month_start,
        d.year,
        d.month,
        d.month_name,
        SUM(f.net_amount)    AS net_revenue,
        SUM(f.gross_amount)  AS gross_revenue,
        SUM(f.profit_amount) AS profit,
        COUNT(DISTINCT f.order_id) AS orders,
        SUM(f.quantity)      AS quantity,
        SUM(f.net_amount) / NULLIF(COUNT(DISTINCT f.order_id), 0) AS avg_order_value
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY d.year, d.month, d.month_name, month_start
),
trended AS (
    SELECT
        m.*,
        SUM(net_revenue)     OVER (PARTITION BY year ORDER BY month_start)                              AS ytd_revenue,
        SUM(profit)          OVER (PARTITION BY year ORDER BY month_start)                              AS ytd_profit,
        SUM(orders)          OVER (PARTITION BY year ORDER BY month_start)                              AS ytd_orders,
        LAG(net_revenue)     OVER (ORDER BY month_start)                                                 AS prev_month_revenue,
        LAG(net_revenue, 12) OVER (ORDER BY month_start)                                                 AS same_month_last_year,
        ROUND(AVG(net_revenue) OVER (ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)  AS moving_avg_3mo
    FROM monthly m
)
SELECT
    month_start,
    month_name,
    year,

    -- volume / topline
    net_revenue,
    gross_revenue,
    orders,
    quantity,
    ROUND(avg_order_value, 2)                                    AS avg_order_value,

    -- profitability
    profit,
    ROUND(100.0 * profit / NULLIF(net_revenue, 0), 1)            AS profit_margin_pct,
    ROUND(100.0 * (gross_revenue - net_revenue) / NULLIF(gross_revenue, 0), 1) AS discount_pct,

    -- cumulative
    ytd_revenue,
    ytd_profit,
    ytd_orders,

    -- trend
    ROUND(100.0 * (net_revenue - prev_month_revenue) / NULLIF(prev_month_revenue, 0), 1) AS mom_pct,
    ROUND(100.0 * (net_revenue - same_month_last_year) / NULLIF(same_month_last_year, 0), 1) AS yoy_pct,
    moving_avg_3mo

FROM trended
ORDER BY month_start;



WITH comp_stores AS (
    SELECT store_key
    FROM dw.dim_store
    WHERE opened_date <= CURRENT_DATE - INTERVAL '12 months'
),
sss_monthly AS (
    SELECT
        DATE_TRUNC('month', d.full_date)::date AS month_start,
        d.year, d.month,
        SUM(f.net_amount) AS comp_revenue,
        COUNT(DISTINCT f.store_key) AS comp_store_count
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
    JOIN comp_stores cs ON cs.store_key = f.store_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY d.year, d.month, month_start
)
SELECT
    month_start,
    comp_revenue,
    comp_store_count,
    LAG(comp_revenue, 12) OVER (ORDER BY month_start) AS comp_revenue_ly,
    ROUND(100.0 * (comp_revenue - LAG(comp_revenue, 12) OVER (ORDER BY month_start))
          / NULLIF(LAG(comp_revenue, 12) OVER (ORDER BY month_start), 0), 1) AS sss_growth_pct
FROM sss_monthly
ORDER BY month_start;


SELECT
    DATE_TRUNC('month', d.full_date)::date AS month_start,
    p.category_name,
    p.parent_category_name,
    p.category_path,
    SUM(f.net_amount)    AS category_revenue,
    SUM(f.profit_amount) AS category_profit,
    SUM(f.quantity)      AS category_units,
    COUNT(DISTINCT f.order_id) AS category_orders
FROM dw.fact_sales f
JOIN dw.dim_date d    ON d.date_key = f.date_key
JOIN dw.dim_product p ON p.product_key = f.product_key
WHERE f.order_status <> 'cancelled'
GROUP BY month_start, p.category_name, p.parent_category_name, p.category_path
ORDER BY month_start, category_revenue DESC;


WITH annual AS (
    SELECT d.year, SUM(f.net_amount) AS yearly_revenue
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
    WHERE f.order_status <> 'cancelled'
    GROUP BY d.year
),
bounds AS (
    SELECT
        MIN(year) AS start_year,
        MAX(year) AS end_year,
        (SELECT yearly_revenue FROM annual a WHERE a.year = MIN(annual.year)) AS start_revenue,
        (SELECT yearly_revenue FROM annual a WHERE a.year = MAX(annual.year)) AS end_revenue
    FROM annual
)
SELECT
    start_year, end_year,
    start_revenue, end_revenue,
    end_year - start_year AS num_years,
    ROUND(
        (POWER(end_revenue / NULLIF(start_revenue, 0), 1.0 / NULLIF(end_year - start_year, 0)) - 1) * 100
    , 2) AS cagr_pct
FROM bounds;
