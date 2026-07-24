# Module 07 - Networking and Scheduling

This is where "the app cannot connect to the database" gets solved. You will
learn a set of key skills. You will find your server's addresses. You will check
that PostgreSQL is listening on its port. You will open firewall rules and test
if a client can connect. You will look up hostnames. You will schedule jobs that
repeat, like backups and maintenance.

A DBA reaches for every one of these skills during an outage. You also use them
when setting up automation you can trust.

---

## Prerequisites

- Server access (CentOS Stream 9) - provided by your instructor
- SSH key from your welcome email
- A terminal application (Terminal on Mac, MobaXterm on Windows)
- Comfort with the command line and `vi` (Module 01)

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
module07-networking-scheduling/
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
| 01 | [IP Addresses and Hostnames](build/01-ip-and-hostname.md) | 45 min | ip addr, ip route, hostname, hostnamectl |
| 02 | [Ports and Listening Sockets](build/02-ports-and-listening.md) | 45 min | ss -tulpn, 5432, LISTEN vs ESTABLISHED, 127.0.0.1 vs 0.0.0.0 |
| 03 | [The Firewall (firewalld)](build/03-firewalld.md) | 45 min | firewall-cmd, --add-port, --permanent, --reload, zones |
| 04 | [Testing Connectivity](build/04-testing-connectivity.md) | 45 min | ping, nc -zv, curl, refused vs timed out |
| 05 | [Hosts File and DNS](build/05-hosts-and-dns.md) | 45 min | /etc/hosts, /etc/resolv.conf, nslookup, dig, resolution order |
| 06 | [Scheduling with Cron and Timers](build/06-cron-and-timers.md) | 60 min | crontab, cron syntax, nightly backups, systemd timers, logs |

### Phase 2 - USE

Complete these exercises without looking back at the BUILD guides.

| # | Exercise | Time | Focus |
|---|----------|------|-------|
| 01 | [Network Recon](use/01-network-recon.md) | 15-20 min | Map the server's addresses, routes, and listeners |
| 02 | [Open the Port](use/02-open-the-port.md) | 20 min | Open 5432 in the firewall and verify end to end |
| 03 | [Connection Detective](use/03-connection-detective.md) | 20 min | Diagnose refused vs timed out from clues |
| 04 | [Name That Host](use/04-name-that-host.md) | 15-20 min | Add hosts entries and test resolution |
| 05 | [Schedule a Backup](use/05-schedule-a-backup.md) | 20 min | Write, install, and verify a cron job |
| - | [Knowledge Checklist](use/checklist.md) | 20 min | Self-assessment before Phase 3 |

### Phase 3 - SURVIVE

Your instructor will inject a problem into your server. You must diagnose and fix
it using only the runbook and your BUILD knowledge.

| # | Scenario | Alert |
|---|----------|-------|
| 01 | [Port Not Listening](survive/01-port-not-listening/) | Clients get connection refused to the database |
| 02 | [Firewall Blocking 5432](survive/02-firewall-blocking/) | Remote clients time out; local connects work |
| 03 | [Listening on Loopback Only](survive/03-loopback-only/) | App on another host cannot connect |
| 04 | [Broken DNS Resolution](survive/04-broken-dns/) | Backup job fails to resolve its target host |
| 05 | [Missing /etc/hosts Entry](survive/05-missing-hosts-entry/) | Replication cannot reach the standby by name |
| 06 | [Backup Cron Not Running](survive/06-backup-cron-silent/) | Nightly backup file is missing this morning |

### Concepts

| Document | Topics |
|----------|--------|
| [Linux Networking](concepts/linux-networking.md) | Addresses, ports, sockets, firewall, DNS resolution order, scheduling, DBA relevance |

---

## Time Estimate

| Phase | Time |
|-------|------|
| BUILD | 4.5-5 hours |
| USE | 1.5-2 hours |
| SURVIVE | 2-3 hours |
| **Total** | **8-10 hours** |

Work at your own pace. Take breaks between BUILD guides. Do not rush.

---

## Getting Help

If you get stuck:

1. Re-read the BUILD guide for the topic you are working on
2. Check the Concepts reference
3. Ask your instructor
