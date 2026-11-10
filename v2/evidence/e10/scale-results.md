# E10 control plane at scale: results

Hypotheses: `scale-prediction.md` (committed before the runs). `[真实]`: etcd, kube-apiserver,
kube-controller-manager, kube-scheduler of Kubernetes v1.37.0 started by kwokctl v0.8.0 as Docker
containers, and the kwok controller. `[虚拟]`: all 1000 nodes and 10 000 pods - objects in etcd whose
status the kwok controller writes; no kubelet, no container, no image, no network. The numbers describe
the control plane's work for that many objects on one machine (a WSL VM of 15.3 GiB shared with the lab
cluster `ent`), not a cluster that could run them.

Clusters (all named `scale`, deleted after use):

| Run | Created | Flags | Used for | Records |
|---|---|---|---|---|
| k1 | 09:41 | defaults (APF on), no memory limits | K1, K4, K5 run 1 | `k1-up.log`, `k1-pods.log`, `k1-state.log`, `k4-lists.log`, `k5-apf.log`, `k1/` |
| k2 | 10:14 | `--disable-qps-limits`; memory limits per container | K2, K5 run 2, K3, restart probe | `k2-up.log`, `k2-pods.log`, `k2-state.log`, `k5-apf-rerun.log`, `k3-clean.log`, `k3-etcd.log`, `k3-etcd-down.log`, `probe-pods.log`, `restart-probe.log`, `k2-down.log` |
| k5 | after k2 | defaults (APF on); memory limits per container | K5 run 3 | `k5-up.log`, `k5-pods.log`, `k5-state.log`, `k5-apf-final.log`, `k5/`, `k5-down.log` |

Between k1 and k2 the VM froze: incident E10-1 (`incident-1.md`).

| | Hypothesis | Measured | |
|---|---|---|---|
| K1 | default scheduler client limits (50/s, burst 100) bound scheduling: about 50 pods/s, at least 3.3 min for 10 000 | first pod scheduled at 3.1 s, all 10 000 at 193.0 s; once creation had finished (54.5-164.7 s) 50.3 pods/s, a straight line; 10 000 attempts, all `scheduled` | confirmed |
| K2 | `--disable-qps-limits`: at least 5x faster; the bound moves to the scheduler's CPU and the API server's write latency | all scheduled at 29.4 s (6.6x), while the 8 creators needed 27.5 s: the scheduler kept pace with creation, so the creators were the bound. All Running at 48.6 s (the kwok controller lagged) | first part confirmed (a lower bound); second part not tested |
| K3 | etcd grows linearly, a few KB per pod; deleting does not shrink the file until a defragmentation | live (compacted, defragmented): 0 pods 17.65 MiB, 5000 35.85, 6969 43.02, 7134 43.62, 10 000 54.14 - **3.73 KiB per pod**, linear (0-5000: 3.73, 5000-10 000: 3.75). Deleting **grows** the file: +80 MiB for 10 000 pods (92.5 -> 172.7 MiB), about 8 KiB per deleted pod. The API server's compaction left the file at 178.6 MiB with 24.3 MiB in use; the defragmentation took it to 18.7 MiB | confirmed, and deletion is worse than predicted |
| K4 | a consistent LIST is served from the watch cache: latency close to resourceVersion=0, etcd not read; tens of MB | resourceVersion=0: 0.94-1.23 s; consistent: 0.88-1.06 s; 33 MiB each; one request of each kind: LISTs of pods sent to etcd +0, watch cache consistent reads +1 (consistent and a paginated walk); since the API server started: 2 LISTs of pods to etcd, 1043 consistent reads from the cache | confirmed |
| K5 | a flooding client in a priority level of 1 share gets 429 for most requests; another client's GETs keep their latency (p99 within 2x) | run 1: 97 % 429, but the victim's p99 went to 10.4 s and the VM froze (E10-1); run 2: invalid (APF was off); run 3: see below | see below |

## K1 and K2: scheduling

`k1/timeline.txt` and `k2/timeline.txt` count pods every few seconds (existing, unscheduled, Running).
The counts are separate LISTs, so while pods are still being created "existing - unscheduled" is skewed;
after creation it is exact. K1: 3331 scheduled at 54.5 s, 8876 at 164.7 s -> 50.3 pods/s, which is the
scheduler's client limit of 50 requests/s - one binding per pod, the scheduling algorithm itself is not
the bound. K2: the scheduler runs with `--kube-api-qps=5000 --kube-api-burst=10000` (container args),
so the limit is gone and scheduling followed creation.

## K3: what etcd keeps

Sizes from `etcdctl endpoint status` (db size and db size in use), not Prometheus.

1. 10 000 pods, with the history of the last 5-10 minutes: 89.3 MiB (k2 at creation), 92.5 MiB (k2
   after K5); k1 93.2 MiB. The live data for 10 000 pods is 54.1 MiB, so the history adds about 70 %.
2. `kubectl delete pods --all`: 0 pods after 119 s; file 172.7 MiB, all in use. Each deletion is new
   revisions (the graceful deletion marks the pod, the kwok controller then deletes it); the old ones
   stay until compaction. Measured again on the way down with physical compactions: 6969 -> 5000 pods
   +16.4 MiB (8.5 KiB per deleted pod), 5000 -> 0 +39.6 MiB (8.1 KiB).
3. A defragmentation right then failed: `context deadline exceeded` after etcdctl's default command
   timeout of 5 s (`k3-clean.log`). With 172 MiB of live revisions there was nothing to give back and a
   lot to copy. The scripts now pass `--command-timeout=120s`.
4. The API server compacts every 5 minutes (`--etcd-compaction-interval`, default), to the revision it
   recorded at its previous run. Its last restart was 10:18:42; the compaction showed at 10:28:47 -
   ten minutes later: the first run after a restart only synchronises with the compaction record in
   etcd, the second compacts. File 178.6 MiB, in use 24.3 MiB: the space is free inside the file.
5. Defragmentation: 0.35 s, file 18.7 MiB.
6. Live size per pod: "down" path with `compact --physical` and a defragmentation at each step
   (`k3-etcd-down.log`). The "up" path of 10:28-10:30 (`k3-etcd.log`) compacted without `--physical`:
   the defragmentation ran before the old revisions were removed, so its "compacted" sizes still hold
   history (52.9/53.3 MiB at 5000) - not used for the per-pod figure.

The pods are minimal (one container, pause image, 3.4 KB as JSON). Real pods are larger; the per-pod
figure applies to these objects only.

Two procedural errors on the way, both in the records: the named deletion of 5000 pods (one kubectl,
5000 names) ran at about 5 deletions/s - `kubectl delete pods --all` had managed at least 84/s on the
same cluster; the cause was not investigated - and was stopped by the script's 600 s timeout at 7134
pods; one re-run used the old script and labels the 7134-pod line "10000 pods" (annotated in the log).
The corrected script deletes with 16 kubectl in parallel (1969 pods in about 60 s).

## K4: LIST of 10 000 pods

`k4-lists.log`. The first attribution used `apiserver_storage_list_total`, which counts LISTs at the
storage layer including those served by the watch cache ("+110 from etcd" - wrong); the second used
`etcd_request_duration_seconds_count{operation="list",resource="pods"}` (requests actually sent to etcd)
and `apiserver_watch_cache_consistent_read_total`. The paginated walk (limit=500, 20 pages) took
5.6-7.1 s, but the client parsed every page with a new Python process to find the continue token: that
time is mostly the client's, not the server's.

## K5: one flooding client

Run 1 (k1, APF on, no memory limits, 40 workers): 1289 of 1329 flood requests 429 (p50 0.095 s), 36 504,
4 admitted (123-208 s each). The victim's GETs: quiet p50 16.8 ms, p99 42.8 ms; during the flood p50
430 ms, p99 10.4 s, and they stopped after 36 of about 120. Then the VM froze - incident E10-1.

Run 2 (k2, 20 workers, memory limits): **not a test of APF**. `--disable-qps-limits`, used for K2, also
starts the API server with `--max-requests-inflight=0 --max-mutating-requests-inflight=0
--enable-priority-and-fairness=false` (container args, checked afterwards); the FlowSchema and priority
level were accepted (the API is served) and did nothing. What it did show:
- the memory limit worked: the kernel killed kube-apiserver inside its cgroup at the limit
  (`Memory cgroup out of memory: Killed process ... (kube-apiserver) ... anon-rss:1567232kB`, four such
  lines in the kernel log), Docker restarted it - 8 restarts - and the VM kept 3438 MiB available. The
  first kill came within 1.7 s of the flood's start: 20 concurrent LISTs of 33 MiB without admission
  control. Docker's `OOMKilled` flag said false: it describes only the current run;
- the victim's view, reconstructed from its sequence: 200, then 000 (connection refused), one 403, then
  200 again - eight cycles in 55 s; 18 x 200, 61 x 000, 7 x 403, p99 of the 200s 2081 ms;
- the flood client spun against the dead server: 16 873 requests answered 000 within about 2 ms - a
  client without backoff; 2089 x 429 (not APF - see the restart probe), 156 x 403.

Restart probe (k2, 10 000 pods, `restart-probe.log`, `screens/restart-probe.png`): `docker restart` of
the API server returned after 11.7 s; LISTs as e10-flood every 0.2 s answered 000 (11.8 s), then 403
"pods is forbidden: User system:serviceaccount:default:e10-flood cannot list resource pods" (13.3 s) -
the service account has the permission, the authorizer had not yet loaded the RBAC bindings - then 429
"storage is (re)initializing" (13.6 s) - the watch cache for pods filling up - and 200 from 16.3 s.
This is what the clients of runs 2 and 3 saw after every kill. A client that treats 403 as final gives
up on a request it is allowed to make.

Run 3 (k5, defaults: APF on, memory limits, 40 workers; `k5-apf-final.log`, `k5/`):
- APF was on and classified as intended: the victim's GET went through flow schema service-accounts,
  priority level workload-low (244 nominal seats); a flood request through e10-flood, e10-low (3 seats);
- and the API server was killed 6 times at its limit of 1536 MiB (6 restarts; 6 cgroup OOM kills of
  container b41116c940d1 in `k5-oom-kernel.log`). Before the flood it held 976 MiB (`k5-state.log`);
- the probe 20 s into the flood got 429 with the message "storage is (re)initializing": after a restart
  the 429s come from the watch cache, not from APF. The per-request messages were not recorded in this
  run, so the split of its 4033 x 429 is unknown;
- flood: 17 875 requests, 13 683 x 000, 4033 x 429, 155 x 403, 4 x 200 (5.2-6.9 s each);
- victim: quiet p50 11.9 ms, p99 19.4 ms; during the flood 86 GETs: 25 x 200 (p50 100.5 ms, p99 219.0
  ms), 57 x 000, 4 x 403. K5 refuted - not by APF's queuing, by the API server's memory;
- APF's rejection counter showed +0: it lives in the process and restarts at zero.
- The same cluster repeated K1 on the way: 52 pods/s between 31 and 166 s (`k5/timeline.txt`); the
  summary line's "first 31.3 s, 64 pods/s" comes from the skewed counts during creation.

RUN4
