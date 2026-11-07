# 第二轮：企业级生产环境高保真仿真

第一册（v1.0.0）的成果保持不变；第二轮的一切都在 `v2/` 下，分支 `v2/enterprise`。

| 目录 | 内容 |
|---|---|
| [docs/PLAN.md](docs/PLAN.md) | 目标、规则（真实 / 虚拟 / 注入 / 模拟的标注）、环境设计、阶段 E0–E12 与验收标准 |
| [docs/STATUS.md](docs/STATUS.md) | 各阶段的状态与证据 |
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
```

所有数字都来自这台笔记本（AMD Ryzen 7 8845HS，WSL2 分得 15.28 GiB）上的实验，只代表这里测到的范围；能力验证不等于生产经验。
