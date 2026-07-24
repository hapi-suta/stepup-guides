# Module 04 - Processes & systemd Services

Every day a DBA does a handful of core tasks. You start, stop, and restart the
database service. You check whether it is running. You read its logs to find out
why it failed. You hunt down stuck processes. This module teaches all of it. You
will learn to view and monitor processes, send signals to stop them, manage
services with systemd, read unit files, and investigate incidents with the
journal. This is the daily operational core of the job.

---

## Prerequisites

- Completion of Module 01 (Linux Fundamentals) - you need pipes, grep, and less
- Server access (CentOS Stream 9) - provided by your instructor
- SSH key from your welcome email
- A terminal application (Terminal on Mac, MobaXterm on Windows)

## Infrastructure

| Resource | Details |
|----------|---------|
| Nodes | 1 (your lab server) |
| OS | CentOS Stream 9 |
| SSH user | ec2-user |
| Package manager | dnf |

---

## Directory Structure

```
module04-processes-systemd/
  build/          Step-by-step guided labs
  use/            Independent exercises
  survive/        Chaos scenarios to troubleshoot
  concepts/       Reference material
```

---

## Phases

### Phase 1 - BUILD

Work through these guides in order. Each one builds on the previous.

| # | Guide | Time | Topics |
|---|-------|------|--------|
| 01 | [Viewing Processes](build/01-viewing-processes.md) | 45 min | ps aux, ps -ef, PID/PPID, grep, pgrep, sorting |
| 02 | [top and Live Monitoring](build/02-top-and-monitoring.md) | 45 min | top, load average, free -h, uptime, nproc |
| 03 | [Signals and kill](build/03-signals-and-kill.md) | 45 min | SIGTERM vs SIGKILL, kill, kill -9, pkill, SIGHUP |
| 04 | [systemctl Basics](build/04-systemctl-basics.md) | 60 min | status, start, stop, restart, enable, disable, is-active |
| 05 | [Reading a Unit File](build/05-reading-a-unit-file.md) | 45 min | systemctl cat, unit sections, daemon-reload, overrides |
| 06 | [Reading Service Logs with journalctl](build/06-journalctl-logs.md) | 45 min | journalctl -u, -f, --since, -p err, incident workflow |

### Phase 2 - USE

Complete these exercises without looking back at the BUILD guides.

| # | Exercise | Time | Focus |
|---|----------|------|-------|
| 01 | [Process Hunt](use/01-process-hunt.md) | 15-20 min | Find, filter, and sort processes |
| 02 | [Health Read](use/02-health-read.md) | 15-20 min | Interpret top, load average, and memory |
| 03 | [Signal Practice](use/03-signal-practice.md) | 15-20 min | Stop processes gracefully and forcibly |
| 04 | [Service Operator](use/04-service-operator.md) | 20 min | Drive a service through its full lifecycle |
| 05 | [Log Investigator](use/05-log-investigator.md) | 20 min | Answer incident questions with journalctl |
| - | [Knowledge Checklist](use/checklist.md) | 20 min | Self-assessment before Phase 3 |

### Phase 3 - SURVIVE

Your instructor will inject a problem into your server. You must diagnose and fix it using only the runbook and your BUILD knowledge.

| # | Scenario | Alert |
|---|----------|-------|
| 01 | [Service Won't Start](survive/01-service-wont-start/) | A service is in the failed state after a config change |
| 02 | [Runaway Process](survive/02-runaway-process/) | Server load is high and everything feels slow |
| 03 | [Disabled at Boot](survive/03-disabled-at-boot/) | Service runs now but does not survive a reboot |
| 04 | [Zombie and Stuck Process](survive/04-stuck-process/) | A process ignores a normal stop request |
| 05 | [Silent Log](survive/05-silent-log/) | Errors reported but the journal seems empty |

---

## Concepts

| Document | Topics |
|----------|--------|
| [Processes and systemd](concepts/systemd-and-processes.md) | Process model, PIDs, signals, load average, systemd units, unit states, the journal, DBA relevance |

---

## Time Estimate

| Phase | Time |
|-------|------|
| BUILD | 4-5 hours |
| USE | 1.5-2 hours |
| SURVIVE | 2-3 hours |
| **Total** | **7-10 hours** |

Work at your own pace. Take breaks between BUILD guides. Do not rush.

---

## Getting Help

If you get stuck:

1. Re-read the BUILD guide for the topic you are working on
2. Check the Concepts reference
3. Ask your instructor
