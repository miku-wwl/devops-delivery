# The image of the configuration repository's pipeline (E8, chapter 9): Helm to render what Argo CD
# will render, the Kyverno CLI to apply the release policies - the same engine as the admission
# controller in the cluster. The Kyverno CLI image has no shell, which GitLab's runner needs.
FROM ghcr.io/kyverno/kyverno-cli:v1.19.2 AS kyverno
FROM alpine/helm:4.3.1
COPY --from=kyverno /ko-app/kubectl-kyverno /usr/local/bin/kyverno
ENTRYPOINT []
