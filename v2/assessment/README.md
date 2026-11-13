# 能力考核（E12，第 13 章）

三部分：架构设计题（`design.md`，人工评分，附评分要点）、故障排查题（脚本注入故障 + 自动判分）、独立实操考核（自动判分）。故障排查与实操都在第二轮的实验环境中进行，运行前环境应当是“39 个应用 Synced/Healthy”。

## 故障排查题

每道题一个脚本，三个动作：

```text
bash v2/assessment/<题目>.sh inject    # 注入故障，只告诉考生一句症状
bash v2/assessment/<题目>.sh grade     # 判分：每项 PASS/FAIL，全部通过退出码为 0
bash v2/assessment/<题目>.sh restore   # 无论结果如何，把环境恢复原状
```

| 题目 | 告诉考生的症状 | 考查 |
|---|---|---|
| `t1-argocd-repo.sh` | 十分钟前合并的改动没有到达集群 | GitOps 的数据通路：Argo CD 读不到仓库时，现象、证据与修复（凭据从 `~/.lab-secrets` 恢复，不经过命令行） |
| `t2-openbao-restart.sh` | 一次重启之后，平台的密钥不再刷新 | 事故 E11-1 的场景：解封 OpenBao，而且不能动解封密钥文件——判分会比较它们的哈希 |
| `t3-out-of-band.sh` | 下单失败，浏览正常，Git 和 Argo CD 都显示一切正常 | Git 之外的改动：Argo CD 不跟踪、也不删除的对象；在网格中定位一个拒绝策略 |

规则：不得修改判分脚本和 `~/.lab-secrets/v2/assessment/` 中的记录；修复应当留下证据（命令与输出），判分只看结果。

## 独立实操考核

`p1-inhibition.sh grade`。任务：关闭事故 E11-1 的行动项 5——OpenBao 密封时，Alertmanager 抑制它的症状：命名空间 `secrets` 中的 `KubeJobFailed` 与 `KubeContainerWaiting`，以及依赖它的应用（backup-jobs、insight、tenants、platform-root）的 `ArgoCDAppDegraded`；其他告警不受影响。改动必须经合并请求进入配置仓库（门禁流水线通过），由 Argo CD 部署。

判分：仓库 main 中有以 `OpenBaoSealed` 为源的抑制规则；main 受保护；运行中的 Alertmanager 已加载该规则；行为检验——在 Alertmanager 中先建一个静默，再发送合成告警（静默保证不会有通知离开 Alertmanager，GitLab 中不会出现事故），三个症状被抑制，两个对照告警（storefront 的任务失败、storefront-gateway 应用 Degraded）不被抑制；最后把合成告警标为已解决，并让静默过期。

## 安全

- 每个注入都有对应的 `restore`；注入只触及一个对象（一个 Secret 的密码字段、一个 Pod、一条手工创建的策略）。
- 凭据只经文件或标准输入传递，判分脚本只比较哈希，从不打印秘密。
- 实操的行为检验使用静默的合成告警，不会通知值班人员。
