
BEGIN;

UPDATE dw.dim_customer AS d
SET valid_to   = CURRENT_DATE,
    is_current = FALSE
FROM public.customers AS s
WHERE d.customer_id = s.customer_id
  AND d.is_current
  AND (
        d.city    IS DISTINCT FROM s.city
     OR d.state   IS DISTINCT FROM s.state
     OR d.address IS DISTINCT FROM s.address
     OR d.phone   IS DISTINCT FROM s.phone
     OR d.email   IS DISTINCT FROM s.email
  );


INSERT INTO dw.dim_customer (
    customer_id,
    full_name,
    email,
    phone,
    address,
    city,
    state,
    age,
    sex,
    signup_date,
    valid_from,
    valid_to,
    is_current
)
SELECT
    s.customer_id,
    s.first_name || ' ' || s.last_name AS full_name,
    s.email,
    s.phone,
    s.address,
    s.city,
    s.state,
    s.age,
    s.sex,
    s.signup_date,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM dw.dim_customer AS h
            WHERE h.customer_id = s.customer_id
        )
        THEN CURRENT_DATE       -- a superseding version: valid from today
        ELSE s.signup_date      -- first ever version: backdate to signup
    END AS valid_from,
    NULL::date AS valid_to,     -- NULL means "still true"
    TRUE       AS is_current
FROM public.customers AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM dw.dim_customer AS d
    WHERE d.customer_id = s.customer_id
      AND d.is_current
);


COMMIT;

