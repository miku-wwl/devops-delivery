# 实验与脚本索引

> 由 `v2/docs/gen_experiment_index.py` 生成：每一行的“用途”取自脚本自己的头部注释。路径相对于 `v2/`。
> 每个阶段的假设、原始记录与结果在 `evidence/<阶段>/`；教材中的对应章节见括号。

## 平台（一次性搭建与日常操作）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `platform/alerting/bridge.py` | Alert bridge (E9, chapter 10): Alertmanager -> GitLab issues, and a dead man's switch. |
| `platform/alerting/run-bridge.sh` | The alert bridge outside the cluster (E9, chapter 10; platform/alerting/bridge.py). Idempotent: |
| `platform/backup/object-store.sh` | The backup target of chapter 8 (E7), outside the cluster: Garage, an S3-compatible object store, in the Docker container backup-s3 on the cluster's network kind-ent (pods resolve the name through Core… |
| `platform/backup/secrets.sh` | In-cluster credentials for the backup target (E7) from ~/.lab-secrets/v2/backup - the copy kept outside the cluster. Deliberately not from OpenBao: OpenBao itself is restored from this object store, a… |
| `platform/bootstrap/bootstrap.sh` | Bootstrap the platform on the ent cluster (E1): secrets that must not live in Git, the image, the configuration repository, Argo CD, and the root application. Idempotent. |
| `platform/bootstrap/build-image.sh` | Build the storefront image and push it to the local registry (localhost:5001). |
| `platform/bootstrap/publish-gitops.sh` | Publish v2/gitops to the configuration repository root/platform-gitops on the lab GitLab. |
| `platform/bootstrap/wait-apps.sh` | Wait until every Argo CD application is Synced and Healthy, printing a line whenever the picture changes (a timeline of the platform converging from Git). |
| `platform/cluster/create.sh` | Create the v2 "ent" cluster (E0): one control plane and three workers in three simulated zones. |
| `platform/cluster/lb-limits.sh` | Raise the open-file limit of the load balancers that cloud-provider-kind runs for LoadBalancer Services (one Envoy container "kindccm-*" per Service, on the Docker network). |
| `platform/cluster/measure.sh` | Resource snapshot of the machine and the "ent" cluster, layer by layer (E0 and later phases). |
| `platform/cluster/resize-workers.sh` | Change the memory size of the running workers without recreating the cluster (E7: 3072 -> 3584 MiB, capacity for the backup stack, chapter 8). Same derivation as create.sh: |
| `platform/cluster/v1-lab.sh` | Pause or resume the v1 "lab" Kind cluster to free memory for v2 (reversible; no state is lost: |
| `platform/dashboards/gen.py` | Generate Grafana dashboards as ConfigMaps for the Grafana sidecar (label grafana_dashboard=1). |
| `platform/gitops/ci-tools/build.sh` | Build and push the pipeline image (helm + kyverno) to the local registry. |
| `platform/gitops/deploy-events.sh` | Deployment events (E8, chapter 9): Argo CD notifications report every finished sync of the storefront services to GitLab's Deployments API (gitops/bootstrap/argocd-values.yaml: notifications). This gi… |
| `platform/gitops/dora.py` | DORA metrics of the storefront, from the systems that hold the facts (E8, chapter 9). |
| `platform/gitops/mr.sh` | Changes to the configuration repository root/platform-gitops go through merge requests (E8, chapter 9; the project is gated by platform/gitops/setup.sh). |
| `platform/gitops/setup.sh` | E8 (chapter 9): make the configuration repository root/platform-gitops a gated repository. |
| `platform/iac/install.sh` | OpenTofu, E11 / chapter 12: infrastructure as code for what Argo CD does not manage (the GitLab governance of the configuration repository). Installs a pinned release into ~/.local/bin after checking … |
| `platform/iac/state-project.sh` | E11 (chapter 12): the GitLab project root/platform-iac holds the OpenTofu states of v2/iac (GitLab's state store: one state per name, a lock that a second holder gets 409 for, versions kept). Private;… |
| `platform/kwok/install.sh` | kwokctl (kubernetes-sigs/kwok), E10 / chapter 11: a Kubernetes control plane whose nodes and pods are simulated by the kwok controller - no kubelet, no containers. Installs a pinned release into ~/.lo… |
| `platform/secrets/openbao-init.sh` | Initialise, unseal and configure OpenBao (E5, chapter 6). Safe to run again: it initialises only once, unseals only when sealed, and re-applies the configuration. |
| `platform/secrets/openbao-key-backup.sh` | OpenBao's unseal key, encrypted, outside the WSL VM - to be run by the OWNER (incident E11-1, action item 2). Never prints the key. |
| `platform/secrets/openbao-restore.sh` | Restore OpenBao from its newest raft snapshot in the bucket platform-snapshots (E7, chapter 8). |
| `platform/secrets/openbao-seed.sh` | The two test values of E5 (chapter 6), written into OpenBao when they are missing - after a re-initialisation (incident E11-1). Random values; they and the root token reach OpenBao through stdin, neve… |
| `platform/slo/gen.py` | Generate SLO recording rules and multi-window, multi-burn-rate alerts from slos.yaml (E9, chapter 10). |
| `platform/tenants/users.sh` | Lab users with x509 client certificates, issued by the cluster's own CA through the CSR API. |
| `platform/tools/install-cli.sh` | CLIs added by the v2 phases (the v1 lab installs its own in automation/lab/bootstrap-root.sh), pinned in platform/versions.env, checked against the release's published SHA-256 sums, installed to /usr/… |


## E1 多服务系统（第 2 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e1/trace_tree.py` | Print a Tempo trace (OTLP JSON from /api/traces/<id>) as an indented tree. |


## E2 服务网格（第 3 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e2/ab-mesh.sh` | Interleaved A/B: the same load with and without the ambient mesh, alternating, so slow drift of the host (other processes, thermal state) affects both sides equally. |
| `experiments/e2/ab-waypoint.sh` | Interleaved A/B like ab-mesh.sh, but L4 (ztunnel only) against L7 (through the waypoint): |
| `experiments/e2/capture.sh` | What does pod-to-pod traffic look like on the wire between two nodes? bash v2/experiments/e2/capture.sh <label> tcpdump runs in the network namespace of node ent-worker (a netshoot container joined to… |
| `experiments/e2/compare-windows.sh` | Where did latency change between two load runs? Medians (and p95) per service/route and per dependency call, each over a 3-minute window ending at the given UTC time. |
| `experiments/e2/exec-stall.sh` | Does "kubectl exec" into a running pod stall the application in it? (observer effect) bash v2/experiments/e2/exec-stall.sh A probe pod (outside the mesh, namespace e2-bench) calls /healthz of one paym… |
| `experiments/e2/exec_probe.py` | Latency probe: GET /healthz on one pod every 20 ms for a fixed time, over one kept-alive |
| `experiments/e2/hop-cost.sh` | Round-trip cost of the mesh, as a 2x2 matrix (see hop_cost.py). |
| `experiments/e2/hop_cost.py` | What does one round trip cost through the ambient mesh? Run inside a pod. |
| `experiments/e2/measure-mode.sh` | One E2 measurement, identical for every mesh mode (none, ambient L4, ambient + waypoint). |
| `experiments/e2/retry-layers.sh` | How many times does payments get called per customer order when it fails? ([注入] fault) bash v2/experiments/e2/retry-layers.sh <label> <status>     # status: 500 or 503 Payments answers every /charges … |
| `experiments/e2/retry-matrix.sh` | Retry layering, four scenarios with payments failing every charge ([注入]): |
| `experiments/e2/strict.sh` | What breaks when the storefront namespace refuses plaintext? (time-boxed, reverted at the end) bash v2/experiments/e2/strict.sh PeerAuthentication STRICT is applied by hand, outside Git, for about two… |


## E3 负载与容量（第 4 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e3/ab-canary.sh` | Old and new build side by side, under the same traffic at the same time. |
| `experiments/e3/burst.sh` | Many new connections at once - through the node's ztunnel, and without it. |
| `experiments/e3/burst_connect.py` | How long do new TCP connections take when many are opened at once? |
| `experiments/e3/capacity_model.py` | Capacity model from two low-load windows; predictions for higher rates. |
| `experiments/e3/diag-status.js` | What exactly fails? The storefront.js mix (70 % browse, 25 % order, 5 % lookup) at a fixed rate; every unexpected response is logged with its status, the k6 error code (0 = an HTTP response arrived; 1… |
| `experiments/e3/first-sample.sh` | Why increase() missed a burst of errors: counter series that are created by the burst itself. |
| `experiments/e3/gateway-wait.sh` | Where does a gateway request wait? Its calls to each upstream in a time window, from Prometheus. |
| `experiments/e3/lb-storm.sh` | Reproduce what happened above ~170 iterations/s in the first step load, with live captures: |
| `experiments/e3/little.sh` | Little's law per pod, from the pod's own /metrics sampled 20 times a second (little_check.py), while the storefront mix runs at <rate> iterations/s. |
| `experiments/e3/little_check.py` | Little's law on one pod, without Prometheus: sample the service's own /metrics often. |
| `experiments/e3/node-sched.sh` | CPU scheduling on the CPUs of one Kind node in a time window (node-exporter's schedstat). |
| `experiments/e3/one-replica.sh` | Capacity after losing a replica: the gateway with one pod instead of two, through GitOps. |
| `experiments/e3/probe_db.py` | Database round trips from inside a storefront pod, every 0.5 s, for SECONDS seconds. |
| `experiments/e3/profile-method.sh` | The facts behind the profiling method of chapter 4, recorded on one gateway pod (no load): |
| `experiments/e3/profile.sh` | Where does the CPU of a storefront service go? Sampling profiles under a fixed load. |
| `experiments/e3/sched-sample.sh` | CPU and run-queue time of a service's main thread, every INTERVAL seconds, from the node. |
| `experiments/e3/stalls.sh` | Event-loop stalls (>= LOOP_STALL_MS, 250 ms) reported by the watchdog of one service, from Loki. |
| `experiments/e3/step-load.sh` | Step load (open model): each rate held for STEP seconds, then the next. |
| `experiments/e3/step-ramp.sh` | Step load in ONE k6 run: a warm-up ramp, then every rate held STEP s, RAMP s between steps. |
| `experiments/e3/storm-net.sh` | Is the slow pod -> database path during the load-balancer crash loop a network problem? bash v2/experiments/e3/storm-net.sh <label> [rate] [seconds] Kernel counters (interface drops, TCP retransmissio… |
| `experiments/e3/storm-probe.sh` | Which hop is slow when readiness probes time out during the load-balancer crash loop? bash v2/experiments/e3/storm-probe.sh <label> [rate] [seconds] For one database-backed pod on each worker node, wh… |
| `experiments/e3/top_frames.py` | Where does the CPU go? Summarise py-spy raw output ("frame;frame;... count" per line). |
| `experiments/e3/traces.sh` | Traces from Tempo (via the API server proxy), for evidence. |
| `experiments/e3/tracing-cost.sh` | The cost of tracing: same load (20 iterations/s, 3 min) at a given sampling ratio. |
| `experiments/e3/warn-logs.sh` | Warnings and errors of storefront services in a time window, from Loki, summarised. |
| `experiments/e3/where-waits.sh` | For every step of a step load: where the gateway waited, and what its main thread did. |
| `experiments/e3/window_stats.py` | Resource and queueing figures for one time window, from Prometheus (via the API server proxy). |


## E4 弹性与调度（第 5 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e4/ab-limit.sh` | A CPU limit side by side (E4, chapter 5): one copy of the service's Deployment with a CPU limit next to the unlimited pods, under the same traffic at the same time. |
| `experiments/e4/evict_rank.py` | The kubelet's memory-eviction ranking of the pods on one node, and its admission headroom. |
| `experiments/e4/eviction.sh` | Node-pressure eviction: which pod goes first, and when. |
| `experiments/e4/hpa-timeline.sh` | Scale-up and scale-down timeline of the gateway's HorizontalPodAutoscaler under a load step. |
| `experiments/e4/noisy.sh` | A CPU hog next to the services: who suffers, and how much do CPU requests protect them? bash v2/experiments/e4/noisy.sh <label> <node> <rate> <seconds-per-phase> One k6 run at <rate> it/s through thre… |
| `experiments/e4/pod-table.sh` | One row per pod of the services in a time window, from Prometheus (also for past windows). |
| `experiments/e4/preemption.sh` | Priority and preemption, with a timeline. |
| `experiments/e4/promq.sh` | Instant Prometheus query, one line per series: its labels and the value (3 decimals). |
| `experiments/e4/quota.sh` | Quotas and default limits for a tenant namespace. |
| `experiments/e4/series.sh` | A few Prometheus series side by side, one row per step, for a time window (evidence tables). |
| `experiments/e4/spread.sh` | Topology spread over the three [模拟] zones while one zone cannot take new pods. |
| `experiments/e4/watch.sh` | One line every ~2 s about a scaled workload: HPA decision, Deployment replicas, pod states. |


## E5 多租户与安全（第 6 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e5/admission-restart.sh` | One Kyverno admission controller pod is deleted; does pod admission stop, and where? bash v2/experiments/e5/admission-restart.sh Every second for 70 s, a valid pod is created with --dry-run=server in … |
| `experiments/e5/admission.sh` | Admission policy: what is decided where, how fast, and what happens while the policy engine is down. |
| `experiments/e5/argocd-projects.sh` | Can an Application of project "insight" leave the team's boundary? Three attempts: |
| `experiments/e5/argocd-rbac.sh` | Argo CD's RBAC, checked offline: every row of argocd-rbac.tsv is asked with argocd admin settings rbac can" inside the argocd-server pod (it reads argocd-rbac-cm from the cluster; no login, no passwor… |
| `experiments/e5/mesh-np-diag.sh` | Why did a default-deny NetworkPolicy not stop traffic inside the ambient mesh (mesh-np.log)? bash v2/experiments/e5/mesh-np-diag.sh Server pinned to ent-worker2; clients pinned to ent-worker3 (another… |
| `experiments/e5/mesh-np-diag2.sh` | Two hypotheses from mesh-np-diag.log, tested separately (server on ent-worker2, client on ent-worker3). |
| `experiments/e5/mesh-np-diag3.sh` | mesh-np-diag2.log, part B: with a waypoint and no "waypoint -> server" rule the request still succeeded. Which path did it take? Same setup as diag2 B1 (server on ent-worker2, client on ent-worker3, p… |
| `experiments/e5/mesh-np-port.sh` | Which port does a NetworkPolicy have to allow for traffic inside the ambient mesh? bash v2/experiments/e5/mesh-np-port.sh Namespace e5-c (ambient, no waypoint); server on ent-worker2. Each step uses a… |
| `experiments/e5/mesh-np.sh` | NetworkPolicy outside and inside the ambient mesh, one rule at a time. |
| `experiments/e5/net-validate.sh` | After the NetworkPolicies: does everything that should work still work - with NEW connections? bash v2/experiments/e5/net-validate.sh A policy does not cut connections that existed before it (mesh-np-… |
| `experiments/e5/np-probe.sh` | Does this cluster enforce NetworkPolicy at all? (kindnet, outside the mesh) bash v2/experiments/e5/np-probe.sh In namespace e5-np (not in the ambient mesh): a web server pod and a client pod. |
| `experiments/e5/rbac-matrix.sh` | Run the RBAC test matrix as the real users: every row of rbac-matrix.tsv is asked with that user's own client certificate (kubectl auth can-i -> a SelfSubjectAccessReview), so the answer comes from th… |
| `experiments/e5/reach.sh` | Who can reach whom: a probe pod in each source namespace tries every target with an application-level request (reach_probe.py) and the results are printed as a matrix. |
| `experiments/e5/reach_probe.py` | Reachability with an application-level answer. |
| `experiments/e5/secrets.sh` | Secrets from OpenBao through the External Secrets Operator (chapter 6). |
| `experiments/e5/who-did-what.sh` | Real requests with the lab users' own certificates, then the same story told by the API server's audit log alone: who, as whom, did what, to which object, allowed or not, and why. |


## E6 故障注入（第 7 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e6/fault-phase.sh` | One fault-injection phase under load ([注入]): steady state, fault, recovery - one k6 run. |
| `experiments/e6/node-failure.sh` | A worker stops answering ([注入]: docker pause freezes the node container - kubelet, containerd and every pod on it), under load. Timeline and SLO impact. |
| `experiments/e6/partition.sh` | A network partition between one zone and the other two ([注入]), under load. |


## E7 数据可靠性（第 8 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e7/failover.sh` | PostgreSQL failover drills (E7, chapter 8), measured with the drill writer (writer.py). |
| `experiments/e7/openbao-rehearsal.sh` | Restore rehearsal S1 (E7, chapter 8): the newest hourly OpenBao snapshot into a second, empty OpenBao next to production (namespace e7-bao-restore), opened with the original unseal key; one secret rea… |
| `experiments/e7/pg-watch.sh` | Once per second until killed: what CloudNativePG and Kubernetes say about pg-main (E7). |
| `experiments/e7/pitr.sh` | Point-in-time recovery drill on the storefront's orders (E7, chapter 8). |
| `experiments/e7/rebuild.sh` | Rebuild drill R1 (E7, chapter 8): the cluster "ent" is lost as a whole (kind delete cluster) and rebuilt from what lives outside it - Git (GitHub, GitLab), the image registry and mirrors, the object s… |
| `experiments/e7/velero-drill.sh` | Velero drills (E7, chapter 8). The velero CLI runs inside the Velero pod: its download URLs point to backup-s3:3900, a name only the cluster network resolves. |
| `experiments/e7/writer.py` | Drill writer (E7, chapter 8): numbered INSERTs into drill.writes at a fixed rate, every attempt |
| `experiments/e7/writer.sh` | The drill writer (writer.py) as a pod in the namespace data (E7). |
| `experiments/e7/writer_report.py` | Report on a drill (E7): the writer's log against the rows that exist afterwards. |


## E8 发布治理（第 9 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e8/abort_report.py` | Report of the canary abort drill (E8, chapter 9) from probe.py's log. |
| `experiments/e8/audit_who.py` | Who wrote what - from the Kubernetes audit log (E8, chapter 9). |
| `experiments/e8/canary-abort.sh` | Canary abort drill (E8, chapter 9; hypothesis C3 in evidence/e8/canary-prediction.md). |
| `experiments/e8/canary.js` | E8 (chapter 9): which version answers? A constant rate of GET /api/products through the layer-7 entrance; every response is counted by its X-Storefront-Version header (set by every storefront service … |
| `experiments/e8/freeze-drill.sh` | Change freeze drill (E8, chapter 9; hypotheses F1-F4 and D1-D2 in evidence/e8/freeze-prediction.md). |
| `experiments/e8/gate-drill.sh` | The merge-request gate drill (E8, chapter 9): alice (team shop, Developer) proposes four changes to the catalog's production release, three of them against a release policy; then a direct push to main… |
| `experiments/e8/impersonation.sh` | Argo CD sync impersonation (E8, chapter 9; hypotheses I1-I5 in evidence/e8/impersonation-prediction.md). |
| `experiments/e8/lab-state.sh` | The lab's state after a phase (E8, chapter 9; reused for later cleanup logs): what stays, what the drills left behind. Read-only.   bash v2/experiments/e8/lab-state.sh > v2/evidence/eN/cleanup.log |
| `experiments/e8/probe.py` | Probe (E8, chapter 9): one GET every INTERVAL seconds through the layer-7 entrance, each one |
| `experiments/e8/rebuild-run.sh` | Rebuilds R3 and R4 (E8, chapter 9; hypotheses W1-W5 in evidence/e8/waves-prediction.md): the runbook of chapter 8 (experiments/e7/rebuild.sh) end to end, without pauses between the steps - destroy, DR… |


## E9 可观测性（第 10 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e9/clock-drift.sh` | Why AlertmanagerClusterCrashlooping fires without a restart (E9, chapter 10). |
| `experiments/e9/deadman.sh` | A4 (E9, chapter 10; evidence/e9/alerting-prediction.md): the node that runs Prometheus and Alertmanager is frozen - only the dead man's switch outside the cluster can tell. |
| `experiments/e9/exemplars.sh` | X1/X2 (E9, chapter 10; evidence/e9/exemplars-prediction.md): exemplars that lead to kept traces. |
| `experiments/e9/incident-drill.sh` | Incident drill (E9, chapter 10; hypotheses S1-S6 in evidence/e9/incident-prediction.md). |
| `experiments/e9/logs-and-audit.sh` | E9 (chapter 10): node-level logs and service accounts' Secret reads (hypotheses L1, U1 in evidence/e9/logs-audit-prediction.md).   bash v2/experiments/e9/logs-and-audit.sh > v2/evidence/e9/logs-audit.… |
| `experiments/e9/openbao-sealed.sh` | A2 (E9, chapter 10; evidence/e9/alerting-prediction.md): OpenBao restarted -> sealed -> alert -> GitLab incident -> unseal -> incident closed. |
| `experiments/e9/tickets.sh` | A3 and A5 (E9, chapter 10; evidence/e9/alerting-prediction.md): warnings become GitLab tickets. |
| `experiments/e9/tracing-cost.sh` | Tracing cost (E9, chapter 10): what the services and the collector spend at the current head sampling ratio, under the running k6 load (10 iterations/s). Run once at 10 % and once at 100 %. |


## E10 大规模控制面（第 11 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e10/apf.sh` | K5 (E10, chapter 11): API Priority and Fairness against one flooding client, in the kwok cluster. |
| `experiments/e10/etcd-size.sh` | K3 (E10, chapter 11): what etcd keeps per pod, and what deleting, compacting and defragmenting do to it. |
| `experiments/e10/restart-probe.sh` | E10, K5 re-run follow-up: what a client sees while kube-apiserver restarts (kwok cluster "scale", 10 000 pods). |
| `experiments/e10/scale.sh` | E10 (chapter 11): a real control plane under virtual load (hypotheses in evidence/e10/scale-prediction.md). |


## E11 IaC（第 12 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/e11/drift.sh` | E11 I3 (chapter 12): manual changes to the governance of root/platform-gitops - does OpenTofu see them, and does apply put the declared values back?   bash v2/experiments/e11/drift.sh [注入] the drift: … |
| `experiments/e11/gitlab-snapshot.sh` | E11: the governance of root/platform-gitops as GitLab reports it (sorted JSON; no tokens). |
| `experiments/e11/state-check.sh` | E11 I2 (chapter 12): is the remote state encrypted, and does the lock exclude a second run? bash v2/experiments/e11/state-check.sh Talks S3 to Garage directly with curl's SigV4 (the key goes to curl t… |
| `experiments/e11/state-consistency.sh` | E11 (chapter 12): after an interrupted state migration - which copy is where, is anything locked? Read-only.   bash v2/experiments/e11/state-consistency.sh Source: Garage (bucket tofu-state, the first… |
| `experiments/e11/state-lock-gitlab.sh` | E11 I2 (chapter 12): the same lock test as experiments/e11/state-check.sh, against GitLab's state store: a foreign lock placed through GitLab's lock API, then tofu plan; then two plans at once. |
| `experiments/e11/watch-argocd.sh` | E11 I4 (chapter 12): watch Argo CD sync itself after a merge - every change of the application argocd (revision, sync, health, operation) and of its pods, until it is Synced and Healthy at the expecte… |


## 负载脚本（k6）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/load/connections.sh` | Who holds TCP connections to whom? Counted on the SERVER side of every storefront pod. |
| `experiments/load/distribution.sh` | How evenly does each service's traffic spread over its replicas? bash v2/experiments/load/distribution.sh [window, default 5m] Server-side request counts per pod over the window (Prometheus, through t… |
| `experiments/load/k6_warnings.py` | Collapse k6's per-request "Request Failed" warnings in a k6 output or a transcript. |
| `experiments/load/storefront.js` | Storefront traffic for experiments E1-E9 (k6 v2.3.0). |


## v2.0.0 之后的运维清理

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `experiments/ops-1/check.sh` | Operational cleanup after v2.0.0 (P0-P2): the lab's state, read-only. No key, token or certificate is printed - keys are checked by structure and compared with cmp, tokens report only their metadata (… |


## E11 基础设施即代码

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `iac/tofu.sh` | E11 (chapter 12): OpenTofu for one configuration under v2/iac, with the lab's secrets. |


## E12 能力考核（第 13 章）

| 脚本 | 用途（取自脚本自己的头部注释） |
|---|---|
| `assessment/lib.sh` | Shared by the assessment scripts of E12 (chapter 13). Sourced, not run. |
| `assessment/p1-inhibition.sh` | P1 (E12, chapter 13) - practical exam: close action item 5 of incident E11-1. |
| `assessment/t1-argocd-repo.sh` | T1 (E12, chapter 13) - "a change merged ten minutes ago has not reached the cluster". |
| `assessment/t2-openbao-restart.sh` | T2 (E12, chapter 13) - "secrets stopped refreshing after a restart" (incident E11-1 as an exercise). |
| `assessment/t3-out-of-band.sh` | T3 (E12, chapter 13) - "checkout fails, browsing works, Git and Argo CD say everything is in order". |

