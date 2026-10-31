# DevOps Delivery Engineering

**CI/CD · GitOps · DevSecOps · Progressive Delivery · Observability**

DevOps Delivery Engineering is an evidence-driven engineering portfolio focused on secure software delivery, release reliability, and production-style observability. It uses official vendor and open-source project exercises as the training foundation and records independently reproduced results in a controlled environment.

> **Status: PLANNED — repository initialization.** No training module, deployment, incident drill, or external learning credential is claimed as completed.

## Why this repository exists

Unlike [KPCP](https://github.com/miku-wwl/kube-platform-control-plane), which explores Kubernetes infrastructure reconciliation and Terraform-controlled resource lifecycles, this repository focuses on the software delivery path:

`Commit → Build → Test → Security Scan → Provenance → GitOps Deployment → Canary → Observe → Promote / Abort → Incident Review`

It complements AWS and Azure CloudOps specializations instead of recreating a cloud infrastructure control plane.

## Training policy

- **Official training:** GitHub Skills, GitLab, Datadog Learning Center, and Red Hat.
- **Official project tutorials:** Helm, Argo CD, Argo Rollouts, Trivy, Sigstore, OpenTelemetry, Prometheus, and Grafana.
- **One requested independent video:** [Learn Observability in 5 Hours](https://www.youtube.com/watch?v=cYAE0ZhT43c), by Abhishek Veeramalla; supplemental only, **not an official course**.
- **Custom engineering gates:** designed for this project; not vendor-issued exams or certificates.

See [Official Resources](docs/OFFICIAL_RESOURCES.md) and the [Full Training Roadmap](docs/DEVOPS_SPECIALTY_ROADMAP.md).

## Modules

| ID | Track | Evidence goal | State |
|---|---|---|---|
| D1 | GitHub Actions | PR checks, build/test artifacts, failure gates | NOT_RUN |
| D2 | GitLab CI/CD | Independent pipeline, MR rules, caching/artifacts | NOT_RUN |
| D3 | Helm | Versioned chart, templating, reproducible installs | NOT_RUN |
| D4 | Argo CD / GitOps | Sync, drift detection, controlled recovery | NOT_RUN |
| D5 | DevSecOps | Trivy scans, SBOM, image digest / attestation | NOT_RUN |
| D6 | Argo Rollouts | Canary, pause, promotion and abort | NOT_RUN |
| D7 | Open observability | OTel Demo, Prometheus, Grafana; logs/metrics/traces | NOT_RUN |
| D8 | Datadog Learning | Core Skills, Configuration, SRE, logs / Kubernetes topics | NOT_RUN |
| D9 | Datadog × CI/CD | Synthetic tests influence a release gate | NOT_RUN |
| D10 | Ansible (optional) | Repeatable host automation | NOT_RUN |

## Suggested sequence

1. **Week 1 — CI:** GitHub Skills and GitLab's official pipeline tutorial.
2. **Week 2 — Delivery:** Helm + Argo CD, no new application platform.
3. **Week 3 — Security & releases:** Trivy, image provenance, Argo Rollouts.
4. **Week 4 — Observability foundations:** specified video as background, then official OpenTelemetry Demo / Prometheus / Grafana exercises.
5. **Week 5 — Datadog:** official Core Skills, Configuration, SRE learning paths and relevant observability topics.
6. **Week 6 — Integrated validation:** Datadog synthetic CI/CD gate, canary failure, abort and incident review.

Six weeks is a suggested sequence, **not** a guaranteed timeline or official course schedule.

## Verification and evidence

Every completed module should include:

- Official course/source URL and the pinned software version or commit (if appropriate)
- Test environment, setup and teardown commands
- Objective, expected result and observed result
- Evidence links (CI job URL, sanitized screenshots, logs or test report)
- Failure investigation and limitations
- Credential / resource cleanup confirmation

Use [Experiment Template](docs/templates/EXPERIMENT.md), [Course Log Template](docs/templates/COURSE_LOG.md), and [Incident RCA Template](docs/templates/INCIDENT_RCA.md). Update [STATUS](docs/STATUS.md) **only after validation**.

## Planned repository layout

```text
.github/workflows/     Minimal repository checks (not course completion)
docs/                  Roadmap, official resources, progress, experiments and RCA
delivery/              Helm, GitOps and progressive rollout material (planned)
automation/            Reusable CI scripts and automation (planned)
observability/         OTel, Prometheus, Grafana and Datadog work (planned)
evidence/              Sanitized evidence and links (planned)
```

## Boundaries

- No new Kubernetes operators, infrastructure provisioning platform, Terraform approval engine or custom cloud control plane.
- Use an existing small app or the official OpenTelemetry Demo as the workload; a reference workload is not presented as original business software.
- Start local with Docker / Kind when supported; a real SaaS or cloud experiment must have a cost/credential review first.
- Never commit credentials, kubeconfigs, Datadog API keys, real customer data or unredacted logs.
- Use the original vendor exercises as learning material; custom integrated tests are clearly identified as **custom**.

## Attribution

Training links are owned by their respective publishers. The independent video is by Abhishek Veeramalla. This repository is not affiliated with GitHub, GitLab, CNCF projects or Datadog.
