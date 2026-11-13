# Incident RCA：prod 坏配置被金丝雀分析自动中止（P10 演练）

> **环境声明：** 本事件发生在本地测试环境（Kind 集群），为计划内的故障演练，不涉及真实用户与生产数据。

| 字段 | 内容 |
|---|---|
| 事件编号 | INC-20261106-02 |
| 严重级别 | SEV-3（金丝雀 Pod 存活的 72 秒里服务约 138 个请求，其中约 91 个慢于 0.5 s；无错误） |
| 开始 / 检测 / 缓解 / 结束时间（UTC） | 13:37:14 / 13:38:26 / 13:38:26（自动中止） / 13:45:27（Git 回滚后 Synced + Healthy） |
| 影响范围 | 金丝雀 ReplicaSet `8bf588ddc` 服务约 138 个 API 请求，其中约 91 个慢于 0.5 s；稳定版 0 个慢请求；5xx 为 0；消耗 30 天延迟预算的 0.034% |
| 检测方式 | Argo Rollouts 后台分析（AnalysisRun `demo-api-prod-8bf588ddc-9`，指标 `p95-latency-seconds`） |
| 负责人 | 实验操作者（由 Claude Code 代为执行） |

## 摘要

一个标题为“pricing call tuning”的合并请求（MR !22，配置仓库 `10a6786`）把 prod 的 `faults.latencyMs` 设为 800。这次变更只改配置、不改镜像，因此不经过 CI 的合成测试门禁（第 11 章）。Argo CD 约一分钟后同步，Argo Rollouts 据此创建新的 revision 9（同一镜像、不同 Pod 模板），以 20% 的权重运行金丝雀。后台分析在两次测量中都得到 p95 ≈ 0.96 s（阈值 0.5 s），于 13:38:26 自动中止发布。中止时为补足副本而新建的稳定版 Pod 读到的是 `FAULT_LATENCY_MS=0`，证明 INC-20261106-01 的修复（Chart 0.3.1）有效。随后用 `git revert` 让 Git 回到正确状态。

## 时间线

| 时间（UTC） | 事件 | 来源/证据 |
|---|---|---|
| 13:36:08 | 基线：prod 延迟与可用性燃烧率均为 0 | `evidence/p10/drill-1-bad-config.log` |
| 13:36 | MR !22 合并（`10a6786`，`faults.latencyMs: 800`） | 同上 |
| 13:37:14 | Argo CD 同步；Rollout 更新到 revision 9，创建 ReplicaSet `8bf588ddc`：**事件开始** | `evidence/p10/drill-2-blast-radius.log`（Rollout 事件） |
| 13:38:00 | 旧的阈值告警 `DemoApiHighLatency`（prod，1 分钟 p95 > 0.5 s）进入 pending | `evidence/p10/drill-4-slo.log` |
| 13:38:06 | 第一次分析测量：p95 0.961 s，失败 | `evidence/p10/drill-1-bad-config.log` |
| **13:38:26** | 第二次测量 0.962 s，失败次数 2 > failureLimit 1 → `RolloutAborted`；金丝雀缩到 0，稳定版扩回 5（新 Pod `nl8wl`，FAULT_LATENCY_MS=0）：**检测 + 缓解** | 同上；`drill-2-blast-radius.log` |
| 13:38:45 | `KubePodNotReady`、`TargetDown` 短暂 pending（Pod 更替所致），未 firing | `evidence/p10/drill-4-slo.log` |
| 13:39:00 | `DemoApiHighLatency` firing：此时问题已被自动缓解 34 秒 | 同上 |
| 13:43:37 | 中止后 4 分钟：稳定版慢请求 0，5xx 0 | `drill-2-blast-radius.log` |
| 13:43:56 | `revert.sh 10a6786 --merge`（MR !23，`39ee3f2`） | `evidence/p10/drill-3-revert.log` |
| 13:45:27 | Argo CD 同步后 Synced + Healthy，未重启任何 Pod：**结束** | 同上 |

## 影响

- 金丝雀约 138 个请求，约 91 个慢于 0.5 s（下单接口占 70%，与注入只影响下单一致）；没有失败请求。
- 延迟燃烧率峰值：5 分钟窗口 3.12，1 小时窗口 0.245，远低于分页阈值 14.4；SLO 告警没有触发，这是预期行为。
- 预算：30 天延迟预算约 266,800 个慢请求（10.29 个请求/秒 × 30 天 × 1%），本次消耗 0.034%。同样的坏配置在 INC-20261106-01 中消耗了 5.87%。

## 根因分析（5 Whys）

1. **为什么有约 91 个请求变慢？** 金丝雀 Pod 以 `FAULT_LATENCY_MS=800` 运行。
2. **为什么金丝雀带着这个配置？** prod 的 values 被一个合并请求改成了 800（演练中故意为之；现实中对应“看似无害的调参”）。
3. **为什么坏配置能进入 prod？** 配置仓库的合并请求没有自动检查：只改配置的变更不会构建镜像，也就不经过合成测试门禁；没有策略禁止 prod 出现非零的故障注入参数。
4. **为什么影响只有 72 秒、约 138 个请求？** 金丝雀只分到 20% 的流量（5 个 Pod 中的 1 个）；后台分析在 45 秒初始延迟后每 20 秒测量一次，失败两次即中止。
5. **为什么中止后没有像 INC-20261106-01 那样留下被污染的 Pod？** Chart 0.3.1 把配置写进了 Pod 模板，稳定版 ReplicaSet 的模板仍是 0，中止时新建的 Pod 也只能读到 0。

**根本原因（演练设定）：** 未经验证的配置变更直接进入 prod。**限制影响的因素：** 金丝雀 + 自动分析 + 按版本隔离的配置。

## 检测与响应评价

**做得好的：**
- 检测与缓解全部自动完成：从金丝雀创建到中止 72 秒，没有人工介入。
- 稳定版完全未受影响（按 Pod 检查环境变量、按 ReplicaSet 统计延迟两方面证实）。
- 回滚走 Git（MR !23），Git、Argo CD 与集群重新一致，留下审计记录。

**待改进的：**
- **阈值告警的噪声。** `DemoApiHighLatency` 在问题被自动缓解 34 秒后才 firing。如果它会呼叫值班人员，这就是一次无用的深夜电话。燃烧率告警按预算消耗速度判断，这次正确地保持了安静。
- **Argo CD 轮询延迟。** 合并后约 66 秒才同步（13:36 → 13:37:14），回滚时也等了 81 秒。用 Git webhook 通知 Argo CD 可以把它缩短到几秒。
- **配置变更缺少左移检查。** 坏配置本可以在合并请求阶段就被拒绝。

## 纠正与预防措施

| 措施 | 类型（预防/检测/缓解） | 负责人 | 状态 |
|---|---|---|---|
| 配置仓库的 MR 流水线增加策略检查：`envs/prod` 中 `faults.*` 必须为 0（例如 GitLab CI 中用 yq 或 conftest） | 预防 | 实验操作者 | 待办（第 12 章练习） |
| 分页只用 SLO 燃烧率告警；`DemoApiHighLatency` 改为工单级别，或增大 `for` | 检测 | 实验操作者 | 建议 |
| 为 Argo CD 配置 GitLab webhook，缩短同步延迟 | 缓解 | 实验操作者 | 建议 |
| 保留“中止后按 Pod 检查配置、按 ReplicaSet 看延迟”的运行手册步骤 | 检测 | 实验操作者 | 完成（第 12 章） |

## 证据

`evidence/p10/drill-1-bad-config.log`、`drill-2-blast-radius.log`、`drill-3-revert.log`、`drill-4-slo.log`、`rollouts-prod-aborted.png`、`prometheus-drill-window.png`
