"""Generate v2/docs/experiment-index.md: every script of the platform, experiments and assessment with the purpose
stated in its own header comment. Regenerate after adding scripts:

  manual/.venv/Scripts/python.exe v2/docs/gen_experiment_index.py
"""
from __future__ import annotations

import re
from pathlib import Path

V2 = Path(__file__).resolve().parents[1]
STAGES = {
    "e0": "E0 平台基线（第 1 章）", "e1": "E1 多服务系统（第 2 章）", "e2": "E2 服务网格（第 3 章）", "e3": "E3 负载与容量（第 4 章）",
    "e4": "E4 弹性与调度（第 5 章）", "e5": "E5 多租户与安全（第 6 章）", "e6": "E6 故障注入（第 7 章）", "e7": "E7 数据可靠性（第 8 章）",
    "e8": "E8 发布治理（第 9 章）", "e9": "E9 可观测性（第 10 章）", "e10": "E10 大规模控制面（第 11 章）", "e11": "E11 IaC（第 12 章）",
    "ops-1": "v2.0.0 之后的运维清理", "load": "负载脚本（k6）",
}


def purpose(path: Path) -> str:
    """The first sentence of the header comment (after the shebang)."""
    lines = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines()[:14]:
        if line.startswith("#!") or line.strip() in ('"""', "'''"):
            continue
        m = re.match(r'^\s*(?:#|//|"""|\*)\s?(.*)$', line)
        if not m:
            if lines:
                break
            continue
        text = m.group(1).strip().strip('"')
        if not text:
            if lines:
                break
            continue
        lines.append(text)
        if text.endswith((".", ":", "。")):
            break
    text = " ".join(lines)
    return (text[:200].rsplit(" ", 1)[0] + " …") if len(text) > 200 else text      # cut between words, never inside a path


def table(files: list[Path]) -> str:
    rows = [f"| `{p.relative_to(V2).as_posix()}` | {purpose(p).replace('|', '/')} |" for p in files]
    return "| 脚本 | 用途（取自脚本自己的头部注释） |\n|---|---|\n" + "\n".join(rows) + "\n"


def scripts(d: Path) -> list[Path]:
    return sorted(p for p in d.rglob("*") if p.is_file() and p.suffix in (".sh", ".py", ".js") and "__pycache__" not in p.parts)


out = ["# 实验与脚本索引", "",
       "> 由 `v2/docs/gen_experiment_index.py` 生成：每一行的“用途”取自脚本自己的头部注释。路径相对于 `v2/`。",
       "> 每个阶段的假设、原始记录与结果在 `evidence/<阶段>/`；教材中的对应章节见括号。", ""]
out += ["## 平台（一次性搭建与日常操作）", "", table(scripts(V2 / "platform")), ""]
for d in sorted((V2 / "experiments").iterdir(), key=lambda p: (len(p.name), p.name)):
    if d.is_dir() and scripts(d):
        out += [f"## {STAGES.get(d.name, d.name)}", "", table(scripts(d)), ""]
out += ["## E11 基础设施即代码", "", table(scripts(V2 / "iac")), ""]
out += ["## E12 能力考核（第 13 章）", "", table(scripts(V2 / "assessment")), ""]
(V2 / "docs" / "experiment-index.md").write_text("\n".join(out), encoding="utf-8", newline="\n")
print(f"experiment-index.md: {sum(len(scripts(d)) for d in (V2 / 'platform', V2 / 'experiments', V2 / 'iac', V2 / 'assessment'))} scripts")
