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


# ---------------------------------------------------------------- chapter 5 (E4)
@fig("e4-hpa-timeline", 5, ["evidence/e4/hpa-timeline-collect.log"],
     check=("01:57:17", "02:02:43", "02:02:51", "02:04:27", "02:08:28", "5 分 26 秒", "8 秒"))
def _(out):
    timeline(out, "台阶到 120 迭代/秒：HPA 的一次扩容与缩容（秒，从负载升高起算）", [
        ("负载", [(0, 430, C["gray"], "120 迭代/秒（430 s）")]),
        ("HPA 的判断", [(0, 326, C["lorange"], "利用率 102%–114%：在 10% 的容差之内，不动"), (326, 334, C["red"], "")]),
        ("网关副本", [(0, 334, C["lblue"], "2 个"), (334, 671, C["blue"], "3 个"), (671, 720, C["lblue"], "2 个")]),
    ], xlim=(0, 740), xlabel="秒", events=[(326, "326 s：决定扩到 3 个", C["red"]), (334, "8 s 后就绪", C["blue"]),
                                          (671, "稳定窗口 300 s 后缩回", C["teal"])])


@fig("e4-new-pods", 5, ["evidence/e4/hpa-2-pods.log"],
     check=("| gateway-…-gm44w（原有） | 147 | 0.79 核 | 36.0 |", "| gateway-…-qhww7（原有） | 142 | 0.92 核 | 21.4 |",
            "| gateway-…-j72rh（02:19 扩出） | 0 | 0.01 核 | — |", "| gateway-…-d5j6r（02:21 扩出） | 0 | 0.01 核 | — |"))
def _(out):
    bar_chart(out, "扩容之后一分钟，四个网关 Pod 各自收到的请求（每秒）", ["原有的 Pod 1\nCPU 0.79 核", "原有的 Pod 2\nCPU 0.92 核", "02:19 扩出\nCPU 0.01 核", "02:21 扩出\nCPU 0.01 核"], [
        {"name": "请求/秒", "color": C["blue"], "vals": [147, 142, 0, 0]},
        {"name": "其中 5xx/秒", "color": C["red"], "vals": [36.0, 21.4, 0, 0]},
    ], ylabel="每秒", ylim=(0, 170), h=290)


@fig("e4-keda-oscillation", 5, ["evidence/e4/keda-steady.log"],
     check=("02:52:52", "02:53:11", "02:58:21", "02:58:36", "02:58:49", "03:03:45", "03:04:01", "03:04:15", "03:05:02"))
def _(out):
    pts = [(0, 1), (19, 3), (329, 1), (344, 3), (357, 5), (653, 1), (669, 2), (683, 4), (730, 4)]
    line_chart(out, "只按积压扩缩：恒定负载下通知服务的副本数", [
        {"name": "通知服务的副本数（只有积压触发器）", "color": C["orange"], "pts": pts, "step": True}],
        xlabel="负载升到 90 迭代/秒之后的秒数", ylabel="副本", xlim=(0, 740), ylim=(0, 5.6), yticks=[0, 1, 2, 3, 4, 5], h=280,
        hlines=[(3, C["teal"], "实际需要 3 个")],
        notes=[(329, 1, "积压消化完 → 300 s 后缩到 1", 14, -92, C["red"]), (653, 1, "又一次缩到 1", -84, -58, C["red"])])


@fig("e4-eviction", 5, ["evidence/e4/eviction-2/watch.txt"],
     check=("07:48:52", "07:51:44", "07:51:52", "07:56:26", "08:01:32", "776 MiB", "933 MiB"))
def _(out):
    timeline(out, "节点内存压力下的两次驱逐（秒，从 07:48:52 起算）", [
        ("burst-hog（Burstable，请求 64Mi）", [(0, 172, C["orange"], "每秒 +4 MiB，到 776 MiB")]),
        ("be-hog（BestEffort）", [(0, 190, C["lgray"], "160 MiB"), (190, 454, C["gray"], "每秒 +3 MiB，到 933 MiB")]),
        ("guaranteed（请求 = 限制）", [(0, 800, C["teal"], "80 MiB，始终运行")]),
        ("节点状态", [(180, 760, C["lred"], "MemoryPressure：拒绝新的 BestEffort Pod（580 s）")]),
    ], xlim=(0, 820), xlabel="秒", events=[(172, "驱逐 burst-hog", C["red"]), (454, "驱逐 be-hog", C["red"]), (760, "压力解除", C["teal"])])


@fig("e4-neighbor", 5, ["evidence/e4/noisy.log"],
     check=("| 没有消耗者 | 16.3 / 16.2 ms |", "| BestEffort 消耗者 | 17.6 / 16.6 ms |", "| Burstable 消耗者（请求 2 核） | 130.8 / 13.9 ms |"))
def _(out):
    bar_chart(out, "同一个节点上的 CPU 消耗者对网关 p50 的影响（ms）", ["没有消耗者", "BestEffort 的消耗者\n（没有 CPU 请求）", "Burstable 的消耗者\n（请求 2 核）"], [
        {"name": "与消耗者同节点的网关", "color": C["orange"], "vals": [16.3, 17.6, 130.8]},
        {"name": "其他节点上的网关", "color": C["teal"], "vals": [16.2, 16.6, 13.9]},
    ], ylabel="ms", ylim=(0, 150), h=290)


# ---------------------------------------------------------------- chapter 7 (E6)
@fig("e6-amplification", 7, ["evidence/e6/slow-resilient.log", "evidence/e6/slow-naive.log", "evidence/e6/errors-naive.log", "evidence/e6/errors-resilient-2.log"],
     check=("| 　每笔下单在 inventory 上的调用 | 0.05 | 1.04 |", "| 　每笔下单在 inventory 上的调用 | 0.07 | 5.56（inventory 每秒 44 个请求，稳态 7.9 个） |"))
def _(out):
    hbar_chart(out, "故障期间，每笔下单打到 inventory 的调用次数", [
        ("inventory 慢 1.5 秒 · resilient", 0.05, C["teal"], "0.05：熔断器打开，几乎不再调用"),
        ("inventory 慢 1.5 秒 · naive", 1.04, C["gray"], "1.04：每笔等到成功"),
        ("inventory 90% 返回 503 · resilient", 0.07, C["teal"], "0.07：预算与熔断封顶"),
        ("inventory 90% 返回 503 · naive", 5.56, C["red"], "5.56：重试风暴"),
    ], xlabel="每笔下单的调用次数（正常时约 1 次）", xlim=(0, 6.6), vline=(1, C["green"], "正常：1 次"))


@fig("e6-node-failure", 7, ["evidence/e6/node-1.log", "evidence/e6/node-2.log"],
     check=("| 10–320 s |", "| 47 s |", "| 331 s |", "| 约 345 s |", "| 410 s |", "| 全部请求的失败率 | 54% | 8.2% |",
            "约 55 秒（到端点移除为止）", "| 节点 NotReady | 47 s | 52 s |"))
def _(out):
    timeline(out, "冻结一个节点：两次实验中请求失败的时段（秒）", [
        ("第一次：waypoint 只有一个副本", [(0, 10, C["lorange"], ""), (10, 320, C["red"], "100% 的请求失败（唯一的 waypoint 在被冻结的节点上）"),
                                      (320, 345, C["lorange"], "")]),
        ("第二次：waypoint 两个副本、跨区", [(0, 55, C["orange"], "约 55 秒：到端点被移除为止")]),
        ("节点（两次相同）", [(0, 410, C["lgray"], "冻结"), (410, 440, C["lgreen"], "")]),
    ], xlim=(0, 450), xlabel="冻结节点之后的秒数",
        events=[(47, "47 s 节点 NotReady", C["gray"]), (331, "331 s 开始重建 Pod", C["blue"]), (410, "410 s 恢复 Ready", C["teal"])],
        legend=[("第一次：全部请求的 54% 失败", C["red"]), ("第二次：8.2%", C["orange"])])


# ---------------------------------------------------------------- chapter 8 (E7)
@fig("concept-rpo-rto", 8, [], kind="concept")
def _(out):
    timeline(out, "RPO 与 RTO：一次故障在时间轴上的两段代价", [
        ("数据", [(0, 150, C["lblue"], "已经在安全的地方：归档、备库"), (150, 200, C["red"], "RPO")]),
        ("服务", [(0, 200, C["lgreen"], "正常"), (200, 430, C["orange"], "RTO：发现 → 决定 → 恢复 → 验证"), (430, 520, C["lgreen"], "恢复")]),
    ], xlim=(0, 520), xlabel="时间 →", xfmt=lambda v: "", lane_h=40,
        events=[(150, "最后一份安全的副本", C["blue"]), (200, "故障发生", C["red"]), (430, "服务恢复", C["teal"])])


@fig("e7-failover", 8, ["evidence/e7/failover-results.md"],
     check=("27.2 s", "10.7 s、11.7 s、8.0 s、14.4 s", "| F1 | 强制删除主库 Pod | 26.9 s | 0 |", "78.0 s", "冻结后 73.7 s", "137.9 s",
            "**3017**", "直连旧主库的客户端 **7**"))
def _(out):
    T, R = C["teal"], C["red"]
    hbar_chart(out, "六种故障下写入中断的时长（秒）与丢失的已确认写入", [
        ("计划内切换（4 次）", 14.4, T, "8.0–14.4 s · 丢失 0"),
        ("F0 滚动更新中原地重启主库", 27.2, T, "27.2 s · 丢失 0"),
        ("F1 强制删除主库 Pod", 26.9, T, "26.9 s · 丢失 0"),
        ("F2 冻结主库所在节点", 78.0, C["orange"], "78.0 s · 直连旧主库的客户端丢 7 次"),
        ("F3 复制中断后失去主库（异步）", 73.7, R, "73.7 s · 丢失 3017 次"),
        ("F4 同 F3（同步复制）", 137.9, T, "137.9 s · 丢失 0"),
    ], xlabel="写入中断的秒数", xlim=(0, 150), legend=[("不丢数据", T), ("丢失已确认的写入", R)])


@fig("e7-rebuild", 8, ["evidence/e7/r1/results.md", "evidence/e7/r2/results.md"],
     check=("| 0–54 s | 集群被删除 |", "| 67–230 s |", "| 370 s |", "| 545 s |", "| 695–826 s |", "| 873–1093 s |", "| 1171 s |",
            "| **1205 s** |", "20.1 分钟", "15.3 分钟"))
def _(out):
    timeline(out, "整个集群删除之后的重建：第一次（R1）的时间线与第二次（R2）的总时长（秒）", [
        ("R1 基础", [(0, 54, C["gray"], ""), (67, 230, C["blue"], "新集群 + Argo CD")]),
        ("R1 从 Git 收敛", [(230, 1171, C["lblue"], "")]),
        ("R1 卡住的两段", [(370, 545, C["red"], "①"), (695, 826, C["red"], "②")]),
        ("R1 数据库", [(873, 1093, C["orange"], "从归档恢复")]),
        ("R2 修复之后", [(0, 918, C["teal"], "没有人工介入：15.3 分钟")]),
    ], xlim=(0, 1290), xlabel="删除集群之后的秒数",
        events=[(54, "集群已删除", C["gray"]), (1171, "1171 s 全部应用就绪", C["blue"]), (1205, "R1 第一笔订单 1205 s", C["teal"])])


# ---------------------------------------------------------------- chapter 9 (E8)
@fig("e8-canary", 9, ["evidence/e8/canary-results.md"], check=("20 001 个中 986 个 = 4.93%", "5.03%", "2.45%", "4.95%"))
def _(out):
    hbar_chart(out, "金丝雀权重 5%：设定值、两种测量，以及出故障时的影响面（占全部请求的 %）", [
        ("设定的权重", 5.0, C["gray"], "5%"),
        ("k6 统计：20 001 个请求中 986 个", 4.93, C["blue"], "4.93%"),
        ("Prometheus 统计（同一窗口）", 5.03, C["blue"], "5.03%"),
        ("金丝雀一半请求返回 503 时受影响的请求", 2.45, C["red"], "2.45% ≈ 权重 × 失败率"),
    ], xlabel="占全部公共请求的比例（%）", xlim=(0, 6.4))


# ---------------------------------------------------------------- chapter 10 (E9)
@fig("model-burnrate", 10, [], kind="model")
def _(out):
    b = 0.01   # checkout: 99 % -> 1 % budget
    fast = [(e / 100, 14.4 * b * 60 / (e / 100)) for e in range(15, 101)]
    slow = [(e / 100, 6 * b * 360 / (e / 100)) for e in range(6, 101)]
    line_chart(out, "下单的 SLO 为 99% 时：错误比例与呼叫之前要等的时间", [
        {"name": "1 小时 / 5 分钟窗口，燃烧率 > 14.4", "color": C["red"], "pts": fast},
        {"name": "6 小时 / 30 分钟窗口，燃烧率 > 6", "color": C["purple"], "pts": slow},
    ], xlabel="失败的请求占比", ylabel="分钟", xlim=(0, 1.0), ylim=(0, 380), h=310,
        xticks=[0.06, 0.144, 0.25, 0.5, 0.75, 1.0], xfmt=lambda v: f"{v * 100:g}%",
        notes=[(1.0, 8.64, "全部失败：8.6 分钟", -120, -46, C["red"]), (0.2, 43.2, "20% 失败：43 分钟", 40, -30, C["red"]),
               (0.144, 60, "低于 14.4%：这一组不会触发", 36, -74, C["red"]), (0.06, 360, "低于 6%：只剩工单", 44, 10, C["purple"])])


@fig("e9-incident", 10, ["evidence/e9/incident/timeline.log"],
     check=("08:23:40.7", "约 08:24:10", "08:26:18.5", "08:26:55.5", "08:28:04.6", "约 08:28:40", "+2 分 08 秒", "+37 秒",
            "呼叫后 69 秒", "恢复后 28.5 分钟"))
def _(out):
    timeline(out, "事故演练的时间线（秒，从合并请求 !37 合并起算）", [
        ("下单失败", [(29, 299, C["red"], "08:24:10 – 08:28:40：约 4.5 分钟")]),
        ("检测", [(29, 158, C["orange"], "2 分 08 秒：燃烧率越过呼叫线")]),
        ("升级", [(158, 195, C["purple"], "37 s 分组等待")]),
        ("响应", [(195, 264, C["blue"], "69 s：确认、定位、撤回")]),
        ("撤回生效", [(264, 299, C["teal"], "")]),
        ("告警未解除", [(299, 330, C["lgray"], "直到 08:57：恢复之后 28.5 分钟")]),
    ], xlim=(0, 330), xlabel="合并之后的秒数",
        events=[(0, "合并 !37", C["gray"]), (158, "呼叫", C["red"]), (195, "事故 #12", C["purple"]), (264, "撤回合并", C["teal"])])


@fig("e9-sampling", 10, ["evidence/e9/tracing-cost.log"], check=("28.9 个/秒", "291 个/秒", "3.4 个/秒", "29.9 个/秒（8.7 倍）", "0.393 核", "0.413 核"))
def _(out):
    bar_chart(out, "两种采样方式下的 span 流量（个/秒）", ["到达收集器", "写入 Tempo"], [
        {"name": "头部采样 10%", "color": C["gray"], "vals": [28.9, 3.4]},
        {"name": "100% 上报，由尾部采样决定", "color": C["teal"], "vals": [291, 29.9]},
    ], ylabel="span/秒", ylim=(0, 330), h=280)


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


# ---------------------------------------------------------------- chapter 12 (E11)
@fig("e11-alert-storm", 12, ["evidence/e11/incident-1.md", "evidence/e11/incident-1/recovery.log"],
     check=("54 个事故", "16 个应用 Degraded", "10 个任务失败", "27 个容器等待",
            "evidence/e11/incident-1/recovery.log::'OpenBaoSealed': 1, 'ArgoCDAppDegraded': 16, 'KubeJobFailed': 10",
            "evidence/e11/incident-1/recovery.log::'KubeContainerWaiting': 27"))
def _(out):
    bar_chart(out, "OpenBao 密封的 9 小时里，告警桥在 GitLab 中开出的事故（个）",
              ["OpenBaoSealed\n原因本身", "ArgoCDAppDegraded\n依赖它的应用", "KubeJobFailed\n每小时的快照任务", "KubeContainerWaiting\n任务的 Pod"], [
                  {"name": "", "color": C["orange"], "vals": [1, 16, 10, 27]}], ylabel="事故数", ylim=(0, 31), h=290,
              notes=[(0, 4.5, "1 个原因"), (2, 29.5, "53 个症状：每小时关闭一批，再打开一批")])


# ---------------------------------------------------------------- chapter 13 (E12)
@fig("e12-grading", 13, ["evidence/e12/t1.log", "evidence/e12/t2.log", "evidence/e12/t3.log", "evidence/e12/p1.log"],
     check=("| T1 | 0/3", "| T2 | 2/3", "| T3 | 2/4", "3/3，25 秒后", "4/4，7 秒后", "| 判分 | 3/8 | 8/8 |",
            "evidence/e12/t1.log::result: 0 passed, 3 failed -> FAIL", "evidence/e12/t2.log::result: 2 passed, 1 failed -> FAIL",
            "evidence/e12/t3.log::result: 2 passed, 2 failed -> FAIL", "evidence/e12/p1.log::result: 3 passed, 5 failed -> FAIL",
            "evidence/e12/p1.log::result: 8 passed, 0 failed -> PASS"))
def _(out):
    bar_chart(out, "四道题的判分：通过的检查项数", ["T1 仓库凭据\n共 3 项", "T2 OpenBao 密封\n共 3 项", "T3 Git 之外的策略\n共 4 项", "P1 告警抑制\n共 8 项"], [
        {"name": "故障存在时（应当 FAIL）", "color": C["red"], "vals": [0, 2, 2, 3]},
        {"name": "修复之后（应当 PASS）", "color": C["teal"], "vals": [3, 3, 4, 8]},
    ], ylabel="通过的检查项", ylim=(0, 9), yticks=[0, 2, 4, 6, 8], h=280)


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
