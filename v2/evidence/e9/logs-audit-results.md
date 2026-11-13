# E9 node-level logs and Secret reads: results

Hypotheses: `logs-audit-prediction.md` (committed in 12493cf before the checks). Record: `logs-audit.log`.

| | Hypothesis | Measured | |
|---|---|---|---|
| L1 | a deleted pod's standard output is still readable from Loki within 30 s | the marker line of e9-logprobe (written 07:31:00.44, pod deleted 07:31:09; `kubectl logs`: NotFound) **is in Loki** (`{job="node-logs"} |= "E9-MARKER"`) - but not within the first query at 07:31:28, and in a stream **without** namespace/pod labels | confirmed with two caveats |
| U1 | service accounts' Secret reads recorded within a minute of the API server's restart | API server restarted 07:31:30, ready 07:31:38; in the next minute 30 service accounts' get/list/watch of Secrets, e.g. External Secrets `get insight/insight-api-key`, `data:pg-main` reading `pg-backup-s3`, Kyverno its TLS secrets, Argo CD its notifications secret | confirmed |

The caveats of L1: Fluent Bit's tail input looks for new files every 60 s (`Refresh_Interval`
default) - it found the 9-second pod's file only after the pod was deleted (the kubelet had not yet
removed the file), and that moment fell into the API server's restart, so the metadata lookup failed
(`kube api upstream connection error`, 07:31:30-31) and the line went out with the job label only.
Of 75 streams, the others carry namespace, pod, container and node. Changed: `Refresh_Interval 5`. A
pod shorter than the refresh interval whose file the kubelet removes first is still lost.
