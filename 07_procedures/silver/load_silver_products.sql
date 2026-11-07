USE DATABASE RETAIL_SUPPLY_CHAIN;

CREATE OR REPLACE PROCEDURE SILVER.LOAD_SILVER_PRODUCTS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    rows_processed NUMBER DEFAULT 0;

BEGIN

    -- Step 1: Create temporary batch table before transaction
    CREATE OR REPLACE TEMPORARY TABLE PRODUCT_BATCH
    LIKE RAW.PRODUCTS;

    BEGIN TRANSACTION;

    -- Step 2: Capture new records from RAW stream
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
        _loaded_at,
        _batch_id,
        _row_number
    FROM RAW.PRODUCTS_STREAM
    WHERE METADATA$ACTION = 'INSERT';


    -- Step 3: Insert rejected records
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

    WITH CLEANED AS
    (
        SELECT
            NULLIF(TRIM(product_id), '') AS product_id,
            NULLIF(TRIM(product_name), '') AS product_name,
            NULLIF(TRIM(category), '') AS category,
            NULLIF(TRIM(brand), '') AS brand,
            TRY_TO_NUMBER(unit_price, 12, 2) AS unit_price,
            TRY_TO_TIMESTAMP_NTZ(created_at) AS created_at,
            TRY_TO_TIMESTAMP_NTZ(updated_at) AS updated_at,
            TRY_TO_BOOLEAN(is_active) AS is_active,

            _source_file,
            _loaded_at,
            _batch_id,
            _row_number,

            OBJECT_CONSTRUCT_KEEP_NULL(
                'product_id', product_id,
                'product_name', product_name,
                'category', category,
                'brand', brand,
                'unit_price', unit_price,
                'created_at', created_at,
                'updated_at', updated_at,
                'is_active', is_active
            ) AS raw_record

        FROM PRODUCT_BATCH
    ),

    VALIDATION AS
    (
        SELECT *,
            CASE
                WHEN product_id IS NULL
                    THEN 'MISSING_PRODUCT_ID'

                WHEN product_name IS NULL
                    THEN 'MISSING_PRODUCT_NAME'

                WHEN unit_price IS NULL OR unit_price <= 0
                    THEN 'INVALID_UNIT_PRICE'

                WHEN created_at IS NULL
                    THEN 'INVALID_CREATED_AT'

                WHEN updated_at IS NULL
                    THEN 'INVALID_UPDATED_AT'

                WHEN updated_at < created_at
                    THEN 'UPDATED_AT_BEFORE_CREATED_AT'

                WHEN is_active IS NULL
                    THEN 'INVALID_IS_ACTIVE'

                ELSE NULL
            END AS rejection_reason

        FROM CLEANED
    )

    SELECT
        V._source_file,
        'PRODUCTS',
        V.product_id,
        V.rejection_reason,
        V.raw_record,
        V._batch_id,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        V._row_number

    FROM VALIDATION V

    WHERE V.rejection_reason IS NOT NULL

      AND NOT EXISTS
      (
          SELECT 1
          FROM SILVER.REJECTED_RECORDS R
          WHERE R.source_file = V._source_file
            AND R.entity_name = 'PRODUCTS'
            AND R.batch_id = V._batch_id
            AND R.source_row_number = V._row_number
      );


    -- Step 4: Deduplicate and MERGE valid products
    MERGE INTO SILVER.PRODUCTS T

    USING
    (
        WITH CLEANED AS
        (
            SELECT
                NULLIF(TRIM(product_id), '') AS product_id,
                NULLIF(TRIM(product_name), '') AS product_name,
                NULLIF(TRIM(category), '') AS category,
                NULLIF(TRIM(brand), '') AS brand,
                TRY_TO_NUMBER(unit_price, 12, 2) AS unit_price,
                TRY_TO_TIMESTAMP_NTZ(created_at) AS created_at,
                TRY_TO_TIMESTAMP_NTZ(updated_at) AS updated_at,
                TRY_TO_BOOLEAN(is_active) AS is_active,
                _source_file,
                _loaded_at,
                _batch_id,
                _row_number

            FROM PRODUCT_BATCH
        ),

        VALIDATION AS
        (
            SELECT *,
                CASE
                    WHEN product_id IS NULL THEN 'INVALID'
                    WHEN product_name IS NULL THEN 'INVALID'
                    WHEN unit_price IS NULL OR unit_price <= 0 THEN 'INVALID'
                    WHEN created_at IS NULL THEN 'INVALID'
                    WHEN updated_at IS NULL THEN 'INVALID'
                    WHEN updated_at < created_at THEN 'INVALID'
                    WHEN is_active IS NULL THEN 'INVALID'
                    ELSE NULL
                END AS rejection_reason

            FROM CLEANED
        )

        SELECT *
        FROM VALIDATION
        WHERE rejection_reason IS NULL

        QUALIFY ROW_NUMBER() OVER
        (
            PARTITION BY product_id
            ORDER BY
                updated_at DESC,
                _loaded_at DESC,
                _source_file DESC,
                _row_number DESC
        ) = 1

    ) S

    ON T.product_id = S.product_id

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
        S._source_file,
        S._batch_id,
        S._loaded_at
    );


    -- Step 5: Capture processed count
    SELECT COUNT(*)
    INTO :rows_processed
    FROM PRODUCT_BATCH;

    COMMIT;

    RETURN 'Product processing completed. Stream records captured: '
           || TO_VARCHAR(rows_processed);

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;

END;
$$;