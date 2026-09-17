WITH customer_orders AS (
    SELECT
        c.customer_id,
        f.order_id,
        d.full_date,
        f.net_amount
    FROM dw.fact_sales f
    JOIN dw.dim_customer c ON c.customer_key = f.customer_key
    JOIN dw.dim_date d     ON d.date_key = f.date_key
    WHERE f.order_status <> 'cancelled'
),
rfm_raw AS (
    SELECT
        customer_id,
        MAX(full_date)                 AS last_order_date,
        (CURRENT_DATE - MAX(full_date)) AS recency_days,
        COUNT(DISTINCT order_id)       AS frequency,
        SUM(net_amount)                AS monetary
    FROM customer_orders
    GROUP BY customer_id
),
rfm_scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)      AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)       AS m_score
    FROM rfm_raw
)
SELECT
    customer_id,
    last_order_date,
    recency_days,
    frequency,
    monetary,
    r_score, f_score, m_score,
    (r_score::text || f_score::text || m_score::text) AS rfm_segment_code,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 4 AND f_score >= 3                  THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
        WHEN r_score BETWEEN 2 AND 3 AND f_score >= 3        THEN 'At Risk'
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4 THEN 'Cant Lose Them'
        WHEN r_score <= 2 AND f_score <= 2                  THEN 'Hibernating / Lost'
        ELSE 'Needs Attention'
    END AS rfm_segment_label
FROM rfm_scored
ORDER BY r_score DESC, f_score DESC, m_score DESC;