# E3 capacity prediction (written before the high steps were run)

Model: `experiments/e3/capacity_model.py` on the phase-1 windows at 20 and 40 it/s
(`steps-run2-low/`, storefront fd38028, 10 % head sampling, two replicas per service);
output in `capacity-model.log`. Phase 2 runs 60, 80, ..., 200 it/s in one k6 run
(`experiments/e3/step-ramp.sh run2-high`), 120 s per step, 10 s ramps.

Testable claims, with the tolerance decided now:

| | Claim | Passes if |
|---|---|---|
| P1 | The busiest gateway pod's CPU grows linearly with the rate, 5.53 ms per iteration | measured within ±15 % of the model at every step from 60 to 160 it/s |
| P2 | The gateway is the first service to saturate; its busiest pod reaches 0.95 cores at 172 it/s | busiest gateway pod ≥ 0.90 cores first at a step between 152 and 192 it/s; no other service's busiest pod above 0.70 cores below 180 it/s |
| P3 | Latency stays flat while the gateway's busiest pod is below ~70 % of a core, and the system fails beyond saturation | k6 browse p95 < 50 ms up to 120 it/s; at 180 and 200 it/s browse p95 > 500 ms or failures > 5 % |
| P4 | The worker nodes are not the limit: 1.01 cores + 32 ms per iteration | all worker nodes together at 160 it/s within ±15 % of 6.13 cores; no node above 3.2 cores (80 %) |

Known limitations of the prediction: the demand D was measured ~30 minutes before phase 2
(this lab drifts by 10-25 % between runs, chapter 4, experiment 1); D fell from 20 to 40 it/s
(gateway 6.46 → 5.95 ms), so a constant D is conservative; the busiest-pod share (0.58 for the
gateway) depends on how k6's connections happen to be spread over the two pods.
