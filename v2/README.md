# 第二轮：企业级生产环境高保真仿真

第一册（v1.0.0）的成果保持不变；第二轮的一切都在 `v2/` 下，分支 `v2/enterprise`。

## 最终交付（v2.0.0，2026-11-11）

E0–E12 全部通过验收。

| 交付物 | 位置 |
|---|---|
| 第二册教材（PDF，172 页，13 章） | [manual/dist/Enterprise-Platform-SRE-Simulation-Vol2.pdf](manual/dist/Enterprise-Platform-SRE-Simulation-Vol2.pdf) |
| 最终验收报告 | [docs/acceptance-report.md](docs/acceptance-report.md)（PDF：[manual/dist/Acceptance-Report-v2.pdf](manual/dist/Acceptance-Report-v2.pdf)） |
| 实验仓库 | 本目录：配置、脚本、原始证据与复现流程（下表） |

| 目录 | 内容 |
|---|---|
| [docs/PLAN.md](docs/PLAN.md) | 目标、规则（真实 / 虚拟 / 注入 / 模拟的标注）、环境设计、阶段 E0–E12 与验收标准 |
| [docs/STATUS.md](docs/STATUS.md) | 各阶段的状态与证据 |
| [docs/cloud-migration.md](docs/cloud-migration.md) | AWS/Azure 迁移分析（E11），只陈述附官方来源的事实 |
| `iac/` | OpenTofu：GitLab 门禁的配置（E11），经 `iac/tofu.sh` 运行 |
| `assessment/` | 能力考核（E12）：架构设计题、故障排查题（注入 + 自动判分）、实操题 |
| `platform/` | 集群创建（`cluster/`）、引导（`bootstrap/`）、看板生成（`dashboards/`）、固定版本（`versions.env`） |
| `gitops/` | 发布到本地 GitLab `root/platform-gitops` 的配置仓库内容：Argo CD 的 app-of-apps、平台组件的参数、服务 Chart、环境配置 |
| `apps/storefront/` | 被交付的多服务系统（6 个服务，一个镜像）及其测试 |
| `experiments/` | 可重复执行的实验脚本 |
| `evidence/eN/` | 每个阶段的原始记录：终端记录、查询结果、截图 |
| `manual/` | 第二册教材的章节与练习答案 |

快速开始（在 WSL 发行版 `devops-lab` 中，仓库路径 `/mnt/d/workshop/nov/devops-delivery`）：

```bash
bash v2/platform/cluster/v1-lab.sh stop        # 暂停第一册的集群（可恢复）
bash v2/platform/cluster/create.sh             # E0：三可用区集群 ent
bash v2/platform/bootstrap/bootstrap.sh        # E1：密钥、镜像、配置仓库、Argo CD、根应用
bash v2/platform/bootstrap/wait-apps.sh 1500   # 等待平台从 Git 收敛
bash v2/platform/secrets/openbao-init.sh       # 每次 OpenBao 重启之后：解封（等待它真正应答，不会覆盖已有的密钥）
```

所有数字都来自这台笔记本（AMD Ryzen 7 8845HS，WSL2 分得 15.28 GiB）上的实验，只代表这里测到的范围；能力验证不等于生产经验。
