-- ============================================================================
-- 05_SEARCH.SQL — Cortex Search for Grid Integration
-- ============================================================================
USE DATABASE GRID_INTEGRATION;
USE SCHEMA SEARCH;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.GRID_INTEGRATION_SEARCH
  ON CONTENT
  ATTRIBUTES DOC_TYPE, CATEGORY
  WAREHOUSE = GRID_WH
  TARGET_LAG = '1 hour'
AS (
  SELECT * FROM RAW.DOCUMENTS
);
