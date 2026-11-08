USE DATABASE RETAIL_SUPPLY_CHAIN;

--=================================================================
--CREATION OF PROCEDURE: LOAD_SILVER_CUSTOMERS 
--=================================================================

CREATE OR REPLACE PROCEDURE SILVER.LOAD_SILVER_CUSTOMERS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    rows_processed NUMBER DEFAULT 0;

BEGIN

    -- Step 1: Create temporary table for incoming stream records
    CREATE OR REPLACE TEMPORARY TABLE CUSTOMER_BATCH
    LIKE RAW.CUSTOMERS;

    BEGIN TRANSACTION;

    -- Step 2: Capture new records from RAW stream
    INSERT INTO CUSTOMER_BATCH
    SELECT
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
    FROM RAW.CUSTOMERS_STREAM
    WHERE METADATA$ACTION = 'INSERT';


    -- Step 3: Validate incoming records
    CREATE OR REPLACE TEMPORARY TABLE CUSTOMER_VALIDATION AS
    SELECT
        NULLIF(TRIM(customer_id), '') AS customer_id,
        NULLIF(TRIM(customer_name), '') AS customer_name,
        LOWER(NULLIF(TRIM(email), '')) AS email,
        NULLIF(TRIM(phone), '') AS phone,
        UPPER(NULLIF(TRIM(region), '')) AS region,
        UPPER(NULLIF(TRIM(segment), '')) AS segment,
        TRY_TO_TIMESTAMP_NTZ(created_at) AS created_at,
        TRY_TO_TIMESTAMP_NTZ(updated_at) AS updated_at,

        _source_file,
        _loaded_at,
        _batch_id,
        _row_number,

        OBJECT_CONSTRUCT_KEEP_NULL(
            'customer_id', customer_id,
            'customer_name', customer_name,
            'email', email,
            'phone', phone,
            'region', region,
            'segment', segment,
            'created_at', created_at,
            'updated_at', updated_at
        ) AS raw_record,

        CASE
            WHEN NULLIF(TRIM(customer_id), '') IS NULL
                THEN 'MISSING_CUSTOMER_ID'

            WHEN NULLIF(TRIM(customer_name), '') IS NULL
                THEN 'MISSING_CUSTOMER_NAME'

            WHEN NULLIF(TRIM(email), '') IS NULL
                THEN 'MISSING_EMAIL'

            WHEN NOT REGEXP_LIKE(
                LOWER(TRIM(email)),
                '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$',
                'i'
            )
                THEN 'INVALID_EMAIL'

            WHEN TRY_TO_TIMESTAMP_NTZ(created_at) IS NULL
                THEN 'INVALID_CREATED_AT'

            WHEN TRY_TO_TIMESTAMP_NTZ(updated_at) IS NULL
                THEN 'INVALID_UPDATED_AT'

            WHEN TRY_TO_TIMESTAMP_NTZ(updated_at)
                 < TRY_TO_TIMESTAMP_NTZ(created_at)
                THEN 'UPDATED_AT_BEFORE_CREATED_AT'

            ELSE NULL
        END AS rejection_reason

    FROM CUSTOMER_BATCH;


    -- Step 4: Insert rejected records
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
    SELECT
        V._source_file,
        'CUSTOMERS',
        V.customer_id,
        V.rejection_reason,
        V.raw_record,
        V._batch_id,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        V._row_number

    FROM CUSTOMER_VALIDATION V

    WHERE V.rejection_reason IS NOT NULL

      AND NOT EXISTS
      (
          SELECT 1
          FROM SILVER.REJECTED_RECORDS R
          WHERE R.source_file = V._source_file
            AND R.entity_name = 'CUSTOMERS'
            AND R.batch_id = V._batch_id
            AND R.source_row_number = V._row_number
      );


    -- Step 5: Deduplicate valid incoming customers
    CREATE OR REPLACE TEMPORARY TABLE CUSTOMER_DEDUPLICATED AS
    SELECT *
    FROM CUSTOMER_VALIDATION
    WHERE rejection_reason IS NULL

    QUALIFY ROW_NUMBER() OVER
    (
        PARTITION BY customer_id
        ORDER BY
            updated_at DESC,
            _loaded_at DESC,
            _row_number DESC
    ) = 1;


    -- Step 6: Merge into Silver customers
    MERGE INTO SILVER.CUSTOMERS T

    USING CUSTOMER_DEDUPLICATED S

    ON T.customer_id = S.customer_id

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
        T.customer_name = S.customer_name,
        T.email = S.email,
        T.phone = S.phone,
        T.region = S.region,
        T.segment = S.segment,
        T.updated_at = S.updated_at,
        T._source_file = S._source_file,
        T._batch_id = S._batch_id,
        T._loaded_at = S._loaded_at

    WHEN NOT MATCHED THEN INSERT
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
        _batch_id,
        _loaded_at
    )

    VALUES
    (
        S.customer_id,
        S.customer_name,
        S.email,
        S.phone,
        S.region,
        S.segment,
        S.created_at,
        S.updated_at,
        S._source_file,
        S._batch_id,
        S._loaded_at
    );


    -- Step 7: Get number of incoming records
    SELECT COUNT(*)
    INTO :rows_processed
    FROM CUSTOMER_BATCH;


    COMMIT;

    RETURN 'Customer processing completed. Stream records captured: '
           || rows_processed;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;

END;
$$;