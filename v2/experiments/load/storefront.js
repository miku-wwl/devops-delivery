// Storefront traffic for experiments E1-E9 (k6 v2.3.0).
//   BASE_URL=http://<gateway LB IP>:8080 RATE=20 DURATION=2m k6 run v2/experiments/load/storefront.js
// Open model (constant-arrival-rate): requests keep arriving at RATE per second whether or not
// the system keeps up, like real users - a closed model would slow down with the system and
// hide the overload. Mix per iteration: 70 % browse (list + one product), 25 % order, 5 % lookup.
// Step mode (E3): STAGES=20,40,60 STEP=120 RAMP=10 WARMUP=30 runs ONE test that ramps up to the
// first rate in WARMUP s, holds every rate STEP s and ramps to the next in RAMP s - connections
// and pools stay warm between steps, unlike one k6 run per step. Every request is tagged with
// its stage (the rate, or "warmup"/"ramp"), and the summary reports each stage on its own.
import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const RATE = Number(__ENV.RATE || 20);
const DURATION = __ENV.DURATION || '1m';
const PRODUCTS = 18;                       // sku-001 .. sku-018 have unlimited stock
const STAGES = (__ENV.STAGES || '').split(',').filter((x) => x).map(Number);
const STEP = Number(__ENV.STEP || 120), RAMP = Number(__ENV.RAMP || 10), WARMUP = Number(__ENV.WARMUP || 30);
const TOP = STAGES.length ? Math.max(...STAGES) : RATE;
const MAX_VUS = Number(__ENV.MAX_VUS || Math.max(50, TOP * 20));
// MAX_VUS caps concurrency: when the system cannot keep up, k6 would otherwise start thousands
// of VUs; with the cap, overload shows up as dropped_iterations instead
const VUS = { preAllocatedVUs: Math.min(Math.max(10, TOP * 2), MAX_VUS), maxVUs: MAX_VUS };
const thresholds = {
  'http_req_failed{kind:browse}': ['rate<0.01'],
  'http_req_duration{kind:browse}': ['p(95)<500'],
  'http_req_duration{kind:order}': ['p(95)<1500'],
};
// k6 reports a tagged sub-metric only when a threshold names it: always-true thresholds per stage
for (const r of STAGES) {
  thresholds[`http_req_duration{stage:${r},kind:browse}`] = ['max>=0'];
  thresholds[`http_req_duration{stage:${r},kind:order}`] = ['max>=0'];
  thresholds[`http_req_failed{stage:${r}}`] = ['rate>=0'];
  thresholds[`http_reqs{stage:${r}}`] = ['count>=0'];
  thresholds[`iterations{stage:${r}}`] = ['count>=0'];
}
const stagesFor = () => {
  const out = [{ target: STAGES[0], duration: `${WARMUP}s` }, { target: STAGES[0], duration: `${STEP}s` }];
  for (const r of STAGES.slice(1)) out.push({ target: r, duration: `${RAMP}s` }, { target: r, duration: `${STEP}s` });
  return out;
};
// The arrival schedule fixes how many iterations start before each moment, so the scenario-wide
// iteration number tells the stage exactly (a wall-clock tag was off by up to 7 % per stage)
const BOUNDS = (() => {
  const b = [[STAGES[0] * WARMUP / 2, 'warmup']];
  STAGES.forEach((r, i) => {
    if (i > 0) b.push([b[b.length - 1][0] + (STAGES[i - 1] + r) / 2 * RAMP, 'ramp']);
    b.push([b[b.length - 1][0] + r * STEP, String(r)]);
  });
  return b;
})();
const stageOf = (n) => {   // n: number of iterations started before this one
  for (const [end, label] of BOUNDS) if (n < end) return label;
  return 'end';
};

export const options = {
  discardResponseBodies: false,
  scenarios: {
    shop: STAGES.length
      ? { executor: 'ramping-arrival-rate', startRate: 0, timeUnit: '1s', stages: stagesFor(), ...VUS }
      : { executor: 'constant-arrival-rate', rate: RATE, timeUnit: '1s', duration: DURATION, ...VUS },
  },
  thresholds,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const sku = () => `sku-${String(1 + Math.floor(Math.random() * PRODUCTS)).padStart(3, '0')}`;
let lastOrder = null;

export default function () {
  if (STAGES.length) exec.vu.metrics.tags.stage = stageOf(exec.scenario.iterationInTest);
  const roll = Math.random();
  if (roll < 0.70) {
    const list = http.get(`${BASE}/api/products?limit=20`, { tags: { kind: 'browse', name: 'list' } });
    check(list, { 'list 200': (r) => r.status === 200 });
    const one = http.get(`${BASE}/api/products/${sku()}`, { tags: { kind: 'browse', name: 'product' } });
    check(one, { 'product 200': (r) => r.status === 200 });
  } else if (roll < 0.95) {
    const items = [{ product_id: sku(), qty: 1 + Math.floor(Math.random() * 3) }];
    if (Math.random() < 0.3) items.push({ product_id: sku(), qty: 1 });
    const key = `k6-${__VU}-${__ITER}-${Date.now()}`;
    const res = http.post(`${BASE}/api/orders`, JSON.stringify({ customer_id: `c-${__VU}`, items }), {
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key },
      tags: { kind: 'order', name: 'order' },
      responseCallback: http.expectedStatuses(201, 402),   // a declined card is not an error
    });
    check(res, { 'order confirmed or declined': (r) => r.status === 201 || r.status === 402 });
    if (res.status === 201) lastOrder = res.json('id');
  } else if (lastOrder) {
    const res = http.get(`${BASE}/api/orders/${lastOrder}`, { tags: { kind: 'browse', name: 'lookup' } });
    check(res, { 'lookup 200': (r) => r.status === 200 });
  }
}

export function handleSummary(data) {
  const out = {};
  if (__ENV.SUMMARY) out[__ENV.SUMMARY] = JSON.stringify(data, null, 1);
  const m = data.metrics;
  const fmt = (t) => t ? `p50=${t.values.med.toFixed(1)} p95=${t.values['p(95)'].toFixed(1)} p99=${t.values['p(99)'].toFixed(1)} max=${t.values.max.toFixed(1)} ms` : '-';
  const lines = [
    STAGES.length ? `stages=${STAGES.join(',')} it/s, ${STEP} s each (ramp ${RAMP} s, warm-up ${WARMUP} s)` :
    `rate=${RATE}/s duration=${DURATION} iterations=${m.iterations.values.count} dropped=${m.dropped_iterations ? m.dropped_iterations.values.count : 0}`,
    `requests=${m.http_reqs.values.count} (${m.http_reqs.values.rate.toFixed(1)}/s) failed=${(m.http_req_failed.values.rate * 100).toFixed(2)}%`,
    `browse: ${fmt(m['http_req_duration{kind:browse}'])}`,
    `order:  ${fmt(m['http_req_duration{kind:order}'])}`,
    `checks: ${(m.checks.values.rate * 100).toFixed(2)}% passed`,
  ];
  if (STAGES.length) {
    lines[0] += ` iterations=${m.iterations.values.count} dropped=${m.dropped_iterations ? m.dropped_iterations.values.count : 0}`;
    for (const r of STAGES) {
      const it = m[`iterations{stage:${r}}`], rq = m[`http_reqs{stage:${r}}`], f = m[`http_req_failed{stage:${r}}`];
      lines.push(`stage ${r}: achieved ${it ? (it.values.count / STEP).toFixed(1) : 0} it/s, ` +
        `requests=${rq ? rq.values.count : 0} failed=${f ? (f.values.rate * 100).toFixed(2) : '-'}% | ` +
        `browse ${fmt(m[`http_req_duration{stage:${r},kind:browse}`])} | order ${fmt(m[`http_req_duration{stage:${r},kind:order}`])}`);
    }
  }
  out.stdout = lines.join('\n') + '\n';
  return out;
}
