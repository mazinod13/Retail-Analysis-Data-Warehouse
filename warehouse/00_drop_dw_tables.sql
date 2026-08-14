-- Teardown for the warehouse schema. Run before 01_create_dw_tables.sql to
-- rebuild from scratch.
--
-- The fact table is dropped first because it holds foreign keys into every
-- dimension. Dimensions can then go in any order.
--
-- Unlike the OLTP teardown, this one is cheap to run: everything in dw is
-- derived from the source tables and can be rebuilt by re-running the ETL.
-- Nothing here is a system of record.

DROP TABLE IF EXISTS dw.fact_sales    CASCADE;
DROP TABLE IF EXISTS dw.dim_customer  CASCADE;
DROP TABLE IF EXISTS dw.dim_product   CASCADE;
DROP TABLE IF EXISTS dw.dim_store     CASCADE;
DROP TABLE IF EXISTS dw.dim_employee  CASCADE;
DROP TABLE IF EXISTS dw.dim_date      CASCADE;
