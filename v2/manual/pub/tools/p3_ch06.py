"""Publication Edition, chapter 6 (multi-tenancy and security): the chapter had no figure at all."""
from edit import Doc, opener, prod

d = Doc("06-e5")
d.before("## 本章目标与产出", opener(
    "集群不再只有一个团队。怎样让每个团队只能动自己的东西——在 API、网络和密钥三个层面——并且事后能从记录里回答“谁做了什么”？",
    ["越权测试全部符合预期：Kubernetes 权限 58 项、Argo CD 权限 24 项、网络可达性 45 项；预期在施加策略之前提交。",
     "能创建 Pod，就能读同一命名空间里的 Secret：RBAC 对此无能为力，边界要靠命名空间和外部密钥管理来划。",
     "网格改变了 NetworkPolicy 的规则：流量到达 15008 端口，经过 waypoint 时来源是 waypoint，新策略不切断已有的连接。",
     "准入引擎是全集群的依赖：单副本、不限范围的 Kyverno 重启一次，全集群 34 秒不能创建 Pod。",
     "密钥轮换时，Secret 8 秒内更新，挂载的文件 61 秒后更新，环境变量要等 Pod 重启。"]))
d.after("## 原理 {#e5-principles}", """```{.mermaid caption="一个租户被五种机制围住，每一种回答一个不同的问题，互不替代：RBAC 管“谁能改什么”，准入管“什么样的对象能进来”，网络策略管“能和谁通信”，外部密钥管“秘密从哪里来”，Argo CD 的项目管“能往哪里部署”。审计日志不拦任何东西，它负责事后回答。"}
flowchart TB
  R["RBAC：谁能改什么<br/>实验 1–3"] --> NS
  A["准入：什么样的对象能进来<br/>Pod Security · Kyverno · 配额<br/>实验 5"] --> NS
  N["网络策略：能和谁通信<br/>默认拒绝，显式放行<br/>实验 4"] --> NS
  subgraph NS["租户命名空间（shop-dev、insight）"]
    P["团队的 Pod 与对象"]
  end
  S["外部密钥：秘密从哪里来<br/>OpenBao + External Secrets<br/>实验 7"] --> NS
  G["Argo CD 项目：能往哪里部署<br/>实验 6"] --> NS
  NS -.-> L["审计日志：谁、何时、做了什么<br/>实验 3"]:::note
```""")
d.before("### 网络", """```{.mermaid caption="一个请求进入 API server 要过的四道关。认证回答“你是谁”，授权回答“这个动作允许吗”，准入回答“这个对象合规吗”；审计把每一步的结果记下来，包括被拒绝的请求。"}
flowchart LR
  U["请求<br/>kubectl · 控制器 · Argo CD"] --> AU["认证<br/>证书 · 服务账号令牌 · OIDC"]
  AU --> AZ["授权（RBAC）<br/>只有“允许”，没有“拒绝”"]
  AZ --> MA["修改型准入<br/>LimitRange 补默认值"]
  MA --> VA["校验型准入<br/>Pod Security · Kyverno<br/>ValidatingAdmissionPolicy"]
  VA --> E[("etcd")]:::store
  AU -.-> LOG["审计日志"]:::note
  AZ -.-> LOG
  VA -.-> LOG
```""")
d.after("3. **有 waypoint 时，服务端看到的来源是 waypoint。**", """```{.mermaid caption="网格中 NetworkPolicy 看到的流量。应用以为自己在访问 8080，线上走的是到 15008 端口的隧道；有 waypoint 时，到达服务端的连接来自 waypoint 而不是客户端。按“客户端 → 服务端:8080”写的经典规则，对网格内的流量不起作用，对网格外的客户端才生效。"}
flowchart LR
  subgraph NOWP["没有 waypoint"]
    direction LR
    C1["客户端 Pod"] --> Z1["ztunnel"]
    Z1 ==>|"HBONE，目的端口 15008<br/>策略必须放行 15008"| S1["服务端 Pod<br/>应用端口 8080"]
  end
  subgraph WP["有 waypoint"]
    direction LR
    C2["客户端 Pod"] ==>|"15008"| W["waypoint"]
    W ==>|"15008，来源是 waypoint"| S2["服务端 Pod"]
  end
  X["网格外的客户端"]:::ghost -->|"直接到 8080"| S1
```""")
d.after("- **审计：**OpenBao 的审计日志按服务账号记录了每一次读取", """```{.mermaid .data caption="一次密钥轮换的传播（时间为实测）。新值 8 秒内进入 Kubernetes Secret，挂载的文件 61 秒后跟上，环境变量永远不会——需要轮换的凭据应当以文件挂载，并由应用重新读取。"}
flowchart LR
  SA["服务账号 secrets-reader<br/>只能读本租户的路径"] -.->|"Kubernetes 认证"| OB
  OB[("OpenBao<br/>写入新值")]:::store -->|"External Secrets<br/>每 30 秒刷新"| KS["Kubernetes Secret<br/>8 秒内更新"]
  KS -->|"kubelet 定期同步"| F["挂载的文件<br/>61 秒后更新"]:::good
  KS -. "只在容器启动时读取" .-> EV["环境变量<br/>旧值，直到 Pod 重启"]:::bad
```""")
d.before("## 常见问题", prod([
    ("用户是集群 CA 签发的客户端证书（7 天，不能吊销）", "企业身份系统经 OIDC 登录，组来自目录，会话可以撤销", "证书只能等它过期；真实环境里离职和调岗要立刻生效"),
    ("OpenBao 单节点、一份解封密钥，用根令牌写入秘密", "高可用部署，KMS 自动解封或多人分片，每个人用自己的身份", "第 12 章的事故 E11-1 就是单份密钥的代价"),
    ("CNI 是 kindnet：新策略不切断已有的连接", "Calico、Cilium 等，行为各不相同，有的支持第 7 层与全局策略", "网络策略的结论要在自己的 CNI 上重新验证"),
    ("两个团队、四个用户、一个最小的示例服务", "几十个团队，自助开通命名空间", "配额、策略例外和审计量的管理，本身会成为一个系统"),
]))
d.save()
