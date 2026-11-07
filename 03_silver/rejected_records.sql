
USE DATABASE RETAIL_SUPPLY_CHAIN;
USE SCHEMA SILVER;

CREATE TABLE IF NOT EXISTS SILVER.REJECTED_RECORDS
(
    rejection_id       NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    source_file        STRING,
    entity_name        STRING,
    business_key       STRING,
    rejection_reason   STRING,
    raw_record         VARIANT,
    batch_id           STRING,
    rejected_at        TIMESTAMP_NTZ,
    source_row_number  NUMBER
);
