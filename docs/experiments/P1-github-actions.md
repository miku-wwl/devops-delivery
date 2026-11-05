# 实验记录：P1 / D1 GitHub Actions 质量门禁

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（证据时间戳为 UTC） |
| 路线图模块 | D1 GitHub Actions |
| 官方来源 | [GitHub Skills: Hello GitHub Actions](https://github.com/skills/hello-github-actions)、[Actions Quickstart](https://docs.github.com/en/actions/get-started/quickstart)、[Reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)、[Rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) |
| 软件版本 | actions/checkout v7.0.1、setup-python v7.1.0、upload-artifact v7.0.2、setup-buildx v4.4.1、build-push v7.4.0（均固定 SHA）；Python 3.13（CI）/ 3.12（本地）；ruff 0.17.4；pytest 9.2.0 |
| 环境 | GitHub 托管 Runner（ubuntu-latest = Ubuntu 24.04）；本地 devops-lab |
| 状态 | **VALIDATED**（工程验收）；官方 Skills 练习 **NOT_RUN**（见局限性） |

## 目标

为参考服务 demo-api 建立 PR 质量门禁（lint、测试与覆盖率、制品、缓存、可复用工作流、镜像构建与冒烟测试），并用规则集强制“检查失败不可合并”。

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 本地 ruff + pytest | 首次：format 检查 3 个文件不合规、httpx 弃用警告；修复后 19 passed、覆盖率 98.96% | [local-tests.log](../../evidence/p1/local-tests.log) |
| 2 | 本地构建镜像并冒烟测试 | 202 MB；uid 10001；接口、指标、JSON 日志正常 | [local-image.log](../../evidence/p1/local-image.log) |
| 3 | actionlint | 首次发现 SC2034（未使用变量 `i`），修复后 0 错误 | [actionlint.log](../../evidence/p1/actionlint.log) |
| 4 | PR #1 首次 CI | lint 17 s、test 16 s、image 42 s，全部通过；生成 `test-reports` 制品与 pip / buildkit 缓存 | [pr1-ci-run.log](../../evidence/p1/pr1-ci-run.log) |
| 5 | 创建规则集 `protect-main`（id 26657635） | 生效：PR 必需、squash、三项必需检查、禁止删除与强推 | [ruleset-protect-main.json](../../evidence/p1/ruleset-protect-main.json)、[drill-blocked.log](../../evidence/p1/drill-blocked.log) |
| 6 | 故障演练 PR #2（`>` 代替 `>=`） | `python / test` 失败（1 failed, 21 passed），`container image` skipped，`mergeStateStatus=BLOCKED` | [drill-blocked.log](../../evidence/p1/drill-blocked.log)、[drill-run-failed.png](../../evidence/p1/drill-run-failed.png) |
| 7 | 推送修复提交 | 三项检查通过，`mergeStateStatus=CLEAN` | [drill-fixed.log](../../evidence/p1/drill-fixed.log)、[drill-run-fixed.png](../../evidence/p1/drill-run-fixed.png) |
| 8 | 缓存作用域观察 | PR #2 读不到 PR #1 的缓存；PR #2 第二次运行命中自身缓存 | [cache-scope.log](../../evidence/p1/cache-scope.log)、[cache-hit.log](../../evidence/p1/cache-hit.log) |

## 局限性

- **官方练习未执行：** 开始 Hello GitHub Actions 需要在用户账号下创建公开仓库，该操作被本次执行环境的权限策略拒绝；需用户本人点击 “Copy Exercise” 后完成。
- **合并由仓库所有者完成：** 权限策略不允许 AI 助手在无人审阅时合并 PR；PR #1、#2 已处于 `CLEAN`，等待所有者审阅合并。
- 运行器使用 `ubuntu-latest`，GitHub 注解提示该标签将迁移到 Ubuntu 26；如需完全可重复，应改为固定的 `ubuntu-24.04`。

## 清理

无需清理：工作流运行、制品（7 天）与缓存（7 天未访问）由 GitHub 自动过期。规则集保留，作为后续所有 Phase 的保护。
