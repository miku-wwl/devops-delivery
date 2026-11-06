# 实验记录：P5 / D5 DevSecOps 与软件供应链

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（证据时间戳为 UTC） |
| 路线图模块 | D5 DevSecOps / Supply Chain；Gate G3 |
| 官方来源 | [Trivy](https://trivy.dev/)、[GitHub Artifact Attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)、[Sigstore Cosign](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)、[Syft](https://github.com/anchore/syft)、[SLSA](https://slsa.dev/)、[Kyverno verifyImages](https://kyverno.io/docs/) |
| 软件版本 | Trivy 0.76.2；Cosign v3.1.4；actions/attest-build-provenance v4.2.2；actions/attest v4.2.2（替代已弃用的 attest-sbom v4.1.0）；anchore/sbom-action v0.24.3；Kyverno chart 3.9.2（v1.19.2） |
| 环境 | GitHub 托管 Runner（ubuntu-24.04）；GHCR；Kind 集群 `lab` |
| 状态 | **VALIDATED** |

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 本地 `trivy fs` / `trivy image` | 仓库 0 个 HIGH/CRITICAL；镜像 5 个可修复 HIGH（pip 自带的 msgpack、urllib3、setuptools）+ 46 个无修复的 OS 问题 | [trivy-local.log](../../evidence/p5/trivy-local.log) |
| 2 | 修复：运行时镜像删除 pip，重扫 | 门禁 exit 0；剩余 affected 45、fix_deferred 1；容器功能正常 | [trivy-remediation.log](../../evidence/p5/trivy-remediation.log) |
| 3 | CI：`security` 作业 + 镜像门禁；actionlint | PR #3 上 security、container image 通过；actionlint 0 错误 | [actionlint.log](../../evidence/p5/actionlint.log) |
| 4 | release 工作流（运行 42135396183） | 1m48s 成功：digest sha256:a0a4f18b…，SLSA 证明 #64287897、SBOM 证明 #64287939、Cosign 签名 | [release-run.log](../../evidence/p5/release-run.log)、[release-run.png](../../evidence/p5/release-run.png)、[attestation-page.png](../../evidence/p5/attestation-page.png) |
| 5 | 消费者验证（gh、cosign）与反例 | 来源证明 / SBOM（104 个包）验证通过；错误工作流、错误仓库、错误身份均失败 | [verify-gh-attestation.log](../../evidence/p5/verify-gh-attestation.log)、[verify-cosign.log](../../evidence/p5/verify-cosign.log) |
| 6 | 同一 digest 经 GitOps 晋级 dev → prod | !5、!6 合并；4 个 Pod 的 imageID 全部为 sha256:a0a4f18b… | [digest-promotion.log](../../evidence/p5/digest-promotion.log) |
| 7 | Kyverno 准入控制 | 第 4 次配置成功：已签名（digest/tag）允许且 tag 被固定为 digest；无来源证明镜像拒绝 | [kyverno-install.log](../../evidence/p5/kyverno-install.log)、[kyverno-admission.log](../../evidence/p5/kyverno-admission.log) |
| 8 | 演练：PR #4 引入 PyYAML 5.3.1 | security、container image、release 门禁失败；`BLOCKED`；推送/签名/证明被跳过；PR 关闭未合并 | [drill-vulnerable-dep.log](../../evidence/p5/drill-vulnerable-dep.log)、[drill-cve-detail.log](../../evidence/p5/drill-cve-detail.log)、[release-gate-blocked.png](../../evidence/p5/release-gate-blocked.png) |

## 失败与排查

- Kyverno 前三次配置都拒绝了已签名镜像：经典模式不认识 Sigstore 包；`subject: ...release.yml@*` 通配符匹配不到含 `/` 的分支名。→ `type: SigstoreBundle` + 验证 SLSA 证明 + `subjectRegExp`。
- CI 中 `gh attestation verify` 无输出：非交互模式下成功时静默。→ 本地验证时使用 `--format json`。
- `cosign verify` 输出的 JSON 中 `.optional.Issuer/Subject` 为空（v3 输出结构变化），CI 摘要中显示 null；验证本身成功。
- Dockerfile 的 `licenses` 标签写成 MIT，与仓库的 Apache-2.0 不符（由 metadata-action 生成的标签暴露）。→ 已修正。
- GitGuardian 在 PR #3 中报告 “Generic Password”（compose.yaml 中的变量引用），经核实为误报，历史中无真实令牌；配置已改写，需仓库所有者在 GitGuardian 中标记误报。

## 局限性

- 发布工作流在本实验中由 `p5/**` 分支触发（main 的合并需所有者审阅）；签名身份因此是 `refs/heads/p5/supply-chain`。
- `security` 作业尚未加入必需检查（避免阻塞尚未包含该作业的 #1）；合并后需更新规则集。
- Kyverno 使用已弃用的 `ClusterPolicy`；新项目应使用 `ImageValidatingPolicy`。
