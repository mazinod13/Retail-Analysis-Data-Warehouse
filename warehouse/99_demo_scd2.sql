-- ===========================================================================
-- SCD Type 2 demonstration
-- ===========================================================================
-- The generated customer data is static: nobody ever moves house or changes
-- their email. So dim_customer loads correctly but produces no history —
-- every row is a first version with valid_to NULL, and the versioning logic
-- in 06_load_dim_customer.sql never actually fires.
--
-- This script creates real change in the SOURCE system so the ETL has
-- something to detect. It is a demo/test artifact, not part of the pipeline
-- — hence the 99_ prefix, which keeps it out of the numbered run order.
--
-- HOW TO RUN THE DEMO
--   1. psql -f warehouse/99_demo_scd2.sql      (this file — mutates OLTP)
--   2. psql -f warehouse/06_load_dim_customer.sql
--   3. run the verification queries at the bottom of this file
--
-- The selection is deterministic (every 100th customer) so the demo is
-- reproducible. To undo, re-run etl/load_data.py --truncate, which restores
-- customers from the generated CSVs.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- Before: these customers each have exactly one row, currently valid.
-- ---------------------------------------------------------------------------
SELECT 'BEFORE' AS state, customer_id, city, state, email, valid_from, valid_to, is_current
FROM dw.dim_customer
WHERE customer_id IN (100, 200, 300)
ORDER BY customer_id, valid_from;


-- ---------------------------------------------------------------------------
-- Simulate real-world change in the source system.
--
-- Two kinds, so both a location move and a contact-detail change are
-- exercised:
--   * every 100th customer relocates to a different city and state
--   * every 250th customer changes email domain
--
-- Note these UPDATE public.customers — the OLTP tables. The warehouse is
-- not touched here; the whole point is that the ETL discovers the change
-- on its own by comparing source against dimension.
-- ---------------------------------------------------------------------------
UPDATE public.customers
SET city    = CASE WHEN city = 'Denver' THEN 'Seattle' ELSE 'Denver' END,
    state   = CASE WHEN city = 'Denver' THEN 'WA' ELSE 'CO' END,
    address = 'Relocated - ' || address
WHERE customer_id % 100 = 0;

UPDATE public.customers
SET email = split_part(email, '@', 1) || '@newdomain.example'
WHERE customer_id % 250 = 0;


