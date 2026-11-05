# 持续集成（二）：GitLab CI/CD（P2 / D2） {#ch-p2}

<div class="lead">GitLab 是另一套被大量企业使用的一体化 DevOps 平台。本章在本机自建一套 GitLab CE 与 GitLab Runner（无需注册账号、可完全复现），把第 3 章的质量门禁用 GitLab 的方式重写一遍，并加入 GitLab 特有的能力：合并请求（MR）流水线、有向无环图（DAG）调度、测试报告解析、环境与部署记录、手动发布闸门。最后用同一个“差一错误”的演练，验证“流水线不通过就不能合并”。</div>

## 本章目标与产出

| 产出 | 位置 |
|---|---|
| 本地 GitLab CE 19.5.3 + Runner 19.5.2（Docker Compose） | `automation/gitlab/compose.yaml` |
| 一键初始化脚本（密码、令牌、项目、Runner） | `automation/gitlab/gitlab-up.sh` |
| 流水线等待与汇总脚本 | `automation/gitlab/wait-pipeline.sh` |
| GitLab 流水线定义 | `.gitlab-ci.yml` |

**验收标准（路线图 D2）：** 独立运行 GitLab 构建/测试/部署流水线。已通过：main 流水线完成 lint → test → 构建镜像 → 部署 dev → 手动部署 prod；MR 流水线在测试失败时被“流水线必须成功”规则阻断，修复后可合并并已合并（`evidence/p2/`）。

## 原理：GitLab CI/CD 的执行模型 {#p2-model}

```{.mermaid caption="GitLab 与 Runner：Runner 主动轮询领取作业"}
sequenceDiagram
  autonumber
  participant Dev as 开发者
  participant GL as GitLab（Rails + Sidekiq）
  participant R as GitLab Runner（Docker executor）
  participant D as Docker Engine
  Dev->>GL: git push / 创建 MR
  GL->>GL: 解析 .gitlab-ci.yml，按 workflow:rules 决定是否建流水线<br/>按 rules 决定包含哪些作业
  loop 每隔几秒
    R->>GL: 有我的作业吗？（出站 HTTPS 长轮询）
  end
  GL-->>R: 作业定义 + 一次性 CI_JOB_TOKEN
  R->>D: 启动作业容器（image: python:3.13-slim）
  D->>GL: 用 CI_JOB_TOKEN 克隆代码（clone_url）
  D->>D: 执行 before_script + script
  R->>GL: 上传日志、制品（artifacts）、报告（JUnit / Cobertura）
  GL-->>Dev: MR 页面显示流水线、测试摘要、覆盖率，并判定能否合并
```

与 GitHub Actions 最大的不同在于 **Runner 是主动“拉”作业的**：它只需要能访问 GitLab（出站连接），GitLab 不需要能访问 Runner。这使得把 Runner 放在内网、防火墙之后变得很容易——很多企业正是因此选择自托管 Runner。

| 概念 | GitLab CI/CD | 对应的 GitHub Actions 概念 |
|---|---|---|
| 流水线定义 | 仓库根目录的单个 `.gitlab-ci.yml`（可 `include` 其他文件） | `.github/workflows/` 下的多个文件 |
| 执行单元 | Job（作业），属于某个 Stage（阶段） | Job |
| 执行顺序 | 默认按 `stages` 顺序逐段执行；`needs` 改为 DAG | 默认并行；`needs` 声明依赖 |
| 执行器 | Runner（shell / Docker / Kubernetes 等 executor） | Runner |
| 复用 | `extends`、隐藏作业（`.name`）、`include`、CI/CD 组件 | 可复用工作流、Action |
| 文件传递 | `artifacts`（作业间、可下载）与 `cache`（加速，不保证存在） | Artifact 与 Cache |
| 测试报告 | `artifacts:reports:junit` 直接在 MR 中展示 | 需借助第三方 Action |
| 环境 | `environment:` 关键字自动生成部署记录 | `environment:` + Deployment Environments |
| 合并门禁 | 项目设置 “Pipelines must succeed” | 规则集的必需检查 |

## 第 1 步：在本地启动 GitLab CE 与 Runner {#p2-setup}

### Compose 定义

```yaml
name: gitlab-lab

services:
  gitlab:
    image: gitlab/gitlab-ce:19.5.3-ce.0
    container_name: gitlab
    hostname: gitlab
    restart: unless-stopped
    shm_size: 256m
    ports:
      # web UI + API + Git over HTTP. Loopback only: with WSL mirrored networking a
      # 0.0.0.0 binding would also listen on the Windows host's LAN interfaces.
      - "127.0.0.1:8929:8929"
    environment:
      GITLAB_ROOT_PASSWORD: ${GITLAB_ROOT_PASSWORD:?run gitlab-up.sh or export GITLAB_ROOT_PASSWORD}
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://localhost:8929'
        # Lab sizing: single Puma process, smaller Sidekiq, no bundled monitoring stack.
        puma['worker_processes'] = 0
        sidekiq['concurrency'] = 10
        prometheus_monitoring['enable'] = false
        gitlab_rails['usage_ping_enabled'] = false
        gitlab_kas['enable'] = false
    volumes:
      - gitlab-config:/etc/gitlab
      - gitlab-logs:/var/log/gitlab
      - gitlab-data:/var/opt/gitlab

  runner:
    image: gitlab/gitlab-runner:alpine-v19.5.2
    container_name: gitlab-runner
    restart: unless-stopped
    volumes:
      - runner-config:/etc/gitlab-runner
      # Docker executor: the runner starts job containers on the lab's Docker Engine.
      - /var/run/docker.sock:/var/run/docker.sock
```

- **`external_url` 决定一切对外地址**：Web、API、Git 克隆地址都由它生成；端口写在 URL 里时，内置 Nginx 就监听这个端口，所以容器内外都是 8929。
- **`GITLAB_OMNIBUS_CONFIG`** 是官方镜像读取配置的方式，内容就是 `gitlab.rb` 的 Ruby 语句。实验环境关掉了内置 Prometheus 等组件以节省内存（GitLab 官方建议至少 4 GB 内存）。
- **`GITLAB_ROOT_PASSWORD`** 只在首次初始化数据库时生效，由脚本随机生成，保存在仓库之外。
- **三个命名卷**保存配置、日志和数据，删除容器后数据仍在。
- **Runner 挂载宿主机的 Docker socket**，它创建的作业容器都运行在实验环境的 Docker Engine 上。

### 初始化脚本做了什么

`gitlab-up.sh` 依次完成：生成 root 密码 → `docker compose up` → 等待 GitLab 就绪 → 用 `gitlab-rails runner` 为 root 创建个人访问令牌（PAT）→ 通过 API 创建项目（开启 “Pipelines must succeed”）→ 通过 API 创建 Runner 并注册。注册部分：

```bash
RUNNER_TOKEN=$(api -X POST "$GL_URL/api/v4/user/runners" \
  --data-urlencode "runner_type=instance_type" \
  --data-urlencode "description=lab-docker-runner" \
  --data-urlencode "run_untagged=true" | jq -r .token)
docker exec gitlab-runner gitlab-runner register --non-interactive \
  --url "http://gitlab:8929" --clone-url "http://gitlab:8929" \
  --token "$RUNNER_TOKEN" \
  --executor docker --docker-image "alpine:3.22" \
  --docker-network-mode "$NETWORK" \
  --docker-volumes /var/run/docker.sock:/var/run/docker.sock >/dev/null
```

- **新的 Runner 注册流程。** 旧版本用一个全局“注册令牌”注册 Runner，已被 GitLab 弃用。新流程先在 GitLab 中**创建** Runner（`POST /user/runners`），得到 `glrt-` 开头的**认证令牌**，再用它注册。Runner 的描述、标签等属性归 GitLab 端管理。
- **`--clone-url` 与 `--docker-network-mode`。** GitLab 生成的克隆地址是 `http://localhost:8929/...`，但在作业容器里 `localhost` 是作业容器自己。于是让作业容器加入 Compose 网络 `gitlab-lab_default`，并把克隆地址改写为 `http://gitlab:8929`。
- **`concurrent = 4`**：Runner 默认同时只跑 1 个作业，DAG 中可以并行的 lint 与 test 也会排队。

::: warning
**挂载 Docker socket 的代价。** 作业容器能通过 `/var/run/docker.sock` 控制宿主机的 Docker，相当于拿到了宿主机 root 权限。这在单人本地实验中可以接受（我们需要在作业里构建镜像、部署容器），在共享 Runner 上绝不应该这样做；替代方案是 Docker-in-Docker（需要特权模式）、Kaniko/BuildKit 无守护进程构建，或者 Kubernetes executor。
:::

### 本次搭建中遇到的四个真实问题

这一步并不顺利，下面四个问题都真实发生过，修复已写进脚本：

1. **脚本静默退出。** 生成密码的第一版写法是 `tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24`。`head` 读够 24 个字节就退出，`tr` 收到 SIGPIPE 信号失败；在 `set -euo pipefail` 下整个管道被判失败，`set -e` 让脚本**不打印任何信息**直接退出。外层又把输出管道给了 `tee`，退出码也被吞掉了。改用 Python 的 `secrets` 模块生成密码。
2. **一直等不到“就绪”。** 第一版用 `/-/readiness` 判断 GitLab 是否就绪，结果一直返回 404。原因：GitLab 的健康检查端点只对“监控白名单”中的 IP（默认只有本机回环地址）开放，经 Docker 端口映射进来的请求源地址是网桥网关，被当作未授权访问。改为使用容器自带的健康检查状态（`docker inspect .State.Health.Status`）加登录页返回 200。
3. **令牌泄露到日志。** 第一版用 `sed 's/Token=[^ ]+/Token=<redacted>/'` 打码 `gitlab-runner list` 的输出，但 Runner 的输出带有 ANSI 颜色码，实际文本是 `Token\e[0;m=glrt-...`，正则根本匹配不上，Runner 令牌被原样打印出来。处理过程：立即对日志文件打码 → 通过 API **删除该 Runner**（服务端删除后令牌立即失效）→ 修正脚本（先去掉 ANSI 码再打码，并额外按 `glrt-` 前缀兜底）→ 重新注册新 Runner → 校验新日志中 `glrt-` 出现次数为 0。同时把 GitLab 的端口绑定从 `0.0.0.0` 改为 `127.0.0.1`。**教训：日志脱敏要在“去格式化”之后做，并且要验证结果，而不是假设正则一定生效；凭据一旦暴露，正确的动作是吊销，而不只是删除日志。**
4. **整个实验环境周期性“重启”。** 详见第 5 章常见问题 Q6：WSL 在空闲时会关闭发行版。

修复后的执行记录（`evidence/p2/gitlab-up.log`）：

```console
==> waiting for GitLab (first boot takes several minutes)
ready (container healthy, sign-in page 200)
token check: user=root
==> project root/devops-delivery
==> runner
Verifying runner... is valid                        correlation_id=01M6Q0WF02GTN5GRGNGWWY2X3H runner=YbBiJLG4Z runner_name=9d58f01b84a5
Runner registered successfully. Feel free to start it, but if it's running already the config should be automatically reloaded!
9d58f01b84a5                                        Executor=docker Token=<redacted> URL=http://gitlab:8929
GitLab lab ready: http://localhost:8929  (user root, password in /home/devops/.lab-secrets/gitlab-root-password)
exit=0 elapsed=4s
```

### 把代码推送到本地 GitLab，而不把令牌写进任何地方

```bash
export GL_TOKEN="$(cat ~/.lab-secrets/gitlab-root-token)"
# the token travels in an HTTP header supplied through GIT_CONFIG_* variables - never in the URL or in .git/config
export GIT_CONFIG_COUNT=2 \
  GIT_CONFIG_KEY_0=http.extraHeader \
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$GL_TOKEN" | base64 -w0)" \
  GIT_CONFIG_KEY_1=safe.directory GIT_CONFIG_VALUE_1='*'
git push http://localhost:8929/root/devops-delivery.git p2/gitlab-ci:refs/heads/main
```

常见的写法 `git push https://user:token@host/...` 会把令牌留在 shell 历史、进程列表，甚至 `.git/config` 的远程地址里。`GIT_CONFIG_COUNT/KEY/VALUE` 环境变量是 Git 官方支持的“临时配置”方式，令牌只存在于当前进程环境中。

## 第 2 步：流水线定义解析 {#p2-pipeline}

```yaml
workflow:
  name: "$CI_PIPELINE_SOURCE · $CI_COMMIT_REF_NAME"
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"  # merge request pipelines
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS    # branch with an open MR:
      when: never                                         #   the MR pipeline covers it
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH         # main
    - if: $CI_PIPELINE_SOURCE == "web"                    # "Run pipeline" button
  auto_cancel:
    on_new_commit: interruptible

stages: [lint, test, build, deploy]

variables:
  PIP_CACHE_DIR: "$CI_PROJECT_DIR/.cache/pip"
  PIP_DISABLE_PIP_VERSION_CHECK: "1"
  IMAGE: "demo-api:gl-$CI_COMMIT_SHORT_SHA"
  LAB_NETWORK: gitlab-lab_default

default:
  image: python:3.13-slim
  interruptible: true

.python:
  before_script:
    - cd app
    - pip install -r requirements-dev.txt
  cache:
    key:
      files: [app/requirements-dev.txt]
      prefix: pip
    paths: [.cache/pip]

lint:
  stage: lint
  extends: .python
  script:
    - ruff check .
    - ruff format --check .

test:
  stage: test
  extends: .python
  needs: []  # DAG: no need to wait for the lint stage
  script:
    - mkdir -p reports
    - pytest --cov --cov-report=term --cov-report=xml:reports/coverage.xml --junitxml=reports/junit.xml
  coverage: '/^TOTAL.*\s(\d+(?:\.\d+)?)%$/'
  artifacts:
    when: always
    expire_in: 1 week
    paths: [app/reports/]
    reports:
      junit: app/reports/junit.xml
      coverage_report:
        coverage_format: cobertura
        path: app/reports/coverage.xml

build-image:
  stage: build
  image: docker:29-cli
  needs: [lint, test]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes: [app/**/*]
  script:
    - docker build --build-arg APP_VERSION="gl-$CI_PIPELINE_IID" --build-arg GIT_SHA="$CI_COMMIT_SHORT_SHA" -t "$IMAGE" app
    - docker image inspect "$IMAGE" --format 'built {{.RepoTags}} size={{.Size}} user={{.Config.User}}'

.deploy:
  stage: deploy
  image: docker:29-cli
  interruptible: false
  script:
    - docker rm -f "demo-api-$CI_ENVIRONMENT_NAME" >/dev/null 2>&1 || true
    - >-
      docker run -d --name "demo-api-$CI_ENVIRONMENT_NAME" --network "$LAB_NETWORK"
      -p "127.0.0.1:$HOST_PORT:8080" -e APP_VERSION="gl-$CI_PIPELINE_IID" -e GIT_SHA="$CI_COMMIT_SHORT_SHA" "$IMAGE"
    - for _ in $(seq 1 30); do wget -qO- "http://demo-api-$CI_ENVIRONMENT_NAME:8080/healthz" && break; sleep 1; done
    - wget -qO- "http://demo-api-$CI_ENVIRONMENT_NAME:8080/api/v1/info"

deploy-dev:
  extends: .deploy
  needs: [build-image]
  variables:
    HOST_PORT: "18081"
  environment:
    name: dev
    url: http://localhost:18081/api/v1/info
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy-prod:
  extends: .deploy
  needs: [deploy-dev]
  variables:
    HOST_PORT: "18082"
  environment:
    name: prod
    url: http://localhost:18082/api/v1/info
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual   # a person decides when dev is promoted to prod
  allow_failure: false  # the pipeline shows "blocked" until someone runs this job
```

### `workflow:rules`：避免“重复流水线”

一个分支既有推送、又有打开的 MR 时，如果不加控制，每次推送会同时触发“分支流水线”和“MR 流水线”，浪费一倍资源，MR 页面上还可能显示错误的那一条。`workflow:rules` 按顺序匹配，**第一条匹配的规则生效**，都不匹配则不创建流水线：

1. 来源是 MR 事件 → 创建（MR 流水线）。
2. 分支上有打开的 MR → `when: never`（交给第 1 条处理）。
3. 默认分支 → 创建。
4. 网页上手动点击 “Run pipeline” → 创建。

于是没有 MR 的功能分支推送时**不会**跑流水线——这是一个有意的取舍，后面的证据会验证它。

### `stages` 与 `needs`：从“阶段”到“有向无环图”

默认情况下，GitLab 按 `stages` 顺序执行，前一阶段**全部**完成才进入下一阶段。`test` 声明 `needs: []`，意思是“我不依赖任何作业”，因此它与 lint 同时开始；`build-image` 声明 `needs: [lint, test]`，两者都成功后立即开始，不必等到整个阶段结束。这就是 DAG（有向无环图）调度，大型流水线能因此显著缩短时长。

### `cache` 与 `artifacts`：容易混淆的两件事

| | cache | artifacts |
|---|---|---|
| 目的 | 加速（例如 pip 下载的包） | 传递结果（测试报告、构建产物） |
| 可靠性 | 尽力而为，可能不存在 | 保证可用（直到过期） |
| 范围 | 同一个缓存键的多次流水线之间共享 | 本流水线后续作业、页面下载、MR 报告 |
| 本项目 | `key.files: app/requirements-dev.txt`：依赖锁文件变了才换缓存 | `reports.junit` 与 `coverage_report` 在 MR 页面展示 |

`coverage: '/^TOTAL.*\s(\d+(?:\.\d+)?)%$/'` 是一个正则表达式，GitLab 用它从作业日志中抓取 pytest-cov 打印的 `TOTAL ... 99%` 行，作为该作业的覆盖率数值。

### `rules:changes`、`environment` 与手动闸门

- `build-image` 在 MR 中只有改动了 `app/` 才运行：只改文档的 MR 不需要重新构建镜像。
- `environment:` 让 GitLab 为每次部署生成一条部署记录，并在 “Operate → Environments” 页面汇总：每个环境当前运行的是哪个提交、谁部署的、何时部署。
- `deploy-prod` 是 `when: manual`，并显式设置 `allow_failure: false`：流水线会停在 “blocked” 状态，直到有人点击运行。这就是一个最简单的**人工发布闸门**。（`rules` 中的手动作业默认就是 `allow_failure: false`，显式写出是为了让读者一眼看懂意图。）
- `.python` 和 `.deploy` 以点开头，是“隐藏作业”，不会单独运行，只用来被 `extends` 继承。

推送后先用 GitLab 自带的 CI Lint API 校验配置：

```console
$ curl -s -H "PRIVATE-TOKEN: $GL_TOKEN" "http://localhost:8929/api/v4/projects/1/ci/lint?ref=main" | jq '{valid, errors, warnings}'
{
  "valid": true,
  "errors": [],
  "warnings": []
}
```

## 第 3 步：main 上的第一条流水线与手动发布 {#p2-main}

```console
$ bash automation/gitlab/wait-pipeline.sh main
pipeline #1 [push] ref=main sha=034fd907 status=manual duration=85s
  lint    lint         success  35s
  test    test         success  40s
  build   build-image  success  32s
  deploy  deploy-dev   success  11s
  deploy  deploy-prod  manual   0s
```

![main 上的第一条流水线（按阶段分组的视图）：5 个作业，deploy-prod 旁边是手动运行按钮（GitLab 页面截图）](../../evidence/p2/main-pipeline.png)

流水线状态 `manual` 表示它停在了手动闸门前。dev 环境已经可以访问：

```console
$ curl -s localhost:18081/api/v1/info
{"service":"demo-api","version":"gl-1","commit":"034fd907"}
```

接着用 API 运行手动作业，相当于在页面上点击 ▶（`POST /projects/:id/jobs/:job_id/play`）：

```console
$ curl -s -X POST -H "PRIVATE-TOKEN: $GL_TOKEN" "http://localhost:8929/api/v4/projects/1/jobs/$JOB/play" | jq '{name, status, user: .user.username}'
{
  "name": "deploy-prod",
  "status": "pending",
  "user": "root"
}
$ bash automation/gitlab/wait-pipeline.sh main
pipeline #1 [push] ref=main sha=034fd907 status=success duration=97s
  ...
  deploy  deploy-prod  success  11s
$ curl -s -H "PRIVATE-TOKEN: $GL_TOKEN" "http://localhost:8929/api/v4/projects/1/deployments?order_by=id" | jq -r '.[] | ...'
deployment #1 env=dev status=success sha=034fd907 by=root
deployment #2 env=prod status=success sha=034fd907 by=root
```

## 第 4 步：MR 流水线与“流水线必须成功” {#p2-mr}

与第 3 章相同的演练：从 main 拉出 `feature/bulk-discount` 分支，提交带差一错误的“满 10 件九折”功能，然后创建 MR。

```console
$ bash automation/gitlab/wait-pipeline.sh --mr 1
pipeline #2 [merge_request_event] ref=refs/merge-requests/1/head sha=c1a378ba status=failed duration=27s
  lint   lint         success  22s
  test   test         failed   26s
  build  build-image  skipped  0s
[exit 1]

$ curl -s -H "PRIVATE-TOKEN: $GL_TOKEN" "http://localhost:8929/api/v4/projects/1/merge_requests/1" | jq '{iid, detailed_merge_status, merge_status, ...}'
{
  "iid": 1,
  "detailed_merge_status": "ci_must_pass",
  "merge_status": "can_be_merged",
  "head_pipeline": { "id": 2, "source": "merge_request_event", "status": "failed" }
}

$ curl -s ... "/pipelines/2/test_report" | jq '{total_count, success_count, failed_count, failed: [...]}'
{
  "total_count": 22,
  "success_count": 21,
  "failed_count": 1,
  "failed": [ "test_bulk_discount_applies_from_ten_items[10-expected_total1]" ]
}
```

![MR 页面：流水线失败、测试摘要“1 failed, 22 total tests”、“Merge blocked: Pipeline must succeed”（GitLab 页面截图）](../../evidence/p2/mr-blocked.png)

与 GitHub 的对照非常整齐：`merge_status: can_be_merged` 只说明没有 Git 冲突；**`detailed_merge_status: ci_must_pass` 才是“被阻断”的原因**。测试报告来自 `artifacts:reports:junit`——GitLab 解析 JUnit XML 后，直接在 MR 页面告诉审阅者是哪一个测试失败了。

推送修复提交后：

```console
pipeline #3 [merge_request_event] ref=refs/merge-requests/1/head sha=7343db4d status=success duration=46s
  lint   lint         success  23s
  test   test         success  29s
  build  build-image  success  16s
detailed_merge_status=mergeable
```

（`detailed_merge_status` 在流水线刚结束时短暂显示为 `unchecked`，这是 GitLab 在后台重新计算可合并性；几秒后变为 `mergeable`。）

这一次的合并发生在**本地实验 GitLab** 中，通过 API 完成：

```console
$ curl -s -X PUT -H "PRIVATE-TOKEN: $GL_TOKEN" ".../merge_requests/1/merge" | jq '{state, merged_by: .merged_by.username, merge_commit_sha: .merge_commit_sha[0:8]}'
{ "state": "merged", "merged_by": "root", "merge_commit_sha": "dd38a063" }
$ bash automation/gitlab/wait-pipeline.sh main
pipeline #4 [push] ref=main sha=dd38a063 status=manual duration=56s
$ curl -s localhost:18081/api/v1/info
{"service":"demo-api","version":"gl-4","commit":"dd38a063"}
```

**`workflow:rules` 的验证：** 列出所有流水线，功能分支 `feature/bulk-discount` 从来没有过“分支流水线”，只有 MR 流水线：

```console
#3  merge_request_event  refs/merge-requests/1/head  success
#2  merge_request_event  refs/merge-requests/1/head  failed
#1  push                 main                        success
```

**DAG 的验证：** 流水线 #4 中各作业的真实开始/结束时间：

```console
lint         started=23:38:13  finished=23:38:36  status=success
test         started=23:38:12  finished=23:38:41  status=success
build-image  started=23:38:42  finished=23:38:57  status=success
deploy-dev   started=23:38:58  finished=23:39:12  status=success
deploy-prod  started=          finished=          status=manual
```

test 甚至比 lint 早一秒开始，两者并行；build-image 在**两者中较晚完成的那个**（test，23:38:41）之后一秒开始。

![流水线 #4 的“作业依赖”视图：deploy-prod 停在手动闸门（GitLab 页面截图）](../../evidence/p2/pipeline-dag.png)

![Environments 页面：dev 已是合并提交 dd38a063，prod 仍是 034fd907，新部署处于 Waiting（GitLab 页面截图）](../../evidence/p2/environments.png)

## 第 5 步：缓存是否生效 {#p2-cache}

比较流水线 #1 和 #4 中 lint 作业的日志：

```console
== pipeline #1, job lint (1)
Checking cache for pip-5cc53b81deb0c0fb477d0ec3a202d2d8d457eb5e-protected...
No URL provided, cache will not be downloaded from shared cache server. Instead a local version of cache will be extracted.
Saving cache for successful job
Creating cache pip-5cc53b81deb0c0fb477d0ec3a202d2d8d457eb5e-protected...
== pipeline #4, job lint (12)
Checking cache for pip-5cc53b81deb0c0fb477d0ec3a202d2d8d457eb5e-protected...
No URL provided, cache will not be downloaded from shared cache server. Instead a local version of cache will be extracted.
Successfully extracted cache
```

- 缓存键由前缀 `pip`、`requirements-dev.txt` 的哈希组成；结尾的 **`-protected`** 表示这是受保护分支（main）的缓存。GitLab 默认把受保护分支与非受保护分支（如 MR）的缓存分开，防止不受信任的分支污染发布分支使用的缓存——与 GitHub 的缓存作用域是同一种安全考虑。
- “No URL provided” 说明 Runner 没有配置 S3 等共享缓存，缓存保存在 Runner 本机。多台 Runner 时需要配置分布式缓存，否则缓存命中率很低。
- 效果：lint 从 35 秒降到 22 秒，test 从 40 秒降到 28 秒。

## GitHub Actions 与 GitLab CI 实现同一门禁的对照

| 关注点 | GitHub Actions（第 3 章） | GitLab CI（本章） |
|---|---|---|
| PR/MR 触发 | `on: pull_request` | `workflow:rules` 中 `merge_request_event` |
| 复用 | 可复用工作流 `workflow_call` | 隐藏作业 + `extends`（跨项目可用 `include`/组件） |
| 并行与依赖 | Job 默认并行，`needs` 串联 | 默认按阶段串行，`needs` 构成 DAG |
| 测试报告 | 上传为制品，需要自己看 | `reports:junit` 自动显示在 MR |
| 阻断合并 | 规则集必需检查 → `BLOCKED` | “Pipelines must succeed” → `ci_must_pass` |
| 人工闸门 | Deployment Environment 的必需审阅者（第 8 章） | `when: manual` 作业 |
| 部署记录 | Deployments / Environments | Environments 页面 |

## 常见问题

**Q1：作业日志显示克隆失败，地址是 `http://localhost:8929/...`。**
作业容器里的 `localhost` 不是 GitLab。为 Runner 配置 `clone_url`，并让作业容器加入能解析 GitLab 主机名的网络（`network_mode`）。

**Q2：同一次推送出现两条流水线。**
没有配置 `workflow:rules` 去重，参考本章的四条规则。

**Q3：`needs` 引用的作业被 `rules` 排除后，流水线创建失败。**
被依赖的作业如果可能不存在，使用 `needs: [{job: xxx, optional: true}]`，或保证两者的 `rules` 一致。

**Q4：MR 显示 “Pipeline must succeed” 但流水线明明成功了。**
检查是否成功的是一条旧流水线，或是分支流水线而不是 MR 流水线；以 MR 的 `head_pipeline` 为准。

**Q5：新建 Runner 时找不到 “registration token”。**
旧的注册令牌机制已弃用。在 “Admin → CI/CD → Runners” 页面或通过 API 创建 Runner，获得 `glrt-` 认证令牌后再注册。

**Q6：GitLab 容器启动后很久仍不可用 / 内存不足。**
首次启动需要初始化数据库，几分钟是正常的；内存低于 4 GB 时可能反复重启，参考本章的精简配置。

## 清理

```bash
docker compose -f automation/gitlab/compose.yaml down          # 停止，保留数据卷
docker compose -f automation/gitlab/compose.yaml down -v       # 连同数据卷一起删除
docker rm -f demo-api-dev demo-api-prod                        # 流水线部署的容器
rm -f ~/.lab-secrets/gitlab-root-password ~/.lab-secrets/gitlab-root-token
```

## 本章小结

- GitLab Runner 主动轮询领取作业；Docker executor 为每个作业启动一个干净的容器。
- `workflow:rules` 去重、`needs` 构成 DAG、`cache`/`artifacts` 各司其职、`reports:junit` 让测试结果直接出现在 MR 中、`environment` 与手动作业形成可审计的发布流程。
- 演练证明：MR 流水线失败时 `detailed_merge_status=ci_must_pass`，修复后 `mergeable`；作业时间戳证明了 DAG 并行，缓存日志证明了缓存命中。
- 本章还记录了一次真实的凭据泄露与吊销过程——比“完美运行”的截图更有价值的工程经验。
