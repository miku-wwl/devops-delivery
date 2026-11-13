按主题排列。括号中为英文原名，最后一列是主要讲解该术语的章节。

| 术语 | 含义 | 章节 |
|---|---|---|
| DORA 指标 | 变更前置时间、部署频率、变更失败率、失败部署的恢复时间，衡量交付的速度与稳定性 | 1 |
| 持续集成（CI） | 每次变更都自动构建、检查和测试，不合格的变更进不了主干 | 3 |
| 质量门禁（quality gate） | 变更必须通过的自动检查；不通过就阻断合并或发布 | 3、4 |
| Runner | 执行 CI 作业的机器；GitHub 托管 Runner 每个作业一台新虚拟机，GitLab Runner 主动拉取作业 | 3、4 |
| 可复用工作流（reusable workflow） | 通过 `workflow_call` 被多个调用方引用的 GitHub Actions 工作流 | 3 |
| 规则集（ruleset） | GitHub 的分支保护规则，可要求必需检查通过才能合并 | 3 |
| 制品（artifact）与缓存（cache） | 制品用于传递结果、保证可用；缓存用于加速、不保证存在 | 3、4 |
| DAG 调度 | 用 `needs` 声明作业依赖，不必等整个阶段结束 | 4 |
| 合并请求（MR） | GitLab 中对应 GitHub PR 的概念；MR 流水线决定能否合并 | 4 |
| 声明式（declarative）与调和（reconcile） | 声明期望状态，控制器不断比较并消除与实际状态的差异 | 5、6 |
| Pod 模板哈希 | 对 Pod 模板计算的哈希；模板变化就产生新的 ReplicaSet | 5、8 |
| Chart / Release / Revision | Helm 的包、一次安装实例、实例的每次变更 | 5 |
| values schema | 用 JSON Schema 校验 Helm values，错误在渲染前就被拦下 | 5 |
| Pod 安全标准（PSS） | Kubernetes 内置的 privileged / baseline / restricted 三档 Pod 安全策略 | 5、12 |
| PodDisruptionBudget（PDB） | 限制自愿中断时同时不可用的 Pod 数 | 5 |
| 准入 Webhook（admission webhook） | API Server 在持久化之前调用的外部服务：变更型可以修改对象，校验型只能放行或拒绝 | 5、7 |
| level-triggered（基于状态的调和） | 控制器比较当前状态与期望状态，而不是响应单个事件，漏掉事件也能自我纠正 | 5 |
| EndpointSlice / kube-proxy | 记录 Service 就绪后端的对象 / 在每个节点上把它们翻译成 NAT 规则的组件 | 5 |
| conntrack（连接跟踪） | 内核记录每个连接的地址转换，同一连接的后续数据包都走同一个后端 | 5、8 |
| namespace / cgroup | 内核为进程提供的隔离视图 / 资源限制（memory.max、cpu.max、cpu.weight） | 5 |
| capability / seccomp / no_new_privs | 把 root 的特权拆分后的权限集合 / 系统调用过滤器 / 禁止通过 setuid 等方式提权的标志 | 5 |
| overlayfs | 把镜像的只读层与可写层叠加成一个文件系统；只读根文件系统即不再提供可写层 | 5、12 |
| QoS 等级 | 由 requests 与 limits 决定的 Guaranteed / Burstable / BestEffort，影响驱逐顺序 | 5 |
| GitOps | 期望状态保存在 Git，由环境内的代理拉取并持续调和 | 6 |
| 同步状态 / 健康状态 | 集群是否与 Git 一致 / 对象本身是否正常，两者相互独立 | 6、12 |
| 漂移（drift）与自愈（self-heal） | 集群偏离 Git 的状态；自动改回 Git 的行为 | 6、13 |
| AppProject | Argo CD 的多租户边界，限制仓库来源、目标命名空间和资源类型 | 6 |
| digest | 内容的哈希（`sha256:…`），内容变则 digest 变；tag 是可变的指针 | 7 |
| OCI 清单 / 配置 / 层 | 镜像的三部分：列出各部分的 JSON、记录元数据和构建历史的 JSON、文件系统差异包；镜像 digest 是清单的 SHA-256 | 7 |
| 可复现构建（reproducible build） | 同样的输入总是产生逐字节相同的产物，任何人都能独立重建并比对 | 7、11 |
| in-toto 声明（statement） | 来源证明的格式：subject（关于哪个制品）+ predicateType + predicate（声明内容） | 7 |
| SBOM（软件物料清单） | 制品中全部组件及其版本、许可证的清单（SPDX、CycloneDX） | 7 |
| SLSA 与来源证明（provenance） | 供应链分级框架；来源证明是被签名的声明，记录制品由谁、从哪个提交、怎样构建 | 7 |
| 无密钥签名（keyless signing） | Sigstore 用 OIDC 身份换取短期证书签名，签名时间由透明日志证明 | 7 |
| Fulcio / Rekor | Sigstore 的证书机构 / 公开只追加的透明日志 | 7 |
| 准入控制（admission control） | API Server 持久化对象之前的审查与修改；本书用 Kyverno 验证镜像来源 | 7 |
| 金丝雀（canary）/ 蓝绿（blue-green） | 先给小部分流量、按指标逐步扩大 / 两套环境一次切换 | 8 |
| AnalysisRun 与三态判定 | Argo Rollouts 的一次分析；结果分为成功、失败、不确定（Inconclusive） | 8 |
| 爆炸半径（blast radius） | 一次故障影响的范围，例如受影响请求的数量与比例 | 8、12 |
| 可观测性（observability） | 仅凭系统输出的数据就能回答事先没想到的问题 | 9 |
| 指标 / 链路 / 日志 | 聚合的数值 / 一次请求经过的 span 及其关系 / 离散事件记录 | 9 |
| traceparent（W3C Trace Context） | 跨服务传递链路上下文的请求头：版本、trace ID、父 span ID、采样标志 | 9 |
| 外推（extrapolation） | `rate()`、`increase()` 把窗口内样本的增长按比例推算到整个窗口，所以结果可以是小数 | 9、12 |
| span 与 trace_id | 链路中的一个操作 / 把同一请求的 span 和日志关联起来的标识 | 9、12 |
| OpenTelemetry / OTLP / Collector | 可观测性标准 / 其传输协议 / 接收、处理、导出遥测数据的程序 | 9 |
| RED / USE | 面向请求的速率、错误、耗时 / 面向资源的利用率、饱和度、错误 | 9 |
| 高基数（high cardinality） | 标签取值过多导致时间序列爆炸 | 3、9 |
| 头部采样 / 尾部采样 | 在请求入口决定是否记录链路 / 在整条链路结束后决定 | 9 |
| exemplar | 直方图区间上附带的具体请求的 trace_id，从指标跳到链路 | 9 |
| 统一服务标签（UST） | Datadog 的 `env`、`service`、`version` 三个保留标签 | 10 |
| distribution | 在后端全局合并后再计算百分位的指标类型 | 10 |
| 合成测试（synthetic test） | 用脚本模拟用户操作，不依赖真实流量 | 11 |
| 开放模型 / 封闭模型 | 固定到达速率 / 固定并发用户数，后者在服务变慢时会自动降速 | 11 |
| check / threshold | k6 中只记录结果的断言 / 决定测试成败的阈值 | 11 |
| SLI / SLO | 好事件占有效事件的比例 / 该比例在一段时间内的目标 | 12 |
| 错误预算（error budget） | 1 − SLO，允许出错的比例或数量 | 12 |
| 燃烧率（burn rate） | 窗口内坏事件比例 ÷ 错误预算；1 表示恰好在周期结束时用完 | 12 |
| 多窗口告警 | 长窗口与短窗口同时超过阈值才告警，兼顾显著性与恢复速度 | 12 |
| 记录规则（recording rule） | 预先计算并保存为新时间序列的 PromQL 表达式 | 12 |
| 扩展—收缩（expand/contract） | 先只增不减、让新旧版本都能工作，确认稳定后再删除旧的部分，使回滚始终安全 | 8、9 |
| 带外密钥（out-of-band secret） | 不经过 Git、由脚本或人直接创建在集群中的密钥；GitOps 中的替代方案有 Sealed Secrets、SOPS、External Secrets | 6 |
| RCA 与无责复盘 | 事故根因分析；关注改进系统而不是追究个人 | 12 |
| 5 Whys / 根本原因 / 促成因素 | 逐层追问的分析方法 / 去掉即不会发生的原因 / 让问题更严重或更难发现的因素 | 12 |
| MTTD / MTTR | 从事件开始到检测 / 到恢复所用的时间 | 12 |
| 幂等（idempotence） | 执行一次和执行多次结果相同 | 2、13 |
| Inventory / 角色 / handler | Ansible 的主机清单 / 可复用的任务结构 / 被通知且有变化时才运行的任务 | 13 |
