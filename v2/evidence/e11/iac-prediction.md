# E11 infrastructure as code: hypotheses (written before the runs)

What is real: OpenTofu 1.13.9 (`platform/iac/install.sh`), the GitLab provider 19.5.0 against the lab's
GitLab CE 19.5.3, the state in the lab's Garage v2.5.0 (bucket tofu-state, its own key), Argo CD 3.6.1
and its Helm chart. `[注入]`: the drift - changes I make through GitLab's API as root, standing in for
someone clicking in the web UI. `[模拟]`: nothing else; nothing is created in any cloud.

Scope: Argo CD keeps managing what runs in the cluster. OpenTofu takes what nothing declarative manages
today - the governance of the configuration repository root/platform-gitops, set up so far by the
imperative script `platform/gitops/setup.sh` (E8): the project's merge settings (merge only after a
successful pipeline, not after a skipped one; delete the source branch), the protection of main (push:
no one, merge: Maintainers, no force push), and alice's membership (Developer). alice's access token
stays out of it - its value would land in the state.

| | Hypothesis | Measured by |
|---|---|---|
| I1 | adoption: the existing settings are imported (import blocks), not recreated; the first plan after the import shows the differences between the written configuration and reality, and after correcting the configuration (never reality) a plan shows no changes - GitLab is not modified by the adoption | `tofu plan` output before and after; GitLab API before and after |
| I2 | remote state: the state lives in Garage, encrypted on the client (OpenTofu state encryption, AES-GCM with a PBKDF2 key from a passphrase outside Git): the object contains neither the GitLab settings nor any token in plain text. Locking with `use_lockfile` (a lock object written with `If-None-Match`) works on Garage v2.5.0: a second run while the first holds the lock fails with "Error acquiring the state lock" | the object read back from Garage; two concurrent runs |
| I3 | drift: three manual changes - main opened to Developers for push, force push allowed, alice made Maintainer - make `tofu plan -detailed-exitcode` exit with 2 and show exactly these changes as updates to 2 resources; `tofu apply` restores the declared values and the next plan exits 0 | exit codes, plan output, GitLab API |
| I4 | Argo CD manages itself: an Application `argocd` (the chart argo-cd 10.14.0 with `gitops/bootstrap/argocd-values.yaml`) adopts the release installed by `bootstrap.sh` without restarting Argo CD; the upgrade to chart 10.17.1 goes through a merge request (pipeline green), Argo CD syncs itself, and within 10 minutes all applications are Synced and Healthy again. An out-of-band `helm upgrade` afterwards (the path of E8's only failure) is undone by Argo CD (selfHeal) | merge request and pipeline, application status over time, pod restarts |

Limits stated before measuring: one lab GitLab with one project under IaC, not an organisation's
hundreds; the token OpenTofu uses is root's (in an enterprise: a dedicated service account with the
least rights); drift detection runs when started, not on a schedule (chapter text: how to schedule it).
