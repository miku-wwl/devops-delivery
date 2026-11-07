# 实验记录：P7 / D7 / O1 开放可观测性

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（证据时间戳为 UTC；浏览器截图显示 Windows 本地时区 NZDT，UTC+13） |
| 路线图模块 | D7 / O1 开放可观测性；Gate G5 |
| 官方来源 | [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/)、[OTel for Ops](https://opentelemetry.io/docs/getting-started/ops/)、[OpenTelemetry Collector Helm Chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector)、[grafana/otel-lgtm](https://github.com/grafana/docker-otel-lgtm)、[Prometheus Getting Started](https://prometheus.io/docs/prometheus/latest/getting_started/)、[Grafana Learning Hub](https://grafana.com/docs/learning-hub/) |
| 软件版本 | OpenTelemetry Demo 3.1.0（镜像 `3.1.0-*`；Jaeger 2.19.0、Grafana 13.1.0、Prometheus v3.13.1、otelcol-contrib 0.159.0、flagd v0.16.0）；opentelemetry-sdk 1.45.2、opentelemetry-exporter-otlp-proto-http 1.45.2、opentelemetry-instrumentation-fastapi 0.66b2；Collector Chart 0.178.2（otelcol-contrib 0.163.2）；grafana/otel-lgtm 0.39.0；kube-prometheus-stack 92.21.1；Chart demo-api 0.3.0 → 0.3.1 |
| 环境 | WSL2 `devops-lab` 中的 Docker（OTel Demo）；Kind 集群 `lab`（遥测管道、dev/prod）；配置仓库（本地 GitLab）；GitHub Actions（发布流水线） |
| 状态 | **VALIDATED** |

## 步骤与结果

### A. 官方 OpenTelemetry Demo

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 克隆 3.1.0 标签，审阅镜像与内存预算，固定镜像标签 | 发布版 `.env` 指向可变的 `latest-*`；GHCR 中存在 `3.1.0-*` 发布标签；25 个服务内存上限合计 6819 MiB | [session-extracts.md](../../evidence/p7/session-extracts.md) §1–2、`observability/otel-demo/lab.env` |
| 2 | `docker compose up`（最小模式：core + observability + extras） | 第一次：24 个容器运行，`frontend-proxy` 绑定 10000 端口失败（`compose up exit=1 after 308s`）；10000 被 Windows 进程 YunDetectService 占用 → `ENVOY_ADMIN_PORT=10001` 后 25 个容器运行，首页 HTTP 200 | [otel-demo-up.raw.log](../../evidence/p7/otel-demo-up.raw.log)、[session-extracts.md](../../evidence/p7/session-extracts.md) §2b–3b、[otel-demo-shop.png](../../evidence/p7/otel-demo-shop.png) |
| 3 | 基线 | 17 个服务上报链路；Demo 自己的镜像全部为 `3.1.0-*`（第三方组件按 Demo 发布版固定的版本） | [otel-demo-baseline.log](../../evidence/p7/otel-demo-baseline.log) |
| 4 | 打开 `paymentFailure` = 50%（03:45:01Z） | flagd 日志中未见 reload 字样（grep exit 1），但随后出现失败的支付链路 | [otel-demo-fault-on.log](../../evidence/p7/otel-demo-fault-on.log)、[otel-demo-flagd-ui.png](../../evidence/p7/otel-demo-flagd-ui.png) |
| 5 | 三种信号定位 | 链路：错误源头 `PaymentService/Charge`（“Payment request failed. Invalid token”）；spanmetrics：payment/checkout/frontend 各 7 个错误 span；OpenSearch：该 trace 37 条日志 | [otel-demo-fault-traces.log](../../evidence/p7/otel-demo-fault-traces.log)、[otel-demo-fault-logs.log](../../evidence/p7/otel-demo-fault-logs.log)、Jaeger/Grafana 截图 |
| 6 | 关闭开关（03:50:23Z）并验证恢复 | API 统计“最近 2 分钟”仍有 9 条失败链路 → flagd 实际返回 `off`；按 span 开始时间统计：关闭前 44 个 Charge 中 16 个失败，关闭后 20 个中 0 个失败；payment 日志最后一次失败 03:49:39Z | [otel-demo-fault-off.log](../../evidence/p7/otel-demo-fault-off.log)、[otel-demo-recovery.log](../../evidence/p7/otel-demo-recovery.log)、[session-extracts.md](../../evidence/p7/session-extracts.md) §4 |
| 7 | 查明误导原因 | Jaeger v2.19.0 链路搜索 API 只解析 `start`/`end`，忽略 `lookback`，缺省回溯 48 小时 | [jaeger-api-lookback.log](../../evidence/p7/jaeger-api-lookback.log) |
| 8 | 清理 | 移除 26 个容器；GitLab 重新启动并 healthy | [otel-demo-teardown.log](../../evidence/p7/otel-demo-teardown.log) |

### B. demo-api 埋点与遥测管道

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 9 | 埋点（链路 + 日志）与测试 | ruff 通过；25 passed；覆盖率 93.52%（门槛 90%） | [app-tests.log](../../evidence/p7/app-tests.log) |
| 10 | 发布流水线 | 运行 42157662801（`0e551ad`）成功：构建、扫描、签名、证明 → `sha256:9f45ec00…` | GitHub Actions |
| 11 | 安装 LGTM、Collector、告警规则 | 全部 Running；Collector 04:00:15Z “Everything is ready”；PrometheusRule 创建 | [install-pipeline.log](../../evidence/p7/install-pipeline.log) |
| 12 | Chart 0.3.0（MR !15）+ dev 开启 OTel（MR !16） | 第一次推送遇到本地 GitLab 的瞬时 403（exit 128），重试成功；dev 运行新 digest，OTel 环境变量就位 | [dev-otel-rollout.log](../../evidence/p7/dev-otel-rollout.log)、[dev-otel-rollout-2.log](../../evidence/p7/dev-otel-rollout-2.log) |
| 13 | 验证三种信号到达后端 | Tempo 中有 dev 链路；Loki 中带 trace_id 的日志 ≥ 200 条（查询 limit=200）；Collector 抓取的指标：prod 10.5 req/s、dev 4 req/s | [pipeline-verify.log](../../evidence/p7/pipeline-verify.log) |

### C. 故障演练（Gate G5）

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 14 | 注入：MR !17 `fa135cf`（dev 20% 错误 + 600 ms） | 04:05:37Z 合并；dev 延迟告警 04:06:50Z 成立并 firing；错误率告警 04:07:20Z pending（16.78%） | [drill-inject.log](../../evidence/p7/drill-inject.log)、[drill-prometheus-alerts.png](../../evidence/p7/drill-prometheus-alerts.png) |
| 15 | 排查：指标 → 链路 → 日志 | 错误率 15%、p95 956 ms；TraceQL：`pricing.calculate` 约 605 ms 的慢链路、带 `fault.injected` 事件的失败链路 `44d56659…`；Loki：同一 trace 的 “injected fault: failing request” | [drill-investigate.log](../../evidence/p7/drill-investigate.log)、drill-*.png |
| 16 | 恢复：MR !18 `9d2430c`（revert） | dev 告警 04:13:27Z 清零，p95 4 ms | [drill-recover.log](../../evidence/p7/drill-recover.log) |

### D. 意外发现：prod 稳定版 Pod 被污染（真实问题）

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 17 | 告警 | prod `DemoApiHighLatency` 04:01:05Z 成立（836 ms），早于 MR !15 合并；规则在 04:00:15Z 之后才创建 | [drill-inject.log](../../evidence/p7/drill-inject.log)、[install-pipeline.log](../../evidence/p7/install-pipeline.log) |
| 18 | 排查 | Rollout 停在 0.3.0 金丝雀第 1 步；ConfigMap 为 0；按 ReplicaSet：stable 852 ms、canary 4 ms；按接口：只有下单慢 | [prod-latency-investigate.log](../../evidence/p7/prod-latency-investigate.log) |
| 19 | 根因 | 5 个 Pod 中只有 `6bdb67694c-pw772`（01:14:11Z 启动，P6 坏金丝雀中止后扩容所建）`FAULT_LATENCY_MS=800` | [prod-latency-rootcause.log](../../evidence/p7/prod-latency-rootcause.log)、[prod-latency-rootcause.png](../../evidence/p7/prod-latency-rootcause.png) |
| 20 | 影响与缓解 | 该 Pod 处理 15662 个下单请求，全部 > 0.5 s；4 小时窗口内 prod 下单请求共 86680（18%）；删除 Pod 后 4 个稳定版 Pod 均为 0 | [prod-latency-impact.log](../../evidence/p7/prod-latency-impact.log) |
| 21 | 永久修复：Chart 0.3.1（MR !19 `c4724f5`） | 渲染：`envFrom` 为 null，`FAULT_*` 写在 `env`；替代金丝雀 `745d56f9d4` 的 `FAULT_LATENCY_MS=0`、无 `envFrom` | [chart-fix.log](../../evidence/p7/chart-fix.log)、[chart-fix-2.log](../../evidence/p7/chart-fix-2.log) |
| 22 | 分析与晋级 | success-rate 3/3、p95 3/3（0.00475 s）；人工 promote 后 114 s Healthy；04:20:05Z 所有 DemoApi 告警清零；prod、dev p95 均为 4 ms | [chart-fix-promote.log](../../evidence/p7/chart-fix-promote.log) |

## 失败与排查（摘要）

1. **未经审阅的启动脚本被权限策略拒绝**（克隆 + `make start-minimal` + 停止其他服务的组合命令）→ 改为只克隆、用 `docker compose config --images` 审阅镜像，再用固定版本的 `docker compose` 直接启动。
2. **可变镜像标签**：发布版 `.env` 为 `DEMO_VERSION=latest` → `lab.env` 固定为 3.1.0。
3. **端口 10000 冲突**：Windows 进程 YunDetectService 监听 `127.0.0.1:10000`，WSL 镜像网络模式共享端口 → `ENVOY_ADMIN_PORT=10001`。
4. **第一次后台启动失败**：重定向目标目录 `evidence/p7` 尚不存在 → 先创建目录再重新启动。
5. **span 中 `service.version` 为 3.0.0**：`.env` 中 `OTEL_RESOURCE_ATTRIBUTES` 在读取覆盖文件前已用 `IMAGE_VERSION=3.0.0` 展开；不影响演练，未修改官方文件，仅记录。
6. **恢复统计被误导**：Jaeger API 忽略 `lookback`（缺省回溯 48 h），“最近 2 分钟 9 条失败链路”实为启动以来的全部 → 按 span 开始时间与 flagd 实际取值核对；以源码为证。
7. **本地 GitLab 瞬时 403**（`git fetch` 时 `RPC failed; HTTP 403`）→ 重试成功。
8. **yq 表达式写错**（`lexer: invalid input text`，exit 1）→ 改写表达式后验证渲染结果（chart-fix-2.log）。
9. **真实问题**：共享 ConfigMap 使中止的金丝雀把坏配置泄漏给新建的稳定版 Pod（P6 遗留，约 3 小时）→ 缓解、Chart 0.3.1 修复、金丝雀验证；P6 记录与手册第 8 章已加勘误，RCA 在 P10 中完成。

## 局限性

- `grafana/otel-lgtm` 是面向开发与学习的一体化镜像（emptyDir，无持久化、无高可用），不适合生产。
- 只有 dev 开启了链路与日志导出（`otel.enabled`）；prod 只由 Collector 抓取指标。
- 链路未配置采样（全量）；告警未接入通知渠道（Alertmanager 使用 Chart 默认配置，没有配置任何接收器）。
- OTel Demo 已拆除，第 6 步的 API 统计无法用修正后的参数（`start`/`end`）重跑；结论依据 span 时间统计与 Jaeger 源码。
- O0 视频（Abhishek Veeramalla）由用户自学，本记录不转述其内容。

## 清理

- OpenTelemetry Demo：`docker compose down --remove-orphans`（26 个容器）；克隆目录 `~/work/opentelemetry-demo` 暂留，P12 统一清理。
- 遥测管道（`observability` 命名空间）与告警规则继续运行，供 P9/P10 使用。
