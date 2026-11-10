# E8 Argo CD sync impersonation: hypotheses (written before the runs)

Since chapter 6 a project (AppProject) is all that stands between a team's path in the configuration
repository and the cluster: Argo CD checks the project's destinations and kinds, then applies the change
with its own service account, which may do anything anywhere (`kubectl auth can-i create secrets -n
storefront --as=system:serviceaccount:argocd:argocd-application-controller` = yes). Sync impersonation
(Argo CD 2.13+, alpha; argocd-cm `application.sync.impersonation.enabled`) applies a project's changes
as the account the project names (`destinationServiceAccounts`), so Kubernetes RBAC checks them too.

Setup, merge request 1 (impersonation still off):

- deployer accounts `storefront/argocd-storefront` and `insight/argocd-insight`, Roles on the kinds of
  their releases (rendered: Deployment, Service, ServiceAccount, PDB, HPA, ScaledObject, ServiceMonitor;
  insight: Deployment, Service, ExternalSecret) - no Secrets, no Pods, no RBAC;
- the platform's account `argocd/argocd-platform` (cluster-admin) comes with the Argo CD release (helm
  `extraObjects`), not from Git: the root application would otherwise have to sync its own rights;
- `CreateNamespace=true` removed from the storefront ApplicationSet (the platform owns the namespaces);
- two temporary applications of the project storefront: `e8-probe` (a Secret) and `e8-probe-ns`
  (a ConfigMap, `CreateNamespace=true`).

Then `helm upgrade` of Argo CD with the flag on; merge request 2 changes both probes and catalog;
merge request 3 removes the probes.

| | Hypothesis | Measured by |
|---|---|---|
| I1 | impersonation off: `e8-probe` creates its Secret - the project allows every core kind and Argo CD writes with its own rights (audit log: the application controller, no impersonated user) - although `argocd-storefront` may not (`can-i create secrets` = no) | app state, Secret, audit log, can-i |
| I2 | impersonation on: a change to that Secret through the gate is refused by Kubernetes RBAC - the sync fails with "forbidden" for `system:serviceaccount:storefront:argocd-storefront` (verb get in the dry run, or patch); the Secret keeps its first content; nothing else is affected | operation message, Secret content |
| I3 | an ordinary release change (catalog: `LOG_LEVEL: INFO`, the default made explicit - a rollout) syncs as `argocd-storefront` (audit log: patch deployments with that impersonated user, 200) within the usual one to two minutes after the merge | operation state, audit log |
| I4 | the platform's applications keep working as `argocd-platform`: 35/35 Synced/Healthy after the upgrade; the root application's next sync (removing the probes) succeeds with impersonated user `argocd-platform` | app list, audit log |
| I5 | `CreateNamespace=true` needs more than the namespace's Role: Argo CD reads the namespace with the impersonated account, so `e8-probe-ns`'s next sync fails ("Namespace auto creation failed ... forbidden") although its ConfigMap alone would be allowed. Confidence medium: it depends on which client Argo CD uses for that read | operation message, ConfigMap content |

Limits of the measurement: the audit policy (chapter 1) does not log reads by service accounts, so a
refused read shows only in Argo CD's error message (the API server's own text), not in the audit log.
Not tested: a cluster rebuild with impersonation on (bootstrap.sh installs Argo CD, and with it the
platform account, before the root application exists); Applications written by the teams themselves
(here the platform creates every Application, chapter 6).
