# 多租户安全：一道边界回答一个问题 {#ch6}

<p class="subtitle">Multi-Tenancy & Security · 从请求身份到秘密的拥有者</p>

开发者没有 `get Secret` 权限，却能把同一命名空间的 Secret 挂进自己创建的 Pod。权限矩阵可以全部通过，秘密仍可能被合法地间接读取。本章围绕这条看似矛盾的路径，区分 API 权限、准入、网络、网格身份与外部密钥授权。

::: mission
能沿一个 API 请求逐关判断，识别命名空间内的隐式能力，并为真实流量路径而非想象中的端口编写策略。
:::

## 请求先认证，再授权，再检查对象

认证把证书、ServiceAccount token 或 OIDC 凭据映射成用户与组。RBAC 再按动词、资源、子资源和命名空间决定是否允许。RBAC 权限相加，没有一条通用 deny 去抵消其他 Role 的 allow。

{{fig:concept-api-request.svg}}

通过授权并不等于对象一定被接受。创建 RoleBinding 还受提权约束，修改型准入可能补默认值，校验型准入可能拒绝内容。E5 有一条审计记录 authorization=allow、响应仍为 403，正是绑定越权的后续检查拒绝了请求。诊断要读最终响应与拒绝理由，不只读授权阶段。

ServiceAccount 是工作负载身份，RoleBinding 把身份和 Role 连起来。storefront 业务服务不调用 Kubernetes API，因此模板使用 `automountServiceAccountToken: false`。这减少暴露面，但不取消 ServiceAccount 在网格 SPIFFE 身份中的作用。

## “能建 Pod”还附带哪些能力

{{code:tenant-rbac}}

这段真实 ClusterRole 授予工作负载管理与日志权限。它没有直接授予 Secret 读取，却允许 Pod 声明 Secret 卷或环境变量。创建工作负载往往意味着能使用命名空间内其他身份与数据，所以命名空间应按信任边界划分；真正不该让这个租户拿到的秘密，不应已经放在他能创建 Pod 的空间内。

{{fig:concept-tenant-fences.svg}}

图中各边界互补：RBAC 管 API 动作，准入管对象内容，NetworkPolicy 管运行时通信，OpenBao 管秘密路径，AppProject 管发布目标。任何一项通过都不能替代其他项。

E5 Kubernetes 权限矩阵最终 58 项符合、Argo CD 离线权限 24 项符合、网络矩阵 45 项符合。这里的“符合”只说明被列出的组合符合预期。第一次 `can-i pods/exec` 还因写法测成“名叫 exec 的 Pod”，提醒我们先验证测试是否真的发出了目标子资源请求。[E5](#ev-e5)

## 网络策略必须对准执行时的路径

默认网络全通时，一个租户 Pod 可能直接访问数据库，即使它不能通过 API 读取数据库 Secret。NetworkPolicy 由 CNI 执行；入站与出站分别判定，多个允许策略合并，并非按清单顺序做传统防火墙的 first-match。

{{fig:concept-netpol-mesh.svg}}

Ambient 下应用认为访问的是 8080，线上可能到 15008；经过 waypoint，目的端看到的来源又是 waypoint。只写“允许 frontend→api:8080”可能只允许了不在网格中的明文路径。还应结合 mTLS 身份策略限制真实调用者，避免把“允许 waypoint 网络连通”误当成“允许所有经它转发的业务”。

E5 对本次 kindnet 的观察是：默认拒绝不会切断已放行的连接；HBONE 长连接复用时，新请求仍然沿旧通道成功。重建客户端后，新连接才暴露缺规则。策略验收应分别测已存在与重新建立的连接，并要求目标应用作答，不能把本地代理完成 TCP 握手当作端到端通达。这些细节依赖 CNI，不能直接外推到其他实现。

## 准入控制器自己也是关键依赖

Pod Security restricted 限制危险容器；LimitRange 补默认值；Kyverno 可以检查镜像、资源并生成租户基线。Deployment 被 API 接受，不代表 ReplicaSet 创建的 Pod 能通过准入。界面看到“0 Ready”时要追到子对象事件。

E5 单副本、webhook 覆盖全命名空间且 failurePolicy=Fail，重启一次让全集群 34 秒不能创建 Pod。限制到带 tenant 标签的空间后，影响被缩小；两副本加 PDB 后该次只剩删除瞬间一个请求失败。不能因此承诺未来所有升级零失败，但因果很清楚：一个同步准入外部服务会进入每次创建的关键路径。

简单稳定校验可以考虑 API Server 内置策略，复杂生成、变更和报告可能需要独立引擎。选择时要把不可用时拒绝还是放行、覆盖范围、超时、升级策略一起设计，而不是只比较表达式能写多短。

## 秘密轮换是一条有状态的传播链

OpenBao 以 Kubernetes 身份认证，每个租户只能读取自己的路径；ESO 使用平台控制的 SecretStore 把值复制为 Secret。开发者能创建 ExternalSecret，但不能任意更换 SecretStore 的登录身份。E5 跨租户指向 shop 路径时，OpenBao 拒绝、没有生成 Secret。

{{fig:e5-secret-rotation.svg}}

图的三个时刻对应不同拥有者。新值先进入 OpenBao，再由 ESO 同步到 Secret，再由 kubelet 更新挂载文件。环境变量在进程启动时固定，更新 Secret 不会修改已运行进程的环境。应用还要重新读取文件并替换连接，才能把“文件已变”变成“新凭据已被使用”。

历史轮换中 Secret 在 8 秒内更新，挂载文件约 61 秒后跟上，环境变量直到重启仍旧。这些是那次运行的时间，不是各组件硬性 SLA。真正的轮换流程需要新旧凭据重叠、确认消费者已经切换、最后撤销旧值，不能在第一个对象更新后立即删旧密码。[E5](#ev-e5)

## 审计与部署身份：谁真正做了修改

GitOps 下 API 请求者通常是 Argo CD；人的意图在 GitLab 合并请求与 Git 提交中。第 9 章的 sync impersonation 再让每个项目使用专属部署账号，API Server RBAC 因而能执行项目边界。平台账号仍有广泛权限，不能声称这消除了 Argo CD 被攻破的全部风险。

审计记录应包含用户、被冒用身份、动词、资源、命名空间、状态码与授权理由。`exec` 的命令行可出现在 requestURI 中，所以即使仅记 Metadata，也不能把秘密写进命令参数。Secret 的值本身不应进入审计正文；需要核对变化时使用受控版本信息和摘要。

E5 当时遗漏了服务账号读 Secret 的审计，E9 才增加相应规则。新版把这个时间演进讲明，不能同时把两个阶段都描述成审计已完整。本轮也没有重新启用任何审计或轮换证书。

::: warning
仓库没有本主题真实的权限管理网页捕获，本章使用源码、边界图和历史矩阵；不制作虚构 RBAC 页面。单节点 OpenBao、解封材料保管和无法撤销的实验客户端证书仍是限制，密钥事故将在第 12 章讨论。
:::

## 判断与应用

::: exercise
1. 开发者能建 Pod、不能 get Secret。设计三层措施保护另一个团队的数据库密码，并解释为何仅删一个 RBAC 动词不够。
2. 新 NetworkPolicy 当天通过，重部署后才失败；双方在 Ambient，目标前有 waypoint。列出连接、来源和端口三个维度的核对顺序。
3. Secret 已更新，应用仍用旧密码。画出 ESO、Secret、挂载、进程和数据库连接五个状态，指出每一处应观察什么。
:::

安全边界只有对应到身份、对象、路径和状态时才可验证。测试越权失败很重要，理解合法权限所隐含的能力同样重要。
