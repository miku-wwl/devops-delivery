// Storefront traffic for experiments E1-E9 (k6 v2.3.0).
//   BASE_URL=http://<gateway LB IP>:8080 RATE=20 DURATION=2m k6 run v2/experiments/load/storefront.js
// Open model (constant-arrival-rate): requests keep arriving at RATE per second whether or not
// the system keeps up, like real users - a closed model would slow down with the system and
// hide the overload. Mix per iteration: 70 % browse (list + one product), 25 % order, 5 % lookup.
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const RATE = Number(__ENV.RATE || 20);
const DURATION = __ENV.DURATION || '1m';
const PRODUCTS = 18;                       // sku-001 .. sku-018 have unlimited stock
const MAX_VUS = Number(__ENV.MAX_VUS || Math.max(50, RATE * 20));

export const options = {
  discardResponseBodies: false,
  scenarios: {
    shop: {
      executor: 'constant-arrival-rate',
      rate: RATE, timeUnit: '1s', duration: DURATION,
      // MAX_VUS caps concurrency: when the system cannot keep up, k6 would otherwise start
      // thousands of VUs; with the cap, overload shows up as dropped_iterations instead
      preAllocatedVUs: Math.min(Math.max(10, RATE * 2), MAX_VUS), maxVUs: MAX_VUS,
    },
  },
  thresholds: {
    'http_req_failed{kind:browse}': ['rate<0.01'],
    'http_req_duration{kind:browse}': ['p(95)<500'],
    'http_req_duration{kind:order}': ['p(95)<1500'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const sku = () => `sku-${String(1 + Math.floor(Math.random() * PRODUCTS)).padStart(3, '0')}`;
let lastOrder = null;

export default function () {
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
    `rate=${RATE}/s duration=${DURATION} iterations=${m.iterations.values.count} dropped=${m.dropped_iterations ? m.dropped_iterations.values.count : 0}`,
    `requests=${m.http_reqs.values.count} (${m.http_reqs.values.rate.toFixed(1)}/s) failed=${(m.http_req_failed.values.rate * 100).toFixed(2)}%`,
    `browse: ${fmt(m['http_req_duration{kind:browse}'])}`,
    `order:  ${fmt(m['http_req_duration{kind:order}'])}`,
    `checks: ${(m.checks.values.rate * 100).toFixed(2)}% passed`,
  ];
  out.stdout = lines.join('\n') + '\n';
  return out;
}
