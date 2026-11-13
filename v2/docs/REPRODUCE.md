# 复现指南

> **先说明证据的强度。**本指南由执行过这些实验的同一台机器整理而成。集群从零重建在这台机器上实际做过四次（第 8 章的 R1、R2，第 9 章的 R3、R4，记录在 `evidence/e7/r1`–`r4`），这是目前最接近“从零复现”的证据。**还没有任何人在另一台机器上做过独立的端到端复现**；在 Linux 主机或其他硬件上运行属于未验证。

教材讲原理，仓库放实现：先读 PDF 的某一章，再到 [experiment-index.md](experiment-index.md) 找到那一章的脚本，运行，拿自己的输出与 `evidence/<阶段>/` 中的记录对比。

## 1. 需要什么

| 项目 | 实测的配置 | 说明 |
|---|---|---|
| 主机 | AMD Ryzen 7 8845HS（8 核 16 线程），31 GB 内存，Windows 11 | 内存是硬约束：WSL2 虚拟机分得 15.3 GiB，三个工作节点各 3.5 GiB，再加 GitLab 约 3 GiB |
| 虚拟机 | WSL2，Ubuntu 24.04，发行版名 `devops-lab`，Docker Engine 运行在 WSL 内 | 脚本假定仓库在 `/mnt/d/workshop/nov/devops-delivery`；路径不同时要相应调整 |
| 第一册的环境 | 本地 GitLab CE、Runner、镜像仓库与拉取缓存（第一册搭建） | 第二册复用它们；第一册的 Kind 集群 `lab` 在第二册期间暂停 |
| 命令行工具 | kind、kubectl、helm、k6、jq、curl、git、python3、openssl | 由第一册的环境安装；kwokctl 与 OpenTofu 由 `platform/kwok/install.sh`、`platform/iac/install.sh` 安装（固定版本并校验 SHA-256） |
| 固定的版本 | `platform/versions.env` | Kubernetes v1.37.0（Kind 节点镜像按摘要固定）、Istio 1.31.4、Gateway API v1.6.3、KEDA 2.21.0、Kyverno chart 3.9.2、OpenBao chart 0.30.7、External Secrets 2.14.0、Garage v2.5.0、KWOK v0.8.0、OpenTofu 1.13.9；其余组件的 chart 版本写在 `gitops/platform/apps/*.yaml` 中 |
| 教材构建 | pandoc、Microsoft Edge、`manual/.venv`（playwright、pypdf；`manual/requirements.txt`）、`manual/node_modules`（mermaid） | 只在构建 PDF 时需要 |

没有创建任何云资源，没有付费服务。首次运行需要联网拉取镜像与 chart；上游若撤下某个版本，对应步骤需要换版本。

## 2. 顺序与入口

阶段之间有依赖：后面的阶段在前面留下的平台上进行。每个阶段的全部脚本及其用途见 [experiment-index.md](experiment-index.md)。

| 阶段 | 主要入口（相对于 `v2/`） | 实测的耗时参考 | 结果在哪里核对 |
|---|---|---|---|
| E0 平台基线 | `platform/cluster/v1-lab.sh stop`，`platform/cluster/create.sh`，`platform/cluster/measure.sh` | 集群创建 43 秒 | 第 1 章；`evidence/e0/` |
| E1 多服务系统 | `platform/bootstrap/bootstrap.sh`，`platform/bootstrap/wait-apps.sh 1500` | 首次从 Git 收敛 735 秒；后来的重建 636 秒 | 第 2 章；`evidence/e1/` |
| E2 服务网格 | `experiments/e2/` | 每个实验几分钟 | 第 3 章；`evidence/e2/` |
| E3 容量 | 先运行 `platform/cluster/lb-limits.sh`，再运行 `experiments/e3/` | 阶梯负载一次几十分钟 | 第 4 章；预测 `evidence/e3/capacity-prediction.md` |
| E4 弹性与调度 | `experiments/e4/` | 每个实验 5–20 分钟 | 第 5 章 |
| E5 多租户与安全 | `platform/tenants/users.sh`，`platform/secrets/openbao-init.sh`，`experiments/e5/` | — | 第 6 章 |
| E6 故障注入 | `experiments/e6/`（`fault-phase.sh`、`node-failure.sh`、`partition.sh`） | 节点失效一次约 10 分钟 | 第 7 章；三份 `*-prediction.md` |
| E7 数据可靠性 | `platform/backup/object-store.sh`，`experiments/e7/`（`rebuild.sh` 会**删除整个集群**） | 重建 15–20 分钟 | 第 8 章；`evidence/e7/r1`、`r2` |
| E8 发布治理 | `platform/gitops/setup.sh`，`platform/gitops/mr.sh`，`experiments/e8/` | 一次合并请求 30–50 秒 | 第 9 章 |
| E9 可观测性 | `platform/alerting/run-bridge.sh`，`experiments/e9/` | 事故演练约 1.5 小时（含基线） | 第 10 章；`evidence/e9/incident/` |
| E10 控制面规模 | `platform/kwok/install.sh`，`experiments/e10/scale.sh up|pods|state|lists|apf|clean|down` | 每个集群 5–10 分钟 | 第 11 章；`evidence/e10/scale-results.md` |
| E11 IaC | `platform/iac/install.sh`，`platform/iac/state-project.sh`，`iac/tofu.sh gitlab plan`，`experiments/e11/` | — | 第 12 章；`evidence/e11/iac-results.md` |
| E12 考核 | `assessment/README.md` | 每道题几分钟 | 第 13 章；`evidence/e12/` |

日常状态检查（只读）：`experiments/e8/lab-state.sh`、`experiments/ops-1/check.sh`。

## 3. 怎样判断“复现了”

绝对数字随硬件变化，不应期待相同；应当成立的是关系与机制。每个阶段的假设写在 `evidence/<阶段>/*-prediction.md`，结果写在 `*-results.md`。几个不依赖硬件的检验点：

- 默认配置下，调度速度贴近调度器的客户端限速（每秒 50 个）（第 11 章）；
- etcd 的有效数据随 Pod 数线性增长，删除先让数据库变大（第 11 章）；
- 只有 ztunnel 时长连接上的负载仍然不均，经过 waypoint 后接近 50/50（第 3 章）；
- 内存压力下先被驱逐的是超出请求最多的 Pod，而不是 BestEffort（第 5 章）；
- 异步复制在“复制中断后再失去主库”时丢失已确认的写入，同步复制不丢（第 8 章）；
- Garage v2.5.0 不实现 `If-None-Match`，OpenTofu 的 `use_lockfile` 在它上面不起作用（第 12 章）。

被推翻的假设同样是结果：在你的环境里它们可能成立，也可能以别的方式被推翻，两种情况都值得记录。

## 4. 安全边界

- **会破坏东西的脚本**：`experiments/e7/rebuild.sh destroy`（删除集群 `ent`）；`experiments/e10/scale.sh apf`（对 API server 发起洪水——事故 E10-1 中冻结过整台虚拟机，脚本现在给每个容器设了内存上限并自带内存保护）；故障注入脚本（冻结节点、iptables）靠 `trap` 收回故障，中途被杀死时要手动检查。
- **秘密**：全部在 `~/.lab-secrets/`，从不进入 Git、日志或命令行参数。OpenBao 每次重启后要运行 `platform/secrets/openbao-init.sh` 解封；它在 OpenBao 真正应答之前什么也不做，并拒绝覆盖已有的密钥文件（事故 E11-1 的教训）。解封密钥只有这台机器上的副本，丢失即数据不可读——这是所有者接受的实验环境风险。
- **配置变更**：进入集群的配置只经 `platform/bootstrap/publish-gitops.sh`（合并请求 + 门禁）；它镜像整个 `v2/gitops` 目录，演练期间不要编辑这个目录。
- **资源**：两个集群共用 15.3 GiB。启动 KWOK 集群或负载之前先看 `free -m`；工作节点的内存请求常年在 82%–98%。

## 5. 重启之后

虚拟机或主机重启后，Kind 的节点容器有时需要手动启动（`docker start ent-control-plane ent-worker ent-worker2 ent-worker3`），然后依次：`platform/secrets/openbao-init.sh`、`platform/cluster/lb-limits.sh`、`platform/bootstrap/wait-apps.sh`。实验用户的证书 7 天过期（`platform/tenants/users.sh` 重新签发），GitLab 令牌 30–60 天过期（轮换方法见 [operational-cleanup-report.md](operational-cleanup-report.md)）。

## 6. 构建教材与核验

```bash
# 出版版（Publication Edition）
manual/.venv/Scripts/python.exe v2/manual/pub/build_pub.py
# 核验：证据、图表数据、导读一致性、版面
manual/.venv/Scripts/python.exe manual/tools/verify_evidence.py --root v2
manual/.venv/Scripts/python.exe v2/manual/pub/figures.py --check
manual/.venv/Scripts/python.exe v2/manual/pub/pubcheck.py
manual/.venv/Scripts/python.exe v2/manual/pub/figcheck.py --quiet     # 图印刷后的最小字号（使用最近一次构建的 HTML）
manual/.venv/Scripts/python.exe manual/tools/layout_check.py v2/manual/dist/Enterprise-Platform-SRE-Handbook-Vol2-Publication-Edition.pdf --accept-gaps-file v2/manual/pub/layout-accepted-gaps.txt
```

v2.0.0 的技术验收版 PDF 保持原样（`manual/dist/Enterprise-Platform-SRE-Simulation-Vol2.pdf`，标签 `v2.0.0`）。

## 7. 已知的偏差来源

每种配置通常只运行一次；主机在实验期间出现过降频、睡眠；WSL 虚拟机的单调时钟比墙上时钟快约 3%（第 10 章）；镜像经本地缓存拉取，首次运行的耗时不同；Prometheus 只保留几天的数据，证据要在实验当时记录。
