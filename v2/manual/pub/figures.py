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


# ---------------------------------------------------------------- chapter 1 (E0)
@fig("e0-memory-lines", 1, ["evidence/e0/baseline.log"], check=("2666 MiB", "2922 MiB", "3072 MiB", "12720"))
def _(out):
    timeline(out, "一个工作节点的三条内存线（MiB）", [
        ("节点内存", [(0, 2666, C["lblue"], "可分配 allocatable：Pod 的 requests 之和不能超过它"),
                    (2666, 2922, C["lorange"], ""), (2922, 3072, C["lred"], "")]),
    ], xlim=(0, 4300), xlabel="节点容器的内存（MiB）", lane_h=44, xticks=[0, 500, 1000, 1500, 2000, 2500, 3000],
        events=[(2666, "2666 调度器的上限", C["blue"]), (2922, "2922 kubelet 开始驱逐", C["orange"]),
                (3072, "3072 内核 OOM", C["red"])],
        legend=[("可分配", C["lblue"]), ("kube-reserved 256", C["lorange"]), ("驱逐到 OOM 之间的 150", C["lred"])])


# ---------------------------------------------------------------- chapter 2 (E1)
@fig("e1-convergence", 2, ["evidence/e1/converge.log"], check=("t+161 s", "t+188 s", "t+261 s", "t+698 s", "t+735 s", "437 秒"))
def _(out):
    B = C["blue"]
    timeline(out, "第一次从 Git 收敛：同步波次的时间线（秒）", [
        ("波次 −3　监控栈", [(0, 161, B, "161 s")]),
        ("波次 −2　数据库运营商", [(161, 188, B, "27 s")]),
        ("波次 −1　Tempo · Loki · NATS · Valkey", [(188, 261, B, "73 s")]),
        ("波次 0　PostgreSQL 集群", [(261, 698, C["orange"], "437 s：等三个实例依次就绪")]),
        ("波次 1　六个服务", [(698, 735, C["teal"], "37 s")]),
    ], xlim=(0, 780), xlabel="根应用开始同步之后的秒数", events=[(735, "735 s：15 个应用全部 Synced + Healthy", C["teal"])])


# ---------------------------------------------------------------- chapter 3 (E2)
@fig("e2-distribution", 3, ["evidence/e2/mode-none.log", "evidence/e2/mode-ambient-l4.log", "evidence/e2/mode-ambient-l7.log"],
     check=("14.4% / 85.6%", "57.8% / 42.2%", "50.0% / 50.0%", "53.5% / 46.5%", "50.7% / 49.3%", "49.4% / 50.6%",
            "87.4% / 12.6%", "11.2% / 88.8%", "46.9% / 53.1%", "97.1% / 2.9%", "97.2% / 2.8%", "49.7% / 50.3%",
            "86.7% / 13.3%", "15.0% / 85.0%", "48.2% / 51.8%"))
def _(out):
    bar_chart(out, "较忙的那个副本承担的请求比例（%）：三种模式", ["catalog", "gateway", "orders", "inventory", "payments"], [
        {"name": "无网格", "color": C["gray"], "vals": [85.6, 53.5, 87.4, 97.1, 86.7]},
        {"name": "ambient L4（只有 ztunnel）", "color": C["orange"], "vals": [57.8, 50.7, 88.8, 97.2, 85.0]},
        {"name": "ambient L7（经过 waypoint）", "color": C["teal"], "vals": [50.0, 50.6, 53.1, 50.3, 51.8]},
    ], ylabel="%", ylim=(0, 112), yticks=[0, 25, 50, 75, 100], hlines=[(50, C["green"], "完全均匀 50%")], h=310)


@fig("e2-ab", 3, ["evidence/e2/mode-none.log", "evidence/e2/mode-ambient-l4.log", "evidence/e2/ab-mesh.log"],
     check=("| 浏览 p50 / p95 | 10.8 / 19.2 ms | 14.8 / 27.7 ms |", "| 下单 p50 / p95 | 106.0 / 225.0 ms | 138.4 / 253.4 ms |",
            "| 1 | 无网格 | 12.8 | 23.0 | 122.4 | 249.5 |", "| 1 | ambient | 15.5 | 29.6 | 139.2 | 254.9 |",
            "| 2 | 无网格 | 13.0 | 22.5 | 126.2 | 234.6 |", "| 2 | ambient | 15.4 | 29.9 | 131.6 | 258.4 |",
            "| 3 | 无网格 | 12.4 | 22.6 | 124.0 | 230.1 |", "| 3 | ambient | 14.5 | 24.6 | 123.4 | 226.5 |"))
def _(out):
    none = [(10.8, 106.0), (12.8, 122.4), (13.0, 126.2), (12.4, 124.0)]
    amb = [(14.8, 138.4), (15.5, 139.2), (15.4, 131.6), (14.5, 123.4)]
    sign = lambda v: f"{v:+.1f}"
    bar_chart(out, "ambient 相对无网格的 p50 差值（ms）：一次对比与三轮交替", ["第一次：各跑一次\n相隔 15 分钟", "交替 第 1 轮", "交替 第 2 轮", "交替 第 3 轮"], [
        {"name": "浏览 p50 的差", "color": C["blue"], "vals": [round(a[0] - n[0], 1) for n, a in zip(none, amb)]},
        {"name": "下单 p50 的差", "color": C["orange"], "vals": [round(a[1] - n[1], 1) for n, a in zip(none, amb)]},
    ], ylabel="ms", ylim=(-6, 38), yticks=[0, 10, 20, 30], vfmt=sign, h=310)


# ---------------------------------------------------------------- chapter 4 (E3)
@fig("model-mm1", 4, [], kind="model")
def _(out):
    pts = [(u / 100, 1 / (1 - u / 100)) for u in range(0, 97)]
    line_chart(out, "排队模型：响应时间 R = S / (1 − U)", [{"name": "", "color": C["purple"], "pts": pts}],
               xlabel="利用率 U", ylabel="响应时间（服务时间 S 的倍数）", xlim=(0, 1), ylim=(0, 26), h=290,
               xticks=[0, 0.25, 0.5, 0.75, 0.9, 1.0], xfmt=lambda v: f"{v * 100:.0f}%", yfmt=lambda v: f"{v:.0f}×",
               notes=[(0.5, 2, "50%：2 倍", -20, -30, C["purple"]), (0.8, 5, "80%：5 倍", -40, -30, C["purple"]),
                      (0.9, 10, "90%：10 倍", -52, -24, C["purple"]), (0.95, 20, "95%：20 倍", -60, -12, C["purple"])])


@fig("e3-cpu-prediction", 4, ["evidence/e3/capacity-prediction.md", "evidence/e3/step-ramp-high.log"],
     check=("0.289 / 0.33 核", "0.366 / 0.44 核", "0.480 / 0.55 核", "0.607 / 0.66 核", "0.583 / 0.77 核", "0.801 / 0.89 核",
            "0.938 / 0.95 核", "0.533 核（熔断）", "172 迭代/秒"))
def _(out):
    x = [60, 80, 100, 120, 140, 160, 180]
    line_chart(out, "最忙的网关 Pod 的 CPU：实验前的预测与实测", [
        {"name": "预测（实验前提交）", "color": C["gray"], "pts": list(zip(x, [0.33, 0.44, 0.55, 0.66, 0.77, 0.89, 0.95])), "dash": "6 4"},
        {"name": "实测", "color": C["blue"], "pts": list(zip(x + [200], [0.289, 0.366, 0.480, 0.607, 0.583, 0.801, 0.938, 0.533])), "marker": True},
    ], xlabel="负载（迭代/秒）", ylabel="CPU（核）", xlim=(50, 210), ylim=(0, 1.12), yticks=[0, 0.25, 0.5, 0.75, 1.0], h=310,
        xticks=[60, 80, 100, 120, 140, 160, 180, 200], hlines=[(1.0, C["red"], "单线程的上限：1 核")],
        vlines=[(172, C["gray"], "预测的饱和点 172")],
        notes=[(180, 0.938, "180：0.938 核，开始失败", -70, 46, C["blue"]), (200, 0.533, "200：熔断打开，CPU 反而下降", -110, 38, C["red"])])


@fig("e3-latency-knee", 4, ["evidence/e3/step-ramp-high.log"],
     check=("51.0 ms", "26.2 ms", "29.8 ms", "39.5 ms", "36.1 ms", "81.4 ms", "1.18 s", "1.66 s", "13.6%", "33.2%"))
def _(out):
    x = [60, 80, 100, 120, 140, 160, 180, 200]
    line_chart(out, "同一次阶梯负载的浏览 p95：拐点", [
        {"name": "浏览 p95（ms）", "color": C["orange"], "pts": list(zip(x, [51.0, 26.2, 29.8, 39.5, 36.1, 81.4, 1180, 1660])), "marker": True},
    ], xlabel="负载（迭代/秒）", ylabel="ms", xlim=(50, 210), ylim=(0, 1900), h=280, xticks=x,
        vlines=[(172, C["gray"], "预测的饱和点 172")],
        notes=[(160, 81.4, "160 以内：26–81 ms", -60, -40, C["orange"]), (180, 1180, "180：1.18 s，失败率 13.6%", -150, -10, C["orange"]),
               (200, 1660, "200：1.66 s，失败率 33.2%", -160, 8, C["red"])])


@fig("e3-profile", 4, ["evidence/e3/profile-gil-60-summary.log"], check=("32.2%", "19.1%", "16.7%", "13.7%", "3.7%", "3.4%"))
def _(out):
    hbar_chart(out, "网关持有 GIL 的 CPU 时间花在哪里（%）", [
        ("HTTP 客户端（httpx、httpcore、h11）", 32.2, C["blue"], "32.2%"),
        ("Web 框架（FastAPI、Starlette、Pydantic）", 19.1, C["blue"], "19.1%"),
        ("OpenTelemetry 插桩 + SDK", 16.7, C["blue"], "16.7%"),
        ("HTTP 服务器（uvicorn）+ 事件循环", 13.7, C["blue"], "13.7%"),
        ("我们自己的代码", 3.7, C["red"], "3.7%"),
        ("失败的 import（后来修复）", 3.4, C["orange"], "3.4%"),
    ], xlabel="占采样的比例（%）", xlim=(0, 36))


@fig("e3-caller-queue", 4, ["evidence/e3/one-replica-2-analysis.log"],
     check=("| 80 | 0.62 核 | 10.6 ms | 2.2 ms |", "| 100 | 0.76 核 | 13.2 ms | 2.3 ms |", "| 110 | 0.96 核 | 635 ms | 3.3 ms |",
            "| 120 | 0.96 核 | 630 ms | 2.8 ms |"))
def _(out):
    bar_chart(out, "同一次 catalog 调用的两种耗时（ms）：调用方看到的与被调用方自己的", ["80 迭代/秒\n网关 0.62 核", "100\n0.76 核", "110\n0.96 核", "120\n0.96 核"], [
        {"name": "网关看到的调用耗时", "color": C["orange"], "vals": [10.6, 13.2, 635, 630]},
        {"name": "catalog 自己的处理时间", "color": C["teal"], "vals": [2.2, 2.3, 3.3, 2.8]},
    ], ylabel="ms", ylim=(0, 720), h=300)


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
        hlines=[(1536, C["blue"], "上限 1536"), (2560, C["red"], "上限 2560")],
        bands=[(10, 75, "#fdf3e7", "")],
        notes=[(13.8, 1487, "4 秒内 938 → 1487，被杀", -8, 150, C["blue"]),
               (22, 2437, "3 个并发 LIST：2437 MiB", -30, -34, C["red"]),
               (29.5, 2552, "2552：被杀 1 次", 26, -18, C["red"]),
               (61.7, 2004, "重启后 1.6–2.0 GiB", -6, 120, C["red"])])


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
