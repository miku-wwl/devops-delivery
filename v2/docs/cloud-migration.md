# 云迁移分析：AWS 与 Azure（E11）

> 只做分析：没有创建任何云资源，没有产生费用。关于云服务的每一条陈述都附官方来源，核实日期 2026-11-10；没有核实的写明“未核实”。价格不在本分析之内——价格随地区、时间和合同变化，应以官方计算器为准。最后一节是工程判断，单独列出，不当作事实陈述。

## 1. 迁移的对象

第二轮的平台（`v2/`）：一个 Kind 集群（1 个控制面、3 个工作节点，`[模拟]` 三个可用区），GitOps（Argo CD，E11 起管理自身），Istio ambient 与 Gateway API，CloudNativePG、Valkey、NATS JetStream，OpenBao 与 External Secrets Operator，集群外的 Garage（备份目标），Velero，Prometheus、Grafana、Loki、Tempo，GitLab（合并请求门禁），OpenTofu（GitLab 治理与状态）。

## 2. 组件对照

| 实验环境 | AWS | Azure | 迁移时要注意的事实 |
|---|---|---|---|
| Kind 集群 `ent` | Amazon EKS | AKS | 两者的控制面都由云厂商运行；本书第 11 章测到的 API server 内存与 APF 问题仍然存在，只是规格和参数不再由我们看到或调整（未核实各自的 APF 默认值） |
| Argo CD（自管理） | 继续自管理；或 EKS Capabilities 中的托管 Argo CD——2025-11-30 正式可用，Argo CD 的控制面运行在 AWS 一侧，不占用工作节点[^eks-cap] | 继续自管理（Azure 的托管选项未核实） | 托管 Argo CD 改变了第 12 章“Argo CD 管理自身”的问题：升级由云厂商负责，配置项受限（2026-08-21 才支持自定义配置[^eks-cap-cfg]） |
| Istio ambient + Gateway API | 自行安装开源 Istio；AWS App Mesh 已于 2026-09-30 停止支持[^appmesh] | AKS 的 Istio 插件“尚不支持无 sidecar 的 Ambient 模式”，也不支持用 Gateway API 管理网格流量（GAMMA）[^aks-istio] | 在 AKS 上保留 ambient 就要自行安装开源 Istio，放弃插件的托管升级；用插件则要改回 sidecar 模式，第 3 章的测量不再适用 |
| Garage（集群外备份） | S3，Object Lock 合规模式[^s3-lock] | Blob 不可变存储，锁定的基于时间的保留策略[^az-worm] | 见第 3 节 |
| Velero | AWS Backup 自 2025-11-10 起支持 EKS（集群状态与 EBS、EFS、S3 中的数据）；2026-03-12 起可放进逻辑隔离的保管库（默认锁定的不可变副本）[^aws-backup-eks] | Azure Backup for AKS 的保管库层，可用不可变保管库；只支持 Azure 磁盘 CSI 卷[^az-aks-backup] | 微软文档提示 AKS 备份扩展与 Velero 同时运行可能冲突[^az-aks-backup]：二选一 |
| OpenTofu 状态 | S3 后端 + `use_lockfile`：S3 自 2024-08-20 起支持 `If-None-Match` 条件写入，已存在的键返回 412[^s3-cond] | azurerm 后端（Blob 租约锁，未在本次核实） | 第 12 章在 Garage 上失败的锁，正是依赖 412——在 S3 上它成立；“兼容 S3”不等于实现了 S3 的每个语义 |
| OpenBao + ESO | AWS Secrets Manager 或 KMS 自动解封（未核实具体集成） | Azure Key Vault（未核实具体集成） | 事故 E11-1：唯一一份解封密钥丢失，数据与全部快照不可读。托管的密钥服务把“保管密钥”交给云厂商的硬件与流程，但仍要设计密钥的访问与恢复 |
| CloudNativePG、Valkey、NATS | 托管数据库与缓存（未核实）；NATS 没有两家云的同名托管服务（未核实替代） | 同左（未核实） | 迁移前逐项核实；本分析不作结论 |
| Prometheus、Grafana | 未核实 | Azure Monitor 托管 Prometheus 与 Azure Managed Grafana 被 AKS Istio 插件文档列为已验证的集成[^aks-istio] | |
| GitLab 门禁 | GitLab.com 或自管理，不变 | 同左 | 第 12 章的治理配置（OpenTofu）不受云的影响 |

## 3. 不可删除的异地备份

**第 8 章留下的缺口**：备份目标 Garage 与集群在同一台电脑上，而且没有对象锁——任何持有密钥的人（或一个出错的脚本）都能删除全部备份。事故 E11-1 又补上了另一半：备份能否恢复，还取决于打开它的密钥是否还在。

**S3 Object Lock**（官方文档原文要点[^s3-lock]）：

- 合规模式下，受保护的对象版本“不能被任何用户覆盖或删除，包括 AWS 账户的 root 用户”；保留模式不能更改，保留期不能缩短；保留期到期前删除它的唯一方法是删除整个 AWS 账户。
- 治理模式下，持有 `s3:BypassGovernanceRetention` 权限并显式带上 `x-amz-bypass-governance-retention:true` 的请求可以绕过——适合测试，不适合防内部人员。
- 合法保留（legal hold）没有到期日，直到被显式移除。
- 只能用于开启了版本控制的桶；不带版本号的 DELETE 只会加一个删除标记，被锁定的版本仍在。
- Cohasset Associates 评估了它对 SEC 17a-4、CFTC、FINRA 的适用性。

**Azure Blob 不可变存储**（官方文档原文要点[^az-worm]）：

- 基于时间的保留策略期间，blob 可以创建和读取，不能修改或删除；数据“不能被任何用户修改或删除，即使是拥有账户管理权限的用户”。
- 策略先处于未锁定状态（可修改、可删除，仅用于测试）；锁定后不能删除，保留期只能延长不能缩短。
- 合法保留同样存在；有容器级与版本级两种 WORM。
- 与时间点还原（point-in-time restore）不兼容；Cohasset 评估了 SEC 17a-4(f)、CFTC 1.31(c)-(d)、FINRA 4511。

**由事实推出的设计约束**（属于第 5 节的工程判断）：备份放在另一个账户或订阅里；用合规模式或锁定策略，保留期按恢复目标设定；备份加密密钥的保管与备份本身分开设计并演练恢复——一个不可删除、却再也打不开的备份，和被删除的备份一样无用。

## 4. 本分析没有做的事

- 没有价格估算，没有性能比较，没有创建任何云资源。
- 没有核实的服务在表中写明“未核实”；云服务变化快，以上事实以核实日期为准，迁移前应重新核实。

## 5. 工程判断（不是事实陈述）

- 先迁移“不可删除的备份”和“密钥保管”，再迁移计算：这两项是本实验环境最薄弱、也最难靠自建补上的部分（第 8 章、事故 E11-1）。
- 服务网格的选择决定迁移工作量：在 AKS 上保留 ambient 意味着自行维护 Istio；在 EKS 上本来就要自行维护。
- 托管控制面并不消除第 11 章的教训：大 LIST、客户端退避和 APF 配置仍然由我们负责。

[^eks-cap]: AWS, Announcing Amazon EKS Capabilities, https://aws.amazon.com/about-aws/whats-new/2025/11/amazon-eks-capabilities ; AWS News Blog, https://aws.amazon.com/blogs/aws/announcing-amazon-eks-capabilities-for-workload-orchestration-and-cloud-resource-management
[^eks-cap-cfg]: AWS, Amazon EKS Capability for Argo CD now supports custom configuration, https://aws.amazon.com/about-aws/whats-new/2026/08/amazon-eks-argo-cd-configuration
[^appmesh]: AWS, What Is AWS App Mesh (end of support notice), https://docs.aws.amazon.com/app-mesh/latest/userguide/what-is-app-mesh.html
[^aks-istio]: Microsoft Learn, Istio-based service mesh add-on for AKS (Limitations; updated 2026-09-17), https://learn.microsoft.com/en-us/azure/aks/istio-about
[^s3-lock]: AWS, Locking objects with Object Lock, https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html
[^az-worm]: Microsoft Learn, Immutable storage for blob data overview (updated 2026-08-25), https://learn.microsoft.com/en-us/azure/storage/blobs/immutable-storage-overview
[^aws-backup-eks]: AWS, AWS Backup now supports Amazon EKS, https://aws.amazon.com/about-aws/whats-new/2025/11/aws-backup-supports-amazon-eks ; logically air-gapped vaults for EKS, https://aws.amazon.com/about-aws/whats-new/2026/03/aws-backup-logically-air-gapped-vault-amazon-eks
[^az-aks-backup]: Microsoft Learn, AKS backup support matrix, https://learn.microsoft.com/en-us/azure/backup/azure-kubernetes-service-cluster-backup-support-matrix ; Immutable vault concept, https://learn.microsoft.com/en-us/azure/backup/backup-azure-immutable-vault-concept
[^s3-cond]: AWS, Amazon S3 now supports conditional writes (2024-08-20), https://aws.amazon.com/about-aws/whats-new/2024/08/amazon-s3-conditional-writes
