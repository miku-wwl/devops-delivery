# Illustrated Edition 来源索引

基线：`510ec87a9f1b0756248e00f3b53d692ca27aeada`。源码与SVG的SHA-256按UTF-8/LF统一后计算；原始PNG按完整原始字节计算。源码不变；出版视图省略共同缩进并按语义分成视觉续行，可重组核对每个字符。步骤对应原行号，不属于可执行源码。

## 代码节选

**C01　节点预算由有效尺寸倒推**　[v2/platform/cluster/create.sh](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/platform/cluster/create.sh#L30-L34) · L30–34

文件 SHA-256 `35878192a1e0af97548b4d83f8ee777909a56ab79bd3b0605cd124a355992928`；节选 SHA-256 `7c1604bf456cf35b1da44abd7071b6d087a6c3baebcac97268966f3ace1bd157`。共同缩进省略0空格；步骤：[(30, 30, '先声明每节点的目标预算；它不等于宿主机总内存。'), (32, 34, '读取宿主可见内存，再反算驱逐阈值；还要核对节点实际生效值。')]。

**C02　OrderStore.claim：用唯一约束占用业务键**　[v2/apps/storefront/src/storefront/orders/main.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/orders/main.py#L73-L86) · L73–86

文件 SHA-256 `12363f357bf91ce68e3e0be848ff9aa21077a44c84db3452c913d55214d53e24`；节选 SHA-256 `560232ef01bb58771a874226c0e8c21e1668b29199ec023fa95f362011acf6d1`。共同缩进省略4空格；步骤：[(77, 82, '用同一业务键插入PENDING；并发仲裁由数据库唯一约束执行。'), (85, 86, '若发生唯一冲突就返回False，调用方转入已有订单的重放路径。'), (84, 84, '若插入成功则返回True；只表示占键，库存、支付和确认尚未完成。')]。

**C03　重复键返回已有订单，可能仍为 PENDING**　[v2/apps/storefront/src/storefront/orders/main.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/orders/main.py#L199-L210) · L199–210

文件 SHA-256 `12363f357bf91ce68e3e0be848ff9aa21077a44c84db3452c913d55214d53e24`；节选 SHA-256 `01e9abd54b895cf8ae2dd39779791269d199ce3efbd0a243b942c51a54a464d1`。共同缩进省略4空格；步骤：[(200, 202, '接收并校验调用方的稳定键；重试时不能换键。'), (205, 206, '未占到键就查询原订单，不再创建第二笔订单。'), (208, 210, '返回原状态与重放标记；200仍可能携带PENDING。')]。

**C04　条件更新与事务共同防止部分预留**　[v2/apps/storefront/src/storefront/inventory/main.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/inventory/main.py#L48-L62) · L48–62

文件 SHA-256 `9de7dd5bd5278bfbd1d91769e8e1e7e39661ea7886beb09949c967ecdc500d69`；节选 SHA-256 `8b38eab34bba1f84359efd5ea05974903d064cc384ef8db7377e7d9082b0cdb7`。共同缩进省略12空格；步骤：[(48, 54, '同一事务内检查已有预留，再按固定商品顺序获取更新锁。'), (56, 60, '把库存条件与扣减放在同一条UPDATE，避免先读后写的窗口。'), (61, 62, '没有返回行就抛异常，使本事务之前的商品更新一起回滚。')]。

**C05　结果未知仍被当前实现归为失败**　[v2/apps/storefront/src/storefront/orders/main.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/orders/main.py#L246-L255) · L246–255

文件 SHA-256 `12363f357bf91ce68e3e0be848ff9aa21077a44c84db3452c913d55214d53e24`；节选 SHA-256 `6ba0916888b1ddc0724bfb21365ab9f17e2d45a0be7d0d3f796f2a7543dfe3cd`。共同缩进省略8空格；步骤：[(246, 249, '调用异常：尝试释放库存并标记FAILED；这不证明支付未执行。'), (250, 252, '402是明确拒付，采用PAYMENT_DECLINED分支。'), (253, 255, '其余非201也转FAILED；409仍可能是支付处理中，缺口见状态图。')]。

**C06　OrderStore.confirm：订单与事件共享事务**　[v2/apps/storefront/src/storefront/orders/main.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/orders/main.py#L101-L116) · L101–116

文件 SHA-256 `12363f357bf91ce68e3e0be848ff9aa21077a44c84db3452c913d55214d53e24`；节选 SHA-256 `0ee1ecc29c5a83debf5142a019f5361fc6a8b883551cc3d0c6c64f65866e18b6`。共同缩进省略4空格；步骤：[(104, 106, '进入一个本地事务，先把订单更新为CONFIRMED。'), (110, 116, '在同一事务插入事件与上下文；提交后两者一起可见，尚未包含NATS。')]。

**C07　Relay.publish_once：锁行、发布、再标记**　[v2/apps/storefront/src/storefront/orders/outbox.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/orders/outbox.py#L86-L109) · L86–102, L104–109

文件 SHA-256 `5beaaaccbf751b88eba5aa2948e8826029e9ee220ae9388e42d18ef99eb994b4`；节选 SHA-256 `df3a606bef2f3085f437a141d260b01d87692f869aab47c605f08b9cf836e376`。共同缩进省略4空格；步骤：[(87, 92, '事务中锁住待发批次；SKIP LOCKED让其他relay跳过这些行。'), (101, 102, '沿用event_id作为消息去重键，等待JetStream发布应答。'), (104, 109, '然后标记已发布；发布与事务提交之间崩溃仍可能重发。')]。

**C08　通知去重与 ACK 之间仍有失败窗口**　[v2/apps/storefront/src/storefront/notifier/main.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/notifier/main.py#L50-L82) · L50–64, L75–82

文件 SHA-256 `65d70651ed5d5a6c34735ccac92023db8a74574a70e09955a17c7c8104ff9122`；节选 SHA-256 `8d5c7160cfc26706dab87004fadc7c7b2302f4cb7256c731aebccb2033e493e6`。共同缩进省略4空格；步骤：[(59, 64, '先查完成标记，再执行模拟工作，最后保存24小时标记；三步不原子。'), (77, 78, 'handle成功才ACK；已存在标记时也能安全完成消息确认。'), (79, 82, '异常则NAK延迟重投；真实外部副作用仍需自己的幂等契约。')]。

**C09　Observe：直接包裹 ASGI send 与计时**　[v2/apps/storefront/src/storefront/common/web.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/web.py#L117-L147) · L117–132, L140–147

文件 SHA-256 `781e193439b892d6a8dc948dce6d8cf2292f67ab416e100f4efdd5e714d6c999`；节选 SHA-256 `7be502c6a74031e4c3887de0e337a77e10e841d711e209f18cc0382e1f336be9`。共同缩进省略8空格；步骤：[(119, 123, '在ASGI响应起始时获取真实状态与trace_id，再转发消息。'), (127, 131, '排除运维路径，业务请求才计时并增加在途数。'), (140, 147, '无论成功或异常都归还在途计数；有状态时记录同一计时区间。')]。

**C10　Chart 让出动态 replicas 字段**　[v2/gitops/charts/storefront-service/templates/deployment.yaml](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/gitops/charts/storefront-service/templates/deployment.yaml#L6-L15) · L6–15

文件 SHA-256 `0a55b07570103f48c19d6fd858f0dfc266577639b7b6108db151c59ae3c2cec3`；节选 SHA-256 `9b2c064d59d8dc24888e879a4e4d13a02faec50f9cc80b9e5529f9abd0d0ab68`。共同缩进省略0空格；步骤：[(7, 9, 'HPA或KEDA启用时省略replicas字段，避免静态声明争夺副本数。'), (13, 15, '滚动更新策略仍由Deployment负责；字段让权不等于放弃发布策略。')]。

**C11　用订单确认速率维持稳态副本数**　[v2/gitops/envs/prod/storefront/services/notifier.yaml](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/gitops/envs/prod/storefront/services/notifier.yaml#L32-L36) · L32–36

文件 SHA-256 `56efd93e5754f9c1e17e3138efb4d0833c39e9d8032427ca0557ea50508c83a0`；节选 SHA-256 `48e11fb7407890a7c08aa1b4b611dc86f543ec15beba080126c7ea2159c18d4b`。共同缩进省略4空格；步骤：[(32, 35, '从Prometheus读取已确认订单的每秒速率；先看rate的单位。'), (36, 36, '目标8事件/秒/副本用于稳态估算，不直接度量已有队列欠账。')]。

**C12　管理工作负载的权限包含间接能力**　[v2/gitops/platform/manifests/tenants/rbac.yaml](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/gitops/platform/manifests/tenants/rbac.yaml#L10-L27) · L10–19, L22–27

文件 SHA-256 `cafabdd714a8fe724c8a4cdef427d92edd3c967cf6e7bc38ab5c12a392371742`；节选 SHA-256 `06b3932804db760b567a0a49f4207682e014541369e6461b4852006195e64896`。共同缩进省略0空格；步骤：[(14, 19, '分别声明核心资源与日志子资源能执行的动作。'), (23, 24, 'exec与portforward是独立子资源权限，不能只检查Pod的增删改。'), (25, 27, '再授权apps组工作负载；命名空间绑定范围仍需单独核对。')]。

**C13　逻辑调用在整个尝试循环中占用隔舱**　[v2/apps/storefront/src/storefront/common/upstream.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/upstream.py#L73-L82) · L73–78, L80–82

文件 SHA-256 `2b22c3d8c4cea21c323df273325b39350340146576264bcb64b5e97cee29a9d2`；节选 SHA-256 `ee36d4ac4e3f86af1822d3bf00e804d00152810d339e7643f7d2dfaa9ce29de1`。共同缩进省略8空格；步骤：[(74, 76, '识别幂等条件，每次逻辑调用向预算存入一个比例份额。'), (80, 80, '在隔舱上下文内运行整个尝试循环；重试退避期间仍占该名额。'), (81, 82, '隔舱满就拒绝，不再发起尝试；本节省略指标更新，保留控制流。')]。

**C14　每次尝试先判断剩余期限与熔断**　[v2/apps/storefront/src/storefront/common/upstream.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/upstream.py#L89-L100) · L89–100

文件 SHA-256 `2b22c3d8c4cea21c323df273325b39350340146576264bcb64b5e97cee29a9d2`；节选 SHA-256 `860c15f6f32eb7e76b1e9fc8c2537e4db211cd463f6055f3374423f6292bc8cb`。共同缩进省略8空格；步骤：[(91, 95, '每次尝试先看总期限，再询问熔断器能否放行。'), (96, 100, '单次超时取策略值与剩余期限的较小者，再发起网络请求。')]。

**C15　令牌桶的初始值、上限与存取**　[v2/apps/storefront/src/storefront/common/resilience.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/resilience.py#L77-L89) · L77–89

文件 SHA-256 `3dfd7bf6a58643713f81d36a9a6599fe7247aeacf7036afde30275def6e69c1c`；节选 SHA-256 `5641a730b91d002c779e230314780d027ed1475b4b9b1681c3dca0266ccdac84`。共同缩进省略4空格；步骤：[(77, 80, '桶从max_tokens开始，默认允许10令牌初始突发。'), (82, 83, '每次逻辑调用存入ratio，余额不超过桶容量。'), (85, 89, '一次重试花1令牌；不足就拒绝，20%因此是长期比例而非逐窗硬上限。')]。

**C16　失败并不意味着一定重试**　[v2/apps/storefront/src/storefront/common/upstream.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/upstream.py#L108-L122) · L108–122

文件 SHA-256 `2b22c3d8c4cea21c323df273325b39350340146576264bcb64b5e97cee29a9d2`；节选 SHA-256 `44ab5cebe55c146b0d7dd1410092fb4151bca5f4796d186cd033d60c28b48946`。共同缩进省略12空格；步骤：[(110, 115, '记录本次结果，再同时检查幂等性、错误类别和剩余次数。'), (117, 119, '符合重试条件还要取到预算；不能取到就停止。'), (120, 122, '增加尝试计数并退避，随后回到期限与熔断检查。')]。

**C17　半开状态限制试探数量**　[v2/apps/storefront/src/storefront/common/resilience.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/resilience.py#L138-L147) · L138–147

文件 SHA-256 `3dfd7bf6a58643713f81d36a9a6599fe7247aeacf7036afde30275def6e69c1c`；节选 SHA-256 `42d9e2767cd976af2558db4853484fb03d66c9b4306a9e864266ea792685229b`。共同缩进省略4空格；步骤：[(139, 142, 'OPEN未到期拒绝；到期才转入HALF_OPEN。'), (143, 147, '半开限制试探总数，放行不表示已恢复；成功/失败记录另行驱动状态。')]。

**C18　Bulkhead：满则拒绝，退出时归还**　[v2/apps/storefront/src/storefront/common/resilience.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/resilience.py#L174-L190) · L174–190

文件 SHA-256 `3dfd7bf6a58643713f81d36a9a6599fe7247aeacf7036afde30275def6e69c1c`；节选 SHA-256 `670937f5c2b46a9b337c1184419b6a0989006338748bbdfdd663b228bdb433e7`。共同缩进省略4空格；步骤：[(174, 177, '初始化本进程内的并发额度，不是全服务共享额度。'), (179, 185, '满额立即拒绝，取得名额后才增加在途数。'), (187, 190, '上下文退出时归还计数和信号量，失败路径也必须释放。')]。

**C19　把已确认、明确失败和未知分开记录**　[v2/experiments/e7/writer.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/experiments/e7/writer.py#L75-L93) · L75–93

文件 SHA-256 `d9cbddb0b6d47758e846c630a4c8a07778603b14c542353bec8169f50f010e57`；节选 SHA-256 `2dcf6556d06c5b8f22d5fdbe736cf95cc93373f38de58ca7814bc5c761476a68`。共同缩进省略8空格；步骤：[(78, 83, '先连接再标记已发送；只有run返回后才记录ok。'), (84, 89, '服务器错误码可判明确失败；发出后断连、无明确结果则记unk。'), (90, 93, '网络/超时也按是否已发送分类；未知不能直接算成数据丢失。')]。

**C20　恢复后与真实行集合比较**　[v2/experiments/e7/writer_report.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/experiments/e7/writer_report.py#L32-L44) · L32–34, L41–44

文件 SHA-256 `36551984a6e938ea0372756efe6d65ea822347d3d00580ed8f569b61bb94089b`；节选 SHA-256 `c5a431c4004d33987d872ea1b3aa73012d5025779909969bcceaf85d466a3724`。共同缩进省略4空格；步骤：[(32, 34, '先按客户端结果分类；只把已确认ok却不在恢复库的序号计为lost。'), (41, 44, '另查未知中实际提交的记录，并验证fail分类有没有反例。')]。

**C21　先渲染，再检查即将部署的资源**　[v2/gitops/.gitlab-ci.yml](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/gitops/.gitlab-ci.yml#L7-L17) · L7–17

文件 SHA-256 `3c2f2548a7ab99f5326df2b8e9746612b317e45bd39817096362ff531f3f2f19`；节选 SHA-256 `30de5018711c201648d3216cc0a5931347648cb12911ba91fd2d77b5a9d447e7`。共同缩进省略0空格；步骤：[(7, 11, '先把声明渲染成具体资源，保存同一批清单供后续校验。'), (12, 17, '策略阶段依赖渲染产物，按生产与租户范围执行不同门禁。')]。

**C22　资源身份、批处理导出与库插桩**　[v2/apps/storefront/src/storefront/common/telemetry.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/telemetry.py#L38-L56) · L38–48, L52–56

文件 SHA-256 `1cbf576cb40d32252fae6ecea4fae2eced5940b1a66ce93074a9ea490f1a9471`；节选 SHA-256 `bc2a5cd3832cbda3de93e83d70892bbc76fe460ffe1d18b81c722dc1337e9390`。共同缩进省略4空格；步骤：[(38, 45, '先附加服务、版本、环境身份，避免把不同部署混成一个总体。'), (46, 48, '把带身份的span交给批处理与OTLP导出。'), (52, 56, '为HTTPX、数据库、缓存及FastAPI安装真实库插桩；不等于每个span都已保存。')]。

**C23　只把可追踪的错误或慢请求连到直方图**　[v2/apps/storefront/src/storefront/common/web.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/web.py#L149-L157) · L149–157

文件 SHA-256 `781e193439b892d6a8dc948dce6d8cf2292f67ab416e100f4efdd5e714d6c999`；节选 SHA-256 `c38f8d9b33f49798a098325a7feae91a9834a6c46f2f1b5fcba5b8ae6aa77659`。共同缩进省略4空格；步骤：[(150, 151, '用路由模板和状态计数，避免把具体商品ID扩成大量时间序列。'), (152, 154, '只有已有trace_id且满足慢/错条件时才附exemplar；直方图仍记录所有此处请求。'), (155, 157, '日志按错误、慢请求与抽样记录，不能把日志条数当请求总量。')]。

**C24　消息载体显式注入与提取追踪上下文**　[v2/apps/storefront/src/storefront/common/messaging.py](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/apps/storefront/src/storefront/common/messaging.py#L19-L26) · L19–26

文件 SHA-256 `9ffa0e62d049d470d606c93ca6afb121ae78fe90a4b3cf14ae290436c6f04cbb`；节选 SHA-256 `c57d6b62b98b22e0914e2a0af569d91c74e5dcbd62a98c6d721afe1e91535932`。共同缩进省略0空格；步骤：[(19, 22, '生产侧把当前追踪上下文注入载体，再随事件保存或发布。'), (25, 26, '消费侧从消息头提取上下文；创建消费span时还要显式使用它。')]。

**C25　已有 GitLab 项目的治理声明**　[v2/iac/gitlab/main.tf](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/iac/gitlab/main.tf#L12-L24) · L12–24

文件 SHA-256 `8d1e25fe1d87ebdcefad08a4e9c7c652d56264c82903829c912e4edfff8ad979`；节选 SHA-256 `8aa192fa43ca50605bae5ee585cab8f4261711afda1cc6f6a3d7461ff1b42e61`。共同缩进省略0空格；步骤：[(12, 16, '声明既有GitLab项目身份与默认分支；接管前先导入并比较。'), (17, 18, '合并要求成功流水线，skipped不算成功。'), (21, 23, 'prevent_destroy保护这个项目资源，不能覆盖另一资源的替换窗口。')]。

**C26　状态与计划在客户端加密并强制使用**　[v2/iac/gitlab/versions.tf](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/iac/gitlab/versions.tf#L19-L35) · L19–35

文件 SHA-256 `03ae4777d083f2d9e7b414275baa6459bac7094cfa795d4895f790ea355a9aef`；节选 SHA-256 `ffb0c153aa701d6cd2b2cdd2ec6d8817857ebbdbe71e56e7b14aed257b95f705`。共同缩进省略0空格；步骤：[(20, 24, '由仓库外口令派生键，再把键交给AES-GCM；这里不显示口令值。'), (26, 33, '状态与计划分别指定方法并强制加密；锁、访问权限与密钥恢复仍是独立问题。')]。

**C27　T3 的真实注入清单：阻断 payments**　[v2/assessment/t3-out-of-band.sh](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/assessment/t3-out-of-band.sh#L14-L20) · L14–20

文件 SHA-256 `61d6a10d9225b954f6db09ef177044e8a698130aa9b6c92f949d7c0e6d9adf33`；节选 SHA-256 `2dc6264c5422b95306949eabe83a80bb36070edf2b298c9646e32db799f19a95`。共同缩进省略0空格；步骤：[(14, 18, '注入对象位于storefront，并只选中payments工作负载。'), (19, 20, 'DENY配合空匹配规则拒绝命中范围的请求；这是故障注入，不是生产建议。')]。

**C28　T3 同时验证原因、业务与平台状态**　[v2/assessment/t3-out-of-band.sh](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/assessment/t3-out-of-band.sh#L24-L31) · L24–31

文件 SHA-256 `61d6a10d9225b954f6db09ef177044e8a698130aa9b6c92f949d7c0e6d9adf33`；节选 SHA-256 `1ed8965dcae4b244ea0687c7826926644b91dc221f4c68dc690811d3c283975e`。共同缩进省略0空格；步骤：[(26, 28, '先等待业务恢复，再同时检查额外对象与连续下单结果。'), (29, 31, '还要验证浏览与GitOps状态；四类断言一起决定结果。')]。

**C29　正例与负对照共同验证抑制行为**　[v2/assessment/p1-inhibition.sh](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/assessment/p1-inhibition.sh#L30-L47) · L30–37, L42–47

文件 SHA-256 `07dd675f89f42b491e2aeaaf19058fa9c8d3184bc9a352dfedd188b89fd3f95a`；节选 SHA-256 `c2772f5ebfb5cd9c5dc51fb8261ffe92b0933d764265cc375971e9cdfa4dbef6`。共同缩进省略0空格；步骤：[(30, 37, '同批设置源告警、依赖目标与不应被抑制的业务对照。'), (42, 47, '正负断言都要求告警存在，再检查inhibitedBy；消失不算被正确抑制。')]。


## 界面与终端素材

**S01　真实界面局部**　[v2/evidence/e1/grafana-trace-one-order.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e1/grafana-trace-one-order.png)

原图 SHA-256 `97a98d17aee33ada30ae8b1ccb8f8ec6f1879d1f4e15ed9f92406e8a62562a5c`；视窗（左、上、宽、高，原始像素）：[[1040, 1110, 680, 70], [35, 1555, 1120, 435]]。金色框坐标相对各视窗：[[[8, 5, 610, 53]], [[6, 3, 890, 65], [28, 150, 850, 180]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S02　真实界面局部**　[v2/evidence/e2/grafana-balance.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e2/grafana-balance.png)

原图 SHA-256 `bea21c94cbe203e31f5915c57e92a0f23ca82df371359a242fa7005e863626d4`；视窗（左、上、宽、高，原始像素）：[[30, 550, 1740, 440], [1815, 600, 565, 235]]。金色框坐标相对各视窗：[[[100, 65, 1575, 315]], [[5, 5, 550, 218]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S03　真实界面局部**　[v2/evidence/e2/grafana-trace-charged-but-failed.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e2/grafana-trace-charged-but-failed.png)

原图 SHA-256 `1a41df8b43b6db63e1d0c9c0499da31bd4e1de7fa1d44ca40797aa5a7760458c`；视窗（左、上、宽、高，原始像素）：[[40, 1065, 1120, 175], [1710, 1128, 620, 70]]。金色框坐标相对各视窗：[[[5, 65, 1030, 70]], [[290, 4, 210, 54]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S04　真实界面局部**　[v2/evidence/e3/grafana-capacity-one-replica.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e3/grafana-capacity-one-replica.png)

原图 SHA-256 `e027b4f8a7c07467d1f7817bfff4ca72a928efa55531278e60de76de120bf832`；视窗（左、上、宽、高，原始像素）：[[25, 440, 1160, 500], [1210, 440, 1160, 500]]。金色框坐标相对各视窗：[[[90, 75, 565, 335]], [[90, 80, 565, 320]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S05　真实界面局部**　[v2/evidence/e4/grafana-capacity-hpa-170.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e4/grafana-capacity-hpa-170.png)

原图 SHA-256 `2457bd6c4cecb13d39a15cd279907abd8d82f2dff74315db9b04df05c5f3e984`；视窗（左、上、宽、高，原始像素）：[[1205, 90, 1160, 340], [25, 440, 1160, 500]]。金色框坐标相对各视窗：[[[70, 50, 625, 240], [710, 100, 435, 181]], [[90, 65, 565, 350], [685, 167, 455, 138]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S06　真实界面局部**　[v2/evidence/e8/screens/grafana-release-canary-c1-c3-top.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e8/screens/grafana-release-canary-c1-c3-top.png)

原图 SHA-256 `7b408bd7feec6cf8f06e23ae0de973a8241d24bd0f39cb231a3a046125592bb3`；视窗（左、上、宽、高，原始像素）：[[1210, 85, 1165, 460], [25, 555, 1160, 430]]。金色框坐标相对各视窗：[[[90, 85, 585, 290]], [[130, 65, 545, 285]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S07　真实界面局部**　[v2/evidence/e9/screens/grafana-slo-incident-checkout.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e9/screens/grafana-slo-incident-checkout.png)

原图 SHA-256 `df94606ba2d6670efd5f16eb684f6d032c2cd01e12da03891a7c01cbed8cc35e`；视窗（左、上、宽、高，原始像素）：[[25, 95, 1160, 445]]。金色框坐标相对各视窗：[[[255, 75, 170, 315]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S09　真实界面局部**　[v2/evidence/e9/screens/grafana-exemplar-trace.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e9/screens/grafana-exemplar-trace.png)

原图 SHA-256 `e43696e233fc25578941d5206790f279b5b8f65a88f6ead2486d658b7e325d32`；视窗（左、上、宽、高，原始像素）：[[40, 1020, 1140, 230], [1750, 1130, 600, 80]]。金色框坐标相对各视窗：[[[5, 55, 1070, 125]], [[260, 5, 195, 48]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S08　真实界面局部**　[v2/evidence/e9/screens/grafana-slo-incident-checkout.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e9/screens/grafana-slo-incident-checkout.png)

原图 SHA-256 `df94606ba2d6670efd5f16eb684f6d032c2cd01e12da03891a7c01cbed8cc35e`；视窗（左、上、宽、高，原始像素）：[[25, 570, 1185, 435], [1220, 635, 350, 220]]。金色框坐标相对各视窗：[[[760, 55, 400, 335]], [[5, 65, 335, 40], [5, 137, 335, 43]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S10　终端记录节选**　[v2/evidence/e11/screens/gitlab-lock.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e11/screens/gitlab-lock.png)

原图 SHA-256 `be60a0cf0dd050e94e9894852f7e27cac38147bb6ada407875d17d55de253f1d`；视窗（左、上、宽、高，原始像素）：[[45, 160, 555, 42], [25, 238, 1230, 270]]。金色框坐标相对各视窗：[[[5, 3, 545, 36]], [[5, 3, 1210, 262]]]。仅出版视图裁剪/边框标注，原PNG未编辑。

**S11　终端记录节选**　[v2/evidence/e11/screens/drift.png](https://github.com/miku-wwl/devops-delivery/blob/510ec87a9f1b0756248e00f3b53d692ca27aeada/v2/evidence/e11/screens/drift.png)

原图 SHA-256 `226718e358c41b6914651b5d31ef5e302e2b4e3e7b1c44a10d61c1bf6df458e4`；视窗（左、上、宽、高，原始像素）：[[25, 280, 1450, 390]]。金色框坐标相对各视窗：[[[45, 62, 1090, 45], [90, 330, 1320, 55]]]。仅出版视图裁剪/边框标注，原PNG未编辑。


## 图表与机制源文件

### concept-env-nesting.svg

机制示意图；本章的实验环境是四层嵌套：Windows、WSL2 虚拟机、作为“节点”的 Docker 容器、Pod。每一层的上限都约束它里面的所有进程；三个工作节点各自固定在 4 个 CPU 上，内存由内核限制在 3 GiB。

源：`v2/manual/figures/concept-env-nesting.svg`；SHA-256 `906dea76ba2a77af9ea340f7acb2a4a255446043bd2d7b9500fe1243db2a7282`。

历史数据源：['evidence/e0/host.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-kubelet-capacity.svg

机制示意图；问题的根源：kubelet 的“容量”来自整台虚拟机的 /proc/meminfo，真正执行的上限却在节点容器的 cgroup 上。不修正的话，调度器以为每个节点有 15 GiB，驱逐阈值永远不会触发，最先出手的只能是内核的 OOM killer。

源：`v2/manual/figures/concept-kubelet-capacity.svg`；SHA-256 `fcfda0defc341e711fab6a415a04d3eaa407e0aef3c28eb0ccd2082c9dc5c371`。

历史数据源：['evidence/e0/baseline.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e0-memory-lines.svg

历史实测；一个工作节点的三条内存线（MiB）。把预留和驱逐阈值设成“从虚拟机的 15642 MiB 倒推”的值之后，三个角色的判断依次发生：调度器不会把 requests 放过 2666 MiB；实际用量到 2922 MiB 时 kubelet 按顺序驱逐 Pod；只有驱逐来不及时，内核才在 3072 MiB 杀进程。

源：`v2/manual/figures/e0-memory-lines.svg`；SHA-256 `696099857b2fef1c5f162de4d4298305b0be393544454f94589e09a6ddcbe00a`。

历史数据源：['evidence/e0/baseline.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-storefront.svg

机制示意图；storefront 的服务与数据：同步调用（实线）在请求路径上，订单确认后的通知经事务性 outbox 与 NATS 异步送达（虚线）。每个服务只访问自己的数据。

源：`v2/manual/figures/concept-storefront.svg`；SHA-256 `61561434429a54ff609a1acc33575d0ef1a2fa7a74c8e62cd7cb804f413362d6`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-saga.svg

机制示意图；编排式Saga的正常步骤与补偿路径；补偿是独立操作，也可能失败，不能当作跨服务数据库回滚。

源：`v2/manual/figures/concept-saga.svg`；SHA-256 `7dba9ef637e7958451e547bf486d1071e0898c3d8fe46da61113f4bbede98135`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### order-outcomes.svg

机制示意图；订单与支付拥有独立状态：超时只改变调用方的知识；虚线是尚未实现的对账设计，不是当前执行路径。

源：`v2/manual/illustrated/assets/order-outcomes.svg`；SHA-256 `7f12c450591e3e0da4f7ec93d2bea1f73ddec8a7f0a1da5c8e8db76e57663b75`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-outbox.svg

机制示意图；事务性Outbox的原子边界仅覆盖订单与事件行；发布后再标记可能重复，消费者仍需处理副作用窗口。

源：`v2/manual/illustrated/assets/concept-outbox.svg`；SHA-256 `d2f5f0d2121c2a8f647c0d3682cf0cf3f07437d02df95432be446c411c656e21`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-outbox.svg`，原图 SHA-256 `8a6bc4dfa5b1eba45a8c97ba85675adbf976f6d1e39717388680544b3e1ff73f`。原图保持不变；文字更正：{"任何一处崩溃，重来一遍都安全": "原子提交与副作用窗口是两回事", "不丢：事件和订单在同一个事务里提交": "事件与订单在同一事务里提交", "不重：中继在“发布”与“标记”之间崩溃会重发，": "发布后未标记：中继可能重发", "NATS 和 notifier 各去重一次": "消息去重仍不能消除任意副作用窗口"}；重绘说明：{"reason": "放大事务边界、发布后未标记的重复窗口和消费副作用窗口", "sources": ["v2/apps/storefront/src/storefront/orders/main.py", "v2/apps/storefront/src/storefront/orders/outbox.py", "v2/apps/storefront/src/storefront/notifier/main.py"]}。

### concept-app-of-apps.svg

机制示意图；E1初始GitOps布局：根Application创建分层子Application；这里的wave只描述该阶段，后续网格与安全资源扩展见第9章。

源：`v2/manual/illustrated/assets/concept-app-of-apps.svg`；SHA-256 `27c5dc4afda9c41e0edcc6cca823b78c2382c91e40c16c2d40d4dbfe9e12576c`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-app-of-apps.svg`，原图 SHA-256 `27c5dc4afda9c41e0edcc6cca823b78c2382c91e40c16c2d40d4dbfe9e12576c`。原图保持不变；文字更正：{}；重绘说明：{}。

### concept-l4-l7.svg

机制示意图；同一个调用方、两个副本，两种选择时机。少量长连接可能持续集中到同一后端；L7按请求选择。图中为E2实测份额取整：无网格97.1%/2.9%，waypoint后49.7%/50.3%。

源：`v2/manual/figures/concept-l4-l7.svg`；SHA-256 `290a01c0a8d15f7a72f02f3e63ca9f00650f4dc4bb81487ae079875667bb6fc2`。

历史数据源：['evidence/e2/mode-none.log', 'evidence/e2/mode-ambient-l7.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-ambient-path.svg

机制示意图；ambient 模式的数据路径：Pod 里没有 sidecar，流量被重定向到本节点的 ztunnel，节点之间用 HBONE（mTLS 上的 HTTP/2 CONNECT，端口 15008，图中的粗线）传输；需要第 7 层能力时，流量再经过一个 waypoint。

源：`v2/manual/figures/concept-ambient-path.svg`；SHA-256 `e96df3c67d3cb2695f43baa4d0bc56151231ad2c3ec3e22d938254a7070c5d89`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e2-ab.svg

历史实测；同一个问题的两种测法。第一次把“无网格”和“ambient”各跑一次，相隔 15 分钟：下单 p50 相差 32.4 ms。交替运行三轮之后，浏览的差值稳定在 2.1–2.7 ms，而下单的差值在 −0.6 到 +16.8 ms 之间摆动——它被 payments 人为生成的延迟淹没了，第一次的 +32 ms 大部分是两次运行之间的漂移。

源：`v2/manual/figures/e2-ab.svg`；SHA-256 `da210a9f9b34ad452e132ba2027dab778582cb93583e3acc4c7ff56756e984f1`。

历史数据源：['evidence/e2/mode-none.log', 'evidence/e2/mode-ambient-l4.log', 'evidence/e2/ab-mesh.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e2-retry-stack.svg

历史实测；场景 S3 中的重试叠加（数字为实测）：应用认为自己只发出了 7 次尝试，waypoint 上的路由为每一次又重试 3 次，payments 实际收到 28 次。每一层都只看得见自己的重试。

源：`v2/manual/figures/e2-retry-stack.svg`；SHA-256 `71287bc767d91af311e3313932cb7ac190af9030012f1fb6279591a346a170d3`。

历史数据源：['evidence/e2/retry-matrix.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### model-mm1.svg

模型曲线；响应时间律画成曲线（这是公式，不是测量）。利用率从 50% 到 80%，响应时间从服务时间的 2 倍变为 5 倍；越过 90% 之后，每多一点负载都换来成倍的等待。容量规划谈的“拐点”和“余量”，说的就是不要让任何一个组件长期停在曲线的右端。

源：`v2/manual/figures/model-mm1.svg`；SHA-256 `574507981938175971e32ef3984b54dcfaab1757bb07845eeb29071ae6e47469`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e3-latency-knee.svg

历史实测；同一次运行的延迟。160 迭代/秒以内，浏览的 p95 在 26–81 ms 之间；越过饱和点，它在一个档位之内变成 1.18 秒。这就是上面那条模型曲线在真实系统里的样子：拐点之前几乎没有征兆。

源：`v2/manual/figures/e3-latency-knee.svg`；SHA-256 `554d71e250dfd0eae33c702a2f8ee29c0fd59b900e684a297271f5a7f99635fc`。

历史数据源：['evidence/e3/step-ramp-high.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e3-caller-queue.svg

历史实测；排队发生在调用方。网关的 CPU 到 0.96 核之后，它“看到”的 catalog 调用从十几毫秒变成 630 毫秒以上，而 catalog 自己处理一个请求始终只要 2–3 毫秒：响应早已到达，只是网关的事件循环没有空闲去读它。只看被调用方的延迟，会完全错过这次饱和。

源：`v2/manual/figures/e3-caller-queue.svg`；SHA-256 `c99ae618ffa134e17583dd73f7ca4bcaa7695d107e364a327b0fc25604d13411`。

历史数据源：['evidence/e3/one-replica-2-analysis.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-hpa-loop.svg

机制示意图；HPA用观测值计算整数副本目标，再受容差、稳定窗口、策略与Pod启动约束；扩容决定不等于容量已经就绪。

源：`v2/manual/illustrated/assets/concept-hpa-loop.svg`；SHA-256 `9a5c4f5c774466b0cb90e5fb1754a5586786669093e974fb7b25681f76daeab8`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-hpa-loop.svg`，原图 SHA-256 `05824998126741771e252d9bc4184943eac00478984bb0adfa8cadabf2fa625e`。原图保持不变；文字更正：{"期望副本 = 当前副本 ×": "期望副本 = 向上取整", "当前指标 ÷ 目标": "当前副本 × 指标比值", "扩容：立即": "扩容：按策略执行"}；重绘说明：{"reason": "放大公式，分开目标计算、创建、Ready与实际分流", "sources": ["v2/manual/illustrated/chapters/05-scaling.md", "v2/evidence/e4"]}。

### e4-new-pods.svg

历史实测；扩容之后的一分钟里四个网关 Pod 各自的负载。两个原有的 Pod 仍在过载并返回 5xx，两个新 Pod 一个请求也没有收到：已有的长连接不会自己搬家。HPA 计算的是四个 Pod 的平均利用率，于是认为问题已经解决。

源：`v2/manual/figures/e4-new-pods.svg`；SHA-256 `863d6c6e9dee254d755bd247e091ef7fd6e17ec632ce5f3c5cead1dab6785c6d`。

历史数据源：['evidence/e4/hpa-2-pods.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e4-keda-oscillation.svg

历史实测；只按积压扩缩时的副本数。负载没有变化，副本数却在 1 和 5 之间来回：积压被消化完之后，“每个副本的积压”接近 0，KEDA 等满 300 秒的稳定窗口就缩到 1 个；一个副本处理不过来，积压重新出现，再扩容。积压衡量的是“排着多少”，不是“来得多快”。

源：`v2/manual/figures/e4-keda-oscillation.svg`；SHA-256 `adc861d1427ff3371252e47f9df50be44877300da8a4731688c25b09fde70709`。

历史数据源：['evidence/e4/keda-steady.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e4-neighbor.svg

历史实测；同一个 CPU 消耗者，声明不同的 CPU 请求。没有请求时，它只能用别人剩下的 CPU，同节点的网关几乎不受影响；声明 2 核的请求之后，内核按权重分配 CPU 时间（网关请求 500m，权重 20；消耗者请求 2 核，权重 79），网关在争抢中只分到一小份，p50 从 16 ms 变成 131 ms。CPU 请求不只是给调度器看的数字，它是争抢时的权重。

源：`v2/manual/figures/e4-neighbor.svg`；SHA-256 `a9a6f5f4fdb40bc20a3137cfd15e9548ca5c256e2ce8dd2b94bbfe8b7138fbb6`。

历史数据源：['evidence/e4/noisy.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-eviction-order.svg

机制示意图；E4中三个Pod的内存驱逐顺序：先看是否超出requests，再看优先级，最后看超出量。QoS类别不是直接排序键；超出160 MiB的BestEffort排在超出712 MiB的Burstable之后。

源：`v2/manual/figures/concept-eviction-order.svg`；SHA-256 `e5c63ac0099989f6211d926b08a84fccf8bd5b859bbcc4cfc5cc73ea5b06b5fa`。

历史数据源：['evidence/e4/eviction-2.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-api-request.svg

机制示意图；创建或修改对象的简化请求路径；授权通过不代表后续检查通过。审计按配置记录请求阶段与结果，不是逐个内部函数的完整执行轨迹。

源：`v2/manual/illustrated/assets/concept-api-request.svg`；SHA-256 `f2259d50d91be466d308985df3e466a0e1cf80ce03d5325aff87529404a06135`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-api-request.svg`，原图 SHA-256 `3f46a2691796f99c2fcf146f9334407b888a2b3271c957aa0573ca8564b5b60b`。原图保持不变；文字更正：{}；重绘说明：{"reason": "横向六小框改为两行，澄清授权、准入与审计覆盖范围", "sources": ["v2/manual/illustrated/chapters/06-security.md", "v2/evidence/e5"]}。

### concept-tenant-fences.svg

机制示意图；安全边界分工：身份授权、准入、网络、秘密、发布目标与审计共同约束访问；任何一层都不能替代其余层。

源：`v2/manual/illustrated/assets/concept-tenant-fences.svg`；SHA-256 `40fa3aebb44eefe1f71a1c75c51984600caaea772b362c2f9be352aec1f2ba43`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-tenant-fences.svg`，原图 SHA-256 `28639529c9c413286126e51503f217abcb7bf1ff41c3d9b43695efa323bbe847`。原图保持不变；文字更正：{"实验 1–3": "身份与授权", "实验 5": "准入与可用性", "实验 4": "网络与网格", "实验 7": "秘密与轮换", "实验 6": "发布目标", "不拦任何东西，事后回答　实验 3": "不负责拦截；用于事后追溯"}；重绘说明：{}。

### concept-netpol-mesh.svg

机制示意图；网格中 NetworkPolicy 看到的流量。应用以为自己在访问 8080，线上走的是到 15008 端口的隧道；有 waypoint 时，到达服务端的连接来自 waypoint 而不是客户端。按“客户端 → 服务端:8080”写的经典规则，对网格内的流量不起作用，对网格外的客户端才生效。

源：`v2/manual/figures/concept-netpol-mesh.svg`；SHA-256 `42e533587c1ba6c596a82dd804ee95d96083d81bdac111440fc1d6e44bcd2bbb`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e5-secret-rotation.svg

历史实测；一次密钥轮换的传播（时间为实测）。新值 8 秒内进入 Kubernetes Secret，挂载的文件 61 秒后跟上，环境变量永远不会——需要轮换的凭据应当以文件挂载，并由应用重新读取。

源：`v2/manual/figures/e5-secret-rotation.svg`；SHA-256 `b36b32ecd53425cf65732d8ab6e90d92a1d4872ac5718eb839a8053c69289881`。

历史数据源：['evidence/e5/secrets.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-resilience.svg

机制示意图；调用先占隔舱，每次尝试再检查期限与熔断；失败后的重试要经过预算与退避。20%是长期比例，并另有初始突发。

源：`v2/manual/illustrated/assets/concept-resilience.svg`；SHA-256 `56d37a3b1e265581e902bb4df361eed3c1e6d7a3addfb5378fbde788628ce35c`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-resilience.svg`，原图 SHA-256 `c9ec65fc88de1bb59946984608dcf25a62fc9a1230eafd9dc0e786f709ef7654`。原图保持不变；文字更正：{">熔断器</text>": ">截止时间</text>", "对方最近一直失败吗？": "总期限还有剩余吗？", "是：立即拒绝": "过期：立即拒绝", "超时与截止时间": "熔断器与单次超时", "这一次最多等多久？": "断开：立即拒绝", "1 秒，且不超过": "放行：最多1秒", "上游的剩余时间": "且不超过剩余时间", "重试总量不超过 20%": "长期20% + 初始突发"}；重绘说明：{"reason": "按真实执行顺序编号，分开逻辑调用与每次尝试", "sources": ["v2/apps/storefront/src/storefront/common/upstream.py", "v2/apps/storefront/src/storefront/common/resilience.py"]}。

### breaker-states.svg

机制示意图；熔断状态机与保护范围；按服务的熔断不区分健康与故障实例，半开只放有限试探。

源：`v2/manual/illustrated/assets/breaker-states.svg`；SHA-256 `1909e258c9a3e9114bb85ca77e603bb950c9bf44d393a7bdb76c73bb7f11e66b`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e6-amplification.svg

历史实测；同一个故障，两种模式打到故障依赖上的负载。inventory 已经在失败，naive 模式却把对它的调用放大到平时的 5 倍以上——故障中的服务最不需要的就是更多请求；resilient 模式几乎不再打扰它，代价是订单在这段时间里全部快速失败。

源：`v2/manual/figures/e6-amplification.svg`；SHA-256 `edb05f8ef36aafe45d592b091c56d2252bff2172934013d77a511c1f84a986ed`。

历史数据源：['evidence/e6/slow-resilient.log', 'evidence/e6/slow-naive.log', 'evidence/e6/errors-naive.log', 'evidence/e6/errors-resilient-2.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e6-node-failure.svg

历史实测；两次节点失效的对比。第一次，storefront 命名空间唯一的 waypoint 就在被冻结的节点上：所有经过它的请求全部失败，直到 300 秒的容忍期结束、Pod 在别的节点重建；第二次有两个 waypoint 副本，失败只持续到节点 NotReady、端点被移除为止。决定故障时长的不是节点何时恢复，而是 Kubernetes 何时停止向它发送流量。

源：`v2/manual/figures/e6-node-failure.svg`；SHA-256 `825f1e96b6c73c498e67272ec7712a82ecb53fba2903f307fe123d507d619d0d`。

历史数据源：['evidence/e6/node-1.log', 'evidence/e6/node-2.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-partition.svg

机制示意图；分区与节点失效的区别：数据面断了，控制面没有断。节点的心跳照常到达，Kubernetes 认为一切健康，不会移除任何端点；能发现问题的，只有发起连接的一方。

源：`v2/manual/figures/concept-partition.svg`；SHA-256 `6c75d70c9873d97394bfc6554da944ba1bab9c7a2284ea8de2e2439ecd79afbe`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-rpo-rto.svg

机制示意图；两个指标在时间轴上的位置（示意）。RPO 是故障之前、还没来得及送到安全之处的那一段数据——它由复制与归档的落后决定，在故障发生的那一刻就已经确定；RTO 是从故障到服务恢复的时间——发现、决定、执行、验证，每一步都算在内。

源：`v2/manual/figures/concept-rpo-rto.svg`；SHA-256 `ebe7dfa885310278ef46b961a7adfb5d51ced8ec085d9908255b12f981bfcb5b`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-commit-paths.svg

机制示意图；以简化时间线区分确认条件：异步不等备库；同步要等指定备库的确认。复制传输可以与本地提交并行，图中先后不是所有实际运行的固定时序。

源：`v2/manual/illustrated/assets/concept-commit-paths.svg`；SHA-256 `41f2aa9348aa24903a9162a30ac30302dcccc71c70894cbbea4bbb6dfed07c2a`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-commit-paths.svg`，原图 SHA-256 `17c3f4f4c8e4d875e1dc9b2d5b313b8548e2d01611cb2be22c4a0fd4ed2c0c31`。原图保持不变；文字更正：{"异步复制：先回答客户端，再发送 WAL": "异步复制：不等待备库落盘就回答", "稍后发送 WAL：落后的这一段，主库失效时就丢了": "异步发送WAL：未到备库的尾部仍有风险"}；重绘说明：{}。

### e7-failover.svg

历史实测；六种故障的两个结果：写入中断多久，丢了多少已经确认的写入。计划内的操作都在 30 秒以内；计划外的失效，时间主要花在“确认旧主库真的不在了”。唯一丢数据的是异步复制下的 F3；同步复制把它换成了更长的停顿——F4 的 137.9 秒里，主库宁可不接受写入，也不确认一个备库没有收到的提交。

源：`v2/manual/figures/e7-failover.svg`；SHA-256 `bc28e60d28c4fee74483d6c37bf5c4e0a8f782a8f5c23c92297335b74501e0a9`。

历史数据源：['evidence/e7/failover-results.md']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-wal-pitr.svg

机制示意图；恢复链由基础备份与连续WAL组成；archive_timeout触发切段，不保证对象存储在5分钟内收到完整归档。

源：`v2/manual/illustrated/assets/concept-wal-pitr.svg`；SHA-256 `599a41f2deab94bcfb11612864f148016c3c9d6b4c9ce1cd8b21a86c965a32d9`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-wal-pitr.svg`，原图 SHA-256 `69a176c67c999a43adc6273883511c6eaabf4f2d39839339a63c97a47f390eb0`。原图保持不变；文字更正：{"或最迟每 5 分钟": "5分钟触发切段"}；重绘说明：{}。

### concept-release-path.svg

机制示意图；本章的发布路径：每个改动都是一个合并请求，每道关卡都留下记录

源：`v2/manual/figures/concept-release-path.svg`；SHA-256 `fcbbf6e3c22144fb4ab5541ef456035c66a538f5ac32e837be87e087d084c9d5`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-canary-routes.svg

机制示意图；金丝雀的两条路由规则。带预览头的请求全部去金丝雀——团队可以在放量之前自己验证；其余的公共请求按权重分流。新版本出问题时，受影响的比例大约是“权重 × 失败率”，这就是爆炸半径。

源：`v2/manual/figures/concept-canary-routes.svg`；SHA-256 `f94461da722923b2e19b17b4c1c7796fe1e1a3667fa33cf2d720e0e61692f5d7`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e8-canary.svg

历史实测；金丝雀实验的四个数字。两种独立的统计都落在设定的 5% 附近；注入“一半请求返回 503”的故障之后，受影响的公共请求是 2.45%——权重（约 5%）乘以失败率（约 50%）。金丝雀没有让故障消失，它把故障的影响面缩小到可以从容撤回的程度。

源：`v2/manual/figures/e8-canary.svg`；SHA-256 `5a33a390c81a3f58562f4b27d9980d2c2a527f1186d0eb19b987d9506be68d75`。

历史数据源：['evidence/e8/canary-results.md']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-freeze-keys.svg

机制示意图；变更冻结的两把钥匙。第一把在合并之前：冻结期间，流水线只放行标明紧急的改动。第二把在合并之后：即使改动已经进入 main，Argo CD 的同步窗口也不把它带进集群。只有两把钥匙都打开，改动才会生效。

源：`v2/manual/figures/concept-freeze-keys.svg`；SHA-256 `501e510df6a4865d74045efffdafe04acce8a3b929543a282b5a2aba0bd32332`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### investigation-path.svg

机制示意图；从总体异常缩到一笔请求与源码，再用总体业务结果确认缓解；三种信号互相补足。

源：`v2/manual/illustrated/assets/investigation-path.svg`；SHA-256 `7df67bc8059d0b508418382638090f171dc45e2a8c381ee4028835360d0eefea`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-sampling.svg

机制示意图；头部决定在请求开始时发生；尾部决策只能使用到达采样器的数据，迟到、丢失或已被头部丢弃的span仍可能缺失。

源：`v2/manual/illustrated/assets/concept-sampling.svg`；SHA-256 `8d0c00c26c3a923f414bed96b2f694a76ed307112d7e69755790b2a4d734eb0d`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-sampling.svg`，原图 SHA-256 `90886e7094b8e4e65838d2bb21918b6bf1f14d357ff16f0f483c7cfde3146a1a`。原图保持不变；文字更正：{"等 10 秒，看完整条链路": "等约10秒，按已到达span判断"}；重绘说明：{}。

### concept-alert-chain.svg

机制示意图；本章的告警链路：通知离开集群，链路本身由心跳看守

源：`v2/manual/figures/concept-alert-chain.svg`；SHA-256 `1258abad23469500400999336b56f70b31b94f185fc232f702656b5e106e087f`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-kwok-env.svg

机制示意图；本章的实验环境。同一个 WSL 虚拟机中，前十章的实验集群 ent 与 kwokctl 启动的集群 scale 并存。scale 的控制面组件是真实的 Kubernetes v1.37.0 容器，每个都有内存上限（事故 E10-1 之后加上）；它管理的 1000 个节点和 10 000 个 Pod 只是 etcd 里的对象。

源：`v2/manual/figures/concept-kwok-env.svg`；SHA-256 `ad44c0b49a73b1aee27e6da98d5963067029ee7e4c61a48f9487cfcbd4f50b01`。

历史数据源：['experiments/e10/scale.sh']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e10-scheduling.svg

历史实测；一万个虚拟 Pod 进入 Running 的过程，每个点是一次实际计数。K1 在创建结束之后是一条直线，斜率每秒 50 个——调度器并不忙，它在等客户端限速的令牌。K2 放开限速后调度跟着创建走，29.4 秒全部调度完；Running 晚到 48.6 秒，是因为所有 Pod 的状态都由同一个 kwok 控制器写入。

源：`v2/manual/figures/e10-scheduling.svg`；SHA-256 `aa388bef81eb5bedd7d33a9dbe1eff9a36c4dd255f4f434bf3b9fa23c312ed52`。

历史数据源：['evidence/e10/k1/timeline.txt', 'evidence/e10/k2/timeline.txt']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-etcd-space.svg

机制示意图；etcd 的空间去了哪里。每次写入都留下一个新版本；压缩只是把旧版本占的页面标记为空闲，文件并不变小；碎片整理才把空间还给文件系统。任由它增长，最终会撞上配额：整个集群只能读和删除，不能再创建任何对象。

源：`v2/manual/figures/concept-etcd-space.svg`；SHA-256 `5c12ae4d1597ab9e40d825daf512b3c956fe9f0979486deaeadf097ab65efd3f`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e10-etcd.svg

历史实测；删除 10 000 个 Pod 前后的 etcd。灰柱是数据库文件，绿柱是其中的有效数据：删除让文件增大；API server 的压缩把有效数据降到 24.3 MiB，文件却没有变小；碎片整理之后文件才变为 18.7 MiB。

源：`v2/manual/figures/e10-etcd.svg`；SHA-256 `ccf5f1baace640bdb5f7cfaa77ec381d291c299c5fba071a7dde26f4edda7d73`。

历史数据源：['evidence/e10/k3-clean.log', 'evidence/e10/k3-etcd.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-list-paths.svg

机制示意图；本次Kubernetes v1.37中观察的LIST与缓存路径：一致读取得revision后等待缓存追平；rv=0可使用已有视图。不同版本、分页与参数组合仍需分别核对。

源：`v2/manual/illustrated/assets/concept-list-paths.svg`；SHA-256 `12aa6118accfd902814f0754eb787ddce28f7b1296b32491be83484500080609`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

本版教学修订源于 `v2/manual/figures/concept-list-paths.svg`，原图 SHA-256 `3124c271eede8910c5ae46d42dcc0bdef197a0309067c18b19d3165ed2e9f7bc`。原图保持不变；文字更正：{}；重绘说明：{"reason": "分开两种LIST条件与缓存更新，避免小字号和跨版本绝对化", "sources": ["v2/manual/illustrated/chapters/11-controlplane.md", "v2/evidence/e10"]}。

### concept-apf.svg

机制示意图；APF 处理一个请求的过程。FlowSchema 把请求分到一个优先级；优先级有自己的名义席位，没有空席位就排队，队列满了立即返回 429。繁忙的优先级还可以借用别的优先级空闲的席位——除非显式把借用上限设为 0。整个过程只数“同时执行多少个请求”，不看每个请求要用多少内存。

源：`v2/manual/figures/concept-apf.svg`；SHA-256 `98e5df91d72406ec388a2fec1a53388fb7879428a7bd3c5312bd1a7d66df4871`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e10-apiserver-memory.svg

历史实测；洪水期间 API server 的匿名内存，每秒一个采样点。两次运行中优先级 e10-low 都只有 3 个 LIST 在执行；曲线落到 0 的地方，是进程被内核杀死、Docker 重启它的时刻。上限 1536 MiB 时它在 4 秒内被杀，之后反复被杀；上限 2560 MiB 时，三个并发的 LIST 把它推到 2437 MiB，10 秒后越过上限被杀一次，重启后在同样的洪水下维持在 1.6–2.0 GiB。

源：`v2/manual/figures/e10-apiserver-memory.svg`；SHA-256 `508f045d1cfdf16230f8ef1c573954f198fdc5118da2b74aab6f24a650180a99`。

历史数据源：['evidence/e10/k8/apf-apiserver-mem.txt', 'evidence/e10/k9/apf-apiserver-mem.txt']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-iac-split.svg

机制示意图；对象所有权与状态位置：Argo CD管理集群中受跟踪的声明，从E11起管理自己；OpenTofu管理GitLab门禁，状态由GitLab加锁、客户端加密。原Garage后端因锁测试失败而停用。

源：`v2/manual/figures/concept-iac-split.svg`；SHA-256 `ae385cdbb0abfd5c1e5ac619ddacbdd1b8d13955201da01c65a6ca0dd21e9120`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### concept-state-lock.svg

机制示意图；锁保护的是什么。两个运行同时开始：只有后端能保证“只在不存在时才写入”，第二个加锁请求才会失败，B 才会停下。后端做不到这一点时，B 的加锁同样“成功”，两个运行读到同一份状态，后写回的覆盖先写回的——先写的那一方创建的资源，从此不在任何状态里。

源：`v2/manual/figures/concept-state-lock.svg`；SHA-256 `baf3fb5d8f3e25043099455f1666cf90d9b7d76320e8754c7eb0798da1908366`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e11-argocd-upgrade.svg

历史实测；Argo CD 经合并请求升级自己（2026-11-10，合并请求 !45；门禁的流水线 31 秒）。时间从合并起算：Argo CD 轮询 Git，244 秒后才看到新版本；同步本身 24 秒；它的组件依次滚动，应用控制器在自己的同步完成之后才被替换；315 秒时回到 Synced 和 Healthy。

源：`v2/manual/figures/e11-argocd-upgrade.svg`；SHA-256 `5e724832b0dee9b383438ca90e94d051eea4fba4ebfa1d4f3fe4bf5f28990757`。

历史数据源：['evidence/e11/i4/upgrade.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。

### assessment-tree.svg

机制示意图；T3综合诊断的竞争假设；健康状态的覆盖范围与实际请求路径不同，观察应能够区分原因。

源：`v2/manual/illustrated/assets/assessment-tree.svg`；SHA-256 `ca9b1e26de2e6571cfe0511eda9acd4261dd2e03d14196975a4591a7e48a532d`。

历史数据源：[]。新增图的机制依据见 illustrations.py 与相邻代码节选。

### e12-grading.svg

历史实测；四道题在两种状态下的判分。红色是故障存在时通过的检查项数，绿色是修复之后：每一道题都是“故障存在时不能全过，修复之后全过”，判分脚本才算可信。T2 和 T3 在故障存在时仍有两项通过——那两项检查的是症状，而症状有时会滞后或被掩盖。

源：`v2/manual/figures/e12-grading.svg`；SHA-256 `27b66163c8dd93801db9b0652f6a65f4a410ef3f21ff8b547ae61d0a2b2ead92`。

历史数据源：['evidence/e12/t1.log', 'evidence/e12/t2.log', 'evidence/e12/t3.log', 'evidence/e12/p1.log']。新增图的机制依据见 illustrations.py 与相邻代码节选。


## 教学设计参考

高中物理·加速度，文件 `高中物理_加速度_四页样章.pdf`，4页。用户提供的教学设计参考；已阅读全文并逐页视觉审读；参考PDF保留在用户原目录。审读日期：2026-11-16；完整原文件SHA-256 `7734044f418f235d86e5b14592bccf851f3e37c4bfb7817cee3068b7788a0c44`。

对照评估：`v2/docs/illustrated/REFERENCE-REVIEW.md`。该样章不是工程运行证据。
