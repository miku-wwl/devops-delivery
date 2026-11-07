# 第二轮 STATUS

> 只在验收通过后更新。路径相对于 `v2/`。状态取值：`NOT_RUN`、`IN_PROGRESS`、`VALIDATED`、`PARTIAL`、`BLOCKED`。计划与验收标准见 [PLAN](PLAN.md)。

| 阶段 | 主题 | 状态 | 证据 | 备注 |
|---|---|---|---|---|
| E0 | 平台基线与资源预算 | VALIDATED | `evidence/e0/`、第 1 章 | 1+3 节点，工作节点由内核限制为 4 CPU/3 GiB；allocatable 2666 MiB、驱逐起点 2922 MiB 经 `/configz` 证实；发现 Kind 默认无内存驱逐 |
| E1 | 多服务系统 | VALIDATED | `evidence/e1/`、第 2 章 | 6 个服务 + CNPG/Valkey/NATS，全部经 Argo CD 从 Git 部署（735 s 收敛）；订单链路 6 个服务 65 个 span（含 NATS 异步段）；28 个测试；第一次部署的 8 个问题均有证据并修复；一次计划外的 PG 故障转移无数据丢失 |
| E2 | 服务网格与 L7 流量 | VALIDATED | `evidence/e2/`、第 3 章 | Istio 1.31.4 ambient：服务间明文请求行 140 → 0；waypoint 让各服务副本分布 46.9%–53.1%（L4 下 97/3）；交替 A/B：L4 +2.4 ms、waypoint +1.3 ms（浏览 p50）；网格重试 ×4 不受应用预算约束；STRICT 切断网格外调用方；一次真实的“扣款成功、订单失败”事故；约 900 ms 的进程停顿未复现，原因未找到 |
| E3 | 负载与容量规划 | NOT_RUN | | |
| E4 | 弹性与调度 | NOT_RUN | | |
| E5 | 多租户与安全治理 | NOT_RUN | | |
| E6 | 故障注入与传播 | NOT_RUN | | |
| E7 | 数据可靠性与灾难恢复 | NOT_RUN | | |
| E8 | 发布治理 | NOT_RUN | | |
| E9 | 可观测性与事故响应 | NOT_RUN | | |
| E10 | 大规模控制面 | NOT_RUN | | |
| E11 | IaC 与云迁移 | NOT_RUN | | |
| E12 | 能力考核与教材 | NOT_RUN | | |
