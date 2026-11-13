# E8 change freeze and deployment events: results against the hypotheses

Hypotheses: `freeze-prediction.md` (committed in aa46160 before the drill). Drill:
`experiments/e8/freeze-drill.sh 5 14`, record `freeze/run.txt`. Both keys over 04:28:00-04:42:00 UTC:
GitLab freeze period 1 (`28 4 * * *` to `42 4 * * *`) and an Argo CD deny window on the project
storefront (`28 4 * * *`, 14m, manualSync), set up by !18 and removed by !21.

| | Hypothesis | Measured | |
|---|---|---|---|
| F1 | alice's ordinary merge request fails in the job `freeze`; GitLab refuses the merge | !19 (catalog `LOG_LEVEL: WARNING`): pipeline failed after 17 s, job `freeze`: `deploy freeze active - only emergency changes ([emergency] in the commit message) may merge`; merge HTTP 405; closed | confirmed |
| F2 | the emergency merge request passes, its job log says so, merged within a minute | !20 `[emergency] orders, catalog: DB_POOL_MAX +2 (pool exhaustion)`: pipeline 23 s, `deploy freeze active - emergency change, allowed`; merged 04:29:00, 28 s after the proposal | confirmed |
| F3 | the deny window holds the merged change back for at least 120 s; a manual sync applies catalog inside the window within a minute | at +30/60/90/120 s both OutOfSync, their last sync still the one of 03:49 / 03:55; controller: `Sync prevented by sync window` (04:29:03, 04:30:36); operator's sync 04:30:59 -> catalog Synced/Healthy 04:31:23 | confirmed |
| F4 | after the window, orders syncs by itself within 2 minutes | window end 04:42:00, orders' sync started 04:42:56, Synced/Healthy **76 s** after the end; main and the cluster disagreed for **14 min** (merge 04:29:00 -> 04:42:57) | confirmed |
| D1 | each sync becomes exactly one GitLab deployment within 60 s of the application turning healthy | #11 prod/catalog success 04:31:22.98 (sync finished 04:31:01); #12 prod/orders success 04:43:15.25 (sync finished 04:42:57); both with the emergency commit 3783f524, created by the project's bot account; no other deployment | confirmed |
| D2 | GitLab links the emergency merge request to these deployments | both deployments: merge requests !20 and !18 | confirmed - and !18 too |

Notes:

- GitLab links merge requests to a deployment by the commits between deployments of the environment,
  not by what they changed: !18 (the drill's window and the job `freeze`) changed neither service and
  is linked to both. The DORA script maps merge requests to applications by the files they change.
- The emergency change itself is `[模拟]`: there was no pool exhaustion. DB_POOL_MAX stays at 12
  (orders) and 14 (catalog); both merged through the gate and copied back into `v2/gitops`.
- The deny window held the change back exactly as long as it lasted: an Argo CD window alone lets main
  run ahead of the cluster, and everything merged meanwhile goes out together at its end.
- The year-end window (24-26 December) stays in the project storefront; the drill's GitLab freeze
  period was deleted.
