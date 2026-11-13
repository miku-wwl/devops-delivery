# E8 scale-out re-test: hypotheses (written before the runs)

Chapter 5 (E4, `evidence/e4/hpa-2*`): a load step 30 -> 170 -> 30 iterations/s against the gateway
(HPA 2-6 pods, target 100 % of a 500m CPU request) through the L4 load balancer. The HPA added two
pods; **neither received a single request** - the clients' keep-alive connections stayed on the
two old pods - and 20.5 % of the requests of the high stage failed (bulkhead and breaker
rejections on the overloaded pods). Since then the workers grew to 3.5 GiB and the platform
changed, so the same step runs twice now, back to back, with `experiments/e4/hpa-timeline.sh`:
`hpa-l4` through the L4 entrance (Service gateway, type LoadBalancer) and `hpa-l7` through the new
layer-7 entrance (Gateway storefront-ingress, `GW_URL`).

| | Hypothesis |
|---|---|
| H1 | hpa-l4 repeats chapter 5: the added gateway pods get (almost) no requests; the high stage fails in the order of 20 % |
| H2 | hpa-l7: every added pod gets requests within about 10 s of becoming Ready, and the load spreads evenly (each pod near 1/N of the requests) |
| H3 | hpa-l7: failures only until the first added pod is ready (the first minute of the high stage): below 5 % for the stage |
| H4 | the extra Envoy hop costs about 1-2 ms at the median for browse requests (low stage, hpa-l7 against hpa-l4) |

## Results of hpa-l4 and hpa-l7, and two more runs (written before runs A and B)

- **H1 confirmed** (`hpa-l4.log`): step at 00:20:36; the HPA added pods at +48 s and +93 s; in every
  60 s window of the high stage only the two original pods served requests (135-150/s each), the
  added pods none. 46.57 % of the high stage failed (chapter 5: 20.5 %; the platform has changed
  since, which is why the control ran the same day). The test suite of the storefront ran on the
  host from about 00:19:30 to 00:20:45, overlapping the low stage and the first 10 s of the ramp.
- **H2 confirmed, H3 refuted** (`hpa-l7.log`): the added pods got requests at once (pod 6m9nq
  79/s in its first full minute) and at the end of the stage all four shared the load (22-44/s
  each). But 57.20 % of the high stage failed, browse p95 9.6 s; k6 hit its 600 virtual users 21 s
  into the step and dropped 13 483 iterations (its per-stage summary then reports the last stage as
  0 it/s, although the gateway served 45-50 requests/s in it). The gateway pods received 150-245
  requests/s of the ~290 offered.
- **H4 refuted the other way**: low-stage browse p50 11.6 ms through the entrance against 12.4 ms
  (L4) - no measurable cost, within run-to-run noise.

Suspected cause: Istio gives every route a default retry policy (the entrance's config dump:
`num_retries: 2`, `retry_on: connect-failure,refused-stream,unavailable,cancelled,retriable-status-codes`)
- the gateway's quick refusals under overload come back as more load. Not counted: Istio exposes
only a few Envoy stats; the entrance now exposes its retry counters and is scraped.

| | Run | Hypothesis |
|---|---|---|
| H5 | A: `hpa-l7-retries`, same as hpa-l7, retry counters visible | repeats hpa-l7 (> 50 % failed in the high stage, browse p95 several seconds); the entrance retries a large number of requests in the high stage (`envoy_cluster_upstream_rq_retry` > 10 % of its upstream requests) |
| H6 | B: `hpa-l7-noretry`, the route's retries switched off (`retry: {attempts: 0}`) | the load still spreads over all pods; the high stage fails far less than L4 (< 20 %), browse p95 below 3.5 s (one attempt, the gateway's 3 s deadline) |
