# 打包与部署：Kubernetes 基础与 Helm（P3 / D3） {#ch-p3}

<div class="lead">CI 产出的是镜像，镜像要变成“在集群里稳定运行的服务”，还需要一组 Kubernetes 对象。本章先用最少的篇幅讲清这些对象，再用 Helm 把它们做成一个可参数化、可版本化、可回滚的 Chart：同一个 Chart 按环境部署到 dev 和 prod，经历一次正常升级、一次“坏配置发布”和一次回滚，最后以 OCI 制品的形式发布 Chart 本身。</div>

## 本章目标与产出

| 产出 | 位置 |
|---|---|
| 实验集群（1 控制面 + 2 工作节点）与本地镜像仓库 | `delivery/kind/lab-cluster.yaml`、`create-lab-cluster.sh` |
| demo-api 的 Helm Chart（含 values schema 与 helm test） | `delivery/helm/demo-api/` |
| 环境差异配置 | `values-dev.yaml`、`values-prod.yaml` |
| 探测脚本（统计 HTTP 状态码） | `delivery/kind/probe.sh` |

**验收标准（路线图 D3）：** 可重复部署同一应用，配置按环境区分。已通过：dev（1 副本）与 prod（3 副本 + PDB + 反亲和）由同一 Chart 部署，升级、坏发布、回滚全过程有记录（`evidence/p3/`）。

**学完本章，你应当能够：**

- 用“期望状态 + 控制器调和”解释 Kubernetes 的工作方式，说清 Deployment、ReplicaSet、Service、ConfigMap、PDB 的分工；
- 理解 Pod 模板哈希如何驱动滚动更新，以及它为什么贯穿后面的金丝雀发布；
- 编写带 values schema、安全默认值和环境差异文件的 Helm Chart，并用 `lint`、`template`、`diff` 审查它；
- 完成安装、升级、坏发布和回滚，并说明 Helm 回滚与 GitOps 回滚的区别。

## 原理一：最小够用的 Kubernetes {#p3-k8s}

Kubernetes 是一个**声明式**系统：你把“期望状态”（例如“运行 3 个 demo-api 0.1.1 的副本”）以对象的形式提交给 API Server，各种**控制器**不停地比较“期望状态”与“实际状态”，并采取行动消除差异。这个“观察 → 比较 → 行动”的循环叫**调和（reconcile）**，是理解 Kubernetes、GitOps（第 6 章）和渐进式交付（第 8 章）的钥匙。

```{.mermaid caption="demo-api 在集群中涉及的对象及其关系"}
flowchart LR
  subgraph NS["Namespace: prod（Pod Security: restricted）"]
    D["Deployment<br/>replicas: 3"] -->|管理| RS["ReplicaSet<br/>（每个版本一个）"]
    RS -->|创建| P1["Pod"] & P2["Pod"] & P3["Pod"]
    CM["ConfigMap<br/>FAULT_* 配置"] -.->|envFrom| P1
    SA["ServiceAccount<br/>不挂载 Token"] -.-> P1
    SVC["Service<br/>ClusterIP :80"] -->|按标签选择| P1 & P2 & P3
    PDB["PodDisruptionBudget<br/>minAvailable: 2"] -.->|保护| P1
  end
  Client["集群内客户端<br/>（helm test / 探测）"] --> SVC
```

| 对象 | 作用 | 本章中的要点 |
|---|---|---|
| **Pod** | 最小调度单位，包含一个或多个容器 | 安全上下文、探针、资源限制都写在 Pod 模板里 |
| **Deployment** | 声明副本数与 Pod 模板，负责滚动更新 | 每次 Pod 模板变化都会生成新的 ReplicaSet，旧的保留用于回滚 |
| **Service** | 为一组 Pod 提供稳定的虚拟 IP 和 DNS 名称 | 通过**标签选择器**找到 Pod；Pod 换了 IP 也不影响调用方 |
| **ConfigMap** | 非敏感配置 | 通过 `envFrom` 注入为环境变量 |
| **ServiceAccount** | Pod 访问 API Server 的身份 | demo-api 不需要访问 API，所以不挂载令牌 |
| **PodDisruptionBudget** | 限制“自愿中断”（节点维护、驱逐）时同时不可用的 Pod 数 | prod 要求至少 2 个可用 |
| **Namespace** | 逻辑隔离与配额、策略的边界 | `dev`、`prod` 两个命名空间 |

**探针（Probe）：** `readinessProbe` 决定 Pod 是否接收流量（未就绪时会从 Service 的后端列表中摘除）；`livenessProbe` 决定容器是否要被重启。二者用途不同，不能混用：把依赖数据库的检查放进 liveness，数据库抖一下就会导致所有 Pod 被重启。readiness 还是滚动更新的“节拍器”：Deployment 只有在新 Pod 就绪之后，才会继续缩减旧 Pod（由 `maxSurge`、`maxUnavailable` 控制步幅，默认各 25%）。一个永远不就绪的新版本会让滚动更新停住，而不是把旧版本全部替换掉。

::: principle
**Pod 模板哈希：本书反复用到的机制。** Deployment 会对 Pod 模板（`spec.template`）计算一个哈希，作为 ReplicaSet 名称的后缀和 Pod 的标签 `pod-template-hash`。模板中任何一个字段变了（镜像、环境变量、注解），哈希就变，Deployment 创建新的 ReplicaSet 并开始滚动更新；模板没变，就什么也不发生。旧的 ReplicaSet 缩到 0 后仍被保留，`kubectl rollout undo` 就是把它们重新扩起来。

后面的章节都建立在这个机制上：本章的 `checksum/config` 注解靠改变模板来触发重启；第 8 章的 Argo Rollouts 用同样的哈希（标签 `rollouts-pod-template-hash`）区分稳定版和金丝雀，分析查询也按它过滤；第 12 章只改配置也会产生新的修订，是因为 Chart 0.3.1 把配置写进了 Pod 模板。
:::

**Pod 安全标准（Pod Security Standards）：** Kubernetes 内置三档策略：`privileged`、`baseline`、`restricted`。给命名空间打上标签 `pod-security.kubernetes.io/enforce=restricted` 后，任何不满足最严格要求的 Pod（以 root 运行、允许提权、未丢弃 Linux capabilities、未设置 seccomp 等）都会被**直接拒绝创建**。本章的 dev、prod 都启用了 `restricted`，Chart 必须“生来安全”。

## 原理二：Helm 解决什么问题 {#p3-helm}

直接用 `kubectl apply` 管理 YAML 会遇到三个问题：同一份清单要部署到多个环境，只能复制后手改；一次发布由多个对象组成，没有“版本”的概念，出了问题不知道回滚到哪里；清单不能像软件包一样发布、引用。Helm 正是“Kubernetes 的包管理器”：

| 概念 | 含义 |
|---|---|
| **Chart** | 一个包：模板（`templates/`）+ 默认值（`values.yaml`）+ 元数据（`Chart.yaml`） |
| **Values** | 模板参数。优先级：`--set` / `--set-json` > 后面的 `-f` 文件 > 前面的 `-f` 文件 > Chart 默认值 |
| **Release** | Chart 在某个命名空间中的一次安装实例，例如 `demo-api-prod` |
| **Revision** | Release 的每次变更（install、upgrade、rollback）都产生一个新的修订号，完整的渲染结果保存在集群的 Secret 中 |
| **Repository / OCI** | Chart 的分发方式。Helm 3.8 起支持把 Chart 当作 OCI 制品推送到镜像仓库 |

```{.mermaid caption="helm upgrade 的工作流程"}
flowchart TB
  V["values.yaml<br/>values-prod.yaml<br/>--set-json"] --> S{"values.schema.json<br/>校验"}
  S -- 不通过 --> X["立即失败<br/>不产生新修订"]
  S -- 通过 --> T["渲染 templates/<br/>得到 Kubernetes 清单"]
  T --> API["API Server<br/>创建 / 更新对象"]
  API --> R["保存修订 N+1<br/>（一个 Secret）"]
  R --> W["--wait<br/>等待资源就绪"]
```

## 第 1 步：实验集群与本地镜像仓库 {#p3-cluster}

P0 的冒烟集群只有一个节点；从本章起使用一个“像样一点”的集群：1 个控制面节点 + 2 个工作节点，这样才能观察到 Pod 分布、反亲和、PDB 的效果。

镜像如何进入 Kind 集群？有两种方式：`kind load docker-image` 把镜像直接复制进每个节点；或者运行一个本地镜像仓库，节点像在真实环境中一样从仓库**拉取**。后者更接近生产（按 digest 拉取、仓库可以被扫描和签名），也是 Kind 官方文档 “Local Registry” 一节推荐的做法。`create-lab-cluster.sh` 的关键步骤：

```bash
# 1. registry container (Distribution / registry:3) on the host's loopback
docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --network bridge \
  --name "$REG_NAME" registry:3.1.2

# 2. cluster
kind create cluster --config "$HERE/lab-cluster.yaml" --image "$KIND_NODE_IMAGE" --wait 180s

# 3. tell containerd on every node that localhost:5001 means http://kind-registry:5000
for node in $(kind get nodes --name lab); do
  docker exec "$node" mkdir -p "/etc/containerd/certs.d/localhost:${REG_PORT}"
  printf '[host."http://%s:5000"]\n' "$REG_NAME" |
    docker exec -i "$node" cp /dev/stdin "/etc/containerd/certs.d/localhost:${REG_PORT}/hosts.toml"
done

# 4. put the registry on the kind network so nodes can resolve "kind-registry"
docker network connect kind "$REG_NAME"

# 5. advertise the registry (KEP-1755 "local-registry-hosting")
kubectl apply -f - <<EOF  # ConfigMap kube-public/local-registry-hosting ...
```

这里有一个“同名不同义”的细节值得体会：在 WSL 主机上，`localhost:5001` 指向仓库容器的映射端口；但在 Kind 节点（容器）里，`localhost` 是节点自己。第 3 步通过 containerd 的 `hosts.toml` 告诉节点：“当你要拉 `localhost:5001/...` 时，实际去 `http://kind-registry:5000`”。这样，同一个镜像名在主机和集群中都能用。

::: note
较早的 Kind 教程会在集群配置里加一段 `containerdConfigPatches`，把 containerd 的 `config_path` 指向 `/etc/containerd/certs.d`。Kind v0.27 起的节点镜像已默认如此（且 containerd 2.x 改了插件名，照抄旧补丁反而可能出错），所以本项目的 `lab-cluster.yaml` 不需要任何补丁。
:::

执行结果（节选，完整记录：`evidence/p3/cluster.log`）：

```console
$ bash delivery/kind/create-lab-cluster.sh
 ✓ Joining worker nodes 🚜
 • Ready after 9s 💚
configmap/local-registry-hosting created
NAME                STATUS   ROLES           AGE   VERSION   INTERNAL-IP   ...   CONTAINER-RUNTIME
lab-control-plane   Ready    control-plane   26s   v1.37.0   172.18.0.2    ...   containerd://2.3.4
lab-worker          Ready    <none>          12s   v1.37.0   172.18.0.4    ...   containerd://2.3.4
lab-worker2         Ready    <none>          13s   v1.37.0   172.18.0.3    ...   containerd://2.3.4

$ for n in $(kind get nodes --name lab); do echo "$n: $(docker exec $n cat /etc/containerd/certs.d/localhost:5001/hosts.toml)"; done
lab-worker2: [host."http://kind-registry:5000"]
lab-control-plane: [host."http://kind-registry:5000"]
lab-worker: [host."http://kind-registry:5000"]
```

## 第 2 步：Chart 结构与模板解析 {#p3-chart}

```text
delivery/helm/demo-api/
├── Chart.yaml            # 名称、Chart 版本（version）、应用版本（appVersion）
├── values.yaml           # 默认值（安全默认：restricted 级别的安全上下文）
├── values-dev.yaml       # dev 只覆盖与默认不同的部分
├── values-prod.yaml      # prod：3 副本、PDB、反亲和、更大的资源
├── values.schema.json    # values 的 JSON Schema，lint / install / upgrade 时强制校验
├── .helmignore
└── templates/
    ├── _helpers.tpl      # 命名、标签、镜像引用等可复用片段
    ├── configmap.yaml
    ├── deployment.yaml
    ├── service.yaml
    ├── serviceaccount.yaml
    ├── pdb.yaml          # podDisruptionBudget.enabled 时才渲染
    ├── hpa.yaml          # autoscaling.enabled 时才渲染（需要 metrics-server）
    ├── NOTES.txt         # 安装后打印的使用说明
    └── tests/test-connection.yaml   # helm test 钩子
```

**两个版本号。** `Chart.yaml` 中的 `version` 是 **Chart 自身**的版本（模板改了就要升）；`appVersion` 是它默认部署的**应用**版本。二者独立演进。后面你会看到 `helm history` 的 `APP VERSION` 列显示的是 `appVersion`，而不是你用 `--set image.tag` 覆盖后的实际镜像版本——这是一个常见误解。

### 辅助模板：`_helpers.tpl`

```text
{{/* Labels used to select pods - must never change after the first install. */}}
{{- define "demo-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "demo-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Image reference: repository@digest when a digest is pinned, otherwise repository:tag. */}}
{{- define "demo-api.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (include "demo-api.imageTag" .) -}}
{{- end -}}
{{- end -}}
```

- **选择器标签必须稳定。** Deployment 的 `spec.selector` 创建后不可修改。所以选择器只用 `name` 和 `instance` 两个永远不变的标签，版本号之类会变的标签只放在普通 `labels` 里。
- **按 digest 引用镜像。** 第 7 章会把 CI 构建出的镜像以 `repository@sha256:...` 的形式晋级到各环境；这里提前预留了 `image.digest`。

### Deployment 模板中的关键写法

```yaml
  template:
    metadata:
      annotations:
        # Changing the ConfigMap changes this hash, which rolls the pods.
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      serviceAccountName: {{ include "demo-api.fullname" . }}
      automountServiceAccountToken: false
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: demo-api
          image: {{ include "demo-api.image" . | quote }}
          envFrom:
            - configMapRef:
                name: {{ include "demo-api.fullname" . }}
          readinessProbe:
            httpGet: { path: /readyz, port: http }
          livenessProbe:
            httpGet: { path: /healthz, port: http }
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
```

**`checksum/config` 注解**是 Helm 社区的经典技巧。环境变量只在容器启动时读取一次，单独修改 ConfigMap 不会让正在运行的 Pod 生效。把 ConfigMap 渲染结果的 SHA-256 写进 Pod 模板的注解，ConfigMap 一变，Pod 模板随之改变，Deployment 就会自动滚动更新。后面的坏发布演练正是靠它让新配置立刻生效的。

::: warning
**后文的修订。** 这个技巧解决了“配置改了、Pod 不重启”的问题，但留下一个隐患：新旧 ReplicaSet 读取的是**同一个** ConfigMap。旧版本的 Pod 只要在配置变更之后重建（扩容、节点故障、被驱逐），读到的就是新配置。滚动更新很快结束，这个窗口通常不显眼；第 8 章的金丝雀发布会长时间同时运行两个版本，并且会在中止时扩容稳定版，隐患就变成了真实的问题。第 9 章记录了这次问题，并在 Chart 0.3.1 中把发布配置直接写进 Pod 模板的 `env`，`checksum/config` 注解随之删除。
:::

**只读根文件系统 + `/tmp` 空目录卷：** `readOnlyRootFilesystem: true` 让攻击者即使拿到容器内执行权限，也无法改写程序文件；应用若需要临时文件，挂一个 `emptyDir` 到 `/tmp`。

### values.schema.json：把错误挡在集群之外

```json
"environment": { "enum": ["dev", "staging", "prod"] },
"faults": {
  "type": "object",
  "properties": {
    "errorRate": { "type": "number", "minimum": 0, "maximum": 1 },
    "latencyMs": { "type": "number", "minimum": 0 }
  }
}
```

有了 schema，`helm lint`、`helm install`、`helm upgrade` 都会先校验 values，不合格就直接失败，不会生成新修订。下一步就会看到它拦下的两个真实错误。

## 第 3 步：静态检查——lint、schema 与 template {#p3-lint}

![helm lint：三种 values 组合都通过；故意传入非法值时被 schema 拦截（终端记录渲染）](../../evidence/p3/helm-lint-schema.png)

`[INFO] Chart.yaml: icon is recommended` 只是建议，不影响结果。反例中，`--set faults.errorRate=2 --set environment=production` 同时违反了两条约束，schema 给出了精确的路径与原因。

`helm template` 在本地渲染出最终清单，不接触集群，是审查 Chart 的最佳方式。用同一个 Release 名分别渲染 dev 和 prod，再做 diff，就能清楚看到“环境差异到底是什么”：

```console
$ grep -c '^kind:' /tmp/dev.yaml /tmp/prod.yaml
/tmp/dev.yaml:5
/tmp/prod.yaml:6
$ diff -u /tmp/dev.yaml /tmp/prod.yaml | grep -E '^[-+][^-+]' | grep -v 'environment:'
+kind: PodDisruptionBudget
+  minAvailable: 2
-  replicas: 1
+  replicas: 3
-        checksum/config: a4b55415d2f0b69ef9942a324f5a9b5215eb98f358df08374b60c48f71513af9
+        checksum/config: dab4d135c88383c6afcb181041914ab0cda32a8a55a6899e7b150865725570d5
-              cpu: 250m
+              cpu: "1"
+      affinity:
+        podAntiAffinity:
+          preferredDuringSchedulingIgnoredDuringExecution: ...
[exit 1]
```

（`diff` 在两个文件不同时返回 1，这里的 `[exit 1]` 是预期的。）你可能会好奇：两个环境的故障注入值都是 0，为什么 `checksum/config` 不同？因为 ConfigMap 的 `metadata.labels` 中包含 `environment: dev/prod`，哈希覆盖的是整个渲染结果。

::: warning
**一个在 diff 中发现的设计缺陷。** 最初的 `values-prod.yaml` 直接写了反亲和规则，选择器里硬编码了 `app.kubernetes.io/instance: demo-api-prod`。diff 一出来就暴露了问题：一旦 Release 换个名字，这条规则会静默失效（选不中任何 Pod，也不报错）。修正方法是在模板中根据 Chart 自己的 `selectorLabels` 生成规则，values 中只保留一个开关 `podAntiAffinityPreset: soft`。**教训：values 文件不应该猜测 Release 名称。**
:::

## 第 4 步：安装到 dev 与 prod {#p3-install}

```bash
# 构建镜像并推送到本地仓库
docker build --build-arg APP_VERSION=0.1.0 --build-arg GIT_SHA=$(git rev-parse --short HEAD) \
  -t localhost:5001/demo-api:0.1.0 app
docker push localhost:5001/demo-api:0.1.0

# 两个命名空间都强制 restricted 级别的 Pod 安全标准
for ns in dev prod; do
  kubectl create namespace $ns
  kubectl label namespace $ns pod-security.kubernetes.io/enforce=restricted \
                             pod-security.kubernetes.io/warn=restricted
done

helm install demo-api-dev  delivery/helm/demo-api -n dev  -f delivery/helm/demo-api/values-dev.yaml  --wait --timeout 3m
helm install demo-api-prod delivery/helm/demo-api -n prod -f delivery/helm/demo-api/values-prod.yaml --wait --timeout 3m
helm test demo-api-dev -n dev --logs
```

![安装结果：prod 3 个副本分布在两个工作节点、PDB 允许 1 个中断；helm test 通过并打印接口响应（终端记录渲染）](../../evidence/p3/helm-install-prod.png)

观察要点：

- `--wait` 让 Helm 等到资源真正就绪才返回成功；没有它，`helm install` 在对象“提交成功”时就返回了，Pod 可能还在崩溃重启。
- prod 的 3 个 Pod 落在 `lab-worker`（2 个）和 `lab-worker2`（1 个）上：控制面节点带有 `NoSchedule` 污点，只有 2 个工作节点可用；“软”反亲和（preferred）在无法完全满足时仍允许调度。若改成“硬”反亲和（required），第三个 Pod 会一直 Pending。
- PDB 显示 `ALLOWED DISRUPTIONS 1`：3 个副本、至少 2 个可用，所以同一时间只允许驱逐 1 个。
- 所有 Pod 都通过了 `restricted` 策略的准入检查，没有任何警告——这正是 Chart 默认安全上下文的价值。
- `helm test` 启动了 `tests/test-connection.yaml` 中定义的 Pod（同样满足 restricted），它依次调用健康检查、信息接口和下单接口；Pod 以退出码 0 结束即测试通过。

## 第 5 步：升级、坏发布与回滚 {#p3-rollback}

这一步模拟真实发布中最常见的三种情况：一次正常升级、一次“坏发布”、一次回滚。

**修订 2：正常升级到 0.1.1。** 构建新镜像，`helm upgrade --set image.tag=0.1.1`，探测 20 次全部返回 200，`/api/v1/info` 报告 `"version":"0.1.1"`。

**第一次尝试制造坏发布——被 schema 拦下了：**

```console
$ helm upgrade demo-api-prod delivery/helm/demo-api -n prod -f delivery/helm/demo-api/values-prod.yaml --set image.tag=0.1.1 --set faults.errorRate=0.5 --wait --timeout 3m
Error: UPGRADE FAILED: values don't meet the specifications of the schema(s) in the following chart(s):
demo-api:
- at '/faults/errorRate': got string, want number
[exit 1]
```

这是一个真实踩到的坑：**`--set` 只会把整数和布尔值转换成对应类型，`0.5` 这样的小数会被当作字符串。**没有 schema 的话，这个字符串会被原样写进 ConfigMap，问题被推迟到运行时才暴露；有了 schema，它在提交前就被拒绝，而且 `helm history` 中没有留下任何失败的修订。需要传入数字时，应使用 `--set-json 'faults.errorRate=0.5'`，或者把值写进 values 文件。

**修订 4：用 `--set-json` 真正发布一个坏配置（50% 请求返回 500），然后回滚：**

![坏配置发布：40 次请求中 22 次返回 500；回滚到修订 2 后 40 次全部 200（终端记录渲染）](../../evidence/p3/helm-bad-release.png){height=140mm}

逐段解读：

1. 升级后立即查看 Pod，能看到 3 个新 Pod（新的 `checksum/config`）和 1 个尚未退出的旧 Pod——`--wait` 等待的是新版本就绪，并不等待旧 Pod 完全终止。
2. 探测 40 次：18 次 200、22 次 500，与 50% 的故障率吻合。
3. `helm get values --revision 4` 能精确查出“这次发布到底改了什么”，这在事故复盘中非常有用。
4. `helm rollback demo-api-prod 2` 并不是“删除修订 4”，而是**以修订 2 的内容生成一个新的修订 5**。历史是只追加的，审计信息不会丢失。
5. 回滚后 ConfigMap 恢复为 `FAULT_ERROR_RATE: "0"`，探测 40 次全部 200。

::: principle
**Helm 回滚与 GitOps 回滚的区别。** `helm rollback` 改变的是集群状态，但 Git 中的 values 文件并没有变。如果下一次有人从 Git 重新部署，坏配置会“复活”。第 6 章的 GitOps 会把这个问题彻底解决：回滚是对 Git 的一次提交（`git revert`），集群跟随 Git。
:::

## 第 6 步：打包并以 OCI 制品发布 Chart {#p3-oci}

```console
$ helm package delivery/helm/demo-api -d /tmp/charts
Successfully packaged chart and saved it to: /tmp/charts/demo-api-0.1.0.tgz
$ helm push /tmp/charts/demo-api-0.1.0.tgz oci://localhost:5001/charts --plain-http
Pushed: localhost:5001/charts/demo-api:0.1.0
$ helm template smoke oci://localhost:5001/charts/demo-api --version 0.1.0 --plain-http --show-only templates/service.yaml
Pulled: localhost:5001/charts/demo-api:0.1.0
Digest: sha256:9953e17510793f58f6a6fa7662aba985b5f7645b9bd971cdc7b651b94c759493
```

Chart 被打包成 `.tgz`，以 OCI 制品推送到与镜像相同的仓库，之后可以像引用镜像一样按版本甚至 digest 引用它。`--plain-http` 只因为本地实验仓库没有 TLS；真实环境中的仓库都应启用 HTTPS 和认证。（完整输出：`evidence/p3/helm-package-oci.log`）

## 深入：从一行 YAML 到内核 {#p3-deep}

前面把 Kubernetes 当作“提交期望状态、控制器负责收敛”的黑盒来用。本节把它打开，回答三个问题：一次写请求在 API Server 里经过了什么；控制器、调度器和 kubelet 怎样接力把它变成一个运行中的进程；Service 怎样把流量分给 Pod；Pod 规格里的 `securityContext` 和 `resources` 在内核里又变成了什么。后面几章遇到的很多现象，例如准入控制把镜像标签改写成 digest（第 7 章）、金丝雀收不到流量（第 8 章）、只读根文件系统暴露出隐藏的写入路径（第 12 章），都能在这里找到底层原因。

下面的实验是在全书实验完成之后的集群上做的：这时 prod 已经由第 8 章的 Rollout 管理，集群里也装好了第 7 章的 Kyverno。机制与本章的 Deployment 完全相同（证据：`evidence/p12/kubernetes-request-path.log`、`container-internals.log`）。

### 一次写请求的旅程

```{.mermaid caption="kubectl apply 之后：API Server 处理请求，其余组件各自监视对象、接力完成工作"}
sequenceDiagram
  autonumber
  participant U as kubectl
  participant A as API Server
  participant W as 准入 Webhook（Kyverno 等）
  participant E as etcd
  participant C as 控制器（Deployment、ReplicaSet）
  participant S as 调度器
  participant K as kubelet + containerd
  U->>A: 写请求（创建或修改对象）
  A->>A: 认证（是谁）→ 鉴权（RBAC：能不能）
  A->>W: 变更型准入：可以修改对象
  A->>A: 按 schema 校验
  A->>W: 校验型准入：只能放行或拒绝
  A->>E: 持久化
  A-->>U: 返回结果
  C->>A: 监视到新的期望状态，创建下一级对象
  S->>A: 监视到未调度的 Pod，写入 nodeName
  K->>A: 监视到分配给本节点的 Pod
  K->>K: 拉取镜像、创建沙箱与容器、配置网络（CNI）
  K->>A: 上报 Pod 状态（Running、Ready）
```

**准入发生在持久化之前。** 集群中注册了 4 个变更型和 8 个校验型 Webhook 配置，来自 Kyverno 和 kube-prometheus-stack。用 `--dry-run=server` 发送请求，API Server 会完整地执行认证、鉴权和准入，只是不写入 etcd，于是可以直接看到准入的效果：

```console
$ yq '... .spec.containers[0].image' delivery/policies/tests/admission-test-pods.yaml
ghcr.io/miku-wwl/devops-delivery/demo-api:sha-04a724f
$ yq '...' delivery/policies/tests/admission-test-pods.yaml | kubectl apply --dry-run=server -o jsonpath='{.spec.containers[0].image}' -f -
ghcr.io/miku-wwl/devops-delivery/demo-api:sha-04a724f@sha256:a0a4f18b1749f946d63f8af795f1001e7d06a190f2e70f0adf3e54d7c5ac9c74
```

提交的是一个标签，返回的对象里已经被 Kyverno 的变更型 Webhook 固定成了验证过签名的 digest（第 7 章的 `mutateDigest`）。准入 Webhook 是 API Server 请求路径上的一环：它越慢，所有写请求就越慢；它不可用时，按 `failurePolicy` 的设置，要么拒绝所有相关请求，要么放行。这也是 Kyverno 策略里要设置 `webhookTimeoutSeconds` 的原因。

**控制器接力。** 在一个临时命名空间里创建一个 2 副本的 Deployment，再按时间查看事件（同一秒内的事件，输出顺序不一定是发生顺序，这里按逻辑顺序排列）：

```console
COMPONENT               OBJECT       REASON              MESSAGE
deployment-controller   Deployment   ScalingReplicaSet   Scaled up replica set chain-demo-85847b776c from 0 to 2
replicaset-controller   ReplicaSet   SuccessfulCreate    Created pod: chain-demo-85847b776c-f8q9q
default-scheduler       Pod          Scheduled           Successfully assigned p12-chain/chain-demo-85847b776c-f8q9q to lab-worker
kubelet                 Pod          Pulled              Container image "registry.k8s.io/pause:3.10" already present on machine ...
kubelet                 Pod          Created             Container created
kubelet                 Pod          Started             Container started
```

Deployment 控制器只负责创建或调整 ReplicaSet，ReplicaSet 控制器只负责让 Pod 的数量对上，调度器只负责给 Pod 选节点，kubelet 只负责把分配给自己的 Pod 跑起来。它们之间不直接通信，而是都通过 API Server 读写对象来协作。对象之间的从属关系记在 `ownerReferences` 里：

```console
Pod chain-demo-85847b776c-f8q9q <- ReplicaSet chain-demo-85847b776c <- Deployment/chain-demo
Pod demo-api-prod-56ffb56667-gr7cz <- ReplicaSet demo-api-prod-56ffb56667 <- Rollout/demo-api-prod
argocd tracking id: demo-api-prod:argoproj.io/Rollout:prod/demo-api-prod
```

prod 中把 ReplicaSet 创建出来的是 Argo Rollouts 的控制器，而不是 Deployment 控制器。这正是第 8 章能“替换”发布策略的原因：Rollout 只是另一个管理 ReplicaSet 的控制器。Argo CD 则不是任何对象的 owner，它用注解“认领”自己管理的资源，所以删除 Application 时，要靠第 6 章提到的 finalizer 来级联删除资源。

::: principle
**基于状态而不是基于事件。** 控制器每次调和比较的是“期望状态”和“当前状态”，而不是“刚刚发生了什么事件”（这种做法称为 level-triggered）。即使控制器重启、漏掉了几个事件，下一次调和仍会得出正确的动作。这也是 Kubernetes 可以被不断扩展的原因：Argo CD、Argo Rollouts、Kyverno、Prometheus Operator 都是按同样的模式写成的控制器。
:::

### Service 是怎样分流的

ClusterIP 并不是某个进程在监听的地址。EndpointSlice 控制器维护每个 Service 对应的就绪 Pod 列表；每个节点上的 kube-proxy 再把这个列表翻译成内核的 NAT 规则。Kind 中的 kube-proxy 使用 iptables 模式（`mode: iptables`）。prod 的 5 个就绪 Pod 在 lab-worker 节点上对应的规则如下（为便于阅读，注释被简写为括号中的后端地址）：

```console
-A KUBE-SERVICES -d 10.96.78.13/32 -p tcp ... --dport 80 -j KUBE-SVC-4MKJFZO4EMFIXLDZ
-A KUBE-SVC-4MKJFZO4EMFIXLDZ (-> 10.244.1.43:8080) -m statistic --mode random --probability 0.20000000019 -j KUBE-SEP-2HEUMPRBKZSWPLCL
-A KUBE-SVC-4MKJFZO4EMFIXLDZ (-> 10.244.1.44:8080) -m statistic --mode random --probability 0.25000000000 -j KUBE-SEP-U6HFCHFDZRI2ZMIR
-A KUBE-SVC-4MKJFZO4EMFIXLDZ (-> 10.244.1.46:8080) -m statistic --mode random --probability 0.33333333349 -j KUBE-SEP-6Z757G2UCX2ORLHG
-A KUBE-SVC-4MKJFZO4EMFIXLDZ (-> 10.244.2.58:8080) -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-3FSLLPAN64XLXBBU
-A KUBE-SVC-4MKJFZO4EMFIXLDZ (-> 10.244.2.59:8080) -j KUBE-SEP-GDUDNWIQLOCHUIX7
-A KUBE-SEP-2HEUMPRBKZSWPLCL -p tcp ... -j DNAT --to-destination 10.244.1.43:8080
```

规则按顺序匹配：第一条以 1/5 的概率命中；没命中时（概率 4/5），第二条以 1/4 命中，总概率同样是 4/5 × 1/4 = 1/5；依此类推，最后一条无条件命中剩下的 1/5。结果是 5 个后端被均匀地随机选中，命中后由 DNAT 把目的地址改写为 Pod 的地址。

**关键在于：这个选择只对连接的第一个包做一次。** 内核的连接跟踪（conntrack）会记住这次地址转换，同一个连接后续所有的包都走同一个后端。在负载生成器 k6 所在的节点上，可以直接看到这些记录：每一行先是发往 ClusterIP 的原始方向，再是从某个 Pod 返回的方向。

```console
$ docker exec $K conntrack -L -p tcp --orig-dst 10.96.78.13 | head -2
tcp 6 20 TIME_WAIT src=10.244.1.41 dst=10.96.78.13 sport=42110 dport=80 src=10.244.1.46 dst=10.244.1.41 sport=8080 dport=42110 [ASSURED] ...
tcp 6 77 TIME_WAIT src=10.244.1.41 dst=10.96.78.13 sport=60964 dport=80 src=10.244.1.44 dst=10.244.1.41 sport=8080 dport=60964 [ASSURED] ...
[exit 141]
$ docker exec $K conntrack -L -p tcp --orig-dst 10.96.78.13 | ... | sort | uniq -c
    243 src=10.244.1.43
    236 src=10.244.1.44
    241 src=10.244.1.46
    247 src=10.244.2.58
    242 src=10.244.2.59
```

（`[exit 141]` 是 128 + 13：`head` 读完两行就关闭了管道，`conntrack` 随即收到 SIGPIPE，与第 4 章脚本静默退出是同一个信号，这里无害。）k6 每个请求新建一个连接，1209 个连接几乎均匀地分到了 5 个后端。

如果连接被复用呢？从 dev 的一个 Pod 里向 prod 发送 40 个请求：前 20 个复用同一个 HTTP/1.1 keep-alive 连接，后 20 个每次新建连接。每个请求带一个不同的 `X-Request-ID`（第 12 章加入的功能），再统计每个 prod Pod 的访问日志：

```console
demo-api-prod-56ffb56667-gr7cz: keep-alive=20 new-connections=2
demo-api-prod-56ffb56667-kdrzz: keep-alive=0 new-connections=4
demo-api-prod-56ffb56667-klpxl: keep-alive=0 new-connections=2
demo-api-prod-56ffb56667-nl8wl: keep-alive=0 new-connections=7
demo-api-prod-56ffb56667-nqlv6: keep-alive=0 new-connections=5
```

复用连接的 20 个请求全部落在同一个 Pod 上。这就是第 8 章第一次金丝雀“收不到流量”的完整机制：k6 在金丝雀出现之前就建好了长连接，这些连接的后端早已固定，新 Pod 只能分到新建的连接。按请求分配权重，需要能理解 HTTP 的 L7 代理（服务网格、Gateway API 实现等），而不是 L4 的 NAT 规则。

### securityContext 与 resources 在内核里是什么

容器不是虚拟机，它是宿主机上一个被内核限制住的普通进程。在 prod 一个 Pod 所在的节点上，通过 `crictl inspect` 找到容器主进程在节点上的 PID，就可以直接查看内核为它设置的一切：

| Pod 规格中的字段 | 对应的内核机制 | 实测结果 |
|---|---|---|
| （隐含）每个 Pod 有自己的网络、进程编号等 | namespace | cgroup、ipc、mnt、net、pid、uts 六个 namespace 都与节点不同；**user namespace 与节点相同** |
| `runAsUser: 10001`、`runAsNonRoot` | 进程的 UID | `Uid: 10001`；在容器内看，1 号进程就是 uvicorn |
| `capabilities.drop: ["ALL"]` | capability 集合 | `CapEff`、`CapBnd` 均为 0（节点上的 1 号进程是 `000001ffffffffff`，即全部） |
| `allowPrivilegeEscalation: false` | no_new_privs 标志 | `NoNewPrivs: 1` |
| `seccompProfile: RuntimeDefault` | seccomp-bpf 系统调用过滤 | `Seccomp: 2`（过滤模式） |
| `limits.memory: 256Mi` | cgroup `memory.max` | 268435456（超出即被 OOM 终止，退出码 137） |
| `limits.cpu: 1` | cgroup `cpu.max` | `100000 100000`：每 100 ms 的周期内最多运行 100 ms，超出就被限流，而不是被终止 |
| `requests.cpu: 100m` | cgroup `cpu.weight` | 17：只在 CPU 争用时起作用的相对权重（换算公式随 runc 版本而不同） |
| `readOnlyRootFilesystem: true` | 只读挂载的 overlayfs 根文件系统 | `/` 以 `ro` 挂载，由 8 个镜像层叠加而成；写 `/app` 报 “Read-only file system”，`/tmp`（emptyDir）可写 |

几点值得展开：

- **user namespace 是共享的。** Kubernetes 默认不为 Pod 创建独立的 user namespace，容器里的 UID 10001 在节点上也是 10001；如果容器以 root 运行，它在节点上就是 root，只是被 capability 和 seccomp 收紧了。这正是 `runAsNonRoot` 重要的原因。Kubernetes 支持用 `hostUsers: false` 为 Pod 启用独立的 user namespace（需要节点内核与容器运行时的支持），本项目没有启用。
- **requests 与 limits 决定了 QoS 等级。** demo-api 的 requests（100m、128Mi）小于 limits（1 CPU、256Mi），所以是 **Burstable**；两者完全相等是 **Guaranteed**，都不设置是 **BestEffort**。节点内存紧张时，kubelet 按 BestEffort、超出 requests 较多的 Burstable、Guaranteed 的顺序驱逐 Pod。内存超过 limits 会被立即终止，CPU 超过 limits 只会被限流，这两者的差别经常是“服务突然变慢”和“服务反复重启”两类问题的根源。
- **seccomp 拦的是系统调用。** `add_key` 不需要任何 capability，普通用户就可以调用。用同一个 Python 脚本调用它：

```console
$ kubectl -n prod exec -i $P -- python - < /tmp/addkey.py                     # demo-api，RuntimeDefault
add_key -> error: Operation not permitted
$ docker run --rm -i --user 10001 --security-opt seccomp=unconfined python@sha256:09a17cad... python - < /tmp/addkey.py
add_key -> key serial 536790600 (allowed)
$ docker run --rm -i --user 10001 python@sha256:09a17cad... python - < /tmp/addkey.py   # Docker 默认的 seccomp 配置
add_key -> error: Operation not permitted
```

对照实验使用同一个基础镜像、同一个用户，只改变 seccomp 设置，因此可以确定拦截来自 seccomp 配置，而不是来自权限。内核密钥环没有按容器隔离，默认配置因此禁止了这组调用。

- **只读根文件系统让写入路径变得可见。** 根文件系统是镜像各层通过 overlayfs 叠加出来的，挂载为只读后，任何未声明的写入都会立刻失败，而不是悄悄写进容器的可写层。第 12 章加固 LGTM 时，Tempo 写 `/var/tempo` 失败，正是这样暴露出来的。这里看到的 8 层，与第 7 章“深入”一节从镜像仓库读到的 8 个层是同一回事，只是一个在节点的挂载表里，一个在镜像清单里。

## 常见问题

**Q1：`helm upgrade` 报 “got string, want number”。**
`--set` 不转换小数。改用 `--set-json`，或把值放进 values 文件。

**Q2：改了 ConfigMap，Pod 里的环境变量没变。**
环境变量只在容器启动时注入。使用本章的 `checksum/config` 注解，或手动 `kubectl rollout restart`。

**Q3：Pod 创建被拒绝，提示 “violates PodSecurity "restricted"”。**
逐项补齐：`runAsNonRoot: true` 且镜像使用数字 UID、`allowPrivilegeEscalation: false`、`capabilities.drop: ["ALL"]`、`seccompProfile.type: RuntimeDefault`。

**Q4：镜像拉取失败 `ErrImagePull`，地址是 `localhost:5001/...`。**
检查节点内 `/etc/containerd/certs.d/localhost:5001/hosts.toml` 是否存在，以及仓库容器是否已连入 `kind` 网络（`docker network inspect kind`）。

**Q5：Deployment 报 “field is immutable”。**
修改了 `spec.selector`（例如把会变的版本号放进了选择器标签）。选择器只用稳定标签；已经出错的 Release 需要删除重建。

**Q6：实验过程中 Kind 集群和 GitLab 容器“莫名其妙”全部重启，控制面节点停在 `Exited (128)`。**
这是本次实验中真实发生的问题。WSL 在没有任何 `wsl.exe` 会话连接时，会在短暂空闲后**关闭整个发行版**，即使 systemd 中的 Docker 仍在运行；systemd 日志中可以看到每次空闲后都出现 `Reached target shutdown.target`。下次进入时 Docker 重启，Kind 节点容器在开机过程中与 systemd 的 cgroup 创建发生竞争，报 `unable to start unit docker-....scope`。处理方法：保持一个 WSL 终端（或后台的 `wsl.exe -d devops-lab -- sleep infinity`）一直打开；已经停止的节点用 `docker start lab-control-plane lab-worker lab-worker2` 恢复，集群中的工作负载会随之恢复。

## 练习 {#p3-exercises}

::: exercise
1. **（理解）** 一个服务依赖数据库。把“数据库是否可用”的检查分别放进 livenessProbe 和 readinessProbe，数据库短暂故障时会分别发生什么？你会怎么设计这两个探针？
2. **（动手）** 用 `helm template` 渲染 prod，分别在 `--set-json faults.latencyMs=800` 前后各渲染一次，用 diff 找出 Pod 模板中变化的字段。按本章的原理，这次变更会创建新的 ReplicaSet 吗？
3. **（排障）** `helm upgrade --set faults.errorRate=0.5` 报 `got string, want number`。解释原因，并给出两种正确的写法。
4. **（设计）** prod 的反亲和为什么用“软”规则（preferred）？3 个副本、2 个工作节点时改成“硬”规则（required）会怎样？什么场景下必须用硬规则？
5. **（原理）** `helm rollback demo-api-prod 2` 之后，`helm history` 里为什么出现的是修订 5，而不是回到修订 2？这种只追加的历史有什么好处？它与 GitOps 的回滚有什么根本区别？
6. **（思考）** 本章的 `checksum/config` 方案在第 8 章引发了真实故障。用 Pod 模板哈希的原理，解释 Chart 0.3.1（配置写进 Pod 模板）为什么能修复它；再与“名字带内容哈希的不可变 ConfigMap”方案比较异同。
7. **（计算）** prod 缩容到 4 个副本后，kube-proxy 为这个 Service 生成的各条规则的概率依次是多少？如果其中一个 Pod 的 readiness 探针失败了呢？已经建立在那个 Pod 上的连接会怎样？
8. **（分析）** 一个容器以 root 运行（没有设置 `runAsNonRoot`），但保留了 `drop: ["ALL"]` 和 RuntimeDefault。和本章的 demo-api 相比，它多了哪些风险？如果为它启用了独立的 user namespace（`hostUsers: false`），情况有什么不同？
:::

参考答案见附录 B。

## 本章小结

- Kubernetes 以声明式对象 + 控制器调和的方式工作；Deployment、Service、ConfigMap、PDB 等对象各司其职。
- Helm 把这些对象封装成参数化的 Chart：同一 Chart + 不同 values = 不同环境；每次变更都是一个可追溯、可回滚的修订。
- values schema 在本章拦下了两类真实错误（非法取值、`--set` 的类型陷阱）；diff 帮助发现了硬编码 Release 名的设计缺陷。
- 坏配置发布使错误率达到 55%，`helm rollback` 生成新修订并恢复服务——但集群与 Git 不再一致，这正是下一章 GitOps 要解决的问题。
