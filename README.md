# Retail Sales Data Engineering Pipeline using Snowflake

## Overview

This project implements an end-to-end retail sales data pipeline using Snowflake and SQL. It processes customer, product, store, and sales data through RAW, SILVER, and GOLD layers, covering data ingestion, transformation, validation, dimensional modeling, and incremental processing.

CSV files are uploaded to a Snowflake internal stage and loaded into RAW tables using `COPY INTO`. The data is then cleaned and validated in the Silver layer before being transformed into analytical tables in Gold.

The pipeline also demonstrates incremental data processing using Snowflake Streams, Tasks, and Stored Procedures, along with customer history tracking through SCD Type 2 and product updates using SCD Type 1.

## Architecture

```text
                 SOURCE CSV FILES
                        |
                        v
                SNOWFLAKE STAGE
                        |
                    COPY INTO
                        |
                        v
                 RAW LAYER
          (Customers, Products,
             Stores, Sales)
                        |
                CLEANING & VALIDATION
                        |
                        v
                SILVER LAYER
          (Cleaned and Validated Data)
                        |
                        v
                 GOLD LAYER
          (Dimensions and Fact Tables)
                        |
              +---------+---------+
              |                   |
              v                   v
       STREAMS & TASKS       DYNAMIC TABLE
       Incremental Loads     Daily Sales Summary
```

## Technologies Used

- **Cloud Data Warehouse:** Snowflake
- **Query Language:** SQL, Snowflake Scripting
- **Data Ingestion:** Internal Stage, `COPY INTO`
- **Data Processing:** Streams, Tasks, Stored Procedures
- **Data Modeling:** Dimensional Modeling, Fact and Dimension Tables
- **Change Tracking:** SCD Type 1 and SCD Type 2
- **Analytics:** Dynamic Tables
- **Security:** RBAC, Dynamic Data Masking

## Project Architecture

The pipeline follows a Medallion Architecture with three main layers.

### 1. RAW Layer

The RAW layer stores data loaded directly from CSV files using Snowflake's internal stage and `COPY INTO`.

Four source tables are maintained:

- `RAW.CUSTOMERS`
- `RAW.PRODUCTS`
- `RAW.STORES`
- `RAW.SALES`

Along with the original source columns, ingestion metadata is captured:

- `_SOURCE_FILE`
- `_LOADED_AT`
- `_BATCH_ID`
- `_ROW_NUMBER`

Source values are retained in their original form to support downstream validation and troubleshooting.

### 2. SILVER Layer

The Silver layer handles data cleaning, validation, and deduplication.

Transformations include:

- Removing leading and trailing spaces using `TRIM`.
- Standardizing text using `LOWER` and `UPPER`.
- Handling empty values using `NULLIF`.
- Converting data types using `TRY_TO_NUMBER`, `TRY_TO_DATE`, and `TRY_TO_TIMESTAMP_NTZ`.
- Validating business rules such as email formats, positive prices, and valid sales quantities.
- Removing duplicate records using `ROW_NUMBER()` and `QUALIFY`.

Invalid records are stored in:

`SILVER.REJECTED_RECORDS`

The original record is retained along with its rejection reason, making it easier to investigate data-quality issues.

### 3. GOLD Layer

The Gold layer contains dimensional models used for reporting and analytical queries.

| Table | Description |
|---|---|
| `DIM_CUSTOMER` | Customer dimension with SCD Type 2 |
| `DIM_PRODUCT` | Product dimension with Type 1 updates |
| `DIM_STORE` | Store dimension |
| `DIM_DATE` | Date dimension |
| `FACT_SALES` | Sales fact table |

Surrogate keys are used in the dimension tables and referenced by the fact table.

Sales records are associated with the appropriate customer, product, and store dimension records.

## Dataset

The project uses generated retail CSV datasets covering four business entities.

### Initial Load

| Entity | Records |
|---|---:|
| Customers | 1,000 |
| Products | 100 |
| Stores | 30 |
| Sales | 10,000 |

### Incremental Loads

Two additional batches are used to demonstrate incremental processing.

| Batch | Customers | Products | Sales |
|---|---:|---:|---:|
| Batch 01 | 25 | 5 | 200 |
| Batch 02 | 24 | 5 | 200 |

The datasets contain scenarios such as customer updates, new customers, duplicate records, invalid emails, product price changes, invalid prices, and sales arriving before their corresponding customer records.

## Incremental Processing

Snowflake Streams capture newly inserted records from the RAW customer and sales tables.

Two streams are created:

- `RAW.CUSTOMER_STREAM`
- `RAW.SALES_STREAM`

The streams are configured with `APPEND_ONLY = TRUE` because the source ingestion process appends new records.

The captured records are processed through stored procedures.

### Customer Processing

The customer procedure:

1. Reads new records from `CUSTOMER_STREAM`.
2. Validates and deduplicates incoming customers.
3. Stores invalid records in the rejected-record table.
4. Updates the Silver customer table.
5. Applies SCD Type 2 logic to the Gold customer dimension.
6. Resolves inferred customer records when actual customer information arrives.

### Sales Processing

The sales procedure:

1. Reads new records from `SALES_STREAM`.
2. Validates and deduplicates sales.
3. Quarantines invalid records.
4. Updates the Silver sales table.
5. Resolves customer, product, and store surrogate keys.
6. Inserts new records into `GOLD.FACT_SALES`.

Business-key checks using `customer_id` and `sale_id` help prevent duplicate processing.

Both procedures use explicit transactions so that related changes are committed or rolled back together.

## Slowly Changing Dimensions

### SCD Type 2 – Customers

Customer attributes such as email, region, phone number, and segment can change over time.

SCD Type 2 maintains historical customer records rather than overwriting previous values.

For example, customer `C00001` initially has:

```text
email  = customer00001@example.com
region = SOUTH
```

In Batch 01, the customer's email changes:

```text
email  = updated.customer1@example.com
region = SOUTH
```

The existing dimension record is expired, and a new version is inserted.

The dimension maintains:

- `EFFECTIVE_START_DATE`
- `EFFECTIVE_END_DATE`
- `IS_CURRENT`

Each version receives a different surrogate key.

Historical sales are linked to the customer version that was valid when the sale occurred.

The lookup uses an effective-date condition:

```sql
c.effective_start_date <= s.sale_timestamp
AND s.sale_timestamp < c.effective_end_date
```

### SCD Type 1 – Products

Product attributes such as price, category, and brand are updated directly in the existing dimension record.

For example:

```text
P00001

Old price: 500
New price: 550
```

The Gold dimension stores the latest price without maintaining historical versions.

## Late-Arriving Dimension Handling

The project also handles sales arriving before their corresponding customer records.

In Batch 01, a sale arrives for customer `C99999`, but the customer does not yet exist in the customer dimension.

An inferred customer record is created:

```text
customer_id   = C99999
customer_name = UNKNOWN
is_inferred   = TRUE
```

A surrogate key is assigned to this record and used by the corresponding sales fact.

In Batch 02, the actual customer record arrives.

Instead of inserting another dimension record, the existing inferred record is updated with the real customer information.

```text
is_inferred = FALSE
```

The original surrogate key is retained, so previously loaded sales continue referencing the correct customer dimension record.

## Stored Procedures and Tasks

Two stored procedures handle incremental processing:

```text
GOLD.PROCESS_CUSTOMER_INCREMENTAL
GOLD.PROCESS_SALES_INCREMENTAL
```

Two Snowflake Tasks execute these procedures:

```text
GOLD.CUSTOMER_INCREMENTAL_TASK
GOLD.SALES_INCREMENTAL_TASK
```

Both tasks use `SYSTEM$STREAM_HAS_DATA()` to check whether their respective streams contain unconsumed records.

The tasks are created in a suspended state and can be resumed after validating the manual incremental processing.

```sql
ALTER TASK GOLD.CUSTOMER_INCREMENTAL_TASK RESUME;

ALTER TASK GOLD.SALES_INCREMENTAL_TASK RESUME;
```

This allows new customer and sales records to be processed automatically when data arrives in RAW.

## Dynamic Table – Daily Sales Summary

A Dynamic Table is created to maintain daily sales aggregations.

Object:

`GOLD.DAILY_SALES_SUMMARY`

It contains:

| Column | Description |
|---|---|
| `SALE_DATE` | Date of sale |
| `TOTAL_ORDERS` | Number of orders |
| `TOTAL_QUANTITY` | Units sold |
| `GROSS_SALES` | Sales before discounts |
| `DISCOUNT_AMOUNT` | Total discounts |
| `NET_SALES` | Sales after discounts |

The Dynamic Table uses a target lag of five minutes to maintain the aggregated results.

This also demonstrates the difference between procedural incremental processing using Streams and Tasks and declarative data transformations using Dynamic Tables.

## Security and Access Control

Basic role-based access control is implemented using three custom roles:

- `DATA_ENGINEER`
- `DATA_ANALYST`
- `DATA_VIEWER`

Privileges such as `USAGE` and `SELECT` are assigned based on the responsibilities of each role.

A masking policy is also applied to:

`GOLD.DIM_CUSTOMER.EMAIL`

Users with the `DATA_ENGINEER` and `ACCOUNTADMIN` roles can access the original email address, while other roles see a masked value.

*Note: Dynamic Data Masking requires Snowflake Enterprise Edition or higher.*

## Monitoring

The project includes a control schema for pipeline monitoring.

`CONTROL.PIPELINE_MONITORING`

Execution details are recorded in:

`CONTROL.PIPELINE_RUNS`

The monitoring implementation tracks information such as:

- Pipeline execution status
- Records processed
- Records rejected
- Execution start and end times
- Error messages

Snowflake history views are also used to inspect ingestion and task execution:

- `INFORMATION_SCHEMA.COPY_HISTORY`
- `INFORMATION_SCHEMA.TASK_HISTORY`

## Repository Structure

```text
retail-snowflake-data-engineering/
|
+-- 01_setup/
|   +-- database_schemas.sql
|   +-- file_format.sql
|   +-- stage.sql
|
+-- 02_raw/
|   +-- raw_tables.sql
|   +-- initial_load.sql
|   +-- raw_validation.sql
|
+-- 03_silver/
|   +-- customers.sql
|   +-- products.sql
|   +-- stores.sql
|   +-- sales.sql
|   +-- rejected_records.sql
|   +-- silver_validation.sql
|
+-- 04_gold/
|   +-- dim_customer.sql
|   +-- dim_product.sql
|   +-- dim_store.sql
|   +-- dim_date.sql
|   +-- fact_sales.sql
|   +-- gold_validation.sql
|
+-- 05_streams/
|   +-- customer_stream.sql
|   +-- sales_stream.sql
|
+-- 06_incremental/
|   +-- batch_01.sql
|   +-- batch_01_validation.sql
|   +-- batch_02.sql
|   +-- batch_02_validation.sql
|
+-- 07_procedures/
|   +-- customer_incremental.sql
|   +-- sales_incremental.sql
|
+-- 08_tasks/
|   +-- tasks.sql
|
+-- 09_dynamic_tables/
|   +-- daily_sales_summary.sql
|
+-- 10_security/
|   +-- roles.sql
|   +-- masking_policy.sql
|
+-- 11_monitoring/
|   +-- monitoring.sql
|   +-- final_validation.sql
|
+-- data/
    +-- customers_initial.csv
    +-- products_initial.csv
    +-- stores_initial.csv
    +-- sales_initial.csv
    +-- customers_batch_01.csv
    +-- products_batch_01.csv
    +-- sales_batch_01.csv
    +-- customers_batch_02.csv
    +-- products_batch_02.csv
    +-- sales_batch_02.csv
```

## Project Execution

Follow the sequence below to set up and execute the pipeline.

### Step 1 – Create Database Objects

Execute:

```text
01_setup/database_schemas.sql
01_setup/file_format.sql
01_setup/stage.sql
```

This creates the database, warehouse, schemas, file format, and internal stage.

### Step 2 – Upload Source Files

Upload the four initial CSV files to:

```text
@RETAIL_SUPPLY_CHAIN.RAW.RETAIL_SOURCE_STAGE/initial/
```

Files:

```text
customers_initial.csv
products_initial.csv
stores_initial.csv
sales_initial.csv
```

Files can be uploaded using Snowsight, SnowSQL, or Snowflake CLI.

### Step 3 – Load RAW Tables

Execute:

```text
02_raw/raw_tables.sql
02_raw/initial_load.sql
02_raw/raw_validation.sql
```

Verify the initial record counts:

```text
CUSTOMERS = 1000
PRODUCTS  = 100
STORES    = 30
SALES     = 10000
```

### Step 4 – Build SILVER Layer

Execute:

```text
03_silver/rejected_records.sql
03_silver/customers.sql
03_silver/products.sql
03_silver/stores.sql
03_silver/sales.sql
03_silver/silver_validation.sql
```

Verify the transformed records, rejected records, and business-key uniqueness.

### Step 5 – Build GOLD Layer

Execute:

```text
04_gold/dim_customer.sql
04_gold/dim_product.sql
04_gold/dim_store.sql
04_gold/dim_date.sql
04_gold/fact_sales.sql
04_gold/gold_validation.sql
```

Verify dimension records, fact records, surrogate keys, and foreign-key coverage.

### Step 6 – Create Streams

Execute:

```text
05_streams/customer_stream.sql
05_streams/sales_stream.sql
```

These streams capture subsequent customer and sales inserts.

### Step 7 – Process Incremental Batches

Execute:

```text
06_incremental/batch_01.sql
06_incremental/batch_01_validation.sql
06_incremental/batch_02.sql
06_incremental/batch_02_validation.sql
```

The batches demonstrate customer changes, new records, duplicates, invalid data, product updates, and late-arriving customer handling.

### Step 8 – Create Stored Procedures

Execute:

```text
07_procedures/customer_incremental.sql
07_procedures/sales_incremental.sql
```

Test the procedures manually before enabling automation.

### Step 9 – Enable Tasks

Execute:

```text
08_tasks/tasks.sql
```

After verifying the manual batch processing, resume the tasks to enable automatic processing.

### Step 10 – Create Dynamic Table

Execute:

```text
09_dynamic_tables/daily_sales_summary.sql
```

Verify the daily sales aggregation.

### Step 11 – Configure Security

Execute:

```text
10_security/roles.sql
10_security/masking_policy.sql
```

Run the scripts using a role with the required administrative privileges. The masking policy can be skipped if the account edition does not support it.

### Step 12 – Monitoring and Final Validation

Execute:

```text
11_monitoring/monitoring.sql
11_monitoring/final_validation.sql
```

Review pipeline execution history, task status, record counts, and data-quality checks.

## Validation and Testing

The following checks are used to validate the pipeline.

**RAW Layer**
- Verify source record counts.
- Check file names and batch IDs.
- Verify ingestion timestamps and row numbers.

**SILVER Layer**
- Check invalid and rejected records.
- Verify duplicate handling.
- Check null values and data types.
- Validate business-key uniqueness.

**GOLD Layer**
- Verify dimension and fact counts.
- Check surrogate-key relationships.
- Validate foreign-key coverage.
- Verify sales calculations.

**SCD Type 2**

Ensure that a customer has no more than one current dimension record:

```sql
SELECT customer_id
FROM GOLD.DIM_CUSTOMER
GROUP BY customer_id
HAVING COUNT_IF(is_current) > 1;
```

Expected result: zero rows.

**Late-Arriving Dimension**

After Batch 01:

```text
C99999 -> is_inferred = TRUE
```

After Batch 02:

```text
C99999 -> is_inferred = FALSE
```

The `CUSTOMER_KEY` should remain unchanged between both batches.

## Sample Analytical Queries

**Daily Sales Revenue**

```sql
SELECT
    sale_date,
    net_sales
FROM GOLD.DAILY_SALES_SUMMARY
ORDER BY sale_date;
```

**Sales by Customer Region**

```sql
SELECT
    c.region,
    SUM(f.net_amount) AS net_sales
FROM GOLD.FACT_SALES f
JOIN GOLD.DIM_CUSTOMER c
    ON f.customer_key = c.customer_key
GROUP BY c.region
ORDER BY net_sales DESC;
```

**Sales by Product Category**

```sql
SELECT
    p.category,
    SUM(f.net_amount) AS net_sales,
    SUM(f.quantity) AS units
FROM GOLD.FACT_SALES f
JOIN GOLD.DIM_PRODUCT p
    ON f.product_key = p.product_key
GROUP BY p.category
ORDER BY net_sales DESC;
```

**Store Performance**

```sql
SELECT
    s.store_id,
    s.city,
    SUM(f.net_amount) AS net_sales
FROM GOLD.FACT_SALES f
JOIN GOLD.DIM_STORE s
    ON f.store_key = s.store_key
GROUP BY s.store_id, s.city
ORDER BY net_sales DESC;
```

## Key Concepts Demonstrated

| Concept | Snowflake Implementation |
|---|---|
| Data ingestion | Internal Stage, COPY INTO |
| Data organization | RAW, SILVER, GOLD |
| Data cleaning | SQL transformations |
| Data validation | Business rules |
| Deduplication | ROW_NUMBER, QUALIFY |
| Error handling | Rejected Records |
| Incremental processing | Streams |
| Automation | Tasks |
| Procedural processing | Stored Procedures |
| Historical tracking | SCD Type 2 |
| Latest-value updates | SCD Type 1 |
| Late-arriving dimensions | Inferred Members |
| Dimensional modeling | Fact and Dimension Tables |
| Aggregation | Dynamic Tables |
| Access management | RBAC |
| Data protection | Dynamic Data Masking |
| Monitoring | COPY_HISTORY, TASK_HISTORY |

## Resume Description

**Retail Sales Data Engineering Pipeline | Snowflake, SQL**

- Developed an end-to-end retail data pipeline in Snowflake, processing 1K customers, 100 products, 30 stores, and 10K sales records across RAW, SILVER, and GOLD layers using COPY INTO, SQL transformations, data validation, and deduplication.
- Implemented incremental processing using Streams, Tasks, and Stored Procedures, with SCD Type 2 customer history, SCD Type 1 product updates, and inferred-member handling for late-arriving dimensions.
- Built dimensional models and a Dynamic Table for daily sales analytics, incorporating surrogate keys, rejected-record handling, RBAC, dynamic data masking, and pipeline monitoring.

## Conclusion

This project covers the key stages of building a data engineering pipeline in Snowflake, from loading raw CSV data to preparing analytical datasets.

It brings together data ingestion, transformation, incremental processing, dimensional modeling, data quality, security, and monitoring in one project.

The implementation also provides practical examples of handling changing customer attributes, late-arriving dimensions, duplicate records, and invalid source data using Snowflake SQL features.

