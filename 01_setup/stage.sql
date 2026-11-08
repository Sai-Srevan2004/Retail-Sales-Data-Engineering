USE DATABASE RETAIL_SUPPLY_CHAIN;

--==================================================
-- 1. INTERNAL STAGE CREATION
--==================================================

CREATE STAGE IF NOT EXISTS RAW.RETAIL_SOURCE_STAGE
  FILE_FORMAT = RAW.RETAIL_CSV_FORMAT;

--==================================================
-- 2. VERIFYING STAGE
--==================================================

LIST @RAW.RETAIL_SOURCE_STAGE;
