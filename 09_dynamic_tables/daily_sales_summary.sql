
--========================================================
-- 1. SETUP
--========================================================
USE DATABASE RETAIL_SUPPLY_CHAIN;
USE SCHEMA GOLD;


--========================================================
-- 2. CREATE DAILY SALES SUMMARY DYNAMIC TABLE
--========================================================

CREATE OR REPLACE DYNAMIC TABLE GOLD.DAILY_SALES_SUMMARY

    TARGET_LAG = '1 HOUR'
    WAREHOUSE = RETAIL_WH

AS

SELECT
    DATE_KEY,
    STORE_KEY,

    COUNT(DISTINCT SALE_ID) AS TOTAL_ORDERS,

    SUM(QUANTITY) AS TOTAL_UNITS_SOLD,

    SUM(GROSS_AMOUNT) AS TOTAL_GROSS_SALES,

    SUM(DISCOUNT_AMOUNT) AS TOTAL_DISCOUNTS,

    SUM(NET_AMOUNT) AS TOTAL_NET_SALES,

    AVG(NET_AMOUNT) AS AVG_ORDER_VALUE

FROM GOLD.FACT_SALES

GROUP BY
    DATE_KEY,
    STORE_KEY;


--========================================================
-- 3. VERIFY DYNAMIC TABLE
--========================================================

SELECT *
FROM GOLD.DAILY_SALES_SUMMARY
ORDER BY DATE_KEY, STORE_KEY;


--========================================================
-- 4. CHECK DYNAMIC TABLE DETAILS
--========================================================

SHOW DYNAMIC TABLES IN SCHEMA GOLD;
