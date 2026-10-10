-- ============================================================================
-- 06_INTELLIGENCE.SQL - search, anomaly detection, semantic view, agent,
-- live-telemetry alert and on-demand refresh DAG.
-- Run with snowflake/run_intelligence.py (substitutes checked __DEMO_DB__ /
-- __DEMO_WH__ / __ALERT_EMAIL__). Requires 00-05, plus 08 (Snowflake only) or
-- aws/setup_aws.py (AWS build) for RAW.LIVE_TELEMETRY.
-- Alerts and tasks are created SUSPENDED; run them with EXECUTE ALERT / EXECUTE TASK.
-- ============================================================================
USE DATABASE __DEMO_DB__;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;


-- ---------- Synthetic grid connection knowledge base (clearly synthetic SOPs) ----------
CREATE OR REPLACE TABLE SEARCH.SUBSTATION_SOP_DOCS AS
WITH causes AS (
  SELECT DISTINCT r.ROOT_CAUSE, h.CATEGORY
  FROM RAW.SUBSTATION_DAILY r JOIN RAW.SUBSTATIONS h ON h.ID = r.ENTITY_ID
  WHERE r.ROOT_CAUSE IS NOT NULL AND r.GRID_EVENT_COUNT > 0
)
SELECT
  'SOP-' || LPAD(ROW_NUMBER() OVER (ORDER BY CATEGORY, ROOT_CAUSE)::VARCHAR, 3, '0') AS DOC_ID,
  'SOP' AS DOC_TYPE,
  CATEGORY,
  ROOT_CAUSE,
  CATEGORY || ' - ' || ROOT_CAUSE || ' grid event response' AS TITLE,
  'Synthetic demo SOP. Connection type: ' || CATEGORY || '. Grid event cause: ' || ROOT_CAUSE || '. '
  || 'Step 1: notify the control room dispatch engineer, log the feeders and plant units affected, and confirm the SCADA values for voltage, frequency, power factor and active power against the revenue meter. '
  || 'Step 2: ' || CASE
       WHEN ROOT_CAUSE ILIKE '%ramp%' THEN 'apply the ramp-rate limit in the plant controller, request the battery or hybrid plant to smooth output where available and log the curtailment instruction with its timestamp.'
       WHEN ROOT_CAUSE ILIKE '%inverter%' OR ROOT_CAUSE ILIKE '%converter%' OR ROOT_CAUSE ILIKE '%ride-through%' THEN 'isolate the tripped units, review the protection relay event record, restore units in small blocks and send the fault log to the original equipment supplier.'
       WHEN ROOT_CAUSE ILIKE '%reactive%' OR ROOT_CAUSE ILIKE '%harmonic%' THEN 'switch in the reactive compensation or harmonic filter bank, check the power quality meter trend and hold additional export until the reading is back inside the band.'
       WHEN ROOT_CAUSE ILIKE '%cable%' OR ROOT_CAUSE ILIKE '%transmission%' OR ROOT_CAUSE ILIKE '%storm%' THEN 'open the affected bay, confirm the network switching plan with the transmission control centre, dispatch the line crew once conditions are safe and record each switching step.'
       WHEN ROOT_CAUSE ILIKE '%battery%' OR ROOT_CAUSE ILIKE '%charge%' THEN 'reduce the battery charge or discharge setpoint, check cooling and state-of-charge limits in the battery management system and log the limit reached.'
       WHEN ROOT_CAUSE ILIKE '%controller%' OR ROOT_CAUSE ILIKE '%metering%' THEN 'switch the plant controller to its standby unit or recalibrate the meter against a portable reference, and flag samples since the last good calibration for review.'
       ELSE 'record the issue, contain the affected bay and escalate to the regional grid operations lead.'
     END
  || ' Step 3: if busbar voltage deviation stays above 2.5% or transformer loading stays above 92% after recovery, keep the substation on the watch list and defer new plant energisation. '
  || 'Step 4: confirm recovery of the in-limit rate and record the root cause, feeders and switching steps in the grid event log.' AS CONTENT
FROM causes;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.SUBSTATION_SOP_SEARCH
  ON CONTENT
  ATTRIBUTES CATEGORY, ROOT_CAUSE
  WAREHOUSE = __DEMO_WH__
  TARGET_LAG = '7 days'
AS (SELECT DOC_ID, TITLE, CATEGORY, ROOT_CAUSE, CONTENT FROM SEARCH.SUBSTATION_SOP_DOCS);

-- ---------- Voltage deviation anomaly detection (train first 75 days, detect last 15) ----------
CREATE OR REPLACE VIEW ML.VOLTAGE_DEV_SERIES AS
SELECT ENTITY_ID, EVENT_DATE::TIMESTAMP_NTZ AS TS, VOLTAGE_DEV_PCT::FLOAT AS VOLTAGE_DEV
FROM RAW.SUBSTATION_DAILY;
CREATE OR REPLACE VIEW ML.VOLTAGE_DEV_TRAIN AS
SELECT * FROM ML.VOLTAGE_DEV_SERIES WHERE TS < (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.VOLTAGE_DEV_SERIES);
CREATE OR REPLACE VIEW ML.VOLTAGE_DEV_DETECT AS
SELECT * FROM ML.VOLTAGE_DEV_SERIES WHERE TS >= (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.VOLTAGE_DEV_SERIES);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ML.VOLTAGE_DEV_ANOMALY_MODEL(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.VOLTAGE_DEV_TRAIN'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'VOLTAGE_DEV',
  LABEL_COLNAME => '');

CREATE OR REPLACE TABLE ML.VOLTAGE_DEV_ANOMALIES AS
SELECT SERIES::VARCHAR AS ENTITY_ID, TS::DATE AS EVENT_DATE, Y AS VOLTAGE_DEV, FORECAST AS EXPECTED,
       LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, PERCENTILE
FROM TABLE(ML.VOLTAGE_DEV_ANOMALY_MODEL!DETECT_ANOMALIES(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.VOLTAGE_DEV_DETECT'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'VOLTAGE_DEV'));

-- ---------- Semantic view ----------
CREATE OR REPLACE SEMANTIC VIEW APP.GRID_INTEGRATION_ANALYTICS
  TABLES (
    substations AS CURATED.PERFORMANCE_SUMMARY PRIMARY KEY (ENTITY_ID)
      WITH SYNONYMS = ('entities', 'substations', 'grid connection points', 'connection substations', 'renewable connections')
      COMMENT = 'One row per grid connection substation (entity), 90-day totals',
    risk AS ML.GRID_EVENT_RISK_SCORES PRIMARY KEY (ENTITY_ID)
      COMMENT = 'Latest next-7-day grid event probability per substation',
    causes AS CURATED.GRID_EVENT_CAUSES PRIMARY KEY (ROOT_CAUSE)
      COMMENT = 'Grid events by root cause, 90 days',
    daily AS CURATED.TREND_ANALYSIS PRIMARY KEY (METRIC_DATE)
      COMMENT = 'Network-wide totals per day'
  )
  RELATIONSHIPS (risk_substation AS risk (ENTITY_ID) REFERENCES substations)
  FACTS (
    substations.in_limit_f AS IN_LIMIT_SAMPLES,
    substations.samples_f AS SCADA_SAMPLES,
    substations.checks_f AS PROTECTION_CHECKS,
    substations.alarms_f AS PROTECTION_ALARMS,
    substations.grid_events_f AS GRID_EVENT_COUNT,
    substations.downtime_hours_f AS DOWNTIME_HOURS,
    substations.operating_hours_f AS OPERATING_HOURS,
    substations.planned_hours_f AS PLANNED_HOURS,
    risk.grid_event_prob_f AS GRID_EVENT_PROB_7D,
    causes.cause_grid_events_f AS GRID_EVENT_COUNT,
    causes.cause_out_of_limit_f AS OUT_OF_LIMIT_SAMPLES,
    causes.cause_hours_f AS DOWNTIME_HOURS,
    daily.day_in_limit_f AS IN_LIMIT_SAMPLES,
    daily.day_samples_f AS SCADA_SAMPLES,
    daily.day_grid_events_f AS GRID_EVENT_COUNT
  )
  DIMENSIONS (
    substations.substation_id AS ENTITY_ID WITH SYNONYMS = ('substation', 'entity', 'entity id', 'connection point code'),
    substations.substation_name AS ENTITY_NAME,
    substations.region AS REGION WITH SYNONYMS = ('region', 'city', 'province', 'renewable hub') COMMENT = 'Vietnam city',
    substations.connection_type AS CATEGORY WITH SYNONYMS = ('connection type', 'plant type', 'category'),
    risk.risk_band AS RISK_BAND COMMENT = 'High >= 0.5, Medium >= 0.25, else Low',
    risk.scored_as_of AS SCORED_AS_OF,
    causes.root_cause AS ROOT_CAUSE,
    daily.metric_date AS METRIC_DATE
  )
  METRICS (
    substations.substation_count AS COUNT(substations.substation_id) WITH SYNONYMS = ('number of entities', 'entity count', 'number of substations'),
    substations.in_limit_sample_pct AS 100 * SUM(substations.in_limit_f) / NULLIF(SUM(substations.samples_f), 0)
      WITH SYNONYMS = ('in-limit rate', 'grid code compliance') COMMENT = 'In-limit SCADA samples / SCADA samples',
    substations.total_grid_events AS SUM(substations.grid_events_f) WITH SYNONYMS = ('grid events', 'connection events'),
    substations.protection_alarms_per_1k AS 1000 * SUM(substations.alarms_f) / NULLIF(SUM(substations.checks_f), 0),
    substations.total_scada_samples AS SUM(substations.samples_f) WITH SYNONYMS = ('sample volume', 'scada samples'),
    substations.total_protection_checks AS SUM(substations.checks_f),
    substations.connection_availability_rate AS 100 * SUM(substations.operating_hours_f) / NULLIF(SUM(substations.planned_hours_f), 0),
    substations.total_downtime_hours AS SUM(substations.downtime_hours_f),
    risk.avg_grid_event_prob AS AVG(risk.grid_event_prob_f),
    causes.cause_grid_events AS SUM(causes.cause_grid_events_f),
    causes.cause_out_of_limit_samples AS SUM(causes.cause_out_of_limit_f),
    causes.cause_downtime_hours AS SUM(causes.cause_hours_f),
    daily.daily_in_limit_pct AS 100 * SUM(daily.day_in_limit_f) / NULLIF(SUM(daily.day_samples_f), 0),
    daily.daily_scada_samples AS SUM(daily.day_samples_f),
    daily.daily_grid_events AS SUM(daily.day_grid_events_f)
  )
  COMMENT = 'Synthetic Vietnam renewable grid integration analytics (demo)';

-- ---------- Cortex Agent ----------
CREATE OR REPLACE AGENT APP.GRID_INTEGRATION_AGENT
  COMMENT = 'Grid integration assistant over a synthetic Vietnam renewable grid connection network'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  response: "Answer only from tool results. State that data is synthetic. Give substation IDs and numbers with units."
  orchestration: "Use grid_analyst for in-limit SCADA samples, grid events, protection alarms, sample volume, substations, regions, risk and root causes. Use sop_search for grid event response procedures."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: grid_analyst
      description: "In-limit SCADA samples, grid events, protection alarms per 1,000 checks, SCADA sample volume, connection availability, root causes and event-risk scores per substation"
  - tool_spec:
      type: cortex_search
      name: sop_search
      description: "Synthetic grid event response SOPs by connection type and cause"
tool_resources:
  grid_analyst:
    semantic_view: __DEMO_DB__.APP.GRID_INTEGRATION_ANALYTICS
    execution_environment:
      type: warehouse
      warehouse: __DEMO_WH__
  sop_search:
    name: __DEMO_DB__.SEARCH.SUBSTATION_SOP_SEARCH
    max_results: 3
    id_column: DOC_ID
    title_column: TITLE
$$;

-- ---------- Live-telemetry alert ----------
CREATE TABLE IF NOT EXISTS APP.ALERT_LOG (
  ALERTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), SUBSTATION_ID VARCHAR,
  EVENT_TS TIMESTAMP_NTZ, VOLTAGE_DEV_PCT FLOAT, TRANSFORMER_LOAD_PCT FLOAT, SOP_HINT VARCHAR);

CREATE OR REPLACE NOTIFICATION INTEGRATION VN_RENEWABLE_GRID_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE ALLOWED_RECIPIENTS = ('__ALERT_EMAIL__');

CREATE OR REPLACE PROCEDURE APP.LOG_LIVE_ALARMS()
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  n NUMBER;
BEGIN
  INSERT INTO APP.ALERT_LOG (SUBSTATION_ID, EVENT_TS, VOLTAGE_DEV_PCT, TRANSFORMER_LOAD_PCT, SOP_HINT)
    SELECT t.SUBSTATION_ID, t.EVENT_TS, t.VOLTAGE_DEV_PCT, t.TRANSFORMER_LOAD_PCT,
           'Check ' || h.CATEGORY || ' SOPs; current risk band ' || COALESCE(r.RISK_BAND, 'n/a')
    FROM RAW.LIVE_TELEMETRY t
    JOIN RAW.SUBSTATIONS h ON h.ID = t.SUBSTATION_ID
    LEFT JOIN ML.GRID_EVENT_RISK_SCORES r ON r.ENTITY_ID = t.SUBSTATION_ID
    WHERE t.STATUS = 'ALARM'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.SUBSTATION_ID = t.SUBSTATION_ID AND l.EVENT_TS = t.EVENT_TS);
  n := SQLROWCOUNT;
  IF (n > 0) THEN
    CALL SYSTEM$SEND_EMAIL('VN_RENEWABLE_GRID_EMAIL_INT', '__ALERT_EMAIL__',
      '[Demo] Vietnam renewable grid connection alarm',
      'New live-telemetry alarms logged in APP.ALERT_LOG: ' || :n || '. Data is synthetic.');
  END IF;
  RETURN n;
END;
$$;

CREATE OR REPLACE ALERT APP.LIVE_ALARM_ALERT
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM RAW.LIVE_TELEMETRY t
    WHERE t.STATUS = 'ALARM'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.SUBSTATION_ID = t.SUBSTATION_ID AND l.EVENT_TS = t.EVENT_TS)))
  THEN CALL APP.LOG_LIVE_ALARMS();

-- ---------- On-demand refresh DAG (suspended; run with EXECUTE TASK APP.TASK_REFRESH_CURATED) ----------
CREATE OR REPLACE PROCEDURE APP.REFRESH_CURATED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  ALTER DYNAMIC TABLE CURATED.PERFORMANCE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.TREND_ANALYSIS REFRESH;
  ALTER DYNAMIC TABLE CURATED.GRID_EVENT_CAUSES REFRESH;
  ALTER DYNAMIC TABLE CURATED.KPI_SUMMARY REFRESH;
  RETURN 'refreshed';
END;
$$;

CREATE OR REPLACE TASK APP.TASK_REFRESH_CURATED
  WAREHOUSE = __DEMO_WH__
AS
  CALL APP.REFRESH_CURATED();

CREATE OR REPLACE TASK APP.TASK_RESCORE_RISK
  WAREHOUSE = __DEMO_WH__
  AFTER APP.TASK_REFRESH_CURATED
AS
  CREATE OR REPLACE TABLE ML.GRID_EVENT_RISK_SCORES COPY GRANTS AS
  WITH latest AS (
    SELECT * FROM ML.GRID_EVENT_FEATURES QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_ID ORDER BY EVENT_DATE DESC) = 1
  ), p AS (
    SELECT ENTITY_ID, EVENT_DATE,
           ML.GRID_EVENT_RISK_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(
             'CATEGORY', CATEGORY, 'AGE_YEARS', AGE_YEARS, 'VOLTAGE_DEV_PCT', VOLTAGE_DEV_PCT,
             'TRANSFORMER_LOAD_PCT', TRANSFORMER_LOAD_PCT, 'VOLTAGE_DEV_7D', VOLTAGE_DEV_7D, 'GRID_EVENTS_30D', GRID_EVENTS_30D)) AS PRED
    FROM latest
  )
  SELECT ENTITY_ID, EVENT_DATE AS SCORED_AS_OF, ROUND(PRED:probability:GRID_EVENT::FLOAT, 4) AS GRID_EVENT_PROB_7D,
         CASE WHEN PRED:probability:GRID_EVENT::FLOAT >= 0.5 THEN 'High'
              WHEN PRED:probability:GRID_EVENT::FLOAT >= 0.25 THEN 'Medium' ELSE 'Low' END AS RISK_BAND,
         CURRENT_TIMESTAMP() AS SCORED_AT
  FROM p;
