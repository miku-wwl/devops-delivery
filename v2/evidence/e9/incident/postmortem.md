# Postmortem: checkouts failed after a release carried a test setting (E9 drill, 2026-11-10)

Blameless. The cause is `[模拟]` - a test setting put into production on purpose for the drill;
detection, notification, diagnosis, mitigation and the numbers below are real (`timeline.log`,
`watch.log`, the bridge's event log, Prometheus, GitLab).

## Summary

At 08:23:40 UTC merge request !37 (author alice, merged by a Maintainer) added `PSP_ERROR_RATE: "1"`
to the production values of payments - a setting meant to test the payment provider's error handling.
From about 08:24:10 every charge failed and the gateway answered 98 % of checkouts with 503. The SLO
page fired at 08:26:18, the incident opened in GitLab at 08:26:55, the on-call engineer found the change
through the deployment record and merged a revert at 08:28:04; the failures stopped by 08:28:40. The
incident closed at 08:57:05.

## Impact

- **Checkout:** 670 of 5365 orders between the merge and the close failed (5xx at the gateway); in
  08:24:30-08:28:30, 626 of 638 (98.1 %). Customer-visible failure lasted about 4.5 minutes.
- **Browse:** no 5xx.
- **Error budget:** at 2.66 orders/s, 30 days hold 6.89 million orders and 1 % of them (68 900) may
  fail; 670 failures = **0.97 % of the month's budget**.

## Timeline (UTC)

| Time | Event | |
|---|---|---|
| 08:23:40.7 | !37 merged (pipeline 73 green after 42 s - the gate does not judge environment variables) | change |
| 08:23:47 | Argo CD syncs payments | |
| 08:24:01.6 | GitLab deployment #25, prod/payments, success | |
| ~08:24:10 | first failed checkouts (first 30-second interval with 503s ends 08:24:30) | impact begins |
| 08:24:33.5 | SLOBurnCheckoutAvailabilityTicket fires; ticket #11 sent 08:25:17.6 | |
| 08:26:18.5 | **SLOBurnCheckoutAvailabilityPage fires** | detection +2 min 08 s |
| 08:26:55.5 | **incident #12 opened** by the alert bridge (group_wait 30 s) | escalation +37 s |
| 08:27:20.8 | acknowledged by the on-call engineer (note in GitLab) | +25 s |
| 08:27:22.7 | diagnosis: deployment #25 of prod/payments lists !37 by alice | |
| 08:28:04.6 | **revert merged** (pipeline green) | mitigation +69 s after the page |
| ~08:28:40 | last failed checkouts (no 503 in the interval ending 08:29:00) | impact ends |
| 08:33:56 | checkout 5-minute error ratio back to 0 | |
| 08:56:33 | page resolves (the 30-minute window no longer holds the failures) | |
| 08:57:05.5 | **incident #12 closed** by the bridge | resolution +28.5 min after recovery |

## Detection

The page came from the **6 h / 30 min** pair (6 h ratio up to 11.4 % > 6 %, 30 min > 6 %); the 1 h / 5 min
pair never fired - its 1 h ratio peaked at 13.5 %, below 14.4 %. It paged after 2 minutes only because
the windows held about **35 minutes of traffic**: the host had been suspended from about 07:47 to 08:13
(the dead man's switch opened incident #8 at 08:13:32 after 1548.5 s of silence) and the cluster was
rebuilt at 06:05, so the "6-hour" ratio was a 35-minute ratio. With a full history the 1 h / 5 min pair
needs 14.4 % x 60 / 0.98 = **8.8 minutes** of such failures - about twice this whole outage - before it
pages. The ticket fired first (08:24:33); the page inhibits it only from 08:26:18 on, so ticket #11 had
already gone out: one cause, two GitLab items.

## Root cause and contributing factors

- **Root cause:** a setting for a test environment ended up in `envs/prod/storefront/services/payments.yaml`.
- The gate checks images, resources, probes and replicas - not what an environment variable means.
- Configuration changes go to every replica at once: Argo CD applied the change 7 s after the merge.
- The burn-rate page depends on the history its windows hold; the symptom - almost every checkout
  failing - was obvious within a minute.
- "Resolved" is not "mitigated": the page stayed active 28 minutes after the failures stopped, as the
  30-minute window is designed to.

## What went well

- The deployment events (chapter 9) gave the on-call the suspect change in one query: prod/payments was
  deployed 9 s before the first failure, and GitLab listed !37 on that deployment.
- The revert went through the gate in 42 s; the failures stopped 36 s after its merge.
- The gateway's circuit breaker towards orders failed fast: only 113 of 638 checkouts reached orders
  (chapter 7), so the failing provider did not drag orders and the database into a retry storm.

## Action items

| # | Action | Status |
|---|---|---|
| 1 | Release policy `no-fault-simulation`: PSP_ERROR_RATE and PSP_HANG_RATE must be 0 in production (`gitops/policies/release/prod/availability.yaml`) | **done** (!39); verified: alice's same change failed pipeline 79 at `release-prod-availability`, merge refused (HTTP 405), `action-item-1-gate.log` |
| 2 | Symptom page `CheckoutFailing`: more than half of the checkouts failing over 2 minutes (and more than 20 of them), for 1 minute (`platform/manifests/alerts/storefront-symptoms.yaml`) | **done** (!39); back-tested on the drill: fires 08:26:15 (`symptom-backtest.log`) |
| 3 | SLO tickets wait 5 minutes (`group_wait`) so that a page can inhibit them before they are sent | **done** (!39); not yet observed in a burn |
| 4 | The checkout SLI counts POST requests only | **done** (!39) |
| 5 | Canary for configuration changes of payment-critical services (the weighted route of chapter 9) | open |
| 6 | Incidents record "mitigated" separately from "resolved" | open |
| 7 | Drills keep the host awake and check how much history the SLO windows hold first | open (lab) |
