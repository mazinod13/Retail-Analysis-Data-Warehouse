WITH customer_orders AS (
    SELECT
        c.customer_id,
        f.order_id,
        d.full_date,
        DATE_TRUNC('month', d.full_date)::date AS order_month,
        f.net_amount
    FROM dw.fact_sales f
    JOIN dw.dim_customer c ON c.customer_key = f.customer_key
    JOIN dw.dim_date d     ON d.date_key = f.date_key
    WHERE f.order_status <> 'cancelled'
),
customer_cohort AS (
    SELECT
        customer_id,
        MIN(order_month) AS cohort_month
    FROM customer_orders
    GROUP BY customer_id
),
cohort_activity AS (
    SELECT
        co.customer_id,
        cc.cohort_month,
        co.order_month,
        (EXTRACT(YEAR FROM co.order_month) - EXTRACT(YEAR FROM cc.cohort_month)) * 12
          + (EXTRACT(MONTH FROM co.order_month) - EXTRACT(MONTH FROM cc.cohort_month)) AS period_number
    FROM customer_orders co
    JOIN customer_cohort cc ON cc.customer_id = co.customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS num_customers
    FROM customer_cohort
    GROUP BY cohort_month
),
cohort_retention AS (
    SELECT
        ca.cohort_month,
        ca.period_number,
        COUNT(DISTINCT ca.customer_id) AS active_customers
    FROM cohort_activity ca
    GROUP BY ca.cohort_month, ca.period_number
),
-- this CTE is the "long-format query" the pivot below reads from
retention_long AS (
    SELECT
        cr.cohort_month,
        cs.num_customers AS cohort_size,
        cr.period_number,
        cr.active_customers,
        ROUND(100.0 * cr.active_customers / cs.num_customers, 1) AS retention_pct
    FROM cohort_retention cr
    JOIN cohort_size cs ON cs.cohort_month = cr.cohort_month
)
-- pivoted "retention triangle" — the actual output
SELECT
    cohort_month,
    MAX(cohort_size)                                        AS cohort_size,
    MAX(CASE WHEN period_number = 0 THEN retention_pct END) AS m0,
    MAX(CASE WHEN period_number = 1 THEN retention_pct END) AS m1,
    MAX(CASE WHEN period_number = 2 THEN retention_pct END) AS m2,
    MAX(CASE WHEN period_number = 3 THEN retention_pct END) AS m3,
    MAX(CASE WHEN period_number = 4 THEN retention_pct END) AS m4,
    MAX(CASE WHEN period_number = 5 THEN retention_pct END) AS m5
FROM retention_long
GROUP BY cohort_month
ORDER BY cohort_month;