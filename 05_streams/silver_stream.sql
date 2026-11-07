USE DATABASE RETAIL_SUPPLY_CHAIN;

-- =========================================================
-- SILVER STREAMS
-- =========================================================

CREATE STREAM IF NOT EXISTS SILVER.CUSTOMERS_STREAM
ON TABLE SILVER.CUSTOMERS;

CREATE STREAM IF NOT EXISTS SILVER.PRODUCTS_STREAM
ON TABLE SILVER.PRODUCTS;

CREATE STREAM IF NOT EXISTS SILVER.SALES_STREAM
ON TABLE SILVER.SALES
APPEND_ONLY = TRUE;


-- =========================================================
-- VALIDATION
-- =========================================================
SHOW STREAMS IN SCHEMA SILVER;