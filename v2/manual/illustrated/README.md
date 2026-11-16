# Enterprise Illustrated Edition

这套独立的中文教材源文件从订单业务和工程决策组织全部 13 章。历史 Publication Edition 保持原样。

构建（仓库根目录，Windows；不需要实验环境）：

```powershell
manual/.venv/Scripts/python.exe v2/manual/illustrated/build.py
```

源码基线：`510ec87a9f1b0756248e00f3b53d692ca27aeada`。依赖沿用 `manual/requirements.txt`、Pandoc、Microsoft Edge。`chapters/` 是可编辑正文；`sources.json` 登记源码节选、原图与历史观察，`presentation.py` 保存原行号对应的执行步骤、截图视窗及出版标注；`illustrations.py` 保存可维护的SVG生成源。既有数据图直接复用 `../figures/`；机制图重绘写入本版 `assets/`，历史原图不变。

构建产物：`../dist/Enterprise-Platform-SRE-Handbook-Vol2-Illustrated-Edition.pdf`。来源索引随 PDF 一起生成，也见本目录的 `SOURCES.md`。具体审查与限制见 `../../docs/illustrated/`。

最终精修版验收见 [REFINEMENT-QA.md](../../docs/illustrated/REFINEMENT-QA.md)，修改与页码对照见 [REFINEMENT-CHANGES.md](../../docs/illustrated/REFINEMENT-CHANGES.md)。[REPORT.md](../../docs/illustrated/REPORT.md)保留106页初版的历史审查记录，页码和数量以本轮QA为准。

生成前可用 `build.py --sources-only` 核对13章、真实源码、图表和截图来源。版面检查沿用 `manual/tools/layout_check.py`，传入本目录的 `layout-accepted-gaps.txt`；其中记录最终PDF已目视接受的留白及原因。修改排版后应重新渲染并复核页码。代码面板省略共同缩进但保留相对缩进，视觉续行用↳注明，可按原行号和来源逐字符重组核对。

精修工作先使用候选文件，验收后才替换正式PDF：

```powershell
manual/.venv/Scripts/python.exe v2/manual/illustrated/build.py --out C:/path/to/work/Illustrated-Edition-Candidate.pdf
```

精修验收阶段未推送GitHub；用户随后明确授权将全部最新修改经PR合入`main`，并删除其他分支。QA与计划中“未提交/未推送”指验收时状态，后续Git发布以PR和Git历史为准。原始PNG、Evidence、业务与基础设施均不改动，不启动实验环境。
