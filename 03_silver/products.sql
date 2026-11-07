
USE DATABASE RETAIL_SUPPLY_CHAIN;
USE SCHEMA SILVER;


-- ============================================================
-- 1. CREATE SILVER PRODUCTS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SILVER.PRODUCTS
(
    product_id      STRING NOT NULL,
    product_name    STRING,
    category        STRING,
    brand           STRING,
    unit_price      NUMBER(12,2),
    created_at      TIMESTAMP_NTZ,
    updated_at      TIMESTAMP_NTZ,
    is_active       BOOLEAN,
    _source_file    STRING,
    _batch_id       STRING,
    _loaded_at      TIMESTAMP_NTZ
);


-- ============================================================
-- 2. CLEAN AND VALIDATE RAW PRODUCTS
-- ============================================================

CREATE OR REPLACE TEMP TABLE PRODUCT_VALIDATION AS

WITH CLEANED AS
(
    SELECT
        NULLIF(TRIM(R.product_id), '') AS product_id,
        NULLIF(TRIM(R.product_name), '') AS product_name,
        UPPER(NULLIF(TRIM(R.category), '')) AS category,
        UPPER(NULLIF(TRIM(R.brand), '')) AS brand,

        TRY_TO_NUMBER(
            NULLIF(TRIM(R.unit_price), ''), 12, 2
        ) AS unit_price,

        TRY_TO_TIMESTAMP_NTZ(
            NULLIF(TRIM(R.created_at), '')
        ) AS created_at,

        TRY_TO_TIMESTAMP_NTZ(
            NULLIF(TRIM(R.updated_at), '')
        ) AS updated_at,

        TRY_TO_BOOLEAN(
            NULLIF(TRIM(R.is_active), '')
        ) AS is_active,

        R._source_file,
        R._batch_id,
        R._loaded_at,
        R._row_number,

        OBJECT_CONSTRUCT_KEEP_NULL(
            'product_id', R.product_id,
            'product_name', R.product_name,
            'category', R.category,
            'brand', R.brand,
            'unit_price', R.unit_price,
            'created_at', R.created_at,
            'updated_at', R.updated_at,
            'is_active', R.is_active
        ) AS raw_record

    FROM RAW.PRODUCTS R
)

SELECT
    *,

    CASE
        WHEN product_id IS NULL
            THEN 'MISSING_PRODUCT_ID'

        WHEN product_name IS NULL
            THEN 'MISSING_PRODUCT_NAME'

        WHEN unit_price IS NULL OR unit_price <= 0
            THEN 'INVALID_UNIT_PRICE'

        WHEN created_at IS NULL
            THEN 'INVALID_CREATED_AT'

        WHEN updated_at IS NULL
            THEN 'INVALID_UPDATED_AT'

        WHEN updated_at < created_at
            THEN 'UPDATED_AT_BEFORE_CREATED_AT'

        WHEN is_active IS NULL
            THEN 'INVALID_IS_ACTIVE'

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
    P._source_file,
    'PRODUCT',
    P.product_id,
    P.rejection_reason,
    P.raw_record,
    P._batch_id,
    CURRENT_TIMESTAMP(),
    P._row_number

FROM PRODUCT_VALIDATION P

WHERE P.rejection_reason IS NOT NULL

AND NOT EXISTS
(
    SELECT 1
    FROM SILVER.REJECTED_RECORDS R
    WHERE R.source_file = P._source_file
      AND R.entity_name = 'PRODUCT'
      AND R.batch_id = P._batch_id
      AND R.source_row_number = P._row_number
);


-- ============================================================
-- 4. GLOBAL DEDUPLICATION
-- ============================================================

CREATE OR REPLACE TEMP TABLE PRODUCT_DEDUPLICATED AS

SELECT
    *,

    ROW_NUMBER() OVER
    (
        PARTITION BY product_id
        ORDER BY
            updated_at DESC,
            _loaded_at DESC,
            _source_file DESC,
            _row_number DESC
    ) AS rn

FROM PRODUCT_VALIDATION

WHERE rejection_reason IS NULL;


-- ============================================================
-- 5. MERGE INTO SILVER PRODUCTS
-- ============================================================

MERGE INTO SILVER.PRODUCTS T

USING
(
    SELECT
        product_id,
        product_name,
        category,
        brand,
        unit_price,
        created_at,
        updated_at,
        is_active,
        _source_file,
        _batch_id,
        _loaded_at

    FROM PRODUCT_DEDUPLICATED

    WHERE rn = 1

) S

ON T.product_id = S.product_id

WHEN MATCHED AND
(
    S.updated_at > T.updated_at

    OR
    (
        S.updated_at = T.updated_at
        AND S._loaded_at > T._loaded_at
    )
)

THEN UPDATE SET
    T.product_name = S.product_name,
    T.category = S.category,
    T.brand = S.brand,
    T.unit_price = S.unit_price,
    T.updated_at = S.updated_at,
    T.is_active = S.is_active,
    T._source_file = S._source_file,
    T._batch_id = S._batch_id,
    T._loaded_at = S._loaded_at

WHEN NOT MATCHED THEN INSERT
(
    product_id,
    product_name,
    category,
    brand,
    unit_price,
    created_at,
    updated_at,
    is_active,
    _source_file,
    _batch_id,
    _loaded_at
)

VALUES
(
    S.product_id,
    S.product_name,
    S.category,
    S.brand,
    S.unit_price,
    S.created_at,
    S.updated_at,
    S.is_active,
    S._source_file,
    S._batch_id,
    S._loaded_at
);


-- ============================================================
-- 6. VERIFY SILVER PRODUCTS
-- ============================================================

SELECT COUNT(*) AS TOTAL_PRODUCTS
FROM SILVER.PRODUCTS;


-- ============================================================
-- 7. CHECK REJECTED PRODUCTS
-- ============================================================

SELECT
    rejection_reason,
    COUNT(*) AS rejected_count

FROM SILVER.REJECTED_RECORDS

WHERE entity_name = 'PRODUCT'

GROUP BY rejection_reason

ORDER BY rejected_count DESC;


-- ============================================================
-- 8. CHECK FOR DUPLICATE PRODUCT IDs
-- ============================================================

SELECT
    product_id,
    COUNT(*) AS record_count

FROM SILVER.PRODUCTS

GROUP BY product_id

HAVING COUNT(*) > 1;
