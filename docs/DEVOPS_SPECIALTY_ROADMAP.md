# DevOps Software Delivery & Observability — 官方专项训练路线图

> 版本：2026-11-01 | 状态：PLANNED（尚未执行）  
> 目标岗位：New Zealand DevOps / DevSecOps / SRE / Developer Experience Engineer  
> 定位：与 KPCP（云平台控制平面）互补，聚焦软件交付、发布安全、可观测性与事件响应。  
> 资源准入规则：正式课程/实验只选官方项目或大型厂商官方训练；保留用户指定的一部独立作者视频作为**辅助讲解，不当作官方教学证据**。

## 0. 资源来源分级

- **Official Training**：GitHub Skills、GitLab University/Docs、Datadog Learning Center、Red Hat Developer 等由产品厂商发布的培训及实验。
- **Official Project Tutorial**：Helm、Argo CD、Argo Rollouts、OpenTelemetry、Prometheus、Grafana、Trivy、Sigstore 的项目官方文档和示例。
- **Specified Supplementary Video**：Abhishek Veeramalla 的 [Learn Observability in 5 Hours](https://www.youtube.com/watch?v=cYAE0ZhT43c)；不是厂商/基金会官方课程。
- **Custom Assessment**：下表中所有「验收门槛」「故障演练」是基于招聘要求制定的自定义工程考核，并非各课程原本的考试。

## 1. 正式训练模块与官方入口

| ID | 主题 | 主要官方课程/实验 | 核心实践 | 建议验收 |
|---|---|---|---|---|
| D1 | GitHub Actions | [GitHub Skills: Hello GitHub Actions](https://github.com/skills/hello-github-actions)、[GitHub Actions Quickstart](https://docs.github.com/en/actions/get-started/quickstart) | PR Build/Test、Artifacts、Caching、Reusable Workflows | PR 自动质量门禁运行成功；测试故障能阻断合并 |
| D2 | GitLab CI/CD | [GitLab Docs: Complex Pipeline Tutorial](https://docs.gitlab.com/ci/quick_start/tutorial/)、[GitLab CI/CD Hands-on Lab Guide](https://handbook.gitlab.com/handbook/customer-experience/professional-services-engineering/education-services/ilt-labs/gitlabcicdhandson/)、[GitLab University](https://university.gitlab.com/) | `.gitlab-ci.yml`、Rules、Needs、Artifacts、MR Pipeline | 独立运行 GitLab 构建/测试/部署流水线 |
| D3 | Helm / Containers | [Helm Official Docs](https://helm.sh/docs/)、[Chart Template Guide](https://helm.sh/docs/chart_template_guide/) | `helm lint/template`、values、chart 版本、打包 | 可重复部署一个已有应用，配置按环境区分 |
| D4 | GitOps | [Argo CD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)、[Argo CD Official Examples](https://github.com/argoproj/argocd-example-apps) | Git 作为期望状态、Sync、Drift、回滚 | 声明式部署且能观察与修复漂移 |
| D5 | DevSecOps / Supply Chain | [Trivy Official Getting Started](https://www.trivy.dev/docs/latest/getting-started/)、[GitHub Artifact Attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)、[Sigstore Cosign Official](https://docs.sigstore.dev/cosign/signing/signing_with_containers/) | Image/Repo Scan、SBOM、Digest、签名/来源验证 | 漏洞策略阻断不合格发布；同一镜像 Digest 在环境间晋级 |
| D6 | Progressive Delivery | [Argo Rollouts Getting Started](https://argo-rollouts.readthedocs.io/en/stable/getting-started/)、[GitHub Deployment Environments](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments) | Canary、Manual Promotion/Abort、Rollback、Approval | 故障版本停止晋级，稳定版恢复 |
| D7 | Open Observability | [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/)、[OpenTelemetry Kubernetes](https://opentelemetry.io/docs/platforms/kubernetes/getting-started/)、[Prometheus Tutorial](https://prometheus.io/docs/tutorials/)、[Grafana Learn](https://grafana.com/docs/learning-hub/) | Metrics、Logs、Traces、Collector、PromQL、Alerting、Tracing | 能通过 Trace/Metric/Log 关联定位一次错误 |
| D8 | Datadog Observability | [Datadog Learning Paths](https://learn.datadoghq.com/pages/learning-paths)、[Datadog SRE Path](https://learn.datadoghq.com/bundles/site-reliability-engineer-learning-path)、[Datadog Courses](https://learn.datadoghq.com/collections) | Datadog Metrics、Monitors、Dashboards、APM、Logs、SLO、Incident Management | 完成所选 Learning Path 官方实验并保存学习记录 |
| D9 | Observability × CI/CD | [Datadog: Synthetic Tests in a CI/CD Pipeline](https://learn.datadoghq.com/courses/synthetic-tests-ci-cd-pipeline) | `datadog-ci`、Synthetic API Test、失败阻断发布 | CI 检测出预置故障并阻断或中止发布 |
| D10（可选） | Linux / Ansible | [Red Hat Ansible Learning](https://developers.redhat.com/learn/ansible)、[Ansible Official Getting Started](https://docs.ansible.com/projects/ansible/latest/getting_started/get_started_ansible.html) | Inventory、Playbook、Idempotency、Linux | 重复执行 Playbook 不产生不必要变更 |

**费用与权限注意事项：** GitLab 的 Instructor-led CI/CD Training 是收费课程，以上 D2 优先选 GitLab 官网的免费自学教程；其部分课程实验环境需要付费培训邀请码。GitHub 的审批保护、私有仓库构建来源证明等功能视 GitHub 计划和仓库可见性而定，不应假设全部免费。Datadog 官方 Learning Center 标注免费自学和配套实验，但将其接入个人真实云账户时可能产生独立费用。

## 2. Observability 专项详细顺序（新增重点）

### O0 — 视频辅助理解（用户指定，非官方）

观看 [Learn Observability in 5 Hours — Abhishek Veeramalla](https://www.youtube.com/watch?v=cYAE0ZhT43c)。据作者公开介绍，内容涵盖：
- Observability 基础，以及 Monitoring 与 Observability 的差别
- Prometheus 与 PromQL、指标类型、应用埋点
- EFK 日志采集与查询
- Jaeger 分布式链路追踪
- OpenTelemetry 端到端演示

**注意：** 该视频为独立内容创作者的教程。章节内容以实际视频为准；如命令或版本过期，按下面各官方产品最新文档执行，不直接照搬视频中的版本。

### O1 — CNCF / 项目官方 OpenTelemetry 实操

- [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/)：部署官方多服务 Demo，观察跨服务请求。
- [OpenTelemetry for Ops](https://opentelemetry.io/docs/getting-started/ops/)：学习 Collector、自动采集及导出。
- [Prometheus Getting Started](https://prometheus.io/docs/prometheus/latest/getting_started/)：验证指标采集和 PromQL。
- [Grafana Learn](https://grafana.com/docs/learning-hub/)：完成 Dashboard、Alerting、Trace 相关路径。

**验收：** 能解释 Logs/Metrics/Traces 各自能回答什么问题，并在一次 HTTP 5xx 或高延迟演练中用至少两类信号定位故障。

### O2 — Datadog Learning Center：按这个顺序学完指定路径

1. [Introduction to Observability](https://learn.datadoghq.com/collections)（官方课程目录可检索）
2. [Core Skills Learning Path](https://learn.datadoghq.com/pages/learning-paths) — Tagging、Metrics、Monitors、Dashboards。
3. [Configuration Learning Path](https://learn.datadoghq.com/pages/learning-paths) — Datadog Agent、Docker、Integrations。
4. [Site Reliability Engineer Learning Path](https://learn.datadoghq.com/bundles/site-reliability-engineer-learning-path) — APM、基础设施/网络监控、SLO、Incident Management。
5. [Log Querying & Analytics Learning Path](https://learn.datadoghq.com/pages/learning-paths) — Logs 查询与分析。
6. [Kubernetes Monitoring Learning Path](https://learn.datadoghq.com/pages/learning-paths) — 集群可观测性。
7. [Synthetic Tests in a CI/CD Pipeline](https://learn.datadoghq.com/courses/synthetic-tests-ci-cd-pipeline) — 将监控反馈接入交付流水线。

**“学完”的含义：** 完成以上所选官方 Learning Paths 与指定课程的实验，不要求把 Datadog 官网所有无关产品课程一一学完。完成记录应包括课程名称、日期、实验结果和官方学习成果（若课程提供）。

### O3 — 交付闭环（自定义综合验收）

`Commit → CI → Scan → Signed Artifact → Argo CD/Rollouts → OTel/Datadog → SLO/Synthetic Gate → Promotion or Abort → RCA`

- 部署故意增加延迟的版本。
- 观察 P95 延迟、错误率、Trace 与日志。
- 依据自定义 SLO/发布阈值决定是否推进 Canary。
- 触发失败门禁，验证 Abort/Rollback；保存可复现证据。
- 最后编写一份 Incident RCA，注明数据来自**测试环境**。

## 3. 六周建议执行安排

| 周次 | 重点 | 最终产物 |
|---|---|---|
| W1 | D1 GitHub Actions + D2 GitLab CI | 两套构建测试流水线、失败样例 |
| W2 | D3 Helm + D4 Argo CD | Chart、GitOps 示例、漂移修复记录 |
| W3 | D5 Trivy/SBOM/Attestation + D6 Rollouts | 制品可信链、Canary 和回滚记录 |
| W4 | 视频 O0 + 官方 O1（OpenTelemetry/Prometheus/Grafana） | 指标、日志、链路追踪关联分析 |
| W5 | Datadog O2（Core + SRE + Logs + Kubernetes） | Learning Center 课程记录、SLO/Monitor 配置 |
| W6 | D9 Datadog Synthetic CI/CD + 综合 O3 | 端到端发布门禁、故障复盘、交付报告 |

六周为建议节奏，不是官方承诺的完成时间；课程时长、实际环境和付费功能可能改变进度。

## 4. 项目边界与成本

- 使用**已有后端服务**作为交付对象（例如后续 LedgerCore 的最小可运行 API，或 CNCF OpenTelemetry Demo）。不新建另一套云基础设施控制平面。
- 本地优先：Kind、Helm、Argo CD、OpenTelemetry Demo。Docker、Runner、Registry 可先使用本地或免费额度资源。
- 不复制 KPCP 的 CRD、Terraform approval、基础设施生命周期管理。
- 不提交任何 Datadog API Key、GitHub/GitLab Token、云密钥、真实用户日志或包含密钥的截图。
- 用 GitHub Actions OIDC 替代长期云密钥；对第三方 Actions 固定 Commit SHA，验证镜像 Digest 和签名。
- 注意私有仓库可能没有 GitHub Artifact Attestations 或高级环境保护规则的完整权限；以官方文档和当前账户方案为准。
- Datadog Learning Center 的实验通常免费，但自建账户持续上报可能收费；训练后清理所有云资源及监控数据源。

## 5. 阶段 Gates（自定义，不属于官方课程）

- **G1:** GitHub 和 GitLab 均有可复现的构建/测试 Pipeline。
- **G2:** Helm/Argo CD 成功部署，Git Drift 能被检测、解释并恢复。
- **G3:** 扫描策略阻止不合格制品，签名/Attestation 经验证通过。
- **G4:** Canary 不健康时可安全中止/回滚；记录发布版本与恢复过程。
- **G5:** OpenTelemetry Metrics、Logs、Traces 能帮助独立定位指定故障。
- **G6:** Datadog 选定路径已完成，至少有一个 SLO、Monitor 和一次 Incident 调查记录。
- **G7:** Datadog Synthetic 测试实际参与 CI 门禁；存在失败和恢复两份证据。
- **G8:** README 不夸大：官方课程完成状态、实验环境、测试结果和未覆盖能力明确区分。

## 6. 求职岗位对应

| NZ DevOps JD 类型 | 重点展示 |
|---|---|
| ASB / Developer Platform | GitHub Actions、Reusable Workflow、Runner、Developer Experience |
| ZURU / DevOps & SRE | GitLab CI、OpenTelemetry、SLO、发布门禁、Incident Response |
| Partly / DevSecOps | Argo CD、GitOps、Trivy、SBOM、签名、供应链安全 |
| SecuritEase / Senior DevOps | Helm、Kubernetes、Grafana、日志、备份/恢复、CI/CD |
| IDEXX / Developer Experience | 构建效率、测试可靠性、流水线可复用性 |

此表用于针对 JD 决定展示重点；不表示完成训练即可满足生产工作经验要求。以上所有实验初始状态为 **NOT_RUN**。

## 7. 不推荐作为当前训练起点的旧仓库

Google/DORA 之前开源的 [Four Keys](https://github.com/dora-team/fourkeys) 已在 2024 年归档，不推荐作为仍在维护的 DevOps 专项练习主仓库。可以借鉴指标定义，但建议通过现有 CI/CD 平台报告、仪表盘和官方文档来做交付指标实验。

---

### 资源审查结论

- GitHub、GitLab、Helm、Argo、OTel、Prometheus、Grafana、Red Hat、Trivy、Sigstore、Datadog 的主资源来自官方发布渠道。
- 用户指定的视频是独立作者教程，非官方；只作为辅助理解，**不能替代官方实验**。
- 综合路线、周次和 Gates 由本计划设计，**不是任何一家公司的官方完整课程**。
- 尚未运行用户账户下的实验，也未核实个人账户对付费功能的权限。
