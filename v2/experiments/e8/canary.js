// E8 (chapter 9): which version answers? A constant rate of GET /api/products through the layer-7
// entrance; every response is counted by its X-Storefront-Version header (set by every storefront
// service since E8) and by its status class. PREVIEW=1 sends the header x-storefront-preview: canary.
//   BASE_URL=http://<ingress>:8080 STABLE=<tag> CANARY=<tag> RATE=100 DURATION=200s k6 run canary.js
// Prints one JSON line: requests answered by each version, and their 5xx.
import http from 'k6/http';
import { Counter } from 'k6/metrics';

const served = new Counter('served');
const BASE = __ENV.BASE_URL;
const STABLE = __ENV.STABLE;
const CANARY = __ENV.CANARY;
const headers = __ENV.PREVIEW === '1' ? { 'x-storefront-preview': 'canary' } : {};

// k6 keeps per-tag counts only for sub-metrics that a threshold names
const subs = [
  `served{version:${STABLE}}`, `served{version:${CANARY}}`, 'served{version:none}',
  `served{version:${STABLE},status:5xx}`, `served{version:${CANARY},status:5xx}`, 'served{version:none,status:5xx}',
];
export const options = {
  scenarios: {
    constant: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 100),
      timeUnit: '1s',
      duration: __ENV.DURATION || '200s',
      preAllocatedVUs: 50,
      maxVUs: 200,
    },
  },
  thresholds: Object.fromEntries(subs.map((s) => [s, ['count>=0']])),
};

export default function () {
  const r = http.get(`${BASE}/api/products?limit=5`, { headers, tags: { name: 'products' } });
  served.add(1, { version: r.headers['X-Storefront-Version'] || 'none', status: `${Math.floor(r.status / 100)}xx` });
}

export function handleSummary(data) {
  const c = (k) => (data.metrics[k] ? data.metrics[k].values.count : 0);
  const out = {
    requests: data.metrics.http_reqs.values.count,
    stable: c(subs[0]), canary: c(subs[1]), none: c(subs[2]),
    stable_5xx: c(subs[3]), canary_5xx: c(subs[4]), none_5xx: c(subs[5]),
  };
  return { stdout: JSON.stringify(out) + '\n' };
}
