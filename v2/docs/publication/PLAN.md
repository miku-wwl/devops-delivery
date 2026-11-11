# Publication Edition：出版方案与进度

> 分支 `v2/publication`（从 `v2/enterprise` @ 7a41a89 分出）。`v1.0.0`、`v2.0.0` 标签、v2.0.0 的 PDF 与全部原始证据不改动。
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
| 改写记录 | 每章的改动由脚本完成并留存 | `v2/manual/pub/tools/` |
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
- [ ] P4 第 9–13 章
- [ ] P5 阅读指南、术语表；仓库文档（README、复现指南、Agent 说明、证据索引）
- [ ] P6 全书构建、自动检查、逐页审查与修复（记录：`REVIEW.md`）
- [ ] P7 独立出版与工程验收报告（`ACCEPTANCE.md`），最终提交

## 已知事项

- v2.0.0 的 PDF 不含练习答案附录（正文写着“参考答案见附录”，v2.0.0 验收报告也称附录在内）——出版版补入附录 A，并在验收报告中更正。
- OpenBao 密钥的外部备份：所有者接受风险，记为 `ACCEPTED_RISK`（不是 PASS）。
