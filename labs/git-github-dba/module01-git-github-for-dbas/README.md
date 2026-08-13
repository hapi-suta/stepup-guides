# Module 01 - Git & GitHub for DBAs

Version control for database administrators who have never used it. The capstone: the student's REAL PostgreSQL configuration files (postgresql.conf, pg_hba.conf, postgresql.auto.conf) under git in the data directory, pushed to their own private GitHub repository - then broken and recovered with git during SURVIVE.

**Environment:** one CentOS Stream 9 server (pg-git-1, t3.small) with PostgreSQL 16 pre-installed and running at /opt/pgsql/data. Git is NOT pre-installed - installing it is a teaching step. The student needs a web browser to create their own free GitHub account.

## Concepts

| Doc | Title | Time |
|-----|-------|------|
| 01 | Why Version Control for DBAs | 15 min |
| 02 | The Git Mental Model | 20 min |
| 03 | Remotes, GitHub, and Security | 15 min |

## BUILD Guides

| Guide | Title | Duration |
|-------|-------|----------|
| 01 | Your First Repository | 30-35 min |
| 02 | Branches, Merging, and Undoing | 40-45 min |
| 03 | GitHub - Your Repository, Off the Server | 40-45 min |
| 04 | The Capstone - Version Control Your PostgreSQL Configs | 50-60 min |

## USE Exercises

| Exercise | Title | Duration |
|----------|-------|----------|
| 01 | The Blame Hunt | 15 min |
| 02 | pg_hba Lockout Forensics | 20 min |
| 03 | Tag Before the Maintenance Window | 15 min |
| 04 | The Pickaxe Hunt | 15 min |
| 05 | The Reflog Rescue | 15 min |

## SURVIVE Scenarios

| Scenario | Title | Severity |
|----------|-------|----------|
| 01 | Bad Config Committed: PostgreSQL Won't Start | CRITICAL |
| 02 | pg_hba Lockout: Locked Out of Your Own Database | HIGH |
| 03 | Detached HEAD: Nobody Knows What's on Disk | MEDIUM |
| 04 | Secret Committed: A Password in the Repo | HIGH |
| 05 | Deleted Repo: The History Is Gone From the Server | HIGH |

## Notes for instructors

- All commands live-tested 2026-08-13 on a t3.small CentOS Stream 9 box with PostgreSQL 16.14 (PGDG) and git 2.52.0 from AppStream.
- Guides 03 and 04 require the student's own GitHub account (free) - repos MUST be private.
- The postgres user already has an ed25519 key from provisioning; guide 04 uses it.
- SURVIVE inject/validate/revert scripts live in the control-plane chaos dir (not in this repo) so students cannot read the answers. Runbooks live here.
- Canonical references: git-scm.com/docs, the Pro Git book (git-scm.com/book), docs.github.com.
