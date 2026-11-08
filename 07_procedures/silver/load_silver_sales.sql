USE DATABASE RETAIL_SUPPLY_CHAIN;

--=================================================================
--CREATION OF PROCEDURE: LOAD_SILVER_SALES
--=================================================================

CREATE OR REPLACE PROCEDURE SILVER.LOAD_SILVER_SALES()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    rows_processed NUMBER DEFAULT 0;

BEGIN

    -- Step 1: Create temporary batch table before transaction
    CREATE OR REPLACE TEMPORARY TABLE SALES_BATCH
    LIKE RAW.SALES;

    BEGIN TRANSACTION;

    -- Step 2: Capture new records from RAW stream
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
        _loaded_at,
        _batch_id,
        _row_number
    FROM RAW.SALES_STREAM
    WHERE METADATA$ACTION = 'INSERT';


    -- Step 3: Insert invalid and duplicate sales into rejection table
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
            NULLIF(TRIM(sale_id), '') AS sale_id,
            TRY_TO_TIMESTAMP_NTZ(sale_timestamp) AS sale_timestamp,
            NULLIF(TRIM(customer_id), '') AS customer_id,
            NULLIF(TRIM(product_id), '') AS product_id,
            NULLIF(TRIM(store_id), '') AS store_id,
            TRY_TO_NUMBER(quantity) AS quantity,
            TRY_TO_NUMBER(unit_price, 12, 2) AS unit_price,
            TRY_TO_NUMBER(discount_amount, 12, 2) AS discount_amount,
            UPPER(NULLIF(TRIM(payment_method), '')) AS payment_method,

            _source_file,
            _loaded_at,
            _batch_id,
            _row_number,

            OBJECT_CONSTRUCT_KEEP_NULL(
                'sale_id', sale_id,
                'sale_timestamp', sale_timestamp,
                'customer_id', customer_id,
                'product_id', product_id,
                'store_id', store_id,
                'quantity', quantity,
                'unit_price', unit_price,
                'discount_amount', discount_amount,
                'payment_method', payment_method
            ) AS raw_record

        FROM SALES_BATCH
    ),

    VALIDATION AS
    (
        SELECT *,
            CASE
                WHEN sale_id IS NULL
                    THEN 'MISSING_SALE_ID'

                WHEN sale_timestamp IS NULL
                    THEN 'INVALID_SALE_TIMESTAMP'

                WHEN customer_id IS NULL
                    THEN 'MISSING_CUSTOMER_ID'

                WHEN product_id IS NULL
                    THEN 'MISSING_PRODUCT_ID'

                WHEN store_id IS NULL
                    THEN 'MISSING_STORE_ID'

                WHEN quantity IS NULL OR quantity <= 0
                    THEN 'INVALID_QUANTITY'

                WHEN unit_price IS NULL OR unit_price <= 0
                    THEN 'INVALID_UNIT_PRICE'

                WHEN discount_amount IS NULL OR discount_amount < 0
                    THEN 'INVALID_DISCOUNT_AMOUNT'

                WHEN discount_amount > quantity * unit_price
                    THEN 'DISCOUNT_EXCEEDS_GROSS_AMOUNT'

                WHEN payment_method NOT IN
                    ('CASH', 'CARD', 'UPI', 'WALLET','NET_BANKING')
                    OR payment_method IS NULL
                    THEN 'INVALID_PAYMENT_METHOD'

                ELSE NULL
            END AS rejection_reason

        FROM CLEANED
    ),

    VALID_RANKED AS
    (
        SELECT *,
            ROW_NUMBER() OVER
            (
                PARTITION BY sale_id
                ORDER BY
                    _loaded_at,
                    _source_file,
                    _row_number
            ) AS rn

        FROM VALIDATION
        WHERE rejection_reason IS NULL
    ),

    REJECTIONS AS
    (
        -- Invalid records
        SELECT
            _source_file,
            sale_id,
            rejection_reason,
            raw_record,
            _batch_id,
            _row_number

        FROM VALIDATION
        WHERE rejection_reason IS NOT NULL

        UNION ALL

        -- Duplicate IDs within the incoming batch
        SELECT
            _source_file,
            sale_id,
            'DUPLICATE_SALE_ID',
            raw_record,
            _batch_id,
            _row_number

        FROM VALID_RANKED
        WHERE rn > 1

        UNION ALL

        -- Sale IDs that already exist in Silver
        SELECT
            V._source_file,
            V.sale_id,
            'DUPLICATE_SALE_ID',
            V.raw_record,
            V._batch_id,
            V._row_number

        FROM VALID_RANKED V

        WHERE V.rn = 1

          AND EXISTS
          (
              SELECT 1
              FROM SILVER.SALES S
              WHERE S.sale_id = V.sale_id
          )
    )

    SELECT
        R._source_file,
        'SALES',
        R.sale_id,
        R.rejection_reason,
        R.raw_record,
        R._batch_id,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        R._row_number

    FROM REJECTIONS R

    WHERE NOT EXISTS
    (
        SELECT 1
        FROM SILVER.REJECTED_RECORDS X
        WHERE X.source_file = R._source_file
          AND X.entity_name = 'SALES'
          AND X.batch_id = R._batch_id
          AND X.source_row_number = R._row_number
    );


    -- Step 4: Insert valid, unique sales into Silver
    MERGE INTO SILVER.SALES T

    USING
    (
        WITH CLEANED AS
        (
            SELECT
                NULLIF(TRIM(sale_id), '') AS sale_id,
                TRY_TO_TIMESTAMP_NTZ(sale_timestamp) AS sale_timestamp,
                NULLIF(TRIM(customer_id), '') AS customer_id,
                NULLIF(TRIM(product_id), '') AS product_id,
                NULLIF(TRIM(store_id), '') AS store_id,
                TRY_TO_NUMBER(quantity) AS quantity,
                TRY_TO_NUMBER(unit_price, 12, 2) AS unit_price,
                TRY_TO_NUMBER(discount_amount, 12, 2) AS discount_amount,
                UPPER(NULLIF(TRIM(payment_method), '')) AS payment_method,
                _source_file,
                _loaded_at,
                _batch_id,
                _row_number

            FROM SALES_BATCH
        ),

        VALIDATION AS
        (
            SELECT *,
                CASE
                    WHEN sale_id IS NULL THEN 'INVALID'
                    WHEN sale_timestamp IS NULL THEN 'INVALID'
                    WHEN customer_id IS NULL THEN 'INVALID'
                    WHEN product_id IS NULL THEN 'INVALID'
                    WHEN store_id IS NULL THEN 'INVALID'
                    WHEN quantity IS NULL OR quantity <= 0 THEN 'INVALID'
                    WHEN unit_price IS NULL OR unit_price <= 0 THEN 'INVALID'
                    WHEN discount_amount IS NULL OR discount_amount < 0 THEN 'INVALID'
                    WHEN discount_amount > quantity * unit_price THEN 'INVALID'
                    WHEN payment_method NOT IN
                        ('CASH', 'CARD', 'UPI', 'WALLET','NET_BANKING')
                        OR payment_method IS NULL THEN 'INVALID'
                    ELSE NULL
                END AS rejection_reason

            FROM CLEANED
        ),

        DEDUPLICATED AS
        (
            SELECT *
            FROM VALIDATION
            WHERE rejection_reason IS NULL

            QUALIFY ROW_NUMBER() OVER
            (
                PARTITION BY sale_id
                ORDER BY
                    _loaded_at,
                    _source_file,
                    _row_number
            ) = 1
        )

        SELECT *
        FROM DEDUPLICATED

    ) S

    ON T.sale_id = S.sale_id

    WHEN NOT MATCHED THEN INSERT
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
        _batch_id,
        _loaded_at
    )

    VALUES
    (
        S.sale_id,
        S.sale_timestamp,
        S.customer_id,
        S.product_id,
        S.store_id,
        S.quantity,
        S.unit_price,
        S.discount_amount,
        S.payment_method,
        S._source_file,
        S._batch_id,
        S._loaded_at
    );


    -- Step 5: Capture processed count
    SELECT COUNT(*)
    INTO :rows_processed
    FROM SALES_BATCH;

    COMMIT;

    RETURN 'Sales processing completed. Stream records captured: '
           || TO_VARCHAR(rows_processed);

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;

END;
$$;