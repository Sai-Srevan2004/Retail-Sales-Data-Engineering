
# Retail Supply Chain Data Engineering Project

## Overview

This project implements an end-to-end retail supply chain data engineering pipeline using **Snowflake SQL**. It processes customer, product, store, and sales data through a medallion architecture (RAW → SILVER → GOLD), applying data cleansing, validation, deduplication, incremental loading, and dimensional modelling to build an analytics-ready data warehouse.

The pipeline uses Snowflake Streams, Stored Procedures, and Tasks for automated incremental processing. It also implements SCD Type 1 and Type 2, late-arriving dimension handling, Dynamic Tables, and data security using RBAC, Dynamic Data Masking, and Row Access Policies.

## Architecture

```text
             SOURCE CSV FILES
                    |
                    v
           SNOWFLAKE INTERNAL STAGE
                    |
                    v
                RAW LAYER
           (Raw Data + Metadata)
                    |
                    v
              RAW STREAMS
                    |
                    v
             SILVER LAYER
      (Cleansing, Validation, Deduplication)
                    |
                    v
          REJECTED RECORDS TABLE
                    |
                    v
               GOLD LAYER
           (Dimensional Model)
                    |
             +------+------+
             |             |
         DIMENSIONS     FACT_SALES
             |             |
             +------+------+
                    |
                    v
         DAILY_SALES_SUMMARY
            (Dynamic Table)
                    |
                    v
            ANALYTICS READY
```

## Technologies Used

- **Snowflake SQL** – Cloud data warehouse and data processing.
- **Snowflake Internal Stage** – CSV file staging and ingestion.
- **COPY INTO** – Loading source files into RAW tables.
- **Snowflake Streams** – Change data capture for incremental processing.
- **Stored Procedures** – Reusable transformation and loading logic.
- **Snowflake Tasks** – Automated pipeline orchestration.
- **Dynamic Tables** – Automated analytical aggregations.

## Data Pipeline Implementation

### 1. Data Ingestion – RAW Layer

- Loaded CSV source files into a Snowflake Internal Stage.
- Used `COPY INTO` to ingest data into RAW tables.
- Stored source metadata such as file name, load timestamp, batch ID, and row number.
- Maintained raw source values as strings for downstream validation and transformation.

### 2. Data Transformation – SILVER Layer

- Converted raw data into appropriate data types using safe conversion functions.
- Applied data cleansing and standardization.
- Implemented business-key-based deduplication.
- Validated mandatory fields, timestamps, numerical values, and business rules.
- Captured invalid records in a centralized rejection table with rejection reasons and source metadata.
- Used Streams to support incremental processing.

### 3. Data Warehousing – GOLD Layer

Implemented a dimensional model using fact and dimension tables.

**Dimension Tables**

| Table | Implementation |
|---|---|
| DIM_CUSTOMER | SCD Type 2 |
| DIM_PRODUCT | SCD Type 1 |
| DIM_STORE | Static Dimension |
| DIM_DATE | Pre-populated Date Dimension |

**Fact Table**

- `FACT_SALES` – Stores transactional sales measures and dimension keys.

Additional implementation:

- Used surrogate keys for dimensional modelling.
- Implemented inferred dimension members for late-arriving dimension records.
- Resolved inferred records when actual dimension data became available.
- Used effective date ranges to associate historical sales with the correct customer dimension version.

### 4. Incremental Processing and Automation

- Created Snowflake Streams on RAW and SILVER tables to capture data changes.
- Implemented Stored Procedures for Silver transformations and Gold loading.
- Used Snowflake Tasks to orchestrate the pipeline through a dependency-based task graph.
- Designed independent Silver processing branches for customers, products, and sales.
- Coordinated Gold dimension and fact loading based on upstream task dependencies.
- Used triggered-task execution to initiate processing when new stream data is detected.

### 5. Analytical Layer – Dynamic Tables

Created `GOLD.DAILY_SALES_SUMMARY` using a Snowflake Dynamic Table.

The summary aggregates sales by date and store, including:

- Total orders
- Total units sold
- Gross sales
- Total discounts
- Net sales
- Average order value

Configured a target lag to maintain data freshness through automated refreshes.

### 6. Data Quality and Validation

Implemented data quality checks to handle:

- Duplicate records.
- Missing mandatory values.
- Invalid timestamps and numeric values.
- Invalid business attributes.
- Incorrect sales measures.
- Rejected record tracking.
- Fact-to-dimension relationship validation.
- End-to-end record reconciliation.

### 7. Security and Access Control

Implemented Snowflake security features:

- **RBAC:** Created separate `DATA_ENGINEER` and `DATA_ANALYST` roles with different access permissions.
- **Dynamic Data Masking:** Protected customer email addresses and phone numbers based on active roles.
- **Row Access Policies:** Restricted analyst visibility to customers belonging to the SOUTH region.
- **Least Privilege:** Limited analyst access to the GOLD layer while providing broader permissions to the data engineering role.

## Key Features

- End-to-end medallion architecture.
- Snowflake Internal Stage-based ingestion.
- Incremental data processing using Streams.
- Automated orchestration using Tasks.
- SCD Type 1 and SCD Type 2 implementation.
- Late-arriving dimension handling.
- Centralized rejected-record management.
- Star schema dimensional modelling.
- Automated analytical aggregations using Dynamic Tables.
- Role-based security and data protection.

## Learning Outcomes

Through this project, I gained practical experience in building data pipelines using Snowflake, implementing incremental ETL/ELT workflows, designing dimensional data models, handling real-world data quality scenarios, automating pipeline execution, and securing analytical data.

---

**Project Focus:** Data Engineering | Snowflake | SQL | Data Warehousing | ETL/ELT | Incremental Data Processing
