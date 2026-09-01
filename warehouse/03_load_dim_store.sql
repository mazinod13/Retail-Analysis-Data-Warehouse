INSERT INTO dw.dim_store(
    store_id,
    name,
    city,
    phone,
    manager,
    opened_date
)
SELECT
    s.store_id,
    s.name,
    s.city,
    s.phone,
    s.manager,
    s.opened_date
FROM public.stores as s 
ON CONFLICT (store_id)
DO UPDATE SET
    name = EXCLUDED.name,
    city = EXCLUDED.city,
    phone = EXCLUDED.phone,
    manager = EXCLUDED.manager,
    opened_date = EXCLUDED.opened_date
WHERE
    dw.dim_store.name  IS DISTINCT FROM EXCLUDED.name
    OR dw.dim_store.city IS DISTINCT FROm EXCLUDED.city 
    OR dw.dim_store.phone IS DISTINCT FROm EXCLUDED.phone
    OR dw.dim_store.manager IS DISTINCT FROm EXCLUDED.manager
    OR dw.dim_store.opened_date IS DISTINCT FROm EXCLUDED.opened_date        
