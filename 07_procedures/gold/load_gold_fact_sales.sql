
USE DATABASE RETAIL_SUPPLY_CHAIN;

CREATE OR REPLACE PROCEDURE GOLD.LOAD_GOLD_FACT_SALES()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    rows_processed NUMBER DEFAULT 0;
    missing_dimensions NUMBER DEFAULT 0;

    missing_dimension_error EXCEPTION
        (-20001, 'Missing Gold dimension records for incoming sales.');

BEGIN

    -- Create temporary tables before transaction
    CREATE OR REPLACE TEMPORARY TABLE SALES_BATCH
    LIKE SILVER.SALES;

    CREATE OR REPLACE TEMPORARY TABLE SALES_DEDUPLICATED
    LIKE SILVER.SALES;


    BEGIN TRANSACTION;


    -- 1. Capture incoming sales
    INSERT INTO SALES_BATCH
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
    FROM SILVER.SALES_STREAM
    WHERE METADATA$ACTION = 'INSERT';


    -- 2. Deduplicate by sale_id
    INSERT INTO SALES_DEDUPLICATED
    SELECT *
    FROM SALES_BATCH
    QUALIFY ROW_NUMBER() OVER
    (
        PARTITION BY sale_id
        ORDER BY
            _loaded_at DESC,
            _source_file DESC
    ) = 1;


    -- 3. Create inferred customers
    INSERT INTO GOLD.DIM_CUSTOMER
    (
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
        'UNKNOWN',
        NULL,
        NULL,
        'UNKNOWN',
        'UNKNOWN',
        MIN(S.sale_timestamp),
        TO_TIMESTAMP_NTZ('9999-12-31 23:59:59'),
        TRUE,
        TRUE,
        'INFERRED',
        'INFERRED',
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
    FROM SALES_DEDUPLICATED S
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM GOLD.DIM_CUSTOMER C
        WHERE C.customer_id = S.customer_id
    )
    GROUP BY S.customer_id;


    -- 4. Create inferred products
    INSERT INTO GOLD.DIM_PRODUCT
    (
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
        'UNKNOWN',
        'UNKNOWN',
        'UNKNOWN',
        NULL,
        NULL,
        NULL,
        NULL,
        TRUE,
        'INFERRED',
        'INFERRED',
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
    FROM SALES_DEDUPLICATED S
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM GOLD.DIM_PRODUCT P
        WHERE P.product_id = S.product_id
    )
    GROUP BY S.product_id;


    -- 5. Create inferred stores
    INSERT INTO GOLD.DIM_STORE
    (
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
        'UNKNOWN',
        'UNKNOWN',
        'UNKNOWN',
        'UNKNOWN',
        'UNKNOWN',
        NULL,
        TRUE,
        'INFERRED',
        'INFERRED',
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
    FROM SALES_DEDUPLICATED S
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM GOLD.DIM_STORE ST
        WHERE ST.store_id = S.store_id
    )
    GROUP BY S.store_id;


    -- 6. Validate all dimension lookups
    SELECT COUNT(*)
    INTO :missing_dimensions
    FROM SALES_DEDUPLICATED S

    LEFT JOIN GOLD.DIM_DATE D
        ON D.full_date = TO_DATE(S.sale_timestamp)

    LEFT JOIN GOLD.DIM_CUSTOMER C
        ON C.customer_id = S.customer_id
       AND S.sale_timestamp >= C.effective_start_date
       AND S.sale_timestamp < C.effective_end_date

    LEFT JOIN GOLD.DIM_PRODUCT P
        ON P.product_id = S.product_id

    LEFT JOIN GOLD.DIM_STORE ST
        ON ST.store_id = S.store_id

    WHERE D.date_key IS NULL
       OR C.customer_key IS NULL
       OR P.product_key IS NULL
       OR ST.store_key IS NULL;


    -- Stop processing if any dimension lookup is missing
    IF (missing_dimensions > 0) THEN
        RAISE missing_dimension_error;
    END IF;


    -- 7. Insert sales into FACT_SALES
    INSERT INTO GOLD.FACT_SALES
    (
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
        D.date_key,
        C.customer_key,
        P.product_key,
        ST.store_key,
        S.sale_timestamp,
        S.quantity,
        S.unit_price,

        ROUND(
            (S.discount_amount /
             NULLIF(S.quantity * S.unit_price, 0)) * 100,
            2
        ),

        ROUND(S.quantity * S.unit_price, 2),
        S.discount_amount,

        ROUND(
            (S.quantity * S.unit_price) - S.discount_amount,
            2
        ),

        S.payment_method,
        S._source_file,
        S._batch_id,
        S._loaded_at

    FROM SALES_DEDUPLICATED S

    INNER JOIN GOLD.DIM_DATE D
        ON D.full_date = TO_DATE(S.sale_timestamp)

    INNER JOIN GOLD.DIM_CUSTOMER C
        ON C.customer_id = S.customer_id
       AND S.sale_timestamp >= C.effective_start_date
       AND S.sale_timestamp < C.effective_end_date

    INNER JOIN GOLD.DIM_PRODUCT P
        ON P.product_id = S.product_id

    INNER JOIN GOLD.DIM_STORE ST
        ON ST.store_id = S.store_id

    WHERE NOT EXISTS
    (
        SELECT 1
        FROM GOLD.FACT_SALES F
        WHERE F.sale_id = S.sale_id
    );


    SELECT COUNT(*)
    INTO :rows_processed
    FROM SALES_DEDUPLICATED;


    COMMIT;

    RETURN 'Gold fact sales processing completed. Records captured: '
           || TO_VARCHAR(rows_processed);


EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;

END;
$$;
