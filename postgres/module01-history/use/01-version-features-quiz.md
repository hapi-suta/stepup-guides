# Use Exercise 01 - PostgreSQL History Quiz

Test your knowledge of PostgreSQL's evolution, versioning, and community model.

**Mode:** AI Lab (no server needed)
**Time:** 20 minutes

---

## Instructions

Answer all 15 questions before checking the answer key at the bottom. Cover the answers
with a piece of paper or scroll past the horizontal rule at the end when you are done.

Write your answers in the blanks or circle your choice.

---

## Section A - Multiple Choice (10 questions)

**Question 1**

Who started the POSTGRES project at UC Berkeley, and in what year?

A) Larry Ellison, 1980
B) Michael Stonebraker, 1986
C) Michael Stonebraker, 1974
D) Jolly Chen, 1994

Your answer: _______

---

**Question 2**

What was the query language used by POSTGRES before SQL was added?

A) PL/pgSQL
B) QUEL
C) POSTQUEL
D) HQL

Your answer: _______

---

**Question 3**

Who added SQL support to POSTGRES, creating Postgres95?

A) Michael Stonebraker and Bruce Momjian
B) Larry Ellison and Bill Gates
C) Andrew Yu and Jolly Chen
D) Tom Lane and Alvaro Herrera

Your answer: _______

---

**Question 4**

What was the first official release under the PostgreSQL name?

A) PostgreSQL 1.0 (1995)
B) PostgreSQL 6.0 (1997)
C) PostgreSQL 7.0 (2000)
D) PostgreSQL 5.0 (1996)

Your answer: _______

---

**Question 5**

Which version introduced WAL (Write-Ahead Logging)?

A) 6.0
B) 7.1
C) 8.0
D) 9.0

Your answer: _______

---

**Question 6**

Which version first added streaming replication and hot standby?

A) 8.4
B) 9.0
C) 9.1
D) 9.3

Your answer: _______

---

**Question 7**

Under the OLD versioning scheme (before version 10), which of the following was a MAJOR
version upgrade requiring pg_upgrade or dump/restore?

A) PostgreSQL 9.6.1 to 9.6.5
B) PostgreSQL 9.5 to 9.5.10
C) PostgreSQL 9.5 to 9.6
D) PostgreSQL 9.6.22 to 9.6.24

Your answer: _______

---

**Question 8**

Which version introduced JSONB (binary JSON with indexing support)?

A) 9.2
B) 9.3
C) 9.4
D) 10

Your answer: _______

---

**Question 9**

Which version changed the versioning scheme so that the major version is a single number?

A) 9.6
B) 10
C) 11
D) 12

Your answer: _______

---

**Question 10**

Which version first included built-in logical replication and declarative table
partitioning?

A) 9.6
B) 10
C) 11
D) 12

Your answer: _______

---

## Section B - Match Features to Versions (3 questions)

**Question 11**

Draw a line (or write the letter) connecting each feature to the version that introduced it.

```
Features                          Versions
---------                         --------
A. Window functions               1. 7.1
B. UPSERT (INSERT ON CONFLICT)    2. 8.4
C. WAL                            3. 9.5
```

Your answer:
A - ___
B - ___
C - ___

---

**Question 12**

Match each feature to the correct version.

```
Features                          Versions
---------                         --------
A. Parallel query execution       1. 9.0
B. Streaming replication          2. 9.6
C. Row-level security             3. 9.5
```

Your answer:
A - ___
B - ___
C - ___

---

**Question 13**

Match each feature to the correct version.

```
Features                          Versions
---------                         --------
A. MERGE statement                1. 11
B. JIT compilation                2. 15
C. Logical replication (built-in) 3. 10
```

Your answer:
A - ___
B - ___
C - ___

---

## Section C - True or False (5 questions)

Write T (true) or F (false).

**Question 14**

"The PostgreSQL Global Development Group is a subsidiary of EDB (EnterpriseDB) and EDB
controls which features get added to each release."

Your answer: _______

---

**Question 15**

"PostgreSQL is released under a permissive license that allows use in commercial
products without paying a licensing fee."

Your answer: _______

---

**Question 16**

"In the old versioning scheme, moving from PostgreSQL 9.4 to 9.4.5 required a
dump/restore or pg_upgrade."

Your answer: _______

---

**Question 17**

"Each major version of PostgreSQL is supported for exactly 5 years after its first
release."

Your answer: _______

---

**Question 18**

"Before streaming replication was added in version 9.0, there was no way to have a
standby server for PostgreSQL."

Your answer: _______

---

## Bonus Question

**Question 19**

PostgreSQL's extensibility lets users add new data types, index types, and operators
without modifying the database source code. Name two PostgreSQL extensions and describe
what capability each one adds.

Extension 1: _______________________________________
What it adds: _______________________________________

Extension 2: _______________________________________
What it adds: _______________________________________

---
---
---

# Answer Key

(Do not look until you have answered all questions.)

---

## Section A Answers

| Question | Answer | Explanation |
|----------|--------|-------------|
| 1 | B | Michael Stonebraker started POSTGRES in 1986. He had earlier commercialized INGRES (1974), but POSTGRES was a new project back at Berkeley. |
| 2 | C | POSTGRES used POSTQUEL, derived from QUEL (the INGRES query language). SQL was added by Postgres95. |
| 3 | C | Andrew Yu and Jolly Chen were the graduate students who replaced POSTQUEL with SQL in 1994-1995. |
| 4 | B | PostgreSQL 6.0 was released in January 1997, the first release under the PostgreSQL name. |
| 5 | B | WAL was introduced in version 7.1 (2001). Before WAL, a crash could corrupt the database. |
| 6 | B | Version 9.0 (2010) added both streaming replication and hot standby in the same release. |
| 7 | C | Moving from 9.5 to 9.6 is a major upgrade (different first two numbers in old scheme). The others are minor (bug fix) releases. |
| 8 | C | JSONB arrived in version 9.4 (2014). Version 9.2 had a basic JSON type, but JSONB is binary, compressed, and indexable. |
| 9 | B | Version 10 (2017) switched to single-number major versioning. |
| 10 | B | Version 10 introduced both built-in logical replication and the declarative `PARTITION BY` syntax. |

---

## Section B Answers

**Question 11:**

| Feature | Version |
|---------|---------|
| A. Window functions | 2 (8.4, released 2009) |
| B. UPSERT | 3 (9.5, released 2016) |
| C. WAL | 1 (7.1, released 2001) |

**Question 12:**

| Feature | Version |
|---------|---------|
| A. Parallel query execution | 2 (9.6, released 2016) |
| B. Streaming replication | 1 (9.0, released 2010) |
| C. Row-level security | 3 (9.5, released 2016) |

**Question 13:**

| Feature | Version |
|---------|---------|
| A. MERGE statement | 2 (15, released 2022) |
| B. JIT compilation | 1 (11, released 2018) |
| C. Logical replication (built-in) | 3 (10, released 2017) |

---

## Section C Answers

| Question | Answer | Explanation |
|----------|--------|-------------|
| 14 | F | The PostgreSQL Global Development Group is an independent volunteer organization. No single company controls it. EDB contributes engineers, but so do Amazon, Google, Microsoft, Fujitsu, and hundreds of others. |
| 15 | T | The PostgreSQL License is a permissive open source license similar to MIT. It allows use in any product, commercial or otherwise, without a fee. |
| 16 | F | Moving from 9.4 to 9.4.5 is a minor (bug fix) upgrade. Only binary replacement and restart are needed. Dump/restore is required for major upgrades (e.g., 9.4 to 9.5). |
| 17 | T | Each major PostgreSQL version receives bug fix and security updates for 5 years from its first release date. |
| 18 | F | Before v9.0, teams used WAL archiving with continuous recovery (warm standby, available since v8.x) and third-party tools like Slony-I and Londiste. Streaming replication made it dramatically easier but was not the only option. |

---

## Bonus Answer

There is no single correct answer. Strong responses might include:

- **PostGIS** - adds full geospatial data types (points, polygons, lines), spatial
  indexes, and hundreds of geospatial functions. Turns PostgreSQL into a full GIS database.
- **pgvector** - adds a vector data type and similarity search operators. Used for AI/ML
  workloads where you need to find the nearest embedding vectors to a query vector.
- **TimescaleDB** - optimizes PostgreSQL for time-series data with automatic chunking,
  compression, and continuous aggregates.
- **pg_partman** - automates the creation and maintenance of time-based and serial
  partitions so you do not have to manage partition tables manually.
- **pgstattuple** - provides functions to measure actual bloat (dead space) inside
  tables and indexes at the page level.
- **pg_stat_statements** - tracks execution statistics for every query type. Essential
  for performance troubleshooting.

---

## Scoring

| Score | Rating |
|-------|--------|
| 18-19 correct | Excellent - ready for the next module |
| 14-17 correct | Good - review the areas you missed in the concepts reading |
| 10-13 correct | Fair - re-read the concepts doc and redo the build guide |
| Below 10 | Re-read the concepts doc before moving forward |
