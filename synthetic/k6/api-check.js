// Synthetic API test for demo-api: the pre-release gate (roadmap D9).
//
// Each iteration is one user journey: read service info -> create an order -> read it back.
// Thresholds turn the run into a pass/fail signal; k6 exits with code 99 when any fails.
//
//   k6 run -e BASE_URL=http://127.0.0.1:18080 -e SUMMARY_DIR=out synthetic/k6/api-check.js
//
// Environment: BASE_URL (required), RATE (journeys/s, default 4), DURATION (default 60s),
// P95_MS (latency budget per endpoint, default 300), SUMMARY_DIR (where summary files go).
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL;
const P95_MS = Number(__ENV.P95_MS || 300);
const SUMMARY_DIR = __ENV.SUMMARY_DIR || '.';

export const options = {
  scenarios: {
    journeys: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 4),
      timeUnit: '1s',
      duration: __ENV.DURATION || '60s',
      preAllocatedVUs: 8,
      maxVUs: 40,
    },
  },
  thresholds: {
    // Functional: (almost) every assertion must hold.
    checks: ['rate>0.99'],
    // Availability: transport errors and 4xx/5xx responses.
    http_req_failed: ['rate<0.01'],
    // Latency budget per endpoint (tagged with "name" below).
    'http_req_duration{name:GET /api/v1/info}': [`p(95)<${P95_MS}`],
    'http_req_duration{name:POST /api/v1/orders}': [`p(95)<${P95_MS}`],
    'http_req_duration{name:GET /api/v1/orders/:id}': [`p(95)<${P95_MS}`],
  },
};

export function setup() {
  if (!BASE) throw new Error('BASE_URL is required');
}

const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' }, timeout: '5s' };

export default function () {
  const info = http.get(`${BASE}/api/v1/info`, { tags: { name: 'GET /api/v1/info' }, timeout: '5s' });
  check(info, {
    'info: status 200': (r) => r.status === 200,
    'info: reports service and version': (r) => r.status === 200 && !!r.json('service') && !!r.json('version'),
  });

  const quantity = 1 + Math.floor(Math.random() * 3);
  const created = http.post(
    `${BASE}/api/v1/orders`,
    JSON.stringify({ sku: 'BOOK-001', quantity }),
    Object.assign({ tags: { name: 'POST /api/v1/orders' } }, JSON_HEADERS),
  );
  const ok = check(created, {
    'order: status 201': (r) => r.status === 201,
    'order: total = unit_price x quantity': (r) =>
      r.status === 201 && Math.abs(Number(r.json('total')) - Number(r.json('unit_price')) * quantity) < 0.005,
  });
  if (!ok || created.status !== 201) return;

  const id = created.json('id');
  const read = http.get(`${BASE}/api/v1/orders/${id}`, { tags: { name: 'GET /api/v1/orders/:id' }, timeout: '5s' });
  check(read, {
    'read-back: status 200': (r) => r.status === 200,
    'read-back: same order': (r) => r.status === 200 && r.json('id') === id && r.json('quantity') === quantity,
  });
}

// ---------------------------------------------------------------- summary
function fmt(n, unit) {
  return n === undefined ? '-' : `${Number(n).toFixed(unit === '%' ? 2 : 1)}${unit}`;
}

export function handleSummary(data) {
  const rows = [];
  let pass = true;
  for (const [metric, m] of Object.entries(data.metrics)) {
    for (const [expr, t] of Object.entries(m.thresholds || {})) {
      pass = pass && t.ok;
      let observed;
      if (m.type === 'rate') observed = fmt(m.values.rate * 100, '%');
      else if (expr.startsWith('p(95)')) observed = fmt(m.values['p(95)'], ' ms');
      else observed = JSON.stringify(m.values);
      rows.push({ metric, expr, observed, ok: t.ok });
    }
  }
  const checks = data.metrics.checks ? data.metrics.checks.values : { passes: 0, fails: 0 };
  const reqs = data.metrics.http_reqs ? data.metrics.http_reqs.values.count : 0;
  const verdict = pass ? 'PASS' : 'FAIL';

  const text = [
    `synthetic gate: ${verdict}  (base ${BASE}, ${reqs} requests, checks ${checks.passes} passed / ${checks.fails} failed)`,
    ...rows.map((r) => `  [${r.ok ? 'ok  ' : 'FAIL'}] ${r.metric}  ${r.expr}  observed ${r.observed}`),
  ].join('\n');

  const md = [
    `### Synthetic gate: ${pass ? 'PASS' : 'FAIL'}`,
    '',
    `Target \`${BASE}\` - ${reqs} requests - checks ${checks.passes} passed / ${checks.fails} failed`,
    '',
    '| Metric | Threshold | Observed | Result |',
    '|---|---|---|---|',
    ...rows.map((r) => `| \`${r.metric}\` | \`${r.expr}\` | ${r.observed} | ${r.ok ? 'pass' : '**fail**'} |`),
    '',
  ].join('\n');

  return {
    stdout: text + '\n',
    [`${SUMMARY_DIR}/k6-summary.json`]: JSON.stringify(data, null, 1),
    [`${SUMMARY_DIR}/k6-summary.md`]: md,
  };
}
