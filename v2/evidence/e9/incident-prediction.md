# E9 incident drill: hypotheses (written before the drill)

Scenario `[模拟]` cause, `[真实]` everything else: team shop tests the payment provider's error handling
with a setting meant for a test environment - `PSP_ERROR_RATE: "1"`, every charge fails - and the
line ends up in `envs/prod/storefront/services/payments.yaml`. alice proposes the change, the gate
passes it (the release policies check images, resources, probes and replicas, not the meaning of an
environment variable), a Maintainer merges it. Traffic: k6 `experiments/load/storefront.js`, 10
iterations/s (70 % browse, 25 % order, 5 % lookup), running for about an hour before the change so
that the SLO windows hold clean traffic. The on-call engineer works from the GitLab incident; the
drill script timestamps each step (`experiments/e9/incident-drill.sh`).

SLO: checkout-availability, 99 % (error budget 1 %). Page (critical): ratio over 1 h and over 5 min
both above 14.4 x 1 % = 14.4 %. With a full hour of clean traffic before the change and every order
failing afterwards, the 1-hour ratio after x minutes is x / 60: it crosses 14.4 % after 8.6 minutes;
the 5-minute ratio crosses it within the first minute.

| | Hypothesis | Measured by |
|---|---|---|
| S1 | the change passes the gate (pipeline green) and reaches payments within 2 minutes of the merge | MR, deployment event, rollout |
| S2 | checkout fails almost completely (gateway POST /api/orders 5xx > 90 %) - retries in orders cannot help when every charge fails, the per-service breaker turns them into fast 503s; browse is unaffected (its SLO does not burn) | Prometheus, k6 |
| S3 | the page `SLOBurnCheckoutAvailabilityPage` fires 9-10 minutes after the failures start (8.6 min + rule evaluation), not earlier; no ticket alert (its windows are 2 h and 1 d) | Prometheus alert state, bridge |
| S4 | the bridge opens a GitLab incident (labels team::shop, slo::checkout-availability) within 1 minute of the alert firing (group_wait 30 s) | bridge log, GitLab |
| S5 | the on-call finds the cause from the incident without logging in to the cluster: the GitLab deployment record of prod/payments, a minute before the failures, links the merge request; mitigation = a revert through the gate; failures stop within 3 minutes of the revert's merge | GitLab API, Prometheus |
| S6 | the alert resolves within 5 minutes after the failures stop (the 5-minute window falls below 14.4 %), the bridge closes the incident; the incident consumes about (failed orders) / (1 % of 30 days of orders) of the month's budget - a single-digit percentage | bridge log, Prometheus |

The timeline - change, first failure, alert pending/firing, incident opened, acknowledged, diagnosed,
revert merged, recovered, resolved - goes into the postmortem (`evidence/e9/incident/postmortem.md`)
together with the action items.
