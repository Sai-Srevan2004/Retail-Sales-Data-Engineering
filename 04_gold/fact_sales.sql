
USE DATABASE RETAIL_SUPPLY_CHAIN;

-- =========================================================
-- 1. CREATE FACT SALES TABLE
-- =========================================================

CREATE TABLE IF NOT EXISTS GOLD.FACT_SALES (
    sale_key NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    sale_id STRING NOT NULL,

    date_key NUMBER NOT NULL,
    customer_key NUMBER NOT NULL,
    product_key NUMBER NOT NULL,
    store_key NUMBER NOT NULL,

    sale_timestamp TIMESTAMP_NTZ NOT NULL,

    quantity NUMBER NOT NULL,
    unit_price NUMBER(12,2) NOT NULL,

    discount NUMBER(12,2) NOT NULL,
    gross_amount NUMBER(14,2) NOT NULL,
    discount_amount NUMBER(14,2) NOT NULL,
    net_amount NUMBER(14,2) NOT NULL,

    payment_method STRING,

    _source_file STRING,
    _batch_id STRING,
    _loaded_at TIMESTAMP_NTZ,

    CONSTRAINT PK_FACT_SALES PRIMARY KEY (sale_key)
);


BEGIN TRANSACTION;


-- =========================================================
-- 2. CREATE INFERRED CUSTOMER MEMBERS
-- =========================================================
-- If a sale arrives before its customer exists in Gold, create an inferred customer dimension record.
-- The effective start date is the earliest sale timestamp for that customer.

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
    is_inferred
)

SELECT
    S.customer_id,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,

    MIN(S.sale_timestamp),

    '9999-12-31 23:59:59'::TIMESTAMP_NTZ,

    TRUE,
    TRUE

FROM SILVER.SALES S

WHERE NOT EXISTS (
    SELECT 1
    FROM GOLD.DIM_CUSTOMER C
    WHERE C.customer_id = S.customer_id
)

GROUP BY S.customer_id;


-- =========================================================
-- 3. LOAD SALES INTO FACT TABLE
-- =========================================================

INSERT INTO GOLD.FACT_SALES (
    sale_id,
    date_key,
    customer_key,
    product_key,
    store_key,
    sale_timestamp,
    quantity,
    unit_price,
    discount,
    gross_amount,
    discount_amount,
    net_amount,
    payment_method,
    _source_file,
    _batch_id,
    _loaded_at
)

SELECT
    S.sale_id,

    -- Date key in YYYYMMDD format
    TO_NUMBER(TO_CHAR(S.sale_timestamp::DATE, 'YYYYMMDD')),

    C.customer_key,
    P.product_key,
    ST.store_key,

    S.sale_timestamp,
    S.quantity,
    S.unit_price,

    -- Discount percentage
    CASE
        WHEN S.quantity * S.unit_price > 0
        THEN ROUND(
            (S.discount_amount / (S.quantity * S.unit_price)) * 100,
            2
        )
        ELSE 0
    END,

    -- Gross amount
    S.quantity * S.unit_price,

    -- Discount amount
    S.discount_amount,

    -- Net amount
    (S.quantity * S.unit_price) - S.discount_amount,

    S.payment_method,

    S._source_file,
    S._batch_id,
    S._loaded_at

FROM SILVER.SALES S

-- Historical SCD Type 2 customer lookup
JOIN GOLD.DIM_CUSTOMER C
    ON C.customer_id = S.customer_id
   AND C.effective_start_date <= S.sale_timestamp
   AND S.sale_timestamp < C.effective_end_date

-- Product lookup (SCD Type 1)
JOIN GOLD.DIM_PRODUCT P
    ON P.product_id = S.product_id

-- Store lookup
JOIN GOLD.DIM_STORE ST
    ON ST.store_id = S.store_id

-- Prevent duplicate fact records
WHERE NOT EXISTS (
    SELECT 1
    FROM GOLD.FACT_SALES F
    WHERE F.sale_id = S.sale_id
);


COMMIT;


-- =========================================================
-- 4. VALIDATION
-- =========================================================

-- Total sales records
SELECT COUNT(*) AS total_sales
FROM GOLD.FACT_SALES;


-- Check duplicate sale IDs
SELECT
    sale_id,
    COUNT(*) AS record_count
FROM GOLD.FACT_SALES
GROUP BY sale_id
HAVING COUNT(*) > 1;


-- Check sales amounts
SELECT
    SUM(gross_amount) AS total_gross_amount,
    SUM(discount_amount) AS total_discount_amount,
    SUM(net_amount) AS total_net_amount
FROM GOLD.FACT_SALES;


-- Check inferred customers
SELECT *
FROM GOLD.DIM_CUSTOMER
WHERE is_inferred = TRUE;
