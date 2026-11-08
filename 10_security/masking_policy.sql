
--========================================================
-- 1. SETUP
--========================================================

USE ROLE ACCOUNTADMIN;

USE DATABASE RETAIL_SUPPLY_CHAIN;
USE SCHEMA CONTROL;


--========================================================
-- 2. CREATE EMAIL MASKING POLICY
--========================================================

CREATE OR REPLACE MASKING POLICY MASK_CUSTOMER_EMAIL
AS (EMAIL_VALUE STRING)
RETURNS STRING ->
    CASE
        WHEN EMAIL_VALUE IS NULL THEN NULL

        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_ENGINEER')
            THEN EMAIL_VALUE

        ELSE '***MASKED***'
    END;


--========================================================
-- 3. CREATE PHONE MASKING POLICY
--========================================================

CREATE OR REPLACE MASKING POLICY MASK_CUSTOMER_PHONE
AS (PHONE_VALUE STRING)
RETURNS STRING ->
    CASE
        WHEN PHONE_VALUE IS NULL THEN NULL

        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_ENGINEER')
            THEN PHONE_VALUE

        ELSE '***MASKED***'
    END;


--========================================================
-- 4. APPLY EMAIL MASKING POLICY
--========================================================

ALTER TABLE RETAIL_SUPPLY_CHAIN.GOLD.DIM_CUSTOMER
MODIFY COLUMN EMAIL
SET MASKING POLICY RETAIL_SUPPLY_CHAIN.CONTROL.MASK_CUSTOMER_EMAIL;


--========================================================
-- 5. APPLY PHONE MASKING POLICY
--========================================================

ALTER TABLE RETAIL_SUPPLY_CHAIN.GOLD.DIM_CUSTOMER
MODIFY COLUMN PHONE
SET MASKING POLICY RETAIL_SUPPLY_CHAIN.CONTROL.MASK_CUSTOMER_PHONE;


--========================================================
-- 6. TEST AS DATA ANALYST
--========================================================

USE ROLE DATA_ANALYST;

SELECT
    CUSTOMER_ID,
    CUSTOMER_NAME,
    EMAIL,
    PHONE
FROM RETAIL_SUPPLY_CHAIN.GOLD.DIM_CUSTOMER
LIMIT 10;


--========================================================
-- 7. TEST AS DATA ENGINEER
--========================================================

USE ROLE DATA_ENGINEER;

SELECT
    CUSTOMER_ID,
    CUSTOMER_NAME,
    EMAIL,
    PHONE
FROM RETAIL_SUPPLY_CHAIN.GOLD.DIM_CUSTOMER
LIMIT 10;


--========================================================
-- 8. VERIFY MASKING POLICIES
--========================================================

USE ROLE ACCOUNTADMIN;

SELECT *
FROM TABLE(
    RETAIL_SUPPLY_CHAIN.INFORMATION_SCHEMA.POLICY_REFERENCES(
        REF_ENTITY_NAME => 'RETAIL_SUPPLY_CHAIN.GOLD.DIM_CUSTOMER',
        REF_ENTITY_DOMAIN => 'TABLE'
    )
);
