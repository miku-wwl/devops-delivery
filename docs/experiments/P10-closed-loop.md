# 实验记录：P10 / O3 交付闭环综合演练与 RCA

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（UTC） |
| 路线图模块 | O3 交付闭环：Commit → CI → Scan → Sign → GitOps → Canary → 观测 → 晋级/中止 → RCA |
| 官方来源 | [Google SRE Workbook: Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)、[Google SRE Workbook: Postmortem Culture](https://sre.google/workbook/postmortem-culture/)、[Prometheus: Recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/)、[Prometheus: Histograms and summaries](https://prometheus.io/docs/practices/histograms/)、[Argo Rollouts: Analysis](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/) |
| 软件版本 | 同 P5–P9（kube-prometheus-stack 92.21.1、Argo CD v3.6.1、Argo Rollouts v1.10.2、Chart demo-api 0.3.1、grafana/otel-lgtm 0.39.0、Trivy 0.76.2、Cosign v3.1.4） |
| 环境 | Kind 集群 `lab`（dev/prod、监控、遥测）；本地 GitLab 配置仓库；GitHub Actions |
| 状态 | **VALIDATED** |

## 步骤与结果

### A. SLO 规则

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 应用 PrometheusRule `demo-api-slo`（记录规则 11 条、燃烧率告警 4 条） | 规则组加载；无 5xx 的环境中错误比例为“无数据” | [slo-rules.log](../../evidence/p10/slo-rules.log) |
| 2 | 改为 `(5xx or 0 * 全部) / 全部` | 应用后第 75 秒仍是旧结果（规则传播延迟）；约 95 秒后全部正常 | [slo-rules-2.log](../../evidence/p10/slo-rules-2.log)、[slo-baseline.log](../../evidence/p10/slo-baseline.log) |
| 3 | 基线 | 所有燃烧率为 0；prod 6h 慢请求比例 1.03%（P7 事故的尾部，计算吻合） | [slo-baseline.log](../../evidence/p10/slo-baseline.log) |

### B. 演练 A：好版本走完整条链

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 4 | 功能 X-Request-ID（`85b3a49`），本地 ruff + pytest | 34 passed，覆盖率 93.87% | [app-tests.log](../../evidence/p10/app-tests.log) |
| 5 | 发布流水线（推送触发，42198984873） | 门禁 PASS（723 个请求，p95 ≤ 2.1 ms）；Trivy、推送、SBOM、来源证明、签名、自检全部成功；`sha256:4bb4aac3…` | [release-run.log](../../evidence/p10/release-run.log) |
| 6 | `ci.yml`（手动触发，42198994779） | **失败**：security 作业发现 7 个 HIGH 配置问题（k6、准入测试 Pod、LGTM），来自 P5–P7，从未被扫描 | [ci-run-1-security-fail.log](../../evidence/p10/ci-run-1-security-fail.log) |
| 7 | 加固 LGTM，在 restricted 临时命名空间测试 | 第 1 次：Tempo 未就绪（`mkdir /var/tempo: read-only file system`）；加 emptyDir 后第 2 次 6 个组件全部启动 | [lgtm-hardening-test-1.log](../../evidence/p10/lgtm-hardening-test-1.log)、[-2.log](../../evidence/p10/lgtm-hardening-test-2.log) |
| 8 | 本地复查（CI 同款命令） | 第 1 次在 drvfs 工作区上超时（5 分钟）；扫描 `git ls-files` 副本：干净 | [trivy-repo-scan-1-timeout.log](../../evidence/p10/trivy-repo-scan-1-timeout.log)、[trivy-repo-scan-2.log](../../evidence/p10/trivy-repo-scan-2.log) |
| 9 | 应用到实验集群并验证；准入测试复测 | LGTM uid 10001、只读根文件系统；负载与遥测正常；签名镜像允许、未签名拒绝 | [hardening-apply.log](../../evidence/p10/hardening-apply.log)、[hardening-verify.log](../../evidence/p10/hardening-verify.log)、[admission-retest.log](../../evidence/p10/admission-retest.log) |
| 10 | 提交 `5b3e829`，CI 重跑（42201262422） | 4 个作业全部成功 | [ci-run-2-pass.log](../../evidence/p10/ci-run-2-pass.log) |
| 11 | 消费者验证 | cosign verify 通过；来源证明指向提交 `85b3a49`、运行 42198984873；SBOM 124 个包 | [verify-cosign.log](../../evidence/p10/verify-cosign.log)、[verify-attestation.log](../../evidence/p10/verify-attestation.log) |
| 12 | dev 晋级（MR !20 → `e9472b2`） | 59 秒 Synced + Healthy | [chain-1-dev.log](../../evidence/p10/chain-1-dev.log) |
| 13 | dev 冒烟测试 | 第 1 次**失败**：127.0.0.1:18081 被 P2 的 Docker 容器占用，port-forward 只绑定了 [::1]；换端口后请求 ID 原样返回、不安全的 ID 被替换 | [chain-1-dev.log](../../evidence/p10/chain-1-dev.log)、[chain-2-dev-smoke.log](../../evidence/p10/chain-2-dev-smoke.log) |
| 14 | 关联验证 | 同一请求 ID → stdout 日志 → Loki → Tempo，trace `95c27aad…`，服务端 span 带 `request.id` | [chain-3-dev-correlation.log](../../evidence/p10/chain-3-dev-correlation.log) |
| 15 | prod 金丝雀（MR !21 → `f49539c`） | 停在人工闸门；分析 5/5 成功（p95 4.75 ms） | [chain-4-prod-canary.log](../../evidence/p10/chain-4-prod-canary.log)、[rollouts-prod-paused.png](../../evidence/p10/rollouts-prod-paused.png) |
| 16 | 人工晋级 | 120 秒后 Healthy；分析 12/12 成功 | [chain-5-prod-promote.log](../../evidence/p10/chain-5-prod-promote.log) |

### C. 演练 B：坏配置

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 17 | `faults.latencyMs:=800`（MR !22 → `10a6786`） | 13:37:14 金丝雀 revision 9；13:38:06、13:38:26 两次 p95 ≈ 0.96 s → 13:38:26 自动中止；Argo CD Synced + Degraded | [drill-1-bad-config.log](../../evidence/p10/drill-1-bad-config.log)、[rollouts-prod-aborted.png](../../evidence/p10/rollouts-prod-aborted.png) |
| 18 | 稳定版是否被污染 | 中止时新建的 `nl8wl` 为 FAULT_LATENCY_MS=0；中止后 4 分钟稳定版慢请求 0；金丝雀约 138 个请求、约 91 个慢请求；5xx 0 | [drill-2-blast-radius.log](../../evidence/p10/drill-2-blast-radius.log) |
| 19 | `git revert`（MR !23 → `39ee3f2`） | 13:45:27 Synced + Healthy，未重启 Pod | [drill-3-revert.log](../../evidence/p10/drill-3-revert.log) |
| 20 | SLO 与告警 | 燃烧率峰值 5m 3.121 / 1h 0.245（未达 14.4）；`DemoApiHighLatency` 13:39:00 firing（中止后 34 秒）；预算消耗 0.034%（P7 事故 5.87%） | [drill-4-slo.log](../../evidence/p10/drill-4-slo.log)、[prometheus-burn-rate.png](../../evidence/p10/prometheus-burn-rate.png)、[prometheus-traffic-by-rs.png](../../evidence/p10/prometheus-traffic-by-rs.png) |
| 21 | RCA | 两份：P7 的真实事故与本次演练 | [INC-20261106-01](../rca/INC-20261106-01-prod-latency-poisoned-stable-pod.md)、[INC-20261106-02](../rca/INC-20261106-02-p10-bad-config-drill.md) |

验收标准“延迟故障版本被中止并回滚；输出测试环境 Incident RCA”由步骤 17–21 满足。

## 失败与排查

1. **CI 的 security 作业失败**：见步骤 6–10。根因是触发条件（`ci.yml` 只覆盖 main），修复是真正加固而不是添加例外。
2. **LGTM 第一次加固失败**：Tempo 3 写 `/var/tempo`，只读根文件系统使其显式失败；加 emptyDir 解决。
3. **本地 Trivy 超时**：drvfs 工作区中有大量未跟踪目录；改为扫描受版本控制的文件副本。
4. **冒烟测试打到旧容器**：端口被 P2 的 Docker 容器占用，port-forward 部分绑定成功而未退出。
5. **两个误判陷阱**：`kubectl logs -l` 默认每个 Pod 只输出 10 行；Tempo 搜索对刚结束的链路有延迟。
6. **webshot 访问 Prometheus 超时**：Prometheus 页面持续轮询，永远达不到 `networkidle`；为 `webshot.py` 增加 `--wait-until load`。

## 局限

- 演练 A 的总耗时含约 3 小时 7 分钟的会话中断，不代表流程本身的耗时。
- prod 的人工晋级用本地 `kubectl argo rollouts promote` 完成；GitHub Environments 的生产审批（P6）仍在等待仓库所有者批准。
- 配置仓库的策略检查（禁止 prod 出现故障注入参数）只作为行动项和练习提出，未实现。

## 清理

演练没有留下额外资源：临时命名空间 `lgtm-hardening-test*`、`lgtm-debug` 已删除；prod 回到 revision 8（`4bb4aac3…`），Git 与集群一致。
