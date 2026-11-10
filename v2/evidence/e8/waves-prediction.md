# E8 sync waves on an empty cluster: hypotheses (written before rebuild R3)

R2 (E7, `evidence/e7/r2/wait-apps.txt`): the root application went through 11 waves; each waits for
the slowest application of the one before. Per application, from creation to Synced+Healthy (R2):

| wave (R2) | applications (seconds) | wave took |
|---|---|---|
| -6 .. -4 | gateway-api-crds 35, istio-base 38; istiod 11, istio-cni 21; ztunnel 9 | 68 s |
| -3 | **external-secrets 238**, monitoring 222 (healthy earlier), kyverno 277 / keda 335 (healthy at 107 / 127), cert-manager 88, openbao 41, namespaces | 243 s |
| -2 | cnpg-operator 158 (healthy earlier), tenants 15, mesh 20 | 34 s |
| -1 | barman-cloud 113, velero 88, loki 78, tempo 78, otel-collector 47, nats 36, valkey 27, policies 11 | 93 s |
| 0 | **pg-main 178** (restore from the archive), dashboards 4 | 178 s |
| 1, 2 | storefront (the services 46-76 s; the root does not wait for generated applications), insight 9 | - |

The root application took 692 s from its first sync to 35/35 Synced+Healthy; the rebuild 15.3 min.
Waves are dependency barriers; most of these do not depend on each other. New layout (9 waves):

| wave | applications | why there |
|---|---|---|
| -10, -8 | projects; baseline (PriorityClasses), **namespaces** (from -3) | plain objects, needed by many |
| -6 .. -4 | the Istio chain, unchanged | CRDs -> istiod/CNI -> ztunnel |
| -3 | the operators + **cnpg-operator** (from -2), **barman-cloud** (from -1, retries until cert-manager answers), **velero** (from -1) | nothing here needs another member except barman-cloud -> cert-manager |
| -2 | tenants, mesh, **pg-main** (from 0), nats, valkey, policies, loki, tempo, otel-collector, dashboards | need operators and CRDs only |
| -1 | storefront, backup-jobs | need PostgreSQL, NATS, Valkey, the tenants' accounts, OpenBao |
| 0 | insight | needs the tenants' SecretStore and an unsealed OpenBao |

| | Hypothesis | Measured by |
|---|---|---|
| W1 | the root application's first sync to 35/35 Synced+Healthy takes **at most 600 s** (R2: 692 s): barman-cloud, cnpg-operator and velero now run while external-secrets is still starting, and pg-main starts a wave earlier; estimate 565 s = 68 (Istio) + 243 (operators) + 178 (pg-main) + 76 (storefront) | wait-apps.sh timeline |
| W2 | no wave deadlock and no manual fix beyond the planned OpenBao restore and unseal | wait-apps.sh, the operator's log |
| W3 | sync impersonation works from the first sync: platform-root syncs as `argocd-root`, every other application with its project's account; no "no matching service account" | application states, audit log |
| W4 | the deployment events record the rebuild: one GitLab deployment per storefront service, status success | GitLab deployments |
| W5 | the rebuild, destroy to 35/35, takes **at most 13.5 min** (R2: 15.3 min) | rebuild timeline |

Not changed: the cluster creation and Argo CD installation (R2: 3.3 min), the Istio chain, and the
order inside each application (sync waves within charts).
