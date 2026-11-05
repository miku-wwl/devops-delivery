# Official Resources

本项目使用的官方课程、官方项目文档与工具发布渠道。版本号为本仓库实验实际固定的版本（2026-11-06 解析），见 [automation/lab/versions.env](../automation/lab/versions.env)。

| 模块 | 官方来源 | 类型 | 本项目使用的版本 |
|---|---|---|---|
| D1 | [GitHub Skills: Hello GitHub Actions](https://github.com/skills/hello-github-actions) | Official Training | 模板仓库当前版本 |
| D1 | [GitHub Actions Quickstart](https://docs.github.com/en/actions/get-started/quickstart)、[Reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)、[Rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) | Official Docs | — |
| D2 | [GitLab CI/CD Tutorial: complex pipeline](https://docs.gitlab.com/ci/quick_start/tutorial/)、[`.gitlab-ci.yml` reference](https://docs.gitlab.com/ci/yaml/)、[Install GitLab in Docker](https://docs.gitlab.com/install/docker/) | Official Docs | GitLab CE（Docker 镜像，执行时记录） |
| D3 | [Helm Docs](https://helm.sh/docs/)、[Chart Template Guide](https://helm.sh/docs/chart_template_guide/) | Official Project | Helm v4.3.1 |
| D4 | [Argo CD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)、[argocd-example-apps](https://github.com/argoproj/argocd-example-apps) | Official Project | Argo CD v3.6.1 |
| D5 | [Trivy](https://trivy.dev/)、[GitHub Artifact Attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)、[Sigstore Cosign](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)、[Syft](https://github.com/anchore/syft) | Official Project / Docs | Trivy 0.76.2、Cosign v3.1.4、Syft 1.57.0 |
| D6 | [Argo Rollouts Getting Started](https://argo-rollouts.readthedocs.io/en/stable/getting-started/)、[Analysis & Progressive Delivery](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/)、[GitHub Deployment Environments](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments) | Official Project / Docs | Argo Rollouts v1.10.2 |
| D7 / O1 | [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/)、[OTel for Ops](https://opentelemetry.io/docs/getting-started/ops/)、[Prometheus Getting Started](https://prometheus.io/docs/prometheus/latest/getting_started/)、[Grafana Learning Hub](https://grafana.com/docs/learning-hub/) | Official Project | OTel Demo 3.1.0；其余以 Helm Chart 版本记录 |
| D8 / O2 | [Datadog Learning Paths](https://learn.datadoghq.com/pages/learning-paths)、[SRE Learning Path](https://learn.datadoghq.com/bundles/site-reliability-engineer-learning-path) | Official Training | 需用户账号 |
| D9 | [Datadog: Synthetic Tests in a CI/CD Pipeline](https://learn.datadoghq.com/courses/synthetic-tests-ci-cd-pipeline)；开源替代：[k6 thresholds](https://grafana.com/docs/k6/latest/using-k6/thresholds/)、[kind](https://kind.sigs.k8s.io/) | Official Training / Project | k6 v2.3.0 |
| D10 | [Ansible Getting Started](https://docs.ansible.com/projects/ansible/latest/getting_started/get_started_ansible.html) | Official Docs | 执行时记录 |
| 环境 | [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)、[kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)、[kubectl install](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)、[Ubuntu WSL images](https://cloud-images.ubuntu.com/wsl/) | Official Docs | kubectl v1.37.2、kind v0.33.0、Ubuntu 24.04 LTS |

**辅助材料（非官方）：** [Learn Observability in 5 Hours — Abhishek Veeramalla](https://www.youtube.com/watch?v=cYAE0ZhT43c)，仅作背景理解，不作为任何官方课程完成的证据。
