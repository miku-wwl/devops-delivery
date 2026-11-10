# E12 assessments: hypotheses (written before the runs)

The assessment kit is `assessment/` (README.md, design.md, three troubleshooting scenarios, one
practical exam). The question for E12's acceptance is whether the scripts run and grade correctly on
the real lab - so each grader must fail on the injected fault and pass on the fixed lab, and each
`restore` must leave the lab as it was. The candidate is me, working from the one-sentence symptom.
`[注入]`: every fault; everything else is real.

| | Hypothesis | Measured by |
|---|---|---|
| A1 | T1 (Argo CD's repository credential broken): grade FAIL after the injection (ComparisonError on the applications), PASS after the repair; the lab back at 39/39 Synced/Healthy | grader output, application status |
| A2 | T2 (OpenBao restarted, sealed): grade FAIL after the injection; PASS after unsealing with the fixed `openbao-init.sh`; the key files' hashes unchanged | grader output |
| A3 | T3 (DENY AuthorizationPolicy on payments, applied outside Git): checkout fails while browsing works and Argo CD reports nothing; grade FAIL; PASS after removing the untracked policy | grader output, probes |
| A4 | P1 (inhibition for a sealed OpenBao): grade FAIL before the change (no rule, symptoms not inhibited); PASS after a merge request adds a correct rule; no GitLab incident is opened by the synthetic alerts | grader output, alert bridge events |
