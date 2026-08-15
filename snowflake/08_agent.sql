-- ============================================================================
-- 08_AGENT.SQL — Cortex Agent for Grid Integration
-- ============================================================================
USE DATABASE GRID_INTEGRATION;
USE SCHEMA APP;

CREATE OR REPLACE CORTEX AGENT APP.GRID_INTEGRATION_AGENT
  COMMENT = 'Grid Integration AI Assistant'
  MODEL = 'claude-opus-4-8'
  TOOLS = (
    SEMANTIC_VIEW_TOOL(SEMANTIC_VIEW => 'GRID_INTEGRATION.APP.GRID_INTEGRATION_ANALYTICS'),    CORTEX_SEARCH_TOOL(CORTEX_SEARCH_SERVICE => 'GRID_INTEGRATION.SEARCH.GRID_INTEGRATION_SEARCH', TOOL_DESCRIPTION => 'Search documents for Renewable Energy information')
  )
  SYSTEM_PROMPT = 'You are the Grid Integration Agent for Vietnamese renewable energy operations in Hanoi (EVN NLD).';
