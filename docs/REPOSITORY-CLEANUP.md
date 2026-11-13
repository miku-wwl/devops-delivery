# 仓库整理报告（2026-11-13）

目标：GitHub 仓库只保留 `main` 一个分支，`main` 包含第二册出版版（标签 `v2.1.0`）；按实际引用关系审计全部文件，删除真正的冗余，不损害教材、证据与复现链。

本报告分两次提交：第 1–5 节随整理的合并请求一起提交（合并之前已经确定的事实）；第 6–8 节在合并、分支清理与验证完成之后补全。

## 1. 整理前的基线

| 项目 | 状态 |
|---|---|
| 工作树 | 1668 个受版本控制的文件，合计 92 300 384 字节（88.0 MiB） |
| `main` | `be0efaa5e1b7`，比 `v2.1.0` 落后 170 个提交，没有独有提交；是默认分支 |
| 标签 | `v1.0.0` → `b062e7841026`，`v2.0.0` → `84c55998f829`，`v2.1.0` → `affabe06698a`（均为带注释的标签） |
| 远端分支 | 18 个（见第 5 节）；本地分支 18 个 |
| 规则集 `protect-main`（作用于默认分支） | 禁止删除与非快进推送；必须经合并请求，**只允许 squash**；必需检查 `python / lint`、`python / test`、`container image`；**没有任何人可以绕过** |
| 开放的合并请求 | #1 `p1/ci-pipeline`、#2 `p1/drill-bulk-discount`（演练）、#3 `p5/supply-chain`、#5 `release/v1.0`；#4 `p5/drill-vulnerable-dep` 早已关闭 |

## 2. 方法

**依赖审计。**对每个受版本控制的文件，查找引用它的其他文件：完整路径、相对于引用者或 `v2/` 的路径、路径后缀、有固定目录前缀的通配符、只出现文件名，以及只引用其所在目录。被扫描的文本包括工作流、README 与 AGENTS、两册教材的章节、抽查清单 `spot-checks.json`、图表登记表、证据中的结果文件和脚本本身。自动生成的脚本索引 `v2/docs/experiment-index.md` 列出全部脚本，不能证明某个脚本有用，所以不算作引用。

| 审计结果 | 文件数 |
|---|---|
| 被完整路径或通配符引用 | 1146 |
| 只有文件名被提到 | 322（主要是被结果文件引用的运行目录中的原始记录，以及按模块导入的源代码） |
| 只有所在目录被引用 | 198（同上：一次运行的原始记录目录，例如第二册第 8 章 F0b 切换实验的运行目录） |
| 没有任何引用 | 2（`LICENSE`、`.editorconfig`：许可证和编辑器配置，保留） |

**内容相同的文件。**有 18 组内容逐字节相同的文件，全部是正当的，予以保留：空的 `__init__.py`（Python 包的必需文件）；空的日志，表示“这一次没有错误”（例如某个节点上的 ztunnel 错误日志）；以及相邻两次运行恰好相同的输出（例如 Pod 列表）。

**缓存与临时文件。**没有受版本控制的构建缓存、`__pycache__`、编辑器备份或临时文件；构建目录 `manual/build/`、`v2/manual/.pubsrc/` 本来就在 `.gitignore` 中。

**分类规则。**

- KEEP：教材、验证、复现或 CI 实际用到的文件。
- DELETE：没有用途、可以再生的中间产物。
- ARCHIVED_BY_TAG：有历史价值、但最新的 `main` 不需要的文件。删除之前确认已有不可变的标签保存它，并把现行文档中的引用改为指向标签。

本次删除的 41 个文件**全部**都在标签 `v2.1.0` 中，其中 28 个也在 `v2.0.0` 中，2 个也在 `v1.0.0` 中：历史版本仍可完整取回。

## 3. 删除的文件（41 个，14 087 200 字节，13.4 MiB）

| 类别 | 数量 | 路径 | 理由 | 保存在 |
|---|---|---|---|---|
| ARCHIVED_BY_TAG | 2 | `v2/manual/dist/Enterprise-Platform-SRE-Simulation-Vol2.pdf`（12.7 MB）、`v2/manual/dist/Acceptance-Report-v2.pdf` | 第二册第一版（172 页）和它的验收报告 PDF，已被出版版（`v2.1.0`）取代；验收报告的 Markdown 原文 `v2/docs/acceptance-report.md` 保留 | `v2.0.0` |
| ARCHIVED_BY_TAG | 3 | `v2/manual/metadata.yaml`、`v2/manual/layout-accepted-gaps.txt`、`v2/docs/acceptance-metadata.yaml` | 只用于构建上面两个 PDF；出版版使用 `v2/manual/pub/` 下自己的元数据和留白清单 | `v2.0.0` |
| DELETE | 21 | `v2/evidence/{e3,e4,e5,e6,e7,e8,e9}/{build-check.log,verify-evidence.json,verify-evidence.md}`（7 个阶段 × 3 个文件） | 撰写各章时检查构建与证据核验的输出，记录的是书稿检查，不是实验；可以随时用现在的工具重新生成；没有任何章节、抽查、附录或文档引用它们 | `v2.0.0`、`v2.1.0` |
| ARCHIVED_BY_TAG | 13 | `v2/manual/pub/tools/` 下的 `edit.py`、`ch11_figures.py`、`p2_ch01_03.py`、`p2_ch04.py`、`p3_ch05.py`–`p3_ch08.py`、`p3_fix_layout.py`、`p4_ch09_10.py`、`p4_ch11_13.py`、`p6_diagrams.py`、`p6_round2.py` | 出版改造时对章节源文件的一次性改写脚本：只运行一次，再运行会因锚点已不存在而失败；改动本身由 Git 提交记录。保留可以重复使用的 `gaps.py` 和 `preview_figs.py` | `v2.1.0` |
| ARCHIVED_BY_TAG | 1 | `docs/RELEASE_v1.0.md` | 第一册的集成方案和所有者操作清单；其中的合并与关闭合并请求等步骤由本次整理完成或取代，尚未完成的所有者事项转入根目录 README 的 Open items | `v1.0.0` |
| ARCHIVED_BY_TAG | 1 | `manual/tools/prep_p8_evidence.py` | 一次性脚本：把 P8 的浏览器截图复制进 `evidence/p8/`，裁剪并遮挡显示名；需要不在仓库中的原始截图，无法再运行。它说明了这些截图的处理方式，所以保存在标签中 | `v1.0.0` |

已删除的证据文件用花括号写法列出：第一册的证据核验把 `docs/` 中出现的每个证据路径都当作必须存在的引用。完整的删除清单可以随时取得：`git diff --name-only --diff-filter=D v2.1.0 5684b13`（41 行）。

**为此修改的现行引用（10 个文件）：**根目录 `README.md`；`docs/STATUS.md`、`docs/ACCEPTANCE_REPORT.md`（指向 `RELEASE_v1.0.md` 的链接改为 `v1.0.0` 标签中的文件）；`v2/README.md`、`v2/docs/REPRODUCE.md`（第一版 PDF 改为链接到标签 `v2.0.0`）；`v2/docs/acceptance-report.md`（顶部加一段说明，正文不变）；`v2/AGENTS.md`、`v2/docs/publication/PLAN.md`、`REVIEW.md`、`ACCEPTANCE.md`（改写脚本改为指向标签 `v2.1.0`）。

## 4. 保留的核心资产

| 资产 | 理由 |
|---|---|
| `v2/manual/dist/Enterprise-Platform-SRE-Handbook-Vol2-Publication-Edition.pdf` | 第二册的正式版本；与 `v2.1.0` 中的逐字节相同（SHA-256 `5042fb2e…6cd6`），未重新生成 |
| `manual/dist/DevOps-Delivery-Observability-Handbook.pdf`（第一册） | 第一册没有更新的版本；CI 的 `manual-qa` 和 `test_qa_tools.py` 的版面测试都直接检查这个文件 |
| 两册的章节源文件、附录源文件、`manual/tools/`、`v2/manual/pub/`、`v2/manual/figures/`（63 幅） | 重新构建两本 PDF 所需；从整理后的源文件重新构建出版版：217 页，目录 329/329，图与提交的逐字节相同 |
| 全部实验原始记录：`evidence/`（209 个文件）、`v2/evidence/`（841 个） | 教材结论的依据；附录 D 的 226 个证据文件全部存在；572 项抽查全部通过 |
| `v2/platform`、`v2/experiments`、`v2/gitops`、`v2/iac`、`v2/assessment`、`v2/apps` | 第二册的复现链：被复现指南、脚本索引、各章或证据中的运行记录引用 |
| `app/`、`delivery/`、`observability/`、`ansible/`、`synthetic/`、`automation/`、根目录的 `.gitlab-ci.yml` | 第一册的实验对象和交付流水线；第二册的复现也依赖第一册搭建的 GitLab、Runner 与镜像缓存 |
| 全部工作流 | `ci`：规则集要求的三项检查都来自它；`manual-qa`：两册的验收检查；`release`、`production-gate`、`synthetic-gate`：第一册所讲的交付流水线本身 |
| 文档 | 两册的 README 与 AGENTS、复现指南、计划与状态、两份验收报告、出版版审查记录、第一册的实验报告、复盘与模板 |

**审查后保留的一处“断链”。**`v2/manual/pub/front/preface.md` 中的 `../figures/concept-bookmap.svg` 在源目录中不存在。这个路径相对于构建时的派生目录 `v2/manual/.pubsrc/`，阅读指南在构建时被复制到那里，所以在 PDF 中能正常显示；修改它需要改动构建输入，因此保持原样。

**镜像安全修复（整合请求的检查中发现）。**必需检查 `container image` 中的 Trivy 镜像扫描发现，第一册 demo-api 固定的基础镜像（`python:3.13-slim`，Debian 13.7）中的 `zlib1g` 有两个可修复的 HIGH 漏洞（CVE-2026-76844、CVE-2026-85091，修复版本 `1:1.3.dfsg+really1.3.1-1+deb13u1`）。Docker Hub 上当前的 `python:3.13-slim`（2026-11-05 构建）还不含这个修复，所以 `app/Dockerfile` 的运行阶段增加一步，只升级 `zlib1g` 这一个包；基础镜像的固定摘要不变（第一册第 3 章引用了它）。扫描的范围和阈值没有改动。

**CI 补充。**原有的 `manual-qa` 只检查第一册。本次在同一个作业中加了 4 个最小的第二册检查：`verify_evidence.py --root v2`、`figures.py --check`（并要求重新生成的图与提交的逐字节相同）、`pubcheck.py`、出版版 PDF 的版面检查。`figcheck.py` 需要用浏览器构建，留在本地运行。

## 5. 分支处置计划

| 分支 | SHA | 不在 `v2.1.0` 中的提交 | 合并请求 | 处置 |
|---|---|---|---|---|
| `p1/ci-pipeline`、`p2/gitlab-ci`、`p3/helm`、`p4/gitops`、`p5/supply-chain`、`p6/progressive-delivery`、`p7/observability`、`p8/datadog-learning`、`p9/synthetic-gate`、`p10/closed-loop`、`p11/ansible`、`p12/manual` | 各自的阶段末提交 | 0 | #1（p1）、#3（p5）开放 | 已被 `v2.1.0` 包含；删除。#1、#3 已被取代，关闭 |
| `release/v1.0` | `b062e7841026` | 0 | #5 开放 | 就是 `v1.0.0` 指向的提交；删除。#5 由本次整理取代，关闭 |
| `v2/enterprise` | `7a41a899cb9b` | 0 | — | 已被包含（`v2.0.0` 及运维清理）；删除 |
| `v2/publication` | `affabe06698a` + 本次整理 | 0 | 整合请求的源分支 | `main` 验证通过后删除 |
| `p1/drill-bulk-discount` | `926e632a6fb8` | 2：`f7e0700`（“满 10 件九折”，故意带有边界错误）、`926e632`（修复） | #2 开放 | 第一册第 3 章“测试失败阻断合并”的演练，从未经过后续各道关卡。证据（`evidence/release-v1.0/branch-audit.log`）记录了这个分支。**不合并**；打带注释的归档标签 `archive/p1-drill-bulk-discount` 后删除分支，关闭 #2 |
| `p5/drill-vulnerable-dep` | `fb70b451b354` | 1：`fb70b45`（引入 PyYAML 5.3.1，CVE-2020-14343） | #4 已关闭 | 第一册第 7 章供应链演练，被三道关卡拦下（`docs/experiments/P5-supply-chain.md`）。**不合并**；打归档标签 `archive/p5-drill-vulnerable-dep` 后删除分支 |

## 6. 合并与分支清理的结果

（合并之后补全）

## 7. 验证结果

（合并之后补全）

## 8. 未解决的问题与接受的风险

（合并之后补全）
