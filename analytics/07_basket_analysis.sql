

-- ---------------------------------------------------------------------------
-- 1. CATEGORY-LEVEL ASSOCIATION RULES
-- ---------------------------------------------------------------------------
WITH baskets AS (
    SELECT DISTINCT
        f.order_id,
        p.category_name AS item
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
),
total AS (
    SELECT COUNT(DISTINCT order_id)::numeric AS n_baskets FROM baskets
),
item_freq AS (
    SELECT item, COUNT(*)::numeric AS n_item FROM baskets GROUP BY item
),
pair_freq AS (
    SELECT a.item AS item_a, b.item AS item_b, COUNT(*)::numeric AS n_pair
    FROM baskets a
    JOIN baskets b
        ON a.order_id = b.order_id
       AND a.item < b.item
    GROUP BY 1, 2
)
SELECT
    pf.item_a,
    pf.item_b,
    pf.n_pair::int                                     AS pair_baskets,
    ROUND(100 * pf.n_pair / t.n_baskets, 3)            AS support_pct,
    ROUND(100 * pf.n_pair / fa.n_item, 2)              AS conf_a_to_b_pct,
    ROUND(100 * pf.n_pair / fb.n_item, 2)              AS conf_b_to_a_pct,
    ROUND((pf.n_pair * t.n_baskets) / (fa.n_item * fb.n_item), 3) AS lift
FROM pair_freq pf
CROSS JOIN total t
JOIN item_freq fa ON fa.item = pf.item_a
JOIN item_freq fb ON fb.item = pf.item_b
WHERE pf.n_pair >= 50
ORDER BY lift DESC;


-- ---------------------------------------------------------------------------
-- 2. SUBSTITUTES — the bottom of the same ranking
-- ---------------------------------------------------------------------------
WITH baskets AS (
    SELECT DISTINCT f.order_id, p.category_name AS item
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.order_status <> 'cancelled'
),
total AS (SELECT COUNT(DISTINCT order_id)::numeric AS n_baskets FROM baskets),
item_freq AS (SELECT item, COUNT(*)::numeric AS n_item FROM baskets GROUP BY item),
pair_freq AS (
    SELECT a.item AS item_a, b.item AS item_b, COUNT(*)::numeric AS n_pair
    FROM baskets a JOIN baskets b ON a.order_id = b.order_id AND a.item < b.item
    GROUP BY 1, 2
)
SELECT
    pf.item_a, pf.item_b, pf.n_pair::int AS pair_baskets,
    ROUND((pf.n_pair * t.n_baskets) / (fa.n_item * fb.n_item), 3) AS lift
FROM pair_freq pf
CROSS JOIN total t
JOIN item_freq fa ON fa.item = pf.item_a
JOIN item_freq fb ON fb.item = pf.item_b
WHERE pf.n_pair >= 50
ORDER BY lift ASC
LIMIT 15;


-- ---------------------------------------------------------------------------
-- 3. PRODUCT-LEVEL RULES — demonstrating the sparsity problem
-- ---------------------------------------------------------------------------
WITH baskets AS (
    SELECT DISTINCT f.order_id, f.product_key AS item
    FROM dw.fact_sales f
    WHERE f.order_status <> 'cancelled'
),
total AS (SELECT COUNT(DISTINCT order_id)::numeric AS n_baskets FROM baskets),
item_freq AS (SELECT item, COUNT(*)::numeric AS n_item FROM baskets GROUP BY item),
pair_freq AS (
    SELECT a.item AS item_a, b.item AS item_b, COUNT(*)::numeric AS n_pair
    FROM baskets a JOIN baskets b ON a.order_id = b.order_id AND a.item < b.item
    GROUP BY 1, 2
    HAVING COUNT(*) >= 30
)
SELECT
    pa.name AS product_a,
    pb.name AS product_b,
    pa.category_name AS category_a,
    pb.category_name AS category_b,
    pf.n_pair::int AS pair_baskets,
    ROUND(100 * pf.n_pair / t.n_baskets, 4) AS support_pct,
    ROUND((pf.n_pair * t.n_baskets) / (fa.n_item * fb.n_item), 3) AS lift
FROM pair_freq pf
CROSS JOIN total t
JOIN item_freq fa ON fa.item = pf.item_a
JOIN item_freq fb ON fb.item = pf.item_b
JOIN dw.dim_product pa ON pa.product_key = pf.item_a
JOIN dw.dim_product pb ON pb.product_key = pf.item_b
ORDER BY lift DESC
LIMIT 20;


-- ---------------------------------------------------------------------------
-- 4. BASKET COMPOSITION — context for everything above
-- ---------------------------------------------------------------------------
WITH b AS (
    SELECT order_id, COUNT(DISTINCT product_key) AS n_items
    FROM dw.fact_sales
    WHERE order_status <> 'cancelled'
    GROUP BY order_id
)
SELECT
    n_items                                                  AS items_in_basket,
    COUNT(*)                                                 AS baskets,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)       AS pct_of_baskets,
    SUM(n_items * (n_items - 1) / 2)                         AS pair_instances
FROM b
GROUP BY n_items
ORDER BY n_items;

