
USE DATABASE RETAIL_SUPPLY_CHAIN;

-- =========================================================
-- 1. CREATE CUSTOMER DIMENSION
-- =========================================================

CREATE TABLE IF NOT EXISTS GOLD.DIM_CUSTOMER (
    customer_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    customer_id STRING NOT NULL,
    customer_name STRING,
    email STRING,
    phone STRING,
    region STRING,
    segment STRING,

    effective_start_date TIMESTAMP_NTZ NOT NULL,
    effective_end_date TIMESTAMP_NTZ NOT NULL,

    is_current BOOLEAN NOT NULL,
    is_inferred BOOLEAN NOT NULL DEFAULT FALSE,

    _source_file STRING,
    _batch_id STRING,
    _loaded_at TIMESTAMP_NTZ,

    CONSTRAINT PK_DIM_CUSTOMER PRIMARY KEY (customer_key)
);


BEGIN TRANSACTION;

-- =========================================================
-- 2. RESOLVE INFERRED CUSTOMER RECORDS
-- =========================================================
-- Update the existing inferred record instead of inserting a new one. Preserve the existing customer_key.

UPDATE GOLD.DIM_CUSTOMER T
SET
    customer_name = S.customer_name,
    email = S.email,
    phone = S.phone,
    region = S.region,
    segment = S.segment,

    effective_start_date = COALESCE(
        S.created_at,
        T.effective_start_date
    ),

    is_inferred = FALSE,

    _source_file = S._source_file,
    _batch_id = S._batch_id,
    _loaded_at = S._loaded_at

FROM SILVER.CUSTOMERS S

WHERE T.customer_id = S.customer_id
  AND T.is_current = TRUE
  AND T.is_inferred = TRUE;


-- =========================================================
-- 3. EXPIRE OLD CUSTOMER VERSIONS
-- =========================================================
-- If a tracked customer attribute changes, expire the existing version.

UPDATE GOLD.DIM_CUSTOMER T
SET
    effective_end_date = S.updated_at,
    is_current = FALSE

FROM SILVER.CUSTOMERS S

WHERE T.customer_id = S.customer_id
  AND T.is_current = TRUE
  AND T.is_inferred = FALSE

  AND (
      T.customer_name IS DISTINCT FROM S.customer_name
      OR T.email IS DISTINCT FROM S.email
      OR T.phone IS DISTINCT FROM S.phone
      OR T.region IS DISTINCT FROM S.region
      OR T.segment IS DISTINCT FROM S.segment
  )

  AND S.updated_at > T.effective_start_date;


-- =========================================================
-- 4. INSERT NEW CUSTOMER RECORDS / NEW VERSIONS
-- =========================================================
-- Inserts:
-- 1. Customers that do not exist in Gold.
-- 2. New versions of customers whose old versions expired.

INSERT INTO GOLD.DIM_CUSTOMER (
    customer_id,
    customer_name,
    email,
    phone,
    region,
    segment,
    effective_start_date,
    effective_end_date,
    is_current,
    is_inferred,
    _source_file,
    _batch_id,
    _loaded_at
)

SELECT
    S.customer_id,
    S.customer_name,
    S.email,
    S.phone,
    S.region,
    S.segment,

    CASE
        WHEN EXISTS (
            SELECT 1
            FROM GOLD.DIM_CUSTOMER H
            WHERE H.customer_id = S.customer_id
        )
        THEN S.updated_at
        ELSE COALESCE(S.created_at, S.updated_at)
    END,

    '9999-12-31 23:59:59'::TIMESTAMP_NTZ,

    TRUE,
    FALSE,

    S._source_file,
    S._batch_id,
    S._loaded_at

FROM SILVER.CUSTOMERS S

WHERE NOT EXISTS (
    SELECT 1
    FROM GOLD.DIM_CUSTOMER T
    WHERE T.customer_id = S.customer_id
      AND T.is_current = TRUE
);

COMMIT;


-- =========================================================
-- 5. VALIDATION
-- =========================================================

-- View customer history
SELECT *
FROM GOLD.DIM_CUSTOMER
ORDER BY customer_id, effective_start_date;


-- Check whether any customer has multiple current records
SELECT
    customer_id,
    COUNT_IF(is_current) AS current_rows
FROM GOLD.DIM_CUSTOMER
GROUP BY customer_id
HAVING COUNT_IF(is_current) > 1;


-- Check unresolved inferred customers
SELECT *
FROM GOLD.DIM_CUSTOMER
WHERE is_inferred = TRUE;
