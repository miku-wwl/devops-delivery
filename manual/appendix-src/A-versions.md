## 工具与组件版本 {-}

命令行工具的版本以 `automation/lab/versions.env` 为唯一来源，安装时校验 SHA256（第 2 章）；集群组件按 Helm Chart 或清单的版本号固定。

::: {.tbl-versions}
| 类别 | 组件 | 版本 | 章节 |
|---|---|---|---|
| 宿主环境 | Windows 11 家庭中文版、WSL | WSL 2.7.3.0，内核 6.6.114.1 | 2 |
| | 发行版 `devops-lab` | Ubuntu 24.04 LTS | 2 |
| | Docker Engine / Compose | 29.9.3 / v5.7.0 | 2 |
| 命令行工具 | kubectl | v1.37.2 | 2 |
| | kind / 节点镜像 | v0.33.0 / `kindest/node:v1.37.0@sha256:a1ed56cf…` | 2、5 |
| | Helm | v4.3.1 | 5 |
| | argocd CLI | v3.6.1 | 6 |
| | kubectl-argo-rollouts | v1.10.2 | 8 |
| | Trivy | 0.76.2 | 7 |
| | Syft（实验环境） | 1.57.0 | 7 |
| | Cosign | v3.1.4 | 7 |
| | k6 | v2.3.0 | 8、11 |
| | yq | v4.54.1 | 6 |
| CI/CD | GitLab CE / GitLab Runner | 19.5.3 / 19.5.2 | 4 |
| | GitHub Actions 中的 Action | 全部按 commit SHA 固定（见各工作流文件） | 3、7、11 |
| 集群组件 | Argo CD | v3.6.1 | 6 |
| | Argo Rollouts | v1.10.2 | 8 |
| | kube-prometheus-stack（Operator） | 92.21.1（v0.94.2） | 8 |
| | Kyverno（应用版本） | Chart 3.9.2（v1.19.2） | 7 |
| | OpenTelemetry Collector | Chart 0.178.2（otelcol-contrib 0.163.2） | 9 |
| | grafana/otel-lgtm | 0.39.0（Grafana 13.3.0、Tempo 3.1.1、Loki 3.7.9、Prometheus 3.15.1） | 9 |
| | OpenTelemetry Demo | 3.1.0 | 9 |
| 应用 | demo-api：Python / ruff / pytest | 3.13（CI）、3.12（本地） / 0.17.4 / 9.2.0 | 3 |
| | demo-api Helm Chart | 0.3.1 | 5、9 |
| 配置管理 | ansible-core / community.docker | 2.20.11 / 5.4.0 | 13 |
:::

## 常用命令速查 {-}

::: {.tbl-commands}
| 场景 | 命令 | 章节 |
|---|---|---|
| 录制终端证据 | `bash automation/evidence/transcript.sh evidence/pN/x.log "标题" <<'EOF' … EOF` | 2 |
| 查看 PR 检查与合并状态 | `gh pr checks <号>`；`gh pr view <号> --json mergeStateStatus` | 3 |
| 查看运行与日志 | `gh run list --branch <分支>`；`gh run view <ID> --log-failed` | 3 |
| 静态检查工作流 | `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12` | 3 |
| 渲染并比较 Chart | `helm template <名称> <chart> -f values-prod.yaml`，再 `diff -u` | 5 |
| 查看发布历史与回滚 | `helm history <release>`；`helm rollback <release> <修订>` | 5 |
| GitOps 发布 / 回滚 | `bash delivery/argocd/promote.sh <env> <键=值>… --merge`；`bash delivery/argocd/revert.sh <提交> --merge` | 6 |
| 等待同步 | `bash delivery/argocd/wait-sync.sh <app> "" <超时秒数>` | 6 |
| 查看差异 / 立即刷新 | `argocd app diff <app> --grpc-web`；`argocd app get <app> --refresh --grpc-web` | 6 |
| 扫描仓库 / 镜像 | `trivy fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 .`；`trivy image …` | 7 |
| 验证签名 | `cosign verify <镜像@digest> --certificate-identity-regexp '…' --certificate-oidc-issuer https://token.actions.githubusercontent.com` | 7 |
| 验证来源证明 | `gh attestation verify oci://<镜像@digest> --repo <owner/repo>` | 7 |
| 观察金丝雀 | `kubectl argo rollouts get rollout <名称> -n <ns>`；`bash delivery/rollouts/watch-rollout.sh <ns> <名称> <状态> <超时>` | 8 |
| 人工晋级 / 中止 / 重试 | `kubectl argo rollouts promote <名称> -n <ns>`，`abort`、`retry rollout` 同理 | 8 |
| 查看分析结果 | `kubectl -n <ns> get analysisrun <名称> -o json`（见第 8、12 章的 jq 写法） | 8 |
| 按 ReplicaSet 拆分请求 | `sum by (rollouts_pod_template_hash) (rate(http_requests_total{namespace="prod"}[1m]))` | 8、12 |
| 检查 Pod 实际配置 | `kubectl get pods -o custom-columns=POD:.metadata.name,LAT:'.spec.containers[0].env[?(@.name=="FAULT_LATENCY_MS")].value'` | 9、12 |
| 链路与日志查询 | TraceQL：`{span.request.id="…"}`；LogQL：`{service_name="demo-api"} \| trace_id="…"` | 9、12 |
| 燃烧率与告警 | `demo_api:slo_latency:burn_rate5m{namespace="prod"}`；`ALERTS{alertname=~"DemoApi.*"}` | 12 |
| 找到容器主进程并查看内核限制 | `docker exec <节点> crictl inspect <容器ID> \| jq .info.pid`，再看 `/proc/<pid>/status`、`/proc/<pid>/cgroup` | 5 |
| 查看 Service 的 NAT 规则与连接跟踪 | `docker exec <节点> iptables-save -t nat \| grep <ClusterIP>`；`docker exec <节点> conntrack -L -p tcp --orig-dst <ClusterIP>` | 5 |
| 观察准入的效果（不写入） | `kubectl apply --dry-run=server -o yaml -f <文件>` | 5 |
| 读取镜像清单并核对 digest | 匿名令牌 `https://ghcr.io/token?scope=repository:<仓库>:pull`，再 `curl …/v2/<仓库>/manifests/<digest> \| sha256sum` | 7 |
| 带链路上下文发请求 | `curl -H "traceparent: 00-<32 位 trace ID>-<16 位 span ID>-01" …` | 9 |
| 从配置仓库统计部署与回滚 | `git log --first-parent --format='%h %cI %s' <基线>..origin/main -- envs/prod charts` | 12 |
| 本地合成测试门禁 | `bash synthetic/run-gate.sh --image <仓库> --digest <sha256:…> [--fault latency]` | 11 |
| Ansible 演练 | `ansible-playbook site.yml --check --diff`，再 `ansible-playbook site.yml` | 13 |
:::

## 仓库结构 {-}

```text
devops-delivery/
├── app/                    demo-api：源码、测试、Dockerfile（第 3 章）
├── .github/workflows/      ci、reusable-python-ci、release、synthetic-gate、production-gate
├── .gitlab-ci.yml          GitLab 流水线（第 4 章）
├── automation/             实验环境、GitLab、CI 工具安装、证据录制脚本
├── delivery/               kind、helm、gitops、argocd、rollouts、monitoring、policies、loadgen、release
├── observability/          OTel Collector、LGTM、告警与 SLO 规则、OTel Demo 覆盖文件
├── synthetic/              k6 用户旅程、门禁脚本、Datadog Synthetic 模板（未运行）
├── ansible/                Inventory、playbook、baseline 角色（第 13 章）
├── docs/                   路线图、阶段计划、STATUS、实验记录、RCA、验收报告
├── evidence/p0 … p11/      终端记录与截图
└── manual/                 本书的章节源文件、样式与构建工具
```
