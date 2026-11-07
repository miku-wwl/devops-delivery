# 全景：一条现代软件交付链路 {#ch-overview}

<div class="lead">在进入具体技术之前，先站远一点看清全貌：这本书要解决哪些问题，最终搭起来的系统长什么样，一个代码变更要经过哪些关卡才能到达生产，各章之间是什么关系，以及怎样从零复现整套实验。读完本章，后面每一章在整体中的位置都会很清楚。</div>

## 本书要回答的三个问题 {#ov-questions}

现代软件交付工程可以归结为三个问题：

1. **怎样交付得又快又稳？** 每次提交都自动构建和测试（第 3、4 章），部署由 Git 中的声明驱动（第 5、6 章），新版本先让小部分流量试用、由指标决定是否继续（第 8 章）。
2. **交付的东西可信吗？** 依赖与镜像经过漏洞扫描，制品带有签名、来源证明和物料清单，集群只运行自己流水线构建的镜像（第 7 章）；上线前还要通过模拟真实用户的合成测试（第 11 章）。
3. **出了问题，能多快知道、多快恢复、怎样不再犯？** 指标、链路、日志三种信号（第 9、10 章），面向用户的 SLO 与燃烧率告警，以及无责的事故复盘（第 12 章）。

衡量交付能力的常用尺子是 DORA 的四个关键指标：**变更前置时间**（从提交到上线）、**部署频率**、**变更失败率**、**失败部署的恢复时间**。前两个衡量速度，后两个衡量稳定性。DORA 的研究反复表明，二者并不矛盾：自动化的门禁、小批量的变更和快速的回滚，让团队可以既快又稳。本书的每一章都在改善其中的一个或几个指标。

## 系统全景 {#ov-architecture}

```{.mermaid caption="本书最终搭建的系统：三条主线，各自运行在不同的地方"}
flowchart LR
  subgraph CODE["① 代码线：GitHub"]
    direction TB
    A1["提交与 PR"] --> A2["质量门禁<br/>合成测试"] --> A3["扫描 · 签名 · 证明"] --> A4["GHCR<br/>按 digest 发布"]
  end
  subgraph DEPLOY["② 部署线：本机 GitLab + Kind"]
    direction TB
    B1["合并请求<br/>修改部署状态"] --> B2["Argo CD<br/>同步"] --> B3["Kyverno<br/>验证来源"] --> B4["Argo Rollouts<br/>金丝雀"]
  end
  subgraph FEED["③ 反馈线：可观测性"]
    direction TB
    C1["指标 · 链路 · 日志"] --> C2["分析与<br/>SLO 告警"] --> C3["晋级 / 中止<br/>回滚"] --> C4["复盘<br/>改进关卡"]
  end
  CODE --> DEPLOY --> FEED
```

三条主线分别是：

- **代码线（GitHub）**：代码经质量门禁与合成测试，构建出镜像；镜像被扫描、签名、附上来源证明后，按 digest 推送到 GHCR。签名所用的身份来自 Sigstore 的无密钥签名。
- **部署线（本机的 GitLab 与 Kind 集群）**：部署状态保存在 GitLab 中独立的配置仓库里，每次发布都是一次合并请求；Argo CD 把集群拉向 Git 中的状态，Kyverno 在准入时拒绝来历不明的镜像，Argo Rollouts 以金丝雀方式推进新版本。
- **反馈线（集群中的可观测性组件）**：Prometheus、OpenTelemetry Collector、Tempo、Loki 和 Grafana 收集三种信号；金丝雀分析决定晋级还是中止，SLO 燃烧率告警判断对用户的承诺是否受到威胁；事后的复盘再反过来改进前面的关卡。

各组件具体运行在哪里、怎样访问，见本章“实验环境拓扑”一节。

## 一个变更的一生 {#ov-change}

第 12 章用一个真实的功能（为每个请求附带 X-Request-ID）完整地走了一遍这条链路。下表按顺序列出它经过的每一站：

| 步骤 | 发生了什么 | 关键技术 | 章节 |
|---|---|---|---|
| 1 | 提交代码，本地运行 lint 与测试 | ruff、pytest、覆盖率门槛 | 3 |
| 2 | 质量门禁：lint、测试、镜像冒烟、仓库安全扫描 | GitHub Actions、可复用工作流、Trivy | 3、7 |
| 3 | 合成测试门禁：在临时集群中部署候选版本，模拟用户操作 | Kind、Helm、k6 | 11 |
| 4 | 构建并扫描镜像，推送，生成 SBOM、来源证明，签名 | Trivy、Syft、SLSA、Cosign | 7 |
| 5 | 以消费者身份验证签名与来源 | cosign verify、gh attestation verify | 7 |
| 6 | 合并请求修改 dev 的部署状态，Argo CD 同步 | GitOps、Argo CD | 6 |
| 7 | 准入控制验证镜像来源 | Kyverno | 7 |
| 8 | dev 金丝雀与端到端验证 | Argo Rollouts、OpenTelemetry | 8、9 |
| 9 | 合并请求修改 prod，金丝雀 20%，后台分析 | Argo Rollouts、Prometheus | 8 |
| 10 | 人工闸门，晋级到 100% | Rollouts promote、审批 | 8 |
| 11 | 持续观测：指标、链路、日志、SLO 燃烧率 | Prometheus、Tempo、Loki | 9、12 |
| 12 | 出现问题：自动中止或 Git 回滚，事后写 RCA | git revert、无责复盘 | 6、12 |

## 各章内容与验收状态 {#ov-status}

| 章 | 阶段 | 路线图模块 | 主题 | 状态 |
|---|---|---|---|---|
| 2 | P0 | — | 实验环境：WSL2、Docker、Kind | VALIDATED |
| 3 | P1 | D1 | GitHub Actions 质量门禁 | VALIDATED（官方 Skills 练习未执行） |
| 4 | P2 | D2 | GitLab CI/CD | VALIDATED |
| 5 | P3 | D3 | Kubernetes 基础与 Helm | VALIDATED |
| 6 | P4 | D4 | GitOps 与 Argo CD | VALIDATED |
| 7 | P5 | D5 | 软件供应链安全 | VALIDATED |
| 8 | P6 | D6 | 渐进式交付 | VALIDATED（含勘误；生产审批等待所有者批准） |
| 9 | P7 | D7 / O1 | 开放可观测性 | VALIDATED |
| 10 | P8 | D8 / O2 | Datadog 学习路径与实验 | PARTIAL（网页登录部分、问卷、认证需本人完成） |
| 11 | P9 | D9 | 发布前合成测试门禁 | VALIDATED（Datadog Synthetic 方案未执行） |
| 12 | P10 | O3 | 交付闭环演练与事故复盘 | VALIDATED |
| 13 | P11 | D10 | Ansible 配置管理（选修） | VALIDATED |

状态的含义见前言。每章的实验记录在 `docs/experiments/` 中，汇总在 `docs/STATUS.md`。

## 知识地图与学习路径 {#ov-map}

```{.mermaid caption="全书结构：五个部分依次展开，每部分内部按箭头顺序阅读"}
flowchart LR
  subgraph P1["基础"]
    direction TB
    C2["2 实验环境"]
  end
  subgraph P2["持续集成"]
    direction TB
    C3["3 GitHub Actions"] --> C4["4 GitLab CI"]
  end
  subgraph P3["持续交付"]
    direction TB
    C5["5 Kubernetes<br/>与 Helm"] --> C6["6 GitOps"] --> C7["7 供应链安全"] --> C8["8 渐进式交付"]
  end
  subgraph P4["可观测性与可靠性"]
    direction TB
    C9["9 可观测性"] --> C10["10 Datadog"]
    C9 --> C11["11 合成测试门禁"] --> C12["12 闭环与 RCA"]
  end
  subgraph P5["选修"]
    direction TB
    C13["13 Ansible"]
  end
  P1 --> P2 --> P3 --> P4
  P1 --> P5
```

各章更细的前置关系：第 6 章的配置仓库建在第 4 章的 GitLab 上；第 7 章的签名与晋级用到第 6 章的 GitOps 流程；第 11 章复用第 5 章的 Chart 和第 7 章的发布流水线；第 12 章需要第 8、9、11 章全部就绪。

几条推荐的学习路径：

| 路径 | 章节 | 适合 |
|---|---|---|
| 完整路线 | 2 → 13 顺序阅读并动手 | 想系统掌握全部内容 |
| 交付主线 | 2、3、5、6、8、12 | 先打通“提交 → 生产”的主干 |
| 安全方向 | 2、3、7、11，再读第 12 章“CI 在阶段分支上的第一次运行”一节 | 关注 DevSecOps 与供应链安全 |
| SRE 方向 | 2、5、8、9、10、12 | 关注发布稳定性、可观测性与事故处理 |
| 只读原理 | 各章“原理”与“小结”，以及第 12 章 | 先建立概念，暂不动手 |

有几条线索会在多章之间反复出现，跟着它们读能把知识串起来：

- **期望状态与调和**：Kubernetes 控制器（第 5 章）→ Argo CD（第 6 章）→ Argo Rollouts（第 8 章）→ Ansible（第 13 章）。
- **Pod 模板哈希**：`checksum/config`（第 5 章）→ 金丝雀与稳定版的区分（第 8 章）→ Chart 0.3.1 的修复（第 9 章）→ 只改配置的修订（第 12 章）。
- **按 digest 而不是按名字信任制品**：基础镜像固定 digest（第 3 章）→ 签名与晋级（第 7 章）→ 同一提交、不同 digest（第 11 章）。
- **门禁只在被触发时有效**：触发条件（第 3 章）→ 叠加分支漏掉的扫描（第 7、12 章）→ 只改配置的变更绕过合成测试（第 11、12 章）。
- **自动化的结论要用独立信号核实**：Jaeger 的 lookback 参数（第 9 章）→ Rollout 显示 Healthy 但有一个 Pod 被污染（第 8、9 章）→ 冒烟测试打到旧容器（第 12 章）。
- **从现象到机制**：金丝雀收不到流量（第 8 章）← Service 只在连接建立时选择后端（第 5 章“深入”）；同一提交得到两个 digest（第 11 章）← digest 是清单的哈希、层里记录了时间（第 7 章“深入”）；日志里有 trace ID 却找不到链路（第 9 章练习）← 采样决定随 traceparent 传递（第 9 章“深入”）。

## 被交付的参考服务 {#ov-app}

全书交付的对象是 demo-api：一个刻意做得很小的订单服务（FastAPI），专门为演示设计。它有业务接口（下单、查订单）、健康检查、Prometheus 指标、JSON 日志、OpenTelemetry 链路，以及通过环境变量开启的故障注入（`FAULT_ERROR_RATE`、`FAULT_LATENCY_MS`），后者让本书的每一次故障演练都可以精确复现。第 3 章详细介绍它的代码与设计。

## 实验环境拓扑 {#ov-topology}

| 组件 | 位置 | 访问方式 |
|---|---|---|
| GitLab CE 19.5.3 | Docker 容器 `gitlab` | `http://localhost:8929` |
| 本地镜像仓库 | Docker 容器 `kind-registry` | `localhost:5001` |
| Kind 集群 `lab`（1 控制面 + 2 工作节点） | Docker 容器 `lab-*` | kubeconfig 上下文 `kind-lab` |
| Argo CD v3.6.1 | 命名空间 `argocd` | `kubectl -n argocd port-forward svc/argocd-server 8443:443` |
| Argo Rollouts v1.10.2 | 命名空间 `argo-rollouts` | `kubectl argo rollouts dashboard --port 3100` |
| kube-prometheus-stack 92.21.1 | 命名空间 `monitoring` | Prometheus 9090、Grafana 3000（port-forward） |
| OTel Collector + grafana/otel-lgtm 0.39.0 | 命名空间 `observability` | LGTM 的 Grafana 3001（port-forward） |
| Kyverno 3.9.2 | 命名空间 `kyverno` | — |
| k6 负载生成器 | 命名空间 `loadgen` | prod 每秒 10 个请求，dev 每秒 4 个 |
| demo-api | 命名空间 `dev`（1 副本）、`prod`（5 副本） | Service `demo-api-dev`、`demo-api-prod` |
| 第 4 章部署的容器 | Docker 容器 `demo-api-dev`、`demo-api-prod` | `127.0.0.1:18081`、`127.0.0.1:18082` |

## 从零复现 {#ov-reproduce}

按下面的顺序执行，可以在一台新机器上重建整套实验。每一步的细节和输出都在对应章节中。

1. **实验环境（第 2 章）**：在 PowerShell 中运行 `automation/lab/wsl-create.ps1`，在发行版中以 root 运行 `automation/lab/bootstrap-root.sh`，然后重启发行版。实验期间保持一个后台 `wsl.exe -d devops-lab -- sleep infinity`。
2. **集群与镜像仓库（第 5 章）**：`bash delivery/kind/create-lab-cluster.sh`。
3. **GitLab（第 4 章）**：`bash automation/gitlab/gitlab-up.sh`，把代码推送到本地 GitLab，体验 MR 流水线。
4. **GitHub 一侧（第 3、7、8 章）**：fork 仓库并启用 Actions；按 `evidence/p1/ruleset-protect-main.json` 创建规则集；发布流水线推送镜像到 GHCR 后，把包设为公开（或为集群配置拉取凭据）；为生产审批创建 `production` 环境。
5. **GitOps（第 6 章）**：`bash delivery/argocd/seed-gitops-repo.sh`、`bash delivery/argocd/install-argocd.sh`，再 `kubectl apply -f delivery/gitops/apps/`。
6. **准入控制（第 7 章）**：`helm upgrade --install kyverno kyverno/kyverno --version 3.9.2 -n kyverno --create-namespace --wait`，然后应用 `delivery/policies/verify-release-signature.yaml`。
7. **渐进式交付（第 8 章）**：`bash delivery/monitoring/install-monitoring.sh`、`bash delivery/rollouts/install-rollouts.sh`、`kubectl apply -f delivery/loadgen/k6-loadgen.yaml`，再用 `update-chart.sh` 和 `promote.sh` 应用 `delivery/gitops/patches/` 中的补丁。
8. **可观测性（第 9 章）**：`bash observability/install-observability.sh`。
9. **SLO 规则（第 12 章）**：`kubectl apply -f observability/alerts/demo-api-slo.yaml`。
10. **合成测试门禁（第 11 章）**：本地运行 `bash synthetic/run-gate.sh`，CI 中由发布流水线自动运行。
11. **Ansible（第 13 章）**：按第 13 章准备控制节点并运行 `ansible/site.yml`。

::: warning
**fork 之后要改的地方。** 仓库中有几处写死了原仓库的身份 `miku-wwl/devops-delivery`：Kyverno 策略中的签名者正则、各章的 `cosign verify`/`gh attestation verify` 命令、GHCR 镜像路径，以及 GitOps 中环境的镜像地址。不改的话，你自己构建的镜像会被准入策略拒绝。
:::

## 需要你本人完成的事项 {#ov-todo}

以下事项按规则必须由仓库所有者本人完成，自动化执行时没有代办：

1. 审阅并合并 PR #1–#3 以及之后各阶段叠加的分支（`p4/…` 至 `p12/…`）；合并后把 `security` 检查加入规则集的必需检查。
2. 在 GitHub 上批准（或拒绝）等待中的生产审批运行 42142945642（第 8 章）。
3. 在 GitGuardian 中把第 4 章的误报事件标记为误报。
4. 完成 GitHub Skills 的 Hello GitHub Actions 练习（第 3 章）。
5. Datadog：登录实验用的试用账号，完成两个 Agent 实验的网页部分，填写各课问卷；是否参加认证考试由你决定（第 10 章）。

## 本章小结

- 本书围绕三个问题展开：怎样交付得又快又稳、交付的东西是否可信、出了问题如何快速发现与恢复。
- 最终的系统由代码线、部署线和反馈线组成，一个变更要经过十几道关卡才能到达生产，每道关卡防的是不同的问题。
- 各章之间有清晰的依赖关系；按知识地图选择学习路径，并留意几条贯穿全书的线索。
- 整套实验可以按“从零复现”一节的顺序在新机器上重建。
