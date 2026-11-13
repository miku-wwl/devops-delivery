# 实验记录：P11 / D10 Ansible（可选模块）

| 字段 | 内容 |
|---|---|
| 日期 | 2026-11-06（UTC） |
| 路线图模块 | D10 Ansible：Inventory、Playbook、幂等性 |
| 官方来源 | [Ansible 文档](https://docs.ansible.com/)、[community.docker 集合](https://docs.ansible.com/ansible/latest/collections/community/docker/) |
| 软件版本 | ansible-core 2.20.11；docker SDK 7.2.0；community.docker 5.4.0；托管节点镜像 `ubuntu:24.04@sha256:fe815609…` |
| 环境 | WSL2 `devops-lab` 中的 Python 虚拟环境；托管节点是两个容器，经 `community.docker.docker` 连接（docker exec） |
| 状态 | **VALIDATED** |

## 步骤与结果

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| 1 | 第一次运行（没有设置 `ANSIBLE_CONFIG`） | **失败**：仓库在 drvfs 挂载上，目录看起来对所有人可写，Ansible 拒绝加载当前目录的 `ansible.cfg`，没读到 Inventory，报 `groups['lab_nodes']` 未定义 | [run-0-cfg-ignored.log](../../evidence/p11/run-0-cfg-ignored.log) |
| 2 | 设置 `ANSIBLE_CONFIG` 后的首次运行 | localhost changed=1（创建了两个容器）；node1、node2 各 changed=8（raw 安装 Python、软件包、组、用户、目录、模板、logrotate、handler） | [run-1.log](../../evidence/p11/run-1.log) |
| 3 | 第二次运行 | 三台主机都是 **changed=0**；渲染的配置按主机不同（node2 由 host_vars 覆盖为 staging、replicas 2） | [run-2-idempotent.log](../../evidence/p11/run-2-idempotent.log) |
| 4 | 漂移：在 node1 上手工改 `replicas: 5` | `--check --diff` 显示差异但不修改文件；正式运行后恢复为 1，handler 只触发一次；之后再运行全部 changed=0 | [run-3-drift.log](../../evidence/p11/run-3-drift.log) |

## 失败与排查

1. **`ansible.cfg` 被忽略（world-writable 目录）。** 这是 Ansible 的安全设计：当前目录对所有人可写时，不从这里加载配置，防止被人放入恶意配置。解决办法是用 `ANSIBLE_CONFIG` 显式指定配置文件（官方给出的做法），或者把项目放到 Linux 原生路径下。
2. **check 模式下 `raw` 任务被跳过**（skipped=2）。`raw` 不支持 check 模式，属于正常现象；dry run 的结论只针对支持 check 模式的模块。

## 清理

`docker rm -f node1 node2`（P12 统一清理）；Python 虚拟环境在 `~/work/ansible-venv`。
