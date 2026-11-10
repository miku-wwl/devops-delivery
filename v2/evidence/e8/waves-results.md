# E8 sync waves on an empty cluster: results against the hypotheses (rebuilds R3 and R4)

Hypotheses: `waves-prediction.md` (committed in da7ad36; layout merged as !23 in 594718d, both before
R3). Driver: `experiments/e8/rebuild-run.sh` (the runbook of chapter 8 without pauses between the
steps; OpenBao restored as soon as its pod exists). Records: `evidence/e7/r3/`, `evidence/e7/r4/`
(the run directories of the rebuild series; R1 and R2 are chapter 8's).

## R3 (T0 = 04:53:42 UTC): stuck in wave -2

`wait-apps.txt`: Istio chain t+10..150 s, operators (wave -3) t+150..356 s - barman-cloud healthy at
t+266 s, inside the wave as planned; wave -2 from t+356 s, pg-main healthy at t+546 s. Then nothing:
`timeout after 1800s` with 24/27 applications, root `OutOfSync/Degraded`, sync failed after 5 retries.

| Cause | Evidence | Fix |
|---|---|---|
| **HTTPRoute storefront/storefront** (application mesh, wave -2) points at the storefront's Service `gateway` - created in wave -1. `ResolvedRefs=False BackendNotFound`, the route and with it mesh Degraded; the root waits for wave -2 to be healthy, so the storefront is never created. Introduced by E8 (!6, the layer-7 entrance), not by the new layout: the old layout had the same order (mesh -2, storefront 1) | root: `Application mesh Synced Failed - Caused by gateway.networking.k8s.io/HTTPRoute:storefront/storefront`; route conditions | the route moves to an application of its own, `storefront-routes`, in the last wave (1) - !25 |
| **Kyverno generated the Git tenants' defaults.** The generate policy `tenant-namespace-defaults` (synchronize) leaves shop-dev and insight alone only because they used to exist before it; the new layout put policies (from -1) in the same wave as tenants, so Kyverno generated their LimitRange, quota and NetworkPolicies first, and Argo CD and Kyverno both claimed them (tenants OutOfSync) | the 8 objects labelled `app.kubernetes.io/managed-by: kyverno`, `generate.kyverno.io/policy-name: tenant-namespace-defaults` | an explicit exclusion: label `tenant-defaults: git` on the two namespaces, `DoesNotExist` in the four rules - !25. Kyverno refused the changed rule on the live cluster (`changes of immutable fields of a rule spec in a generate rule is disallowed`): the policy was deleted by hand and recreated from Git |

Recovery (`r3/recovery.txt`): !25 merged 05:31; storefront synced 05:33:41, 34/36 two minutes later;
the policy recreated at 05:49:24, 36/36 at 05:49:29 (T0 + 55.8 min, of which about 35 min waiting
and diagnosing).

## R4 (T0 = 05:51:00 UTC): no manual step

36/36 applications Synced+Healthy **636 s** after the root's first sync, **847 s (14.1 min)** after
the destroy (`r4/wait-apps.txt`).

| | Hypothesis | Measured | |
|---|---|---|---|
| W1 | root's first sync to all applications Synced+Healthy at most 600 s (R2: 692 s) | **636 s** (36 applications; R2 had 35) | refuted (-56 s, -8 %) |
| W2 | no wave deadlock, no manual fix beyond the planned OpenBao restore | R3: two (above), fixed by hand; **R4: none** | refuted in R3, confirmed in R4 |
| W3 | impersonation from the first sync | R4, all audit files since the cluster exists: the controller wrote only Argo CD's own objects itself (854 status updates); every other write impersonated - argocd-root 33 (first 05:54:35), argocd-platform 1315, argocd-storefront 36, argocd-insight 3; no 401/403. R3 the same (`r3/impersonation-deploy-events.txt`) | confirmed |
| W4 | the deployment events record the rebuild | R4: GitLab deployments #19-#24, one per storefront service, success, 06:04:27-06:05:03, commit 6ab4f718; R3: #13-#18 after the recovery | confirmed |
| W5 | destroy to 35/35 at most 13.5 min (R2: 15.05 min to all applications, T0 + 903 s) | **14.1 min** (T0 + 847 s); R4 had no pauses between the steps, R2 about 35 s | refuted |

Where the time went, R2 against R4 (seconds after the root's first sync, created/done):

| | R2 | R4 | |
|---|---|---|---|
| Istio chain (gateway-api-crds, istio-base -> istiod, CNI -> ztunnel) | 0 - 68 | 10 - 162 | **gateway-api-crds 121 s instead of 35 s** (R3: 109 s) - cause not determined |
| operators (wave -3) | 68 - 311 (external-secrets) | 162 - 308 | 146 s instead of 243 s; barman-cloud done at 277, inside the wave |
| pg-main (restore from the archive) | 438 - 616 (178 s) | 308 - 538 (230 s) | starts **130 s earlier**, takes 52 s longer |
| storefront | 616 - 692 | 543 - 636 | |

The layout delivered its structural gain - PostgreSQL started 130 s earlier, barman-cloud no longer had
a wave of its own - and two components that the layout does not touch took 138 s longer than in R2 (gateway-api-crds +86 s, the restore +52 s).
Run-to-run variation of single components (R2 / R3 / R4: gateway-api-crds 35 / 109 / 121 s, the
restore 178 / 190 / 230 s, external-secrets until healthy 238 / 200 / about 146 s) is as large as the
gain of the reordering; one rebuild per layout cannot resolve a two-minute improvement.

RPO in R3 and R4: the drill writer ran only 18 s (R3) and 12 s (R4) before the destroy - in R4 by a
mistake: the wait before the destroy computed its start time with `date -d 05:50:50` in WSL's local
time zone (UTC+13), which lay in the past. All acknowledged writes (931 and 610) were lost: none of
them reached an archived WAL segment (`archive_timeout` 5 min), as chapter 8 predicts. Not a new RPO
measurement.

Further observations: the audit log lives on the host (`$STATE/audit-log`) and survives rebuilds; it
rotated at 100 MB during R4's bootstrap (05:57:30), so counts must read all `audit*.log` files.
