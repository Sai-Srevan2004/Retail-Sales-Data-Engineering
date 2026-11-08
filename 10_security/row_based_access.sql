
--========================================================
-- 1. SETUP
--========================================================

USE ROLE ACCOUNTADMIN;

USE DATABASE RETAIL_SUPPLY_CHAIN;
USE SCHEMA CONTROL;


--========================================================
-- 2. CREATE ROW ACCESS POLICY
--========================================================

CREATE OR REPLACE ROW ACCESS POLICY CUSTOMER_REGION_POLICY
AS (REGION_VALUE STRING)
RETURNS BOOLEAN ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_ENGINEER')
            THEN TRUE

        WHEN CURRENT_ROLE() = 'DATA_ANALYST'
             AND UPPER(REGION_VALUE) = 'SOUTH'
            THEN TRUE

        ELSE FALSE
    END;


--========================================================
-- 3. APPLY POLICY TO CUSTOMER DIMENSION
--========================================================

ALTER TABLE RETAIL_SUPPLY_CHAIN.GOLD.DIM_CUSTOMER
ADD ROW ACCESS POLICY RETAIL_SUPPLY_CHAIN.CONTROL.CUSTOMER_REGION_POLICY
ON (REGION);


--========================================================
-- 4. TEST AS DATA ANALYST
--========================================================

USE ROLE DATA_ANALYST;

SELECT
    CUSTOMER_ID,
    CUSTOMER_NAME,
    REGION
FROM RETAIL_SUPPLY_CHAIN.GOLD.DIM_CUSTOMER;


--========================================================
-- 5. TEST AS DATA ENGINEER
--========================================================

USE ROLE DATA_ENGINEER;

SELECT
    CUSTOMER_ID,
    CUSTOMER_NAME,
    REGION
FROM RETAIL_SUPPLY_CHAIN.GOLD.DIM_CUSTOMER;


--========================================================
-- 6. VERIFY ROW ACCESS POLICY
--========================================================

USE ROLE ACCOUNTADMIN;

SELECT *
FROM TABLE(
    RETAIL_SUPPLY_CHAIN.INFORMATION_SCHEMA.POLICY_REFERENCES(
        REF_ENTITY_NAME => 'RETAIL_SUPPLY_CHAIN.GOLD.DIM_CUSTOMER',
        REF_ENTITY_DOMAIN => 'TABLE'
    )
);
