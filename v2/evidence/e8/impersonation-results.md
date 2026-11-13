# E8 Argo CD sync impersonation: results against the hypotheses

Hypotheses: `impersonation-prediction.md` (committed in 9b5d750 before the runs). Merge requests !14
(accounts, probes; impersonation still off), !15 (both probes write again, orders), !16 (probes removed);
two `helm upgrade`s of Argo CD (the flag on; later the root account). Records: `impersonation.sh`
(state + audit log via `audit_who.py`), one log per step.

| | Hypothesis | Measured | |
|---|---|---|---|
| I1 | impersonation off: `e8-probe` creates its Secret with Argo CD's own rights, although `argocd-storefront` may not | Secret created 03:49:28 by `system:serviceaccount:argocd:argocd-application-controller`, no impersonated user (audit log: `create secrets storefront/e8-probe 201`); `can-i create secrets -n storefront` as `argocd-storefront`: no (`impersonation-i1.log`) | confirmed |
| I2 | impersonation on: the Secret's change is refused by Kubernetes RBAC | sync failed: `secrets "e8-probe" is forbidden: User "system:serviceaccount:storefront:argocd-storefront" cannot get resource "secrets" in API group "" in the namespace "storefront"` - already the read before the apply (dry run); refused on every retry; the Secret kept its first content (`impersonation-i2.log`, `impersonation-i4.log`) | confirmed |
| I3 | an ordinary release change syncs as `argocd-storefront` | orders (`LOG_LEVEL: INFO`): merged 03:54:07, synced 03:55:25 (78 s), rollout complete; audit log: `patch deployments storefront 200` and `patch poddisruptionbudgets storefront 200`, impersonated user `argocd-storefront` (`impersonation-i2.log`) | confirmed |
| I4 | the platform's applications keep working; the root application's next sync succeeds as `argocd-platform` | the project platform: yes - its applications' server-side dry runs ran as `argocd-platform` with 200 (one exception, below). **The root application: no** - it is in the project `default` (it creates the other projects, so it cannot be in one of them), and `default` had no account: `no matching service account found for destination server https://kubernetes.default.svc and namespace argocd`, 5 retries; from the merge of !16 (03:58) to the fix (04:05:33) the root application could not sync (`impersonation-i4.log`) | **refuted** for the root application |
| I5 | `CreateNamespace=true` needs read rights on the namespace | controller log: `namespace auto creation failed: namespaces "storefront" is forbidden: User "system:serviceaccount:storefront:argocd-storefront" cannot get resource "namespaces"`; Argo CD then planned to create the namespace, and the project check refused that task (`resource :Namespace is not permitted in project storefront` - the message the application shows); the same application had synced without impersonation (!14) (`impersonation-i2.log`) | confirmed |

The fix for I4: a project `root` of its own (`gitops/bootstrap/root.yaml`, applied by hand like the root
application) that allows only Applications, ApplicationSets and AppProjects in `argocd`, with the account
`argocd-root` (a Role on exactly these, from the Argo CD release). The root application then synced at
04:05:33 and removed both probes as `argocd-root` (`delete applications argocd 200`, 2x); 35/35
applications Synced/Healthy (`impersonation-i4-fixed.log`). `default` keeps no account: with
impersonation on, nothing in it can sync.

Further findings:

- **The flag can outrun the rights.** One `helm upgrade` brought the flag and the platform account; helm
  applied `argocd-cm` at 03:50:17.572 and the ClusterRoleBinding at 03:50:19.574. In between, one dry run
  as `argocd-platform` was refused (403, the Kyverno CRD `policyexceptions.kyverno.io`) - harmless here,
  but on a live system the accounts come first and the flag in a second step (`impersonation-upgrade.log`).
- **Impersonation covers the diff, not only the sync.** Applications that sync with `ServerSideApply=true`
  are compared by server-side dry runs (`dryRun=All`, field manager `argocd-controller`), and those ran
  as the project's account too: the account needs patch rights on everything of its application even
  when nothing is synced.
- Argo CD 3.6 retried the failed automated syncs 5 times, although the probe applications had no retry
  policy (`retried 5 times` in the final operation message).
- The audit log now names the project's account as the impersonated user on every applied write:
  who changed something in the cluster can be traced to a project, not only to "Argo CD".
- Not alerted: the root application could not sync for about 7 minutes and nothing reported it - an
  alert on failed syncs is an E9 item.
- Deviation: catalog's `LOG_LEVEL` change went into !14 by mistake (synced 03:49:12, impersonation still
  off); I3 used the same change on orders in !15.
