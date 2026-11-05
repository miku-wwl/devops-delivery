# STATUS

> 只在**验收通过后**更新。状态取值：`NOT_RUN`、`IN_PROGRESS`、`VALIDATED`、`PARTIAL`（部分验证）、`BLOCKED`（缺少外部条件）。
> 计划与验收标准见 [PHASE_PLAN.md](PHASE_PLAN.md)。

| Phase | 模块 | 状态 | 证据 | 备注 |
|---|---|---|---|---|
| P0 | 实验环境与工具链 | VALIDATED | [P0 记录](experiments/P0-environment.md)、`evidence/p0/` | Kind v1.37.0 冒烟通过 |
| P1 | D1 GitHub Actions | VALIDATED | [P1 记录](experiments/P1-github-actions.md)、`evidence/p1/`、PR #1 #2 | 门禁与阻断已验证；官方 Skills 练习 NOT_RUN（需用户创建仓库）；PR 合并待所有者审阅 |
| P2 | D2 GitLab CI/CD | VALIDATED | [P2 记录](experiments/P2-gitlab-ci.md)、`evidence/p2/` | 本地自建 GitLab CE 19.5.3；MR 阻断与合并、手动发布闸门已验证 |
| P3 | D3 Helm | VALIDATED | [P3 记录](experiments/P3-helm.md)、`evidence/p3/` | dev/prod 同一 Chart；坏配置发布 55% 错误 → 回滚恢复 |
| P4 | D4 Argo CD / GitOps | NOT_RUN | — | — |
| P5 | D5 DevSecOps / 供应链 | NOT_RUN | — | — |
| P6 | D6 渐进式交付 | NOT_RUN | — | — |
| P7 | D7 / O1 开放可观测性 | NOT_RUN | — | — |
| P8 | D8 / O2 Datadog Learning | NOT_RUN | — | 需要用户本人账号 |
| P9 | D9 可观测性 × CI/CD | NOT_RUN | — | Datadog 部分需要用户账号 |
| P10 | O3 交付闭环 + RCA | NOT_RUN | — | — |
| P11 | D10 Ansible（可选） | NOT_RUN | — | — |
| P12 | PDF 手册整合 | NOT_RUN | — | — |
