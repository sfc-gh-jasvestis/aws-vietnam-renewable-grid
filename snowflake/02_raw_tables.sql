-- Synthetic substation-day grid telemetry for a fictional Vietnam renewable grid operator.
-- Nothing is seeded as a prediction. Randomness is HASH-seeded, so every rebuild is
-- reproducible: per-substation SCADA sample volume, asset age and event propensity,
-- a weekly planned maintenance outage window and a new-plant energisation peak,
-- wear between preventive-maintenance (PM) visits, connection-type-weighted grid
-- event causes, and two regional events.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

CREATE TABLE RAW.SUBSTATIONS AS
WITH substations AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS SUBSTATION_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 30))
), draws AS (
  SELECT SUBSTATION_INDEX,
         MOD(ABS(HASH(SUBSTATION_INDEX, 'vnrgrid-age')), 1000000) / 1e6 AS U_AGE,
         MOD(ABS(HASH(SUBSTATION_INDEX, 'vnrgrid-rate')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(SUBSTATION_INDEX, 'vnrgrid-pm')), 1000000) / 1e6 AS U_PM,
         MOD(ABS(HASH(SUBSTATION_INDEX, 'vnrgrid-discipline')), 1000000) / 1e6 AS U_DISCIPLINE,
         MOD(ABS(HASH(SUBSTATION_INDEX, 'vnrgrid-capacity')), 1000000) / 1e6 AS U_CAPACITY
  FROM substations
)
SELECT 'GC-' || LPAD(SUBSTATION_INDEX::VARCHAR, 4, '0') AS ID,
       'Synthetic grid connection substation ' || LPAD(SUBSTATION_INDEX::VARCHAR, 4, '0') AS NAME,
       -- Deterministic spread (7 and 5 are coprime): every city and connection type is
       -- present, with Phan Rang-Thap Cham the largest renewable hub.
       CASE MOD(SUBSTATION_INDEX, 7) WHEN 0 THEN 'Phan Rang-Thap Cham' WHEN 1 THEN 'Phan Rang-Thap Cham'
            WHEN 2 THEN 'Quy Nhon' WHEN 3 THEN 'Bac Lieu' WHEN 4 THEN 'Tuy Hoa'
            WHEN 5 THEN 'Phan Thiet' ELSE 'Buon Ma Thuot' END AS REGION,
       CASE MOD(SUBSTATION_INDEX, 5) WHEN 0 THEN 'Utility Solar Connection' WHEN 1 THEN 'Onshore Wind Connection'
            WHEN 2 THEN 'Nearshore Wind Connection' WHEN 3 THEN 'Battery Storage Connection'
            ELSE 'Solar-Storage Hybrid Connection' END AS CATEGORY,
       SUBSTATION_INDEX,
       ROUND(1 + U_AGE * 11, 1) AS AGE_YEARS,
       -- Base daily event probability 0.6%-3.4%; ~15% of substations are chronic (x3).
       (0.006 + U_RATE * 0.028) * IFF(U_RATE > 0.85, 3, 1) AS BASE_GRID_EVENT_RATE,
       7 * (1 + FLOOR(U_PM * 3)) AS PM_INTERVAL_DAYS,
       0.55 + U_DISCIPLINE * 0.43 AS PM_COMPLETION_PROB,
       -- SCADA samples per day at the connection point (scan-rate dependent).
       ROUND(CASE MOD(SUBSTATION_INDEX, 5) WHEN 0 THEN 1440 WHEN 1 THEN 1700 WHEN 2 THEN 1900
                  WHEN 3 THEN 1150 ELSE 1320 END * (0.8 + U_CAPACITY * 0.4)) AS DAILY_CAPACITY,
       'Active' AS STATUS
FROM draws;

CREATE TABLE RAW.SUBSTATION_DAILY AS
WITH days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS DAY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 90))
), regional_events AS (
  -- Two city-wide events in the window.
  SELECT * FROM VALUES (31, 'Phan Thiet', 'Transmission line outage', 9.0),
                       (63, 'Quy Nhon', 'Tropical storm', 7.5)
    AS o(DAY_INDEX, REGION, EVENT_CAUSE, HOURS)
), base AS (
  SELECT h.ID AS ENTITY_ID, h.SUBSTATION_INDEX, h.CATEGORY, h.REGION, h.AGE_YEARS,
         h.BASE_GRID_EVENT_RATE, h.PM_INTERVAL_DAYS, h.PM_COMPLETION_PROB, h.DAILY_CAPACITY,
         d.DAY_INDEX,
         DATEADD('day', d.DAY_INDEX - 89, CURRENT_DATE()) AS EVENT_DATE,
         24.0 AS PLANNED_HOURS,
         MOD(d.DAY_INDEX + h.SUBSTATION_INDEX * 3, h.PM_INTERVAL_DAYS) AS DAYS_SINCE_PM,
         MOD(ABS(HASH(h.ID, d.DAY_INDEX, 'vnrgrid-evt')), 1000000) / 1e6 AS U_EVT,
         MOD(ABS(HASH(h.ID, d.DAY_INDEX, 'vnrgrid-down')), 1000000) / 1e6 + 1e-6 AS U_DOWN,
         MOD(ABS(HASH(h.ID, d.DAY_INDEX, 'vnrgrid-cause')), 1000000) / 1e6 AS U_CAUSE,
         MOD(ABS(HASH(h.ID, d.DAY_INDEX, 'vnrgrid-pmdone')), 1000000) / 1e6 AS U_PMDONE,
         MOD(ABS(HASH(h.ID, d.DAY_INDEX, 'vnrgrid-volume')), 1000000) / 1e6 AS U_VOLUME,
         MOD(ABS(HASH(h.ID, d.DAY_INDEX, 'vnrgrid-noise')), 1000000) / 1e6 AS U_NOISE,
         MOD(ABS(HASH(h.ID, d.DAY_INDEX, 'vnrgrid-hit')), 1000000) / 1e6 AS U_HIT,
         e.EVENT_CAUSE, e.HOURS AS EVENT_HOURS
  FROM RAW.SUBSTATIONS h CROSS JOIN days d
  LEFT JOIN regional_events e ON e.DAY_INDEX = d.DAY_INDEX AND e.REGION = h.REGION
), loaded AS (
  SELECT *,
         IFF(DAYS_SINCE_PM = 0, 1, 0) AS PM_DUE,
         IFF(DAYS_SINCE_PM = 0 AND U_PMDONE < PM_COMPLETION_PROB, 1, 0) AS PM_COMPLETED,
         -- Switchgear and converter wear rises between PM visits; weak PM discipline carries wear over.
         DAYS_SINCE_PM / PM_INTERVAL_DAYS + (1 - PM_COMPLETION_PROB) AS WEAR,
         -- Congestion episode (high renewable output on a constrained corridor):
         -- 6 of every 19 days per substation (staggered, keyed to the day index).
         IFF(MOD(DAY_INDEX + SUBSTATION_INDEX * 4, 19) < 6, 1, 0) AS STRESS,
         -- Volume: a weekly planned maintenance window takes some feeders out of scan, and a
         -- new-plant energisation peak on day 52 (+31%) eases over 3 days.
         ROUND(DAILY_CAPACITY * (0.70 + 0.25 * U_VOLUME)
               * IFF(MOD(DAY_INDEX, 7) = 5, 0.81, 1.0)
               * CASE DAY_INDEX - 52 WHEN 0 THEN 1.31 WHEN 1 THEN 1.19 WHEN 2 THEN 1.08 ELSE 1.0 END) AS SCADA_SAMPLES
  FROM base
), events AS (
  SELECT *, SCADA_SAMPLES / DAILY_CAPACITY AS LOAD_RATIO,
         LEAST(0.5, BASE_GRID_EVENT_RATE * (0.4 + 1.6 * WEAR) * (0.3 + SCADA_SAMPLES / DAILY_CAPACITY)
                    * (1 + AGE_YEARS / 18) * (1 + 3.0 * STRESS)) AS P_EVT
  FROM loaded
), counted AS (
  SELECT *,
         CASE WHEN EVENT_HOURS IS NOT NULL THEN 1
              WHEN U_EVT < P_EVT / 4 THEN 2
              WHEN U_EVT < P_EVT THEN 1
              ELSE 0 END AS GRID_EVENT_COUNT
  FROM events
), timed AS (
  SELECT *,
         -- Constrained or disconnected hours: exponential, mean depends on connection type.
         CASE WHEN GRID_EVENT_COUNT = 0 THEN 0.0
              WHEN EVENT_HOURS IS NOT NULL THEN EVENT_HOURS
              ELSE LEAST(20.0, ROUND(GRID_EVENT_COUNT * (0.5 - LN(U_DOWN) *
                   CASE CATEGORY WHEN 'Utility Solar Connection' THEN 2.1 WHEN 'Onshore Wind Connection' THEN 2.6
                                 WHEN 'Nearshore Wind Connection' THEN 3.2 WHEN 'Battery Storage Connection' THEN 1.7
                                 ELSE 2.4 END), 1))
         END AS DOWNTIME_HOURS,
         -- In-limit rate (SCADA samples with voltage, frequency, power factor, harmonics and
         -- ramp rate all inside the connection-agreement band): base by connection type,
         -- minus wear and overload, minus the event hit.
         LEAST(0.995, GREATEST(0.50,
           CASE CATEGORY WHEN 'Utility Solar Connection' THEN 0.957 WHEN 'Onshore Wind Connection' THEN 0.946
                         WHEN 'Nearshore Wind Connection' THEN 0.939 WHEN 'Battery Storage Connection' THEN 0.971
                         ELSE 0.952 END
             - 0.028 * WEAR - 0.05 * GREATEST(0, LOAD_RATIO - 0.9) - 0.012 * U_NOISE
             - GRID_EVENT_COUNT * (0.06 + 0.12 * U_HIT))) AS IN_LIMIT_RATE
  FROM counted
)
SELECT ENTITY_ID || '-' || TO_CHAR(EVENT_DATE, 'YYYYMMDD') AS EVENT_ID,
       ENTITY_ID, EVENT_DATE, PLANNED_HOURS, DOWNTIME_HOURS,
       PLANNED_HOURS - DOWNTIME_HOURS AS OPERATING_HOURS,
       GRID_EVENT_COUNT,
       CASE WHEN GRID_EVENT_COUNT = 0 THEN 'None'
            WHEN EVENT_CAUSE IS NOT NULL THEN EVENT_CAUSE
            WHEN CATEGORY = 'Utility Solar Connection' THEN IFF(U_CAUSE < 0.45, 'Cloud-cover ramp', IFF(U_CAUSE < 0.75, 'Inverter fleet trip', 'Reactive power shortfall'))
            WHEN CATEGORY = 'Onshore Wind Connection' THEN IFF(U_CAUSE < 0.5, 'Wind gust ramp', IFF(U_CAUSE < 0.8, 'Turbine converter fault', 'Fault ride-through trip'))
            WHEN CATEGORY = 'Nearshore Wind Connection' THEN IFF(U_CAUSE < 0.55, 'Export cable fault', 'Harmonic distortion')
            WHEN CATEGORY = 'Battery Storage Connection' THEN IFF(U_CAUSE < 0.6, 'Battery cooling fault', 'State-of-charge limit')
            ELSE IFF(U_CAUSE < 0.55, 'Plant controller fault', 'Metering calibration drift') END AS ROOT_CAUSE,
       PM_DUE, PM_COMPLETED,
       SCADA_SAMPLES,
       FLOOR(SCADA_SAMPLES * IN_LIMIT_RATE) AS IN_LIMIT_SAMPLES,
       ROUND(SCADA_SAMPLES * (3.0 + U_VOLUME * 1.2)) AS PROTECTION_CHECKS,
       ROUND(SCADA_SAMPLES * (3.0 + U_VOLUME * 1.2) * (0.004 + 0.011 * WEAR + 0.024 * GRID_EVENT_COUNT + 0.005 * U_NOISE)) AS PROTECTION_ALARMS,
       -- Busbar voltage deviation from nominal (%): rises with wear, overload, congestion and events.
       ROUND(0.85 + 0.62 * WEAR + 0.80 * GREATEST(0, LOAD_RATIO - 0.8) + 0.70 * STRESS + 0.90 * GRID_EVENT_COUNT + U_NOISE * 0.25, 3) AS VOLTAGE_DEV_PCT,
       ROUND(LEAST(100, 100 * LOAD_RATIO * (0.78 + 0.14 * U_NOISE) + 9 * STRESS + 5 * GRID_EVENT_COUNT), 1) AS TRANSFORMER_LOAD_PCT,
       ROUND(85.0 + 12.0 * IN_LIMIT_RATE + 1.8 * U_NOISE, 1) AS DISPATCH_COMPLIANCE_PCT,
       CURRENT_TIMESTAMP() AS LOADED_AT
FROM timed;

-- Protection and spares readiness per substation (snapshot): units required versus on hand.
CREATE TABLE RAW.EQUIPMENT_READINESS AS
SELECT ID AS ENTITY_ID,
       CASE CATEGORY WHEN 'Utility Solar Connection' THEN 'Inverter spare module' WHEN 'Onshore Wind Connection' THEN 'Converter spare module'
                     WHEN 'Nearshore Wind Connection' THEN 'Cable joint kit' WHEN 'Battery Storage Connection' THEN 'Battery cooling unit'
                     ELSE 'Power quality meter' END AS EQUIPMENT_TYPE,
       4 + MOD(ABS(HASH(ID, 'vnrgrid-req')), 19) AS REQUIRED_QTY,
       FLOOR((4 + MOD(ABS(HASH(ID, 'vnrgrid-req')), 19)) * (0.66 + MOD(ABS(HASH(ID, 'vnrgrid-avail')), 1000) / 1000 * 0.38)) AS ON_HAND_QTY,
       MOD(ABS(HASH(ID, 'vnrgrid-order')), 4) AS ON_ORDER_QTY,
       CURRENT_DATE() AS SNAPSHOT_DATE
FROM RAW.SUBSTATIONS;
