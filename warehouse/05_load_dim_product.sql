
WITH RECURSIVE category_tree AS (

    SELECT
        c.category_id,
        c.name,
        NULL::text AS parent_name,
        c.name::text AS category_path
    FROM public.categories AS c
    WHERE c.parent_category_id IS NULL

    UNION ALL

    -- UNION ALL rather than UNION: UNION would deduplicate, costing a sort on
    -- every pass. That is only needed when the graph can contain cycles, and
    -- a category tree cannot.
    SELECT
        c.category_id,
        c.name,
        t.name AS parent_name,
        t.category_path || ' > ' || c.name AS category_path
    FROM public.categories AS c
    JOIN category_tree AS t
        ON c.parent_category_id = t.category_id
)

INSERT INTO dw.dim_product (
    product_id,
    name,
    brand,
    category_name,
    parent_category_name,
    category_path,
    unit_price,
    cost
)
SELECT
    p.product_id,
    p.name,
    p.brand,
    t.name AS category_name,
    t.parent_name AS parent_category_name,
    t.category_path,
    p.unit_price,
    p.cost
FROM public.products AS p
LEFT JOIN category_tree AS t
    ON t.category_id = p.category_id

ON CONFLICT (product_id)
DO UPDATE SET
    name                 = EXCLUDED.name,
    brand                = EXCLUDED.brand,
    category_name        = EXCLUDED.category_name,
    parent_category_name = EXCLUDED.parent_category_name,
    category_path        = EXCLUDED.category_path,
    unit_price           = EXCLUDED.unit_price,
    cost                 = EXCLUDED.cost
WHERE
    dw.dim_product.name                 IS DISTINCT FROM EXCLUDED.name
    OR dw.dim_product.brand                IS DISTINCT FROM EXCLUDED.brand
    OR dw.dim_product.category_name        IS DISTINCT FROM EXCLUDED.category_name
    OR dw.dim_product.parent_category_name IS DISTINCT FROM EXCLUDED.parent_category_name
    OR dw.dim_product.category_path        IS DISTINCT FROM EXCLUDED.category_path
    OR dw.dim_product.unit_price           IS DISTINCT FROM EXCLUDED.unit_price
    OR dw.dim_product.cost                 IS DISTINCT FROM EXCLUDED.cost;


#test
SELECT count(*) FROM dw.dim_product;                                    -- 500
SELECT count(*) FROM dw.dim_product WHERE category_name IS NULL;        -- 0
SELECT count(*) FROM dw.dim_product WHERE parent_category_name IS NULL; -- 0
SELECT count(DISTINCT category_path) FROM dw.dim_product;               -- 28
SELECT DISTINCT category_path FROM dw.dim_product ORDER BY 1 LIMIT 5;
