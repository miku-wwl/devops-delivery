# 实验记录：P9 / D9 可观测性 × CI/CD：发布前合成测试门禁

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（UTC） |
| 路线图模块 | D9 可观测性 × CI/CD；Gate G7（开源部分） |
| 官方来源 | [k6 文档：Thresholds、Checks、Scenarios / constant-arrival-rate、handleSummary](https://grafana.com/docs/k6/latest/)、[kind 文档](https://kind.sigs.k8s.io/)、[GitHub Actions：Reusing workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows)、[Datadog Continuous Testing / datadog-ci](https://docs.datadoghq.com/continuous_testing/) |
| 软件版本 | k6 v2.3.0；kind v0.33.0（节点镜像 `kindest/node:v1.37.0@sha256:a1ed56cf…`）；kubectl v1.37.2；helm v4.3.1；Chart demo-api 0.3.1；actions/upload-artifact v7.0.2（按 SHA 固定）；datadog-ci 5.25.0（仅模板） |
| 环境 | 本地：WSL2 `devops-lab` 中的 Kind 集群 `lab`；CI：GitHub 托管运行器 `ubuntu-24.04` 上每次新建的 Kind 集群 `gate` |
| 状态 | **VALIDATED**（开源实现）；Datadog Synthetic 方案 **NOT_RUN**（没有可用于 CI 的 Datadog 账号） |

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 本地门禁，健康候选版本（GHCR 镜像 `sha256:9f45ec00…`，P7 已签名） | PASS：723 个请求，1446 个 check 全部通过；三个接口 p95 分别为 11.1 / 11.0 / 8.9 ms；错误率 0 | [gate-local-pass.log](../../evidence/p9/gate-local-pass.log) |
| 2 | 本地门禁，`--fault latency`（定价调用 +600 ms） | FAIL：check 1440 个全部通过、错误率 0，但下单接口 p95 610.5 ms > 300 ms；k6 退出码 99；命名空间被清理 | [gate-local-fail.log](../../evidence/p9/gate-local-fail.log)、[gate-local-fail.png](../../evidence/p9/gate-local-fail.png) |
| 3 | 工作流静态检查 | actionlint（Docker 镜像，含 shellcheck）零告警；SC1090 改为用 grep 读取 `versions.env` 解决 | 提交 `70ae35c` |
| 4 | 运行 A：推送 `p9/synthetic-gate` 触发发布流水线（42195568852） | 门禁通过（720 个请求，p95 ≤ 2.2 ms）→ 发布作业构建、扫描、推送、生成 SBOM 与证明：`sha256:27919359…` | [ci-run-pass.log](../../evidence/p9/ci-run-pass.log) |
| 5 | 运行 B：手动触发，`synthetic_fault=latency`（42196278404） | 门禁失败：下单 p95 603.6 ms，k6 退出码 99 → 发布作业 **skipped**，没有推送镜像、没有签名 | [ci-run-blocked.log](../../evidence/p9/ci-run-blocked.log)、[ci-run-blocked.png](../../evidence/p9/ci-run-blocked.png)、[github-run-blocked.png](../../evidence/p9/github-run-blocked.png) |
| 6 | 运行 C：手动触发，`synthetic_fault=none`（42196846132） | 门禁通过（723 个请求，p95 ≤ 2.1 ms，用时 2 分 30 秒）→ 发布作业成功（2 分 19 秒）：`sha256:e17b82f1…` | [ci-run-recovered.log](../../evidence/p9/ci-run-recovered.log)、[ci-run-recovered.png](../../evidence/p9/ci-run-recovered.png)、[github-run-recovered.png](../../evidence/p9/github-run-recovered.png) |
| 7 | Datadog Synthetic 方案 | 编写 `synthetic/datadog/` 模板（`datadog-ci.json`、`demo-api.synthetics.json`、README），**未运行** | `synthetic/datadog/` |

验收标准“合成测试失败时阻断发布，恢复后通过”由步骤 5、6 满足。

## 观察

1. **check 全部通过，阈值仍然失败。** 延迟故障下服务功能完全正确，只有按接口设置的 p95 阈值发现了问题。如果只设置一个全局 p95，下单接口的退化会被另外两个快接口稀释（每次迭代三个请求中只有一个慢）。
2. **CI 中比本地快。** 托管运行器上的 p95 约 1–2 ms，本地实验集群约 9–11 ms。本地集群同时运行着 Argo CD、监控栈、GitLab 和 dev/prod 负载，阈值 300 ms 对两者都留有充足余量。
3. **同一个 commit，两个 digest。** 运行 A 与运行 C 都构建自 `70ae35c`，digest 不同（构建参数含运行编号，镜像中有时间戳）。构建不可复现，制品必须按 digest 追踪。

## 失败与排查

1. **actionlint 参数错误。** 无颜色输出的参数是 `-no-color`，不是 `-color=never`。
2. **shellcheck SC1090**（不能跟踪动态 `source`）。改为 `grep -E '^KIND_NODE_IMAGE=' versions.env | cut -d= -f2- | tr -d '\r'`，同时去掉了 Windows 换行符的影响。
3. **在 WSL 中用 `find /` 寻找 actionlint 二进制导致命令挂起**，已停止；改用官方 Docker 镜像。

## 局限

- 门禁只测试“候选镜像 + Chart 默认值”、60 秒轻负载；只改配置的发布（如 P6 的 `faults.latencyMs: 800`）不会触发这条流水线，需要生产金丝雀（P6）和告警（P7）兜底。
- 门禁放在发布流水线而不是 PR 阶段；把它设为 PR 的必需检查需要仓库所有者修改规则集。

## 清理

每次运行的命名空间 `synthetic-<时间戳>` 由 `run-gate.sh` 的 `trap` 删除；CI 中的 Kind 集群随运行器销毁。运行 A、C 推送的两个镜像保留在 GHCR 中（未部署）。
