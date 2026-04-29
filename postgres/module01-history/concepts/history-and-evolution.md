# History and Evolution of PostgreSQL

## Why This Module Matters

PostgreSQL did not appear out of thin air. It came from decades of academic research,
arguments about the right way to build a database, and a community that refused to let
a great piece of software die when it lost corporate backing. Understanding that history
tells you a lot about why PostgreSQL makes the choices it does today - and why it keeps
winning against databases with billion-dollar marketing budgets.

---

## The INGRES Years (1974-1985)

In 1973, a computer scientist named Michael Stonebraker at the University of California
Berkeley decided the relational model - described by E.F. Codd at IBM in 1970 - was worth
building. The result was INGRES (Interactive Graphics and Retrieval System), developed
from 1974 through the early 1980s.

INGRES was influential beyond its user base. It introduced:

- **QUEL** - a query language that predated SQL
- The concept of a rule system for rewriting queries
- Practical demonstrations that relational databases could actually work at scale

Stonebraker eventually left Berkeley to commercialize INGRES. The company became Ingres
Corporation (later part of Computer Associates, now Actian). But Stonebraker himself grew
frustrated with the limitations of the relational model - specifically, its inability to
handle complex data types and objects.

```
Timeline:
  1970  -- E.F. Codd publishes "A Relational Model of Data for Large Shared Data Banks"
  1973  -- Stonebraker starts INGRES project at UC Berkeley
  1977  -- INGRES becomes operational
  1982  -- Stonebraker leaves Berkeley to commercialize INGRES
  1985  -- Stonebraker returns to Berkeley with a new idea
```

---

## The POSTGRES Project (1986-1994)

Stonebraker came back to Berkeley with a bigger question: what if a database could store
not just flat rows of primitive data, but complex objects, user-defined types, and rules?

The answer was POSTGRES - "post-INGRES." Development ran from 1986 to 1994.

### What Made POSTGRES Different

POSTGRES introduced ideas that were genuinely radical at the time:

- **Object-relational model** - tables could store user-defined types, not just integers
  and strings. You could define a `point` type and store geometric data natively.
- **Extensibility** - users could add new data types, operators, and index types without
  modifying the database source code.
- **Rules system** - queries could be rewritten automatically based on defined rules.
- **Time travel** - early versions kept historical row versions, letting you query data
  as it existed at a previous point in time.

POSTGRES used a query language called POSTQUEL, which was derived from QUEL, not SQL.
SQL was an ANSI standard by then, but the Berkeley team was more interested in getting
the object-relational ideas right than in SQL compatibility.

```
POSTGRES data model (simplified):
  +---------------------------+
  | Regular Columns           |  -- integer, text, etc.
  | User-Defined Types        |  -- point, polygon, your own types
  | Inheritance               |  -- tables can inherit from parent tables
  | Rules                     |  -- automatic query rewriting
  +---------------------------+
  ^
  |-- None of this existed in commercial databases at the time
```

The POSTGRES project ended in 1994. Stonebraker moved on (he later won the Turing Award
in 2014). The source code was released publicly under a permissive license.

---

## Postgres95 - Adding SQL (1994-1995)

Two graduate students at Berkeley - Andrew Yu and Jolly Chen - took the POSTGRES source
code and replaced POSTQUEL with SQL. They called the result Postgres95.

This was a critical decision. SQL was already the lingua franca of relational databases.
Without SQL compatibility, POSTGRES would have remained a research curiosity. Adding SQL
made it usable by real application developers.

Postgres95 also cleaned up a lot of the original code, improved performance, and fixed
dozens of bugs. By the end of 1995, it was a real, usable database system.

---

## PostgreSQL - The Community Takes Over (1996 onward)

In 1996, a wider group of developers took over development and renamed the project
PostgreSQL - combining "Postgres" with "SQL" to make clear it now spoke standard SQL.

The first release under the new name was PostgreSQL 6.0 in January 1997.

From that point forward, there has been no single company in control of PostgreSQL.
Development happens through:

- **The PostgreSQL Global Development Group** - a volunteer organization with no employees
- **Committers** - developers who have earned the right to approve code changes
- **Mailing lists** - the primary channel for design discussions (pgsql-hackers is the main one)
- **Annual conferences** - PGConf, PGConf.EU, and regional events worldwide

Any company can contribute code. Companies like EDB, Crunchy Data, AWS, Google, and
Microsoft all have engineers who commit to PostgreSQL. But no single company has veto
power over the direction of the project.

---

## Major Version Milestones

### Version 7.x (2001-2003) - Growing Up

The 7.x series made PostgreSQL serious infrastructure:

- **7.1** (2001): Write-Ahead Logging (WAL) - the foundation of crash safety and
  replication. Before WAL, a crash could leave the database in a corrupted state.
- **7.3** (2002): Schemas - the ability to organize database objects into namespaces.
  Also introduced function overloading and proper information_schema support.
- **7.4** (2003): Bitmap index scans, significant query optimizer improvements, and
  much better performance. The release that made serious people take PostgreSQL seriously.

### Version 8.x (2005-2010) - Enterprise Ready

```
  8.0 (2005) ---- Windows native port, point-in-time recovery, tablespaces
  8.1 (2005) ---- Partitioning (table inheritance), two-phase commit
  8.2 (2006) ---- Online VACUUM FULL improvements, performance gains
  8.3 (2008) ---- HOT updates, full-text search built-in, ENUM types
  8.4 (2009) ---- Window functions, recursive CTEs, column-level permissions
```

Key milestones:
- **8.0**: Windows native port - no more Cygwin workarounds. Also added point-in-time
  recovery (PITR), letting you restore a database to any moment, not just a full backup.
- **8.3**: HOT (Heap Only Tuple) updates dramatically reduced table bloat for updates
  that did not change indexed columns. This was a huge performance win for OLTP workloads.
- **8.4**: Window functions (`ROW_NUMBER()`, `RANK()`, `LAG()`, `LEAD()`) arrived - a
  feature Oracle had for years that analysts rely on constantly.

### Version 9.x (2010-2016) - Replication and JSON

```
  9.0 (2010) ---- Streaming replication, hot standby
  9.1 (2011) ---- Synchronous replication, unlogged tables, pg_basebackup
  9.2 (2012) ---- Cascading replication, index-only scans, JSON type
  9.3 (2013) ---- Materialized views, writeable foreign tables, event triggers
  9.4 (2014) ---- JSONB, logical decoding, replication slots
  9.5 (2016) ---- UPSERT (INSERT ON CONFLICT), row-level security, BRIN indexes
  9.6 (2016) ---- Parallel query execution
```

The 9.x era was transformational:

- **9.0**: Built-in streaming replication arrived. Before this, you needed third-party
  tools like Slony-I or Londiste to replicate. Hot standby meant you could query a
  replica while it was receiving changes from the primary.
- **9.4**: JSONB (binary JSON) was the feature that killed the argument for using MongoDB
  for simple document storage. JSONB stores JSON efficiently and supports GIN indexes
  on any JSON key or value.
- **9.5**: Row-level security (RLS) let you define policies that restrict which rows a
  user can see, directly in the database - no application code required.

### Version 10+ (2017 onward) - Modern Era

PostgreSQL dropped the major.minor.patch numbering in version 10. Before version 10,
the major version was the first two numbers: `9.6` was a major version, `9.6.5` was a
minor (bug fix) release. From version 10 onward, the first number alone is the major
version: `10`, `11`, `12` and so on.

```
Before v10 numbering:   9.6.0  -> 9.6.1  -> 9.6.5  (minor = bug fixes)
After v10 numbering:    10.0   -> 10.1   -> 10.5   (minor = bug fixes)
                        10     -> 11     -> 12      (major = new features)
```

```
  10  (2017) ---- Logical replication, declarative partitioning, quorum commit
  11  (2018) ---- JIT compilation, stored procedures with transactions
  12  (2019) ---- CTE optimization, generated columns, partitioned indexes
  13  (2020) ---- Parallel vacuum, incremental sort, deduplication in B-tree indexes
  14  (2021) ---- Multirange types, JSON subscripting, pipeline mode
  15  (2022) ---- MERGE command, pg_walinspect, improved logical replication
  16  (2023) ---- Parallel pg_restore, more logical replication controls
  17  (2024) ---- MERGE improvements, pg_combinebackup, async I/O groundwork
```

Key recent milestones:

- **10**: Logical replication finally built-in - subscribe to specific tables from another
  PostgreSQL instance. Also introduced declarative partitioning (much cleaner than the old
  inheritance-based approach).
- **11**: JIT (Just-In-Time) compilation can speed up complex analytical queries by
  compiling row evaluation code at runtime instead of interpreting it.
- **14**: JSON subscripting - `data['key']` syntax instead of always needing `->` and
  `->>`operators. Small thing, but developers love it.
- **15**: The `MERGE` statement - finally. Update, insert, or delete in one statement
  based on whether a source row matches a target row.

---

## The Community Model

PostgreSQL is governed by the **PostgreSQL Global Development Group**. There is no CEO,
no board of investors, and no company that can acquire it or change its license.

### How Decisions Get Made

1. **Someone proposes a feature** on the pgsql-hackers mailing list with a patch.
2. **Other developers review it** - often for months. Reviews are thorough and sometimes
   brutal. The bar for correctness and performance is high.
3. **A committer approves it** during the annual commit fest window.
4. **It lands in the next major release** (one per year, typically in the fall).

### The Annual Release Cycle

- Features are committed during the year
- A feature freeze happens around April
- Beta releases run from May through September
- The final release ships in September or October
- Each major version is supported for 5 years

### Who Contributes?

A 2023 analysis of commit credits showed contributions from engineers at:
EDB, Microsoft, AWS, Google, Crunchy Data, Fujitsu, NTT, Huawei, Supabase, and hundreds
of independent contributors. No single organization dominates commit counts.

---

## PostgreSQL vs Commercial Databases

### Licensing

| Database      | License         | Cost                              |
|---------------|-----------------|-----------------------------------|
| PostgreSQL    | PostgreSQL License (MIT-like) | Free forever, any use  |
| Oracle DB     | Proprietary     | $47,500+ per processor core       |
| SQL Server    | Proprietary     | $3,700+ per core (Standard)       |
| MySQL         | GPL / Commercial| Free (GPL) or paid (commercial)   |

The PostgreSQL License allows you to use, modify, and distribute PostgreSQL for any
purpose, including commercial products, without paying anyone. You cannot be locked out,
and the license cannot be revoked.

### Capabilities

| Feature                  | PostgreSQL   | Oracle       | SQL Server   |
|--------------------------|--------------|--------------|--------------|
| ACID compliance          | Yes          | Yes          | Yes          |
| Window functions         | Yes          | Yes          | Yes          |
| JSON/JSONB support       | Best in class| Limited      | Good (17+)   |
| Logical replication      | Built-in     | Paid add-on  | Built-in     |
| Row-level security       | Built-in     | Built-in     | Built-in     |
| Partitioning             | Declarative  | Yes          | Yes          |
| Extensibility            | Best in class| Limited      | Limited      |
| Full-text search         | Built-in     | Paid option  | Built-in     |
| Geospatial (PostGIS)     | Yes          | Paid option  | Limited      |
| Linux support            | First-class  | Yes          | Yes (2016+)  |

### The Extension Ecosystem

PostgreSQL's extensibility is a genuine differentiator. Extensions can add entirely new
data types, index types, and operators at the C level - not just stored procedures.

Notable extensions that other databases cannot match:
- **PostGIS** - full geospatial database capabilities
- **TimescaleDB** - turns PostgreSQL into a time-series database
- **pg_partman** - automatic partition management
- **pgvector** - vector similarity search for AI/ML workloads
- **Citus** - horizontal sharding across multiple nodes

### Why PostgreSQL Is Growing Fastest

The Stack Overflow Developer Survey has ranked PostgreSQL as the most wanted and most
used database among professional developers for several consecutive years (2022-2024),
overtaking MySQL.

Reasons for the growth:

1. **No licensing surprises** - companies know their cost model will not change overnight.
   Oracle's audit teams are legendary for triggering seven-figure invoices.
2. **Cloud availability** - every major cloud provider offers managed PostgreSQL: AWS RDS
   and Aurora, Google Cloud SQL and AlloyDB, Azure Database for PostgreSQL.
3. **JSONB changed the calculus** - teams that would have reached for MongoDB now stay on
   PostgreSQL and use JSONB for semi-structured data.
4. **Reliability record** - PostgreSQL has a near-zero critical bug history compared to
   commercial alternatives. The review process is slow because it is thorough.
5. **Supabase, Neon, and new cloud-native players** - startups are building entire
   platforms on top of PostgreSQL, expanding its reach to audiences that never would have
   deployed it manually.

---

## The Bottom Line

PostgreSQL started as an academic project, survived because graduate students added SQL
support, and thrived because a global community took it seriously when no company would.

It is now used by companies managing petabytes of data. It powers Spotify, Instagram
(at least in its early years), Notion, GitHub, and thousands of other production systems.

The features you will use in this course - WAL, streaming replication, JSONB, logical
replication, partitioning - each took years of careful engineering by people who cared
more about correctness than ship dates.

That history matters when you are the DBA at 2 AM deciding whether to trust your database
with a critical recovery.

---

## Key Facts to Remember

- **1986**: POSTGRES project starts at UC Berkeley (Stonebraker)
- **1994**: Postgres95 adds SQL support (Yu and Chen)
- **1996**: PostgreSQL name adopted, open community takes over
- **2001**: WAL introduced in 7.1 - the foundation of crash safety
- **2010**: Streaming replication in 9.0 - built-in HA becomes possible
- **2014**: JSONB in 9.4 - the document database argument ended
- **2017**: Version 10 - new numbering, logical replication built-in
- **License**: PostgreSQL License - free for any use, no exceptions
- **Release cadence**: One major version per year, 5 years of support per version
