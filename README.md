# Retail Sales Data Engineering Pipeline using Snowflake 

A medium-sized Snowflake data engineering project that ingests retail CSV files, cleans and validates them, models them into dimensions/facts, and demonstrates incremental processing with Streams, Tasks, SCD Type 2, Type 1, an inferred member for a late-arriving dimension, a Dynamic Table, RBAC, masking, and monitoring.

The design intentionally uses only the four business entities required for the project:

- Customers — incremental + SCD Type 2
- Products — incremental + Type 1
- Stores — initial/static
- Sales — incremental fact

It does **not** introduce Kafka, Airflow, Spark, Databricks, dbt, Kubernetes, suppliers, inventory, warehouses, or an external database.

## Automation design

```text
RAW.CUSTOMERS ──> CUSTOMER_STREAM ──> TRIGGERED TASK ──> CUSTOMER PROCEDURE
                                                   └──> SILVER.CUSTOMERS
                                                   └──> GOLD.DIM_CUSTOMER (SCD2)

RAW.SALES ──────> SALES_STREAM ──────> TRIGGERED TASK ──> SALES PROCEDURE
                                                   ├──> SILVER.SALES
                                                   └──> GOLD.FACT_SALES

GOLD.FACT_SALES ──> DYNAMIC TABLE ──> GOLD.DAILY_SALES_SUMMARY
```

The automation starts at the RAW layer because the project deliberately uses `COPY INTO` for source-file ingestion. In a larger production deployment, a managed ingestion service could replace the manual file-to-RAW step, but it is intentionally outside this fresher-sized project.

## Reliability practices

- **Stream-driven automation:** tasks fire only when their stream contains unconsumed CDC records.
- **Transactional incremental processing:** customer and sales procedures wrap related DML in explicit transactions.
- **Retry safety:** a failed procedure rolls back its downstream changes, so the stream change is not treated as successfully consumed.
- **Business-key idempotency:** customer processing uses `customer_id`; sales processing protects `sale_id`.
- **SCD2 safety:** only tracked customer changes expire the current row; inferred customers are resolved in place.
- **Quarantine safety:** rejected records use source/batch/business-key guards to avoid duplicate quarantine entries.
- **Run monitoring:** `CONTROL.PIPELINE_RUNS` records execution status, counts, timing, and errors.

## Architecture

```text
                    SOURCE CSV FILES
                           |
                           v
                +----------------------+
                | INTERNAL STAGE       |
                | RAW.RETAIL_SOURCE... |
                +----------------------+
                           |
                        COPY INTO
                           |
                           v
                +----------------------+
                | RAW                  |
                | customers/products   |
                | stores/sales         |
                +----------------------+
                           |
                     clean / validate
                     / deduplicate
                           |
                           v
                +----------------------+
                | SILVER               |
                | customers/products   |
                | stores/sales         |
                | rejected_records     |
                +----------------------+
                           |
                           v
                +----------------------+
                | GOLD                 |
                | dim_customer (SCD2)  |
                | dim_product (Type 1) |
                | dim_store             |
                | dim_date              |
                | fact_sales            |
                +----------------------+
                    |             |
             Streams/Tasks     Dynamic Table
                    |             |
                    v             v
             incremental      daily sales
              processing        summary
```

## Initial data

| Entity | Rows |
|---|---:|
| Customers | 1,000 |
| Products | 100 |
| Stores | 30 |
| Sales | 10,000 |

The CSVs are deterministic. Important scenarios are deliberately controlled rather than random.

## Incremental data

| Batch | Customers | Products | Sales |
|---|---:|---:|---:|
| Batch 01 | 25 | 5 | 200 |
| Batch 02 | 24 | 5 | 200 |

The incremental files are intentionally small so that the pipeline can be inspected manually.

### Controlled scenarios

Batch 01:

- `C00001` changes email -> SCD Type 2
- `C00002` is unchanged -> no new SCD2 version
- `C01001`... new customers
- `C01022` has an invalid email -> rejected
- `C01023` appears twice -> deduplicated using `ROW_NUMBER`
- `P00001` and `P00002` change price -> Type 1 overwrite
- `P00101` and `P00103` are new products
- `P00102` has a non-positive price -> rejected
- `C99999` appears in a valid sale before its customer record arrives -> inferred customer
- one sale has non-positive quantity -> rejected
- one sale ID is duplicated within the batch

Batch 02:

- `C99999` real customer record arrives -> inferred row is resolved in-place
- `C00003` changes region/segment -> another SCD2 version
- new customers are added
- `C01044` has an invalid email -> rejected
- `P00003` changes price -> Type 1 overwrite
- new products are added
- one sale has a discount larger than gross amount -> rejected
- one sale ID is duplicated within the batch

## Why the design treats entities differently

### Customers -> incremental + SCD Type 2

Customer attributes such as email, phone, region, and segment can change. The Gold dimension therefore preserves historical versions.

### Products -> incremental + Type 1

Product price/category/brand changes are represented by the latest state. Old versions are not required for this project.

### Stores -> initial load only

Stores are treated as relatively static master data. There is intentionally no store stream, store incremental procedure, or store batch file.

### Sales -> incremental fact

Sales arrive continuously. Only newly arrived sales are processed into the fact table.

---

# Folder structure

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

---

# Execution order

Run the project in this order. Do not turn on the Tasks before the manual batch flow has been verified.

## Phase 1 — Setup

1. `01_setup/database_schemas.sql`
2. `01_setup/file_format.sql`
3. `01_setup/stage.sql`

Upload the initial files into:

```text
@RETAIL_SUPPLY_CHAIN.RAW.RETAIL_SOURCE_STAGE/initial/
```

The files are:

```text
customers_initial.csv
products_initial.csv
stores_initial.csv
sales_initial.csv
```

You can upload them from Snowsight's stage UI, Snowflake CLI, or SnowSQL.

For SnowSQL/Snowflake CLI-style file upload, the pattern is:

```sql
PUT 'file:///absolute/path/data/customers_initial.csv'
  @RETAIL_SUPPLY_CHAIN.RAW.RETAIL_SOURCE_STAGE/initial
  AUTO_COMPRESS=TRUE;
```

Repeat for the other three files.

Then:

```sql
LIST @RETAIL_SUPPLY_CHAIN.RAW.RETAIL_SOURCE_STAGE/initial;
```

## Phase 2 — RAW

Run:

```text
02_raw/raw_tables.sql
02_raw/initial_load.sql
02_raw/raw_validation.sql
```

Expected initial RAW counts:

```text
CUSTOMERS = 1000
PRODUCTS  = 100
STORES    = 30
SALES     = 10000
```

RAW intentionally preserves source values and ingestion metadata:

```text
_source_file
_loaded_at
_batch_id
_row_number
```

No business transformation belongs in RAW.

## Phase 3 — SILVER

Run:

```text
03_silver/rejected_records.sql
03_silver/customers.sql
03_silver/products.sql
03_silver/stores.sql
03_silver/sales.sql
03_silver/silver_validation.sql
```

Silver performs:

```text
TRIM
LOWER / UPPER
NULLIF
TRY_TO_DATE
TRY_TO_TIMESTAMP_NTZ
TRY_TO_NUMBER
validation
deduplication
```

Invalid records go to:

```text
SILVER.REJECTED_RECORDS
```

The original values are retained in `raw_record`.

### Important count rule

Do not expect:

```text
RAW = SILVER + REJECTED
```

because a valid duplicate can be removed during deduplication.

Validate separately:

```text
RAW arrivals
INVALID records
DUPLICATES
SILVER valid records
BUSINESS KEY uniqueness
```

## Phase 4 — GOLD

Run:

```text
04_gold/dim_customer.sql
04_gold/dim_product.sql
04_gold/dim_store.sql
04_gold/dim_date.sql
04_gold/fact_sales.sql
04_gold/gold_validation.sql
```

Gold contains:

```text
DIM_CUSTOMER
DIM_PRODUCT
DIM_STORE
DIM_DATE
FACT_SALES
```

The initial customer dimension is one current version per customer.

The fact table uses surrogate keys rather than natural IDs.

---

# SCD Type 2

The controlled example is `C00001`.

Initial:

```text
customer_id = C00001
email       = customer00001@example.com
region      = SOUTH
segment     = REGULAR
```

Batch 01:

```text
customer_id = C00001
email       = updated.customer1@example.com
region      = SOUTH
segment     = REGULAR
updated_at  = 2026-09-01 09:00:00
```

The result is:

```text
OLD VERSION
is_current = FALSE
effective_end_date = 2026-09-01 09:00:00

NEW VERSION
is_current = TRUE
effective_start_date = 2026-09-01 09:00:00
effective_end_date = 9999-12-31 23:59:59
```

The two rows have different `customer_key` surrogate keys.

The fact lookup uses:

```sql
c.effective_start_date <= s.sale_timestamp
AND s.sale_timestamp < c.effective_end_date
```

This is why a historical sale continues to point to the customer version that was valid at the time of the sale.

---

# Late-arriving dimension

Batch 01 contains a sale for:

```text
customer_id = C99999
```

but there is no real C99999 customer record yet.

The sales procedure creates:

```text
customer_id = C99999
customer_name = UNKNOWN
is_inferred = TRUE
```

The inferred row receives a surrogate `customer_key`.

The Batch 01 sale uses that key.

Batch 02 later contains the real C99999 customer.

The customer procedure updates the existing inferred row:

```text
UNKNOWN
    |
    v
real customer information
```

and changes:

```text
is_inferred = TRUE
```

to:

```text
is_inferred = FALSE
```

The critical rule is:

```text
SAME customer_key
```

No second dimension row is created for C99999.

This keeps the Batch 01 fact's foreign key valid.

---

# Streams

The project uses only:

```text
RAW.CUSTOMER_STREAM
RAW.SALES_STREAM
```

Stores do not have a stream because stores are intentionally static.

Streams capture changes between offsets. The stream metadata includes values such as:

```text
METADATA$ACTION
METADATA$ISUPDATE
METADATA$ROW_ID
```

The project uses `APPEND_ONLY = TRUE` because the ingestion pattern appends newly arrived CSV rows into RAW.

The batch files therefore create INSERT change records in the streams.

---

# Incremental processing

## Customer

```text
RAW.CUSTOMER_STREAM
        |
        v
validate + deduplicate
        |
        +--> rejected records
        |
        v
SILVER.CUSTOMERS
        |
        v
GOLD.DIM_CUSTOMER
        |
        +--> SCD2 change
        |
        +--> inferred-member resolution
```

## Sales

```text
RAW.SALES_STREAM
        |
        v
validate + deduplicate
        |
        +--> rejected records
        |
        v
SILVER.SALES
        |
        v
dimension lookups
        |
        v
GOLD.FACT_SALES
```

---

# Type 1 product processing

Product changes are applied directly to the current Gold row.

Example:

```text
P00001
old price -> 500
new price -> 550
```

Gold ends with:

```text
P00001 -> 550
```

There is no product history table.

The project deliberately keeps Type 1 simple.

---

# Stored procedures

Only two stored procedures are used:

```text
GOLD.PROCESS_CUSTOMER_INCREMENTAL
GOLD.PROCESS_SALES_INCREMENTAL
```

They consume their streams and perform the incremental logic.

The procedures use Snowflake Scripting with small temporary working tables.

They are not generic enterprise frameworks.

---

# Tasks

Two small triggered tasks are defined:

```text
GOLD.CUSTOMER_INCREMENTAL_TASK
GOLD.SALES_INCREMENTAL_TASK
```

Each task uses:

```sql
WHEN SYSTEM$STREAM_HAS_DATA(...)
```

and calls the corresponding procedure only when its stream has unconsumed change data.

The tasks intentionally have no `SCHEDULE`. This models event-driven RAW -> SILVER -> GOLD processing after the RAW tables have been loaded. Keep them suspended while validating the manual initial/batch flow, then resume them when automation is ready.

The procedures use explicit transactions around the stream consumption and downstream DML. If a procedure fails, the transaction is rolled back and the task can retry the unconsumed stream changes without leaving a partially-applied SCD2/fact update.

The tasks are created **SUSPENDED** initially.

After manual Batch 01 and Batch 02 testing succeeds, they can be enabled:

```sql
ALTER TASK GOLD.CUSTOMER_INCREMENTAL_TASK RESUME;
ALTER TASK GOLD.SALES_INCREMENTAL_TASK RESUME;
```

The project intentionally avoids a large orchestration graph.

---

# Dynamic Table

The project has one Dynamic Table:

```text
GOLD.DAILY_SALES_SUMMARY
```

It contains:

```text
sale_date
total_orders
total_quantity
gross_sales
discount_amount
net_sales
```

Target lag:

```text
5 minutes
```

Important: target lag is a freshness target, not a guaranteed five-minute refresh interval.

This gives a clean interview comparison:

```text
Streams + Tasks
    -> explicitly capture changes and run procedural work

Dynamic Table
    -> declaratively materializes a query result and keeps it fresh
```

---

# Security

Three custom roles are demonstrated:

```text
DATA_ENGINEER
DATA_ANALYST
DATA_VIEWER
```

The roles show basic:

```text
USAGE
SELECT
object-level access
```

A masking policy is applied to:

```text
GOLD.DIM_CUSTOMER.email
```

The example allows `DATA_ENGINEER` and `ACCOUNTADMIN` to see the real value and masks it for other roles.

The masking-policy feature requires Snowflake Enterprise Edition or higher.

If your account does not support masking policies, skip:

```text
10_security/masking_policy.sql
```

The core pipeline does not depend on masking.

---

# Monitoring

The project includes:

```text
CONTROL.PIPELINE_MONITORING
```

and example history queries for:

```text
COPY_HISTORY
TASK_HISTORY
```

The goal is observability without building a separate monitoring platform.

---

# Validation checklist

## RAW

Check:

- row counts
- source file
- batch ID
- load metadata

## SILVER

Check:

- valid rows
- rejected rows
- duplicate diagnostics
- nulls
- business-key uniqueness

## GOLD

Check:

- dimension counts
- fact count
- surrogate keys
- foreign-key coverage
- calculated amounts

## SCD2

This must return zero rows:

```sql
SELECT customer_id
FROM GOLD.DIM_CUSTOMER
GROUP BY customer_id
HAVING COUNT_IF(is_current) > 1;
```

## Late-arriving customer

After Batch 01:

```text
C99999 -> is_inferred = TRUE
```

After Batch 02:

```text
C99999 -> is_inferred = FALSE
```

The `customer_key` must remain unchanged.

---

# Example analytics

```sql
-- Daily revenue
SELECT sale_date, net_sales
FROM GOLD.DAILY_SALES_SUMMARY
ORDER BY sale_date;

-- Revenue by region using the customer version valid at sale time
SELECT
    c.region,
    SUM(f.net_amount) AS net_sales
FROM GOLD.FACT_SALES f
JOIN GOLD.DIM_CUSTOMER c
  ON f.customer_key = c.customer_key
GROUP BY c.region
ORDER BY net_sales DESC;

-- Product sales
SELECT
    p.category,
    SUM(f.net_amount) AS net_sales,
    SUM(f.quantity) AS units
FROM GOLD.FACT_SALES f
JOIN GOLD.DIM_PRODUCT p
  ON f.product_key = p.product_key
GROUP BY p.category
ORDER BY net_sales DESC;

-- Store performance
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

