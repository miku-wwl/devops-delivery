# 第二轮 STATUS

> 只在验收通过后更新。路径相对于 `v2/`。状态取值：`NOT_RUN`、`IN_PROGRESS`、`VALIDATED`、`PARTIAL`、`BLOCKED`。计划与验收标准见 [PLAN](PLAN.md)。

| 阶段 | 主题 | 状态 | 证据 | 备注 |
|---|---|---|---|---|
| E0 | 平台基线与资源预算 | VALIDATED | `evidence/e0/`、第 1 章 | 1+3 节点，工作节点由内核限制为 4 CPU/3 GiB；allocatable 2666 MiB、驱逐起点 2922 MiB 经 `/configz` 证实；发现 Kind 默认无内存驱逐 |
| E1 | 多服务系统 | VALIDATED | `evidence/e1/`、第 2 章 | 6 个服务 + CNPG/Valkey/NATS，全部经 Argo CD 从 Git 部署（735 s 收敛）；订单链路 6 个服务 65 个 span（含 NATS 异步段）；28 个测试；第一次部署的 8 个问题均有证据并修复；一次计划外的 PG 故障转移无数据丢失 |
| E2 | 服务网格与 L7 流量 | VALIDATED | `evidence/e2/`、第 3 章 | Istio 1.31.4 ambient：服务间明文请求行 140 → 0；waypoint 让各服务副本分布 46.9%–53.1%（L4 下 97/3）；交替 A/B：L4 +2.4 ms、waypoint +1.3 ms（浏览 p50）；网格重试 ×4 不受应用预算约束；STRICT 切断网格外调用方；一次真实的“扣款成功、订单失败”事故；约 900 ms 的进程停顿未复现，原因未找到 |
| E3 | 负载与容量规划 | VALIDATED | `evidence/e3/`、第 4 章 | 容量模型的预测在实验前提交（98be3f2）：两副本时网关最先饱和于 180 迭代/秒（预测 172 ± 20），工作节点 CPU 误差 +4%（P2、P4 通过；P1 在 6 档中 4 档达标，P3 在 60 迭代/秒以 1 ms 之差未达标）；单副本时饱和点在 100–110 迭代/秒之间（预测 99），但“0.90 核”判据未在预测档位出现；饱和后先由隔舱拒绝（事件循环排队使 3 ms 的调用在网关看来 635 ms）。纯 ASGI 中间件 + sniffio 经金丝雀并排测得每请求 CPU −25%。三个失败机制有证据：被 `increase()` 隐藏的熔断 503、实验环境负载均衡器 1024 文件描述符崩溃（已修正）、崩溃风暴中经 ztunnel 的停顿。利特尔定律密集采样误差 < 5%。未解释：升档瞬态、约 0.1% 请求超时、首次单副本 0.81 核上限。CPU 限流实验移至 E4 |
| E4 | 弹性与调度 | VALIDATED | `evidence/e4/`、第 5 章 | 网关 HPA（请求 500m、目标 100%）：120 迭代/秒时利用率停在容差边缘（102%–114%），5 分 26 秒后才扩容，决定到就绪 8 秒，缩容按 300 秒稳定窗口；170 迭代/秒时 44 秒扩容，但 L4 入口 + 长连接使扩出的 Pod 收不到请求（20.5% 失败，HPA 的平均值看似正常）。KEDA 按 JetStream 积压首次扩容 15 秒；恒定负载下只按积压会以稳定窗口为周期缩到 1 个（通知 p95 约 20 s），加到达速率触发器后稳定在 3 个（p95 0.48–0.73 s）。CPU 限制 300m：平均 0.28 核仍有 67% 的周期被限流，事件循环 p99 6 → 96 ms。邻居：声明 2 核请求的消耗者使同节点网关 p50 131 ms（BestEffort 时几乎无影响），cgroup 权重 2/20/79 实测。驱逐（预测先提交，V1–V6 全部符合）：超出请求 712 MiB 的 Burstable 先于 160 MiB 的 BestEffort 被驱逐，超调 < 10 MiB，MemoryPressure 持续近 10 分钟，驱逐前同节点数据库页缓存 411 → 115 MiB；kubelet 准入拒绝超额的 nodeName Pod（OutOfmemory）和压力期间的 BestEffort Pod。抢占 1 秒内完成（批处理 −10 + Never）；LimitRange 的 max.cpu 成为默认 CPU 限制；DoNotSchedule 宁可 Pending，调度器不重新分散。主机中途降频到 65%。移交：L7 入口下的扩容分担（E8）、节点级日志采集（E9）；更快的内存增长下 kubelet 与 OOM killer 谁先动作未测。保留的平台变更：网关 HPA、KEDA 与通知服务的 ScaledObject、[模拟] 的慢速通知（200 ms × 2） |
| E5 | 多租户与安全治理 | NOT_RUN | | |
| E6 | 故障注入与传播 | NOT_RUN | | |
| E7 | 数据可靠性与灾难恢复 | NOT_RUN | | |
| E8 | 发布治理 | NOT_RUN | | |
| E9 | 可观测性与事故响应 | NOT_RUN | | |
| E10 | 大规模控制面 | NOT_RUN | | |
| E11 | IaC 与云迁移 | NOT_RUN | | |
| E12 | 能力考核与教材 | NOT_RUN | | |
