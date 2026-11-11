"""Charts of the Publication Edition, drawn from the lab's measurements.

  manual/.venv/Scripts/python.exe v2/manual/pub/figures.py            # write v2/manual/figures/*.svg
  manual/.venv/Scripts/python.exe v2/manual/pub/figures.py --check    # verify the numbers, print the provenance

Every figure is registered with its sources. Two kinds of provenance:
  parsed  - the series are read from an evidence file when the figure is built (time series);
  quoted  - the numbers are typed here; `check` lists strings that must be present in the chapter (default) or in
            an evidence file ("evidence/...::string"). The chapter's own numbers are held to the evidence by the
            spot checks (v2/manual/spot-checks.json), so a chart cannot drift from the text or from the records.
Model curves (class "model") plot a formula, not a measurement; they say so in their tag and caption.
"""
from __future__ import annotations

import sys
from pathlib import Path

PUB = Path(__file__).resolve().parent
MAN = PUB.parent
V2 = MAN.parent
FIG = MAN / "figures"
sys.path.insert(0, str(PUB))
from charts import C, bar_chart, hbar_chart, line_chart, timeline  # noqa: E402

FIGS: list[dict] = []
CHAPTERS = sorted((MAN / "chapters").glob("*.md"))


def fig(name: str, chapter: int, sources: list[str], check: tuple[str, ...] = (), kind: str = "quoted"):
    def deco(fn):
        FIGS.append({"name": name, "chapter": chapter, "sources": sources, "check": check, "kind": kind, "fn": fn})
        return fn
    return deco


def ev(rel: str) -> Path:
    return V2 / rel


def rows(rel: str, skip: int = 1) -> list[list[str]]:
    return [l.split() for l in ev(rel).read_text(encoding="utf-8").splitlines()[skip:] if l.strip()]


# ---------------------------------------------------------------- chapter 11 (E10)
@fig("e10-scheduling", 11, ["evidence/e10/k1/timeline.txt", "evidence/e10/k2/timeline.txt"], kind="parsed",
     check=("51.3 秒", "193.0 秒", "29.4 秒", "48.6 秒", "每秒 50.3 个"))
def _(out):
    k1 = [(float(t), float(r)) for t, _, _, r in rows("evidence/e10/k1/timeline.txt")]
    k2 = [(float(t), float(r)) for t, _, _, r in rows("evidence/e10/k2/timeline.txt")]
    line_chart(out, "一万个虚拟 Pod 进入 Running：默认限速与放开限速", [
        {"name": "K1 默认限速（调度器每秒 50 次请求）", "color": C["blue"], "pts": k1, "marker": True},
        {"name": "K2 放开限速", "color": C["orange"], "pts": k2 + [(200, 10000)], "marker": False},
        {"name": "每秒 50 个的参考斜率", "color": C["gray"], "pts": [(54.5, 3661), (181.3, 10000)], "dash": "5 4", "sw": 1.3},
    ], xlabel="创建开始后的秒数", ylabel="Running 的 Pod", xlim=(0, 200), ylim=(0, 10800),
        vlines=[(51.3, C["blue"], "K1 创建完成 51.3 s")],
        notes=[(120, 6775, "直线：每秒 50.3 个 = 客户端限速", 16, 38, C["blue"]),
               (48.6, 10000, "K2 全部 Running 48.6 s（29.4 s 已全部调度）", 22, 30, C["orange"]),
               (193, 10000, "K1 193.0 s", -30, 34, C["blue"])])


@fig("e10-etcd", 11, ["evidence/e10/k3-clean.log", "evidence/e10/k3-etcd.log"],
     check=("92.5 MiB", "172.7 MiB", "178.6 MiB", "24.3 MiB", "18.7 MiB"))
def _(out):
    bar_chart(out, "删除 10 000 个 Pod：etcd 的文件与其中的有效数据（MiB）",
              ["10 000 个 Pod", "全部删除之后", "API server 压缩之后", "碎片整理之后"], [
                  {"name": "数据库文件大小", "color": C["gray"], "vals": [92.5, 172.7, 178.6, 18.7]},
                  {"name": "其中的有效数据", "color": C["teal"], "vals": [92.5, 172.7, 24.3, 18.7]},
              ], ylabel="MiB", ylim=(0, 210), h=300,
              notes=[(1, 197, "删除先让它变大：+80 MiB"), (2, 197, "压缩：数据少了，文件没变"), (3, 44, "整理：文件才变小")])


@fig("e10-apiserver-memory", 11, ["evidence/e10/k8/apf-apiserver-mem.txt", "evidence/e10/k9/apf-apiserver-mem.txt"], kind="parsed",
     check=("1536 MiB", "2560 MiB", "2437 MiB", "2552 MiB", "938 MiB", "1487 MiB"))
def _(out):
    r6 = [(float(t), float(a)) for t, _, a in rows("evidence/e10/k8/apf-apiserver-mem.txt")]
    r7 = [(float(t), float(a)) for t, _, a in rows("evidence/e10/k9/apf-apiserver-mem.txt")]
    line_chart(out, "洪水期间 API server 的匿名内存（每秒采样）：3 个席位，两种内存上限", [
        {"name": "第 6a 次运行：上限 1536 MiB", "color": C["blue"], "pts": r6},
        {"name": "第 7 次运行：上限 2560 MiB", "color": C["red"], "pts": r7},
    ], xlabel="秒（洪水在第 10 秒左右开始）", ylabel="MiB", xlim=(0, 75), ylim=(0, 2800), h=350,
        hlines=[(1536, C["blue"], "上限 1536 MiB"), (2560, C["red"], "上限 2560 MiB")],
        bands=[(10, 75, "#fdf3e7", "")],
        notes=[(13.8, 1487, "4 秒内 938 → 1487，被杀", 44, -30, C["blue"]),
               (24, 2437, "3 个并发 LIST：停在 2437 MiB", 22, 44, C["red"]),
               (29.5, 2552, "2552 MiB：被杀 1 次", 60, 40, C["red"]),
               (60, 2004, "重启后同样的洪水下 1.6–2.0 GiB", -30, 66, C["red"])])


@fig("e10-k5-runs", 11, ["evidence/e10/scale-results.md"],
     check=("42.8 ms → 10.4 s", "40.1 ms → 2081 ms", "19.4 ms → 219 ms", "19.4 ms → 1800 ms", "15.6 ms → 1387 ms",
            "20.7 ms → 437 ms", "14.7 ms → 1540 ms", "20.3 ms → 194 ms", "被杀 6 次", "被杀 4 次", "被杀 5 次", "被杀 1 次"))
def _(out):
    R, B = C["red"], C["orange"]
    hbar_chart(out, "K5 的七次运行：洪水期间受害者成功请求的 p99（毫秒，对数刻度）", [
        ("1  原始设计，无内存上限 · 虚拟机冻结", 10400, R, "10.4 s（安静时 42.8 ms）"),
        ("2  加内存上限，但 APF 被关闭 · 被杀 8 次", 2081, B, "2081 ms（40.1 ms）"),
        ("3  APF 开启，1536 MiB · 被杀 6 次", 219, B, "219 ms（19.4 ms）"),
        ("4  加 GOMEMLIMIT · 被杀 4 次", 1800, B, "1800 ms（19.4 ms）"),
        ("5  Pod 减半 · 被杀 8 次", 1387, B, "1387 ms（15.6 ms）"),
        ("6a 借用上限为 0，3 个席位 · 被杀 5 次", 437, B, "437 ms（20.7 ms）"),
        ("6b 不限借用，7 个席位 · 被杀 8 次", 1540, B, "1540 ms（14.7 ms）"),
        ("7  3 个席位，2560 MiB · 被杀 1 次", 194, C["teal"], "194 ms（20.3 ms）"),
    ], xlabel="受害者 GET 的 p99，毫秒；假设 K5 的目标线是安静值的 2 倍（约 40 ms）", xlim=(10, 30000), log=True,
        vline=(40, C["green"], "目标：不超过安静值的 2 倍"))


# ---------------------------------------------------------------- build and check
def generate() -> int:
    FIG.mkdir(parents=True, exist_ok=True)
    for f in FIGS:
        f["fn"](FIG / f"{f['name']}.svg")
    return len(FIGS)


def check() -> int:
    bad = 0
    for f in FIGS:
        chapter = CHAPTERS[f["chapter"] - 1].read_text(encoding="utf-8")
        missing = []
        for src in f["sources"]:
            if not ev(src).exists():
                missing.append(f"source missing: {src}")
        for item in f["check"]:
            if "::" in item:
                path, needle = item.split("::", 1)
                if needle not in ev(path).read_text(encoding="utf-8"):
                    missing.append(f"not in {path}: {needle}")
            elif item not in chapter:
                missing.append(f"not in chapter {f['chapter']}: {item}")
        used = f"../figures/{f['name']}.svg" in chapter
        if not used:
            missing.append("figure not used in its chapter")
        bad += bool(missing)
        print(f"{'FAIL' if missing else 'ok  '} {f['name']:26} ch{f['chapter']:<2} {f['kind']:6} checks {len(f['check']):2}  "
              f"sources: {', '.join(f['sources'])}" + "".join(f"\n       {m}" for m in missing))
    print(f"RESULT: {'FAIL' if bad else 'PASS'} - {len(FIGS)} figure(s), {sum(len(f['check']) for f in FIGS)} quoted value(s) checked, "
          f"{sum(f['kind'] == 'parsed' for f in FIGS)} parsed from evidence")
    return 1 if bad else 0


if __name__ == "__main__":
    n = generate()
    print(f"{n} figure(s) -> {FIG}")
    if "--check" in sys.argv:
        sys.exit(check())
