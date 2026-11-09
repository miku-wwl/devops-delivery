# E7 rebuild R2 (after the fixes of R1): hypotheses (written before the run)

Same procedure as R1 (`rebuild-prediction.md`) with the two fixes of R1 in Git (`r1/results.md`,
`r1/fixes.log`): the PriorityClass in the app platform-baseline (wave -8), OpenBao Ready while
sealed. pg-main restores from the archive pg-main-r1 (base backup 22:53:55 UTC) and archives as
pg-main-r2. The OpenBao restore runs as soon as its pod runs, in parallel with the rest.

| | Hypothesis | Reasoning |
|---|---|---|
| R2a | No manual fix: every application converges from Git; manual steps only the planned ones (OpenBao restore, users, load balancer limits) | both deadlocks of R1 removed |
| R2b | Only insight - the one application that needs a secret from OpenBao - waits for the OpenBao restore; PostgreSQL starts its restore without waiting | OpenBao no longer holds wave -3 |
| R2c | First order **12-15 min** after T0 | R1's 20.1 min minus what the deadlocks cost (wave -3: 7.6 min instead of about 2.5); less WAL to replay |
| R2d | RPO again the WAL not yet archived: 0-5 min of writes lost, none before the end of the last archived segment | unchanged |
