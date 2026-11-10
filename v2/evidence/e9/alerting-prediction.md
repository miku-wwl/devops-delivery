# E9 alert routing: hypotheses (written before the routing is switched on)

Until now no alert left the cluster: Alertmanager ran the chart's default configuration (receiver
"null"). Two alerts fire permanently: Watchdog (by design) and AlertmanagerClusterCrashlooping
(critical) - a false positive: Alertmanager never restarted, but in this WSL VM the monotonic clock
runs about 3 % fast against the wall clock, the kernel's boot time moves back 2 s a minute, and with it
every `process_start_time_seconds` (`clock-drift.log`: 14-15 "changes" in 10 minutes, the alert fires
above 4). The rule is disabled and replaced by one on the kubelet's restart count.

The change: Alertmanager routes critical -> `incident`, warning -> `ticket`, Watchdog -> `deadman`; all
three are webhooks of the alert bridge (`platform/alerting/bridge.py`), a container outside the cluster
next to GitLab, which opens one GitLab issue per alert in the project root/incidents (type incident
for critical) and closes it on the resolved notification; it opens an incident of its own when the
Watchdog has been silent for 180 s. New rules: platform alerts (Argo CD, OpenBao, Velero, Alertmanager
restarts) and SLO rules generated from `platform/slo/slos.yaml` (tested by the incident drill).

| | Hypothesis | Measured by |
|---|---|---|
| A1 | switching the routing on opens no issue: nothing but Watchdog fires; the bridge gets its first heartbeat within 2 minutes of Alertmanager loading the configuration | bridge event log, GitLab issues, Prometheus alerts |
| A2 | OpenBao restarted (needed anyway: the telemetry configuration loads only on a restart) comes up sealed; `OpenBaoSealed` fires and the bridge opens an incident within 2.5 minutes of the pod's start (scrape 30 s + `for` 1 m + group_wait 30 s + evaluation); after the unseal the incident is closed within 3 minutes. Confidence medium: if OpenBao's metrics endpoint answers nothing while sealed, the gauge is absent and the rule never fires | bridge log, issue, unseal time |
| A3 | a temporary application whose sync fails (a Secret written as `argocd-storefront`, forbidden - chapter 9) raises `ArgoCDSyncFailing` and a GitLab issue of kind ticket (not an incident) within 1.5 minutes of the failed sync | bridge log, issue type |
| A4 | the node that runs both Prometheus and Alertmanager (ent-worker3) is frozen (`docker pause`): no alert of the cluster can fire; the dead man's switch opens its incident 180-200 s after the last heartbeat; after the unpause the heartbeat returns and the incident is closed within a minute. PostgreSQL keeps accepting writes (synchronous ANY 1 is satisfied by the replica on ent-worker2) | bridge log, node state, writes |
| A5 | a backup of the namespace data with file-system backup completes with warnings (chapter 8) and `VeleroBackupWarnings` opens a ticket within 2 minutes of the backup's completion | backup, bridge log |
