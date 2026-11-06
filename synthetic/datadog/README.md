# Datadog Synthetic variant of the gate (NOT_RUN)

Status: **NOT_RUN.** This project has no Datadog account for CI use, and the lab trial
organizations from the Learning Center must not be reused outside their labs. These files
are a reviewed starting point, not something that was executed.

## Idea

The open-source gate (`synthetic/run-gate.sh`, `.github/workflows/synthetic-gate.yml`) runs
k6 journeys against a throwaway Kind deployment. The Datadog variant runs the same journeys
as **Datadog Synthetic API tests**. The tests are defined once in Datadog (UI, API or
Terraform) and triggered from CI with the `datadog-ci` CLI:

1. CI deploys the candidate exactly as the open-source gate does (Kind + Helm + port-forward).
2. `datadog-ci synthetics run-tests` asks Datadog to run the referenced tests. The
   **Continuous Testing tunnel** (`"tunnel": true`) lets Datadog's managed locations reach the
   private URL on the runner. `testOverrides.startUrl` points each test at that URL.
3. The CLI waits for the results and exits non-zero when a test fails, which blocks the
   release job exactly like the k6 gate.

## Files

| File | Purpose |
|---|---|
| `datadog-ci.json` | global CLI config: site, failure policy, tunnel, which test files to run |
| `demo-api.synthetics.json` | the tests to run (by public ID) and their per-run overrides |

## How it would run (after creating the tests in your own Datadog org)

```bash
export DATADOG_API_KEY=...  DATADOG_APP_KEY=...   # GitHub Actions secrets, never committed
npx --yes @datadog/datadog-ci@5.25.0 synthetics run-tests --config synthetic/datadog/datadog-ci.json
```

Replace `<public-test-id>` with the IDs of the tests you created. Option names follow the
`datadog-ci` documentation for the version pinned above. Check them against that
documentation before the first real run, because they were not exercised here.
