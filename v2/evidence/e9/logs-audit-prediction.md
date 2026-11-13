# E9 node-level logs and Secret reads: hypotheses (written before the checks)

| | Hypothesis | Measured by |
|---|---|---|
| L1 | the standard output of a pod that has been deleted is still readable: `kubectl logs` fails once the pod is gone, Loki (stream job=node-logs from Fluent Bit on every node) returns the marker line and the line after it within 30 s | `logs-audit.log` |
| U1 | with the audit rule added before "service accounts' reads: None", the API server records which service account read which Secret (Metadata level, no values): within a minute of the restart the log holds list/watch of Secrets by controllers (Argo CD, External Secrets, cert-manager, CloudNativePG), which re-list after the restart | audit log |
