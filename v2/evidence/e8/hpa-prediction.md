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
