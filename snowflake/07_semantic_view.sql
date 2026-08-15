-- ============================================================================
-- 07_SEMANTIC_VIEW.SQL — Semantic View for Grid Integration
-- ============================================================================
USE DATABASE GRID_INTEGRATION;
USE SCHEMA APP;

CREATE OR REPLACE SEMANTIC VIEW APP.GRID_INTEGRATION_ANALYTICS
  COMMENT = 'Renewable Energy grid integration analytics'
AS
  TABLES (
    CURATED.PERFORMANCE_DASHBOARD AS performance_dashboard,CURATED.TREND_ANALYTICS AS trend_analytics,CURATED.FORECAST_INPUT AS forecast_input,CURATED.OPERATIONAL_RISK AS operational_risk
  );
