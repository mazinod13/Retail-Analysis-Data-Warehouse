


DELETE FROM dw.dim_employee;


INSERT INTO dw.dim_employee(
    employee_id,
    full_name,
    email,
    hire_date,
    manager_name,
    store_name
)
SELECT
    e.employee_id,
    e.first_name || ' ' || e.last_name AS full_name,
    e.email,
    e.hire_date,
    mgr.first_name || ' ' || mgr.last_name AS manager_name,
    s.name AS store_name
FROM public.employees as e
LEFT JOIN public.employees as mgr
    ON mgr.employee_id = e.manager_id
LEFT JOIN public.stores as s
    ON s.store_id = e.store_id
ON CONFLICT(employee_id)
DO UPDATE SET
    full_name =  EXCLUDED.full_name,
    email = EXCLUDED.email,
    hire_date = EXCLUDED.hire_date,
    manager_name = EXCLUDED.manager_name,
    store_name = EXCLUDED.store_name
WHERE
    dw.dim_employee.full_name IS DISTINCT FROM EXCLUDED.full_name            
    OR dw.dim_employee.email IS DISTINCT FROM EXCLUDED.email
    OR dw.dim_employee.hire_date IS DISTINCT FROM EXCLUDED.hire_date
    OR dw.dim_employee.manager_name IS DISTINCT FROM EXCLUDED.manager_name
    OR dw.dim_employee.store_name IS DISTINCT FROM EXCLUDED.store_name;


#test queries
SELECT count(*) FROM dw.dim_employee;      
SELECT count(*) FROM dw.dim_employee WHERE manager_name IS NULL; -- ~16 (15 managers + unknown)
SELECT * FROM dw.dim_employee WHERE employee_key = -1;         