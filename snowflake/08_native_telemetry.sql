-- ============================================================================
-- 08_native_telemetry.sql - Snowflake-only build: live telemetry without AWS.
-- Creates RAW.LIVE_TELEMETRY (same columns as the Snowpipe target created by
-- aws/setup_aws.py) and APP.SIMULATE_TELEMETRY(N), which inserts synthetic
-- substation SCADA readings (busbar voltage deviation in %, transformer loading in %) with the same value ranges and ~10% ALARM rate as
-- aws/publish_telemetry.py. Rows are inserted directly; this simulates a
-- sensor feed and is not Snowpipe Streaming.
-- Run before 06_intelligence.sql (the alert reads RAW.LIVE_TELEMETRY).
-- Idempotent: safe to run in the AWS build too.
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS APP;

CREATE TABLE IF NOT EXISTS RAW.LIVE_TELEMETRY (
  SUBSTATION_ID VARCHAR, EVENT_TS TIMESTAMP_NTZ, VOLTAGE_DEV_PCT FLOAT, TRANSFORMER_LOAD_PCT FLOAT,
  STATUS VARCHAR, IOT_RECEIVED_TS TIMESTAMP_NTZ, SOURCE_FILE VARCHAR,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());

CREATE OR REPLACE PROCEDURE APP.SIMULATE_TELEMETRY(N NUMBER)
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  IF (N < 1 OR N > 1000) THEN
    RETURN 0;
  END IF;
  INSERT INTO RAW.LIVE_TELEMETRY (SUBSTATION_ID, EVENT_TS, VOLTAGE_DEV_PCT, TRANSFORMER_LOAD_PCT, STATUS, IOT_RECEIVED_TS, SOURCE_FILE)
    WITH g AS (
      SELECT 'GC-' || LPAD(UNIFORM(0, 29, RANDOM())::VARCHAR, 4, '0') AS SUBSTATION_ID,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.1 AS IS_ALARM,
             SYSDATE() AS TS, SEQ4() AS I
      FROM TABLE(GENERATOR(ROWCOUNT => 1000))
    )
    -- NORMAL() needs a constant mean, so the alarm offset is added outside it.
    SELECT SUBSTATION_ID, TS,
           ROUND(GREATEST(0.05, IFF(IS_ALARM, 3.90, 1.40) + NORMAL(0, 0.25, RANDOM())), 3),
           ROUND(LEAST(100, IFF(IS_ALARM, 95, 71) + NORMAL(0, 3, RANDOM())), 1),
           IFF(IS_ALARM, 'ALARM', 'NORMAL'), TS, 'APP.SIMULATE_TELEMETRY'
    FROM g
    WHERE I < :N;
  RETURN SQLROWCOUNT;
END;
$$;

-- Optional continuous feed for longer demos (suspended; RESUME to start, SUSPEND after).
CREATE OR REPLACE TASK APP.TASK_SIMULATE_TELEMETRY
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '1 MINUTE'
AS
  CALL APP.SIMULATE_TELEMETRY(5);
