# 可观测性与事故响应（E9） {#ch-e9}

<div class="lead">到第 9 章为止，平台测量了很多东西，却几乎从不主动告诉任何人：Alertmanager 用的是默认配置，所有告警都送进了“null”。本章让告警离开集群：严重的变成 GitLab 中的事故，一般的变成工单，告警链路本身由集群外的“死人开关”看守。告警规则从 SLO 规格生成，按多窗口、多燃烧率触发；日志改为在每个节点收集，链路改为尾部采样，审计日志开始记录谁读了哪个密钥。最后用一次真实的事故演练检验整条链：从一个看似无害的合并请求，到被呼叫、定位、撤回、关闭，再到复盘与行动项。</div>

## 本章目标与产出

| 产出 | 位置（相对于 `v2/`） |
|---|---|
| 集群外的告警桥：Alertmanager → GitLab 事故与工单，死人开关 | `platform/alerting/bridge.py`、`platform/alerting/run-bridge.sh` |
| 告警路由、抑制与平台告警（Argo CD、OpenBao、Velero、Alertmanager 重启），处置手册 | `gitops/platform/values/monitoring.yaml`、`gitops/platform/manifests/alerts/`、`docs/runbooks.md` |
| SLO 规格与生成器：记录规则、多窗口多燃烧率告警、SLO 看板 | `platform/slo/`、`platform/dashboards/gen.py` |
| 节点级日志（Fluent Bit → Loki）、尾部采样、记录服务账号读取 Secret 的审计规则 | `gitops/platform/values/node-logs.yaml`、`gitops/platform/values/otel-collector.yaml`、`platform/cluster/audit-policy.yaml` |
| 事故演练脚本、时间线与复盘 | `experiments/e9/`、`evidence/e9/incident/` |
| 每组实验前提交的假设与全部测量记录 | `evidence/e9/` |

**学完本章，你应当能够：**

- 设计一条不与被监控对象同处一个故障域的告警链路，并用死人开关检测它自身的失效；
- 从 SLO 推导多窗口、多燃烧率告警，事先算出一次故障多久之后才会呼叫值班人员；
- 用路由与抑制区分“立即处理”和“工作时间处理”，避免一次故障触发一串告警；
- 在节点上收集日志，使被删除或被驱逐的 Pod 的输出仍可查询；用尾部采样只保留有价值的链路；
- 按“检测—升级—缓解—解决”记录一次事故的时间线，写出带行动项的复盘。

本章的实验都是 `[真实]` 运行的：Prometheus、Alertmanager、GitLab、Fluent Bit、OpenTelemetry Collector 和集群都是真实软件，负载由 k6 产生。冻结节点、重启 OpenBao、写入一个注定失败的应用是 `[注入]` 的故障；事故演练的起因——一个测试环境的参数被带进了生产配置——是 `[模拟]` 的情节，之后的检测、通知、诊断与撤回都是真实发生的。值班工程师由我扮演，按脚本记录每一步的时刻。

## 原理 {#e9-principles}

### 告警要能离开故障域

监控系统最容易被忽略的失效，是它自己和被监控的对象一起倒下。第 8 章的 F4 中，唯一的 Prometheus 与 PostgreSQL 主库在同一个节点上，节点被冻结时告警一条也发不出来，直到故障切换结束。解决办法有两层：

1. **通知路径要离开集群。**本章的告警桥是一个运行在集群之外（与 GitLab 同一个 Docker 网络）的小程序：Alertmanager 用 webhook 把通知发给它，它在 GitLab 项目 `root/incidents` 中为每条告警开一个 issue——critical 是事故（incident），warning 是普通工单——告警解除时评论并关闭。
2. **用心跳检测“沉默”。**kube-prometheus-stack 自带一条永远在触发的告警 Watchdog。Alertmanager 每 30 秒把它发给告警桥；告警桥 180 秒没有收到心跳，就自己开一个事故：“集群的告警链路沉默了”。这就是死人开关（dead man's switch）：它不依赖被监控的系统说出“我坏了”，只依赖“它不再说话”。

### 从 SLO 到告警：多窗口、多燃烧率

SLO 的错误预算 $b = 1 - \text{SLO}$（下单 99%：$b = 1\%$）。某个时间窗口内的错误比例除以 $b$，就是燃烧率：燃烧率 1 意味着预算恰好用 30 天；燃烧率 14.4 意味着 1 小时就用掉 30 天预算的 2%（$14.4 / 720 = 0.02$）。按 Google SRE 工作手册的做法，本章的规则是：

| 级别 | 条件（两个窗口同时超过） | 含义 |
|---|---|---|
| 呼叫（critical） | 1 h 与 5 min 都 > 14.4 $b$，或 6 h 与 30 min 都 > 6 $b$ | 按此速度约 2 天或 5 天用完预算 |
| 工单（warning） | 1 d 与 2 h 都 > 3 $b$，或 3 d 与 6 h 都 > 1 $b$ | 慢性消耗 |

长窗口保证告警是“真的在燃烧”，短窗口让燃烧一停告警就解除。代价是检测时间：如果之前一小时的流量全部正常，故障开始后错误比例为 $e$，1 小时窗口的比例在 $t$ 分钟后达到 $t \cdot e / 60$，越过 $14.4 b$ 需要

$$t = \frac{14.4\, b \cdot 60}{e}\ \text{分钟}$$

下单全部失败（$e = 100\%$）时 $t \approx 8.6$ 分钟，失败一半时约 17 分钟，失败 20% 时 43 分钟，低于 14.4% 的错误比例在这一组窗口上永远不会呼叫。这不是缺陷，而是设计：呼叫只用于会在几天内耗尽预算的燃烧。这些规则由 `platform/slo/gen.py` 从 `platform/slo/slos.yaml` 生成：浏览可用性 99.5%、下单可用性 99%、浏览延迟（500 ms 内）99%。

### 路由、抑制与分级

告警分两级就够了：需要立即处理的（critical，呼叫）和可以等到工作时间的（warning，工单）。Alertmanager 按 `severity` 路由，按 `alertname`、`namespace`、`slo` 分组（同一组只发一次通知，等待 30 秒以收集同时发生的告警）。抑制规则让“原因”压住“后果”：某个 SLO 的呼叫告警抑制同一 SLO 的工单告警；`PostgresPrimaryMissingReplicas` 抑制 `PostgresReplicaNotStreaming`；同一告警的 critical 版本抑制 warning 版本。每条告警都带 `team` 标签和处置手册的链接（`docs/runbooks.md`）。

### 日志、链路与审计：保留什么

- **日志**以前只有服务通过 OTLP 主动发送的部分；其他容器的标准输出、以及一个已经被删除或驱逐的 Pod 的输出，随 Pod 一起消失（第 5 章的驱逐实验就读不到被驱逐 Pod 的最后几行）。节点级收集在每个节点上读取 `/var/log/containers`，与 Pod 的生命周期无关。
- **链路**在每秒几十个请求时就已经很多。头部采样在请求开始时决定是否保留，无法知道这次请求会不会出错；尾部采样等整条链路结束（这里等 10 秒）再决定：保留全部出错的、全部慢于 1 秒的、其余的 10%。代价是收集器要在内存里暂存每条链路，而且同一条链路的所有 span 必须到达同一个收集器实例。
- **审计**此前不记录服务账号的读操作（数据量太大），因此回答不了“哪个控制器读了哪个 Secret”。本章只为 Secret 打开这一类记录，级别为 Metadata：记录谁、读了哪个对象，从不记录内容。

## 实验 1：一条永远在响的告警 {#e9-false-positive}

启用路由之前，先看现在有哪些告警在触发：除了 Watchdog，只有一条 critical 的 `AlertmanagerClusterCrashlooping`——它在第 8 章就一直在响，经过两次整集群重建（全新的 Alertmanager）仍然在响。Alertmanager 的重启次数是 0。规则的输入是 `changes(process_start_time_seconds[10m])`：进程启动时间在 10 分钟内变化超过 4 次就视为崩溃循环。实际记录（`evidence/e9/clock-drift.log`）显示，这个“启动时间”每半分钟左右往回退 1 秒，10 分钟内变化了 14–15 次，而进程从未重启。

原因在时钟。Linux 计算进程启动时间用的是“开机时刻 + 进程启动时的开机时长”，开机时刻 `btime` = 当前墙上时间 − 开机时长。在这台 WSL2 虚拟机里，单调时钟（开机时长）比墙上时钟快约 3%：60 秒的开机时长里墙上时间只走了 58.3 秒（WSL 里测得 +2.91%，kind 节点里 +2.86%；另一次 45 秒的测量是 +3.74%），墙上时钟被不断校正回主机时间，于是 `btime` 每分钟后退约 2 秒，所有进程的“启动时间”跟着后退。节点导出器报告的时钟偏移却是 0、状态“已同步”——它看的是内核的 NTP 状态，看不到这种虚拟化层面的校正。

处置：关闭这条默认规则（kube-prometheus-stack 的 `defaultRules.disabled`），换成按 kubelet 统计的真实重启次数判断的 `AlertmanagerRestarting`。这个结论对其他测量也有意义：用单调时钟计时的工具（k6 的耗时、Go 和 Python 的计时器）与按墙上时间计算的间隔，在这台机器上可能相差 3% 左右；本书各章的时间点和间隔都来自墙上时间（`date`、Prometheus、审计日志的时间戳）。

## 实验 2：告警离开集群 {#e9-routing}

告警桥运行在集群外（容器 `alert-bridge`，172.20.0.15），集群内的 Alertmanager 按名字访问它；GitLab 项目 `root/incidents` 和一个只有 Reporter 角色的项目访问令牌由 `platform/alerting/run-bridge.sh` 创建。路由、抑制和平台告警通过合并请求 !27 生效。假设提交在 `evidence/e9/alerting-prediction.md`：

| | 假设 | 测量 | |
|---|---|---|---|
| A1 | 启用路由不会打开任何 issue | 第一条通知（06:45:18）就是 **AlertmanagerClusterCrashlooping**：规则已经从 Prometheus 删除，Alertmanager 却还持有这条告警直到它过期；告警桥开了事故 #1，06:49:12 在告警解除后关闭 | **推翻** |
| A2 | 重启后的 OpenBao 处于密封状态：Pod 启动 2.5 分钟内开出事故，解封 3 分钟内关闭 | Pod 06:46:01 运行；31 秒后 `vault_core_unsealed` 为 0（密封时指标端点仍然应答）；41 秒 pending、102 秒 firing；事故 #2 在 **128 秒**后开出；06:48:13 解封，**112 秒**后关闭 | 符合 |
| A3 | 一个同步失败的应用触发 `ArgoCDSyncFailing`，1.5 分钟内开出工单 | 探针应用 06:57:26 在 5 次重试后失败——**告警从未触发**：`argocd_app_sync_total{phase="Failed"}` 在第一次失败时才诞生，初值就是 1，`increase()` 看不到任何增长 | **推翻**（规则已修正） |
| A4 | 冻结同时运行 Prometheus 与 Alertmanager 的节点：最后一次心跳后 180–200 秒死人开关开出事故；解冻一分钟内关闭；数据库写入不受影响 | 07:16:38 冻结 ent-worker3；45 秒后节点状态 Unknown；事故 #6 在最后一次心跳后 **183.2 秒**开出；解冻后 3 秒关闭；冻结期间写入 14 行 | 符合 |
| A5 | 一次带警告的备份 2 分钟内开出工单 | 备份 e9-warnings 完成，7 个警告；告警 06:52:57 触发，工单 #3 在 34 秒后开出 | 符合 |

A3 的修正值得记住：计数器的某个标签组合在第一次发生时才出现，它的第一个样本就是 1，`increase()` 和 `rate()` 都认为“没有增长”。修正后的规则同时匹配“10 分钟前还不存在的失败计数器”（`... unless ... offset 10m`），并用已经记录在 Prometheus 中的数据回测：新规则会在 06:58 到 07:07 之间触发，旧规则始终为空（`evidence/e9/a3-backtest.log`）。

另有两个发现比假设本身更重要：

- **一个永远不健康的子应用挡住了根应用。**为了让同步波次等待，平台给 Argo CD 的 Application 配置了健康检查（第 9 章），于是根应用的同步要等每个子应用健康。探针应用永远不会健康，根应用的同步一直“等待 e9-probe 健康”，删除探针的合并（!29）因此迟迟无法生效。新规则 `ArgoCDRootNotSynced` 在 07:13:30 开出了事故 #5——一次真正的呼叫。团队的应用由 ApplicationSet 生成，不是根应用的直接子应用，只有平台自己声明的应用会这样挡住根应用。
- **沉默的 Prometheus 看起来像“一切正常”。**节点冻结期间，Prometheus 不再刷新告警，Alertmanager 让仍在生效的 `VeleroBackupWarnings` 过期并发出“已解除”，告警桥关闭了工单 #3，而问题并没有解决。这一刻唯一说真话的是死人开关。

## 实验 3：被删除的 Pod 的日志，和谁读了哪个密钥 {#e9-logs-audit}

Fluent Bit 5.1.3 以 DaemonSet 运行在全部 4 个节点上（每个只请求 16 MiB 内存，ent-worker3 的内存请求已经到了 98%），把容器的标准输出连同命名空间、Pod、容器、节点标签推送给 Loki。审计策略在“服务账号的读操作一律不记录”之前加了一条：服务账号读取 Secret 记录到 Metadata 级别；策略文件在主机上，API 服务器重启后生效（这次重启用了 8 秒）。假设提交在 `evidence/e9/logs-audit-prediction.md`：

| | 假设 | 测量 | |
|---|---|---|---|
| L1 | 被删除的 Pod 的标准输出仍可从 Loki 查到，30 秒之内 | Pod 写下标记后被删除，`kubectl logs` 返回 NotFound；标记行**在 Loki 中**，但第一次查询（删除后 19 秒）没有找到，而且所在的流**没有**命名空间和 Pod 标签 | 符合，有两个保留 |
| U1 | API 服务器重启后一分钟内，审计日志记录服务账号读取 Secret | 一分钟内 30 个服务账号读取 Secret 的记录，例如 External Secrets 读取 `insight/insight-api-key`、`data:pg-main` 读取备份凭据 `pg-backup-s3`、Kyverno 读取自己的 TLS 证书 | 符合 |

L1 的两个保留来自同一个细节：Fluent Bit 默认每 60 秒才发现一次新文件。这个只活了 9 秒的 Pod 的日志文件在 Pod 删除之后才被发现（kubelet 恰好还没删除文件），发现的那一刻又正赶上 API 服务器重启，补充元数据失败，于是这一行只带着 job 标签发了出去。当时 Loki 中共有 75 个流，除了 API 服务器重启那几秒发出的行，都带有完整的标签。改为每 5 秒发现一次新文件之后，寿命短于 5 秒、文件又被 kubelet 先删掉的 Pod 仍然会丢失日志——节点级收集缩小了窗口，没有消灭它。

<!-- E9: incident drill, tail sampling, exemplars, limits, FAQ, exercises, summary follow -->
