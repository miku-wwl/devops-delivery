# Incident E11-1: a recovery script destroyed the only unseal key (2026-11-10)

Blameless. Unplanned; everything below happened. Status: **resolved** 22:40 UTC - OpenBao
re-initialised after the owner's approval, the sealed data kept on a retained volume; follow-ups in the
last section.

## What happened

| Time (UTC) | |
|---|---|
| ~12:08 | The Windows host stopped responding and the owner signed out; the WSL VM stopped with it, in the middle of E11's state migration (the plan after `tofu init -migrate-state` was cut off). OpenBao, like after every restart, would come back sealed |
| 13:43 | The VM started again. Containers with a restart policy came up, the four kind nodes included; all Ready within seconds |
| 13:44:03 | The routine step after a restart, `platform/secrets/openbao-init.sh` ("unseal"), ran. The pod's status still said Running from before the restart, so the script's `kubectl wait` passed, but the container did not exist yet (`container not found`). The status check swallowed the error (`\|\| true`), read "not initialised" and ran `bao operator init ... > init.json`. **The shell emptied `init.json` before the command failed.** The file held the only copy of the unseal key and of the root token |
| 13:44:24 | The container started. A second run tried to unseal with the empty file: `400 'key' must be specified` |
| 13:45 | Found: `init.json` 0 bytes, modified 13:44:03; no other copy on the machine (a search for `unseal_keys_b64`); the throwaway key of the last restore (`init-throwaway.json`, E8's rebuild R4) does not open the restored keyring - tried, refused |
| 13:47:39 | The alert `OpenBaoSealed` (chapter 10, `for: 1m`) opened incident #14 in GitLab `root/incidents` through the alert bridge - the alerting worked |
| 13:46-13:50 | Both scripts fixed (`openbao-init.sh`, `openbao-restore.sh`); wiping the sealed storage and re-initialising was stopped by the session's permission check as an irreversible deletion - left for the owner. A safer variant (keep the data on a retained volume) was stopped the same way |
| 13:57-22:39 | The sealed OpenBao keeps the hourly snapshot job failing: the alert bridge opens **54 GitLab incidents from this one cause** (16 ArgoCDAppDegraded, 10 KubeJobFailed, 27 KubeContainerWaiting, besides OpenBaoSealed) - each failed job and pod is a new alert, closed and reopened every hour |
| ~22:37 | The owner decides: re-initialise, keep the old data (and store a copy of the new key personally) |
| 22:38:15 | The old volume (`pvc-a98749bd...`, 9.5 MiB on ent-worker) set to reclaim policy Retain; the emptied key file kept as `init.json.truncated-20261110T134403Z`; the claim released, the pod deleted: a new pod with a fresh volume at 22:38:29; the old volume stays, Released |
| 22:38:33 | `openbao-init.sh` (fixed): initialised, unsealed, configured; the new key in `init.json` and `init.json.copy`, both read-only |
| 22:39:14 | `platform/secrets/openbao-seed.sh`: the two E5 test values written anew (random); both SecretStores Valid and insight's ExternalSecret synced 3 s later |
| 22:39:20 | A snapshot with the new key: a job from the CronJob, `openbao/20261110T223920Z.snap` (30233 bytes) uploaded to Garage |
| 22:39:39 | 39 of 39 applications Synced and Healthy |
| 22:40:15 | The bridge closes incident #14 (OpenBaoSealed) |

Recovery log: `incident-1/recovery.log`.

## Impact

- OpenBao's data cannot be read by anyone, ever. It held the configuration (KV store, Kubernetes
  auth, two tenant policies and roles, the snapshot role - all re-applied by the script) and two random
  test values written by E5 (`secret/insight/api-key`, `secret/shop/db-password`).
- **Every OpenBao snapshot in Garage is worthless**: the hourly raft snapshots of E7 are encrypted with
  the lost keyring. The backup chain of chapter 8 was intact and is useless without its key.
- No workload was affected: the one consumer, insight's ExternalSecret, reports `SecretSyncedError` and
  its Secret `insight-api-key` keeps the last value (the External Secrets Operator does not delete it);
  both SecretStores report `InvalidProviderConfig`. The hourly snapshot job fails while OpenBao is
  sealed.

## Why

- **"No answer" read as "not initialised".** The status function returned nothing when the exec failed,
  and an empty status is not `true`.
- **A stale pod status.** `kubectl wait --for=jsonpath='{.status.phase}'=Running` was satisfied by the
  status the pod had before the VM stopped.
- **Redirection truncates first.** `cmd > file` empties the file before `cmd` runs; the file was
  writable.
- **One copy.** Chapters 6 and 8 recorded the single key as a lab simplification ("解封密钥只有一份…快照
  无法打开"). The risk was known and accepted; this is what it costs.

## Action items

| # | | Status |
|---|---|---|
| 1 | `openbao-init.sh` and `openbao-restore.sh`: wait until OpenBao itself answers; a status counts only from an answer; never initialise while a key file exists; write a new key to a temporary file and move it into place; keep it read-only (a stray `>` then fails) and keep a second copy | done |
| 2 | A copy of the key outside the VM - the owner's decision: the owner keeps a copy (password manager); in the VM two read-only files | with the owner |
| 3 | Initialise anew, re-seed the two test values, check the External Secrets sync and a fresh snapshot | done 22:38-22:40 (owner's approval) |
| 4 | The sealed data: kept on the retained volume `pvc-a98749bd-0275-4dee-b6f0-5ff0092094db` (Released) in case a copy of the old key turns up; deleting it is the owner's call | open (owner) |
| 5 | **Alert storm**: one cause, 54 incidents in 9 hours. Inhibit the symptoms of a sealed OpenBao (failed jobs and waiting containers in namespace `secrets`, the Degraded applications that depend on it) while `OpenBaoSealed` fires - and test it by sealing OpenBao on purpose | open |
| 6 | Chapter 12 records the incident; the limitation notes of chapters 6 and 8 point to it | done (chapter 12) |
