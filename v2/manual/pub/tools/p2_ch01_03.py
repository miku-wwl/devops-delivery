"""Publication Edition, chapters 1-3: openers, captions, mechanism diagrams, data charts, lab-vs-production tables."""
from edit import Doc


def opener(question: str, results: list[str]) -> str:
    items = "\n".join(f"- {r}" for r in results)
    return f"::: opener\n::: q\n**工程问题**\n\n{question}\n:::\n::: k\n**实测结论**\n\n{items}\n:::\n:::"


def prod(rows: list[tuple[str, str, str]]) -> str:
    body = "\n".join(f"| {a} | {b} | {c} |" for a, b, c in rows)
    return ("### 从实验环境到生产环境\n\n::: prod\n| 本章的做法 | 生产环境通常的做法 | 差别意味着什么 |\n|---|---|---|\n"
            + body + "\n:::")


# ------------------------------------------------------------------ chapter 1
d = Doc("01-e0")
d.before("## 本章目标与产出", opener(
    "一台 16 线程、虚拟机只分得 15.28 GiB 内存的笔记本，怎样当作“三个可用区、每个节点 4 核 3 GiB”的集群来做实验——"
    "并且让调度器、kubelet 和内核对“这个节点有多大”的看法一致？",
    ["Kind 的节点是容器：不加修正时，kubelet 认为每个节点拥有整台虚拟机的 15642 MiB 内存，而且 Kind 默认关闭了内存驱逐。",
     "修正之后三条线对齐：调度器按 2666 MiB 放 Pod，kubelet 在 2922 MiB 开始驱逐，内核在 3072 MiB 才动用 OOM killer。",
     "集群创建用了 43 秒，脚本可以重复执行；CPU 用 cpuset 固定，而不是用配额限制，避免了周期性的限流。"]))
d.caption("subgraph WIN[", "本章的实验环境是四层嵌套：Windows、WSL2 虚拟机、作为“节点”的 Docker 容器、Pod。每一层的上限都约束它里面的所有进程；"
          "三个工作节点各自固定在 4 个 CPU 上，内存由内核限制在 3 GiB。")
d.after("问题在于，kubelet 并不知道自己被关在一个 3 GiB 的容器里。", """```{.mermaid caption="问题的根源：kubelet 的“容量”来自整台虚拟机的 /proc/meminfo，真正执行的上限却在节点容器的 cgroup 上。不修正的话，调度器以为每个节点有 15 GiB，驱逐阈值永远不会触发，最先出手的只能是内核的 OOM killer。"}
flowchart LR
  M["/proc/meminfo<br/>MemTotal 15642 MiB<br/>整台虚拟机"]:::ghost --> CA["cAdvisor"] --> K["kubelet<br/>capacity = 15642 MiB"]
  K --> AL["allocatable =<br/>capacity − 预留 − 驱逐阈值"]
  AL --> S["调度器<br/>按 allocatable 放 Pod"]
  CG["节点容器的 cgroup<br/>memory.max = 3072 MiB"]:::bad -. "kubelet 不读它" .-> K
  CG --> OOM["内核 OOM killer<br/>在 3072 MiB 执行"]:::bad
```""")
d.after("此时 allocatable 为", "![一个工作节点的三条内存线（MiB）。把预留和驱逐阈值设成“从虚拟机的 15642 MiB 倒推”的值之后，三个角色的判断"
        "依次发生：调度器不会把 requests 放过 2666 MiB；实际用量到 2922 MiB 时 kubelet 按顺序驱逐 Pod；只有驱逐来不及时，"
        "内核才在 3072 MiB 杀进程。](../figures/e0-memory-lines.svg)")
d.wrap_table("| 方面 | 本环境 | 真实生产 |", "prod")
d.save()

# ------------------------------------------------------------------ chapter 2
d = Doc("02-e1")
d.before("## 本章目标与产出", opener(
    "把一个服务拆成六个之后，一笔订单要跨三个数据库、一个缓存和一个消息队列。怎样让它在部分失败时不丢、不重、可追踪——"
    "并且整个平台能从 Git 重建？",
    ["平台从 Git 收敛用了 735 秒，其中等待 PostgreSQL 集群就占了 437 秒：同步波次把“谁依赖谁”变成了看得见的时间线。",
     "一笔订单的链路包含 6 个服务、65 个 span，从网关一直延续到通知服务消费消息——追踪上下文跨过了消息队列。",
     "两个副本并不意味着负载减半：长连接下 orders 的一个副本承担了 91.3% 的请求（第 3 章解决）。",
     "第一次部署暴露了 8 个问题，每一个都留下了证据和修复——它们比顺利的部分更有教学价值。"]))
d.caption("sequenceDiagram", "下单的 saga：orders 依次预留库存、扣款、确认订单；任何一步失败，都用补偿撤销已经完成的步骤。"
          "没有跨服务的事务，只有“每一步都可以重试、可以撤销”的约定。")
d.caption('K["k6（主机）"]', "storefront 的服务与数据：同步调用（实线）在请求路径上，订单确认后的通知经事务性 outbox 与 NATS 异步送达（虚线）。"
          "每个服务只访问自己的数据。")
d.after_block("### 双写问题与事务性 outbox", 4, """```{.mermaid caption="事务性 outbox 的三段：订单与事件在同一个事务里提交；中继把事件发布到 NATS，重复发布由消息 ID 去重；消费者自己再去重一次。任何一处崩溃，重来一遍都不会丢、也不会重。"}
flowchart LR
  subgraph TX["orders：一个数据库事务"]
    U["UPDATE orders<br/>status = CONFIRMED"] --- I["INSERT INTO outbox<br/>事件 + trace 上下文"]
  end
  TX -->|"COMMIT：要么都在，要么都不在"| OB[("outbox 表")]:::store
  OB -->|"中继每 200 ms 读取<br/>FOR UPDATE SKIP LOCKED"| R["中继 relay"]
  R -->|"发布，Nats-Msg-Id = 事件 ID"| N[["NATS JetStream<br/>2 分钟去重窗口"]]:::store
  R -. "发布成功后标记已发布<br/>（崩溃在两步之间：重发，被去重）" .-> OB
  N --> C["notifier<br/>按事件 ID 再去重"]
```""")
d.after_block("### 平台从 Git 引导", 1, """```{.mermaid caption="平台从 Git 引导（app-of-apps）：手工只做两件事——安装 Argo CD、应用根应用。根应用指向一个目录，目录里的每个文件是一个应用；同步波次决定先后，ApplicationSet 为每个服务生成一个应用。"}
flowchart LR
  B["bootstrap.sh<br/>安装 Argo CD<br/>应用 root.yaml"]:::dark --> ROOT["根应用<br/>platform-root"]
  G[("GitLab<br/>platform-gitops")]:::store --> ROOT
  ROOT --> W3["波次 −3<br/>监控栈"]
  ROOT --> W2["波次 −2<br/>数据库运营商"]
  ROOT --> W1["波次 −1<br/>Tempo · Loki · NATS · Valkey"]
  ROOT --> W0["波次 0<br/>PostgreSQL 集群"]
  ROOT --> AS["波次 1<br/>ApplicationSet"]
  AS --> SV["6 个服务应用<br/>每个服务一个值文件"]
```""")
d.after("| t+735 s | 15 个应用全部 Synced + Healthy |", "![第一次从 Git 收敛的时间线。每一条是一个同步波次从开始到下一波次开始的时间："
        "整个 735 秒里，437 秒在等 PostgreSQL 集群就绪（第一个实例初始化，两个副本依次加入），而 6 个服务自己只用了 37 秒。]"
        "(../figures/e1-convergence.svg)")
d.before("## 常见问题", prod([
    ("六个服务共用一个镜像和一套公共库", "每个服务独立的代码库、镜像与发布节奏", "这里一次构建更新全部服务；真实团队要面对版本并存与接口契约的兼容"),
    ("payments 是自己写的模拟器，延迟人为生成", "外部支付网关：限流、回调、对账文件", "“结果不明”在真实网关上更常见，对账是必需的流程，而不是可选的补充"),
    ("一个 PostgreSQL 集群上每服务一个库；Valkey 单实例三种用途", "按数据的重要性分开实例，缓存与“记录”不共用", "淘汰策略、故障域和备份要求不同的数据放在一起，迟早互相拖累"),
    ("中继每 200 ms 轮询 outbox", "变更数据捕获（读取 WAL）或 LISTEN/NOTIFY", "轮询简单、延迟固定；变更数据捕获延迟更低，但多一个要运维的系统"),
]))
d.save()

# ------------------------------------------------------------------ chapter 3
d = Doc("03-e2")
d.before("## 本章目标与产出", opener(
    "第 2 章留下两个问题：服务之间的流量是明文的；长连接让请求压在一个副本上。不改应用代码，服务网格能解决到什么程度，"
    "又要付出什么代价？",
    ["加入 ambient 网格不需要重启任何 Pod；节点之间线上可读的服务间请求行从 140 行变为 0。",
     "只加密（L4）解决不了负载不均：inventory 仍是 97.2% / 2.8%；经过 waypoint（L7）之后，各服务的两个副本都在 46.9%–53.1% 之间。",
     "代价要交替测量才测得准：L4 让浏览的 p50 增加约 2.4 ms，waypoint 再加约 1.3 ms；相隔 15 分钟的第一次对比得出的 +32 ms 主要是漂移。",
     "网格的重试与应用的重试相乘：加一条“重试 3 次”的路由，payments 收到的调用变成 4 倍。"]))
d.caption('A["gateway Pod', "ambient 模式的数据路径：Pod 里没有 sidecar，流量被重定向到本节点的 ztunnel，节点之间用 HBONE（mTLS 上的 HTTP/2 CONNECT，"
          "端口 15008）传输；需要第 7 层能力时，流量再经过一个 waypoint。")
d.after_block("### L4 与 L7 负载均衡", 2, """```{.mermaid caption="同一个调用方、两个副本，两种选择后端的时机。按连接选择时，少数几条长连接落在哪里，之后的所有请求就在哪里；按请求选择时，每个请求都重新分配。"}
flowchart LR
  subgraph L4["L4：kube-proxy / ztunnel，在连接建立时选一次"]
    direction LR
    C1["调用方<br/>2 条长连接"] ==>|"连接 1：之后的全部请求"| A1["副本 A<br/>约 97%"]:::bad
    C1 ==>|"连接 2 也落在 A"| A1
    C1 -.- B1["副本 B<br/>约 3%"]:::ghost
  end
  subgraph L7["L7：waypoint，为每个请求选一次"]
    direction LR
    C2["调用方"] ==> WP["waypoint<br/>终止 HTTP，最少请求算法"]
    WP -->|"请求 1、3、5…"| A2["副本 A<br/>约 50%"]:::good
    WP -->|"请求 2、4、6…"| B2["副本 B<br/>约 50%"]:::good
  end
```""")
d.after("结论很清楚", "![三种模式下，两个副本中较忙的那个承担的请求比例。50% 是完全均匀。只有 ztunnel（L4）时，不均的程度和没有网格时"
        "一样——只是换了一个副本“中签”；经过 waypoint（L7）之后，五个服务全部回到 50% 附近。gateway 的调用方是 k6 的大量连接，"
        "所以三种模式下都均匀。](../figures/e2-distribution.svg)")
d.after("| 3 | ambient | 14.5 | 24.6 | 123.4 | 226.5 |", "![同一个问题的两种测法。第一次把“无网格”和“ambient”各跑一次，相隔 15 分钟：下单 p50 相差 32.4 ms。"
        "交替运行三轮之后，浏览的差值稳定在 2.1–2.7 ms，而下单的差值在 −0.6 到 +16.8 ms 之间摆动——它被 payments 人为生成的延迟"
        "淹没了，第一次的 +32 ms 大部分是两次运行之间的漂移。](../figures/e2-ab.svg)")
d.after("| S4：只有 ztunnel（L4），返回 503 | 11（0.18） | 6 | 6 | 0 |", """```{.mermaid .data caption="场景 S3 中的重试叠加（数字为实测）：应用认为自己只发出了 7 次尝试，waypoint 上的路由为每一次又重试 3 次，payments 实际收到 28 次。每一层都只看得见自己的重试。"}
flowchart LR
  O["orders<br/>应用层：重试 + 重试预算"] -->|"7 次尝试"| W["waypoint<br/>HTTPRoute：重试 3 次"]:::sim
  W ==>|"7 × (1 + 3) = 28 次调用"| P["payments<br/>正在返回 503"]:::bad
```""")
d.before("## 常见问题", prod([
    ("本章只有一个 waypoint 副本（第 7 章改为两个）", "waypoint 多副本、跨可用区、带 PodDisruptionBudget", "单副本的 L7 代理是整个命名空间的单点：第 7 章的节点失效实验为此付出了 5.5 分钟"),
    ("负载每秒几十个请求", "成千上万的连接与请求", "ztunnel 与 waypoint 的容量要单独压测；本章毫秒级的开销不能直接外推"),
    ("PERMISSIVE，STRICT 只做了短暂的试验", "全网格 STRICT，入口与监控抓取纳入网格或显式放行", "STRICT 会切断网格外的调用方（实验 5），上线前要先盘点谁在网格外"),
    ("网格版本固定，一次安装", "控制面与数据面按金丝雀方式分批升级", "升级过程中的版本偏差，本书没有测试"),
]))
d.save()
