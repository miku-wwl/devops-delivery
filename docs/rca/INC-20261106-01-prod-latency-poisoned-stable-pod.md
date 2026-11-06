# Incident RCA：prod 下单变慢——被中止的金丝雀把坏配置留给了稳定版 Pod

> **环境声明：** 本事件发生在本地测试环境（Kind 集群），流量来自 k6 负载生成器，不涉及真实用户与生产数据。它**不是**计划内的演练：P6 的故障演练结束后，一个副作用潜伏了约 3 小时，直到 P7 新加的告警发现它。

| 字段 | 内容 |
|---|---|
| 事件编号 | INC-20261106-01 |
| 严重级别 | SEV-2（约 18% 的下单请求每次多等 0.8 s，持续约 3 小时；没有错误，没有数据损坏） |
| 开始 / 检测 / 缓解 / 修复完成（UTC） | 01:14:11 / 04:01:05（条件成立，04:02 前后 firing） / 约 04:14:50（删除 Pod） / 04:20:05（Chart 0.3.1 全量，告警全部清除） |
| 影响范围 | prod 的 `POST /api/v1/orders`：被污染的 Pod 处理的 15,662 个请求全部慢于 0.5 s，占同一 4 小时窗口内 prod 下单请求（86,680）的 18%；消耗 30 天延迟预算的 5.87% |
| 检测方式 | Prometheus 告警 `DemoApiHighLatency`（P7 新增；prod 的 p95 为 836 ms） |
| 负责人 | 实验操作者（由 Claude Code 代为执行） |

## 摘要

P6 演练把 `faults.latencyMs: 800` 合并进 prod，金丝雀分析在一分钟多一点之后判定失败并中止发布。中止时 Argo Rollouts 把稳定版 ReplicaSet 从 4 个副本扩回 5 个。新建的稳定版 Pod 启动时读取了**所有 ReplicaSet 共享的 ConfigMap**，而此刻 Git 中的坏配置还没有回滚，于是这个“稳定版” Pod 带着 800 ms 的延迟运行了 3 小时。Rollout 的状态一直是 Healthy；当时只有金丝雀分析，它只看金丝雀 Pod，因此没有任何信号。P7 加上延迟告警后，规则生效不到一分钟就发现了问题。按 ReplicaSet、接口、Pod 拆分指标后定位到这个 Pod，删除它即完成缓解。根本修复是 Chart 0.3.1：把发布配置写进 Pod 模板，让每个 ReplicaSet 携带自己的配置。P10 的演练验证了这个修复（INC-20261106-02）。

## 时间线

| 时间（UTC） | 事件 | 来源/证据 |
|---|---|---|
| 01:11:21 | P6 坏金丝雀演练开始；MR !13（`5234a32`）把 prod 的 `faults.latencyMs` 设为 800，ConfigMap `demo-api-prod` 随之变为 800 | `evidence/p6/canary-bad.log` |
| 约 01:13 | 金丝雀 Pod 创建（revision 4，20% 流量） | 同上（监视开始后第 94 秒） |
| 约 01:14:08 | 分析失败（p95 两次超过 0.5 s），Rollout 中止；稳定版 ReplicaSet 由 4 扩到 5 | 同上（第 166 秒） |
| **01:14:11** | 新的稳定版 Pod `6bdb67694c-pw772` 启动，读到 `FAULT_LATENCY_MS=800`：**事件开始** | `evidence/p7/prod-latency-rootcause.log` |
| 01:15–01:17 | `git revert`（MR !14，`d6225fa`），ConfigMap 恢复为 0，Rollout Healthy；pw772 的环境变量不会随之改变 | `evidence/p6/canary-bad-revert.log` |
| 01:17–04:00 | 潜伏期：没有针对稳定版的延迟告警 | — |
| 04:00:15 | P7：Collector 就绪，随后创建 PrometheusRule `demo-api` | P7 记录 |
| **04:01:05** | `DemoApiHighLatency`（prod，p95 836 ms）条件成立；`for: 1m` 后 firing：**检测** | `evidence/p7/drill-prometheus-alerts.png` |
| 04:01:23 之后 | 无关变更 MR !15（Chart 0.3.0）触发 prod 金丝雀，停在 20%；告警早于它，被排除 | P7 第 6 步 |
| 04:13:44 | 按 ReplicaSet 拆分：稳定版 p95 852 ms，新金丝雀 4 ms；按接口拆分：只有下单接口慢 | `evidence/p7/prod-latency-investigate.log` |
| 04:14:08 | 逐个检查 Pod 的环境变量：只有 pw772 为 800，启动时间 01:14:11 落在 P6 中止窗口内：**根因确认** | `evidence/p7/prod-latency-rootcause.log` |
| 04:14:47 起 | 统计影响（15,662 / 86,680），删除 pw772；新 Pod 读到 0：**缓解** | `evidence/p7/prod-latency-impact.log` |
| 04:15:41 | Chart 0.3.1（配置写入 Pod 模板）经 MR 发布，金丝雀分析 3/3 通过后人工晋级 | P7 第 6 步 |
| 04:20:05 | 所有 DemoApi 告警清除，prod 与 dev 的 p95 都是 4 ms：**修复完成** | P7 第 6 步 |

## 影响

- 15,662 个下单请求每个多等约 800 ms（全部慢于 SLO 阈值 0.5 s），没有失败请求。
- 按 P10 的延迟 SLO（30 天内 99% 的 API 请求不超过 0.5 s；prod 平均 10.29 个请求/秒，30 天预算 266,800 个慢请求）计算，这次事件消耗了 **5.87%** 的月度预算。作为对比，P10 中被金丝雀拦下的同一个坏配置只消耗了 0.034%（`evidence/p10/drill-4-slo.log`）。
- P6 当时的结论“只影响 1.4% 的请求、稳定版恢复”不完整，P6 章节和记录已加勘误。

## 根因分析（5 Whys）

1. **为什么 18% 的下单请求变慢了 3 小时？** 一个稳定版 Pod（pw772）以 `FAULT_LATENCY_MS=800` 运行。
2. **为什么稳定版 Pod 会有坏配置？** 它是在金丝雀中止、稳定版扩回 5 个副本时新建的，启动时从共享 ConfigMap 读取配置，而那一刻 ConfigMap 中仍是坏值；环境变量只在容器启动时读取，之后 ConfigMap 被改回 0 也不会影响它。
3. **为什么配置放在共享的 ConfigMap 里？** P3 的 Chart 设计假设同一时刻只有一个版本（滚动更新），用 `envFrom` + `checksum/config` 注解让配置变更触发滚动。金丝雀发布打破了这个假设：两个版本长时间并存，却读取同一份可变配置。
4. **为什么 3 小时没人发现？** 当时只有金丝雀分析，它只评估金丝雀 Pod；Rollout 的 Healthy 只表示控制器达成了期望的副本状态，不代表每个 Pod 的配置正确；P6 的验证在新 Pod 启动 19 秒时就做完了，而且只按金丝雀统计。
5. **为什么验证会漏掉？** 演练的验收只看“分析是否中止”和“Rollout 是否恢复”，没有“中止后逐个检查稳定版 Pod 的实际配置和延迟”这一步，也还没有覆盖全体 Pod 的 SLO 告警。

**根本原因：** 渐进式交付期间，多个版本共享一份可变配置（配置没有与 Pod 模板一起版本化）。
**促成因素：** 缺少针对全体 Pod 的延迟告警；验证只看控制器状态；中止时扩回稳定版是正常且必要的行为，恰好在坏配置仍有效时创建了新 Pod。

## 检测与响应评价

**做得好的：**
- 告警规则上线后 1 分钟内就发现了问题。
- 先排除最近的变更（MR !15），再按 ReplicaSet → 接口 → Pod 逐层拆分，从告警 firing 到确认根因约 12 分钟（期间 dev 的演练也在同时排查）。
- 先缓解（删除 Pod），再修复（Chart 0.3.1），修复版本仍然走金丝雀和分析。
- 影响有精确的数字（按 Pod 统计的请求数），而不是估计。

**待改进的：**
- 检测完全依赖“碰巧加上了告警”：从开始到检测约 2 小时 47 分钟（MTTD）。
- 演练的验收标准只看自动化的结论（“已中止”），没有验证副作用。

## 纠正与预防措施

| 措施 | 类型（预防/检测/缓解） | 负责人 | 状态 |
|---|---|---|---|
| Chart 0.3.1：发布配置写入 Pod 模板的 `env`，每个 ReplicaSet 携带自己的配置（expand/contract 迁移，旧 ConfigMap 暂留一个版本） | 预防 | 实验操作者 | 完成（P7） |
| P10 演练：中止时新建的稳定版 Pod 读到 0，中止后 4 分钟内稳定版慢请求为 0 | 验证 | 实验操作者 | 完成（INC-20261106-02） |
| 全体 Pod 的错误率与延迟告警（P7），SLO 多窗口燃烧率告警（P10） | 检测 | 实验操作者 | 完成 |
| 演练与发布的运行手册增加一步：中止或回滚后，按 Pod 检查实际配置并按 ReplicaSet 查看延迟 | 检测 | 实验操作者 | 完成（第 12 章运行手册） |
| 在后续 Chart 版本中删除遗留的 ConfigMap（expand/contract 的 contract 一步） | 清理 | 实验操作者 | 待办 |
| 若配置重新放回 ConfigMap，使用带内容哈希的不可变 ConfigMap（每个版本一个名字） | 预防 | 实验操作者 | 待评估 |

## 证据

- P6：`evidence/p6/canary-bad.log`、`evidence/p6/canary-bad-revert.log`、`evidence/p6/canary-bad-impact.log`
- P7：`evidence/p7/drill-prometheus-alerts.png`、`evidence/p7/prod-latency-investigate.log`、`evidence/p7/prod-latency-rootcause.log`、`evidence/p7/prod-latency-rootcause.png`、`evidence/p7/prod-latency-impact.log`
- P10（修复验证与预算换算）：`evidence/p10/drill-2-blast-radius.log`、`evidence/p10/drill-4-slo.log`
