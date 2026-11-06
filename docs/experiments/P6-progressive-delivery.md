# 实验记录：P6 / D6 渐进式交付

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（证据时间戳为 UTC） |
| 路线图模块 | D6 Progressive Delivery；Gate G4 |
| 官方来源 | [Argo Rollouts Getting Started](https://argo-rollouts.readthedocs.io/en/stable/getting-started/)、[Analysis & Progressive Delivery](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/)、[GitHub Deployment Environments](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments)、[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) |
| 软件版本 | Argo Rollouts v1.10.2；kube-prometheus-stack 92.21.1（operator v0.94.2）；k6 v2.3.0；Chart demo-api 0.2.1 |
| 环境 | Kind 集群 `lab`；配置仓库（本地 GitLab）；GitHub Actions |
| 状态 | **VALIDATED** |

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 安装监控栈与 Argo Rollouts | 全部 Running | [install.log](../../evidence/p6/install.log) |
| 2 | Chart 0.2.0：Rollout / AnalysisTemplate / PodMonitor | lint 通过；两种模式渲染正确 | [chart-lint.log](../../evidence/p6/chart-lint.log) |
| 3 | 经 GitOps 把 dev、prod 从 Deployment 切换为 Rollout | prod 5/5 Healthy；dev 第一次 MR 创建 400（异步竞态），修复为重试后成功 | [enable-rollouts.log](../../evidence/p6/enable-rollouts.log)、[enable-rollouts-dev.log](../../evidence/p6/enable-rollouts-dev.log) |
| 4 | k6 首次启动失败 | `unknown flag: --no-summary`（k6 v2 改为 `--summary-mode=disabled`） | 本记录 |
| 5 | 第一次好版本金丝雀 | **误杀**：values=[]，因 keep-alive 使金丝雀无业务流量；分析只有成功条件 | [canary-good-1.log](../../evidence/p6/canary-good-1.log)、[canary-good-2.log](../../evidence/p6/canary-good-2.log) |
| 6 | 修复：逐请求建连；三态分析（Chart 0.2.1） | 新金丝雀分析为 Inconclusive（未误杀）；发现 k6 未重启 | [canary-fix.log](../../evidence/p6/canary-fix.log)、[canary-good-3.log](../../evidence/p6/canary-good-3.log) |
| 7 | 重启 k6；手动 abort；retry | 金丝雀收到流量；abort → Degraded；retry → 暂停于第 1 步 | [canary-abort-retry.log](../../evidence/p6/canary-abort-retry.log) |
| 8 | 分析通过后人工 promote | 120 s 全量；AnalysisRun Successful（12/12）；5 Pod 全部新 digest | [canary-good-4.log](../../evidence/p6/canary-good-4.log)、[canary-good-promote.log](../../evidence/p6/canary-good-promote.log) |
| 9 | 坏版本（latencyMs 800） | p95 0.966 s ×2 → 自动中止（约 65 s）；121 个请求中 85 个慢，占同期 1.4% | [canary-bad.log](../../evidence/p6/canary-bad.log)、[canary-bad-impact.log](../../evidence/p6/canary-bad-impact.log) |
| 10 | git revert（!14） | Synced/Healthy，126 s | [canary-bad-revert.log](../../evidence/p6/canary-bad-revert.log) |
| 11 | GitHub Environment `production` 审批闸门 | 运行 42142945642 处于 waiting，审阅者 miku-wwl；**批准留给仓库所有者** | [production-gate.log](../../evidence/p6/production-gate.log)、[production-gate-waiting.png](../../evidence/p6/production-gate-waiting.png) |

## 失败与排查（摘要）

1. MR 创建 400：GitLab 分支缓存异步刷新 → `lib.sh` 中对创建操作重试并打印错误体。
2. 好版本被误杀：L4 负载均衡 + keep-alive 使金丝雀无流量；分析把“无数据”当失败 → 逐请求建连、success/failure/inconclusive 三态。
3. Chart 升级触发新金丝雀：Pod 模板标签包含 `helm.sh/chart`（反模式，留待后续 Chart 版本修正）。
4. 改了 ConfigMap 但 k6 未重启 → `rollout restart`。

## 局限性

- 未使用流量路由器，权重按副本比例近似；精确权重需服务网格或 Gateway API。
- 生产审批需要人工点击，本次自动执行未代为批准。
