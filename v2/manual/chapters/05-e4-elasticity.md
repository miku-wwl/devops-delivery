# 弹性与调度（E4） {#ch-e4}

<div class="lead">第 4 章回答了“这套系统能扛多少”；本章回答“负载变了、资源不够了、出了故障时，平台会怎样自动应对”。Kubernetes 用一组彼此独立的机制处理这些问题：按指标增减副本的自动扩缩容，决定 Pod 放在哪里的调度器，决定资源不够时谁先让路的优先级与驱逐，以及按请求量分配 CPU 的内核调度。每一种机制都有自己的延迟和自己的判断依据。本章逐一测量它们的时间线，并检验它们在一起工作时是否符合预期。</div>

## 本章目标与产出

| 产出 | 位置（相对于 `v2/`） |
|---|---|
| 可选的 HPA 与 KEDA 模板（storefront Chart） | `gitops/charts/storefront-service/templates/` |
| KEDA（经 GitOps 安装） | `gitops/platform/apps/keda.yaml` |
| 扩缩容、限流、邻居干扰、驱逐、抢占、配额、拓扑分布的实验脚本 | `experiments/e4/` |
| 全部测量记录 | `evidence/e4/` |

**学完本章，你应当能够：**

- 区分 CPU 请求（requests）在调度、CPU 分配和自动扩缩容中的三种作用，以及 CPU 限制（limits）带来的限流；
- 解释 HPA 从负载变化到新副本就绪之间每一段延迟的来源，并据此设定目标利用率和副本范围；
- 在 GitOps 中让 HPA 或 KEDA 接管副本数，而不与 Argo CD 的自愈相互抵消；
- 用队列积压（而不是 CPU）驱动扩容；
- 预测节点内存不足时哪个 Pod 先被驱逐，以及高优先级 Pod 会抢占谁；
- 用配额、默认值和拓扑分布约束为多个团队共享的集群设定边界。

本章的实验都是 `[真实]` 运行的。三个“可用区”是 `[模拟]` 的（第 1 章）；为了让通知服务跟不上订单，它的“发送通知”被调慢为每条 200 ms，这是 `[模拟]` 的外部服务延迟。驱逐、抢占和邻居干扰实验中占用内存或 CPU 的 Pod 是有意制造的负载，它们只运行在实验期间，脚本结束时删除。

## 原理 {#e4-principles}

### CPU 请求的三种作用，与 CPU 限制

一个容器的 `resources.requests.cpu` 同时被三个互不相干的组件使用：

1. **调度器**把它当作“这个 Pod 需要的 CPU”：一个节点上所有 Pod 的请求之和不能超过节点的可分配量（本实验环境每个工作节点 3.75 核）。请求只是记账，Pod 实际用多少由下面两项决定。
2. **内核**按请求分配 CPU：kubelet 把请求换算成 cgroup 的权重（`cpu.weight`），CPU 空闲时谁都可以多用，CPU 不够用时按权重比例分配。请求为 500m 的 Pod 权重约为 20，请求为 50m 的约为 2，没有请求的 BestEffort Pod 只有 1。
3. **HPA** 的目标利用率是“实际用量 ÷ 请求”。请求定得不真实，百分比就失去意义：请求 50m、实际用 0.5 核，利用率是 1000%。

`resources.limits.cpu` 是另一回事：它变成 CFS 的配额（`cpu.max`），在每个 100 ms 的周期里，容器最多运行“限制 × 100 ms”的 CPU 时间，用完就被暂停到下一个周期开始。平均用量远低于限制的服务，也可能在某个周期内的突发中用完配额，于是请求凭空多等几十毫秒。这就是 CPU 限流（throttling）。

### HPA 的算法与它的延迟

HPA 控制器每 15 秒计算一次：

$$\text{期望副本数} = \left\lceil \text{当前副本数} \times \frac{\text{当前指标}}{\text{目标指标}} \right\rceil$$

比值与 1 的差在 10% 以内时不动（容差）。扩容默认立即执行（每 15 秒最多翻倍或加 4 个），缩容要求过去 300 秒内的期望值都更低（稳定窗口），以免来回抖动。从负载上升到新副本开始分担流量，要经过一串延迟：kubelet 采集容器 CPU，metrics-server 汇总（本环境每 15 秒），HPA 下一次计算，Deployment 创建 Pod，调度器选择节点，拉取镜像、启动容器，就绪探针通过，最后网格与负载均衡把新连接分给它。本章测量这条链上的每一段。

### KEDA：按事件源扩缩容

CPU 不是所有服务的好指标。通知服务大部分时间在等待外部接口，CPU 很低，积压却可能越来越多。KEDA 读取事件源（这里是 NATS JetStream 消费者的未处理消息数），把它作为外部指标交给自己创建的 HPA：期望副本数约等于“积压 ÷ 每个副本的目标积压”。KEDA 每隔 `pollingInterval` 秒读一次事件源，这是它特有的一段延迟。

### 资源不够时谁让路：QoS、驱逐与抢占

- **QoS 类别**由请求和限制决定：所有容器的请求等于限制是 Guaranteed，有请求但不全相等是 Burstable，什么都没写是 BestEffort。
- **节点压力驱逐**：kubelet 发现节点可用内存低于阈值（本环境是工作集超过约 2922 MiB，第 1 章），按顺序驱逐 Pod：先看用量是否超过请求，再看优先级，最后看超出请求的多少。BestEffort 的请求为 0，它的全部用量都算“超出”。
- **抢占**：调度器为一个放不下的高优先级 Pod 寻找节点，在那里驱逐尽量少、优先级尽量低的 Pod。没有指定 PriorityClass 的 Pod 优先级为 0。
- **拓扑分布约束**：把副本均匀地放在可用区之间；`ScheduleAnyway` 是建议，`DoNotSchedule` 是硬性要求，宁可不调度也不打破均匀。

## 实验 1：把副本数交给 HPA {#e4-handover}

到第 4 章为止，网关的副本数写在 Git 中（`replicas: 2`），Argo CD 开启了自愈：任何人用 `kubectl scale` 改了副本数，几秒钟后就会被改回去。HPA 正是要改副本数的那个“人”。如果 Deployment 的清单里仍然有 `replicas` 字段，HPA 每扩容一次，Argo CD 就把它改回 2，两个控制器会永远互相抵消。所以 Chart 增加了一个可选的 HPA，启用时 Deployment 的清单里不再有 `replicas` 字段（`gitops/charts/storefront-service/templates/`）。

网关的 CPU 请求同时改为 500m。原来的 50m 只是一个占位数字：第 4 章测得网关在 60 迭代/秒时每个 Pod 约用 0.28 核，按 50m 计算利用率是 560%，HPA 会立刻扩到上限。500m 接近计划负载下的真实用量；目标利用率 100%，即让每个 Pod 平均用 0.5 核。按第 4 章的数据，两个副本时较忙的那个承担约 53%，它会在 0.53 核左右，仍在延迟平坦的区间之内。

这次交接本身有代价（`evidence/e4/hpa-switch.log`，观察脚本每 2 秒记录一次）：

```text
01:52:51 | hpa none | deploy 2 2 | 9c2jd:Running:true twsgl:Running:true
01:52:58 | hpa 2 1  | deploy 2 1 | gm44w:Pending:false qhww7:Pending:false 9c2jd:Running:true twsgl:Running:true
01:53:05 | hpa 2 1  | deploy 2 2 | gm44w:Running:false qhww7:Running:true 9c2jd:Running:true
01:53:15 | hpa 2 2  | deploy 2 2 | gm44w:Running:true qhww7:Running:true
```

Argo CD 默认用客户端方式应用清单（相当于 `kubectl apply`）：清单中去掉的字段会从对象上删除，`replicas` 被删除后取默认值 1，Deployment 立刻缩到 1 个副本。HPA 在同一秒里发现“副本数低于最小值 2”并改回 2（事件：`New size: 2; reason: Current number of replicas below Spec.MinReplicas`）。由于 CPU 请求同时变了，这还是一次滚动更新。合在一起，有约 7 秒只剩一个就绪的网关副本。在没有负载的时候这无关紧要；在高峰期做这个交接，相当于主动去掉一半容量。可以避免它的做法有两种：用服务端应用（server-side apply，字段的归属可以转移而不被删除），或者先让 Argo CD 忽略 `replicas` 的差异（`ignoreDifferences`）再从清单中删除它。

## 实验 2：HPA 的反应，以及它看不见的过载 {#e4-hpa}

`experiments/e4/hpa-timeline.sh` 用一次 k6 运行给网关加一个负载台阶，同时每约 2 秒记录 HPA 的决定、Deployment 的副本数和每个 Pod 的状态（`experiments/e4/watch.sh`），结束后收集 HPA 与 Pod 的事件，以及每个新 Pod 的创建、调度、就绪时间。本环境的相关设置都是默认值：metrics-server 每 15 秒汇总一次，HPA 每 15 秒计算一次，容差 10%，缩容稳定窗口 300 秒。

### 台阶到 120 迭代/秒：卡在容差边缘

第一次台阶从 30 升到 120 迭代/秒（`evidence/e4/hpa-timeline-collect.log`；脚本在 k6 结束后中断了，因为我在它运行时修改了脚本文件，bash 是边读边执行的；事件与 Pod 时间是之后补收集的）。按第 4 章的数据，120 迭代/秒时两个网关 Pod 平均各用约 0.55 核，即请求的 110%，正好在容差的边上。观察到的利用率在 102%–114% 之间摆动，HPA 直到台阶开始 5 分 26 秒后才扩到 3 个（`New size: 3; reason: cpu resource utilization (percentage of request) above target`）。一旦决定扩容，执行很快：

| 时刻 | 事件 |
|---|---|
| 01:57:17 | 负载升到 120 迭代/秒 |
| 02:02:43 | HPA 决定扩到 3 个，Pod 创建并调度到 ent-worker2 |
| 02:02:45 | 容器启动（镜像已在节点上） |
| 02:02:49 | 启动探针第一次失败（进程还没开始监听） |
| 02:02:51 | Pod 就绪：从决定到就绪 8 秒 |
| 02:04:27 | 负载回到 30 迭代/秒 |
| 02:08:28 | 缩回 2 个：距离最后一次“需要 3 个”的计算约 300 秒（稳定窗口） |

延迟一直正常（120 迭代/秒时浏览 p95 31.8 ms），因为两个副本本来也撑得住。这说明容差有它的盲区：利用率在目标的 100%–110% 之间时，HPA 什么也不做。目标值的含义是“允许长期停留的水平”，而不是“开始扩容的水平”。

### 台阶到 170 迭代/秒：扩出来的 Pod 没有流量

第二次台阶升到 170 迭代/秒，约为目标的 150%（`evidence/e4/hpa-timeline-2.log`）。HPA 这次反应很快：台阶开始 44 秒后扩到 3 个（利用率 116%），8 秒后就绪；2 分 44 秒后扩到 4 个。可是这一档有 20.5% 的请求失败，浏览 p95 接近 1 秒。每 30 秒的记录（`evidence/e4/hpa-2-analysis.log`）显示，网关每秒约 300 个请求、每秒 60–140 个 5xx，全部是隔舱或熔断器的拒绝；网关的 CPU 合计只有 1.4–1.5 核，扩到 3 个、4 个之后也没有增加。按 Pod 拆开（`evidence/e4/hpa-2-pods.log`）就清楚了：

| 02:21:30–02:22:30 | 请求/秒 | CPU | 5xx/秒 |
|---|---|---|---|
| gateway-…-gm44w（原有） | 147 | 0.79 核 | 36.0 |
| gateway-…-qhww7（原有） | 142 | 0.92 核 | 21.4 |
| gateway-…-j72rh（02:19 扩出） | 0 | 0.01 核 | — |
| gateway-…-d5j6r（02:21 扩出） | 0 | 0.01 核 | — |

扩出来的两个 Pod 在整个高负载阶段**一个请求也没有收到**。原因是第 3 章讲过的 L4 负载均衡与长连接：k6 的每个虚拟用户在第一次迭代时建立一条保持连接（keep-alive），之后一直复用它；负载均衡器、NodePort 都在连接建立时决定后端。台阶开始的头几秒里所有虚拟用户都已经连上了原来的两个 Pod，新 Pod 就绪时已经没有新连接了。HPA 看到的是四个 Pod 的平均值：两个 0.8–0.9 核、两个 0.01 核，平均约 0.43 核，正好在目标附近，“一切正常”；用户看到的是五分之一的请求失败。

这个实验得出三点：

- **扩容不等于分担负载。**流量要能到达新的副本：要么客户端会重新建立连接，要么入口按请求（L7）而不是按连接分配。本环境的外部入口是 L4，第 9 章（E8）用网关 API 在入口做 L7 路由。
- **HPA 看的是平均值，容量却由最忙的那个 Pod 决定**（第 4 章的份额 $b$）。负载不均时，平均利用率会掩盖已经饱和的 Pod。
- **会主动拒绝请求的服务，CPU 会低估需求。**被隔舱或熔断器快速拒绝的请求几乎不花 CPU。对这种服务，按请求速率或排队情况扩容比按 CPU 更可靠。

### 让客户端重新连接：这次失败的是负载生成器

为了直接验证“是保持连接把流量钉在了旧副本上”，同样的台阶又做了一次，让 k6 在每次迭代时新建连接（`noVUConnectionReuse`，`evidence/e4/hpa-timeline-3.log`）。这个对照没有做成，失败的是负载生成器自己：32 546 个错误中有 32 518 个是 `connect: cannot assign requested address`。k6 从同一个地址、向同一个负载均衡器地址每秒建立上百个新连接，客户端关闭的连接要在 TIME_WAIT 状态停留 60 秒，本地端口很快就用完了（加上失败的连接尝试本身也占用端口）。网关只收到一部分请求，其中大部分以 5xx 结束，HPA 始终没有扩容。原因在压测工具一侧，结论不能用于判断网关。要做这个对照，需要更多的客户端地址，或者干脆在入口按请求分配流量；第 9 章（E8）在入口使用 L7 路由。

另外，这几次实验之间，主机的 CPU 主频降了下来：笔记本在持续负载下降频，Windows 的“处理器性能”计数器显示只有标称频率的 65%（3.8 GHz 中的约 2.5 GHz，`evidence/e4/host-cpu.txt`）。同样的流量下，每个服务每个请求的 CPU 都变成了 1.5–2 小时前的约两倍（网关 4.47 → 8.94 ms，`evidence/e4/drift-check.log`）。这正是第 4 章强调要并排比较的原因；也说明自动扩缩容在这种情况下是有用的：同样 90 迭代/秒的负载，网关在主频下降后被扩到了 4 个副本。

## 实验 3：按队列积压扩容（KEDA） {#e4-keda}

通知服务的 CPU 很低，它的“负载”是 JetStream 消费者中未处理的消息。KEDA 2.21.0 经 GitOps 安装（`evidence/e4/keda-install.log`），通知服务的 ScaledObject 以“每个副本 50 条积压”为目标，1–5 个副本，每 10 秒读一次 NATS 的监控接口。安装时有一个细节：KEDA 的 CRD 太大，客户端方式应用时写不进 `last-applied-configuration` 注解，它的 Argo CD 应用用服务端应用。为了让一个副本跟不上，通知服务的“发送”被调慢为每条 200 ms、同时 2 条，即每个副本每秒 10 条（`[模拟]` 的慢速外部服务）；170 迭代/秒时每秒约有 35 笔订单确认，即 35 条消息（实测 35.3 笔/秒，通知服务处理 35.2 条/秒），需要 4 个副本。

与网关的台阶在同一次运行中（`evidence/e4/hpa-timeline-2.log`）：

| 时刻 | 通知服务 |
|---|---|
| 02:18:31 | 负载升到 170 迭代/秒 |
| 02:18:46 | 扩到 2 个（每个副本积压 100 条），8 秒后就绪 |
| 02:19:16 | 扩到 4 个（每个副本 193.5 条） |
| 02:19:31 | 扩到 5 个（上限），02:19:37 全部就绪：台阶开始后 66 秒 |
| 02:19:47 起 | 每个副本的积压 0–4.4 条，积压消化完毕 |
| 02:23:41 | 负载回到 30 迭代/秒 |
| 02:24:17、02:24:32 | 缩到 3 个、1 个 |

KEDA 比 CPU 扩容快得多：第一次扩容只用了 15 秒，因为积压在台阶开始后立刻增长，而且它每 10 秒读一次。缩容的时刻值得细看：它恰好是 02:19:16 和 02:19:31 那两次“需要更多副本”的计算之后 300 秒（稳定窗口），与负载何时下降无关。积压消化完之后，每个副本只剩几条积压，按“积压 ÷ 50”计算的期望副本数早就是 1 了。也就是说，**积压衡量的是“排着多少”，不是“来得多快”**：消费者跟得上时积压接近零，指标就认为一个副本足够。负载如果在 02:24 之后仍然保持，通知服务也会缩回 1 个，积压重新积累，再扩容。

### 稳定负载下的振荡

上面的推断可以直接检验：负载在 90 迭代/秒保持 12 分钟（`evidence/e4/keda-steady.log`），通知服务需要约 2 个副本才跟得上。

| 时刻 | 通知服务副本 | 每个副本的积压 |
|---|---|---|
| 02:52:52 | 负载升到 90 迭代/秒 | |
| 02:53:11 | 1 → 3 | 134 |
| 02:58:21 | 3 → **1** | 1.7 |
| 02:58:36 | 1 → 3 | 121 |
| 02:58:49 | 3 → 5 | 67 |
| 03:03:45 | 5 → **1** | 1.6 |
| 03:04:01 | 1 → 2 | 92 |
| 03:04:15 | 2 → 4 | 99.5 |
| 03:05:02 | 负载回到 30 迭代/秒 | |

负载一直没有变，通知服务却两次被缩到 1 个副本，又在 15–30 秒内扩回去：一个周期约等于稳定窗口（300 秒）的锯齿。每次缩到 1 个，积压都重新涨到一两百条，通知的延迟随之升高。修正的方向是让指标反映到达速率而不是积压：例如用 KEDA 的 Prometheus 触发器按“每秒处理的消息数 ÷ 每个副本的处理能力”计算副本数，积压触发器只负责应对突发（KEDA 取多个触发器中要求最多的那个）。

## 实验 4：CPU 限制与限流 {#e4-limits}

`experiments/e4/ab-limit.sh` 复制网关的 Deployment，给副本加上 300m 的 CPU 限制（请求也设为 300m，请求高于限制是无效的），让它与两个不设限制的网关 Pod 同时承受 60 迭代/秒的流量，方法与第 4 章的金丝雀对比相同。内核为这个容器设置的配额是 `cpu.max: 30000 100000`：每 100 ms 的周期内最多运行 30 ms（`evidence/e4/ab-limit-300m.log`，按 Pod 的统计见 `evidence/e4/ab-limit-300m-table.log`）：

| | 不设限制（2 个 Pod） | 限制 300m |
|---|---|---|
| 平均 CPU | 0.207–0.288 核 | 0.282 核 |
| 延迟 p50 | 16.4 ms | 21.9 ms |
| 延迟 p99 | 262 ms | 475 ms |
| 事件循环延迟 p99 | 5–7 ms | 95.5 ms |
| 被限流的周期 | — | 67% |

容器自己的 `cpu.stat` 在实验期间增加了 1816 个周期，其中 1218 个被限流，累计被暂停 44.8 秒。平均用量（0.28 核）低于限制（0.3 核），三分之二的周期却被限流：请求是一簇一簇到达的，一簇请求在一个周期的前 30 ms 就用完配额，这个周期剩下的时间里整个进程被暂停，排在后面的请求只能等到下一个周期。对单线程的事件循环服务，限流直接表现为事件循环的停顿，p99 从约 6 ms 升到 96 ms。连这个副本启动的过程（导入模块、建立连接池）就已经被限流了 71 个周期。

对延迟敏感的服务，CPU 限制几乎只有坏处：保证份额靠请求（cgroup 权重），限制只会在突发时把进程停下来。如果出于成本或公平需要限制，应当把它设在峰值之上，并监控被限流的周期比例（`container_cpu_cfs_throttled_periods_total`）。实验 8 中，LimitRange 正是在没有人察觉的情况下给每个容器加上了这样的限制。

NOISY_EVICTION

## 实验 7：优先级与抢占 {#e4-preemption}

`experiments/e4/preemption.sh` 先建两个 PriorityClass：批处理 `e4-batch-low`（值 −10，`preemptionPolicy: Never`）和关键任务 `e4-critical`（值 100 000）。然后用批处理的 pause 容器（每个请求 1 核，实际不用 CPU）把三个工作节点的空余 CPU 占满：每个节点 3.75 核可分配、已请求 0.93–1.23 核，各放下 2 个，另外 6 个 Pending。最后创建 2 个关键任务 Pod，同样请求 1 核（`evidence/e4/preemption.log`）：

```text
02:35:19  critical-…-xmq4x  FailedScheduling  0/4 nodes are available: … 3 Insufficient cpu.
          preemption: found a potential placement for pod on node ent-worker3, preempting 1 victim
02:35:19  filler-…-kvfx8    Preempted         Preempted by pod 5d6b799e-… on node ent-worker3
02:35:20  critical-…-xmq4x  Scheduled         Successfully assigned e4-sched/critical-…-xmq4x to ent-worker3
02:35:20  filler-…-2jmpb    FailedScheduling  … preemption: not eligible due to preemptionPolicy=Never.
```

关键任务 Pod 创建后 1 秒被调度、3 秒后就绪；每个只抢占了一个批处理 Pod。被抢占的批处理 Pod 由它们的 ReplicaSet 重建，又因为 `preemptionPolicy: Never` 只能等待，不会反过来抢别人。

批处理的优先级设为 −10 而不是一个正数，是有意的。没有指定 PriorityClass 的 Pod（本书所有的 storefront 服务）优先级为 0；调度器选择牺牲者时，先保留优先级高的。如果批处理是 +100，比服务还高，关键任务需要腾地方时，被驱逐的会是 storefront 的 Pod。给批处理一个负的优先级，或者给所有在线服务一个明确的、更高的 PriorityClass，是共享集群的基本功。

## 实验 8：配额、默认值与拓扑分布 {#e4-quota-spread}

### 租户的配额与默认值

`experiments/e4/quota.sh` 为一个租户命名空间设置 ResourceQuota（最多 4 个 Pod、1 核请求、512Mi 内存请求、1Gi 内存限制）和 LimitRange（每个容器的默认请求 100m/64Mi、默认内存限制 128Mi、CPU 最多 500m）（`evidence/e4/quota.log`）：

- 一个没写任何资源的 Pod 被接受，LimitRange 为它补上了请求和限制：`{"limits":{"cpu":"500m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}`。**CPU 限制 500m 是没有人写过的**：LimitRange 只写了 `max.cpu`，没写默认限制时，Kubernetes 把最大值当作默认限制。结果这个租户的每个容器都带上了 CPU 限制，会在突发时被限流（实验 4）。
- 请求 2 核的 Pod 在准入时被拒绝：`must be less than or equal to cpu limit of 500m`，比较的正是那个被默认出来的限制。
- 6 个副本的 Deployment 本身被接受，但它的 ReplicaSet 只创建到配额用完为止：`exceeded quota: tenant, requested: pods=1, used: pods=4, limited: pods=4`，最终 3/6 就绪（另一个名额被第一个 Pod 占了）。配额拒绝的不是 Deployment，而是 Pod 的创建，所以要在 ReplicaSet 的事件里找原因。

### 拓扑分布：建议与要求

`experiments/e4/spread.sh` 把一个可用区（ent-worker2）设为不可调度，然后部署三组 3 副本的 Deployment（`evidence/e4/spread.log`）：

| 约束 | ent-worker2 不可调度时 | 恢复调度 20 秒后 |
|---|---|---|
| `ScheduleAnyway`（storefront Chart 的现状） | 2 个可用区：1 + 2 | 不变（1 + 2） |
| `DoNotSchedule` | 1 + 1，第 3 个 Pending | 1 + 1 + 1（恢复的同一秒被调度） |
| `DoNotSchedule` + `nodeTaintsPolicy: Honor` | 1 + 2 | 不变（1 + 2） |

硬性约束下，第三个 Pod 宁可 Pending（“2 node(s) didn't match pod topology spread constraints”）也不打破均匀：被禁止调度的节点仍然算作一个可用区，其中 0 个 Pod，再放一个就会使差距变成 2。加上 `nodeTaintsPolicy: Honor`，带污点（包括“不可调度”）的节点不再参与计算，Pod 可以挤进剩下的两个可用区。两种选择对应不同的风险：前者保证了失去任何一个可用区时副本不会全军覆没，代价是一个可用区不可用时扩容会卡住；后者优先保证副本数。还有一点：调度器只在放置新 Pod 时考虑分布，恢复之后并不会把已经挤在一起的 Pod 重新分散（那是 descheduler 的工作），软约束组和 Honor 组都停留在 1 + 2。第 4 章中 catalog 的两个副本落在同两个节点上，正是 `ScheduleAnyway` 加上不会自动重新分散的结果。
