# 实验记录：P4 / D4 GitOps（Argo CD）

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（证据时间戳为 UTC） |
| 路线图模块 | D4 GitOps；Gate G2 |
| 官方来源 | [Argo CD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)、[Declarative Setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)、[Automated Sync / Self-Heal](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)、[Projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)、[OpenGitOps principles](https://opengitops.dev/) |
| 软件版本 | Argo CD v3.6.1（服务端与 CLI）；GitLab CE 19.5.3（配置仓库）；Kind / Kubernetes v1.37.0 |
| 环境 | Kind 集群 `lab`；配置仓库 `http://gitlab:8929/root/delivery-gitops.git`（只读项目访问令牌） |
| 状态 | **VALIDATED** |

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 建配置仓库、种子提交、只读项目令牌；安装 Argo CD；Pod 内 DNS 检查 | 7 个组件 Running；Pod 访问 gitlab:8929 返回 200 | [install.log](../../evidence/p4/install.log) |
| 2 | 卸载 P3 的 Helm Release，应用 AppProject 与两个 Application | 两个应用 Synced/Healthy（种子提交 7e0c4d3）；镜像版本与 envs 一致 | [bootstrap-apps.log](../../evidence/p4/bootstrap-apps.log) |
| 3 | 经合并请求把 prod 升级到 0.1.1 | 首次尝试 HTTP 400（分支异步可见），修复脚本后：!2 合并 → 81 s 拾取 → 103 s Healthy | [promote-prod.log](../../evidence/p4/promote-prod.log) |
| 4 | dev 手动扩容到 3 | 约 2–4 s 内被 selfHeal 改回 1（automated partial sync） | [drift-dev-selfheal.log](../../evidence/p4/drift-dev-selfheal.log) |
| 5 | prod 手动扩容到 5 | OutOfSync + Healthy；diff 精确到 replicas 5→3；UI 截图 | [drift-prod-detect.log](../../evidence/p4/drift-prod-detect.log)、[argocd-prod-diff.png](../../evidence/p4/argocd-prod-diff.png) |
| 6 | `argocd app rollback`；`argocd app sync` | rollback 被拒（auto-sync 开启）；sync 后 3/3 | [drift-prod-sync.log](../../evidence/p4/drift-prod-sync.log) |
| 7 | 坏变更 !3（errorRate 0.5）→ `git revert` !4 | 坏版本 20/40 返回 500，存活 1m22s；revert 后 40/40 返回 200 | [bad-change-revert.log](../../evidence/p4/bad-change-revert.log)、[argocd-prod-history.png](../../evidence/p4/argocd-prod-history.png) |
| 8 | AppProject 护栏：目标为 kube-system 的应用 | 被拒绝（destination 不在允许列表） | [project-guardrail.log](../../evidence/p4/project-guardrail.log) |

## 失败与排查

- `promote.sh` 首版：推送后立刻创建 MR 返回 400（GitLab 异步登记分支）。→ 创建前轮询分支 API。
- 内联等待循环逻辑错误，过早退出。→ 改为独立的 `wait-sync.sh`，只在状态变化时打印。
- 护栏实验中 `git fetch` 未带认证头，Git 通过 `/dev/tty` 询问凭据而挂起。→ 统一设置 `GIT_TERMINAL_PROMPT=0` 并传入认证头；该段重新记录在 [config-history.log](../../evidence/p4/config-history.log)。
- `pkill -f <模式>` 匹配到执行它的 shell 自身（退出码 15）。→ 使用 `[x]pattern` 写法避免自匹配。

## 局限性

- 配置仓库在本地 GitLab（原因：GitHub main 合并需所有者审阅）；种子与脚本可指向任何 Git 服务器。
- 未配置 Git Webhook，依赖 60 秒轮询（实验设置）。
- 未启用 SSO（Dex）与通知控制器。
