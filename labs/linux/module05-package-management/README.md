# Module 05 - Package Management with dnf

This module is about how software gets onto a Linux server. You will learn to
search for and inspect packages, then install and remove them. You will patch the
system, work with repositories, and add the official PostgreSQL repo. You will
also audit changes with dnf history and rpm. This is how PostgreSQL and its
dependencies actually get onto the box. It is a core DBA skill.

---

## Prerequisites

- Completed Module 01 - Linux Fundamentals (or equivalent comfort with SSH and the shell)
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
module05-package-management/
  build/          Step-by-step guided labs
  use/            Independent exercises
  survive/        Chaos scenarios to troubleshoot
  concepts/       Reference material
```

---

## Phases

### Phase 1 - BUILD

Work through these guides in order. Each one builds on the last.

| # | Guide | Time | Topics |
|---|-------|------|--------|
| 01 | [Searching for and Inspecting Packages](build/01-searching-and-info.md) | 40 min | dnf search, dnf info, dnf list installed, dnf provides |
| 02 | [Installing and Removing Packages](build/02-installing-and-removing.md) | 45 min | dnf install, dnf remove, the -y flag, dependencies |
| 03 | [Updating the System](build/03-updating-the-system.md) | 40 min | dnf check-update, dnf update/upgrade, security updates, patching |
| 04 | [Working with Repositories](build/04-repositories.md) | 40 min | /etc/yum.repos.d/, dnf repolist, enable/disable repos, .repo files |
| 05 | [Installing PostgreSQL from the Official Repo](build/05-installing-postgresql-repo.md) | 50 min | PGDG repo, repo RPM, module disable, postgresql16-server |
| 06 | [dnf history and rpm](build/06-dnf-history-and-rpm.md) | 40 min | dnf history, dnf history undo, rpm -qa, rpm -qf, rpm -ql |

### Concepts

| Document | Topics |
|----------|--------|
| [Packages and Repositories](concepts/packages-and-repositories.md) | rpm vs dnf, repos, dependency resolution, transactions, GPG signatures, patching, AppStream modules, DBA relevance |

---

## Time Estimate

| Phase | Time |
|-------|------|
| BUILD | 4-4.5 hours |
| **Total** | **4-4.5 hours** |

Work at your own pace. Take breaks between BUILD guides. Do not rush.

---

## Getting Help

If you get stuck:

1. Re-read the BUILD guide for the topic you are working on
2. Check the Concepts reference
3. Ask your instructor
