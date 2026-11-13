# 第二册：企业级生产环境高保真仿真

一台笔记本上的真实软件，搭成一个尽可能接近企业生产的多服务平台，再对它做十三组实验：平台基线、多服务系统、服务网格、容量、弹性与调度、多租户与安全、故障注入、数据可靠性与灾难恢复、发布治理、可观测性与事故响应、控制面规模、基础设施即代码、能力考核。每个结论都有执行记录。

第一册（`v1.0.0`）的成果保持不变；第二册的一切都在 `v2/` 下。

## 两个版本

| 版本 | 是什么 | PDF | 分支 / 标签 |
|---|---|---|---|
| **Publication Edition** | 出版级重构：章首导读、机制示意图与实测数据图、图的分类标注、证据编号与四个附录；实验结论与 v2.0.0 相同 | [manual/dist/Enterprise-Platform-SRE-Handbook-Vol2-Publication-Edition.pdf](manual/dist/Enterprise-Platform-SRE-Handbook-Vol2-Publication-Edition.pdf) | 标签 `v2.1.0`，分支 `v2/publication` |
| v2.0.0 | 技术验收版：E0–E12 全部通过验收时的教材与验收报告 | [manual/dist/Enterprise-Platform-SRE-Simulation-Vol2.pdf](manual/dist/Enterprise-Platform-SRE-Simulation-Vol2.pdf) | 标签 `v2.0.0`，分支 `v2/enterprise` |

两次验收是分开的：[docs/acceptance-report.md](docs/acceptance-report.md) 是 v2.0.0 的技术验收；[docs/publication/ACCEPTANCE.md](docs/publication/ACCEPTANCE.md) 是出版版的出版与工程验收，其中也更正了前者的一处不实之处。

## 怎样使用这个仓库

1. **读**：PDF 讲原理、机制与结果。每章开头提出工程问题并列出实测结论，章末说明局限以及与生产环境的差别。
2. **查**：PDF 的附录 C 与 [docs/experiment-index.md](docs/experiment-index.md) 按章列出每个实验的脚本和配置；附录 D 与 [evidence/README.md](evidence/README.md) 说明每个结论对应的原始记录。
3. **做**：[docs/REPRODUCE.md](docs/REPRODUCE.md) 说明环境、顺序、安全边界与核对方法。自动化代理另见 [AGENTS.md](AGENTS.md)。

## 目录

| 位置 | 内容 |
|---|---|
| [docs/PLAN.md](docs/PLAN.md)、[docs/STATUS.md](docs/STATUS.md) | 规则（真实 / 虚拟 / 注入 / 模拟的标注）、环境设计、阶段 E0–E12 的验收标准与结果摘要 |
| [docs/REPRODUCE.md](docs/REPRODUCE.md)、[docs/experiment-index.md](docs/experiment-index.md)、[AGENTS.md](AGENTS.md) | 复现指南、脚本索引、给自动化代理的说明 |
| [docs/runbooks.md](docs/runbooks.md)、[docs/operational-cleanup-report.md](docs/operational-cleanup-report.md) | 告警的处置手册；v2.0.0 之后的运维清理与凭据轮换方法 |
| [docs/cloud-migration.md](docs/cloud-migration.md) | AWS / Azure 迁移分析，只陈述附官方来源的事实 |
| [docs/publication/](docs/publication/) | 出版版的方案与进度、逐页审查记录、验收报告 |
| `platform/` | 集群创建、引导、GitOps 门禁、备份目标、告警桥、KWOK 与 OpenTofu 的安装、固定版本（`versions.env`） |
| `gitops/` | 发布到本地 GitLab `root/platform-gitops` 的配置仓库：Argo CD 的 app-of-apps、平台组件的参数、服务 Chart、环境配置 |
| `apps/storefront/` | 被交付的多服务系统（6 个服务，一个镜像）及其测试 |
| `iac/` | OpenTofu：GitLab 门禁的配置，经 `iac/tofu.sh` 运行 |
| `experiments/` | 可重复执行的实验脚本，按阶段分目录 |
| `evidence/` | 每个阶段的原始记录：假设、终端输出、查询结果、截图、复盘 |
| `assessment/` | 能力考核：架构设计题、故障排查题（注入 + 自动判分）、实操题 |
| `manual/chapters/`、`manual/appendix-src/` | 教材的章节源文件与练习答案；`manual/spot-checks.json` 是正文与证据的逐条对照 |
| `manual/pub/`、`manual/figures/` | 出版版的构建脚本、样式、图表库与图表数据来源；生成的图 |

## 快速开始

在 WSL 发行版 `devops-lab` 中，仓库路径 `/mnt/d/workshop/nov/devops-delivery`：

```bash
bash v2/platform/cluster/v1-lab.sh stop        # 暂停第一册的集群（可恢复）
bash v2/platform/cluster/create.sh             # E0：三可用区集群 ent
bash v2/platform/bootstrap/bootstrap.sh        # E1：密钥、镜像、配置仓库、Argo CD、根应用
bash v2/platform/bootstrap/wait-apps.sh 1500   # 等待平台从 Git 收敛
bash v2/platform/secrets/openbao-init.sh       # 每次 OpenBao 重启之后：解封（等待它真正应答，不会覆盖已有的密钥）
```

完整的顺序与每个阶段的入口见 [docs/REPRODUCE.md](docs/REPRODUCE.md)。

## 边界

所有数字都来自这台笔记本（AMD Ryzen 7 8845HS，WSL2 分得 15.28 GiB）上的一次或几次运行，只代表这里测到的范围。第 11 章的 1000 个节点与 10 000 个 Pod 是 KWOK 的虚拟对象，只有控制面是真实的。能力验证不等于生产经验；还没有第三方做过独立的端到端复现。
