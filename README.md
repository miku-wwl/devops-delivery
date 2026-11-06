# DevOps Delivery Engineering

**CI/CD · GitOps · DevSecOps · Progressive Delivery · Observability**

DevOps Delivery Engineering is an evidence-driven engineering portfolio focused on secure software delivery, release reliability, and production-style observability. It uses official vendor and open-source project exercises as the training foundation and records independently reproduced results in a controlled environment.

> **Status (2026-11-07):** phases P0–P12 executed in a local lab (Windows 11 + WSL2 + Kind) and GitHub Actions. Ten modules are **VALIDATED** by recorded evidence; the Datadog learning module is **PARTIAL** and the Datadog Synthetic variant is **NOT_RUN** (see the table below and [STATUS](docs/STATUS.md)). No vendor certificate or course completion is claimed. Owner actions that remain open are listed under [Open items](#open-items).

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

| ID | Track | Evidence goal | State | Record |
|---|---|---|---|---|
| D1 | GitHub Actions | PR checks, build/test artifacts, failure gates | VALIDATED (official GitHub Skills exercise not run: it needs a new public repository) | [P1](docs/experiments/P1-github-actions.md) |
| D2 | GitLab CI/CD | Independent pipeline, MR rules, caching/artifacts | VALIDATED (self-hosted GitLab CE) | [P2](docs/experiments/P2-gitlab-ci.md) |
| D3 | Helm | Versioned chart, templating, reproducible installs | VALIDATED | [P3](docs/experiments/P3-helm.md) |
| D4 | Argo CD / GitOps | Sync, drift detection, controlled recovery | VALIDATED | [P4](docs/experiments/P4-gitops.md) |
| D5 | DevSecOps | Trivy scans, SBOM, image digest / attestation | VALIDATED | [P5](docs/experiments/P5-supply-chain.md) |
| D6 | Argo Rollouts | Canary, pause, promotion and abort | VALIDATED, with an erratum found in P7 (GitHub production approval awaits the owner) | [P6](docs/experiments/P6-progressive-delivery.md) |
| D7 | Open observability | OTel Demo, Prometheus, Grafana; logs/metrics/traces | VALIDATED | [P7](docs/experiments/P7-observability.md) |
| D8 | Datadog Learning | Core Skills, Configuration, SRE, logs / Kubernetes topics | PARTIAL: all 56 lessons read and recorded; 7 lab challenges passed; web-login parts, surveys and certification remain with the owner | [P8](docs/experiments/P8-datadog-learning.md) |
| D9 | Observability × CI/CD | Synthetic tests influence a release gate | VALIDATED with an open-source gate (Kind + k6 in CI); Datadog Synthetic variant NOT_RUN | [P9](docs/experiments/P9-synthetic-gate.md) |
| O3 | Integrated delivery loop | Commit → … → canary → promote / abort → RCA | VALIDATED, two RCAs | [P10](docs/experiments/P10-closed-loop.md), [RCA](docs/rca/) |
| D10 | Ansible (optional) | Repeatable host automation | VALIDATED (second run `changed=0`) | [P11](docs/experiments/P11-ansible.md) |

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

## The handbook

The phases are written up as a Chinese textbook, built from `manual/chapters/` with `manual/tools/build.py` (pandoc + Edge):
**[manual/dist/DevOps-Delivery-Observability-Handbook.pdf](manual/dist/DevOps-Delivery-Observability-Handbook.pdf)** (241 pages: preface, 13 chapters, appendices A–E).
Every command output and screenshot in it comes from the recorded evidence; `manual/tools/verify_evidence.py` re-checks the book against the evidence. See the [acceptance report](docs/ACCEPTANCE_REPORT.md) for how the book was reviewed.

## Repository layout

```text
app/                   demo-api, the reference workload (FastAPI), with tests and Dockerfile
.github/workflows/     ci (PR gate), release (gate → scan → sign → attest), synthetic-gate, production-gate
.gitlab-ci.yml         GitLab pipeline (self-hosted GitLab in the lab)
delivery/              kind, Helm chart, GitOps seed, Argo CD / Rollouts scripts, monitoring, Kyverno policy, k6 load
observability/         OTel Collector, LGTM backend, alert and SLO rules, OTel Demo overrides
synthetic/             k6 user journey and pre-release gate; Datadog Synthetic templates (not run)
ansible/               inventory, playbook and role (optional module)
automation/            lab bootstrap, GitLab setup, CI tool installers, evidence recorder
docs/                  roadmap, phase plan, STATUS, experiment records, RCAs, acceptance report
evidence/p0 … p12/     terminal transcripts and screenshots
manual/                handbook sources, styles, build and QA tools, built PDF
```

## Open items

These need the repository owner and were deliberately not done by automation:

1. Review and merge PRs #1–#3 and the stacked phase branches (`p4/…` to `p12/…`); then add the `security` check to the `protect-main` ruleset.
2. Approve or reject the waiting production-gate run 42142945642.
3. Mark the GitGuardian finding from P2 as a false positive.
4. Do the official GitHub Skills exercise "Hello GitHub Actions".
5. Datadog Learning Center: log in to the lab trial account, finish the web parts of the two Agent labs, fill in the course surveys; the certification exam is optional.

## Boundaries

- No new Kubernetes operators, infrastructure provisioning platform, Terraform approval engine or custom cloud control plane.
- Use an existing small app or the official OpenTelemetry Demo as the workload; a reference workload is not presented as original business software.
- Start local with Docker / Kind when supported; a real SaaS or cloud experiment must have a cost/credential review first.
- Never commit credentials, kubeconfigs, Datadog API keys, real customer data or unredacted logs.
- Use the original vendor exercises as learning material; custom integrated tests are clearly identified as **custom**.

## Attribution

Training links are owned by their respective publishers. The independent video is by Abhishek Veeramalla. This repository is not affiliated with GitHub, GitLab, CNCF projects or Datadog.
