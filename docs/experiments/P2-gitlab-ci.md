# 实验记录：P2 / D2 GitLab CI/CD

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（证据时间戳为 UTC） |
| 路线图模块 | D2 GitLab CI/CD |
| 官方来源 | [GitLab CI/CD tutorial](https://docs.gitlab.com/ci/quick_start/tutorial/)、[`.gitlab-ci.yml` reference](https://docs.gitlab.com/ci/yaml/)、[Install GitLab in Docker](https://docs.gitlab.com/install/docker/)、[Runner registration (authentication tokens)](https://docs.gitlab.com/ci/runners/new_creation_workflow/) |
| 软件版本 | GitLab CE 19.5.3-ce.0；GitLab Runner alpine-v19.5.2（Docker executor）；作业镜像 python:3.13-slim、docker:29-cli |
| 环境 | devops-lab（WSL2）中的 Docker Compose 栈，仅监听 127.0.0.1:8929 |
| 状态 | **VALIDATED** |

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | `gitlab-up.sh`：启动、建令牌、建项目（Pipelines must succeed）、注册 Runner | 成功；过程中修复 4 个问题（见下） | [gitlab-up.log](../../evidence/p2/gitlab-up.log) |
| 2 | 推送 main，CI Lint | `valid: true`；推送使用 GIT_CONFIG_* 头部认证 | [push-main.log](../../evidence/p2/push-main.log)、[main-pipeline.log](../../evidence/p2/main-pipeline.log) |
| 3 | main 流水线 #1 | lint/test 并行 → build → deploy-dev 成功，deploy-prod 手动（status=manual，85 s） | [main-pipeline.log](../../evidence/p2/main-pipeline.log)、[main-pipeline.png](../../evidence/p2/main-pipeline.png) |
| 4 | 运行手动作业 deploy-prod | 成功；dev/prod 两条部署记录 | [manual-prod.log](../../evidence/p2/manual-prod.log) |
| 5 | MR !1（差一错误） | MR 流水线 #2：test failed、build skipped；`detailed_merge_status=ci_must_pass`；JUnit 报告 22 个测试 1 个失败 | [mr-blocked.log](../../evidence/p2/mr-blocked.log)、[mr-blocked.png](../../evidence/p2/mr-blocked.png) |
| 6 | 推送修复 | 流水线 #3 成功；`mergeable` | [mr-fixed.log](../../evidence/p2/mr-fixed.log)、[mr-mergeable.log](../../evidence/p2/mr-mergeable.log) |
| 7 | 在本地实验 GitLab 中合并 MR | 合并提交 dd38a063；main 流水线 #4 部署 dev（gl-4），prod 等待手动 | [mr-merged.log](../../evidence/p2/mr-merged.log)、[environments.png](../../evidence/p2/environments.png) |
| 8 | DAG 与缓存验证 | test 与 lint 同时开始；#4 中 “Successfully extracted cache”，lint 35 s → 22 s | [dag-timing.log](../../evidence/p2/dag-timing.log)、[cache.log](../../evidence/p2/cache.log)、[pipeline-dag.png](../../evidence/p2/pipeline-dag.png) |

## 失败与排查

1. 生成密码的 `tr </dev/urandom | head` 在 `pipefail` 下触发 SIGPIPE，`set -e` 让脚本静默退出；外层 `tee` 掩盖了退出码。→ 改用 Python `secrets`。
2. `/-/readiness` 经端口映射访问返回 404（监控白名单只含回环地址）。→ 改用容器健康状态 + 登录页。
3. **Runner 认证令牌泄露到日志与会话输出**：ANSI 颜色码使 `Token=` 正则失效。→ 日志打码；通过 API 删除该 Runner（令牌失效）；修复脚本（先去 ANSI 再打码，`glrt-` 兜底）；重新注册；验证新日志 0 次出现。端口绑定改为 127.0.0.1。
4. WSL 空闲关机导致 Docker、GitLab、Kind 周期性停止（systemd journal 中多次 `Reached target shutdown.target`）。→ 保持一个后台 `wsl.exe ... sleep infinity` 会话。
5. 通过 `wsl.exe -- bash -c '...'` 传入的脚本会被二次解析，`$?`、`$SECONDS` 被提前展开。→ 多行脚本一律通过 stdin（here-document）传入。

## 局限性

- 使用自建 GitLab CE，而非 GitLab.com；GitLab University 课程与官方实验环境（部分需付费邀请码）未使用。
- Runner 挂载 Docker socket，仅适用于单人本地实验。

## 清理

见第 4 章“清理”。实验结束前保留 GitLab 以便复查；P12 收尾时统一清理。
