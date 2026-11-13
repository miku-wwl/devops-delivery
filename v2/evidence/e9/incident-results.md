# E9 incident drill: results against the hypotheses

Hypotheses: `incident-prediction.md` (committed in 8f8d4d2 before the drill (07:21:55 UTC)). Records: `incident/`
(timeline, watch log, postmortem), the bridge's event log, `screens/grafana-slo-incident.png`.

| | Hypothesis | Measured | |
|---|---|---|---|
| S1 | the change passes the gate and reaches payments within 2 minutes | !37 pipeline green after 42 s; merged 08:23:40.7; Argo CD synced 08:23:47; GitLab deployment record 08:24:01.6 | confirmed |
| S2 | checkout fails almost completely (> 90 %), browse unaffected | 626 of 638 checkouts 08:24:30-08:28:30 = **98.1 %**; only 113 reached orders (the gateway's breaker); browse 5xx 0 | confirmed |
| S3 | the page fires 9-10 minutes after the failures start, not earlier; no ticket | page after **2 min 08 s** (08:26:18), from the 6 h / 30 min pair - the windows held 35 minutes of traffic (host suspended 07:47-08:13); the 1 h / 5 min pair never fired (1 h ratio max 13.5 %); the **ticket fired first** (08:24:33) | **refuted** |
| S4 | GitLab incident within 1 minute of the alert firing | incident #12 at 08:26:55.5, 37 s after firing (group_wait 30 s), labels team::shop, slo::checkout-availability | confirmed |
| S5 | the cause found from GitLab without logging in to the cluster; failures stop within 3 minutes of the revert's merge | deployment #25 of prod/payments listed !37 (author alice); revert merged 08:28:04.6; last failures about 08:28:40 (36 s) | confirmed |
| S6 | the alert resolves within 5 minutes after the failures stop; about a single-digit percentage of the month's budget | resolved 08:56:33, **28 minutes** after the failures stopped (the 30-minute window); budget **0.97 %** (670 of 68 900 allowed failures) | **refuted** (resolution) / confirmed (budget) |

Also seen: the host's suspension (07:47-08:13) was itself caught by the dead man's switch (incident #8,
1548.5 s of silence) and its wake-up produced a short burst of errors in every SLO (browse 5-minute
error ratio 73 %, ticket #9); the inhibition of the ticket by the page worked in Alertmanager
(`inhibitedBy`) but only after the ticket's first notification. Action items and their verification:
`incident/postmortem.md`.
