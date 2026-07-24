# Module 03 - Users, Groups & Permissions

This module is about who can do what on a Linux server. You will learn about
user accounts, groups, sudo and root, ownership, and how permissions work.
Then you will use all of it on the `postgres` user and its data directory.

PostgreSQL runs as a user called `postgres`. If the data directory has the
wrong owner or the wrong permissions, the database will not start. This is the
number one reason a database fails to start.

By the end, "permission denied" will be a problem you can fix on sight.

---

## Prerequisites

- Completion of Module 01 - Linux Fundamentals (especially File Permissions Basics)
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
module03-users-groups-permissions/
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
| 01 | [Users and Passwords](build/01-users-and-passwords.md) | 45 min | whoami, id, /etc/passwd, useradd, passwd, userdel |
| 02 | [Groups](build/02-groups.md) | 40 min | /etc/group, groups, groupadd, usermod -aG, shared access |
| 03 | [sudo and root](build/03-sudo-and-root.md) | 45 min | root vs user, sudo, sudo -u, su -, /etc/sudoers, least privilege |
| 04 | [Ownership](build/04-ownership.md) | 45 min | chown, chgrp, recursive -R, the postgres:postgres data dir |
| 05 | [Permissions Deep Dive](build/05-permissions-deep.md) | 50 min | octal recap, symbolic chmod, umask, sticky/setuid/setgid |
| 06 | [The postgres User](build/06-the-postgres-user.md) | 45 min | sudo su - postgres, unprivileged service account, 700 data dir |

### Phase 2 - USE

Complete these exercises without looking back at the BUILD guides.

_To be released with the USE phase._

### Phase 3 - SURVIVE

Your instructor will inject a problem into your server. You must diagnose and
fix it using only the runbook and your BUILD knowledge.

_To be released with the SURVIVE phase._

### Concepts

| Document | Topics |
|----------|--------|
| [The Linux Permissions Model](concepts/linux-permissions-model.md) | Users/groups/other, ownership, octal + symbolic, umask, special bits, DBA relevance tables |

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
