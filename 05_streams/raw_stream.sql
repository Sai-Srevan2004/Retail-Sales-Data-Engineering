USE DATABASE RETAIL_SUPPLY_CHAIN;

-- =========================================================
-- 1. RAW STREAMS
-- =========================================================

CREATE STREAM IF NOT EXISTS RAW.CUSTOMERS_STREAM
ON TABLE RAW.CUSTOMERS;

CREATE STREAM IF NOT EXISTS RAW.PRODUCTS_STREAM
ON TABLE RAW.PRODUCTS;

CREATE STREAM IF NOT EXISTS RAW.SALES_STREAM
ON TABLE RAW.SALES;

-- =========================================================
-- 2. VALIDATION
-- =========================================================

SHOW STREAMS IN SCHEMA RAW;
