# E10 control plane at scale: hypotheses (written before the runs)

What is real and what is not. `[真实]`: the control plane - etcd, kube-apiserver, kube-controller-manager
and kube-scheduler of Kubernetes v1.37.0, started by kwokctl v0.8.0 as Docker containers next to the lab
cluster, plus a Prometheus that scrapes them. `[虚拟]`: every node and every pod - the kwok controller
writes their status (Ready, Running) and renews the node leases; no kubelet runs, no container is ever
started, nothing is scheduled onto CPU or memory that exists. The numbers below therefore describe the
control plane's work for N nodes and pods, not a cluster that could run them; they come from one
machine (16 threads, a WSL VM of 15.3 GiB shared with the lab cluster `ent`).

Load: 1000 virtual nodes; 10 000 pods (100m CPU and 128Mi requested each, tolerating every taint),
created by 8 parallel `kubectl create` processes so that creation outruns scheduling.

| | Hypothesis | Measured by |
|---|---|---|
| K1 | with the scheduler's default client limits (50 requests/s, burst 100) scheduling is bounded by them: one binding per pod, so at most about 50 pods/s - 10 000 pods take at least 3.3 minutes | scheduler metrics (scheduled attempts over time), timeline |
| K2 | with `--disable-qps-limits` the same 10 000 pods are scheduled at least 5 times faster; the bound moves to the scheduler's CPU and the API server's write latency | the same, second cluster |
| K3 | etcd grows linearly with the objects, a few KB per pod (the object and its events); deleting the pods does not shrink the database file until a defragmentation | `etcd_mvcc_db_total_size_in_bytes`, `apiserver_storage_objects` |
| K4 | Kubernetes 1.37 serves a consistent LIST of all pods (resourceVersion unset) from the watch cache (ConsistentListFromCache): its latency is close to resourceVersion=0 and etcd is not read for it; the response for 10 000 pods is tens of MB | wall time of the requests, `apiserver_cache_list_total` vs `apiserver_storage_list_total` |
| K5 | a client flooding LISTs of all pods, put by a FlowSchema into a priority level with one concurrency share and a short queue, receives 429 (Too Many Requests) for most of its requests, while another client's small GETs in a different priority level keep their latency (p99 within 2x of the quiet value) | client status codes and latencies, `apiserver_flowcontrol_rejected_requests_total` |

Limits stated before measuring: one run per configuration; the control plane shares the host with
`ent`, so absolute numbers depend on what `ent` does meanwhile; real kubelets would add their own load
(pod status updates, node heartbeats come from kwok here), and real nodes would add image pulls,
container starts and network setup that are absent here.

## Added 2026-11-10 11:15 UTC, after K5 run 3 and before run 4

Run 3 (defaults, APF on, kube-apiserver limited to 1536 MiB): APF classified the flood correctly
(flow schema e10-flood, priority level e10-low, 3 nominal seats), and still the API server was killed 6
times by the kernel at its cgroup limit. Before the flood it held 976 MiB. Go's garbage collector lets
the heap grow to about twice the live heap before collecting (GOGC=100) and does not know the
container's limit unless GOMEMLIMIT is set; the containers of kwokctl do not set it.

| | Hypothesis | Measured by |
|---|---|---|
| K5b | with `GOMEMLIMIT=1300MiB` (85 % of the container's 1536 MiB) the API server is not killed during the same flood (40 workers, 60 s): 0 OOM kills, 0 restarts; the flood's 429 carry APF's message ("Too many requests"), not the watch cache's; the victim's GETs keep p99 within 2x of the quiet value | kernel log, restart count, 429 messages, victim latencies (`scale.sh apf`) |

## Added 2026-11-10 11:25 UTC, after K5 run 4 and before run 5

Run 4: K5b refuted - GOMEMLIMIT was in effect (`go_gc_gomemlimit_bytes` 1363148800) and the API server
was still killed 4 times at 1536 MiB. Not only the collector's headroom: under this flood the API server
needs more than 1.5 GiB with 10 000 pods. Every run so far lost the API server, so K5's question - does
APF keep another client's latency - is still open. Run 5 halves the objects instead of raising the limit
(the VM cannot spare more memory while the lab cluster runs).

| | Hypothesis | Measured by |
|---|---|---|
| K5c | with 5000 pods (a LIST of about 16.5 MiB) and everything else as in run 3 - defaults, APF on, kube-apiserver limited to 1536 MiB, no GOMEMLIMIT, 40 workers for 60 s - the API server is not killed; the flood's 429 are APF's; the victim's GETs keep p99 within 2x of the quiet value | kernel log, restarts, 429 messages, victim latencies, the API server's cgroup memory every second |
