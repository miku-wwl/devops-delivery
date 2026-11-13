# E8 merge-request gate: hypotheses (written before the gate was switched on)

The configuration repository root/platform-gitops gets a pipeline (`gitops/.gitlab-ci.yml`): render
what Argo CD would deploy (`gitops/ci/render.sh`, Helm 4.3.1), apply the release policies
(`gitops/policies/release/`) with the Kyverno CLI 1.19.2 - image from localhost:5001 with a fixed
tag, requests and a memory limit, a readiness probe; in production at least two replicas. The
project merges only merge requests whose pipeline succeeded; nobody pushes to main
(`platform/gitops/setup.sh`). alice (team shop) is a Developer: she proposes, a Maintainer merges.

Found before switching it on, in a local run of the same pipeline: team insight's insight-api has no
readiness probe - the gate would reject the tenant's next change. It is fixed in the change that
introduces the gate.

| | Hypothesis |
|---|---|
| G1 | The change that introduces the gate goes through the gate itself (the publisher's merge request): pipeline green in about 1-2 min, merged |
| G2 | alice's merge request that sets catalog's image to `:latest`: the policy job fails on release-images; the merge is refused by GitLab (HTTP 405), main and the cluster stay unchanged |
| G3 | alice's merge request that removes catalog's memory limit: fails on release-resources; refused |
| G4 | alice's merge request with one replica of catalog in production: fails on release-prod-availability; refused |
| G5 | alice's compliant merge request (catalog's DB pool 10 -> 12): pipeline green; alice cannot merge it herself (Developer); merged by a Maintainer, Argo CD rolls catalog out within its polling interval (3 min) |
| G6 | A direct push to main, even by the administrator, is rejected |
