# Operational Cleanup Report（v2.0.0 之后，第一阶段）

> 日期 2026-11-10/11（UTC 23:50–23:56）｜ 分支 `v2/enterprise` ｜ 不修改 `v1.0.0`、`v2.0.0` 标签与历史证据 ｜ 证据：`v2/evidence/ops-1/` ｜ 检查脚本：`v2/experiments/ops-1/check.sh`（只读，不输出任何密钥、令牌或证书内容）

## 结果

| 项目 | 状态 | 摘要 |
|---|---|---|
| P0 解封密钥：完整性、权限、一致性 | PASS | `init.json` 与 `init.json.copy` 均为 400、属主 devops、目录 700，结构有效（含密钥与根令牌），两份逐字节相同 |
| P0 OpenBao 与密钥同步 | PASS | 已初始化、未密封（2.7.2）；两个 SecretStore Valid，ExternalSecret SecretSynced |
| P0 恢复脚本的防护 | PASS | `openbao-init.sh`：等待真实应答、存在密钥文件时拒绝初始化、原子写入、只读（事故 E11-1 的修复） |
| P0 WSL 之外的加密备份 | **OWNER_ACTION_REQUIRED** | 流程与脚本已就绪并用假密钥测试通过；需要所有者本人执行并确认（见下） |
| P1 历史失败的快照任务 | PASS | 两个 Job 与 6 个 Init:Error Pod 已清理；CronJob、成功的任务、快照对象未受影响；相关工单已自动关闭 |
| P1 ent-worker3 内存请求 98% | **OWNER_ACTION_REQUIRED** | 证据不支持安全的降配；容量瓶颈与扩容建议见下，未做改动 |
| P2 实验用户证书 | PASS | 4 个常设用户已重新签发并验证；下次到期 2026-11-17 23:49 UTC |
| P2 GitLab 访问令牌 | PASS（检查完成，未到轮换窗口） | 最早 2026-12-05 到期；轮换手册与提醒日期见下 |

## P0 解封密钥

检查（`before.log`）：两份密钥文件权限 400、目录 700，结构有效、逐字节相同；OpenBao 未密封，密钥同步正常；恢复脚本具备防误初始化和防截断的保护。旧的 Retain 卷 `pvc-a98749bd-…` 保留未动。

**外部备份（OWNER_ACTION_REQUIRED）**——由所有者本人在 WSL 终端中执行：

```bash
bash v2/platform/secrets/openbao-key-backup.sh /mnt/c/Users/<你>/lab-key-staging
```

1. 脚本用 gpg（AES-256，对称加密）加密密钥文件，口令由你输入两次，不保存、不缓存；
2. 再解密一次（第三次输入口令）并与原文件逐字节比较，只输出 `verified`；
3. 输出加密文件名与 SHA-256；
4. 把 `.gpg` 文件移入独立的加密存储（密码管理器附件或加密的外置磁盘），口令另存于密码管理器，删除暂存目录中的副本；
5. 回复确认后，此项才能标为完成。

脚本测试（`p0-backup-test.log`，假密钥文件、测试口令）：解密结果与原文件一致；加密文件中不含明文标记；错误口令被拒绝；真实密钥文件未被触碰。恢复方法写在脚本注释中（只能写入空位，`openbao-init.sh` 拒绝覆盖已有密钥）。

## P1 历史失败的快照任务

`openbao-snapshot-29905757`、`openbao-snapshot-29905817`：属于 CronJob `openbao-snapshot`，各失败 3 次、无活动 Pod，产生于 OpenBao 密封期间（事故 E11-1）。清理（`p1-jobs.log`）：只删除这两个 Job，从属 Pod 随之删除；集群中非 Running/Completed 的 Pod 6 → 0。未受影响：CronJob（每小时第 17 分，未暂停，最近成功 23:17:06）、成功的任务、Garage 中的 22 个 OpenBao 快照对象（最新 `openbao/20261110T231703Z.snap`）。告警桥中相关的 KubeJobFailed/KubeContainerWaiting 工单随之自动关闭，当前没有打开的事故或工单。

## P1 ent-worker3 内存

证据（`p1-memory.log`）：

| | 请求 | 实际（当前） | 17 小时峰值 |
|---|---|---|---|
| ent-worker3（节点） | 3130 Mi（98%） | 2643 Mi（83%） | — |
| Prometheus | 1024 Mi | 903 Mi | 1030–1156 Mi（**超过请求**） |
| Tempo | 640 Mi | 234 Mi | 424–443 Mi |
| PostgreSQL pg-main-3 | 256 Mi | 116 Mi | 110–203 Mi |

结论：唯一明显富余的是 Tempo（峰值约为请求的 70%），而 Prometheus 的峰值已经超过它的请求——把 Tempo 的余量让出来，只是把缺口转移到 Prometheus；17 小时的窗口也不包含负载实验时 Tempo 的峰值。没有证据支持安全的降配，因此不做改动。

容量建议（所有者决定）：工作节点内存 3.5 GiB → 4 GiB（三个节点共 +1.5 GiB；当前 WSL 可用约 4 GiB），或增加第四个工作节点；在此之前，Prometheus 的请求宜提高到实际峰值（约 1.2 GiB），但这需要先有节点容量。若以后有 7 天的数据证明 Tempo 峰值稳定低于 450 Mi，可再评估将其请求降到约 512 Mi。

## P2 证书与令牌

**实验用户证书**（`p2-certs.log`）：之前的实际到期时间是 2026-11-17 05:53 UTC（早先估计的 11-16 有误）。已用 `v2/platform/tenants/users.sh` 重新签发 alice、bob、carol、dave，新的到期时间 2026-11-17 23:49 UTC（证书有意只有 7 天）；验证：API server 识别出正确的用户与组，alice 能列出 shop-dev 的 Pod、不能读 storefront 的 Secret。carol-breakglass 是 1 小时的证书，按设计不续签。没有服务依赖这些证书（只用于实验与考核）。**提醒：每 7 天重跑一次 `users.sh`**（下一次在 2026-11-17 23:49 UTC 之前）。

**GitLab 访问令牌**（`before.log`，只读取元数据）：

| 令牌 | 使用方 | 到期 | 轮换后要更新的地方 |
|---|---|---|---|
| lab-automation（root） | 各脚本、OpenTofu（`iac/tofu.sh`）、门禁的合并请求 | **2026-12-05** | 只有文件 `~/.lab-secrets/gitlab-root-token`（脚本每次运行时读取） |
| argocd-ent-read（项目令牌） | Argo CD 读取配置仓库 | 2026-12-07 | Argo CD 的仓库 Secret：`bash v2/assessment/t1-argocd-repo.sh restore`（从文件经标准输入写入），再用 `... grade` 验证 3/3 |
| e8-merge-requests（alice 的模拟令牌） | `mr.sh --as alice` | 2026-12-10 | 文件 `~/.lab-secrets/v2/gitlab/alice-token` |
| argocd-deployment-events | Argo CD 通知 → GitLab 部署记录 | 2027-01-09 | 重跑 `v2/platform/gitops/deploy-events.sh` |
| alert-bridge | 告警桥 | 2027-01-09 | `incidents.env`，再用 `run-bridge.sh` 重启告警桥 |

轮换方法：用待轮换的令牌调用 GitLab 的 `POST /api/v4/personal_access_tokens/self/rotate`（令牌只经请求头文件传递），返回的新令牌写入原文件（`umask 077`，先写临时文件再移动），再按上表更新使用方并验证；模拟令牌由管理员为 alice 新建、确认可用后吊销旧的。**提醒：2026-11-28 前轮换前三个令牌**；每周运行一次 `bash v2/experiments/ops-1/check.sh` 查看所有到期时间。

## 当前健康状态（`after.log`，2026-11-10 23:56 UTC）

- Kubernetes：4/4 节点 Ready，上下文 kind-ent，非 Running/Completed 的 Pod 0 个；
- Argo CD：39/39 Synced/Healthy；
- OpenBao：已初始化、未密封，密钥同步正常；
- 快照：CronJob 正常，最近成功 23:17:06；告警桥：没有打开的事故或工单，死人开关线程存活。

## 未解决的风险与所有者操作

1. **OWNER_ACTION_REQUIRED**：执行密钥的外部加密备份并确认（P0）。
2. **OWNER_ACTION_REQUIRED**：决定工作节点扩容（P1 内存）。
3. 2026-11-17 前重新签发实验用户证书；2026-11-28 前轮换 root、Argo CD 读取、alice 三个 GitLab 令牌。
4. 旧的 Retain 卷保留未动，是否删除由所有者决定。
5. 本轮未改动的已知风险（见 `v2/docs/acceptance-report.md`）：告警桥单点、Garage 没有对象锁、抑制规则只用合成告警验证过。
