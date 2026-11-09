# E6 dependency faults: hypotheses for a confirmatory run (written before it)

The four runs of experiment 1 (slow-resilient, slow-naive, errors-naive, errors-resilient-2) were an
exploratory comparison; no hypothesis was written down before them. This run tests what they
suggest, under a condition not run yet: resilient mode, **50 %** (not 90 %) of inventory's requests
answer 503, 30 it/s, 120 s steady / fault / recovery
(`experiments/e6/fault-phase.sh errors50-resilient inventory '{"error_rate": 0.5, "status": 503}' 30 120`).

| | Hypothesis | Passes if (fault part) |
|---|---|---|
| D1 | The fault does not cross the service boundary: browse is unaffected | browse p95 within 20 % of the steady part, no browse SLO violation (k6 browse) |
| D2 | The retry budget (20 %) and the breakers bound the load on inventory: no retry storm | inventory receives at most 1.3 calls per order placed (steady: about 1.0; naive at 90 %: 5.56) |
| D3 | Orders that fail, fail fast: the breakers reject instead of waiting | order p50 below 100 ms, or the order success rate stays above 90 % |
| D4 | The order SLO (99 %) is violated during the fault and recovers within 30 s after it | k6 stage results; failures per part |
