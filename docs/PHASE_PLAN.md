# Phase 执行计划（自主执行版）

> 制定：2026-11-06 ｜ 依据：[DEVOPS_SPECIALTY_ROADMAP.md](DEVOPS_SPECIALTY_ROADMAP.md)
> 规则：每个 Phase 必须**实际执行 → 保存证据 → 通过验收**后才进入下一个 Phase。
> 无法执行的部分如实标记为 `NOT_RUN` 或 `BLOCKED` 并写明原因，**不虚构任何执行结果**。

## 1. 执行环境基线

| 项 | 选择 | 理由 |
|---|---|---|
| 宿主机 | Windows 11 家庭中文版；Ryzen 7 8845HS（16 线程）；31 GB 内存 | 用户现有机器 |
| Linux 实验环境 | 新建独立 WSL2 发行版 `devops-lab`（Ubuntu 24.04 LTS，装在 D 盘） | 官方文档默认 Linux；与已有 Podman 环境隔离；C 盘剩余空间有限 |
| 容器运行时 | Docker Engine（download.docker.com 官方 apt 源） | Kind、GitLab Runner 与各官方教程默认使用 Docker |
| Kubernetes | Kind v0.33.0，节点镜像 `kindest/node:v1.37.0`（固定 digest） | 本地优先、零云成本 |
| 代码托管 / CI | GitHub `miku-wwl/devops-delivery`（public）+ GitHub Actions + GHCR | 公开仓库可免费使用 Actions、规则集（Ruleset）和 Artifact Attestations |
| GitLab | 本地自建 GitLab CE + GitLab Runner（Docker executor） | 无需注册或验证信用卡，完全可复现 |
| 被交付应用 | `app/`：自建的小型 FastAPI 参考服务（**训练用参考负载，不是业务软件**）；观测部分另用官方 OpenTelemetry Demo | 路线图第 4 节：使用已有/最小可运行服务 |
| 手册工具链 | Markdown → pandoc → HTML → Edge（Playwright）打印 PDF；Mermaid 画架构图 | 中文排版稳定，支持代码高亮、截图与图表 |

工具版本固定在 [automation/lab/versions.env](../automation/lab/versions.env)，每个二进制安装前都校验官方 SHA256。

## 2. Phase 列表与验收标准

| Phase | 路线图 | 内容 | 验收标准（自定义考核） | Gate |
|---|---|---|---|---|
| P0 | — | 实验环境、工程骨架、证据与手册工具链 | `docker run hello-world` 和 Kind 冒烟集群通过；手册管线能生成含中文、代码、Mermaid 图和截图的测试 PDF | — |
| P1 | D1 | GitHub Actions：官方 Hello GitHub Actions 练习；参考服务；PR 质量门禁（lint/test/coverage）、Artifacts、Caching、Reusable Workflow | PR 自动门禁运行成功；故意失败的测试阻断合并，修复后可合并 | G1（前半） |
| P2 | D2 | GitLab CI/CD：`.gitlab-ci.yml`（stages、rules、needs、artifacts、cache、MR pipeline） | 本地 GitLab 上的构建/测试/打包流水线独立运行；失败 MR 不能合并 | G1（后半） |
| P3 | D3 | Helm：Chart 开发、lint/template、按环境区分 values、install/upgrade/rollback、package | 同一 Chart 可重复部署到 dev/prod 两个命名空间，配置按环境区分 | — |
| P4 | D4 | Argo CD：Git 作为期望状态、Sync、Drift、Self-Heal、回滚 | 声明式部署成功；人为漂移被检测、解释并自动或手动恢复 | G2 |
| P5 | D5 | DevSecOps：Trivy 扫描与策略、SBOM、GHCR 镜像 digest、Cosign 无密钥签名、GitHub Artifact Attestation | 漏洞策略阻断不合格制品；签名与 Attestation 验证通过；同一 digest 在环境间晋级 | G3 |
| P6 | D6 | 渐进式交付：Argo Rollouts Canary、手动晋级/中止、基于 Prometheus 的自动分析、GitHub Environments 审批 | 故障版本自动停止晋级，稳定版恢复；审批门禁生效 | G4 |
| P7 | D7 / O1 | 开放可观测性：官方 OpenTelemetry Demo；参考服务接入 OTel Collector、Prometheus、Grafana、Loki、Tempo | 在一次 5xx/高延迟演练中用至少两类信号（Metrics/Traces/Logs）定位故障 | G5 |
| P8 | D8 / O2 | Datadog Learning Center 学习路径 | **需要用户本人账号**；无账号时标记 `BLOCKED`，只提供学习指引与配置材料 | G6 |
| P9 | D9 | 可观测性 × CI/CD：发布前合成测试门禁（开源实现：Kind-in-CI + k6）；Datadog Synthetic 方案 | 合成测试失败阻断、恢复后通过（开源实现）；Datadog 版本无账号时 `NOT_RUN` | G7（部分） |
| P10 | O3 | 交付闭环综合演练：Commit → CI → Scan → Sign → GitOps → Canary → 观测 → 晋级/中止 → RCA | 延迟故障版本被中止并回滚；输出测试环境 Incident RCA | — |
| P11 | D10（可选） | Ansible：Inventory、Playbook、幂等性 | 第二次执行 `changed=0` | — |
| P12 | — | 整合 PDF 学习手册；README/STATUS 收尾；资源清理 | PDF 生成；状态如实、不夸大 | G8 |

O0（Abhishek Veeramalla 视频）属于用户自学的辅助材料，本计划不代为观看，也不转述其内容。

## 3. 证据规范

- `evidence/pN/*.log`：用 [automation/evidence/transcript.sh](../automation/evidence/transcript.sh) 录制的真实终端记录（命令 + 原样输出 + 非零退出码）。
- `evidence/pN/*.png`：Web 界面截图（GitHub、GitLab、Argo CD、Grafana 等），以及由真实终端记录渲染出的终端截图。
- `docs/experiments/PN-*.md`：每个 Phase 的实验记录（目标、环境、步骤、预期、实际、失败分析、清理）。
- [STATUS.md](STATUS.md) **只在验收通过后**更新。

## 4. 需要用户本人完成或授权的事项

| 事项 | 影响 | 当前处理 |
|---|---|---|
| Datadog 账号 / Learning Center 注册 | P8、P9 的 Datadog 部分 | 不代为注册；准备好材料，状态标记为 BLOCKED/NOT_RUN |
| 观看 O0 视频 | 背景理解 | 用户自学 |
| GHCR 包可见性（如默认为 private） | P5 起本地集群拉取 CI 构建的镜像 | 到时检查；如需在网页上点一次“改为 public”，会明确说明 |

## 5. 安全与成本规则

- 不提交任何 Token、密钥、kubeconfig 或含密码的截图；实验环境的本地密码在运行时生成，只保存在 WSL 内的 `~/.lab-secrets/`（不在仓库内）。
- 第三方 GitHub Actions 全部固定到 commit SHA；`permissions` 最小化。
- 全部实验在本地 Kind 集群与 GitHub 免费额度内完成，不创建云资源。
