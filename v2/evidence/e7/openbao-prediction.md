# E7 OpenBao restore rehearsal: hypotheses (written before the run)

Run: `experiments/e7/openbao-rehearsal.sh s1-openbao`. The newest hourly raft snapshot
(platform-snapshots/openbao/, made by the CronJob of `gitops/platform/manifests/backup/`) is restored
into a second, empty OpenBao of the same version next to production (`platform/secrets/openbao-restore.sh`).

| | Hypothesis | Reasoning |
|---|---|---|
| S1a | After `snapshot restore -force` the server is **sealed** and opens only with the **original** unseal key, not with the throwaway key it was initialised with | The snapshot carries the keyring encrypted with the original barrier key |
| S1b | The restored `secret/insight/api-key` equals production's (same SHA-256) | The snapshot is younger than the secret (E5) |
| S1c | The throwaway root token is rejected after the restore; the original one works | Tokens are part of the restored data |
| S1d | Rehearsal from an empty namespace to the secret read back: under 3 min | Chart install, one ~40 kB snapshot |
