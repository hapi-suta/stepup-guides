# Guide 01 - PostgreSQL Timeline Exploration

Trace the evolution of PostgreSQL from a Berkeley research project to the world's most
advanced open source database.

**Mode:** AI Lab (no server needed)
**Time:** 30 minutes

---

## Overview

In this exercise you will research and document the PostgreSQL timeline, explore how
versioning changed in version 10, and map key features to the releases that introduced
them. You will use the concepts reading, the official PostgreSQL release notes, and your
AI assistant to complete the tasks.

By the end of this guide you will be able to:

- Name the major phases of PostgreSQL's development
- Explain the pre-10 vs post-10 versioning difference
- Match 10 or more major features to the version that introduced them
- Draw a rough timeline from memory

---

## Task 1 - Document Five Major Releases

Research each of the five releases below and fill in the table. Use the concepts reading
first, then cross-reference with the official release notes at:
`https://www.postgresql.org/docs/release/`

For each release, identify:
- The year it shipped
- Two or three features that made it significant
- One sentence explaining why it mattered

Fill in this table:

| Version | Year | Key Features (2-3) | Why It Mattered |
|---------|------|-------------------|-----------------|
| 7.1     |      |                   |                 |
| 8.0     |      |                   |                 |
| 9.0     |      |                   |                 |
| 9.4     |      |                   |                 |
| 10      |      |                   |                 |

**Completed reference table (check your work after):**

| Version | Year | Key Features | Why It Mattered |
|---------|------|--------------|-----------------|
| 7.1     | 2001 | WAL, sequences | First crash-safe release. Before WAL, a server crash could leave the database unreadable. |
| 8.0     | 2005 | Windows port, PITR, tablespaces | Opened PostgreSQL to the Windows ecosystem and gave DBAs point-in-time recovery. |
| 9.0     | 2010 | Streaming replication, hot standby | Built-in HA became possible without third-party tools. |
| 9.4     | 2014 | JSONB, logical decoding, replication slots | JSONB made the "use MongoDB for JSON" argument obsolete. |
| 10      | 2017 | Logical replication, declarative partitioning, new versioning | First release with built-in logical replication and a cleaner partitioning syntax. |

---

## Task 2 - Versioning Then and Now

PostgreSQL changed its version numbering with the release of version 10. This trips up
a lot of people who are used to the old scheme.

Read the explanation below and then answer the questions.

### The Old Scheme (before version 10)

In the old scheme, the major version was defined by the first TWO numbers.

```
Major version:  9.6
Minor release:  9.6.0  -> 9.6.1  -> 9.6.5

Major version:  9.5
Minor release:  9.5.0  -> 9.5.10

Major version:  8.4
Minor release:  8.4.0  -> 8.4.22
```

Minor releases contained only bug fixes and security patches. No new features.
Major releases added new features and could require a dump/restore to upgrade.

### The New Scheme (version 10 onward)

From version 10, the major version is just the first number.

```
Major version:  10
Minor release:  10.0  -> 10.5  -> 10.23

Major version:  11
Minor release:  11.0  -> 11.1

Major version:  16
Minor release:  16.0  -> 16.3
```

The logic is the same - minor releases are bug fixes only. But the numbering is simpler.

### Questions

Answer these questions. Write your answers in the blank lines.

**Question 1:** Under the old scheme, was `9.5` a major version or a minor version?

Your answer: ___________________________________________________________

Reference answer: `9.5` is a major version. Under the old scheme, major versions were
identified by the first two numbers (e.g., 9.4, 9.5, 9.6). The third number (e.g.,
9.5.3) indicated a minor bug-fix release.

---

**Question 2:** Under the new scheme, is `16.3` a major or minor release?

Your answer: ___________________________________________________________

Reference answer: `16.3` is a minor (bug fix) release of major version 16. The major
version is just `16`.

---

**Question 3:** If a company is running PostgreSQL `9.4.26`, does it need a major upgrade
to move to PostgreSQL `9.5`? What about moving from `9.5` to `9.5.10`?

Your answer: ___________________________________________________________

Reference answer: Yes, moving from `9.4` to `9.5` is a major upgrade and requires a
pg_upgrade or dump/restore process. Moving from `9.5` to `9.5.10` is a minor upgrade -
just replace the binaries and restart.

---

**Question 4:** What is the current latest major version of PostgreSQL as of 2024?

Your answer: ___________________________________________________________

Reference answer: PostgreSQL 17, released September 2024.

---

## Task 3 - Feature to Version Mapping

Match each feature to the version that first introduced it. Write the version number
in the blank. Use the concepts reading and your AI assistant.

```
Features to map:
  A. WAL (Write-Ahead Logging)
  B. Streaming replication
  C. Hot standby (read replicas)
  D. JSONB type
  E. Row-level security (RLS)
  F. Logical replication (built-in)
  G. Declarative table partitioning
  H. Window functions (ROW_NUMBER, RANK, etc.)
  I. UPSERT (INSERT ON CONFLICT DO ...)
  J. Parallel query execution
```

Fill in:

| Feature | Introduced In |
|---------|--------------|
| A. WAL  |              |
| B. Streaming replication |  |
| C. Hot standby |          |
| D. JSONB |               |
| E. Row-level security |   |
| F. Logical replication |  |
| G. Declarative partitioning | |
| H. Window functions |     |
| I. UPSERT |               |
| J. Parallel query |       |

**Answer key (check your work):**

| Feature | Introduced In |
|---------|--------------|
| A. WAL  | 7.1 (2001)   |
| B. Streaming replication | 9.0 (2010) |
| C. Hot standby | 9.0 (2010) |
| D. JSONB | 9.4 (2014)  |
| E. Row-level security | 9.5 (2016) |
| F. Logical replication | 10 (2017) |
| G. Declarative partitioning | 10 (2017) |
| H. Window functions | 8.4 (2009) |
| I. UPSERT | 9.5 (2016) |
| J. Parallel query | 9.6 (2016) |

---

## Task 4 - Build a Timeline Diagram

Without looking at your notes, draw a rough ASCII timeline covering the key milestones
from 1974 to 2024. Use the format below as a starting template.

```
1970s |
      |--[Your entry here]
      |
1980s |
      |--[Your entry here]
      |
1990s |
      |--[Your entry here]
      |
2000s |
      |--[Your entry here]
      |
2010s |
      |--[Your entry here]
      |
2020s |
      |--[Your entry here]
```

**Completed reference timeline:**

```
1970  |--E.F. Codd publishes relational model paper at IBM
      |
1974  |--INGRES project starts at UC Berkeley (Stonebraker)
      |
1982  |--Stonebraker leaves to commercialize INGRES
      |
1986  |--POSTGRES project starts at Berkeley
      |
1994  |--Postgres95: SQL replaces POSTQUEL (Yu, Chen)
      |
1996  |--PostgreSQL name adopted; community governance begins
1997  |--v6.0: first PostgreSQL release
      |
2001  |--v7.1: WAL introduced (crash safety)
2003  |--v7.4: serious performance improvements
2005  |--v8.0: Windows port, PITR, tablespaces
2009  |--v8.4: window functions, recursive CTEs
      |
2010  |--v9.0: streaming replication, hot standby
2014  |--v9.4: JSONB, replication slots, logical decoding
2016  |--v9.5: UPSERT, row-level security
2016  |--v9.6: parallel query execution
      |
2017  |--v10: new versioning, declarative partitioning, logical replication
2018  |--v11: JIT compilation, stored procedures with transactions
2019  |--v12: CTE optimization, generated columns
2022  |--v15: MERGE command
2023  |--v16: parallel pg_restore
2024  |--v17: pg_combinebackup, async I/O groundwork
```

---

## Task 5 - Reflection Questions

Answer these in your own words. There are no wrong answers - the goal is to connect the
history to real-world decisions you will make as a DBA.

**Question 1:** WAL was introduced in 2001 (v7.1). What does that tell you about the
risk of running PostgreSQL versions older than 7.1 in production?

Your answer: ___________________________________________________________

---

**Question 2:** Streaming replication arrived in 2010 (v9.0). Before that, how do you
think teams handled high availability for PostgreSQL databases?

Your answer: ___________________________________________________________

Hints to consider: Slony-I (trigger-based logical replication), Londiste, warm standby
using WAL archiving and continuous recovery (available from v8.x onward).

---

**Question 3:** A customer tells you they are running PostgreSQL 9.4 because "it's
stable and they have not had any problems." What concerns would you raise?

Your answer: ___________________________________________________________

Key points to cover:
- 9.4 reached end-of-life in February 2020 - no more security patches
- Missing 5+ years of features: RLS (9.5), logical replication (10), declarative
  partitioning (10), JIT (11), generated columns (12), MERGE (15)
- Upgrade paths: pg_upgrade from 9.4 to a modern version is supported but requires
  testing

---

## Checkpoint

Before moving on, you should be able to:

- [ ] Name the four phases of PostgreSQL's history (INGRES, POSTGRES, Postgres95, PostgreSQL)
- [ ] Explain the difference between pre-10 and post-10 version numbering
- [ ] Map WAL, streaming replication, JSONB, logical replication, and declarative
      partitioning to their release versions without looking
- [ ] Draw a rough timeline from 1986 to 2024 from memory

---

**Next:** [use/01-version-features-quiz.md](../use/01-version-features-quiz.md) - Test
your knowledge with a 15-question quiz on PostgreSQL history.
