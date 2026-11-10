# E8 canary: results against the hypotheses

Hypotheses: `canary-prediction.md` (committed in fdc4e71 before the runs). Every step a merge
request through the gate (pipelines 32-38 s): !10 canary at weight 0, !11 weight 5, !12 rollback,
!13 promotion.

| | Hypothesis | Measured | |
|---|---|---|---|
| C0 | the canary passes the gate and gets no public request at weight 0, only preview requests | !10 green in 33 s; probe 15 s: 300 of 300 requests without the header answered by fd38028, 300 of 300 with `x-storefront-preview: canary` by 8ef5584 (`canary-c0.log`) | confirmed |
| C1 | **weights 95/5: 5.0 % +- 0.3 % of 20 000 requests from 8ef5584** | k6, 100 requests/s for 200 s: **986 of 20 001 = 4.93 %** (2 failed, both answered by the stable release); Prometheus, same window: 1007 of 20 019 = **5.03 %** (`canary-c1.log`) | confirmed |
| C2 | preview header: 100 % canary | 400 of 400 under live weights 95/5 (`canary-c3/run.txt`) | confirmed |
| C3 | faulty canary (50 % 503) costs about 2.5 %; rollback effective within 30 s of the merge, about 1.5 min from the decision | 90 s before the decision: canary 178 of 3596 requests (4.95 %), **88 failed = 2.45 %**, all of them the canary's, none of the stable release; decision -> merge 43 s; **last canary answer 2.8 s after the merge, 46.1 s after the decision**; 0 failures in the 154 s after the merge (`canary-c3/report.txt`) | confirmed (faster) |
| C4 | promotion without a failed request | 8697 requests during the promotion: **0 failed**; last answer from fd38028 55.5 s after the merge; the canary's Application and resources removed by the ApplicationSet 2.7 min after the merge (`canary-c4-report.txt`, `canary-c4.log`) | confirmed |

Notes:

- The stable release fd38028 predates the version header: "no header" identifies it, every
  8ef5584 response names itself.
- The drill script of C3 hung at a bare `wait` (it also waits for the `tee` of `exec > >(tee ...)`)
  after the probe had finished; the faults were removed by its trap when it was stopped, the report
  was computed from the complete probe log (`canary-c3/report.txt` says so). Fixed: `wait $probe`.
- The blast radius of a canary is its weight: at 5 % a canary that fails half its requests cost 2.45 %
  of all requests. The browse SLO of chapter 7 (99.5 %) allows 0.5 %: a canary analysis has to decide
  within minutes, not hours. The time to decide is the slow part here (43 s of it the gate).
