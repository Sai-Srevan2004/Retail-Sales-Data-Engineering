
USE DATABASE RETAIL_SUPPLY_CHAIN;

-- =========================================================
-- 1. CREATE STORE DIMENSION
-- =========================================================

CREATE TABLE IF NOT EXISTS GOLD.DIM_STORE (
    store_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    store_id STRING NOT NULL,
    store_name STRING,
    city STRING,
    state STRING,
    region STRING,
    store_type STRING,
    opened_date DATE,
    is_inferred BOOLEAN NOT NULL DEFAULT FALSE,

    _source_file STRING,
    _batch_id STRING,
    _loaded_at TIMESTAMP_NTZ,

    CONSTRAINT PK_DIM_STORE PRIMARY KEY (store_key)
);


-- =========================================================
-- 2. UPDATE EXISTING STORES
-- =========================================================
-- SCD Type 1: Overwrite changed store information.
-- The existing store_key is preserved.

UPDATE GOLD.DIM_STORE T
SET
    store_name = S.store_name,
    city = S.city,
    state = S.state,
    region = S.region,
    store_type = S.store_type,
    opened_date = S.opened_date,

    is_inferred = FALSE,

    _source_file = S._source_file,
    _batch_id = S._batch_id,
    _loaded_at = S._loaded_at

FROM SILVER.STORES S

WHERE T.store_id = S.store_id
  AND (
      T.store_name IS DISTINCT FROM S.store_name
      OR T.city IS DISTINCT FROM S.city
      OR T.state IS DISTINCT FROM S.state
      OR T.region IS DISTINCT FROM S.region
      OR T.store_type IS DISTINCT FROM S.store_type
      OR T.opened_date IS DISTINCT FROM S.opened_date
      OR T.is_inferred = TRUE
  )
  AND (
      T._loaded_at IS NULL
      OR S._loaded_at >= T._loaded_at
  );


-- =========================================================
-- 3. INSERT NEW STORES
-- =========================================================

INSERT INTO GOLD.DIM_STORE (
    store_id,
    store_name,
    city,
    state,
    region,
    store_type,
    opened_date,
    is_inferred,
    _source_file,
    _batch_id,
    _loaded_at
)

SELECT
    S.store_id,
    S.store_name,
    S.city,
    S.state,
    S.region,
    S.store_type,
    S.opened_date,
    FALSE,
    S._source_file,
    S._batch_id,
    S._loaded_at

FROM SILVER.STORES S

WHERE NOT EXISTS (
    SELECT 1
    FROM GOLD.DIM_STORE T
    WHERE T.store_id = S.store_id
);


-- =========================================================
-- 4. VALIDATION
-- =========================================================

-- View store dimension
SELECT *
FROM GOLD.DIM_STORE
ORDER BY store_id;


-- Check duplicate store IDs
SELECT
    store_id,
    COUNT(*) AS record_count
FROM GOLD.DIM_STORE
GROUP BY store_id
HAVING COUNT(*) > 1;


-- Check unresolved inferred stores
SELECT *
FROM GOLD.DIM_STORE
WHERE is_inferred = TRUE;
