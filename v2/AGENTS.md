# 给自动化代理（Agent）的说明

这个目录是一本实验教材的全部实现与证据。本文件面向在这里继续工作的代码代理：先读什么、能做什么、不能做什么、哪些坑已经有人踩过。人类读者请从 [README.md](README.md) 和 [docs/REPRODUCE.md](docs/REPRODUCE.md) 开始。

## 先读

1. [docs/STATUS.md](docs/STATUS.md)：E0–E12 各阶段的结果摘要；[docs/PLAN.md](docs/PLAN.md)：规则与验收标准。
2. [docs/publication/PLAN.md](docs/publication/PLAN.md)：出版版的做法与进度（会话中断后的恢复入口）。
3. [docs/experiment-index.md](docs/experiment-index.md)：每个脚本的用途；[evidence/README.md](evidence/README.md)：证据的组织方式。
4. [docs/REPRODUCE.md](docs/REPRODUCE.md)：环境、顺序、安全边界。

## 环境入口

- 实验在 WSL 发行版 `devops-lab` 中运行：`wsl.exe -d devops-lab -e bash -lc '<命令>'`（从 Git Bash 调用时加 `MSYS_NO_PATHCONV=1`）；仓库在 `/mnt/d/workshop/nov/devops-delivery`。
- Kubernetes 上下文必须是 `kind-ent`；第 11 章的 KWOK 集群使用独立的 kubeconfig（`~/.kwok/scale.kubeconfig`），用完即删。
- 教材工具在 Windows 一侧运行：`manual/.venv/Scripts/python.exe`。

## 必须遵守

1. **秘密不外泄。**`~/.lab-secrets/` 中的任何内容不得出现在输出、日志、Git、截图或 PDF 中；秘密只经文件或标准输入传给命令，不进命令行参数（API server 的审计日志会记录 exec 的命令行）。比较用哈希，检查用元数据。
2. **假设先于实验。**每组实验先把假设写进 `evidence/<阶段>/*-prediction.md` 并提交，再运行；被推翻的假设如实记录，不为了通过而改结论，不事后修改原始证据（更正用追加的说明）。
3. **变更经过门禁。**进入集群的配置只经 `platform/bootstrap/publish-gitops.sh`（它开合并请求、等流水线、再合并）；不直接 `kubectl apply` 平台配置，不对 Argo CD 运行 `helm upgrade`（它管理自身）。
4. **不可逆的操作先问所有者。**删除卷或集群、重新初始化 OpenBao、合并到 `main`、移动或覆盖标签、创建任何收费资源——都需要所有者明确批准。`v1.0.0`、`v2.0.0` 标签与已发布的 PDF 不得改动。
5. **标注真实性，不夸大。**`[真实]`、`[虚拟]`、`[注入]`、`[模拟]` 四种标注贯穿全书；单机实验的数字不外推为生产容量；没有做过的验证（例如第三方的独立复现）不得声称做过。
6. **资源是共享的。**两个集群共用 15.3 GiB；启动第二个控制面或负载之前检查可用内存，实验组件要有内存上限（事故 E10-1）。

## 已经踩过的坑

- 主机或虚拟机重启后：Kind 节点可能需要 `docker start`；OpenBao 是密封的——运行 `platform/secrets/openbao-init.sh`，它会等 OpenBao 真正应答；不要自己写“如果没初始化就初始化”的逻辑（事故 E11-1：这样的逻辑清空过唯一的解封密钥）。
- 负载实验之前运行 `platform/cluster/lb-limits.sh`（实验环境的负载均衡器默认只有 1024 个文件描述符）。
- `publish-gitops.sh` 镜像整个 `v2/gitops`：演练期间不要编辑这个目录；别人在 GitLab 中合并的改动要抄回 `v2/gitops`，否则下一次发布会把它们撤销。
- Kyverno 的 generate 规则不可变（要删除重建策略）；`kubectl get backup` 是 CloudNativePG 的资源，Velero 的要写全名。
- kwokctl 的 `--disable-qps-limits` 同时关闭 APF；创建集群时必须带 `--kubeconfig`，否则它会改写默认的 kubeconfig。
- WSL 中 `date -d HH:MM` 是本地时间（UTC+13）；记录一律用 UTC。虚拟机的单调时钟比墙上时钟快约 3%。
- 本环境中经 Bash 工具传入的 heredoc 会把两个连续的反斜杠折叠成一个（本文件的这一行就因此被写错过一次）：含反斜杠的 Python 或正则不要用 heredoc 写入文件，用编辑器或文件写入工具。正在后台运行的脚本不要编辑（bash 按偏移量增量读取）。`pkill -f 模式` 会杀死包含该模式的调用者自身，用 `[模]式` 的写法。
- `manual/tools/build.py` 不带 `--out` 时的默认输出是第一册的 PDF：构建第二册必须给 `--out`，出版版用 `v2/manual/pub/build_pub.py`。`manual/tools/gen_appendix.py` 只属于第一册。

## 改了东西之后要跑的检查

```bash
manual/.venv/Scripts/python.exe manual/tools/verify_evidence.py --root v2      # 正文与证据：572 项抽查等 8 类检查
manual/.venv/Scripts/python.exe v2/manual/pub/figures.py --check               # 图表数据与正文、证据一致
manual/.venv/Scripts/python.exe v2/manual/pub/pubcheck.py                      # 章首导读、图注、章节结构、图文顺序、封面数字
manual/.venv/Scripts/python.exe v2/manual/pub/figcheck.py --quiet              # 每幅图印刷后的最小字号不低于 6.5 pt
manual/.venv/Scripts/python.exe v2/manual/pub/build_pub.py                     # 构建出版版 PDF
bash v2/experiments/ops-1/check.sh                                             # 实验环境的只读健康检查（在 WSL 中）
```

改动章节正文时，同步维护 `manual/spot-checks.json`：一条检查 = 正文中的一句话 + 证据文件中的一段原文；删掉或改写了被检查的句子，就把检查指向表达同一事实的新句子，而不是删除检查。出版版对章节的历次改动由一次性脚本完成，脚本保存在标签 `v2.1.0` 中（[v2/manual/pub/tools](https://github.com/miku-wwl/devops-delivery/tree/v2.1.0/v2/manual/pub/tools)）；以后的改动直接编辑章节源文件，由 Git 提交留痕。仓库只有 `main` 一个分支，改动经合并请求进入。

## 复现一个实验的步骤

读这一章的假设（`evidence/<阶段>/*-prediction.md`）→ 检查环境健康与可用内存 → 运行 `experiments/<阶段>/` 下对应的脚本，输出重定向到自己的目录 → 与 `*-results.md` 和章节中的表格对比 → 差异写下来，不要改动仓库中原有的证据。
