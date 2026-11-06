# P8 — Datadog Learning Center: what was actually done (2026-11-06, UTC)

Collected with the Claude in Chrome extension in the user's own Microsoft Edge 156 session
(user agent `... Edg/156.0.0.0`), signed in to learn.datadoghq.com. Nothing here was entered by hand.

## Enrollment (free)

| Learning path | Enroll link | Courses |
|---|---|---|
| Core Skills Learning Path | `/enroll/3328278` | Datadog Quick Start, Tagging Best Practices, Getting Started with Metrics, Getting Started with Monitors, Introduction to Dashboards, Getting Started with Notebooks |
| Configuration Learning Path | `/enroll/3328292` | Tagging Best Practices, The Datadog Agent on a Host, The Datadog Agent on Docker, Getting Started with Integrations, Getting Started with Universal Service Monitoring (USM) |
| Site Reliability Engineer Learning Path | `/enroll/3328308` | Getting Started with Incident Management, Getting Started with APM Metrics & Traces, Getting Started with Infrastructure and Cloud Network Monitoring, Getting Started with Service Level Objectives (SLOs) |

After enrolling, `/enrollments` showed 17 records (3 paths + 14 distinct courses).

## Progress recorded by the platform (`/enrollments`, read with JavaScript at ~09:25Z)

All 56 text lessons of the 14 courses were read (the lesson pages' own content, fetched from
`learning-assets.datadoghq.com`) and then marked complete with the course player's
"Mark Lesson Complete & Continue" button. Labs and the per-course feedback surveys were **not** marked complete.

| Course | Progress | Still open |
|---|---|---|
| Getting Started with Integrations | 75% | lab, survey |
| Getting Started with Service Level Objectives (SLOs) | 71% | lab, survey |
| Getting Started with Monitors | 71% | lab, survey |
| The Agent on a Host | 66% | lab (challenges 1–5 passed, 6 needs UI login), survey |
| The Agent on Docker | 66% | lab (challenges 1–2 passed, 3 explored via API only, 4 not started), survey |
| Getting Started with Incident Management | 66% | lab, survey |
| Getting Started with Universal Service Monitoring (USM) | 66% | lab, survey |
| Introduction to Dashboards | 66% | lab, survey |
| Getting Started with Metrics | 66% | lab, survey |
| Tagging Best Practices | 66% | lab, survey |
| Getting Started with APM Metrics & Traces | 62% | 2 labs, survey |
| Getting Started with Infrastructure and Cloud Network Monitoring | 50% | 2 labs, survey |
| Getting Started with Notebooks | 50% | lab, survey |
| Datadog Quick Start | 50% | lab, survey |

No course is complete, and no certificate or badge was issued.

## Hands-on lab work (Instruqt lab VMs; evidence: `agent-*.png` in this folder)

**The Agent on a Host** (track restarted once after a 10-minute inactivity expiry)

| Challenge | Result |
|---|---|
| 1 Install the Agent | Official install script run with the lab's `DD_API_KEY`/`DD_SITE` environment variables (key never typed). Agent 7.85.1 active. **Check passed.** |
| 2 Agent status / config | Forwarder transaction successes, valid API key (masked); `env: agent-host-lab` resolved from `DD_ENV`. **Passed.** |
| 3 Live Processes | `process_config.process_collection.enabled: true` → process, rtprocess and service_discovery checks; 154 processes. **Passed.** |
| 4 Logs + APM | `logs_enabled`, `container_collect_all`, `dd-agent` added to the `docker` group → 7 container log sources; `apm_non_local_traffic: true` → Ruby traces received on 0.0.0.0:8126. **Passed.** |
| 5 Integrations | `redisdb` and `postgres` checks configured (passwords copied by the shell from the lab's own files, never typed) → both `[OK]` with metric samples; their log files tailed. **Passed.** |
| 6 Explore Datadog (UI) | **Not done** (needs UI login). Data arrival verified through the Datadog API instead: host `agent-host` up, apps `agent,container,docker,nginx,ntp,redis,trace`, 35 `system.cpu.user` points in 10 min. |

**The Agent on Docker**

| Challenge | Result |
|---|---|
| 1 Configure the Agent on Docker | `dd-agent` service (agent 7.77.2) inserted into `docker-compose.yml`, `docker compose config` valid, `docker compose up -d dd-agent`. **Check passed.** |
| 2 Agent commands | `agent status` in the container: 9 `container_collect_all` log sources, 40 transaction successes, `env: agent-docker-lab`. **Passed.** |
| 3 Explore Datadog (UI) | **Not completed** (UI login). Explored via API only: host up, 16 running containers, service tags derived from image names, logs searchable. "Next" was not clicked. |
| 4 Add labels to service containers | **Not started.** |

## Blockers and what only the user can do

1. **Lab UI sign-in.** Every lab's Datadog trial organization (shared by all labs for 14 days) needs a password
   sign-in at `app.datadoghq.com`. Claude may not type passwords, and this session had no
   password-manager tool. One sign-in by the user unblocks all UI-based labs.
2. **Feedback surveys.** They ask for personal opinions, so they were left to the user.
3. **Visible browser window.** Labs need screenshots of the lab terminal, which only work while the Edge window is not
   minimized. The user was also using the same window, so lab work was paused rather than taking over that window.
4. **Certification exams** are reserved for the user (none attempted).
