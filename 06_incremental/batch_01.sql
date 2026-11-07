USE DATABASE RETAIL_SUPPLY_CHAIN;
USE WAREHOUSE RETAIL_WH;


-- =========================================================
-- CUSTOMERS
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
        'BATCH_01',
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.RETAIL_SOURCE_STAGE
)
PATTERN='.*customers_batch_01\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT';



-- =========================================================
-- SALES
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
        'BATCH_01',
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.RETAIL_SOURCE_STAGE
)
PATTERN='.*sales_batch_01\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT';


-- =========================================================
-- PRODUCTS
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
        'BATCH_01',
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.RETAIL_SOURCE_STAGE
)
PATTERN = '.*products_batch_01\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT';


