
USE DATABASE RETAIL_SUPPLY_CHAIN;

-- =========================================================
-- 1. CREATE DATE DIMENSION
-- =========================================================

CREATE TABLE IF NOT EXISTS GOLD.DIM_DATE (
    date_key NUMBER NOT NULL,
    full_date DATE NOT NULL,
    day NUMBER,
    month NUMBER,
    month_name STRING,
    quarter NUMBER,
    year NUMBER,
    week NUMBER,
    day_of_week NUMBER,
    day_name STRING,
    is_weekend BOOLEAN,

    CONSTRAINT PK_DIM_DATE PRIMARY KEY (date_key)
);


-- =========================================================
-- 2. GENERATE AND INSERT DATE RECORDS
-- =========================================================
-- Generates dates from 2025-01-01 through 2030-12-31.
-- Existing dates are not inserted again.

INSERT INTO GOLD.DIM_DATE (
    date_key,
    full_date,
    day,
    month,
    month_name,
    quarter,
    year,
    week,
    day_of_week,
    day_name,
    is_weekend
)

SELECT
    TO_NUMBER(TO_CHAR(D.full_date, 'YYYYMMDD')),
    D.full_date,
    DAY(D.full_date),
    MONTH(D.full_date),
    MONTHNAME(D.full_date),
    QUARTER(D.full_date),
    YEAR(D.full_date),
    WEEKOFYEAR(D.full_date),
    DAYOFWEEKISO(D.full_date),
    DAYNAME(D.full_date),
    DAYOFWEEKISO(D.full_date) IN (6, 7)

FROM (
    SELECT DATEADD(
        DAY,
        SEQ4(),
        '2025-01-01'::DATE
    ) AS full_date

    FROM TABLE(GENERATOR(ROWCOUNT => 2191))
) D

WHERE NOT EXISTS (
    SELECT 1
    FROM GOLD.DIM_DATE X
    WHERE X.date_key = TO_NUMBER(
        TO_CHAR(D.full_date, 'YYYYMMDD')
    )
);


-- =========================================================
-- 3. VALIDATION
-- =========================================================

-- Total dates
SELECT COUNT(*) AS total_dates
FROM GOLD.DIM_DATE;


-- Check date range
SELECT
    MIN(full_date) AS first_date,
    MAX(full_date) AS last_date
FROM GOLD.DIM_DATE;


-- Check duplicate date keys
SELECT
    date_key,
    COUNT(*) AS record_count
FROM GOLD.DIM_DATE
GROUP BY date_key
HAVING COUNT(*) > 1;


-- View sample records
SELECT *
FROM GOLD.DIM_DATE
ORDER BY full_date
LIMIT 10;
