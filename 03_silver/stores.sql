
USE DATABASE RETAIL_SUPPLY_CHAIN;
USE SCHEMA SILVER;


-- ============================================================
-- 1. CREATE SILVER STORES TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SILVER.STORES
(
    store_id        STRING NOT NULL,
    store_name      STRING,
    city            STRING,
    state           STRING,
    region          STRING,
    store_type      STRING,
    opened_date     DATE,
    _source_file    STRING,
    _batch_id       STRING,
    _loaded_at      TIMESTAMP_NTZ
);


-- ============================================================
-- 2. CLEAN AND VALIDATE RAW STORES
-- ============================================================

CREATE OR REPLACE TEMP TABLE STORE_VALIDATION AS

WITH CLEANED AS
(
    SELECT
        NULLIF(TRIM(R.store_id), '') AS store_id,

        NULLIF(TRIM(R.store_name), '') AS store_name,

        NULLIF(TRIM(R.city), '') AS city,

        UPPER(NULLIF(TRIM(R.state), '')) AS state,

        UPPER(NULLIF(TRIM(R.region), '')) AS region,

        UPPER(NULLIF(TRIM(R.store_type), '')) AS store_type,

        TRY_TO_DATE(
            NULLIF(TRIM(R.opened_date), '')
        ) AS opened_date,

        R._source_file,
        R._batch_id,
        R._loaded_at,
        R._row_number,

        OBJECT_CONSTRUCT_KEEP_NULL(
            'store_id', R.store_id,
            'store_name', R.store_name,
            'city', R.city,
            'state', R.state,
            'region', R.region,
            'store_type', R.store_type,
            'opened_date', R.opened_date
        ) AS raw_record

    FROM RAW.STORES R
)

SELECT
    *,

    CASE
        WHEN store_id IS NULL
            THEN 'MISSING_STORE_ID'

        WHEN store_name IS NULL
            THEN 'MISSING_STORE_NAME'

        WHEN opened_date IS NULL
            THEN 'INVALID_OPENED_DATE'

        ELSE NULL
    END AS rejection_reason

FROM CLEANED;


-- ============================================================
-- 3. INSERT INVALID RECORDS INTO REJECTION TABLE
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
    S._source_file,
    'STORE',
    S.store_id,
    S.rejection_reason,
    S.raw_record,
    S._batch_id,
    CURRENT_TIMESTAMP(),
    S._row_number

FROM STORE_VALIDATION S

WHERE S.rejection_reason IS NOT NULL

AND NOT EXISTS
(
    SELECT 1
    FROM SILVER.REJECTED_RECORDS R
    WHERE R.source_file = S._source_file
      AND R.entity_name = 'STORE'
      AND R.batch_id = S._batch_id
      AND R.source_row_number = S._row_number
);


-- ============================================================
-- 4. GLOBAL DEDUPLICATION
-- ============================================================

CREATE OR REPLACE TEMP TABLE STORE_DEDUPLICATED AS

SELECT
    *,

    ROW_NUMBER() OVER
    (
        PARTITION BY store_id
        ORDER BY
            _loaded_at DESC NULLS LAST,
            _source_file DESC,
            _row_number DESC
    ) AS rn

FROM STORE_VALIDATION

WHERE rejection_reason IS NULL;


-- ============================================================
-- 5. MERGE INTO SILVER STORES
-- ============================================================

MERGE INTO SILVER.STORES T

USING
(
    SELECT
        store_id,
        store_name,
        city,
        state,
        region,
        store_type,
        opened_date,
        _source_file,
        _batch_id,
        _loaded_at

    FROM STORE_DEDUPLICATED

    WHERE rn = 1

) S

ON T.store_id = S.store_id

WHEN MATCHED AND
(
    S._loaded_at > T._loaded_at
)

THEN UPDATE SET
    T.store_name = S.store_name,
    T.city = S.city,
    T.state = S.state,
    T.region = S.region,
    T.store_type = S.store_type,
    T.opened_date = S.opened_date,
    T._source_file = S._source_file,
    T._batch_id = S._batch_id,
    T._loaded_at = S._loaded_at

WHEN NOT MATCHED THEN INSERT
(
    store_id,
    store_name,
    city,
    state,
    region,
    store_type,
    opened_date,
    _source_file,
    _batch_id,
    _loaded_at
)

VALUES
(
    S.store_id,
    S.store_name,
    S.city,
    S.state,
    S.region,
    S.store_type,
    S.opened_date,
    S._source_file,
    S._batch_id,
    S._loaded_at
);


-- ============================================================
-- 6. VERIFY SILVER STORES
-- ============================================================

SELECT COUNT(*) AS TOTAL_STORES
FROM SILVER.STORES;


-- ============================================================
-- 7. CHECK REJECTED STORES
-- ============================================================

SELECT
    rejection_reason,
    COUNT(*) AS rejected_count

FROM SILVER.REJECTED_RECORDS

WHERE entity_name = 'STORE'

GROUP BY rejection_reason

ORDER BY rejected_count DESC;


-- ============================================================
-- 8. CHECK FOR DUPLICATE STORE IDs
-- ============================================================

SELECT
    store_id,
    COUNT(*) AS record_count

FROM SILVER.STORES

GROUP BY store_id

HAVING COUNT(*) > 1;
