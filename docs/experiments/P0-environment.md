# 实验记录：P0 实验环境与工具链

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（证据时间戳为 UTC） |
| 路线图模块 | 环境准备（服务于 D1–D10） |
| 官方来源 | [Ubuntu WSL images](https://cloud-images.ubuntu.com/wsl/)、[Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)、[kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)、各工具 GitHub Releases |
| 软件版本 | 见 [versions.env](../../automation/lab/versions.env)；Docker Engine 29.9.3、Compose v5.7.0 |
| 环境 | Windows 11（WSL 2.7.3，mirrored 网络）→ WSL2 发行版 `devops-lab`（Ubuntu 24.04 LTS） |
| 状态 | **VALIDATED** |

## 目标

在不影响用户已有 Podman 环境的前提下，建立可复现的 Linux 实验环境（Docker Engine + Kind + 固定版本 CLI），并建立证据录制与 PDF 手册构建工具链。

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 下载 Ubuntu 24.04 WSL rootfs，按官方 `SHA256SUMS` 校验后 `wsl --import` 到 `D:\wsl\devops-lab` | 校验一致，导入成功（96 s） | [wsl-create.log](../../evidence/p0/wsl-create.log) |
| 2 | 以 root 运行 `bootstrap-root.sh`：wsl.conf（systemd）、用户 `devops`、Docker 官方 apt 源、inotify 参数、10 个 CLI | 10 个二进制全部 `sha256sum: OK`（144 s） | [bootstrap-root.log](../../evidence/p0/bootstrap-root.log) |
| 3 | `wsl --terminate` 后以 `devops` 用户验证：systemd、docker、hello-world、全部 CLI 版本、Kind 冒烟集群 | PID 1 为 systemd；Kind 节点 v1.37.0 在 15 s 内 Ready；transcript 失败命令数 0 | [verify.log](../../evidence/p0/verify.log)、[verify-kind-smoke.png](../../evidence/p0/verify-kind-smoke.png) |
| 4 | 记录资源与配置：16 vCPU、15 GiB 内存、overlayfs、cgroup v2 | 与预期一致 | [lab-info.log](../../evidence/p0/lab-info.log)、[wsl-distros.log](../../evidence/p0/wsl-distros.log) |
| 5 | 手册工具链自检：pandoc 3.8 → HTML → Edge 156（Playwright 1.64.1）→ PDF；Mermaid 12.3.0；目录页码两遍排版 | 自检 PDF 中文、代码、终端块、Mermaid、截图、提示框、表格均正常；目录页码与书签一致 | `manual/build/selftest.pdf`（构建产物，不入库） |

## 失败与排查

- `build.py` 首次运行时以尚不存在的 `manual/chapters` 作为工作目录，报错 `NotADirectoryError: [WinError 267]`；改为仓库根目录后通过。
- 自检发现封面页仍打印页脚（Chromium 的 `@page :first { margin: 0 }` 不能隐藏页脚模板）；改为封面单独打印、用 pypdf 克隆正文后插入封面，书签与目录链接验证仍指向正确页面。

## 局限性

- WSL2 默认只分配宿主机 50% 内存（15 GiB）；后续同时运行 GitLab CE 和完整可观测性栈时需要分时运行。
- 终端截图是由真实终端记录渲染的图片（标题栏注明“终端记录渲染”与录制时间），不是屏幕抓图。

## 清理（如需完全移除实验环境）

```powershell
wsl.exe --unregister devops-lab   # 会永久删除该发行版及其中所有数据
Remove-Item -Recurse D:\wsl\devops-lab, D:\wsl\images
```
