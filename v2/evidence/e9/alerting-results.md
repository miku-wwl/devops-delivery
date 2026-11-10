# E9 alert routing: results against the hypotheses

Hypotheses: `alerting-prediction.md` (committed in 32a8854 before the switch-on). Routing switched on
with merge request !27 and an Argo CD `helm upgrade` (controller metrics) at 06:42:59 UTC.

| | Hypothesis | Measured | |
|---|---|---|---|
| A1 | the switch-on opens no issue | the first notification (06:45:18) was **AlertmanagerClusterCrashlooping**: the rule was gone from Prometheus, but Alertmanager still held the alert until it expired; the bridge opened incident #1, closed at 06:49:12 when Alertmanager resolved it. First Watchdog heartbeat 06:45:18 | **refuted** |
| A2 | OpenBao restarted: sealed, incident within 2.5 min of the pod's start, closed within 3 min of the unseal | pod Running 06:46:01; `vault_core_unsealed` 0 at +31 s (the metrics endpoint answers while sealed); alert pending +41 s, firing +102 s; incident #2 at 06:48:08.8 (**128 s**); unsealed 06:48:13, incident closed 06:50:05 (**112 s**) (`a2-openbao.log`) | confirmed |
| A3 | a failing sync raises `ArgoCDSyncFailing` and a ticket within 1.5 min | e9-probe Failed at 06:57:26 after 5 retries - **the alert never fired**: `argocd_app_sync_total{phase="Failed"}` is born at 1 with the first failure and stays 1, `increase()` sees nothing. Rewritten to catch new series too; back-tested on the recorded data: fires 06:58-07:07 (`a3-backtest.log`). The application did raise `ArgoCDAppOutOfSync` (ticket #4, 07:08:08, after its 15 minutes) | **refuted** (rule fixed) |
| A4 | node of Prometheus and Alertmanager frozen: dead man's incident 180-200 s after the last heartbeat; closed within a minute after the unpause; writes continue | last heartbeat 07:16:36.6, pause 07:16:38; node Unknown after 45 s; incident #6 at 07:19:40.4 (silent **183.2 s**); unpause 07:20:24.6, incident closed 07:20:27.8; 14 rows written during the pause (`a4-deadman.log`) | confirmed |
| A5 | a backup with warnings opens a ticket within 2 min of completion | backup e9-warnings Completed with 7 warnings; `VeleroBackupWarnings` firing 06:52:57, ticket #3 at 06:53:31.7 (`a3-a5-tickets.log`) | confirmed |

Findings beyond the hypotheses:

- **A child that never gets healthy blocks the root.** The platform's health check on Applications
  (needed for sync waves, chapter 9) makes the root application's sync wait for each child's health.
  e9-probe never became healthy, the root's operation kept "waiting for healthy state of
  argoproj.io/Application/e9-probe", and the merge that removed the probe (!29, 07:06:51) could not be
  applied until the old operation ended. `ArgoCDRootNotSynced` opened incident #5 at 07:13:30 (true
  positive), closed 07:15:27. Teams' applications are created by the ApplicationSet, not by the root,
  so only applications the platform itself declares can block it this way.
- **A silent Prometheus looks like "all clear".** During the freeze, Alertmanager let
  VeleroBackupWarnings expire (no updates from Prometheus) and sent a resolved notification at
  07:20:25 - the bridge closed ticket #3 although nothing had been fixed. Only the dead man's switch
  told the truth.
- The noisy rule had to go **before** the routing was switched on (A1): enable paging only once what
  is firing has been reviewed.
