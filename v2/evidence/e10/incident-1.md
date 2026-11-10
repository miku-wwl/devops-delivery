# Incident E10-1: a virtual-load experiment froze the real lab (2026-11-10)

Blameless. Unplanned; everything below happened.

## What happened

| Time (UTC) | |
|---|---|
| 09:41-09:49 | kwokctl cluster "scale" (real control plane, `[虚拟]` nodes and pods) with 1000 nodes and 10 000 pods: K1 and K4 measured. Its containers held about 1.85 GiB; the WSL VM had **2.3 GiB available** before K5 |
| 09:50:00 | K5: the victim client alone for 30 s (p50 16.8 ms, p99 42.8 ms) |
| 09:50:30 | the flood starts: 40 workers LIST all pods (33 MiB each) as e10-flood |
| 09:50:30-~09:54 | APF rejects 1289 of 1329 flood requests with 429 (p50 0.095 s); 36 end in 504; 4 are admitted and take 123-208 s each. The victim's GETs slow down (p50 430 ms, p99 10.4 s) and stop after 36 of about 120 |
| ~09:54 | the WSL VM stops answering (`Wsl/Service/0x8007274c`); the lab cluster `ent`, GitLab, the alert bridge - everything in the VM - freezes |
| 10:01-10:05 | the VM holds 13.6 GB on Windows; two waits (45 s, 90 s) for the kernel to recover, no answer |
| ~10:06 | `wsl --terminate devops-lab`: load average at restart 858 / 971 / 587 (1/5/15 min) |
| 10:06-10:10 | Docker restarts the containers with a restart policy (GitLab, registries, mirrors, alert bridge - and the kwok containers, deleted at once); the four kind nodes of `ent` exited with 128 and are started by hand; all Ready after 60 s |
| 10:08-10:10 | OpenBao unsealed (`openbao-init.sh`), load balancer limits re-applied; 38/38 applications Synced and Healthy |
| 10:06:33 | the alert bridge restarts; its dead man's check finds the last heartbeat from before the freeze and tries to open an incident - GitLab is still starting, the HTTP call fails, and the thread dies with the exception: **the dead man's switch is off and says nothing** |
| 10:11:57 | the bridge fixed (every check on its own, errors logged and retried; `/healthz` fails when the thread is gone) and redeployed; no incident records the outage - by then the heartbeat was back |

## Why

- The control plane under test ran next to the lab in the same VM, without memory limits. Virtual
  nodes need no memory; the control plane that manages them does - about 1.85 GiB at 10 000 pods (the
  API server alone 0.95 GiB) - and it shares the VM's 15.3 GiB with the lab cluster (11.8 GiB in use).
- APF limits how many requests the API server works on, not how much memory or CPU the machine has.
  The admitted LISTs of 33 MiB and the rest of the load pushed a VM with 2.3 GiB available into
  swapping; from there every process, the victim client included, slowed down together.
- The memory guard of the experiment (`scale.sh`: stop below 800 MiB) ran only between timeline
  steps; the flood script had none.
- The dead man's switch runs on the same machine as what it watches: a freeze of the machine freezes
  the watcher too, and its first action after the restart crashed it.

## Action items

| # | | Status |
|---|---|---|
| 1 | The alert bridge survives errors (each dead man's check isolated, retried; `/healthz` reports a dead thread) | done (`platform/alerting/bridge.py`) |
| 2 | Experiment control planes get memory limits (`docker update --memory`) so that an overload kills a container inside its own cgroup instead of freezing the VM; the flood watches the available memory and stops below 1.2 GiB | for the K5 re-run |
| 3 | A watcher on another machine (here: none exists; chapter 10, limits) | open |
| 4 | Load experiments that can exhaust a resource run with less sharing: lower scale, or the lab cluster paused | noted |
