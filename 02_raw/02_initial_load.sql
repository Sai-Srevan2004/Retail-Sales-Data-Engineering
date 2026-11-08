USE DATABASE RETAIL_SUPPLY_CHAIN;
USE WAREHOUSE RETAIL_WH;


-- =========================================================
-- 1. INITIAL LOAD INTO RAW CUSTOMERS TABLE
-- =========================================================

COPY INTO RAW.CUSTOMERS
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
    _loaded_at,
    _batch_id,
    _row_number
)
FROM
(
    SELECT
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP(),
        'INITIAL',
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.RETAIL_SOURCE_STAGE
)
PATTERN = '.*customers_initial\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT'
FORCE=TRUE;



-- =========================================================
-- 2. INITIAL LOAD INTO RAW PRODUCTS TABLE
-- =========================================================

COPY INTO RAW.PRODUCTS
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
    _loaded_at,
    _batch_id,
    _row_number
)
FROM
(
    SELECT
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP(),
        'INITIAL',
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.RETAIL_SOURCE_STAGE
)
PATTERN = '.*products_initial\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT'
FORCE=TRUE;


-- =========================================================
-- 3. INITIAL LOAD INTO RAW STORES TABLE
-- =========================================================

COPY INTO RAW.STORES
(
    store_id,
    store_name,
    city,
    state,
    region,
    store_type,
    opened_date,
    _source_file,
    _loaded_at,
    _batch_id,
    _row_number
)
FROM
(
    SELECT
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP(),
        'INITIAL',
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.RETAIL_SOURCE_STAGE
)
PATTERN = '.*stores_initial\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT'
FORCE=TRUE;


-- =========================================================
-- 4. INITIAL LOAD INTO RAW SALES TABLE
-- =========================================================

COPY INTO RAW.SALES
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
    _loaded_at,
    _batch_id,
    _row_number
)
FROM
(
    SELECT
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8,
        $9,
        METADATA$FILENAME,
        CURRENT_TIMESTAMP(),
        'INITIAL',
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.RETAIL_SOURCE_STAGE
)
PATTERN = '.*sales_initial\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT'
FORCE=TRUE;