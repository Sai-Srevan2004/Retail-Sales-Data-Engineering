
USE DATABASE RETAIL_SUPPLY_CHAIN;

--=================================================================
-- CREATION OF PROCEDURE: LOAD_GOLD_DIM_PRODUCT
--=================================================================

CREATE OR REPLACE PROCEDURE GOLD.LOAD_GOLD_DIM_PRODUCT()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    rows_processed NUMBER DEFAULT 0;

BEGIN

    --=============================================================
    -- 1. CREATE TEMPORARY TABLE
    --=============================================================

    CREATE OR REPLACE TEMPORARY TABLE PRODUCT_BATCH
    LIKE SILVER.PRODUCTS;


    BEGIN TRANSACTION;


    --=============================================================
    -- 2. CAPTURE STREAM DATA
    --=============================================================

    INSERT INTO PRODUCT_BATCH
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

    FROM SILVER.PRODUCTS_STREAM

    WHERE METADATA$ACTION = 'INSERT';


    --=============================================================
    -- 3. UPDATE EXISTING PRODUCTS / INSERT NEW PRODUCTS
    --=============================================================
    -- SCD Type 1: Maintain only the latest product information.
    -- Inferred products are resolved without changing product_key.

    MERGE INTO GOLD.DIM_PRODUCT T

    USING (
        SELECT *
        FROM PRODUCT_BATCH

        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY product_id
            ORDER BY updated_at DESC, _loaded_at DESC
        ) = 1
    ) S

    ON T.product_id = S.product_id


    -- Resolve inferred products

    WHEN MATCHED AND T.is_inferred = TRUE

    THEN UPDATE SET
        T.product_name = S.product_name,
        T.category = S.category,
        T.brand = S.brand,
        T.unit_price = S.unit_price,
        T.created_at = S.created_at,
        T.updated_at = S.updated_at,
        T.is_active = S.is_active,
        T.is_inferred = FALSE,
        T._source_file = S._source_file,
        T._batch_id = S._batch_id,
        T._loaded_at = S._loaded_at


    -- Update existing products when incoming data is newer

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


    -- Insert new products

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
        is_inferred,
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
        FALSE,
        S._source_file,
        S._batch_id,
        S._loaded_at
    );


    --=============================================================
    -- 4. CAPTURE PROCESSED ROW COUNT
    --=============================================================

    SELECT COUNT(*)
    INTO :rows_processed
    FROM PRODUCT_BATCH;


    COMMIT;


    RETURN 'Gold product processing completed. Records captured: '
           || TO_VARCHAR(rows_processed);


EXCEPTION

    WHEN OTHER THEN
        ROLLBACK;
        RAISE;

END;
$$;
