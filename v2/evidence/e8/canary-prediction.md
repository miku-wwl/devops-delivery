# E8 canary: hypotheses (written before the runs)

The next gateway version - image 8ef5584, which adds the response header X-Storefront-Version
(commit 8ef5584) - is released as a canary: a second release `gateway-canary` (2 replicas, chart
value `app: gateway`) next to the stable `gateway` (fd38028), and its share of the public traffic
is set by weights in the HTTPRoute of the layer-7 entrance. Every change - the canary release, each
weight, the rollback, the promotion - is a merge request through the gate (pipeline about 40 s).
Measured with `experiments/e8/canary.js` (k6, every response counted by its version header) and
`experiments/e8/probe.py` (one request every 50 ms, each one logged with its time, status and
version).

| | Hypothesis | Reasoning |
|---|---|---|
| C0 | The canary release passes the gate (release policies: two replicas, fixed tag, probes) and receives no public request while it has no weight - only requests with the header `x-storefront-preview: canary` reach it | the route sends nothing to a backend that it does not name |
| C1 | **Weights 95/5: of 20 000 requests 5.0 % +- 0.3 % are answered by 8ef5584** (95 % binomial interval for p = 0.05, n = 20 000: 4.70-5.30 %); Prometheus' request counts per version agree | Envoy picks the backend of every request at random in proportion to the weights |
| C2 | With the header `x-storefront-preview: canary`, 100 % of the requests reach the canary | a header match is a rule of its own, evaluated before the weighted default rule |
| C3 | A faulty canary (50 % injected 503s) costs the clients about 2.5 % failed requests (5 % x 50 %), the stable release none; once the rollback (weight 0) is merged the canary stops answering within 30 s; from the decision to no canary traffic about 1.5 min (gate + merge + Argo CD + Istio) | the blast radius of a canary is its weight |
| C4 | Promotion (stable -> 8ef5584, canary removed): every response from 8ef5584 after the gateway's rolling update, no failed request during it | readiness probes and the pre-stop sleep of the chart |
