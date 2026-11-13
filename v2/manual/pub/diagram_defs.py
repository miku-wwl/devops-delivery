"""The book's mechanism diagrams, laid out by hand on the 640 px canvas of diagrams.py.

Each diagram is registered like a chart (figreg.fig): the chapter that uses it and, where it shows numbers, the
strings that must also be present in the chapter text or in an evidence file. Diagrams named concept-* carry the
tag "示意图"; the others show measured numbers and carry the tag "实测数据".
"""
from __future__ import annotations

from charts import C
from diagrams import Diagram, sequence
from figreg import fig

BLUE, TEAL, ORANGE, RED, MUTED = C["blue"], C["teal"], C["orange"], C["red"], C["muted"]


# ================================================================== chapter 1 (E0)
@fig("concept-env-nesting", 1, ["evidence/e0/host.log"], kind="concept",
     check=("evidence/e0/host.log::33.6 GB = 31.3 GiB", "evidence/e0/host.log::cores=8; logical=16", "15.28 GiB",
            "| ent-control-plane | — | 0-3 | 0、1 | 不限 |", "| ent-worker | zone-a | 4-7 | 2、3 | 3 GiB |",
            "| ent-worker2 | zone-b | 8-11 | 4、5 | 3 GiB |", "| ent-worker3 | zone-c | 12-15 | 6、7 | 3 GiB |"))
def _(out):
    d = Diagram(304)
    d.group(8, 6, 624, 292, "Windows 11　31.3 GiB 内存，8 核 16 线程", "zone")
    d.group(20, 30, 600, 258, "WSL2 虚拟机 devops-lab　15.28 GiB，16 个 vCPU（Windows 的 16 个线程）", "cool")
    d.group(32, 54, 576, 224, "Docker：下面每一个框都是一个容器，共用虚拟机的内核", "zone2")
    xs = [42, 183, 324, 465]
    d.group(xs[0], 78, 133, 134, None, "zone")
    d.text(xs[0] + 66.5, 94, "ent-control-plane", 9.5, "#1b2430", "middle", "600")
    d.text(xs[0] + 66.5, 107, "CPU 0-3 · 内存不限", 9.5, "#46525f", "middle")
    d.box(xs[0] + 8, 116, 117, 86, ["控制面", "etcd", "kube-apiserver", "scheduler", "controller-manager"], "real", size=10, lh=14)
    zones = [("ent-worker", "zone-a", "CPU 4-7 · 3 GiB"), ("ent-worker2", "zone-b", "CPU 8-11 · 3 GiB"),
             ("ent-worker3", "zone-c", "CPU 12-15 · 3 GiB")]
    for x, (name, zone, res) in zip(xs[1:], zones):
        d.group(x, 78, 133, 134, None, "zone")
        d.text(x + 66.5, 94, f"{name} · {zone}", 9.5, "#1b2430", "middle", "600")
        d.text(x + 66.5, 107, res, 9.5, "#46525f", "middle")
        k = d.box(x + 8, 116, 117, 34, ["kubelet · containerd"], "real", size=10, bold=False)
        p1 = d.box(x + 8, 166, 55, 36, ["Pod"], "good", size=10, bold=False)
        p2 = d.box(x + 70, 166, 55, 36, ["Pod"], "good", size=10, bold=False)
        d.edge(k, p1, src=("b", 0.25), dst="t")
        d.edge(k, p2, src=("b", 0.75), dst="t")
    d.box(42, 224, 556, 42, ["同一个 Docker 里的其他容器", "GitLab · Runner · 镜像仓库与拉取缓存 · 负载均衡器（envoy）"], "ext", size=10)
    d.save(out)


@fig("concept-kubelet-capacity", 1, ["evidence/e0/baseline.log"], kind="concept", check=("15642", "3072 MiB"))
def _(out):
    d = Diagram(196)
    d.text(10, 16, "kubelet 以为的", 10, MUTED, weight="600")
    y, h, w, g = 26, 54, 114, 14
    x = [10 + i * (w + g) for i in range(5)]
    a = d.box(x[0], y, w, h, ["/proc/meminfo", "MemTotal 15642 MiB", "整台虚拟机"], "ghost", size=10)
    b = d.box(x[1], y, w, h, ["cAdvisor", "读取 MemTotal"], "plain", size=10)
    k = d.box(x[2], y, w, h, ["kubelet", "capacity =", "15642 MiB"], "real", size=10)
    al = d.box(x[3], y, w, h, ["allocatable", "capacity − 预留", "− 驱逐阈值"], "real", size=10)
    s = d.box(x[4], y, w, h, ["调度器", "按 allocatable", "放 Pod"], "real", size=10)
    for p, q in ((a, b), (b, k), (k, al), (al, s)):
        d.edge(p, q)
    d.text(10, 122, "内核执行的", 10, MUTED, weight="600")
    cg = d.box(x[1] + 30, 132, 190, 54, ["节点容器的 cgroup", "memory.max = 3072 MiB"], "bad", size=10)
    oom = d.box(x[3] + 40, 132, 204, 54, ["内核 OOM killer", "用量到 3072 MiB 就杀进程"], "bad", size=10)
    d.edge(cg, oom)
    d.edge(cg, k, src=("t", (k.cx - cg.x) / cg.w), dst="b", style="dash", color=RED)
    d.cross(k.cx, 108)
    d.text(k.cx + 14, 111.5, "kubelet 不读它", 9.5, RED, weight="600")
    d.save(out)


# ================================================================== chapter 2 (E1)
@fig("concept-saga", 2, [], kind="concept")
def _(out):
    sequence(out, ["顾客\n（k6）", "gateway", "orders", ("orders\n数据库", "store"), "catalog", "inventory", ("payments\n[模拟]", "sim")], [
        ("msg", 0, 1, "POST /api/orders（带 Idempotency-Key）"),
        ("msg", 1, 2, "POST /orders"),
        ("msg", 2, 3, "INSERT 订单 PENDING（占用幂等键）"),
        ("msg", 2, 4, "GET /products/…（每个商品一次，并行）"),
        ("msg", 2, 5, "POST /reservations（预留库存）"),
        ("msg", 2, 6, "POST /charges（Idempotency-Key = 订单号）"),
        ("band", "支付失败，或结果无法确定：补偿", "bad"),
        ("msg", 2, 5, "POST /reservations/{id}/release（释放库存）"),
        ("end",),
        ("band", "支付成功", "good"),
        ("msg", 2, 3, "一个事务：订单 CONFIRMED + outbox 事件"),
        ("end",),
        ("msg", 2, 1, "201", "reply"),
        ("msg", 1, 0, "201", "reply"),
    ], number=True, margin=46)


@fig("concept-outbox", 2, [], kind="concept", check=("200 ms", "2 分钟"))
def _(out):
    d = Diagram(226)
    d.group(10, 12, 214, 96, "orders：一个数据库事务", "zone")
    d.box(18, 38, 96, 60, ["UPDATE orders", "status =", "CONFIRMED"], "real", size=10)
    d.box(120, 38, 96, 60, ["INSERT INTO", "outbox", "事件 + trace 上下文"], "real", size=10)
    ob = d.box(346, 30, 90, 62, ["outbox 表"], "store", "cyl")
    d.edge((224, 61), ob, "COMMIT\n要么都在，要么都不在", dst="l")
    rl = d.box(506, 34, 124, 54, ["中继 relay", "每 200 ms 读一批", "FOR UPDATE SKIP LOCKED"], "real", size=10)
    d.edge(ob, rl, "未发布的事件", src=("r", 0.32), dst=("l", 0.3))
    d.edge(rl, ob, "标记已发布", src=("l", 0.74), dst=("r", 0.7), style="dash", lp=(470, 90))
    nats = d.box(506, 152, 124, 56, ["NATS JetStream", "2 分钟去重窗口"], "store", size=10)
    d.edge(rl, nats, "发布\nNats-Msg-Id = 事件 ID", la="end", lp=(560, 116))
    no = d.box(318, 152, 124, 56, ["notifier", "按事件 ID 再去重"], "real", size=10)
    d.edge(nats, no, "投递")
    d.box(10, 144, 262, 70, ["任何一处崩溃，重来一遍都安全", "不丢：事件和订单在同一个事务里提交",
                              "不重：中继在“发布”与“标记”之间崩溃会重发，", "NATS 和 notifier 各去重一次"], "note", size=10, lh=14)
    d.save(out)


@fig("concept-storefront", 2, [], kind="concept")
def _(out):
    d = Diagram(292)
    y = 52
    k6 = d.box(8, y, 48, 40, ["k6", "主机"], "ghost", size=10)
    lb = d.box(70, y, 86, 40, ["LoadBalancer", "envoy · 集群外"], "ext", size=10)
    gw = d.box(172, y, 68, 40, ["gateway"], "real")
    ca = d.box(266, y, 76, 40, ["catalog"], "real")
    od = d.box(368, y, 76, 40, ["orders"], "real")
    iv = d.box(470, y, 76, 40, ["inventory"], "real")
    pa = d.box(562, y, 72, 40, ["payments", "[模拟] 支付方"], "sim", size=10)
    d.edge(k6, lb)
    d.edge(lb, gw)
    d.edge(gw, ca)
    d.edge(gw, od, src=("t", 0.7), dst=("t", 0.3), via=[(gw.x + gw.w * 0.7, 26), (od.x + od.w * 0.3, 26)])
    d.edge(od, ca)
    d.edge(od, iv)
    d.edge(od, pa, src=("t", 0.7), dst="t", via=[(od.x + od.w * 0.7, 26), (pa.cx, 26)])
    d.text(320, 18, "同步调用：都在一次请求的路径上", 9.5, MUTED, "middle")
    # each service owns its data
    v0 = d.box(222, 132, 76, 44, ["Valkey db0", "缓存"], "store", "cyl", size=10)
    p1 = d.box(304, 132, 78, 44, ["PostgreSQL", "catalog 库"], "store", "cyl", size=10)
    p2 = d.box(468, 132, 80, 44, ["PostgreSQL", "inventory 库"], "store", "cyl", size=10)
    v1 = d.box(558, 132, 76, 44, ["Valkey db1", "幂等记录"], "store", "cyl", size=10)
    d.edge(ca, v0, src=("b", 0.3), dst="t")
    d.edge(ca, p1, src=("b", 0.7), dst=("t", 0.35))
    d.edge(iv, p2, src="b", dst="t")
    d.edge(pa, v1, src="b", dst="t")
    p3 = d.box(352, 216, 108, 48, ["PostgreSQL", "orders 库 + outbox"], "store", "cyl", size=10)
    d.edge(od, p3, src="b", dst="t")
    na = d.box(214, 218, 106, 44, ["NATS JetStream", "流 ORDERS"], "store", size=10)
    no = d.box(112, 218, 72, 44, ["notifier"], "real")
    v2 = d.box(10, 218, 74, 44, ["Valkey db2", "去重"], "store", "cyl", size=10)
    d.edge(p3, na, "中继", style="dash")
    d.edge(na, no, style="dash")
    d.edge(no, v2)
    d.text(10, 282, "实线：同步调用　　虚线：订单确认之后的异步通知（事务性 outbox → NATS）　　圆柱：每个服务只访问自己的数据", 9.5, MUTED)
    d.save(out)


@fig("concept-app-of-apps", 2, [], kind="concept")
def _(out):
    d = Diagram(236)
    bs = d.box(10, 22, 138, 62, ["bootstrap.sh", "安装 Argo CD", "应用 root.yaml"], "dark", size=10)
    gl = d.box(10, 146, 138, 62, ["GitLab", "platform-gitops"], "store", "cyl", size=10)
    root = d.box(206, 86, 112, 56, ["根应用", "platform-root"], "real")
    d.edge(bs, root, "手工，只做一次", src="r", dst=("t", 0.4), lp=(232, 46))
    d.edge(gl, root, "指向仓库里的一个目录", src="r", dst=("b", 0.4), lp=(238, 190))
    waves = ["波次 −3　监控栈", "波次 −2　数据库运营商", "波次 −1　Tempo · Loki · NATS · Valkey", "波次 0　PostgreSQL 集群"]
    for i, name in enumerate(waves):
        b = d.box(376, 10 + i * 44, 254, 34, [name], "real", size=10, bold=False)
        d.edge(root, b, src="r", dst="l", mid=346)
    aset = d.box(376, 186, 128, 40, ["波次 1", "ApplicationSet"], "real", size=10)
    d.edge(root, aset, src="r", dst="l", mid=346)
    sv = d.box(528, 186, 102, 40, ["6 个服务应用", "各有一个值文件"], "good", size=10)
    d.edge(aset, sv)
    d.save(out)


# ================================================================== chapter 3 (E2)
@fig("concept-ambient-path", 3, [], kind="concept", check=("15008",))
def _(out):
    d = Diagram(184)
    d.group(10, 10, 196, 164, "节点 ent-worker", "zone")
    a = d.box(22, 36, 172, 44, ["gateway Pod", "应用进程，没有 sidecar"], "real", size=10)
    z1 = d.box(22, 118, 172, 44, ["ztunnel", "节点代理，第 4 层"], "store", size=10)
    d.edge(a, z1, "Pod 内重定向")
    d.group(434, 10, 196, 164, "节点 ent-worker2", "zone")
    b = d.box(446, 36, 172, 44, ["orders Pod"], "real")
    z2 = d.box(446, 118, 172, 44, ["ztunnel"], "store")
    d.edge(z2, b)
    wp = d.box(248, 22, 144, 50, ["waypoint（Envoy，第 7 层）", "可选：按命名空间或服务"], "sim", size=10)
    d.edge(z1, wp, src=("r", 0.3), dst="l", via=[(226, 131.2), (226, 47)], sw=2.6, color=TEAL)
    d.edge(wp, z2, src="r", dst=("l", 0.3), via=[(414, 47), (414, 131.2)], sw=2.6, color=TEAL)
    d.text(320, 98, "HBONE 隧道（粗线）", 9.5, "#0b4f48", "middle", "600")
    d.text(320, 111, "mTLS + HTTP/2 CONNECT，端口 15008", 9.5, "#0b4f48", "middle")
    d.edge(z1, z2, "不用 waypoint 时，ztunnel 之间直接相连", src=("r", 0.78), dst=("l", 0.78), style="dash", lp=(320, 166))
    d.save(out)


@fig("concept-l4-l7", 3, ["evidence/e2/mode-none.log", "evidence/e2/mode-ambient-l7.log"], kind="concept",
     check=("| inventory | 97.1% / 2.9% | 97.2% / 2.8% | 49.7% / 50.3% |",))
def _(out):
    d = Diagram(178)
    d.group(8, 8, 306, 162, "L4（kube-proxy、ztunnel）：连接建立时选一次", "warm")
    c1 = d.box(18, 68, 78, 48, ["调用方", "2 条长连接"], "real", size=10)
    a1 = d.box(226, 36, 78, 44, ["副本 A", "约 97%"], "bad", size=10)
    b1 = d.box(226, 114, 78, 44, ["副本 B", "约 3%"], "ghost", size=10)
    d.edge(c1, a1, "连接 1：之后的全部请求", src=("r", 0.25), dst=("l", 0.3), via=[(110, 80), (110, 49.2)], sw=2.4, color=RED, lp=(165, 44))
    d.edge(c1, a1, "连接 2 也落在 A", src=("r", 0.6), dst=("l", 0.75), via=[(126, 96.8), (126, 69)], sw=2.4, color=RED, lp=(176, 88))
    d.edge(c1, b1, "没有连接", src=("r", 0.9), dst="l", via=[(110, 111.2), (110, 136)], style="dot", head=False, lp=(165, 131))
    d.group(326, 8, 306, 162, "L7（waypoint）：为每个请求选一次", "cool")
    c2 = d.box(336, 68, 52, 48, ["调用方"], "real")
    wp = d.box(404, 40, 84, 104, ["waypoint", "终止 HTTP", "最少请求", "算法"], "sim", size=10)
    a2 = d.box(560, 40, 64, 44, ["副本 A", "约 50%"], "good", size=10)
    b2 = d.box(560, 100, 64, 44, ["副本 B", "约 50%"], "good", size=10)
    d.edge(c2, wp, sw=2.4, color=TEAL)
    d.edge((488, 62), a2, "请求 1、3、5…", dst="l")
    d.edge((488, 122), b2, "请求 2、4、6…", dst="l")
    d.save(out)


@fig("e2-retry-stack", 3, ["evidence/e2/retry-matrix.log"], check=("7 次尝试", "28 次", "4 倍"))
def _(out):
    d = Diagram(116)
    o = d.box(10, 24, 150, 52, ["orders", "应用层：重试 + 重试预算"], "real", size=10)
    w = d.box(245, 24, 150, 52, ["waypoint", "HTTPRoute：重试 3 次"], "sim", size=10)
    p = d.box(480, 24, 150, 52, ["payments", "正在返回 503"], "bad", size=10)
    d.edge(o, w, "7 次尝试")
    d.edge(w, p, "7 × 4 = 28 次", sw=3, color=RED, lcolor=RED)
    d.text(85, 96, "以为只发出了 7 次", 9.5, MUTED, "middle")
    d.text(320, 96, "每次尝试 1 次 + 重试 3 次 = 4 次调用，应用看不见", 9.5, MUTED, "middle")
    d.text(555, 96, "实际收到 28 次：4 倍", 9.5, RED, "middle", "600")
    d.save(out)


# ================================================================== chapter 5 (E4)
@fig("concept-hpa-loop", 5, [], kind="concept", check=("每 15 秒", "300 秒", "10%"))
def _(out):
    d = Diagram(232)
    p = d.box(10, 16, 180, 52, ["Pod 的 CPU 用量", "kubelet / cAdvisor 采集"], "real", size=10)
    ms = d.box(262, 16, 106, 52, ["metrics-server"], "real")
    h = d.box(440, 8, 190, 68, ["HPA 控制器", "期望副本 = 当前副本 ×", "当前指标 ÷ 目标", "比值与 1 相差 10% 以内：不动"], "real", size=10, lh=13.5)
    d.edge(p, ms, "每 15 秒汇总")
    d.edge(ms, h, "每 15 秒读取")
    dp = d.box(460, 168, 150, 52, ["Deployment", "改副本数"], "real", size=10)
    d.edge(h, dp, "扩容：立即\n缩容：等稳定窗口 300 秒", src=("b", 0.5), dst="t", la="end", lp=(527, 112))
    s = d.box(244, 168, 160, 52, ["新 Pod", "调度 → 拉镜像 → 启动 → 就绪"], "real", size=10)
    e = d.box(10, 168, 180, 52, ["Service 端点", "负载均衡器开始转发"], "real", size=10)
    d.edge(dp, s)
    d.edge(s, e)
    d.edge(e, p, "新 Pod 分担负载，\n利用率下降", src="t", dst="b", style="dash", color=TEAL, lp=(108, 112), la="start")
    d.box(214, 96, 196, 46, ["回路里没有一环知道：", "请求是否真的分到了新 Pod"], "note", size=10, bold=False)
    d.save(out)


@fig("concept-eviction-order", 5, ["evidence/e4/eviction-2.log"], kind="concept",
     check=("776 MiB", "712 MiB", "160 MiB", "64Mi", "128Mi"))
def _(out):
    d = Diagram(188)
    t = d.box(10, 44, 118, 52, ["memory.available", "低于驱逐阈值"], "bad", size=10)
    q = d.box(160, 26, 136, 88, ["用量超出", "内存请求了吗？"], "plain", "diamond", bold=False)
    d.edge(t, q)
    a = d.box(352, 12, 132, 62, ["burst-hog", "请求 64Mi，用 776 MiB", "超出 712 MiB：第一个"], "bad", size=10)
    b = d.box(504, 12, 128, 62, ["be-hog", "请求 0，用 160 MiB", "超出 160 MiB：第二个"], "sim", size=10)
    d.edge(q, a, "是", src="r", dst=("l", 0.5), via=[(322, 70), (322, 43)], lp=(310, 62))
    d.edge(a, b)
    d.text(492, 92, "超出请求的一组先被驱逐：组内先看优先级，再看超出了多少", 9.5, MUTED, "middle")
    g = d.box(352, 122, 132, 52, ["guaranteed", "请求 128Mi，用 80 MiB"], "good", size=10)
    d.edge(q, g, "否", src="b", dst="l", lp=(240, 142))
    d.text(492, 152, "没有超出请求：最后才轮到", 9.5, MUTED, "start")
    d.save(out)


# ================================================================== chapter 6 (E5)
@fig("concept-tenant-fences", 6, [], kind="concept")
def _(out):
    d = Diagram(262)
    r = d.box(10, 10, 190, 60, ["RBAC：谁能改什么", "角色、绑定、委派授权", "实验 1–3"], "real", size=10)
    a = d.box(225, 10, 190, 60, ["准入：什么样的对象能进来", "Pod Security · Kyverno · 配额", "实验 5"], "real", size=10)
    n = d.box(440, 10, 190, 60, ["网络策略：能和谁通信", "默认拒绝，显式放行", "实验 4"], "real", size=10)
    box = d.group(210, 100, 220, 74, "租户命名空间（shop-dev、insight）", "cool", anchor="middle")
    d.box(250, 124, 140, 38, ["团队的 Pod 与对象"], "good", bold=False)
    s = d.box(10, 192, 190, 60, ["外部密钥：秘密从哪里来", "OpenBao + External Secrets", "实验 7"], "real", size=10)
    g = d.box(440, 192, 190, 60, ["Argo CD 项目：能往哪里部署", "目的地与仓库的白名单", "实验 6"], "real", size=10)
    d.edge(r, box, src="b", dst=("l", 0.3))
    d.edge(a, box, src="b", dst="t")
    d.edge(n, box, src="b", dst=("r", 0.3))
    d.edge(s, box, src="t", dst=("l", 0.72))
    d.edge(g, box, src="t", dst=("r", 0.72))
    lg = d.box(225, 204, 190, 48, ["审计日志：谁、何时、做了什么", "不拦任何东西，事后回答　实验 3"], "note", size=10)
    d.edge(box, lg, src="b", dst="t", style="dash")
    d.save(out)


@fig("concept-api-request", 6, [], kind="concept")
def _(out):
    d = Diagram(178)
    y, h = 14, 78
    u = d.box(10, y, 76, h, ["请求", "kubectl", "控制器", "Argo CD"], "ghost", size=10)
    au = d.box(102, y, 86, h, ["认证", "你是谁？", "证书 · 令牌", "OIDC"], "real", size=10)
    az = d.box(204, y, 96, h, ["授权（RBAC）", "动作允许吗？", "只有“允许”", "没有“拒绝”"], "real", size=10)
    ma = d.box(316, y, 86, h, ["修改型准入", "补上默认值", "LimitRange"], "real", size=10)
    va = d.box(418, y, 142, h, ["校验型准入", "对象合规吗？", "Pod Security · Kyverno", "ValidatingAdmissionPolicy"], "real", size=10)
    e = d.box(576, y + 8, 54, h - 16, ["etcd"], "store", "cyl")
    for p, q in ((u, au), (au, az), (az, ma), (ma, va), (va, e)):
        d.edge(p, q)
    lg = d.box(102, 132, 458, 34, ["审计日志：每一步的结果都记下来，包括被拒绝的请求"], "note", size=10, bold=False)
    for b in (au, az, va):
        d.edge(b, (b.cx, 132), style="dash")
    d.save(out)


@fig("concept-netpol-mesh", 6, [], kind="concept", check=("15008", "8080"))
def _(out):
    d = Diagram(232)
    d.group(8, 8, 624, 126, "没有 waypoint：应用以为自己在访问 8080，线上是到 15008 端口的隧道", "zone")
    c1 = d.box(20, 36, 100, 40, ["客户端 Pod"], "real")
    z1 = d.box(160, 36, 90, 40, ["ztunnel"], "store")
    s1 = d.box(500, 32, 120, 90, ["服务端 Pod", "应用端口 8080"], "real", size=10)
    d.edge(c1, z1)
    d.edge(z1, (500, 56), "HBONE，目的端口 15008：策略必须放行 15008", src="r", sw=2.6, color=TEAL)
    x = d.box(160, 86, 130, 36, ["网格外的客户端"], "ghost", bold=False)
    d.edge(x, (500, 104), "直接到 8080：经典规则只对它生效", src="r")
    d.group(8, 144, 624, 80, "有 waypoint：到达服务端的连接来自 waypoint，不是客户端", "zone")
    c2 = d.box(20, 172, 100, 40, ["客户端 Pod"], "real")
    w = d.box(266, 172, 110, 40, ["waypoint"], "sim")
    s2 = d.box(500, 172, 120, 40, ["服务端 Pod"], "real")
    d.edge(c2, w, "15008", sw=2.6, color=TEAL)
    d.edge(w, s2, "15008，来源是 waypoint", sw=2.6, color=TEAL)
    d.save(out)


@fig("e5-secret-rotation", 6, ["evidence/e5/secrets.log"], check=("8 秒", "61 秒", "30 秒"))
def _(out):
    d = Diagram(198)
    ob = d.box(10, 44, 112, 66, ["OpenBao", "写入新值"], "store", "cyl", size=10)
    ks = d.box(276, 49, 130, 56, ["Kubernetes Secret", "8 秒内更新"], "real", size=10)
    d.edge(ob, ks, "External Secrets\n每 30 秒刷新")
    f = d.box(510, 10, 120, 56, ["挂载的文件", "61 秒后更新"], "good", size=10)
    ev = d.box(510, 104, 120, 56, ["环境变量", "旧值，直到 Pod 重启"], "bad", size=10)
    d.edge(ks, f, src=("r", 0.3), dst="l", mid=458)
    d.text(458, 28, "kubelet 定期同步", 9.5, MUTED, "middle")
    d.edge(ks, ev, src=("r", 0.7), dst="l", mid=458, style="dash")
    d.text(458, 148, "只在容器启动时读取", 9.5, MUTED, "middle")
    sa = d.box(10, 146, 190, 44, ["服务账号 secrets-reader", "只能读本租户的路径"], "ghost", size=10)
    d.edge(sa, ob, "Kubernetes 认证", src=("t", 0.3), dst="b", style="dash")
    d.save(out)


# ================================================================== chapter 7 (E6)
@fig("concept-resilience", 7, [], kind="concept", check=("64", "20%", "30 秒"))
def _(out):
    d = Diagram(206)
    c = d.box(10, 28, 76, 50, ["调用方", "例如 orders"], "real", size=10)
    bh = d.box(110, 14, 126, 78, ["隔舱", "在途调用太多了吗？", "上限 64"], "real", size=10)
    cb = d.box(260, 14, 126, 78, ["熔断器", "对方最近一直失败吗？", "是：立即拒绝"], "real", size=10)
    to = d.box(410, 14, 126, 78, ["超时与截止时间", "这一次最多等多久？", "1 秒，且不超过", "上游的剩余时间"], "real", size=10, lh=13.5)
    t = d.box(560, 28, 72, 50, ["被调用方", "inventory"], "bad", size=10)
    for p, q in ((c, bh), (bh, cb), (cb, to), (to, t)):
        d.edge(p, q)
    rt = d.box(404, 136, 180, 56, ["重试 + 重试预算", "值得再试吗？", "重试总量不超过 20%"], "sim", size=10)
    d.edge(t, rt, "失败或超时", src="b", dst="r", style="dash", lp=(589, 114), la="end")
    d.edge(rt, cb, "带抖动的退避\n之后再试", src="l", dst="b", style="dash", lp=(331, 126), la="start")
    d.box(10, 128, 260, 64, ["naive 模式（本章的对照）", "去掉隔舱、熔断器和重试预算，", "超时放宽到 30 秒，失败立即重试 3 次"], "note", size=10)
    d.save(out)


@fig("concept-partition", 7, [], kind="concept")
def _(out):
    d = Diagram(244)
    cp = d.box(150, 10, 340, 48, ["控制面", "心跳照常到达：节点全部 Ready，端点一个也没有移除"], "real", size=10)
    d.group(10, 96, 250, 118, "zone-a（ent-worker，被隔离）", "warm")
    wa = d.box(30, 128, 210, 66, ["zone-a 上的 Pod", "storefront 的服务", "waypoint 的一个副本"], "real", size=10)
    d.group(380, 96, 250, 118, "zone-b、zone-c", "zone")
    zb = d.box(400, 128, 210, 66, ["其他节点", "ztunnel 与 Pod"], "real", size=10)
    d.edge((135, 96), (235, 58), "kubelet 心跳", via=[(135, 76), (235, 76)], color=TEAL, lp=(128, 80), la="end", lcolor="#0b4f48")
    d.edge((505, 96), (405, 58), "kubelet 心跳", via=[(505, 76), (405, 76)], color=TEAL, lp=(512, 80), la="start", lcolor="#0b4f48")
    d.edge((260, 146), (380, 146), head=False, sw=2.2, color="#8a94a3")
    d.cross(320, 146)
    d.text(320, 122, "iptables 丢弃", 9.5, C["red"], "middle", "600")
    d.text(320, 134, "节点间的全部流量", 9.5, C["red"], "middle", "600")
    d.edge(zb, wa, src=("l", 0.86), dst=("r", 0.86), style="dash")
    d.text(320, 232, "新连接仍有一部分发往 zone-a：超时。能发现问题的，只有发起连接的一方", 9.5, MUTED, "middle")
    d.save(out)


# ================================================================== chapter 8 (E7)
@fig("concept-commit-paths", 8, [], kind="concept")
def _(out):
    sequence(out, ["客户端", "主库", "备库"], [
        ("band", "异步复制：先回答客户端，再发送 WAL", "warm"),
        ("msg", 0, 1, "COMMIT"),
        ("self", 1, "写入本地 WAL"),
        ("msg", 1, 0, "成功", "reply"),
        ("msg", 1, 2, "稍后发送 WAL：落后的这一段，主库失效时就丢了", "async"),
        ("end",),
        ("band", "同步复制（ANY 1）：一个备库落盘之后才回答", "cool"),
        ("msg", 0, 1, "COMMIT"),
        ("self", 1, "写入本地 WAL"),
        ("msg", 1, 2, "发送 WAL"),
        ("msg", 2, 1, "已落盘", "reply"),
        ("msg", 1, 0, "成功：至少一个备库也持有这次写入", "reply"),
        ("end",),
    ], margin=110)


@fig("concept-wal-pitr", 8, [], kind="concept", check=("16 MiB", "5 分钟"))
def _(out):
    d = Diagram(196)
    d.text(140, 16, "平时：连续归档", 10, MUTED, "middle", "600")
    d.text(500, 16, "恢复时：时间点恢复", 10, MUTED, "middle", "600")
    p = d.box(10, 36, 110, 64, ["主库 pg-main"], "real")
    s = d.box(276, 26, 136, 84, ["集群外的对象存储", "基础备份 + WAL 归档"], "store", "cyl", size=10)
    n = d.box(526, 36, 104, 64, ["新的", "PostgreSQL 集群"], "good", size=10.5, bold=False)
    d.edge((120, 55), (276, 55), "WAL 段：写满 16 MiB\n或最迟每 5 分钟")
    d.edge((120, 84), (276, 84))
    d.text(198, 100, "每晚一份基础备份", 9.5, MUTED, "middle")
    d.edge((412, 55), (526, 55), "① 最近的基础备份")
    d.edge((412, 84), (526, 84))
    d.text(469, 100, "② 重放 WAL 到目标时刻", 9.5, MUTED, "middle")
    x = d.box(10, 140, 262, 46, ["尚未归档的 WAL 尾部", "整个集群丢失时，丢掉的就是这一段（RPO）"], "bad", size=10)
    d.edge(p, x, src=("b", 0.5), dst=("t", 0.21), style="dash")
    d.save(out)


# ================================================================== chapter 9 (E8)
@fig("concept-canary-routes", 9, [], kind="concept")
def _(out):
    d = Diagram(176)
    u = d.box(10, 22, 110, 44, ["公共请求"], "real")
    t = d.box(10, 106, 110, 50, ["测试人员", "带预览请求头"], "ghost", size=10)
    gw = d.box(196, 54, 132, 68, ["入口 Gateway", "HTTPRoute", "两条规则"], "real", size=10)
    cn = d.box(500, 14, 130, 56, ["金丝雀版本", "gateway-canary"], "sim", size=10)
    st = d.box(500, 110, 130, 56, ["稳定版本", "gateway"], "good", size=10)
    d.edge(u, gw, src="r", dst=("l", 0.3), mid=158)
    d.edge(t, gw, src="r", dst=("l", 0.7), mid=158, style="dash")
    d.edge((328, 66), (500, 30), "规则 1：带预览头 → 100%", via=[(392, 66), (392, 30)], style="dash", lp=(436, 25))
    d.edge((328, 88), (500, 54), "规则 2：权重 5", via=[(414, 88), (414, 54)], lp=(457, 64), la="middle")
    d.edge((328, 110), (500, 138), "规则 2：权重 95", via=[(414, 110), (414, 138)], sw=2.6, color=TEAL, lp=(457, 133))
    d.save(out)


@fig("concept-freeze-keys", 9, [], kind="concept")
def _(out):
    d = Diagram(196)
    mr = d.box(8, 34, 70, 46, ["合并请求"], "real")
    k1 = d.box(100, 12, 160, 90, ["钥匙一：合并之前", "流水线里的冻结检查", "冻结期只放行 [emergency]"], "sim", size=10)
    m = d.box(284, 34, 62, 46, ["main", "分支"], "real", size=10)
    k2 = d.box(370, 12, 160, 90, ["钥匙二：合并之后", "Argo CD 的同步窗口", "deny 窗口内不自动同步"], "sim", size=10)
    c = d.box(572, 34, 60, 46, ["集群"], "good")
    d.edge(mr, k1)
    d.edge(k1, m)
    d.edge(m, k2)
    d.edge(k2, c)
    d.text(632, 100, "窗口结束，或有权限的", 9.5, MUTED, "end")
    d.text(632, 113, "人手动同步之后", 9.5, MUTED, "end")
    x1 = d.box(100, 142, 160, 44, ["被拒绝", "普通改动：流水线失败，不能合并"], "bad", size=10)
    w = d.box(370, 142, 160, 44, ["等待", "已合并，但在窗口内不生效"], "ghost", size=10)
    d.edge(k1, x1, "不通过", style="dash")
    d.edge(k2, w, "窗口内", style="dash")
    d.save(out)


@fig("concept-release-path", 9, [], kind="concept", check=("405", "每 60 秒"))
def _(out):
    d = Diagram(238)
    d.group(8, 8, 624, 102, "合并之前：GitLab", "zone")
    dev = d.box(20, 38, 100, 54, ["开发者 alice", "Developer"], "real", size=10)
    ci = d.box(196, 32, 184, 66, ["流水线", "渲染 · 发布策略（Kyverno CLI）", "冻结检查"], "real", size=10)
    main = d.box(506, 26, 114, 34, ["main（配置仓库）"], "good", size=10, bold=False)
    keep = d.box(506, 68, 114, 34, ["main 不变"], "bad", size=10, bold=False)
    d.edge(dev, ci, "合并请求")
    d.edge((380, 43), main, "通过：Maintainer 合并", dst="l")
    d.edge((380, 85), keep, "失败：拒绝合并（405）", dst="l", style="dash")
    d.group(8, 142, 624, 88, "合并之后：集群", "zone")
    argo = d.box(20, 168, 132, 52, ["Argo CD", "项目边界 · 同步窗口"], "real", size=10)
    k8s = d.box(262, 168, 120, 52, ["Kubernetes", "RBAC · 准入策略"], "real", size=10)
    nt = d.box(418, 168, 76, 52, ["Argo CD", "通知"], "real", size=10)
    dep = d.box(520, 162, 104, 64, ["GitLab 部署记录", "Deployments API", "→ DORA 指标"], "store", size=10)
    d.edge((124, 110), argo, "Argo CD 每 60 秒轮询 main", dst=("t", 0.79))
    d.edge(argo, k8s, "以项目的部署账号写入")
    d.edge(k8s, nt)
    d.edge(nt, dep)
    d.save(out)


@fig("concept-impersonation", 9, ["evidence/e8/impersonation-results.md"], kind="concept",
     check=("Deployment、Service、ServiceAccount、PDB、HPA、ScaledObject、ServiceMonitor", "Deployment、Service、ExternalSecret"))
def _(out):
    d = Diagram(238)
    ctl = d.box(10, 78, 186, 80, ["argocd-application-controller", "只负责冒用；", "自己只写 Argo CD 的对象"], "real", size=10)
    rows = [("项目 root", ["argocd:argocd-root", "只能写 Application、ApplicationSet、AppProject"], "real", "solid"),
            ("项目 platform", ["argocd:argocd-platform", "cluster-admin：Operator、CRD、集群级对象"], "sim", "solid"),
            ("项目 storefront", ["storefront:argocd-storefront", "只能写发布用到的 7 种对象"], "real", "solid"),
            ("项目 insight", ["insight:argocd-insight", "只能写 3 种对象"], "real", "solid"),
            ("项目 default", ["没有账号", "放在这个项目里的应用无法同步"], "ghost", "dash")]
    for i, (label, lines, kind, style) in enumerate(rows):
        b = d.box(336, 6 + i * 46, 294, 40, lines, kind, size=10)
        d.edge((196, 118), b, label, dst="l", via=[(226, 118), (226, b.cy)], style=style, lp=(281, b.cy - 5))
    d.save(out)


@fig("e8-waves", 9, ["evidence/e8/waves-results.md"],
     check=("evidence/e8/waves-results.md::0 - 68 | 10 - 162", "evidence/e8/waves-results.md::68 - 311 (external-secrets) | 162 - 308",
            "evidence/e8/waves-results.md::438 - 616 (178 s) | 308 - 538 (230 s)", "evidence/e8/waves-results.md::616 - 692 | 543 - 636",
            "692 秒", "636 s", "130 秒"))
def _(out):
    from charts import timeline
    B, L = C["blue"], C["lblue"]
    timeline(out, "根应用第一次同步之后的时间线（秒）：R2 的 11 个波次与 R4 的 9 个波次", [
        ("R2", [(0, 68, B, "Istio"), (68, 311, B, "Operator（−3 波）"), (311, 438, L, "−2、−1 波"),
                (438, 616, C["orange"], "pg-main 恢复 178 s"), (616, 692, C["teal"], "storefront")]),
        ("R4", [(10, 162, B, "Istio"), (162, 308, B, "Operator"),
                (308, 538, C["orange"], "pg-main 恢复 230 s"), (543, 636, C["teal"], "storefront")]),
        ("R4（其余）", [(308, 543, L, "同一波（−2）的其余应用")]),
    ], xlim=(0, 770), xlabel="根应用第一次同步之后的秒数", lane_h=34, xticks=[0, 100, 200, 300, 400, 500, 600, 700],
        events=[(438, "R2：438 s 才开始恢复", C["orange"]), (308, "R4：308 s，早 130 s", C["orange"]),
                (692, "R2 692", C["muted"]), (636, "R4 636", C["teal"])])


# ================================================================== chapter 10 (E9)
@fig("concept-alert-chain", 10, [], kind="concept", check=("每 30 秒", "180 秒"))
def _(out):
    d = Diagram(170)
    d.group(8, 8, 292, 112, "集群（被监控的故障域）", "zone")
    pr = d.box(18, 36, 142, 72, ["Prometheus", "规则：平台告警、", "SLO 燃烧率、症状"], "real", size=10)
    am = d.box(182, 36, 108, 72, ["Alertmanager", "路由、分组、抑制"], "real", size=10)
    d.edge(pr, am)
    d.group(408, 8, 224, 112, "集群之外", "cool")
    br = d.box(418, 36, 92, 72, ["告警桥", "alert-bridge", "（容器）"], "real", size=10)
    gl = d.box(528, 36, 96, 72, ["GitLab", "root/incidents", "critical → 事故", "warning → 工单"], "store", size=10, lh=13.5)
    d.edge(br, gl)
    d.edge((290, 56), (418, 56), "告警的 webhook")
    d.edge((290, 90), (418, 90), style="dash", color=TEAL)
    d.text(354, 104, "Watchdog 心跳", 9.5, "#0b4f48", "middle")
    d.text(354, 117, "每 30 秒", 9.5, "#0b4f48", "middle")
    d.text(632, 142, "180 秒收不到心跳：告警桥自己开出一个事故（死人开关）", 9.5, MUTED, "end")
    d.text(10, 142, "这里的一切都可能和被监控的对象一起倒下", 9.5, MUTED)
    d.save(out)


@fig("concept-sampling", 10, [], kind="concept", check=("10 秒", "10%", "1 秒"))
def _(out):
    d = Diagram(222)
    d.group(8, 8, 624, 98, "头部采样 10%：请求开始时决定——那时还不知道它会不会出错", "warm")
    s1 = d.box(20, 36, 100, 58, ["服务的 SDK"], "real")
    c1 = d.box(316, 32, 90, 32, ["收集器"], "real")
    t1 = d.box(524, 26, 96, 46, ["Tempo"], "store", "cyl")
    x1 = d.box(316, 70, 90, 28, ["丢弃"], "bad", bold=False)
    d.edge((120, 48), c1, "10% 的链路", dst="l")
    d.edge(c1, (524, 48), src="r")
    d.edge((120, 84), x1, "90%：连同其中出错的请求", dst="l", style="dash")
    d.group(8, 114, 624, 100, "100% 上报 + 尾部采样：整条链路结束之后决定", "cool")
    s2 = d.box(20, 142, 100, 60, ["服务的 SDK"], "real")
    c2 = d.box(216, 138, 190, 68, ["收集器（尾部采样）", "等 10 秒，看完整条链路", "出错或慢于 1 秒：全留；其余留 10%"], "real", size=10)
    t2 = d.box(524, 136, 96, 46, ["Tempo"], "store", "cyl")
    x2 = d.box(452, 184, 60, 24, ["丢弃"], "ghost", bold=False)
    d.edge(s2, c2, "全部链路")
    d.edge((406, 160), (524, 160), "保留的链路")
    d.edge((406, 196), x2, dst="l", style="dash")
    d.save(out)


# ================================================================== chapter 11 (E10)
@fig("concept-kwok-env", 11, ["experiments/e10/scale.sh"], kind="concept",
     check=("experiments/e10/scale.sh::kube-apiserver:${APISERVER_MEM:-1536m} etcd:512m kube-controller-manager:512m kube-scheduler:768m",
            "experiments/e10/scale.sh::prometheus:384m", "v1.37.0", "1000 个节点", "10 000 个 Pod"))
def _(out):
    d = Diagram(262)
    d.group(8, 8, 624, 246, "同一个 WSL 虚拟机", "zone")
    ent = d.box(20, 38, 150, 56, ["实验集群 ent [真实]", "前十章的平台", "照常运行"], "real", size=10)
    cli = d.box(20, 126, 150, 52, ["实验客户端 [注入]", "kubectl 与 curl"], "inject", size=10)
    d.group(190, 32, 430, 156, "kwokctl 集群 scale：Kubernetes v1.37.0 的容器，各有内存上限 [真实]", "zone2")
    sch = d.box(200, 58, 98, 44, ["kube-scheduler", "768 MiB"], "real", size=10)
    kcm = d.box(306, 58, 112, 44, ["controller-manager", "512 MiB"], "real", size=10)
    kw = d.box(426, 58, 90, 44, ["kwok 控制器", "代替 kubelet"], "virt", size=10)
    pr = d.box(524, 58, 88, 44, ["Prometheus", "384 MiB"], "real", size=10)
    api = d.box(270, 128, 150, 48, ["kube-apiserver", "1536 MiB"], "real", size=10)
    etcd = d.box(486, 125, 110, 54, ["etcd", "512 MiB"], "store", "cyl", size=10)
    for b, f in ((sch, 0.2), (kcm, 0.45), (kw, 0.7)):
        d.edge(b, api, src="b", dst=("t", f), mid=116)
    d.edge(pr, api, "抓取", src="b", dst=("t", 0.92), mid=116, style="dash", lp=(540, 112), la="middle")
    d.edge(api, etcd)
    d.edge(cli, api, src="r", dst=("l", 0.5))
    obj = d.box(430, 200, 190, 44, ["1000 个节点，10 000 个 Pod [虚拟]", "只是 etcd 里的对象"], "virt", size=10)
    d.edge(etcd, obj, src="b", dst=("t", 0.58), style="dot", head=False)
    d.para(20, 214, ["没有 kubelet、容器运行时和镜像：", "只有控制面处理这些对象的行为是真实的"], 9.5, MUTED)
    d.save(out)


@fig("concept-etcd-space", 11, [], kind="concept", check=("2 GiB", "每 5 分钟"))
def _(out):
    d = Diagram(184)
    w = d.box(10, 26, 96, 60, ["每一次写入", "创建、修改、删除"], "real", size=10)
    rev = d.box(128, 26, 132, 60, ["一个新的修订版本", "旧版本仍留在文件里"], "real", size=10)
    free = d.box(322, 20, 122, 72, ["旧版本被清除", "页面标记为空闲", "文件大小不变"], "sim", size=10)
    small = d.box(510, 26, 122, 60, ["重写成新文件", "空间还给文件系统"], "good", size=10)
    d.edge(w, rev)
    d.edge(rev, free, "压缩")
    d.text(291, 72, "每 5 分钟", 9.5, MUTED, "middle")
    d.edge(free, small, "碎片整理")
    d.text(477, 72, "逐个成员", 9.5, MUTED, "middle")
    q = d.box(322, 126, 310, 46, ["超过配额（默认 2 GiB）", "NOSPACE：只接受读和删除，不能再创建任何对象"], "bad", size=10)
    d.edge(rev, q, "不压缩、不整理", src="b", dst="l", style="dash", lp=(258, 143))
    d.save(out)


@fig("concept-list-paths", 11, [], kind="concept", check=("1.31", "resourceVersion=0"))
def _(out):
    d = Diagram(226)
    c = d.box(10, 52, 100, 52, ["客户端", "LIST 全部 Pod"], "real", size=10)
    a = d.box(156, 52, 104, 52, ["API server"], "real")
    wc = d.box(476, 10, 154, 54, ["watch 缓存", "内存中的全部对象"], "good", size=10)
    e = d.box(476, 100, 154, 58, ["etcd"], "store", "cyl")
    d.edge(c, a)
    d.edge((260, 62), wc, dst=("l", 0.35), via=[(352, 62), (352, 28.9)], color=TEAL, sw=2.2)
    d.edge((260, 78), wc, dst=("l", 0.8), via=[(392, 78), (392, 53.2)], style="dash", color=TEAL)
    d.edge((260, 94), e, dst="l", via=[(352, 94), (352, 129)])
    d.badge(300, 62, "1", TEAL)
    d.badge(300, 78, "2", TEAL)
    d.badge(300, 94, "3", C["gray"])
    d.edge(e, wc, src=("t", 0.7), dst=("b", 0.7), style="dash")
    d.text(590, 86, "watch", 9.5, MUTED, "start")
    d.para(10, 180, ["①  resourceVersion=0：可以略旧，直接由缓存提供",
                     "②  一致的读，1.31 起：只向 etcd 询问当前的修订版本，等缓存追上，再由缓存提供",
                     "③  一致的读，1.31 之前：从 etcd 取回全部对象"], 9.5, "#3a4553", lh=15)
    d.save(out)


@fig("concept-apf", 11, [], kind="concept", check=("429", "borrowingLimitPercent"))
def _(out):
    d = Diagram(218)
    rq = d.box(8, 22, 84, 58, ["请求", "谁 · 动词", "· 资源"], "ghost", size=10)
    fs = d.box(110, 22, 88, 58, ["FlowSchema", "按规则分类"], "real", size=10)
    pl = d.box(216, 12, 142, 78, ["优先级", "名义席位 =", "总并发 × 份额占比"], "real", size=10)
    q = d.box(376, 10, 100, 82, ["有空席位", "吗？"], "plain", "diamond", bold=False)
    ex = d.box(566, 28, 66, 46, ["执行"], "good")
    for p_, q_ in ((rq, fs), (fs, pl), (pl, q)):
        d.edge(p_, q_)
    d.edge(q, ex, "有")
    qu = d.box(366, 138, 120, 64, ["排队", "同一优先级内", "按“流”分队列"], "sim", size=10)
    d.edge(q, qu, "没有")
    d.edge((486, 152), ex, "轮到了", dst="b", lp=(540, 147), la="middle")
    r = d.box(534, 170, 98, 40, ["429", "Too Many Requests"], "bad", size=10)
    d.edge((486, 190), r, "队列已满", dst="l")
    ot = d.box(8, 136, 200, 66, ["其他优先级的空闲席位", "借用上限：borrowingLimitPercent", "不设 = 没有上限"], "ghost", size=10)
    d.edge(ot, pl, "借用", src="r", dst="b", style="dash")
    d.save(out)


# ================================================================== chapter 12 (E11)
@fig("concept-iac-split", 12, [], kind="concept")
def _(out):
    d = Diagram(252)
    src = d.box(270, 8, 170, 44, ["GitHub v2/", "审阅过的源"], "dark", size=10)
    tofu = d.box(10, 96, 130, 52, ["OpenTofu", "iac/gitlab"], "real", size=10)
    d.group(230, 84, 240, 160, "GitLab", "zone")
    gov = d.box(240, 110, 104, 62, ["门禁设置", "合并规则", "main 的保护、成员"], "real", size=10)
    repo = d.box(354, 110, 104, 62, ["配置仓库", "合并请求", "流水线"], "real", size=10)
    st = d.box(240, 182, 104, 54, ["状态存储", "加密、加锁"], "store", "cyl", size=10)
    argo = d.box(500, 110, 130, 62, ["Argo CD", "管理集群里的一切", "E11 起也管理自己"], "real", size=10)
    k8s = d.box(500, 198, 130, 40, ["集群 ent"], "good")
    s3 = d.box(10, 190, 130, 54, ["Garage tofu-state", "锁无效，已弃用"], "ghost", "cyl", size=10)
    d.edge(src, tofu, "IaC 配置", src="l", dst="t", lp=(150, 26), la="middle")
    d.edge(src, repo, "publish：合并请求", src=("b", (repo.cx - src.x) / src.w), dst="t", lp=(412, 76), la="start")
    d.edge((140, 112), gov, "plan / apply", dst=("l", 0.03))
    d.edge((140, 134), st, "状态", dst="l", via=[(190, 134), (190, 209)], tail=True, lp=(196, 180), la="start")
    d.edge(tofu, s3, "第一个家", src=("b", 0.3), dst=("t", 0.3), style="dash")
    d.edge(repo, argo, src="r", dst=("l", 0.5))
    d.edge(argo, k8s)
    d.save(out)


@fig("concept-state-lock", 12, [], kind="concept", check=("412", "409"))
def _(out):
    sequence(out, ["运行 A", ("状态后端", "store"), "运行 B"], [
        ("msg", 0, 1, "加锁：只在锁不存在时写入"),
        ("msg", 1, 0, "成功", "reply"),
        ("msg", 2, 1, "加锁"),
        ("msg", 1, 2, "已被占用（S3：412，GitLab：409）", "reply"),
        ("note", 2, 2, "报告“无法获得状态锁”，停下"),
        ("msg", 0, 1, "读状态 → 应用变更 → 写回状态"),
        ("msg", 0, 1, "解锁"),
        ("gap", 4),
        ("note", 0, 2, "后端忽略这个条件时：B 也“加锁成功”，两个运行读到同一份状态，后写回的覆盖先写回的", "bad"),
    ], margin=110)


@fig("e11-argocd-upgrade", 12, ["evidence/e11/i4/upgrade.log"],
     check=("244 秒", "315 秒", "24 秒", "31 秒", "10.14.0", "10.17.1",
            "evidence/e11/i4/upgrade.log::MR !45 (mr/20261110-140726-root, by root) pipeline 88: success after 31 s"))
def _(out):
    sequence(out, ["开发者", "GitLab", "Argo CD", "argocd\n命名空间"], [
        ("msg", 0, 1, "!45：chart 10.14.0 → 10.17.1"),
        ("self", 1, "流水线：渲染新 chart（31 秒）"),
        ("msg", 0, 1, "合并（计时起点）"),
        ("note", 2, 2, "+244 秒：轮询看到新版本"),
        ("msg", 2, 3, "同步（24 秒）"),
        ("self", 3, "6 个工作负载滚动，\n应用控制器最后被替换"),
        ("msg", 2, 0, "+315 秒：Synced / Healthy", "reply"),
    ], margin=86)


# ================================================================== reading guide
@fig("concept-bookmap", 0, [], kind="concept")
def _(out):
    d = Diagram(296)
    d.group(8, 8, 172, 132, "变更的来源", "zone")
    src = d.box(20, 34, 148, 40, ["源码与配置", "GitHub"], "real", size=10)
    gl = d.box(20, 88, 148, 44, ["GitLab：合并请求门禁", "第 9、12 章"], "real", size=10)
    d.edge(src, gl)
    argo = d.box(8, 162, 172, 48, ["Argo CD：把集群拉向 Git", "第 2、9、12 章"], "real", size=10)
    d.edge(gl, argo, src="b", dst=("t", 0.5))
    k = d.group(200, 8, 300, 220, "实验集群 ent　第 1 章", "cool")
    d.text(209, 37, "1 个控制面 + 3 个工作节点，模拟三个可用区", 9.5, "#46525f")
    items = [("storefront：6 个服务", "第 2 章"), ("服务网格 Istio ambient", "第 3 章"),
             ("PostgreSQL · Valkey · NATS", "第 2、8 章"), ("HPA · KEDA · 调度与驱逐", "第 5 章"),
             ("租户、策略、密钥", "第 6 章"), ("指标、日志、链路", "第 4、10 章")]
    cells = {}
    for i, (name, ch) in enumerate(items):
        cells[i] = d.box(210 + (i % 2) * 144, 48 + (i // 2) * 60, 136, 50, [name, ch], "real", size=10)
    d.edge(argo, (200, 186), src="r")
    k6 = d.box(520, 8, 112, 40, ["k6 负载", "第 4 章"], "ghost", size=10)
    fi = d.box(520, 56, 112, 40, ["故障注入", "第 7 章"], "inject", size=10)
    ex = d.box(520, 104, 112, 40, ["能力考核", "第 13 章"], "ghost", size=10)
    d.edge(k6, (500, 28), src="l")
    d.edge(fi, (500, 76), src="l", style="dash")
    d.edge(ex, (500, 124), src="l", style="dash")
    bk = d.box(520, 152, 112, 36, ["集群外的备份　第 8 章"], "store", size=9.5, bold=False)
    al = d.box(520, 194, 112, 36, ["告警桥 → 事故　第 10 章"], "store", size=9.5, bold=False)
    d.edge((500, 170), bk, dst="l")
    d.edge((500, 212), al, dst="l")
    d.box(200, 242, 300, 46, ["另一个集群：真实的控制面", "1000 个虚拟节点、10 000 个虚拟 Pod　第 11 章"], "virt", size=10)
    d.para(8, 240, ["箭头向内：从外部施加的负载、故障与考核", "箭头向外：离开集群的备份与告警",
                    "第 12 章：OpenTofu 管理 GitLab 的门禁"], 9.5, MUTED, lh=14)
    d.save(out)
