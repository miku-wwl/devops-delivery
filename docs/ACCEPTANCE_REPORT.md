# 验收报告：DevOps 软件交付与可观测性实战手册（P0–P12）

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-07 |
| 交付物 | `manual/dist/DevOps-Delivery-Observability-Handbook.pdf`（241 页，22.3 MB）；源文件 `manual/chapters/`；各阶段记录 `docs/experiments/`；事故复盘 `docs/rca/`；证据 `evidence/p0`–`p12/` |
| 分支 | 叠加的阶段分支 `p1/…` 至 `p12/manual`（最终状态在 `p12/manual`）；合并到 main 需要仓库所有者审阅 |
| 结论 | P0–P11 共 12 个阶段中 11 个 VALIDATED、1 个 PARTIAL（P8 Datadog），P12 本身 VALIDATED；手册通过内容审查、逐页视觉检查和证据核验，残余问题见第 5 节 |

## 1. 阶段状态

| 阶段 | 内容 | 状态 | 说明 |
|---|---|---|---|
| P0 | 实验环境 | VALIDATED | |
| P1 | GitHub Actions | VALIDATED | 官方 GitHub Skills 练习未执行（需要新建公开仓库） |
| P2 | GitLab CI/CD | VALIDATED | |
| P3 | Helm | VALIDATED | |
| P4 | Argo CD / GitOps | VALIDATED | |
| P5 | 软件供应链安全 | VALIDATED | |
| P6 | 渐进式交付 | VALIDATED | 含勘误；GitHub 生产审批等待所有者批准 |
| P7 | 开放可观测性 | VALIDATED | 发现并修复 P6 遗留的真实问题 |
| P8 | Datadog 学习路径 | PARTIAL | 56 篇讲义已读并由平台记录，7 个实验挑战通过；网页登录部分、问卷、认证由本人完成 |
| P9 | 合成测试门禁 | VALIDATED | 开源实现；Datadog Synthetic 方案 NOT_RUN |
| P10 | 交付闭环与 RCA | VALIDATED | |
| P11 | Ansible | VALIDATED | |
| P12 | 手册整合与验收 | VALIDATED | 本报告 |

## 2. 手册的构成

- **结构：** 前言、第 1 章全景、第 2–13 章（每个阶段一章）、附录 A（版本与命令速查）、B（76 道练习的参考答案）、C（术语表）、D（故障排查索引）、E（证据索引与核验）。目录 304 个标题全部带有正确页码。
- **规模：** 正文约 7.7 万汉字，19 幅架构图（Mermaid），67 张截图（网页截图与终端记录渲染），183 个代码块。
- **每章统一的教学结构：** 学习目标、原理（含架构图与“原理”方框）、分步实验（完整命令与真实输出）、常见问题、练习、小结。

## 3. P12 对教材做了什么

**结构与教学：** 新增前言、第 1 章（三个核心问题、系统全景、一个变更的一生、各章状态、知识地图与学习路径、实验环境拓扑、从零复现的顺序、需要本人完成的事项）和附录 A–E；为第 2–13 章补充学习目标和共 76 道练习（理解、计算、动手、排障、设计、思考），答案全部写入附录 B。

**深度：** 识别出的知识缺口主要在“机制只被使用、没有被打开”。为此新做了 6 组真实实验（`evidence/p12/`），写成 4 个“深入”章节和 2 个工程决策章节：

| 章节 | 新增内容 | 依据的实验 |
|---|---|---|
| 5.10 从一行 YAML 到内核 | 写请求的旅程（认证、鉴权、准入、持久化）；控制器接力与 ownerReferences；Service 的 iptables 概率链与 conntrack；keep-alive 连接全部落在同一 Pod；securityContext/resources 对应的 namespace、capability、seccomp、cgroup、overlayfs | `kubernetes-request-path.log`、`container-internals.log` |
| 7.10 digest 与来源证明 | digest = 清单字节的 SHA-256（实测吻合）；同一提交两个 digest 的逐层原因（构建参数、文件时间戳、配置时间）；SLSA 声明逐字段解读与基于字段的验证策略（含反例） | `oci-image-anatomy.log`、`slsa-provenance-structure.log` |
| 9.9 链路与 PromQL | traceparent 跨服务拼接（实测父 span 关系）；未采样请求的行为；`increase()` 外推出小数的计算 | `trace-context-and-promql.log` |
| 12.7 用 GitOps 历史度量交付表现 | 从配置仓库计算部署频率、变更失败率、Git 恢复时间，并讨论这些数字的局限 | `dora-from-gitops.log` |
| 6.11 GitOps 中的密钥 | 本项目的带外做法与四类生产方案的取舍 | 本项目脚本 |
| 8 章“金丝雀只能撤回 Pod” | 扩展—收缩、部署与发布分离、向前修复 | — |

另外补充了原理方框（Pod 模板哈希、Argo CD 的健康与差异、Sigstore 签名时序、中止时间的计算、采样与 exemplar、Ansible 任务的执行过程），并把后文的发现回链到前文（例如第 3、7 章指向第 12 章发现的门禁触发缺口，第 8 章指向第 5 章的 conntrack 实验，第 11 章的推断由第 7 章逐层证实）。

**真实问题与修正：** 增强过程中按证据核对时修正了几处表述，例如第 8 章“65 秒”明确为“分析开始后”（金丝雀创建后为 72 秒），第 12 章的耗时分解按证据重算，附录答案中的一处公式改写。

## 4. 质量检查

### 4.1 内容审查

逐章通读第 2–13 章，检查技术准确性、与证据的一致性、章节间的引用和术语统一。所有新增的数字都来自 `evidence/` 中的终端记录。

### 4.2 逐页视觉检查

方法：用 `manual/tools/contact_sheet.py` 把 PDF 的每一页渲染为图片（每张 6 页），逐张查看；对字号偏小的图表另以 2.2 倍分辨率单独检查。共做了两轮完整检查（第一轮 230 页、第二轮 246 页的全部页面），之后对每一处修改所在的页面重新渲染复查。

发现并修复的问题：Mermaid 图在打印时被拉伸或缩得过小（改为自然尺寸、13px 字号、限制最大高度，并重绘 9 幅布局不合理的图）；节点文字在单词中间折行（加入显式换行）；大截图无法与上文同页造成大片空白（逐张设定尺寸）；附录表格列宽失衡（固定列宽，并覆盖 pandoc 生成的 `col` 宽度）；封面标题在词中断行；前言多出一页。

### 4.3 自动版面检查（`manual/tools/layout_check.py`）

| 检查 | 结果 |
|---|---|
| 超出右边距的字符 | 0 页 |
| 空白页 | 0 页 |
| 页面使用率低于 60% 且下一页不是新章 | 4 页（第 12、183、192、198 页），均为“小节标题 + 大图”整体移到下一页，属于有意保持标题与图在一起，保留 |

### 4.4 证据核验（`manual/tools/verify_evidence.py`）

| 检查项 | 检查对象数 | 发现的问题 |
|---|---|---|
| 书中引用的图片均存在 | 65 | 0 |
| 引用的证据文件均存在 | 292 | 0 |
| 书中的 GitHub 运行编号均出现在证据中 | 7 | 0 |
| 书中的镜像 digest 均出现在证据或源文件中 | 15 | 0 |
| 章节间的内部链接均有效 | 3 | 0 |
| 章节、文档与证据中没有凭据 | 167 个文件 | 0 |
| 练习数量与附录 B 的答案一致 | 76 | 0 |
| 关键数字与证据原文逐字一致 | 31 | 0 |

## 5. 局限与未完成事项

- **需要本人完成（按规则未代做）：** 合并 PR #1–#3 与之后叠加的阶段分支；批准生产审批运行 42142945642；在 GitGuardian 中标记 P2 的误报；GitHub Skills 练习；Datadog 实验的网页登录部分、各课问卷与认证考试；合并后把 `security` 加入规则集的必需检查。
- **未运行：** Datadog Synthetic 门禁方案（无可用于 CI 的账号，只有模板）。
- **未实现、已在书中标明的改进：** 可复现构建（第 7、11 章，方法来自 BuildKit 文档，未实际验证）；配置仓库合并请求的策略检查（第 12 章练习）；用 Git webhook 缩短 Argo CD 同步延迟；删除遗留的 ConfigMap（expand/contract 的 contract 步骤）。
- **数据口径：** 第 12 章的 DORA 数字来自实验环境，部署节奏由演练安排，失败多为故意演练，只用于说明方法，不具有可比性。
- **版面：** 第 4.3 节所列 4 页留白为有意保留；少量较宽的时序图字号偏小，但在原始分辨率下清晰可读。

## 6. 复现与再核验

```powershell
manual/.venv/Scripts/python.exe manual/tools/verify_evidence.py     # 证据核验，生成 manual/build/evidence-check.json
manual/.venv/Scripts/python.exe manual/tools/gen_appendix.py        # 由附录源文件与核验结果生成附录
manual/.venv/Scripts/python.exe manual/tools/build.py               # 构建 PDF（两遍打印，目录页码准确）
manual/.venv/Scripts/python.exe manual/tools/layout_check.py manual/dist/DevOps-Delivery-Observability-Handbook.pdf
manual/.venv/Scripts/python.exe manual/tools/contact_sheet.py manual/dist/DevOps-Delivery-Observability-Handbook.pdf <输出目录>
```

实验环境的重建顺序见手册第 1 章“从零复现”一节。

## 7. v1.0 收尾（2026-11-07 补记）

封版后的工程审查发现，验收工具本身存在“发现问题却返回成功”的缺陷：`verify_evidence.py` 的第 7、8 项（练习与答案、31 个关键数字）发现问题时仍返回 0；`layout_check.py` 无论发现什么都返回 0；`build.py` 对可能错误的目录页码只给警告；`transcript.sh` 在 256 个失败命令时退出码回绕为 0。本报告第 4.3、4.4 节的结论不受影响（当时实际结果都是 0 个问题，第 4.3 节的 4 处留白经过人工复核），但这些工具当时不能阻断失败。

修复、前后对照和自测试见 [RELEASE_v1.0](https://github.com/miku-wwl/devops-delivery/blob/v1.0.0/docs/RELEASE_v1.0.md) 第 2 节与 `evidence/release-v1.0/qa-tools-before-after.log`；新的 CI 工作流 `manual-qa` 在每个 PR 上运行这些检查。教材、PDF 与证据未改动。
