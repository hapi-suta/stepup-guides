# Module 01 - Linux Fundamentals

Your first steps on a Linux server. You will learn how to connect, navigate the
filesystem, create and manage files, view contents, search for text, and
understand file permissions. Every skill in this module is one you will use daily
as a DBA.

---

## Prerequisites

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
module01-linux-fundamentals/
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
| 01 | [Connecting to Your Server](build/01-connecting-to-your-server.md) | 45 min | SSH from Mac and Windows, the prompt, basic commands |
| 02 | [Navigating the Filesystem](build/02-navigating-the-filesystem.md) | 45 min | pwd, ls, cd, key directories for DBAs |
| 03 | [Files and Directories](build/03-files-and-directories.md) | 60 min | mkdir, touch, cp, mv, rm, directory layout |
| 04 | [Viewing File Contents](build/04-viewing-file-contents.md) | 45 min | cat, less, head, tail, wc |
| 05 | [Pipes, Redirects, and Grep](build/05-pipes-redirects-and-grep.md) | 60 min | stdout, stderr, pipes, grep, sort, uniq, cut |
| 06 | [File Permissions Basics](build/06-file-permissions-basics.md) | 45 min | rwx, chmod numeric and symbolic, DBA permissions |
| 07 | [Finding Files](build/07-finding-files.md) | 45 min | find, which, whereis, locate |

### Phase 2 - USE

Complete these exercises without looking back at the BUILD guides.

| # | Exercise | Time | Focus |
|---|----------|------|-------|
| 01 | [Filesystem Scavenger Hunt](use/01-filesystem-scavenger-hunt.md) | 15-20 min | Explore the server, answer questions |
| 02 | [Directory Builder](use/02-directory-builder.md) | 20 min | Build a PostgreSQL-style directory layout |
| 03 | [Log Detective](use/03-log-detective.md) | 20 min | Search and analyze log files |
| 04 | [Permission Fixer](use/04-permission-fixer.md) | 15-20 min | Diagnose and fix broken permissions |
| 05 | [Find Challenge](use/05-find-challenge.md) | 15-20 min | Locate files with find and pipes |
| - | [Knowledge Checklist](use/checklist.md) | 20 min | Self-assessment before Phase 3 |

### Phase 3 - SURVIVE

Your instructor will inject a problem into your server. You must diagnose and fix it using only the runbook and your BUILD knowledge.

| # | Scenario | Alert |
|---|----------|-------|
| 01 | [Missing PATH](survive/01-missing-path/) | grep: command not found when searching logs |
| 02 | [Full /tmp Directory](survive/02-full-tmp-directory/) | Application cannot create temporary files |
| 03 | [Wrong File Permissions](survive/03-wrong-file-permissions/) | DNS resolution is failing for local hostnames |
| 04 | [Broken Home Directory](survive/04-broken-home-directory/) | Cannot SSH into server - getting errors |
| 05 | [Read-Only Filesystem](survive/05-readonly-filesystem/) | Cannot write to /opt directory |
| 06 | [Missing Command](survive/06-missing-command/) | less: command not found when reading logs |
| 07 | [Disk Space Low](survive/07-disk-space-low/) | Low disk space warning on /var partition |
| 08 | [Broken Symlink](survive/08-broken-symlink/) | Configuration file missing |

### Concepts

| Document | Topics |
|----------|--------|
| [Linux Filesystem](concepts/linux-filesystem.md) | Filesystem hierarchy, inodes, file types, permissions deep dive, common filesystems |

---

## Time Estimate

| Phase | Time |
|-------|------|
| BUILD | 5-6 hours |
| USE | 1.5-2 hours |
| SURVIVE | 2-3 hours |
| **Total** | **8-11 hours** |

Work at your own pace. Take breaks between BUILD guides. Do not rush.

---

## Getting Help

If you get stuck:

1. Re-read the BUILD guide for the topic you are working on
2. Check the Concepts reference
3. Ask your instructor
