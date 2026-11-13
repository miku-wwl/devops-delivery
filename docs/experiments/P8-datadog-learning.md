# 实验记录：P8 / D8 / O2 Datadog Learning Center

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（UTC） |
| 路线图模块 | D8 / O2；Gate G6 |
| 官方来源 | [Datadog Learning Center](https://learn.datadoghq.com/)：Core Skills、Configuration、Site Reliability Engineer 三条学习路径 |
| 环境 | 用户本人的 Microsoft Edge 156（Learning Center 已登录），经 Claude in Chrome 扩展操作；实验为 Instruqt 虚拟机加 Datadog 试用组织（由实验平台自动分配，14 天，各实验共用） |
| 软件版本 | Datadog Agent 7.85.1（主机实验，官方安装脚本）；Agent 容器镜像 7.77.2（Docker 实验，实验指定） |
| 状态 | **PARTIAL** |

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 验证浏览器连接与 Learning Center 访问 | UA 含 `Edg/156.0.0.0`；页头显示已登录 | `learning-paths.png`（用户名已遮盖） |
| 2 | 免费报名三条学习路径 | 17 条报名记录（3 条路径、14 门课） | `learning-center-progress.md` |
| 3 | 读完 14 门课的 56 篇讲义并逐篇标记完成 | 平台记录 50%–75%（实验课时和问卷未完成） | `learning-center-progress.md` |
| 4 | Agent on a Host 实验 | 挑战 1–5 通过平台检查（安装、status/config、实时进程、日志与 APM、Redis 与 PostgreSQL 集成）；挑战 6（网页）未做，用 API 验证了数据到达 | `agent-host-*.png` |
| 5 | Agent on Docker 实验 | 挑战 1–2 通过平台检查；挑战 3 只用 API 浏览了数据，未点击下一步；挑战 4 未开始 | `agent-docker-*.png` |
| 6 | 其余 12 个实验 | 未做（需要网页登录，或窗口不可见） | — |

## 失败与排查

1. **网页登录受阻。** 试用组织要求用密码登录 `app.datadoghq.com`。按规则不能代为输入密码，本会话也没有密码管理器工具。记为阻碍，没有绕过。
2. **窗口最小化导致截图超时。** CDP 的 `Page.captureScreenshot` 在窗口最小化或标签页处于后台时一直超时，`outerWidth` 为 107–159 像素。第一次用 `ShowWindow(SW_SHOWNOACTIVATE)` 恢复了窗口；第二次发现用户正在用这个窗口，就没有再恢复，暂停了实验，改为做读讲义、标记完成这类不需要截图的工作。
3. **扩展的标签页组丢失。** 关闭一个标签页后，标签页组不存在了。用不带 `tabId` 的 `navigate` 重新建立。
4. **实验会话过期。** 10 分钟无操作就会过期，“Restart track”后得到新虚拟机，从挑战 1 重做。
5. **讲义正文是延迟加载的。** 课程播放器的 HTML 只有占位符，正文来自 `learning-assets.datadoghq.com/<uri>`（公开地址）。下载到本地 scratchpad 阅读，仅供学习笔记，未写入仓库和手册。
6. **不经手密钥的做法。**
   - 安装 Agent 用环境变量 `DD_API_KEY`；
   - Redis 和 PostgreSQL 的密码由 shell 从实验主机自己的 `/etc/redis/redis.conf`、`/root/restore.sql` 读出后写入配置；
   - 所有截图中的 key 都已打码，凭据横幅都先 `clear` 再截图。

## 局限性

- 平台显示的“完成”只覆盖讲义；所有实验课时和问卷都未完成，也没有领取结课证书或 Credly 徽章。
- API 浏览不等于完成了网页实验，相关课时没有标记完成。
- 课程内容版权属于 Datadog。手册只写自己的理解和本次实验的真实输出，未复制讲义原文。

## 需要用户完成

1. 登录一次实验用的 Datadog 试用账号（凭据在实验终端里），之后可以继续各实验的网页部分。
2. 填写 14 门课的反馈问卷（问的是个人意见）。
3. 认证考试（若参加）。
4. 实验进行期间，保持 Edge 窗口不被最小化。
