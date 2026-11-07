# 实验记录：P3 / D3 Helm

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（证据时间戳为 UTC） |
| 路线图模块 | D3 Helm / Containers |
| 官方来源 | [Helm Docs](https://helm.sh/docs/)、[Chart Template Guide](https://helm.sh/docs/chart_template_guide/)、[kind Local Registry](https://kind.sigs.k8s.io/docs/user/local-registry/)、[Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) |
| 软件版本 | Helm v4.3.1；Kind v0.33.0；Kubernetes v1.37.0；registry:3.1.2；curlimages/curl:8.23.0 |
| 环境 | Kind 集群 `lab`（1 控制面 + 2 工作节点），本地仓库 localhost:5001 |
| 状态 | **VALIDATED** |

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 创建集群与本地仓库 | 3 节点 Ready；各节点 hosts.toml 指向 kind-registry:5000 | [cluster.log](../../evidence/p3/cluster.log) |
| 2 | `helm lint`（默认/dev/prod）与 schema 反例 | 三者通过；反例被 schema 拒绝（environment、errorRate 两处） | [helm-lint.log](../../evidence/p3/helm-lint.log) |
| 3 | `helm template` dev vs prod diff | 差异：PDB、副本、资源、反亲和、checksum；发现并修正“values 中硬编码 Release 名”的缺陷 | [helm-template.log](../../evidence/p3/helm-template.log) |
| 4 | 推送镜像、创建 restricted 命名空间、安装 dev/prod、`helm test` | 全部 deployed；prod 3/3、PDB 允许 1 个中断；helm test Succeeded | [helm-install.log](../../evidence/p3/helm-install.log) |
| 5 | 升级到 0.1.1 | 20/20 返回 200，version=0.1.1 | [helm-upgrade-rollback.log](../../evidence/p3/helm-upgrade-rollback.log) |
| 6 | 坏配置发布（第一次用 `--set` 失败） | `--set faults.errorRate=0.5` 被 schema 拒绝：string ≠ number，未产生修订 | 同上 |
| 7 | 用 `--set-json` 发布坏配置（修订 4），回滚到修订 2（生成修订 5） | 坏发布：40 次中 22 次 500；回滚后 40/40 为 200 | [helm-bad-release.log](../../evidence/p3/helm-bad-release.log) |
| 8 | 打包并推送 OCI Chart，再拉取渲染 | Pushed / Pulled，digest sha256:9953e175… | [helm-package-oci.log](../../evidence/p3/helm-package-oci.log) |

## 局限性

- 本地仓库为 HTTP（`--plain-http`），未启用认证与 TLS。
- HPA 模板未启用（集群中没有 metrics-server）。

## 清理

```bash
helm uninstall demo-api-dev -n dev && helm uninstall demo-api-prod -n prod
kind delete cluster --name lab && docker rm -f kind-registry
```
（集群继续用于 P4–P10，P12 统一清理。）
