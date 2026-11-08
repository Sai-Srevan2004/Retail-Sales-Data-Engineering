--==================================================
-- 1. CREATE DATABASE
--==================================================
CREATE DATABASE IF NOT EXISTS RETAIL_SUPPLY_CHAIN;

--==================================================
-- 2. CREATE SCHEMAS
--==================================================

CREATE SCHEMA IF NOT EXISTS RETAIL_SUPPLY_CHAIN.RAW;
CREATE SCHEMA IF NOT EXISTS RETAIL_SUPPLY_CHAIN.SILVER;
CREATE SCHEMA IF NOT EXISTS RETAIL_SUPPLY_CHAIN.GOLD;
CREATE SCHEMA IF NOT EXISTS RETAIL_SUPPLY_CHAIN.CONTROL;

--==================================================
-- 3. CREATE WAREHOUSE
--==================================================

CREATE WAREHOUSE IF NOT EXISTS RETAIL_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

--==================================================
-- 4. USE DB AND WAREHOUSE
--==================================================

USE DATABASE RETAIL_SUPPLY_CHAIN;
USE WAREHOUSE RETAIL_WH;
