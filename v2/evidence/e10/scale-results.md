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
| k5 | 11:00 | defaults (APF on); memory limits per container | K5 run 3 | `k5-up.log`, `k5-pods.log`, `k5-state.log`, `k5-apf-final.log`, `k5/`, `k5-down.log` |
| k6 | 11:09 | as k5, plus `GOMEMLIMIT=1300MiB` for kube-apiserver | K5 run 4 | `k6-up.log`, `k6-pods.log`, `k6-state.log`, `k6-apf.log`, `k6/`, `k6-down.log` |
| k7 | 11:27 | as k5, 5000 pods instead of 10 000 | K5 run 5 | `k7-up.log`, `k7-pods.log`, `k7-state.log`, `k7-apf.log`, `k7/`, `k7-down.log` |

Kernel log of all cgroup OOM kills: `k5-oom-kernel.log` (and the count per run in the `apf` logs).

Between k1 and k2 the VM froze: incident E10-1 (`incident-1.md`).

| | Hypothesis | Measured | |
|---|---|---|---|
| K1 | default scheduler client limits (50/s, burst 100) bound scheduling: about 50 pods/s, at least 3.3 min for 10 000 | first pod scheduled at 3.1 s, all 10 000 at 193.0 s; once creation had finished (54.5-164.7 s) 50.3 pods/s, a straight line; 10 000 attempts, all `scheduled` | confirmed |
| K2 | `--disable-qps-limits`: at least 5x faster; the bound moves to the scheduler's CPU and the API server's write latency | all scheduled at 29.4 s (6.6x), while the 8 creators needed 27.5 s: the scheduler kept pace with creation, so the creators were the bound. All Running at 48.6 s (the kwok controller lagged) | first part confirmed (a lower bound); second part not tested |
| K3 | etcd grows linearly, a few KB per pod; deleting does not shrink the file until a defragmentation | live (compacted, defragmented): 0 pods 17.65 MiB, 5000 35.85, 6969 43.02, 7134 43.62, 10 000 54.14 - **3.73 KiB per pod**, linear (0-5000: 3.73, 5000-10 000: 3.75). Deleting **grows** the file: +80 MiB for 10 000 pods (92.5 -> 172.7 MiB), about 8 KiB per deleted pod. The API server's compaction left the file at 178.6 MiB with 24.3 MiB in use; the defragmentation took it to 18.7 MiB | confirmed, and deletion is worse than predicted |
| K4 | a consistent LIST is served from the watch cache: latency close to resourceVersion=0, etcd not read; tens of MB | resourceVersion=0: 0.94-1.23 s; consistent: 0.88-1.06 s; 33 MiB each; one request of each kind: LISTs of pods sent to etcd +0, watch cache consistent reads +1 (consistent and a paginated walk); since the API server started: 2 LISTs of pods to etcd, 1043 consistent reads from the cache | confirmed |
| K5 | a flooding client in a priority level of 1 share gets 429 for most requests; another client's GETs keep their latency (p99 within 2x) | seven runs (below): APF rejected and queued as configured, but the API server ran out of memory in every run (VM froze in run 1; 40 cgroup OOM kills in runs 2-7) and the victim's p99 rose 9.5-243x | refuted; follow-up hypotheses K5b-K5e refuted or partly confirmed |

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

Hypothesis K5b (added before run 4, `scale-prediction.md`): the API server dies because Go's collector
lets the heap grow to twice the live data and does not know the container's limit; with GOMEMLIMIT it
survives.

Run 4 (k6, as run 3 plus `GOMEMLIMIT=1300MiB` through kwokctl's `componentsPatches.extraEnvs`;
`k6-up.log`, `k6-state.log`, `k6-apf.log`, `k6/`):
- the limit was in effect: `go_gc_gomemlimit_bytes 1.3631488e+09`, `go_gc_gogc_percent 100`;
- the API server was still killed 4 times (4 restarts, 4 cgroup OOM kills); 997 MiB resident before the
  flood. **K5b refuted**: under this flood the API server needs more than 1.5 GiB with 10 000 pods; the
  collector's headroom is not the whole story;
- the 429s, now with their messages: 1528 "storage is (re)initializing" (the watch cache after a
  restart) and 2543 without a JSON Status - APF answers its rejections as plain text; its counter showed
  54 rejections, reason queue-full, flow schema e10-flood, since the last restart;
- flood: 13 688 requests, 9438 x 000, 4071 x 429, 153 x 403, 26 x 200 (p50 7.4 s, p99 9.3 s);
- victim: quiet p50 12.4 ms, p99 19.4 ms; during the flood 80 GETs, 35 x 200 (p50 105.9 ms, p99 1799.5
  ms), 42 x 000, 3 x 403.

Hypothesis K5c (added before run 5): half the objects, the same limit - the API server survives.

Run 5 (k7, as run 3 with 5000 pods; `k7-*.log`, `k7/`): **K5c refuted**. The API server rested at 662
MiB of anonymous memory and was killed 8 times. The per-second samples of its cgroup
(`k7/apf-apiserver-mem.txt`) show how: 662 MiB until the flood, then 825, 1172, 1523 MiB in the next
three seconds - killed; after each restart it climbed past 1.2 GiB again within about 8 s. All 4033
429s carried APF's plain-text message "Too many requests, please try again later." (the watch cache of
5000 pods fills too quickly to refuse anything). Victim: quiet p99 15.6 ms; during the flood 46 x 200
(p50 99.8 ms, p99 1386.7 ms), 33 x 000, 6 x 403. A rise of about 200 MiB/s cannot come from one LIST at
a time.

The flaw in the experiment's design (`apf-explain.log`, `kubectl explain` against the v1.37 server):
e10-low was given `lendablePercent: 0` - it lends nothing - but no `borrowingLimitPercent`, and "when
this field is left nil, the limit is effectively infinite". None of the suggested priority levels sets
it, and they lend: workload-low 90 % of its 244 seats, workload-high 50 %, global-default 50 %, system
33 %, node-high 25 %. Under demand, the "3-seat" level could borrow a few hundred idle seats - and run
dozens of 33 MiB LISTs at once.

Hypothesis K5d (added before run 6): with `borrowingLimitPercent: 0` e10-low keeps 3 seats and the
API server survives; without it, e10-low borrows and the API server dies as before.

Run 6 (k8, 10 000 pods, defaults, 1536 MiB; two floods on the same cluster; `k8-*.log`, `k8/`, `k8b/`):
- 6a, `borrowingLimitPercent: 0`: e10-low's current limit stayed at 3 seats (`k8/apf-seats.txt`, every
  2 s: limit 3, 3 seats executing, 3 requests executing, 5 queued) - and the API server was still killed
  5 times. Its anonymous memory (`k8/apf-apiserver-mem.txt`): 938 MiB at rest, then 1066, 1204, 1487
  MiB within about 4 s of the flood - killed; after each restart it climbed back past 1.4 GiB. Three
  concurrent LISTs of 10 000 pods (33 MiB of JSON each) cost about 180 MiB each. 429s: 3375 APF, 650
  watch cache. Victim: quiet p99 20.7 ms; flood 36 x 200 (p50 78.7 ms, p99 436.9 ms), 44 x 000, 4 x 403;
- 6b, borrowing limit removed again: e10-low's current limit rose to 7 seats (`k8b/apf-seats.txt`:
  7 executing, 5 queued) - it borrowed 4 - and the API server was killed 8 times (kernel log: 13 kills
  of container 9acd43d5c26a for 6a and 6b together). Victim: quiet p99 14.7 ms; flood 35 x 200 (p99
  1539.7 ms), 44 x 000, 6 x 403. (The restart count line failed: the cgroup was gone at that moment;
  fixed in `scale.sh`.)

K5d: the borrowing part confirmed (3 vs 7 seats); "the API server survives" refuted. APF limited
exactly what it was configured to limit; three seats of full LISTs did not fit into the memory left.

Hypothesis K5e (added before run 7): with 2560 MiB the API server survives (peak about 1.8 GiB) and
the victim keeps p99 within 2x.

Run 7 (k9, as 6a with the API server limited to 2560 MiB; `k9-*.log`, `k9/`):
- e10-low held 3 seats (3 executing, 5 queued) until the kill; APF rejected 428 requests (queue-full)
  in the process that survived to the end; 429s: 3711 APF, 1138 watch cache;
- the API server's anonymous memory: 1018 MiB at rest, 1560 MiB one second into the flood, 2437 MiB
  after 8 s, flat for 10 s, then 2552 MiB - killed once (1 restart, 1 cgroup OOM kill). After the
  restart it held 1.6-2.0 GiB under the same flood until the end, without a second kill;
- victim: quiet p50 13.0 ms, p99 20.3 ms; during the flood 91 GETs, 44 x 200 (p50 70.5 ms, p99 193.8
  ms), 46 x 000, 1 x 403. Most failures came after the restart while the process was alive (25 in a
  row); their cause (the API server not yet serving, or the connection path under 40 churning clients)
  was not determined.

**K5e refuted**: the peak was not 1.8 GiB but above 2.5 GiB - three concurrent LISTs of 10 000 pods
add about 1.4 GiB including the garbage collector's headroom (the 180 MiB per LIST of run 6a was a
slope before a kill, not a size) - and the victim's successful GETs were about 5x slower at the median
and 9.5x at p99.

kwokctl's `--disable-qps-limits`, recorded on a throwaway cluster afterwards (`k2-flags.log`):
kube-apiserver `--max-requests-inflight=0 --max-mutating-requests-inflight=0
--enable-priority-and-fairness=false`; kube-scheduler and kube-controller-manager `--kube-api-qps=5000
--kube-api-burst=10000`.

### K5 overall

Refuted in all seven runs: no run kept the victim's p99 within 2x, and every run lost the API server at
least once. What the runs established:

1. APF did what it was configured to do: classification (flow schema, priority level, checked through
   the response headers), 3 seats and a queue of 5 (sampled), 429 with "Too many requests" for the rest.
2. A priority level without `borrowingLimitPercent` borrows: e10-low went from 3 to 7 seats (run 6b).
3. Seats are not memory: three concurrent full LISTs of 10 000 pods (33 MiB of JSON each) took the API
   server from about 1.0 GiB to 2.4 GiB (run 7); at 1536 MiB it was killed within seconds in runs 3-6,
   and GOMEMLIMIT did not help (run 4). Even while it was up, the other client's GETs were 5-10x slower.
4. A memory limit on the container turned the freeze of the whole VM (run 1) into kills of one process
   (runs 2-7: 40 kills - 8, 6, 4, 8, 13, 1 - the VM always responsive). A killed API server restarts into more load: 403
   until RBAC is loaded, 429 while the watch cache fills, the re-lists of every component.
5. The client is the place to fix: no full LISTs in a loop (informers, pagination for a bounded
   response, backoff on 429 and on connection failures - the flood client sent up to 16 873 requests
   into a dead server in 60 s).
