
USE DATABASE RETAIL_SUPPLY_CHAIN;
USE SCHEMA SILVER;


-- ============================================================
-- 1. CREATE SILVER SALES TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS SILVER.SALES
(
    sale_id           STRING NOT NULL,
    sale_timestamp    TIMESTAMP_NTZ,
    customer_id       STRING,
    product_id        STRING,
    store_id          STRING,
    quantity          NUMBER,
    unit_price        NUMBER(12,2),
    discount_amount   NUMBER(12,2),
    payment_method    STRING,
    _source_file      STRING,
    _batch_id         STRING,
    _loaded_at        TIMESTAMP_NTZ
);


-- ============================================================
-- 2. CLEAN AND VALIDATE RAW SALES
-- ============================================================

CREATE OR REPLACE TEMP TABLE SALES_VALIDATION AS

WITH CLEANED AS
(
    SELECT
        NULLIF(TRIM(R.sale_id), '') AS sale_id,

        TRY_TO_TIMESTAMP_NTZ(
            NULLIF(TRIM(R.sale_timestamp), '')
        ) AS sale_timestamp,

        NULLIF(TRIM(R.customer_id), '') AS customer_id,
        NULLIF(TRIM(R.product_id), '') AS product_id,
        NULLIF(TRIM(R.store_id), '') AS store_id,

        TRY_TO_NUMBER(
            NULLIF(TRIM(R.quantity), '')
        ) AS quantity,

        TRY_TO_NUMBER(
            NULLIF(TRIM(R.unit_price), ''),
            12,
            2
        ) AS unit_price,

        TRY_TO_NUMBER(
            NULLIF(TRIM(R.discount_amount), ''),
            12,
            2
        ) AS discount_amount,

        UPPER(NULLIF(TRIM(R.payment_method), '')) AS payment_method,

        R._source_file,
        R._batch_id,
        R._loaded_at,
        R._row_number,

        OBJECT_CONSTRUCT_KEEP_NULL(
            'sale_id', R.sale_id,
            'sale_timestamp', R.sale_timestamp,
            'customer_id', R.customer_id,
            'product_id', R.product_id,
            'store_id', R.store_id,
            'quantity', R.quantity,
            'unit_price', R.unit_price,
            'discount_amount', R.discount_amount,
            'payment_method', R.payment_method
        ) AS raw_record

    FROM RAW.SALES R
)

SELECT
    *,

    CASE
        WHEN sale_id IS NULL
            THEN 'MISSING_SALE_ID'

        WHEN sale_timestamp IS NULL
            THEN 'INVALID_SALE_TIMESTAMP'

        WHEN customer_id IS NULL
            THEN 'MISSING_CUSTOMER_ID'

        WHEN product_id IS NULL
            THEN 'MISSING_PRODUCT_ID'

        WHEN store_id IS NULL
            THEN 'MISSING_STORE_ID'

        WHEN quantity IS NULL OR quantity <= 0
            THEN 'INVALID_QUANTITY'

        WHEN unit_price IS NULL OR unit_price <= 0
            THEN 'INVALID_UNIT_PRICE'

        WHEN discount_amount IS NULL OR discount_amount < 0
            THEN 'INVALID_DISCOUNT'

        WHEN discount_amount > quantity * unit_price
            THEN 'DISCOUNT_EXCEEDS_GROSS_AMOUNT'

        WHEN payment_method IS NULL
             OR payment_method NOT IN ('CASH', 'CARD', 'UPI', 'WALLET','NET_BANKING')
            THEN 'INVALID_PAYMENT_METHOD'

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
    'SALE',
    S.sale_id,
    S.rejection_reason,
    S.raw_record,
    S._batch_id,
    CURRENT_TIMESTAMP(),
    S._row_number

FROM SALES_VALIDATION S

WHERE S.rejection_reason IS NOT NULL

AND NOT EXISTS
(
    SELECT 1
    FROM SILVER.REJECTED_RECORDS R
    WHERE R.source_file = S._source_file
      AND R.entity_name = 'SALE'
      AND R.batch_id = S._batch_id
      AND R.source_row_number = S._row_number
);


-- ============================================================
-- 4. GLOBAL DEDUPLICATION
-- ============================================================

CREATE OR REPLACE TEMP TABLE SALES_DEDUPLICATED AS

SELECT
    *,

    ROW_NUMBER() OVER
    (
        PARTITION BY sale_id
        ORDER BY
            _loaded_at DESC NULLS LAST,
            _source_file DESC,
            _row_number DESC
    ) AS rn

FROM SALES_VALIDATION

WHERE rejection_reason IS NULL;


-- ============================================================
-- 5. INSERT DUPLICATE SALES INTO REJECTION TABLE
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
    'SALE',
    S.sale_id,
    'DUPLICATE_SALE_ID',
    S.raw_record,
    S._batch_id,
    CURRENT_TIMESTAMP(),
    S._row_number

FROM SALES_DEDUPLICATED S

WHERE S.rn > 1

AND NOT EXISTS
(
    SELECT 1
    FROM SILVER.REJECTED_RECORDS R
    WHERE R.source_file = S._source_file
      AND R.entity_name = 'SALE'
      AND R.batch_id = S._batch_id
      AND R.source_row_number = S._row_number
);


-- ============================================================
-- 6. MERGE VALID SALES INTO SILVER
-- ============================================================

MERGE INTO SILVER.SALES T

USING
(
    SELECT
        sale_id,
        sale_timestamp,
        customer_id,
        product_id,
        store_id,
        quantity,
        unit_price,
        discount_amount,
        payment_method,
        _source_file,
        _batch_id,
        _loaded_at

    FROM SALES_DEDUPLICATED

    WHERE rn = 1

) S

ON T.sale_id = S.sale_id

WHEN NOT MATCHED THEN

INSERT
(
    sale_id,
    sale_timestamp,
    customer_id,
    product_id,
    store_id,
    quantity,
    unit_price,
    discount_amount,
    payment_method,
    _source_file,
    _batch_id,
    _loaded_at
)

VALUES
(
    S.sale_id,
    S.sale_timestamp,
    S.customer_id,
    S.product_id,
    S.store_id,
    S.quantity,
    S.unit_price,
    S.discount_amount,
    S.payment_method,
    S._source_file,
    S._batch_id,
    S._loaded_at
);


-- ============================================================
-- 7. VERIFY SILVER SALES
-- ============================================================

SELECT COUNT(*) AS TOTAL_SILVER_SALES
FROM SILVER.SALES;


-- ============================================================
-- 8. CHECK REJECTED SALES
-- ============================================================

SELECT
    rejection_reason,
    COUNT(*) AS rejected_count

FROM SILVER.REJECTED_RECORDS

WHERE entity_name = 'SALE'

GROUP BY rejection_reason

ORDER BY rejected_count DESC;


-- ============================================================
-- 9. CHECK FOR DUPLICATE SALE IDs
-- ============================================================

SELECT
    sale_id,
    COUNT(*) AS record_count

FROM SILVER.SALES

GROUP BY sale_id

HAVING COUNT(*) > 1;
