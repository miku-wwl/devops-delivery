# v1.0 发布说明与集成方案

| 项 | 内容 |
|---|---|
| 基线 | 分支 `release/v1.0`，标签 `v1.0.0`（指向本分支经 CI 验证后的提交） |
| 内容 | P0–P12 全部阶段：代码、流水线、GitOps 种子、实验记录、事故复盘、证据链、241 页手册（`manual/dist/`） |
| 状态 | 阶段状态见 [STATUS](STATUS.md)；手册验收见 [ACCEPTANCE_REPORT](ACCEPTANCE_REPORT.md) |
| 合并到 main | **需要仓库所有者操作**（第 4 节）。自动化执行只准备集成 PR，不合并、不修改规则集 |

## 1. 分支与 PR 的关系（2026-11-07 核对）

```text
main (be0efaa) ─► p1/ci-pipeline ─► p2/gitlab-ci ─► p3/helm ─► p4/gitops ─► p5/supply-chain
   ─► p6/progressive-delivery ─► p7/observability ─► p8/datadog-learning ─► p9/synthetic-gate
   ─► p10/closed-loop ─► p11/ansible ─► p12/manual ─► release/v1.0
                                    （一条线性历史：每个分支都是下一个分支的祖先）

不在这条历史中的演练分支：
   p1/drill-bulk-discount    PR #2（开放）：第 3 章“测试失败阻断合并”的演练，含“满 10 件九折”功能
   p5/drill-vulnerable-dep   PR #4（已关闭）：第 7 章引入 PyYAML 5.3.1（CVE-2020-14343）的演练
```

核对命令与结果见 `evidence/release-v1.0/branch-audit.log`。

| PR | 分支 | 处理意见 | 理由 |
|---|---|---|---|
| #1 | `p1/ci-pipeline` → main | 不单独合并，由集成 PR 取代后关闭 | 其内容是 `release/v1.0` 的前缀 |
| #2 | `p1/drill-bulk-discount` → main | **不合并，关闭** | 故障演练分支。其“满 10 件九折”功能从未进入交付基线，也没有经过后续各阶段（门禁、扫描、签名、金丝雀）的验证；合并会把未经验证的行为带进 main |
| #3 | `p5/supply-chain` → main | 不单独合并，由集成 PR 取代后关闭 | 内容是 `release/v1.0` 的前缀；其 `security` 检查失败的问题已在 P10（`5b3e829`）修复 |
| #4 | `p5/drill-vulnerable-dep` | 已关闭，保持关闭 | 故意引入严重漏洞的演练，被三道防线拦下 |
| 新 | `release/v1.0` → main | **合并这一个** | 包含全部阶段与 v1.0 收尾修复 |

## 2. v1.0 收尾修复

1. **验收工具“发现问题却返回成功”的缺陷。** 对旧版本与修复版本用同一份故意改坏的输入做了对照（`evidence/release-v1.0/qa-tools-before-after.log`）：

   | 工具 | v1.0 的行为 | 修复后 |
   |---|---|---|
   | `manual/tools/verify_evidence.py` | 第 7 项（练习与答案）、第 8 项（31 个关键数字逐字比对）发现问题时仍返回 0 | 任何一项发现问题都返回 1；另外补上两个漏洞：整章练习被删除不再被忽略，空目录不再“通过” |
   | `manual/tools/layout_check.py` | 发现越界、空白页或留白也总是返回 0 | 越界或空白页返回 1；留白必须逐页列在 `manual/layout-accepted-gaps.txt` 中（经人工复核），否则返回 1 |
   | `manual/tools/build.py` | 目录页码可能错误（标题缺失、两遍打印页数不同）时只给警告 | 默认构建失败（退出码 3），可用 `--allow-warnings` 降级 |
   | `automation/evidence/transcript.sh` | 以失败命令数作为退出码，满 256 个时回绕成 0 | 退出码上限 125 |
   | `automation/lab/verify.sh` | systemd、Docker 服务的检查只打印不判断 | 显式断言；冒烟集群在失败时也会被删除 |

   这些行为由 `manual/tools/test_qa_tools.py` 的 11 个自测试固定下来：每个检查项都用一份故意改坏的副本验证它确实会失败。

2. **新的 CI 工作流 `manual-qa`**（`.github/workflows/manual-qa.yml`）：在每个指向 main 的 PR 和 `release/**` 的推送上运行上述自测试、证据核验和已提交 PDF 的版面检查。它没有路径过滤，因此可以设为必需检查。

教材正文、PDF、实验记录和证据均未改动；PDF 没有重新生成。

## 3. CI 与仓库安全现状

| 项 | 现状 | 建议（需所有者操作） |
|---|---|---|
| 规则集 `protect-main` | 生效；禁止删除和强推；只能经 PR、只允许 squash；必需检查：`python / lint`、`python / test`、`container image`；无人可绕过 | 加入 `security` 和 `manual QA` 两个必需检查 |
| 合并方式 | 只允许 squash | 合并集成 PR 时临时允许 merge commit（见第 4 节） |
| 秘密扫描与推送保护 | 已启用 | 保持 |
| Dependabot 告警与安全更新 | 未启用 | 启用 |
| 代码扫描（CodeQL） | 未配置 | 可选：启用默认配置 |
| 标签保护 | 无 | 为 `v*` 标签加规则集，禁止删除和改写 |
| 生产环境 `production` | 需要审阅者批准，限定分支 | 处理等待中的运行 42142945642 |
| GitGuardian | P2 的一条误报未处理，会让包含该提交的 PR 显示失败 | 在 GitGuardian 中标记为误报 |

## 4. 所有者的合并步骤

1. 在规则集 `protect-main` 的允许合并方式中临时加入 **merge**（或在合并后接受 squash，见下）。
2. 确认集成 PR 的必需检查全部通过；GitGuardian 若因 P2 的误报失败，先在 GitGuardian 中标记误报。
3. 以 **merge commit** 合并集成 PR。原因：手册、事故复盘、SLSA 来源证明和 Kyverno 策略都引用了原始提交号（例如来源证明中的 `85b3a49`），merge commit 保留它们在 main 的历史中。若坚持 squash，main 上只有一个新提交，原始提交仍由标签 `v1.0.0` 保持可达，证据链不受影响。
4. 合并后核对：`git diff v1.0.0 origin/main --stat` 应当没有输出（squash 时同样适用，因为比较的是文件树）。
5. 关闭 PR #1、#3（已被取代）和 #2（演练，不合并）；恢复规则集只允许 squash；把 `security`、`manual QA` 加入必需检查。
6. 演练分支 `p1/drill-bulk-discount`、`p5/drill-vulnerable-dep` 是证据的一部分，建议保留但永不合并；若要清理，先确认标签已推送。

## 5. 复现与核验

```bash
git checkout v1.0.0
python manual/tools/test_qa_tools.py          # 11 个自测试
python manual/tools/verify_evidence.py        # 证据核验，任何问题都返回 1
python manual/tools/layout_check.py manual/dist/DevOps-Delivery-Observability-Handbook.pdf \
  --accept-gaps-file manual/layout-accepted-gaps.txt
```
