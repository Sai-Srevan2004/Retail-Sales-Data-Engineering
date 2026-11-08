
--========================================================
-- 1. ROLE CREATION
--========================================================

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS DATA_ENGINEER;
CREATE ROLE IF NOT EXISTS DATA_ANALYST;


--========================================================
-- 2. WAREHOUSE ACCESS
--========================================================

GRANT USAGE ON WAREHOUSE RETAIL_WH
TO ROLE DATA_ENGINEER;

GRANT USAGE ON WAREHOUSE RETAIL_WH
TO ROLE DATA_ANALYST;


--========================================================
-- 3. DATABASE ACCESS
--========================================================

GRANT USAGE ON DATABASE RETAIL_SUPPLY_CHAIN
TO ROLE DATA_ENGINEER;

GRANT USAGE ON DATABASE RETAIL_SUPPLY_CHAIN
TO ROLE DATA_ANALYST;


--========================================================
-- 4. DATA ENGINEER - SCHEMA ACCESS
--========================================================

GRANT USAGE ON ALL SCHEMAS IN DATABASE RETAIL_SUPPLY_CHAIN
TO ROLE DATA_ENGINEER;

GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE RETAIL_SUPPLY_CHAIN
TO ROLE DATA_ENGINEER;


--========================================================
-- 5. DATA ENGINEER - EXISTING TABLE ACCESS
--========================================================

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.RAW
TO ROLE DATA_ENGINEER;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.SILVER
TO ROLE DATA_ENGINEER;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ENGINEER;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.CONTROL
TO ROLE DATA_ENGINEER;


--========================================================
-- 6. DATA ENGINEER - FUTURE TABLE ACCESS
--========================================================

GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.RAW
TO ROLE DATA_ENGINEER;

GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.SILVER
TO ROLE DATA_ENGINEER;

GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ENGINEER;

GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.CONTROL
TO ROLE DATA_ENGINEER;


--========================================================
-- 7. DATA ENGINEER - STORED PROCEDURE ACCESS
--========================================================

GRANT USAGE ON ALL PROCEDURES IN SCHEMA RETAIL_SUPPLY_CHAIN.SILVER
TO ROLE DATA_ENGINEER;

GRANT USAGE ON ALL PROCEDURES IN SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ENGINEER;


--========================================================
-- 8. DATA ANALYST - GOLD SCHEMA ACCESS
--========================================================

GRANT USAGE ON SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ANALYST;


--========================================================
-- 9. DATA ANALYST - EXISTING TABLE ACCESS
--========================================================

GRANT SELECT ON ALL TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ANALYST;


--========================================================
-- 10. DATA ANALYST - FUTURE TABLE ACCESS
--========================================================

GRANT SELECT ON FUTURE TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ANALYST;


--========================================================
-- 11. DATA ANALYST - EXISTING VIEW ACCESS
--========================================================

GRANT SELECT ON ALL VIEWS IN SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ANALYST;


--========================================================
-- 12. DATA ANALYST - FUTURE VIEW ACCESS
--========================================================

GRANT SELECT ON FUTURE VIEWS IN SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ANALYST;


--========================================================
-- 13. DATA ANALYST - EXISTING DYNAMIC TABLE ACCESS
--========================================================

GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ANALYST;


--========================================================
-- 14. DATA ANALYST - FUTURE DYNAMIC TABLE ACCESS
--========================================================

GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA RETAIL_SUPPLY_CHAIN.GOLD
TO ROLE DATA_ANALYST;


--========================================================
-- 15. USER ROLE ASSIGNMENT
--========================================================

SELECT CURRENT_USER();

GRANT ROLE DATA_ENGINEER TO USER <snowflake_username>;

GRANT ROLE DATA_ANALYST TO USER <snowflake_username>;
