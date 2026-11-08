USE DATABASE RETAIL_SUPPLY_CHAIN;
USE WAREHOUSE RETAIL_WH;

-- Upload:
--   customers_batch_02.csv
--   products_batch_02.csv
--   sales_batch_02.csv
-- under @RAW.RETAIL_SOURCE_STAGE/batch_02/ first.
USE DATABASE RETAIL_SUPPLY_CHAIN;
USE WAREHOUSE RETAIL_WH;


-- =========================================================
-- 1. LOAD CUSTOMERS RECORDS FROM BATCH 2
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
        'BATCH_02',
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.RETAIL_SOURCE_STAGE
)
PATTERN='.*customers_batch_02\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT'
FORCE=TRUE;



-- =========================================================
-- 2. LOAD SALES RECORDS FROM BATCH 2
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
        'BATCH_02',
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.RETAIL_SOURCE_STAGE
)
PATTERN='.*sales_batch_02\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT'
FORCE=TRUE;



-- =========================================================
-- 3. LOAD PRODUCTS RECORDS FROM BATCH 2
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
PATTERN = '.*products_batch_02\\.csv(\\.gz)?'
FILE_FORMAT = (FORMAT_NAME = 'RAW.RETAIL_CSV_FORMAT')
ON_ERROR = 'ABORT_STATEMENT';

