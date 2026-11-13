# E8 change freeze and deployment events: hypotheses (written before the drill)

A freeze needs two keys in a GitOps setup: the merge is the decision to deploy, so the gate has to
refuse ordinary merges (GitLab deploy freeze; the pipeline job `freeze` fails unless the commit message
says `[emergency]`), and Argo CD has to hold back what is merged anyway (a deny sync window on the
project storefront; `manualSync: true` leaves the operator a manual sync). Drill: `experiments/e8/
freeze-drill.sh` - both keys over the same 14 minutes. Deployment events: Argo CD notifications create
a GitLab deployment for every finished sync of a storefront service (enabled before this prediction:
the 6 records of 04:20:07-09 are the initial state of the six services, not a test).

| | Hypothesis | Measured by |
|---|---|---|
| F1 | inside the freeze, alice's ordinary merge request fails its pipeline in the job `freeze` (render and release policies pass), and GitLab refuses the merge (HTTP 405) | pipeline jobs, job log, merge attempt |
| F2 | the emergency merge request (`[emergency]` in the commit message) passes; the job log says it ran as an emergency change; merged within about a minute | job log, merge |
| F3 | the deny window holds the merged change back: catalog and orders stay OutOfSync with no sync operation for at least 120 s after the merge - main and the cluster disagree; the operator's manual sync applies catalog inside the window within about a minute (rollout) | application state at +30/60/90/120 s, manual sync |
| F4 | after the window, orders syncs by itself within 2 minutes (reconciliation every 60 s plus jitter) | time from the end of the window to Synced/Healthy |
| D1 | each sync of the drill (catalog by hand, orders automatically) becomes exactly one GitLab deployment on `prod/<service>` with the emergency commit, created within 60 s of the application turning healthy | GitLab deployments, application times |
| D2 | GitLab links the emergency merge request to these deployments. Confidence medium: deployments created through the API have no CI job behind them | deployment -> merge requests |
