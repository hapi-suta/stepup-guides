# Use Exercise 02 - Database Comparison Research

Compare PostgreSQL against Oracle, MySQL, and SQL Server across licensing, features,
replication, and ecosystem. This is a research exercise - use your AI assistant, the
concepts reading, and public documentation.

**Mode:** AI Lab (no server needed)
**Time:** 25 minutes

---

## Overview

You will never work in a vacuum as a DBA. Clients and employers will ask you to justify
why you chose PostgreSQL, or whether they should migrate from Oracle, or how PostgreSQL
stacks up against MySQL. This exercise builds that knowledge.

By the end you will be able to speak clearly about:
- What each database costs and under what license it runs
- Where PostgreSQL leads, where it follows, and where it is roughly equal
- How replication and HA options differ across platforms
- Which database to recommend for which workload

---

## Task 1 - Licensing Model Research

Fill in the table below. For each database, document the license type, typical cost
for a production server, and any key restrictions.

Use these sources:
- PostgreSQL: postgresql.org/about/licence
- Oracle: oracle.com/database/technologies/licensing
- MySQL: dev.mysql.com/doc/refman/8.0/en/mysql-licenses.html
- SQL Server: microsoft.com/en-us/sql-server/sql-server-2022-comparison

| Database      | License Type     | Approximate Cost (per production server) | Key Restrictions |
|---------------|------------------|------------------------------------------|------------------|
| PostgreSQL    |                  |                                          |                  |
| Oracle DB EE  |                  |                                          |                  |
| MySQL CE      |                  |                                          |                  |
| MySQL EE      |                  |                                          |                  |
| SQL Server SE |                  |                                          |                  |
| SQL Server EE |                  |                                          |                  |

**Completed reference table:**

| Database      | License Type     | Approximate Cost | Key Restrictions |
|---------------|------------------|------------------|------------------|
| PostgreSQL    | PostgreSQL License (permissive, MIT-like) | Free | None. Can use in any product commercially. |
| Oracle DB EE  | Proprietary      | ~$47,500 per processor (named user plus also available) | Strict audit rights. Oracle can audit your environment. |
| MySQL CE      | GPL v2           | Free             | GPL copyleft: if you distribute software using MySQL CE, your software may need to be open source. |
| MySQL EE      | Commercial       | ~$5,000/year per server | Requires commercial license for proprietary products. |
| SQL Server SE | Proprietary      | ~$3,700 per core (perpetual) or $1,586/core/year | Limited to 24 cores, 128 GB RAM per instance. |
| SQL Server EE | Proprietary      | ~$13,748 per core (perpetual) | Full features, no hardware limits. |

---

## Task 2 - Feature Comparison

For each cell, write a brief description (5-15 words). Mark with:
- `Native` - built into the core database with no add-ons needed
- `Extension` - available via an official or well-supported extension
- `Paid add-on` - requires purchasing a separate product or higher edition
- `Limited` - the feature exists but with significant restrictions
- `No` - not available

| Feature                    | PostgreSQL | Oracle DB | MySQL 8 | SQL Server |
|----------------------------|------------|-----------|---------|------------|
| ACID compliance            |            |           |         |            |
| Window functions           |            |           |         |            |
| Recursive CTEs             |            |           |         |            |
| JSONB / binary JSON        |            |           |         |            |
| Full-text search           |            |           |         |            |
| Geospatial support         |            |           |         |            |
| Row-level security         |            |           |         |            |
| Table partitioning         |            |           |         |            |
| User-defined types         |            |           |         |            |
| Foreign data wrappers      |            |           |         |            |
| Vector similarity search   |            |           |         |            |

**Completed reference table:**

| Feature                    | PostgreSQL | Oracle DB | MySQL 8 | SQL Server |
|----------------------------|------------|-----------|---------|------------|
| ACID compliance            | Native | Native | Native (InnoDB) | Native |
| Window functions           | Native (8.4) | Native | Native (8.0) | Native |
| Recursive CTEs             | Native (8.4) | Native | Native (8.0) | Native |
| JSONB / binary JSON        | Native (9.4) - best in class | Limited (JSON in 21c) | Limited (JSON type 8.0) | Native (JSON support 2016+) |
| Full-text search           | Native | Paid (Oracle Text) | Native (limited) | Native |
| Geospatial support         | Extension (PostGIS) - best in class | Paid (Oracle Spatial) | Native (limited) | Native (limited) |
| Row-level security         | Native (9.5) | Native (VPD/FGAC) | No | Native |
| Table partitioning         | Native declarative (10) | Native | Native | Native |
| User-defined types         | Native - extensible type system | Native | Limited | Limited (CLR types) |
| Foreign data wrappers      | Native (postgres_fdw + many others) | Limited | No | Limited (Linked Servers) |
| Vector similarity search   | Extension (pgvector) | Paid (AI Vector Search, 23ai) | No | No |

---

## Task 3 - Replication and High Availability

Fill in the table. For each database/method combination, describe what it provides and
whether it is built-in or requires additional products.

| Replication Type           | PostgreSQL | Oracle DB | MySQL | SQL Server |
|----------------------------|------------|-----------|-------|------------|
| Physical streaming replication |        |           |       |            |
| Logical replication        |            |           |       |            |
| Synchronous replication    |            |           |       |            |
| Multi-master               |            |           |       |            |
| Cloud-managed HA           |            |           |       |            |

**Completed reference table:**

| Replication Type           | PostgreSQL | Oracle DB | MySQL | SQL Server |
|----------------------------|------------|-----------|-------|------------|
| Physical streaming replication | Native (v9.0+). Binary, block-level. Standby is exact copy. | Oracle Data Guard (paid add-on). Very mature. | Not applicable - MySQL uses binlog-based replication. | Always On Availability Groups. Requires Enterprise edition. |
| Logical replication        | Native (v10+). Table-level, subscribe to specific tables. | Oracle GoldenGate (very expensive paid product). | Native binlog-based replication (similar concept). | Transactional replication - built-in but complex. |
| Synchronous replication    | Native (`synchronous_standby_names`). Can require commit confirmation from one or more standbys. | Available via Data Guard (paid). | Semi-synchronous (plugin required). | Available in Always On (Enterprise). |
| Multi-master               | Not natively supported. BDR (Bi-Directional Replication) is a paid EDB product. | Oracle RAC (Real Application Clusters) - very expensive. | InnoDB Cluster / Group Replication - built-in but complex to manage. | No native multi-master. Peer-to-peer transactional replication is limited. |
| Cloud-managed HA           | AWS RDS Multi-AZ, Aurora, Google Cloud SQL, Azure Database, Neon, Supabase | Oracle Exadata Cloud, Oracle RAC on OCI | AWS RDS MySQL, Google Cloud SQL, Azure MySQL | AWS RDS SQL Server, Azure SQL Managed Instance |

---

## Task 4 - JSON Support Deep Dive

JSON support is a major differentiating factor. Research and fill in this detailed
comparison.

| JSON Capability            | PostgreSQL | Oracle (23ai) | MySQL 8 | SQL Server (2016+) |
|----------------------------|------------|---------------|---------|-------------------|
| Native JSON type           |            |               |         |                   |
| Binary JSON storage (JSONB)|            |               |         |                   |
| GIN index on JSON keys     |            |               |         |                   |
| JSON path querying         |            |               |         |                   |
| JSON aggregation functions |            |               |         |                   |
| Subscript syntax (data['key']) |        |               |         |                   |

**Completed reference table:**

| JSON Capability            | PostgreSQL | Oracle (23ai) | MySQL 8 | SQL Server (2016+) |
|----------------------------|------------|---------------|---------|-------------------|
| Native JSON type           | Yes - both `json` and `jsonb` | Yes (`JSON` type in 21c+) | Yes | Yes (stored as string internally) |
| Binary JSON storage (JSONB)| Yes - compressed, deduplicated, indexable | Yes (23ai) | No - JSON is text with validation | No |
| GIN index on JSON keys     | Yes - index any key or value | Yes (JSON Search Index) | Yes (functional index workaround) | Yes (computed column workaround) |
| JSON path querying         | Yes - `jsonb_path_query()`, SQL/JSON standard | Yes | Yes (`JSON_TABLE`, `JSON_VALUE`) | Yes (`JSON_VALUE`, `OPENJSON`) |
| JSON aggregation functions | Yes - `json_agg()`, `jsonb_build_object()`, etc. | Yes | Yes | Yes |
| Subscript syntax (data['key']) | Yes (v14+) | Yes | Limited | No |

---

## Task 5 - Choose the Right Database

For each scenario below, recommend a database and justify your choice in 2-4 sentences.
There are no strictly wrong answers, but your reasoning should be sound.

**Scenario 1:**

A startup with no budget is building a SaaS application. They need JSON document storage,
full-text search, and the ability to scale to millions of users. They will host on AWS.

Your recommendation: _______________________________________________________

Your reasoning: ____________________________________________________________

---

**Scenario 2:**

A large bank runs Oracle Database 19c for its core transaction processing. The DBA team
wants to evaluate whether they could migrate to PostgreSQL. The workload has 500,000
transactions per day, uses stored procedures heavily, and requires 99.99% uptime.

Your recommendation: _______________________________________________________

Your reasoning: ____________________________________________________________

---

**Scenario 3:**

A mid-size company runs SQL Server 2016 and wants to modernize. They have a .NET
application, extensive use of T-SQL stored procedures, and their team knows SQL Server
Administration well. Budget is not a major concern.

Your recommendation: _______________________________________________________

Your reasoning: ____________________________________________________________

---

**Scenario 4:**

A data science team needs to store and query embedding vectors from a machine learning
model (text embeddings, ~1,536 dimensions). They already run PostgreSQL 15 for their
application database.

Your recommendation: _______________________________________________________

Your reasoning: ____________________________________________________________

---

**Reference reasoning (compare your answers):**

**Scenario 1:** PostgreSQL is the obvious choice. It handles JSON natively with JSONB
(indexable, binary), has built-in full-text search, runs on AWS RDS and Aurora, and costs
nothing to license. Supabase or Neon are strong managed options for startups.

**Scenario 2:** This is a migration risk analysis. PostgreSQL can handle the transaction
volume, and stored procedures translate to PL/pgSQL. High availability is achievable with
streaming replication and tools like Patroni. However, the migration itself is not trivial
- Oracle-specific SQL syntax, Oracle-specific stored procedure features, and licensing
compliance during migration all need careful planning. A phased migration over 12-24
months is realistic. Pure PostgreSQL for new services first, then migrate existing ones.

**Scenario 3:** Given the team expertise and lack of budget pressure, staying on SQL
Server or upgrading to SQL Server 2022 is defensible. If there is any desire to reduce
licensing costs or move to Linux hosting, PostgreSQL is a strong migration target - T-SQL
and PL/pgSQL are different but similar enough that experienced developers can bridge the
gap. The migration tooling (pgloader, AWS SCT) has improved significantly.

**Scenario 4:** Add the `pgvector` extension to the existing PostgreSQL 15 instance.
pgvector adds a `vector` data type, IVFFlat and HNSW indexes for approximate nearest
neighbor search, and cosine/dot product/L2 distance operators. Keeping everything in one
database avoids a separate vector store service and lets you JOIN embedding results
against your application data.

---

## Task 6 - Summary Table

Fill in this executive summary table. Aim for a single phrase per cell - the kind of
answer you would give in a 10-minute meeting.

| Question | PostgreSQL | Oracle | MySQL | SQL Server |
|----------|------------|--------|-------|------------|
| Licensing cost | | | | |
| Best for OLTP? | | | | |
| Best for analytics? | | | | |
| Best JSON support? | | | | |
| Easiest HA setup? | | | | |
| Largest cloud ecosystem? | | | | |
| Open source? | | | | |

**Reference summary:**

| Question | PostgreSQL | Oracle | MySQL | SQL Server |
|----------|------------|--------|-------|------------|
| Licensing cost | Free | Very expensive | Free (CE) / Paid (EE) | Moderate to expensive |
| Best for OLTP? | Excellent | Excellent | Good | Excellent |
| Best for analytics? | Good (parallel query, partitioning) | Excellent | Limited | Excellent |
| Best JSON support? | Best in class (JSONB) | Good (23ai) | Limited | Good (2016+) |
| Easiest HA setup? | Good (Patroni + streaming replication) | Hard (Data Guard complexity) | Moderate (Group Replication) | Good (Always On with GUI) |
| Largest cloud ecosystem? | PostgreSQL - available on all clouds natively | Oracle Cloud only (OCI) | Wide - AWS, GCP, Azure | Wide - mainly Azure, also AWS/GCP |
| Open source? | Yes | No | Yes (CE) | No |

---

## Checkpoint

Before moving on, you should be able to:

- [ ] Explain the PostgreSQL license and why it matters for commercial use
- [ ] Name two areas where PostgreSQL leads Oracle or SQL Server
- [ ] Name one area where Oracle still has an advantage over PostgreSQL
- [ ] Describe when you would recommend PostgreSQL vs MySQL for a new project
- [ ] Explain what pgvector adds and when you would use it

---

**Module Complete.** You have finished the module01-history content. Proceed to
**Module 02 - PostgreSQL Architecture** to start working with live servers.
