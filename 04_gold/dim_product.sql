
USE DATABASE RETAIL_SUPPLY_CHAIN;

-- =========================================================
-- 1. CREATE PRODUCT DIMENSION
-- =========================================================

CREATE TABLE IF NOT EXISTS GOLD.DIM_PRODUCT (
    product_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    product_id STRING NOT NULL,
    product_name STRING,
    category STRING,
    brand STRING,
    unit_price NUMBER(12,2),
    created_at TIMESTAMP_NTZ,
    updated_at TIMESTAMP_NTZ,
    is_active BOOLEAN,
    is_inferred BOOLEAN NOT NULL DEFAULT FALSE,

    _source_file STRING,
    _batch_id STRING,
    _loaded_at TIMESTAMP_NTZ,

    CONSTRAINT PK_DIM_PRODUCT PRIMARY KEY (product_key)
);


-- =========================================================
-- 2. RESOLVE INFERRED PRODUCT RECORDS
-- =========================================================
-- If a product was previously created as an inferred member,
-- update that existing row with actual product information.

UPDATE GOLD.DIM_PRODUCT T
SET
    product_name = S.product_name,
    category = S.category,
    brand = S.brand,
    unit_price = S.unit_price,
    created_at = S.created_at,
    updated_at = S.updated_at,
    is_active = S.is_active,
    is_inferred = FALSE,

    _source_file = S._source_file,
    _batch_id = S._batch_id,
    _loaded_at = S._loaded_at

FROM SILVER.PRODUCTS S

WHERE T.product_id = S.product_id
  AND T.is_inferred = TRUE;


-- =========================================================
-- 3. UPDATE EXISTING PRODUCTS
-- =========================================================
-- SCD Type 1: Overwrite existing product information.
-- The product_key remains unchanged.

UPDATE GOLD.DIM_PRODUCT T
SET
    product_name = S.product_name,
    category = S.category,
    brand = S.brand,
    unit_price = S.unit_price,
    updated_at = S.updated_at,
    is_active = S.is_active,

    _source_file = S._source_file,
    _batch_id = S._batch_id,
    _loaded_at = S._loaded_at

FROM SILVER.PRODUCTS S

WHERE T.product_id = S.product_id
  AND T.is_inferred = FALSE
  AND (
      T.product_name IS DISTINCT FROM S.product_name
      OR T.category IS DISTINCT FROM S.category
      OR T.brand IS DISTINCT FROM S.brand
      OR T.unit_price IS DISTINCT FROM S.unit_price
      OR T.updated_at IS DISTINCT FROM S.updated_at
      OR T.is_active IS DISTINCT FROM S.is_active
  )
  AND S.updated_at >= T.updated_at;


-- =========================================================
-- 4. INSERT NEW PRODUCTS
-- =========================================================

INSERT INTO GOLD.DIM_PRODUCT (
    product_id,
    product_name,
    category,
    brand,
    unit_price,
    created_at,
    updated_at,
    is_active,
    is_inferred,
    _source_file,
    _batch_id,
    _loaded_at
)

SELECT
    S.product_id,
    S.product_name,
    S.category,
    S.brand,
    S.unit_price,
    S.created_at,
    S.updated_at,
    S.is_active,
    FALSE,
    S._source_file,
    S._batch_id,
    S._loaded_at

FROM SILVER.PRODUCTS S

WHERE NOT EXISTS (
    SELECT 1
    FROM GOLD.DIM_PRODUCT T
    WHERE T.product_id = S.product_id
);


-- =========================================================
-- 5. VALIDATION
-- =========================================================

-- View product dimension
SELECT *
FROM GOLD.DIM_PRODUCT
ORDER BY product_id;


-- Check duplicate product IDs
SELECT
    product_id,
    COUNT(*) AS record_count
FROM GOLD.DIM_PRODUCT
GROUP BY product_id
HAVING COUNT(*) > 1;


-- Check unresolved inferred products
SELECT *
FROM GOLD.DIM_PRODUCT
WHERE is_inferred = TRUE;
