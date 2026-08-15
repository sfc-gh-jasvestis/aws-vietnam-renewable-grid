-- ============================================================================
-- Grid Integration
-- Grid Integration for Vietnam - ML.FORECAST and Dynamic Tables power real-time grid integration intelligence for renewable energy in Hanoi (EVN NLD).
-- ============================================================================
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS GRID_INTEGRATION;
CREATE WAREHOUSE IF NOT EXISTS GRID_WH WAREHOUSE_SIZE = 'MEDIUM' AUTO_SUSPEND = 120 AUTO_RESUME = TRUE;
USE DATABASE GRID_INTEGRATION;
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS CURATED;
CREATE SCHEMA IF NOT EXISTS ML;
CREATE SCHEMA IF NOT EXISTS AI;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

USE WAREHOUSE GRID_WH;
