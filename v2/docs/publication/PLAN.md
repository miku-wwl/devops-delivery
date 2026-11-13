# Publication Edition：出版方案与进度

> 出版版在分支 `v2/publication`（从 `v2/enterprise` @ 7a41a89 分出）上完成，发布为标签 `v2.1.0`；之后两个分支合并进 `main` 并删除（[../../../docs/REPOSITORY-CLEANUP.md](../../../docs/REPOSITORY-CLEANUP.md)）。`v1.0.0`、`v2.0.0` 标签、v2.0.0 的 PDF 与全部原始证据不改动。
> 本文件是恢复入口：会话中断后，从“进度”一节未勾选的第一项继续。

## 目标

把 172 页、13 章的第二册升级为出版品质的教材：教学结构、技术可视化、图文分离与阅读体验；不扩展实验平台，不重跑已验收的高成本实验。

## 做法

| 方面 | 做法 | 位置 |
|---|---|---|
| 构建 | 章节源文件保持可核验（`verify_evidence.py --root v2`）；出版版由 `build_pub.py` 从源文件确定性地派生 | `v2/manual/pub/build_pub.py` |
| 版式 | 独立的样式、模板与 Mermaid 主题；章首导读、图框与图类标签、表格与代码的统一样式 | `v2/manual/pub/pub.css`、`template.html`、`render.js` |
| 证据分离 | 正文中的证据路径在构建时变为上标编号，文件清单进附录 D；每章开头的“产出/位置”表进附录 C | `build_pub.py` |
| 图的分类 | 每幅图标注：示意图 / 实测数据 / 真实截图 / 终端记录 / 模型曲线 | `pub.css`、`build_pub.py` |
| 数据图 | 无依赖的 SVG 图表库；每幅图登记数据来源，`figures.py --check` 核对图中数字与正文、证据一致 | `v2/manual/pub/charts.py`、`figures.py`、`v2/manual/figures/` |
| 内容 | 每章：章首导读（工程问题 + 实测结论）、机制示意图、数据图、“从实验环境到生产环境”对照；新增阅读指南、术语表、练习答案附录 | `v2/manual/chapters/`、`v2/manual/pub/front`、`back` |
| 改写记录 | 每章的改动由一次性脚本完成，脚本保存在标签 `v2.1.0` 中（已从 `main` 移除） | [v2/manual/pub/tools @ v2.1.0](https://github.com/miku-wwl/devops-delivery/tree/v2.1.0/v2/manual/pub/tools) |
| 验收 | 版面检查、证据核验（抽查基线 572 项）、图表数据核对、逐页审查记录、独立验收报告 | `v2/docs/publication/` |

## 构建

```bash
manual/.venv/Scripts/python.exe v2/manual/pub/build_pub.py                 # 全书
manual/.venv/Scripts/python.exe v2/manual/pub/build_pub.py --only 11 --out manual/build/pub-ch11.pdf   # 单章预览
manual/.venv/Scripts/python.exe v2/manual/pub/figures.py --check           # 图表数据核对
manual/.venv/Scripts/python.exe manual/tools/verify_evidence.py --root v2  # 证据核验
```

## 进度

- [x] P1 构建体系、版式、图表库；第 11 章的三幅 Mermaid 数据图改为从证据绘制
- [x] P2 第 1–4 章：导读、示意图、数据图、对照表（脚本：`pub/tools/p2_ch01_03.py`、`p2_ch04.py`）
- [x] P3 第 5–8 章（脚本：`pub/tools/p3_ch05.py` … `p3_ch08.py`）
- [x] P4 第 9–13 章（脚本：`pub/tools/p4_ch09_10.py`、`p4_ch11_13.py`）
- [x] P5 阅读指南、术语表、`pubcheck.py`、版面规则（`pub/layout.txt`）；仓库文档：`v2/README.md`、`docs/REPRODUCE.md`、`AGENTS.md`、`evidence/README.md`、`docs/experiment-index.md`
- [x] P6 全书构建、自动检查、逐页审查与修复：三轮逐页审查（234 → 226 → 217 页），34 幅示意图重画为手工布局的 SVG（`pub/diagram_defs.py`），图的字号检查 `pub/figcheck.py`，表格按内容定列宽，图文顺序检查进入 `pubcheck.py`；记录：[REVIEW.md](REVIEW.md)、[review/](review/)（检查点 `800c713`、`d4b771a`）
- [x] P7 出版与工程验收报告：[ACCEPTANCE.md](ACCEPTANCE.md)
- [x] P9 仓库整理（2026-11-13）：合并进 `main`；P2–P6 的改写脚本、v2.0.0 的 PDF 与其构建文件移入历史标签；其他分支删除（[../../../docs/REPOSITORY-CLEANUP.md](../../../docs/REPOSITORY-CLEANUP.md)）
- [x] P8 发布：`v2/publication` 的最终提交，带注释的标签 `v2.1.0`（未合并 `main`，未改动 `v1.0.0`、`v2.0.0`）

## 状态（2026-11-13）

**已完成。**出版版 PDF：217 页（封面 + 216），目录 329/329；全部自动检查 PASS；逐页终审无未处理的发现。验收结论、接受的风险与未验证的能力见 [ACCEPTANCE.md](ACCEPTANCE.md) 第 0 节。

之后若再修改教材：先改章节源文件或 `pub/` 下的构建文件，再按 ACCEPTANCE.md 第 11 节重新构建与核验。改动可能移动分页，所以要对照 `pub/layout-accepted-gaps.txt` 重跑版面检查，并对改动过的页重新逐页查看。

## 已知事项

- v2.0.0 的 PDF 不含练习答案附录（正文写着“参考答案见附录”，v2.0.0 验收报告也称附录在内）：出版版补入了附录 A（82 道练习的答案），并在 ACCEPTANCE.md 第 8 节中更正。
- OpenBao 密钥的外部备份：所有者接受风险，记为 `ACCEPTED_RISK`（不是 PASS）。
- 节点内存容量：所有者指示保留分析、不扩容，记为 `ACCEPTED_RISK`。证书与令牌：按运维清理报告中的日期轮换，本轮未轮换。
- 端到端独立复现没有做过；本轮没有启动实验环境（不重跑 E0–E12）。
