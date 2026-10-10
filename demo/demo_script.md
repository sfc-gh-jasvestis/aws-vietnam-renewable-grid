# Vietnam Renewable Grid Integration Monitor

**Vietnam - Renewable Grid Integration**
Use case: In-limit SCADA samples, event traceability and grid event risk

> Grid integration monitoring for a fictional grid operator's 30 renewable connection substations across 6 Vietnam cities (utility solar, onshore wind, nearshore wind, battery storage and solar-storage hybrid connections): dynamic tables, a holdout-evaluated event-risk classifier, a SCADA sample volume forecast and grounded AI answers.

## Why Snowflake

- **Dynamic tables** reconcile in-limit SCADA samples, protection alarms and connection availability from RAW substation data, with checks in `run_core.py`
- **Event-risk classification** gives a holdout-evaluated next-7-day grid event probability per substation
- **SCADA sample volume forecast** projects 14 days of network-wide SCADA samples with prediction intervals
- **Grounded AI**: the Cortex Agent (Analyst over a semantic view, plus Search over SOPs) shows its SQL and SOP citations
- **Live telemetry**: a native simulator (Snowflake only) or IoT Core, S3 and Snowpipe (AWS build), then an alert and email

## What is built

| | |
|---|---|
| Dimension table | `RAW.SUBSTATIONS` (30 rows) |
| Fact table | `RAW.SUBSTATION_DAILY` (2,700 substation-days, 90 days) |
| Curated layer | `CURATED.KPI_SUMMARY`, `PERFORMANCE_SUMMARY`, `GRID_EVENT_CAUSES`, `TREND_ANALYSIS` |
| ML | `ML.GRID_EVENT_RISK_SCORES`, `ML.GRID_EVENT_RISK_HOLDOUT_METRICS`, `ML.VOLUME_FORECAST`, `ML.VOLTAGE_DEV_ANOMALIES` |

Cities: Phan Rang-Thap Cham, Quy Nhon, Bac Lieu, Tuy Hoa, Phan Thiet, Buon Ma Thuot.
Connection types: Utility Solar Connection, Onshore Wind Connection, Nearshore Wind Connection, Battery Storage Connection, Solar-Storage Hybrid Connection.

## KPI cards (live from `CURATED.KPI_SUMMARY`; no fallback values)

| Card | Value from the seeded data |
|---|---|
| In-Limit SCADA Samples | 90.4% |
| Grid Events | 500 |
| Protection Alarms per 1k Checks | 18.32 |
| SCADA Samples | 3,286,308 |
| Connection Availability | 97.7% |
| Grid Connection Substations | 30 |
| Protection Spares Readiness | 78.8% |

Values are synthetic. A rebuild reproduces them because the data is HASH-seeded; dates are relative to the build day.

## Demo flow

1. Executive Cockpit: KPIs, daily in-limit SCADA samples, out-of-limit samples by event cause, substation table
2. Predictive: holdout metrics, risk bands, 14-day SCADA sample volume forecast, busbar voltage deviation anomalies
3. Substation Health: connection availability, protection spares readiness, PM compliance against in-limit SCADA samples, then generate the action memo
4. Live IoT: run `CALL APP.SIMULATE_TELEMETRY(20)` (Snowflake only) or `python aws/publish_telemetry.py --count 20` (AWS build). Then run `EXECUTE ALERT APP.LIVE_ALARM_ALERT` and show the alert log and email.
5. Ask AI: the Cortex Agent answers metric questions through the semantic view and cites SOPs from Cortex Search. The SQL is shown.
6. QuickSight (AWS build): the same Snowflake tables through DIRECT_QUERY
7. Architecture: both builds side by side

## Talking points

- Per-substation in-limit rate ranges from 85.8% to 92.9%. Phan Rang-Thap Cham, the largest renewable hub in the network, is the lowest city at 89.6%.
- Export cable faults push the most SCADA samples out of limit of the 14 event causes.
- The risk model is evaluated on a time-based holdout: precision 0.68 and recall 0.75 at 0.5, against a 0.55 base rate. Present it as triage, not a guarantee.
- The Phan Thiet transmission line outage and the Quy Nhon tropical storm are excluded from event labels, because they are city-wide events, not substation-driven.
- Event traceability: SOPs require logging the affected feeders and confirming SCADA values against the revenue meter, and each substation-day records in-limit samples and dispatch compliance.

## Business impact

Use only the sourced references in `README.md` (Business Impact).
