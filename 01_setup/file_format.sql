USE DATABASE RETAIL_SUPPLY_CHAIN;

--==================================================
-- 1. FILE FORMAT CREATION
--==================================================

CREATE FILE FORMAT IF NOT EXISTS RAW.RETAIL_CSV_FORMAT
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TRIM_SPACE = FALSE
  NULL_IF = ('NULL', 'null','');

DESCRIBE FILE FORMAT RAW.RETAIL_CSV_FORMAT;
