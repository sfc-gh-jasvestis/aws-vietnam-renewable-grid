# Grid Integration

**Vietnam - Renewable Energy**
Use case: Grid Integration

> Grid Integration for Vietnam - ML.FORECAST and Dynamic Tables power real-time grid integration intelligence for renewable energy in Hanoi (EVN NLD).

## Why Snowflake

Snowflake delivers grid integration intelligence for Vietnamese renewable energy - Dynamic Tables maintain real-time dashboards, ML.FORECAST projects key metrics, and Cortex AI generates recommendations

- **ML.FORECAST for grid integration** - Only demo for Vietnamese renewable energy
- **ML.ANOMALY_DETECTION early warning** - Detects deviations before impact
- **AI recommendations** - Cortex AI actionable guidance
- **Vietnamese context** - Local names, VND economics

## What is deployed

| | |
|---|---|
| Database | `VIETNAM_RENEWABLE_GRID` |
| Service | `VIETNAM_RENEWABLE_GRID_APP` |
| Compute pool | `SEA_DEMOS_VIETNAM_POOL` |
| Dimension table | `RAW.SUBSTATIONS` (20 rows) |
| Fact table | `RAW.LOAD_READINGS` (250,000 rows, 90 days) |
| Curated layer | `CURATED.PERFORMANCE_SUMMARY`, `CURATED.TREND_ANALYSIS`, `CURATED.KPI_SUMMARY` |
| Currency | VND (₫) |

Regions in play: Ho Chi Minh City, Hanoi, Binh Duong, Dong Nai, Can Tho
Segments: Solar Feed-In, Wind Feed-In, Battery Storage, Curtailment

Dynamic tables are created suspended and refreshed on demand:

```bash
./refresh_demo_data.sh VIETNAM_RENEWABLE_GRID
```

## KPI cards

Every card below is served live from `CURATED.KPI_SUMMARY`. The app keeps the
original literal as a fallback, so it still renders if Snowflake is unreachable.

| Card | Value | Backed by |
|---|---|---|
| RE Penetration | `28%` | average per event |
| Grid Frequency | `50.01 Hz` | average per event |
| Curtailment (MTD) | `420 GWh` | total across Substations |
| Substations | `847` | total across Substations |
| Peak RE (Today) | `42%` | average per event |
| Ramp Rate | `1.2 GW/hr` | average per event |
| Storage Online | `847 MWh` | average per event |


## Demo flow

1. Overview
2. Analytics
3. AI Intelligence
4. Ask AI
5. Architecture

## Talking points

- **100K operations** - tracked in Hanoi (EVN NLD)
- **500K metrics** - time-series data points
- **5K assets** - monitored
- **100 docs** - searchable

## Business impact

- Vietnam renewable energy sector growing rapidly (GSO Vietnam)
- AI improves outcomes 15-30% (McKinsey)
- Vietnam FDI strong in this sector (MPI)
- Real-time analytics reduces response 60-80% (Gartner)

---
Generated from `generator/demo_specs/aws-vietnam-renewable-grid.json`. Do not hand-edit: run
`python3 generator/gen_repo_docs.py aws-vietnam-renewable-grid` instead.
