-- ===========================================================================
-- Load dw.dim_product
-- ===========================================================================
-- This is where the category hierarchy gets FLATTENED into the product
-- dimension. The source keeps categories in a self-referencing table
-- (categories.parent_category_id); the warehouse stores the resolved names
-- directly on each product row so analytical queries never have to walk the
-- tree at read time.
--
-- The walk is done with a RECURSIVE CTE. The current tree is only two levels
-- deep (8 roots, 28 children), so a plain self-join would also work today.
-- The recursive form handles arbitrary depth with no code change — add a
-- third level tomorrow and this still produces correct paths.
--
-- Type 1 dimension: attribute changes overwrite in place, no history kept.
-- The upsert below IS that Type 1 behaviour. Contrast with dim_customer,
-- which is Type 2 and versions instead.
--
-- Safe to re-run. Deliberately no DELETE: surrogate keys must stay stable
-- because fact_sales stores product_key, and re-generating those keys would
-- silently repoint every fact row.
-- ===========================================================================

WITH RECURSIVE category_tree AS (

    -- ANCHOR — the base case: root categories, which have no parent.
    --
    -- Both casts here are load-bearing. Postgres infers each column's type
    -- from the anchor alone and then demands the recursive term match:
    --   NULL::text  — a bare NULL has no type ("could not determine data type")
    --   name::text  — name is VARCHAR(100), but the recursive term below
    --                 produces text via ||, and the two must agree
    SELECT
        c.category_id,
        c.name,
        NULL::text AS parent_name,
        c.name::text AS category_path
    FROM public.categories AS c
    WHERE c.parent_category_id IS NULL

    UNION ALL

    -- RECURSIVE — joins categories back against rows the previous pass
    -- produced. Pass 1 finds the 28 children of the 8 roots; pass 2 returns
    -- nothing, which is what terminates the recursion.
    --
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
-- LEFT JOIN on purpose: an inner join would silently drop any product whose
-- category failed to appear in the tree. A NULL category_name is visible in
-- the verification queries; a missing row is not.
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
-- Skip rows that have not actually changed, so a re-run touches nothing and
-- writes no dead tuples. IS DISTINCT FROM (rather than <>) because NULL <> NULL
-- is NULL, not false, and parent_category_name is nullable.
WHERE
    dw.dim_product.name                 IS DISTINCT FROM EXCLUDED.name
    OR dw.dim_product.brand                IS DISTINCT FROM EXCLUDED.brand
    OR dw.dim_product.category_name        IS DISTINCT FROM EXCLUDED.category_name
    OR dw.dim_product.parent_category_name IS DISTINCT FROM EXCLUDED.parent_category_name
    OR dw.dim_product.category_path        IS DISTINCT FROM EXCLUDED.category_path
    OR dw.dim_product.unit_price           IS DISTINCT FROM EXCLUDED.unit_price
    OR dw.dim_product.cost                 IS DISTINCT FROM EXCLUDED.cost;
