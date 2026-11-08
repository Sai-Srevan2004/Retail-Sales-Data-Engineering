
USE DATABASE RETAIL_SUPPLY_CHAIN;

--=================================================================
-- CREATION OF PROCEDURE: LOAD_GOLD_DIM_CUSTOMER
--=================================================================

CREATE OR REPLACE PROCEDURE GOLD.LOAD_GOLD_DIM_CUSTOMER()
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

    CREATE OR REPLACE TEMPORARY TABLE CUSTOMER_BATCH
    LIKE SILVER.CUSTOMERS;


    BEGIN TRANSACTION;


    --=============================================================
    -- 2. CAPTURE STREAM DATA
    --=============================================================

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
        _batch_id,
        _loaded_at

    FROM SILVER.CUSTOMERS_STREAM

    WHERE METADATA$ACTION = 'INSERT';


    --=============================================================
    -- 3. RESOLVE INFERRED CUSTOMERS
    --=============================================================
    -- Preserve the existing customer_key.
    -- Update the inferred record instead of inserting a new one.

    UPDATE GOLD.DIM_CUSTOMER T

    SET
        customer_name = S.customer_name,
        email = S.email,
        phone = S.phone,
        region = S.region,
        segment = S.segment,

        effective_start_date = COALESCE(
            S.created_at,
            T.effective_start_date
        ),

        is_inferred = FALSE,

        _source_file = S._source_file,
        _batch_id = S._batch_id,
        _loaded_at = S._loaded_at

    FROM (
        SELECT *
        FROM CUSTOMER_BATCH

        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY updated_at DESC, _loaded_at DESC
        ) = 1
    ) S

    WHERE T.customer_id = S.customer_id
      AND T.is_current = TRUE
      AND T.is_inferred = TRUE;


    --=============================================================
    -- 4. EXPIRE OLD CUSTOMER VERSIONS
    --=============================================================
    -- Expire only when tracked customer attributes have changed.

    UPDATE GOLD.DIM_CUSTOMER T

    SET
        effective_end_date = S.updated_at,
        is_current = FALSE

    FROM (
        SELECT *
        FROM CUSTOMER_BATCH

        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY updated_at DESC, _loaded_at DESC
        ) = 1
    ) S

    WHERE T.customer_id = S.customer_id
      AND T.is_current = TRUE
      AND T.is_inferred = FALSE

      AND (
          T.customer_name IS DISTINCT FROM S.customer_name
          OR T.email IS DISTINCT FROM S.email
          OR T.phone IS DISTINCT FROM S.phone
          OR T.region IS DISTINCT FROM S.region
          OR T.segment IS DISTINCT FROM S.segment
      )

      AND S.updated_at > T.effective_start_date;


    --=============================================================
    -- 5. INSERT NEW CUSTOMERS / NEW SCD2 VERSIONS
    --=============================================================

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
        S.customer_name,
        S.email,
        S.phone,
        S.region,
        S.segment,

        CASE
            WHEN EXISTS (
                SELECT 1
                FROM GOLD.DIM_CUSTOMER H
                WHERE H.customer_id = S.customer_id
            )
            THEN S.updated_at

            ELSE COALESCE(S.created_at, S.updated_at)
        END,

        '9999-12-31 23:59:59'::TIMESTAMP_NTZ,

        TRUE,
        FALSE,

        S._source_file,
        S._batch_id,
        S._loaded_at

    FROM (
        SELECT *
        FROM CUSTOMER_BATCH

        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY updated_at DESC, _loaded_at DESC
        ) = 1
    ) S

    WHERE NOT EXISTS (
        SELECT 1
        FROM GOLD.DIM_CUSTOMER T
        WHERE T.customer_id = S.customer_id
          AND T.is_current = TRUE
    );


    --=============================================================
    -- 6. CAPTURE PROCESSED ROW COUNT
    --=============================================================

    SELECT COUNT(*)
    INTO :rows_processed
    FROM CUSTOMER_BATCH;


    COMMIT;


    RETURN 'Gold customer processing completed. Records captured: '
           || TO_VARCHAR(rows_processed);


EXCEPTION

    WHEN OTHER THEN
        ROLLBACK;
        RAISE;

END;
$$;
