-- Teardown script — run this before 01_create_tables.sql to rebuild the schema
-- from scratch. Tables are dropped in reverse dependency order so foreign keys
-- never block a drop.
--
-- WARNING: this destroys all data. Only run it while iterating on the schema.

DROP TABLE IF EXISTS payments     CASCADE;
DROP TABLE IF EXISTS order_items  CASCADE;
DROP TABLE IF EXISTS inventory    CASCADE;
DROP TABLE IF EXISTS orders       CASCADE;
DROP TABLE IF EXISTS employees    CASCADE;
DROP TABLE IF EXISTS products     CASCADE;
DROP TABLE IF EXISTS customers    CASCADE;
DROP TABLE IF EXISTS stores       CASCADE;
DROP TABLE IF EXISTS categories   CASCADE;
