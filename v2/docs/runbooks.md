# 告警处置手册（E9 起）

每条告警的 `runbook_url` 指向这里的一节。处置顺序：先确认影响（看 SLO 与看板），再止血，再找原因。所有改动经过合并请求门禁；冻结期间只有 `[emergency]` 的变更能合并（第 9 章）。告警通过集群外的告警桥（`platform/alerting/bridge.py`）进入 GitLab 项目 `root/incidents`：critical 是事故（incident），warning 是工单（issue）。

## alertmanager-restarting

Alertmanager 在 15 分钟内重启超过 2 次。查看 `kubectl -n monitoring describe pod alertmanager-kps-alertmanager-0` 的上次退出原因（OOMKilled 时提高内存限制）和日志。注意：本规则取代了 kube-prometheus-stack 的 AlertmanagerClusterCrashlooping，后者在这台 WSL 虚拟机上因为进程启动时间随时钟漂移而误报（第 10 章）。

## argocd-sync-failing

某个应用在 10 分钟内同步失败。`kubectl -n argocd get app <名称> -o jsonpath='{.status.operationState.message}'` 给出原因；常见的有：准入策略拒绝、冒用的部署账号没有权限（forbidden，第 9 章）、项目不允许的种类。修复方式是一个新的合并请求，而不是在集群里手工改。

## argocd-root-not-synced

根应用 5 分钟没有同步：任何合并都到不了集群。先看根应用的 `operationState.message`；第 9 章出现过的原因是冒用开启后根应用所在的项目没有账号（`no matching service account`）。在修复之前，冻结一切依赖新合并的发布。

## argocd-app-out-of-sync

应用 15 分钟处于 OutOfSync：自动同步被拒绝、被同步窗口挡住（冻结期间属正常）或某个对象被别的控制器反复改写（第 9 章：Kyverno 生成的对象与 Git 争夺所有权）。比较 `argocd app diff` 的输出与 Git。

## argocd-app-degraded

应用 10 分钟 Degraded：看哪个资源不健康（`.status.resources[?(@.health.status=="Degraded")]`）。路由找不到后端（BackendNotFound）会让整个应用 Degraded，在空集群上还会挡住后续的同步波次（第 9 章）。

## openbao-sealed

OpenBao 已密封：External Secrets 无法读取或刷新任何密钥，已经同步的 Secret 仍然有效。重启之后必然密封；用 `bash v2/platform/secrets/openbao-init.sh` 解封（解封密钥在 `~/.lab-secrets/v2/openbao`）。如果不是重启导致的，先查看审计日志（`kubectl -n secrets logs openbao-0`）中的 `sys/seal` 请求。

## velero-backup-warnings

一次备份完成但带有警告。`velero backup describe <名称> --details` 列出警告；第 8 章中，节点代理跳过了全部 hostPath 卷，备份却报告“Completed”——警告是唯一的线索。确认需要保护的数据由各自的备份负责（PostgreSQL 的归档、OpenBao 的快照）。

## velero-backup-failed

一次备份失败或部分失败。检查备份目标 `backup-s3`（集群外的容器）是否在运行、密钥是否有效，以及 `velero backup logs <名称>`。

## velero-backup-too-old

超过 26 小时没有成功的定时备份：定时任务没有运行，或连续失败。查看 `velero schedule get` 和最近的备份。

## deadman

告警桥 3 分钟没有收到 Alertmanager 的 Watchdog：集群的告警链路（Prometheus → Alertmanager → 告警桥）断了，其他所有告警此刻都看不见。检查承载 Prometheus 和 Alertmanager 的节点是否还在（`kubectl get nodes`，`docker ps`），以及 Alertmanager 能否访问 `alert-bridge:9095`。

## checkout-failing

超过一半的下单请求在 2 分钟内失败：不论错误预算还剩多少，立即止血。先看 GitLab 部署记录中最近的发布（`root/platform-gitops` 的 Deployments，环境 `prod/<服务>`），撤回可疑的合并请求；没有发布时看依赖（payments、数据库）和网关断路器的状态（第 7 章）。E9 的事故演练就是这样一次失败：一个测试用的支付参数进入了生产配置。

## slo-burn

storefront 的某个 SLO 在消耗错误预算。page（快速燃烧）意味着按当前速度几小时到一两天内耗尽 30 天的预算：立即止血，最常见的手段是撤回最近的发布（合并请求）。ticket（慢速燃烧）在工作时间处理。规则由 `platform/slo/gen.py` 从 `platform/slo/slos.yaml` 生成。
