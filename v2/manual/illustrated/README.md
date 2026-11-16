# Enterprise Illustrated Edition

这套独立的中文教材源文件从订单业务和工程决策组织全部 13 章。历史 Publication Edition 保持原样。

构建（仓库根目录，Windows；不需要实验环境）：

```powershell
manual/.venv/Scripts/python.exe v2/manual/illustrated/build.py
```

源码基线：`510ec87a9f1b0756248e00f3b53d692ca27aeada`。依赖沿用 `manual/requirements.txt`、Pandoc、Microsoft Edge。`chapters/` 是可编辑正文；`sources.json` 是源码节选、真实截图与关键观察登记表；`illustrations.py` 保存新增机制图及教学修订图的可维护 SVG 生成源。既有数据图直接复用 `../figures/`；少量机制图的更正只写入本版 `assets/`，历史原图不变。

构建产物：`../dist/Enterprise-Platform-SRE-Handbook-Vol2-Illustrated-Edition.pdf`。来源索引随 PDF 一起生成，也见本目录的 `SOURCES.md`。具体审查与限制见 `../../docs/illustrated/`。
