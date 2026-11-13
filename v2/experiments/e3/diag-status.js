// What exactly fails? The storefront.js mix (70 % browse, 25 % order, 5 % lookup) at a fixed rate;
// every unexpected response is logged with its status, the k6 error code (0 = an HTTP response
// arrived; 1xxx = network-level errors such as resets or timeouts) and the error text:
//   BASE_URL=http://<lb>:8080 RATE=60 DURATION=90s k6 run diag-status.js 2>&1 |
//     grep -o 'OUT [^"]*' | sort | uniq -c
import http from 'k6/http';

const BASE = __ENV.BASE_URL;
export const options = {
  scenarios: { s: { executor: 'constant-arrival-rate', rate: Number(__ENV.RATE || 60), timeUnit: '1s',
    duration: __ENV.DURATION || '90s', preAllocatedVUs: 100, maxVUs: 600 } },
  summaryTrendStats: ['med', 'p(95)', 'max'],
};
const sku = () => `sku-${String(1 + Math.floor(Math.random() * 18)).padStart(3, '0')}`;
function note(res, name, ok) {
  if (!ok.includes(res.status)) {
    console.log(`OUT ${name} status=${res.status} error_code=${res.error_code} error=${res.error}`);
  }
}
let lastOrder = null;
export default function () {
  const roll = Math.random();
  if (roll < 0.70) {
    note(http.get(`${BASE}/api/products?limit=20`), 'list', [200]);
    note(http.get(`${BASE}/api/products/${sku()}`), 'product', [200]);
  } else if (roll < 0.95) {
    const res = http.post(`${BASE}/api/orders`,
      JSON.stringify({ customer_id: `c-${__VU}`, items: [{ product_id: sku(), qty: 1 }] }),
      { headers: { 'Content-Type': 'application/json', 'Idempotency-Key': `diag-${__VU}-${__ITER}-${Date.now()}` } });
    note(res, 'order', [201, 402]);
    if (res.status === 201) lastOrder = res.json('id');
  } else if (lastOrder) {
    note(http.get(`${BASE}/api/orders/${lastOrder}`), 'lookup', [200]);
  }
}
