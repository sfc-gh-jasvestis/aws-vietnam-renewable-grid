import { NextResponse } from 'next/server';
import { executeQuery } from '@/lib/snowflake';
import { demoPlatform } from '@/lib/platform';

export const dynamic = 'force-dynamic';

// Only these fixed, read-only queries can run. The model never writes SQL; it
// only summarises rows returned here, so every answer is traceable to data.
const INTENTS: Record<string, { match: RegExp; sql: string }> = {
  gridEvents: {
    match: /event|in-limit|alarm|limit|worst|lowest|substation|connection/i,
    sql: `SELECT ENTITY_ID, ENTITY_NAME, REGION, CATEGORY, GRID_EVENT_COUNT, ROUND(IN_LIMIT_PCT, 2) AS IN_LIMIT_PCT
FROM CURATED.PERFORMANCE_SUMMARY
QUALIFY DENSE_RANK() OVER (ORDER BY GRID_EVENT_COUNT DESC) <= 2
ORDER BY GRID_EVENT_COUNT DESC, IN_LIMIT_PCT`,
  },
  causes: {
    match: /cause|root|why/i,
    sql: `SELECT ROOT_CAUSE, GRID_EVENT_COUNT, OUT_OF_LIMIT_SAMPLES, DOWNTIME_HOURS
FROM CURATED.GRID_EVENT_CAUSES ORDER BY OUT_OF_LIMIT_SAMPLES DESC LIMIT 5`,
  },
  kpis: {
    match: /.*/,
    sql: `SELECT TITLE, DISPLAY, SOURCE_WATERMARK FROM CURATED.KPI_SUMMARY ORDER BY SORT_ORDER`,
  },
};

const DEFINITIONS =
  'In-limit SCADA samples = sum(samples with voltage, frequency, power factor, harmonics and ramp rate all inside the connection-type band) / sum(SCADA samples). ' +
  'Protection alarms per 1k checks = 1000 * sum(protection alarms) / sum(protection checks). ' +
  'A grid event is a substation-day event (for example a cloud-cover ramp or a turbine converter fault) that pushed the connection point out of its band. ' +
  'All data is synthetic demo data.';

// provider 'cortex' = Snowflake AI_COMPLETE; 'bedrock' = Amazon Bedrock Claude
// via the external-access UDF APP.BEDROCK_GENERATE (aws/setup_aws.py).
async function summarise(question: string, rows: unknown[], provider: 'cortex' | 'bedrock' = 'cortex'): Promise<string> {
  const prompt =
    'You are a renewable grid integration analyst. Answer ONLY from the JSON rows and definitions below. ' +
    'If the rows do not answer the question, say so. Do not invent numbers. Keep it under 120 words.\n' +
    `Definitions: ${DEFINITIONS}\nRows: ${JSON.stringify(rows)}\nQuestion: ${question}`;
  const out = await executeQuery<{ R: string }>(
    provider === 'bedrock' ? 'SELECT APP.BEDROCK_GENERATE(?) AS R' : `SELECT AI_COMPLETE('claude-sonnet-4-5', ?) AS R`,
    [prompt],
  );
  const raw = String(out[0]?.R ?? '').trim();
  // AI_COMPLETE returns a JSON string literal; decode it when present.
  try {
    const parsed = JSON.parse(raw);
    return typeof parsed === 'string' ? parsed : raw;
  } catch {
    return raw;
  }
}

export async function POST(req: Request) {
  let body: any;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
  }
  const question = typeof body?.question === 'string' ? body.question.trim().slice(0, 2000) : '';
  const memo = body?.mode === 'memo';
  if (!memo && !question) return NextResponse.json({ error: 'Question required' }, { status: 400 });

  try {
    if (memo) {
      const provider = demoPlatform() === 'aws' ? 'bedrock' : 'cortex';
      const [kpis, gridEvents, causes, risk, bands] = await Promise.all([
        executeQuery(INTENTS.kpis.sql),
        executeQuery(INTENTS.gridEvents.sql),
        executeQuery(INTENTS.causes.sql),
        executeQuery(`SELECT ENTITY_ID, ROUND(GRID_EVENT_PROB_7D, 2) AS GRID_EVENT_PROB_7D, RISK_BAND
FROM ML.GRID_EVENT_RISK_SCORES ORDER BY GRID_EVENT_PROB_7D DESC LIMIT 5`),
        executeQuery(`SELECT RISK_BAND, COUNT(*) AS SUBSTATIONS FROM ML.GRID_EVENT_RISK_SCORES GROUP BY RISK_BAND`),
      ]);
      const rows = { kpis, topEventSubstations: gridEvents, topCauses: causes, top5ByRisk: risk, substationsPerRiskBand: bands };
      const answer = await summarise(
        'Draft a short action memo for the Grid Operations Director with 3 prioritised actions, citing the figures.',
        [rows],
        provider,
      );
      return NextResponse.json({ answer, sources: rows, provider: provider === 'bedrock' ? 'Amazon Bedrock (Claude Sonnet 4.5)' : 'Snowflake Cortex AI_COMPLETE (claude-sonnet-4-5)', draft: true, synthetic: true });
    }
    const key = Object.keys(INTENTS).find((k) => INTENTS[k].match.test(question))!;
    const rows = await executeQuery(INTENTS[key].sql);
    const answer = await summarise(question, rows);
    return NextResponse.json({ answer, sql: INTENTS[key].sql, sources: rows, synthetic: true });
  } catch (err) {
    console.error('ask route failed', err);
    return NextResponse.json({ error: 'AI service unavailable' }, { status: 503 });
  }
}
