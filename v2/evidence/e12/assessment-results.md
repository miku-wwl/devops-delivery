# E12 assessments: results

Hypotheses: `assessment-prediction.md` (committed with the kit before the runs, d206ac8). Kit:
`assessment/`. Candidate: me, from the one-sentence symptom. Records: `t1.log`, `t2.log`, `t3.log`,
`p1.log`. Lab before and after every scenario: 39/39 applications Synced and Healthy.

| | Hypothesis | Measured | |
|---|---|---|---|
| A1 | T1 grade FAIL after the injection, PASS after the repair | injected 22:47:43: 37 applications with `ComparisonError ... authentication required: HTTP Basic: Access denied`; grade 0/3; evidence: the token itself still valid against GitLab (HTTP 200), so the cluster's copy was wrong; repair: the secret from the lab secrets through stdin; grade 3/3 after 25 s | confirmed |
| A2 | T2 FAIL after the injection, PASS after unsealing with the fixed script; key files unchanged | sealed after 11 s; grade 2/3 (the stores still reported Valid - External Secrets' status lags behind a sealed store; only the "unsealed" check caught it at that moment); `openbao-init.sh` unsealed in 5 s; grade 3/3, both key files unchanged and read-only | confirmed, with an observation |
| A3 | T3: checkout fails, browsing works, Argo CD silent; FAIL; PASS after removing the untracked policy | injected 22:49:09; orders logged `POST /orders 503`, ztunnel `handling RBAC update e12-quarantine`, the policy's field managers `kubectl-client-side-apply` and ztunnel's - not Argo CD; Argo CD 39/39 Synced/Healthy throughout; grade 2/4; deleted; grade 4/4 seven seconds later. During the first seconds checkout failed only intermittently (three probes in a row answered 200 while old connections drained) | confirmed, with an observation |
| A4 | P1 FAIL before, PASS after a merge request; no incident from the synthetic alerts | before: 3/8 (no rule in Git, none live, symptoms not inhibited; the controls not inhibited - the alerts existed); the rule through MR !46 (pipeline 90, 38 s), live in Alertmanager 38 s after the merge; after: 8/8; the alert bridge received 0 notifications during both gradings (the silence) | confirmed |

Observations for chapter 13:

- A grader has to look at the cause, not only at the symptom: T2's "secrets synced" check passed while
  OpenBao was sealed, T3's single probes passed while the fault was active.
- The rule of P1 has no `equal`: `OpenBaoSealed` is computed with `max()` and carries no namespace label;
  the four existing rules all use `equal`, and copying their pattern would produce a rule that never
  matches - the behavioural check (synthetic alerts) is what tells the two apart.
- Not tested: the rule against a real sealed OpenBao and the hourly snapshot job (it would need hours of
  a sealed OpenBao); the synthetic alerts carry the same label sets as the real ones.
