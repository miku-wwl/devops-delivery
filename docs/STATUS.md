# STATUS

> 只在**验收通过后**更新。状态取值：`NOT_RUN`、`IN_PROGRESS`、`VALIDATED`、`PARTIAL`（部分验证）、`BLOCKED`（缺少外部条件）。
> 计划与验收标准见 [PHASE_PLAN.md](PHASE_PLAN.md)。

| Phase | 模块 | 状态 | 证据 | 备注 |
|---|---|---|---|---|
| P0 | 实验环境与工具链 | VALIDATED | [P0 记录](experiments/P0-environment.md)、`evidence/p0/` | Kind v1.37.0 冒烟通过 |
| P1 | D1 GitHub Actions | VALIDATED | [P1 记录](experiments/P1-github-actions.md)、`evidence/p1/`、PR #1 #2 | 门禁与阻断已验证；官方 Skills 练习 NOT_RUN（需用户创建仓库）；PR 合并待所有者审阅 |
| P2 | D2 GitLab CI/CD | VALIDATED | [P2 记录](experiments/P2-gitlab-ci.md)、`evidence/p2/` | 本地自建 GitLab CE 19.5.3；MR 阻断与合并、手动发布闸门已验证 |
| P3 | D3 Helm | VALIDATED | [P3 记录](experiments/P3-helm.md)、`evidence/p3/` | dev/prod 同一 Chart；坏配置发布 55% 错误 → 回滚恢复 |
| P4 | D4 Argo CD / GitOps | VALIDATED | [P4 记录](experiments/P4-gitops.md)、`evidence/p4/` | 配置仓库在本地 GitLab；MR 发布、漂移自愈/检测、git revert 回滚、AppProject 护栏（G2） |
| P5 | D5 DevSecOps / 供应链 | VALIDATED | [P5 记录](experiments/P5-supply-chain.md)、`evidence/p5/` | Trivy 门禁与真实修复；SBOM + SLSA 证明 + Cosign 签名并独立验证；同一 digest dev→prod；Kyverno 准入（G3） |
| P6 | D6 渐进式交付 | VALIDATED | [P6 记录](experiments/P6-progressive-delivery.md)、`evidence/p6/` | 好版本分析 12/12 后人工晋级；坏版本 65 s 内自动中止（金丝雀本身占 1.4% 请求）；生产审批闸门待所有者批准（G4）。**勘误**：中止时一个稳定版 Pod 读到坏配置，P7 发现并修复（见 P6 记录） |
| P7 | D7 / O1 开放可观测性 | VALIDATED | [P7 记录](experiments/P7-observability.md)、`evidence/p7/` | 官方 OTel Demo 支付故障与 demo-api 错误/延迟演练，均用指标、链路、日志三类信号定位（G5）；意外发现并修复 P6 遗留的 prod 问题（Chart 0.3.1） |
| P8 | D8 / O2 Datadog Learning | PARTIAL | [P8 记录](experiments/P8-datadog-learning.md)、`evidence/p8/` | 3 条路径 14 门课的 56 篇讲义已读并经平台记录（50%–75%）；Agent on a Host 挑战 1–5、Agent on Docker 挑战 1–2 通过实验检查；网页登录（不能代输密码）、问卷与认证需用户本人完成 |
| P9 | D9 可观测性 × CI/CD | VALIDATED | [P9 记录](experiments/P9-synthetic-gate.md)、`evidence/p9/` | 开源实现（CI 中 Kind + k6）：延迟故障运行中发布作业被跳过（42196278404），恢复后通过并发布（42196846132）（G7 开源部分）；Datadog Synthetic 方案 NOT_RUN（无可用于 CI 的账号，只有模板） |
| P10 | O3 交付闭环 + RCA | VALIDATED | [P10 记录](experiments/P10-closed-loop.md)、`evidence/p10/`、[RCA](rca/) | 好版本走完整条链（CI 首次在阶段分支上运行即发现并修复 7 个遗留高危配置问题）；坏配置金丝雀分析开始 65 秒后自动中止，稳定版未被污染（验证 P7 修复），Git 回滚恢复；SLO 燃烧率规则上线；两份 RCA |
| P11 | D10 Ansible（可选） | VALIDATED | [P11 记录](experiments/P11-ansible.md)、`evidence/p11/` | 两个容器作为托管节点（`community.docker.docker` 连接）；第二次执行三台主机均 `changed=0`；人为漂移被 `--check --diff` 发现并纠正 |
| P12 | PDF 手册整合 | VALIDATED | [验收报告](ACCEPTANCE_REPORT.md)、`manual/dist/`、`evidence/p12/` | 241 页手册：前言、13 章、附录 A–E、76 道练习与答案；6 组新实验写成“深入”章节；逐页视觉检查两轮，证据核验 8 项全部通过 |
