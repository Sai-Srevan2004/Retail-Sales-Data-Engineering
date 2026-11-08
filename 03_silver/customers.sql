
-- ============================================================
-- SILVER CUSTOMERS
-- Cleansing + Validation + Rejection + Deduplication + MERGE
-- ============================================================

USE DATABASE RETAIL_SUPPLY_CHAIN;
USE SCHEMA SILVER;

-- Change this value for each batch
--INITIAL/BATCH_01/BATCH_02

SET BATCH_ID = 'BATCH_01';  

-- ============================================================
-- 1. CREATE SILVER CUSTOMERS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SILVER.CUSTOMERS
(
    customer_id     STRING NOT NULL,
    customer_name   STRING,
    email           STRING,
    phone           STRING,
    region          STRING,
    segment         STRING,
    created_at      TIMESTAMP_NTZ,
    updated_at      TIMESTAMP_NTZ,
    _source_file    STRING,
    _batch_id       STRING,
    _loaded_at      TIMESTAMP_NTZ
);

-- ============================================================
-- 2. CLEAN AND VALIDATE RAW CUSTOMER RECORDS
-- ============================================================

CREATE OR REPLACE TEMP TABLE CUSTOMER_VALIDATION AS

WITH CLEANED AS
(
    SELECT
        NULLIF(TRIM(customer_id), '') AS customer_id,

        NULLIF(TRIM(customer_name), '') AS customer_name,

        LOWER(NULLIF(TRIM(email), '')) AS email,

        NULLIF(TRIM(phone), '') AS phone,

        UPPER(NULLIF(TRIM(region), '')) AS region,

        UPPER(NULLIF(TRIM(segment), '')) AS segment,

        TRY_TO_TIMESTAMP_NTZ(
            NULLIF(TRIM(created_at), '')
        ) AS created_at,

        TRY_TO_TIMESTAMP_NTZ(
            NULLIF(TRIM(updated_at), '')
        ) AS updated_at,

        _source_file,
        _batch_id,
        _loaded_at,
        _row_number,

        -- Preserve original RAW values
        OBJECT_CONSTRUCT_KEEP_NULL(
            'customer_id', customer_id,
            'customer_name', customer_name,
            'email', email,
            'phone', phone,
            'region', region,
            'segment', segment,
            'created_at', created_at,
            'updated_at', updated_at
        ) AS raw_record

    FROM RAW.CUSTOMERS

    WHERE _batch_id = $BATCH_ID
)

SELECT
    *,

    CASE
        WHEN customer_id IS NULL
            THEN 'MISSING_CUSTOMER_ID'

        WHEN customer_name IS NULL
            THEN 'MISSING_CUSTOMER_NAME'

        WHEN email IS NULL
            THEN 'MISSING_EMAIL'

        WHEN NOT REGEXP_LIKE(
            email,
            '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'
        )
            THEN 'INVALID_EMAIL'

        WHEN created_at IS NULL
            THEN 'INVALID_CREATED_AT'

        WHEN updated_at IS NULL
            THEN 'INVALID_UPDATED_AT'

        WHEN updated_at < created_at
            THEN 'UPDATED_AT_BEFORE_CREATED_AT'

        ELSE NULL
    END AS rejection_reason

FROM CLEANED;


-- ============================================================
-- 3. INSERT REJECTED CUSTOMER RECORDS
-- ============================================================

INSERT INTO SILVER.REJECTED_RECORDS
(
    source_file,
    entity_name,
    business_key,
    rejection_reason,
    raw_record,
    batch_id,
    rejected_at,
    source_row_number
)

SELECT
    V._source_file,
    'CUSTOMER',
    V.customer_id,
    V.rejection_reason,
    V.raw_record,
    V._batch_id,
    CURRENT_TIMESTAMP(),
    V._row_number

FROM CUSTOMER_VALIDATION V

WHERE V.rejection_reason IS NOT NULL

AND NOT EXISTS
(
    SELECT 1
    FROM SILVER.REJECTED_RECORDS R

    WHERE R.source_file = V._source_file
      AND R.entity_name = 'CUSTOMER'
      AND R.batch_id = V._batch_id
      AND R.source_row_number = V._row_number
);


-- ============================================================
-- 4. DEDUPLICATE AND MERGE VALID CUSTOMER RECORDS
-- ============================================================

MERGE INTO SILVER.CUSTOMERS T

USING
(
    SELECT
        customer_id,
        customer_name,
        email,
        phone,
        region,
        segment,
        created_at,
        updated_at,
        _source_file,
        _batch_id,
        _loaded_at

    FROM CUSTOMER_VALIDATION

    WHERE rejection_reason IS NULL

    QUALIFY ROW_NUMBER() OVER
    (
        PARTITION BY customer_id

        ORDER BY
            updated_at DESC,
            _loaded_at DESC,
            _row_number DESC
    ) = 1

) S

ON T.customer_id = S.customer_id

WHEN MATCHED AND
(
    S.updated_at > T.updated_at

    OR (
        S.updated_at = T.updated_at
        AND S._loaded_at > T._loaded_at
    )
)

THEN UPDATE SET

    T.customer_name = S.customer_name,
    T.email = S.email,
    T.phone = S.phone,
    T.region = S.region,
    T.segment = S.segment,
    T.updated_at = S.updated_at,
    T._source_file = S._source_file,
    T._batch_id = S._batch_id,
    T._loaded_at = S._loaded_at

WHEN NOT MATCHED THEN

INSERT
(
    customer_id,
    customer_name,
    email,
    phone,
    region,
    segment,
    created_at,
    updated_at,
    _source_file,
    _batch_id,
    _loaded_at
)

VALUES
(
    S.customer_id,
    S.customer_name,
    S.email,
    S.phone,
    S.region,
    S.segment,
    S.created_at,
    S.updated_at,
    S._source_file,
    S._batch_id,
    S._loaded_at
);


-- ==============================================================================================
-- 5. VALIDATION SUMMARY - CHECKING NO RECORDS LOADED INTO SILVER CUSTOMERS AND REJECTION TABLE
-- ==============================================================================================

SELECT
    'CUSTOMERS' AS entity_name,
    COUNT(*) AS total_customers
FROM SILVER.CUSTOMERS;

SELECT
    entity_name,
    rejection_reason,
    COUNT(*) AS rejected_count
FROM SILVER.REJECTED_RECORDS
WHERE entity_name = 'CUSTOMER'
  AND batch_id = $BATCH_ID
GROUP BY entity_name, rejection_reason
ORDER BY rejection_reason;
