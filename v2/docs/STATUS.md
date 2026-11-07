# 第二轮 STATUS

> 只在验收通过后更新。路径相对于 `v2/`。状态取值：`NOT_RUN`、`IN_PROGRESS`、`VALIDATED`、`PARTIAL`、`BLOCKED`。计划与验收标准见 [PLAN](PLAN.md)。

| 阶段 | 主题 | 状态 | 证据 | 备注 |
|---|---|---|---|---|
| E0 | 平台基线与资源预算 | VALIDATED | `evidence/e0/`、第 1 章 | 1+3 节点，工作节点由内核限制为 4 CPU/3 GiB；allocatable 2666 MiB、驱逐起点 2922 MiB 经 `/configz` 证实；发现 Kind 默认无内存驱逐 |
| E1 | 多服务系统 | NOT_RUN | | |
| E2 | 服务网格与 L7 流量 | NOT_RUN | | |
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
