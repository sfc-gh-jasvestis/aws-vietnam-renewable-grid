# Grid Integration

Grid Integration for Vietnam - ML.FORECAST and Dynamic Tables power real-time grid integration intelligence for renewable energy in Hanoi (EVN NLD).

## Architecture

Vietnam renewable energy faces increasing complexity in grid integration. Decision-makers in Hanoi (EVN NLD) need real-time intelligence and ML-powered recommendations.

```mermaid
flowchart LR
    S3[S3 Data Landing] --> SP[Snowpipe]
    SPS --> RAW
    RAW --> DT[Dynamic Tables]
    DT --> ML[ML Functions]
    DT --> SEARCH[Cortex Search]
    DT --> SV[Semantic View]
    SV --> AGENT[Cortex Agent]
    SEARCH --> AGENT
    DT --> APP[React App SPCS]
    SM[SageMaker] --> DT
    BR[Bedrock] --> APP
    DT --> QS[QuickSight + Q]
```

## Snowflake Capabilities

| Capability | Implementation |
|-----------|---------------|
| Dynamic Tables | PERFORMANCE_DASHBOARD / TREND_ANALYTICS / FORECAST_INPUT / OPERATIONAL_RISK |
| ML Functions | ML.FORECAST + ML.ANOMALY_DETECTION |
| Cortex AI | COMPLETE, SUMMARIZE, AI_CLASSIFY |
| Cortex Search | 100 documents indexed |
| Cortex Agent | GRID_INTEGRATION_AGENT |
| Semantic View | GRID_INTEGRATION_ANALYTICS |
| React App (SPCS) | 5 tabs + DemoGuide |


## AWS Services

| Service | Role in Demo |
|---------|-------------|
| AWS IoT Core | Ingest real-time data from renewable energy systems |
| Amazon SageMaker | Grid Integration ML models |
| AWS Glue | ETL and data transformation |
| Apache Iceberg (S3) | Open table format for data sharing |
| Amazon Bedrock (Claude) | Generate grid integration recommendations |
| Amazon QuickSight + Q | Grid Integration dashboard with NL queries |


## Personas

| Persona | Role | Key Questions |
|---------|------|---------------|
| **Dr. Le Thanh Binh** | VP Grid Operations | "What are the key grid integration metrics?" "Which areas need attention?" |
| **Nguyen Thi Huyen** | Dispatch Engineer | "Show me the trend analysis." "Which operations are underperforming?" |


## Data

| Table | Rows | Description |
|-------|------|-------------|
| OPERATIONS | 100,000 | Core operational records for grid integration |
| METRICS | 500,000 | Time-series performance metrics |
| ASSETS | 5,000 | Asset and entity master data |
| EVENTS | 200,000 | Operational events and incidents |
| DOCUMENTS | 100 | SOPs, reports, and compliance docs |


## Build Instructions

### Prerequisites
- Snowflake account with ACCOUNTADMIN access
- Cortex AI enabled (ML Functions, Search, Agent)
- Warehouse: GRID_WH (Medium)
- AWS CLI with access (us-west-2)

### Deployment

```bash
snowsql -f snowflake/00_setup.sql
snowsql -f snowflake/01_marketplace_install.sql
snowsql -f snowflake/02_raw_tables.sql
snowsql -f snowflake/03_staging.sql
snowsql -f snowflake/04_dynamic_tables.sql
snowsql -f snowflake/05_search.sql
snowsql -f snowflake/06_ml_models.sql
snowsql -f snowflake/07_semantic_view.sql
snowsql -f snowflake/08_agent.sql
```

### React App (SPCS)
```bash
cd app && npm ci && npm run build
docker build -t aws-vietnam-renewable-grid-app .
docker push bdiqc8sm-default.registry.snowflakecomputing.com/grid_integration/app/aws_vietnam_renewable_grid/app:latest
```

### Demo Mode
Open the app URL with `?demo=true` for presenter view.

## Build Modes

### Snowflake Only
Run scripts 00-08 (skip AWS-specific integration). Uses:
- **Snowpipe Streaming SDK** instead of AWS IoT Core
- **ML.FORECAST + ML.ANOMALY_DETECTION** instead of Amazon SageMaker
- **Dynamic Tables** instead of AWS Glue
- **Snowflake-managed Iceberg Tables** instead of Apache Iceberg (S3)
- **Cortex Complete** instead of Amazon Bedrock (Claude)
- **Snowflake Intelligence (Cortex Analyst)** instead of Amazon QuickSight + Q

### Full AWS + Snowflake
Run all scripts including AWS integration. Deploy QuickSight dashboard from `quicksight/`.

## Business Impact

Industry research and Snowflake customer outcomes:
- **Vietnam's peak electricity demand reached 48GW in 2024 — growing 8-10% annually, fastest in ASEAN** — [EVN Annual Report](https://www.evn.com.vn/d6/news/Annual-Report-2024-141-163-2.aspx)
- **Renewable intermittency causes 20-30% curtailment in Central Vietnam — costing producers $500M annually** — [World Bank Vietnam Energy](https://www.worldbank.org/en/country/vietnam/publication/vietnam-energy-sector-assessment)
- **Smart grid investment in Vietnam projected at $7B through 2030 for AMI, SCADA, and storage** — [ADB Energy Report](https://www.adb.org/publications/viet-nam-energy-sector-assessment)
- **National Grid ESO (UK) uses Snowflake to balance 30GW of renewable generation in real-time** — [Snowflake Energy](https://www.snowflake.com/en/data-cloud/energy-and-utilities/)

## Key Demo Numbers

- **100K operations** tracked in Hanoi (EVN NLD)
- **500K metrics** time-series data points
- **5K assets** monitored
- **100 docs** searchable


## License

Apache 2.0 — See [LICENSE](LICENSE) for details.

This is a personal demo project and is not an official Snowflake offering. It comes with no support or warranty.