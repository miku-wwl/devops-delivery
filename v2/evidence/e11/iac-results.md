# E11 infrastructure as code: results

Hypotheses: `iac-prediction.md` (committed before the runs, 121c532). Real: OpenTofu 1.13.9, the
GitLab provider 19.5.0, GitLab CE 19.5.3, Garage v2.5.0, Argo CD v3.6.1 with the chart argo-cd.
`[注入]`: the drift of I3 and the out-of-band helm upgrades of I4.

| | Hypothesis | Measured | |
|---|---|---|---|
| I1 | the existing governance is imported, not recreated; after correcting the configuration, a plan shows no changes; GitLab unchanged | first plan: `3 to import, 0 to add, 0 to change, 0 to destroy` - the configuration had been written from an API read, so there was nothing to correct; apply: 3 imported; next plan: no changes (exit 0); GitLab's governance identical before and after (`i1-gitlab-before.json` = `i1-gitlab-after.json`) | confirmed |
| I2 | the state is encrypted on the client; `use_lockfile` on Garage excludes a second run | encryption: the stored object has only `encrypted_data`, `encryption_version`, `lineage`, `meta`, `serial` - 0 occurrences of `platform-gitops`, `runners_token`, `only_allow_merge` against 1 each after decryption (the project's runner registration token is in the state). Lock: Garage ignores `If-None-Match` (a second conditional PUT of the same key: 200, not 412); with a foreign lock object in place `tofu plan` ran (exit 0) and **deleted the foreign lock** | encryption confirmed, lock refuted |
| I3 | three manual changes: plan exit 2 with updates to 2 resources; apply restores; next plan exit 0 | exit 2; the branch protection **must be replaced** (`push_access_level` forces replacement in the provider) and the membership is updated in place: `1 to add, 1 to change, 1 to destroy`; apply destroyed and re-created the protection - main was unprotected for about a second; next plan exit 0; GitLab equal to the state after the adoption | confirmed, with a correction |
| I4 | Argo CD adopts its release without restarting; the upgrade to 10.17.1 through a merge request; Synced and Healthy within 10 minutes; an out-of-band helm upgrade undone by selfHeal | adoption without a restart; MR !45 green (the pipeline rendered 10.17.1 with our values), Synced/Healthy 5 min 15 s after the merge; the out-of-band helm upgrade was **refused by the API server** (field ownership), the forced one undone by selfHeal within seconds | confirmed, with an addition |

## I1 adoption

`i1-init.log`, `i1-plan-1.log`, `i1-apply.log`, `i1-gitlab-before.json`, `i1-gitlab-after.json`.
Configuration: `iac/gitlab/` (project settings, protection of main, alice's membership; import blocks
in `imports.tf`). alice's access token stays outside: its value would be in the state.

## I2 state, encryption and locking

`i2-state.log` (Garage), `i2-migrate.log`, `i2-consistency.log`, `i2-lock-gitlab.log`.

- Encryption: OpenTofu state encryption, AES-GCM with a key derived (PBKDF2) from a passphrase in
  `~/.lab-secrets/v2/tofu/passphrase`; plans are encrypted too; `enforced = true`.
- Garage v2.5.0: `PUT` with `If-None-Match: *` on an existing key returned 200 twice. `use_lockfile`
  writes `<state>.tflock` that way and relies on the 412 of a second writer: on Garage every writer
  "gets" the lock, and the run that finishes removes the lock object, whoever wrote it.
- Move: the state went to GitLab's state store (project `root/platform-iac`, state `gitlab`, the
  `http` backend with GitLab's lock endpoints) with `tofu init -migrate-state -force-copy` at 12:08.
  The plan after it was cut off when the Windows host was signed out (12:08; the VM stopped). After the
  restart (`state-consistency.sh`): the target held the complete state (serial 1, 4 entries: 3
  resources and a data source), not locked, `.terraform` pointed at `http`, and the interrupted plan,
  run again, showed no changes. The outer `lineage` field of the copy in Garage (d65c153e...) differs
  from the target's (9d7788b3..., the same inside the decrypted state) - not investigated.
- GitLab's lock: a lock placed through GitLab's API; a second lock request: 409; `tofu plan`: "Error
  acquiring the state lock ... HTTP remote state already locked: ID=e11-test-0001"; after the release:
  no changes. Two plans started at the same moment: one "No changes", one "Error acquiring the state
  lock".
- Trade-off recorded for chapter 12: the state of the GitLab configuration now lives in GitLab - if
  GitLab is broken, its own state is not reachable; the copy in Garage stays as the first home.

## I3 drift

`i3-drift.log`, `i3-plan-drift.log`, `i3-apply.log`, `i3-gitlab-drifted.json`,
`i3-gitlab-restored.json`. Injected 13:51:32: main re-protected with push Developers and force push
allowed; alice Maintainer. Plan 13:51:33: exit 2. Apply 13:51:37: protection destroyed (1 s) and
created (0 s), membership modified (1 s). Plan 13:51:44: exit 0.

## I4 Argo CD manages itself

`i4/publish-1.log`, `i4/adopt.log`, `i4/adopt-dryrun-diff.txt`, `i4/out-of-band.log`,
`i4/upgrade-preview.txt`, `i4/upgrade.log`; application `gitops/platform/apps/argocd.yaml`.

1. MR !43 (pipeline 84, 42 s): the application without automated sync. Argo CD: 56 of 59 resources
   OutOfSync. A server-side dry run of the same render (`kubectl diff --server-side`): 1 object differs
   - the helm hook job `argocd-redis-secret-init`, which helm deletes after it ran; everything else
   differs only in Argo CD's tracking annotation.
2. MR !44 (pipeline 86, 35 s): automated (selfHeal, no prune). The sync ran 14:04:15-14:04:37, 60
   resources, 0 out of sync; no Argo CD pod restarted (same start times and restart counts).
3. Out of band, the E8 way: `helm upgrade` (helm v4.3.1, server-side apply) with `server.replicas=2`
   failed - conflicts with the field manager `argocd-controller` on `.spec.replicas`, the network
   policies' `.spec.ingress` and an environment variable; helm recorded revision 3 as failed, nothing
   changed. With `--force-conflicts` helm succeeded; Argo CD's automated sync started 14:05:59 and set
   1 replica again, `argocd-controller` owns `.spec.replicas` again. helm's history now says revision 4,
   2 replicas, deployed - a record that no longer describes the cluster.
4. MR !45 (pipeline 88, 31 s, the render of chart 10.17.1 with our values included): 10.14.0 ->
   10.17.1. Preview (`upgrade-preview.txt`): same images (argocd v3.6.1, redis 8.6.4), 7 objects
   changed - a pod-level `seccompProfile: RuntimeDefault` on six workloads and a label. Argo CD saw the
   new revision 244 s after the merge (polling), synced in 24 s (14:12:03-14:12:27), all its workloads
   rolled (the application controller at 14:12:29, after its own sync), Synced/Healthy at +315 s.
   The other applications: 35 Healthy and the same 4 Degraded as before - from incident E11-1.

## Incident E11-1

`incident-1.md`: after the VM restart, `openbao-init.sh` emptied the only unseal key; OpenBao and all
its snapshots are unreadable; the scripts are fixed; the sealed volume is untouched, its deletion and
the re-initialisation wait for the owner's decision (both blocked by the session's permission check as
irreversible deletions). The 4 Degraded applications (backup-jobs, insight, tenants, platform-root)
are its consequences.
