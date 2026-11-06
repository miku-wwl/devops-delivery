# delivery-gitops (config repository seed)

This directory is the **seed** of a separate GitOps configuration repository. Argo CD
watches that repository, never this one directly:

```text
delivery-gitops/                 (created by delivery/argocd/seed-gitops-repo.sh)
├── apps/                        Argo CD AppProject + one Application per environment
├── charts/demo-api/             copy of delivery/helm/demo-api at seed time
└── envs/
    ├── dev/values.yaml          deployment state for dev  (image tag / digest)
    └── prod/values.yaml         deployment state for prod (changed only by promotion MRs)
```

Why a separate repository: application code changes often and triggers CI; desired
deployment state changes rarely and must be auditable. Keeping them apart means a
commit to the config repository *is* a deployment, and its history *is* the
deployment log.

In the lab the repository lives on the local GitLab (`http://gitlab:8929/root/delivery-gitops.git`).
The scripts accept another URL, so the same layout works on any Git server.
