# Concepts 3.5: Data Engineering for AI

**Tier 3 - Data analysis and data engineering.** Teaching reference. Data engineering is the plumbing that gets data from where it is born to where a model can use it, reliably and on schedule. Analysis answers a question once; engineering answers it every night, automatically, forever. As an AI consultant you design these pipelines and explain the trade-offs to clients who are choosing where to spend money.

**Who this is for:** DBAs. You already run backups on a schedule, replicate data between servers, and think about consistency. Data engineering is that mindset applied to moving and shaping data for analytics and AI.

This is a concepts doc - vocabulary and trade-offs, with a few runnable checks. You build the real pipeline in BUILD Project 3.

---

## 1. What a data pipeline is

A **pipeline** is an automated sequence of steps that moves and transforms data: ingest it from a source, store it, clean and validate it, load the result somewhere useful, and do it on a repeating schedule without a human. Every step can fail, so a real pipeline also tracks failures and can be re-run safely.

The mental model: a pipeline is a factory line. Raw material comes in one end (an API, a CSV, a database), passes through stations that add value (clean, validate, join, aggregate), and a finished product comes out the other (a curated table a model or dashboard reads).

---

## 2. ETL vs ELT

Two orderings of the same three steps. This is the single most common data-engineering interview question.

- **ETL - Extract, Transform, Load.** Pull data out, transform it on a separate machine, then load the clean result into the warehouse. Older pattern. Good when the destination is expensive or limited and you want only clean data landing there.
- **ELT - Extract, Load, Transform.** Pull data out, load it raw into the warehouse first, then transform it inside the warehouse using its compute. Modern default. Good when your warehouse is cheap and powerful (BigQuery, Snowflake, Redshift) - let it do the heavy lifting, and keep the raw data so you can re-transform later.

The trade-off in one line: ETL transforms before storing (clean data only, but you lose the raw); ELT stores raw then transforms (you keep everything and can redo transforms, at the cost of storing raw data). Modern AI work leans ELT because keeping raw data lets you re-derive features when the model's needs change.

You will build an ETL-shaped pipeline in Project 3 (transform before the final load into a curated schema) but keep the raw landing zone - a pragmatic hybrid that is common in practice.

---

## 3. Batch vs streaming

- **Batch** - process data in chunks on a schedule (every night, every hour). Simple, cheap, easy to reason about and re-run. Right for reports, model training data, and anything where "a few hours old" is fine.
- **Streaming** - process each record the moment it arrives, continuously. Complex and more expensive, but right for fraud detection, live dashboards, and anything where minutes matter.

The consultant's rule: **default to batch.** Most clients ask for streaming and need batch. Streaming triples the complexity and cost; only reach for it when the business truly cannot wait. Project 3 is a batch pipeline on a cron schedule, which is what the vast majority of real pipelines are.

---

## 4. Lakes, warehouses, and lakehouses

Three ways to store data at scale, and clients constantly confuse them.

- **Data warehouse** - structured, schema-on-write, optimized for SQL analytics. You define the tables up front; only clean, structured data goes in. Think PostgreSQL scaled up, or Snowflake/BigQuery/Redshift. Fast queries, strong governance, more rigid.
- **Data lake** - raw storage for anything: files, logs, images, JSON, in cheap object storage (S3). Schema-on-read - you impose structure only when you query. Flexible and cheap, but easily becomes a "data swamp" of undocumented junk nobody trusts.
- **Data lakehouse** - a newer hybrid that puts warehouse-style structure, transactions, and governance on top of lake-style cheap storage (Delta Lake, Iceberg). The goal: lake flexibility and cost with warehouse reliability. Increasingly the default recommendation.

For AI specifically, you often want a lake or lakehouse: models eat unstructured data (text, images) that a rigid warehouse handles poorly, and you want to keep raw data to re-derive features.

---

## 5. Lineage and metadata

- **Data lineage** is the documented map of where data came from and everywhere it flows: this curated table was built from that raw file, which came from that API, and these three dashboards depend on it. Lineage answers "if this source breaks, what downstream reports go wrong?" and "where did this suspicious number come from?"
- **Metadata** is data about your data: schemas, owners, descriptions, last-updated times, row counts, quality scores. It is what makes a dataset findable and trustworthy instead of a mystery file.
- **A data catalog** is the searchable inventory of all your datasets and their metadata - the "card catalog" for a company's data. Tools: DataHub, Amundsen, Unity Catalog, Glue Data Catalog.

Auditors, regulators, and clients all care about lineage because it answers "can you prove where this number came from?" A model that decides who gets a loan must be traceable back to its training data. In Project 3 you record simple lineage (source, timestamp, row counts, run id) so every curated row can be traced to its origin.

---

## 6. Schema evolution

Sources change. A team renames `user_name` to `full_name`, adds a `phone` column, or changes a type from int to string. **Schema evolution** is handling those changes without the pipeline silently breaking or silently dropping data.

Three strategies, from worst to best:

- **Break loudly** - the pipeline hard-fails on any unexpected schema and refuses to load bad data. Safe but brittle; every upstream change pages you.
- **Ignore silently** - the pipeline only reads the columns it knows and ignores the rest. This is the dangerous default: a renamed column becomes all-null and nobody notices until the model degrades.
- **Detect and adapt** - the pipeline compares each batch's schema to the expected contract (Concepts 3.4), alerts on differences, and has a defined policy: new optional columns are allowed and backfilled as null; renamed or dropped required columns fail loudly with the field name.

The right answer is detect-and-adapt driven by a data contract. You live this in SURVIVE: schema-evolution - a source renames a column, you detect it, adapt the loader, and backfill the historical rows.

---

## 7. Change data capture (CDC)

**CDC** is capturing only what changed in a source since last time - new, updated, and deleted rows - instead of copying the whole table every run. It is how you keep a warehouse in sync efficiently.

Two common ways:

- **Timestamp/high-watermark** - each row has an `updated_at`; you pull only rows newer than the last run's max timestamp. Simple, works everywhere, misses hard deletes.
- **Log-based** - read the database's own write-ahead log (the same WAL you know from PostgreSQL replication) to get every change including deletes. This is what tools like Debezium do. More powerful, more setup.

CDC matters because full-table reloads do not scale: reloading a billion-row table every night is wasteful and slow. The DBA connection is direct - CDC log-based replication is literally reading the WAL, the mechanism behind streaming replication you already know.

---

## 8. Orchestration

An **orchestrator** runs your pipeline steps in the right order, on schedule, with retries, dependencies, and visibility. Step B waits for step A; if A fails, B does not run; a failed step retries three times then alerts.

- **cron** - the simplest orchestrator, built into every Linux box. Runs a command on a schedule. No dependencies, no retries, no UI. Perfect for a single small pipeline, which is what you use in Project 3.
- **Airflow / Dagster / Prefect** - real orchestrators for many interdependent pipelines. They model the pipeline as a DAG (directed acyclic graph - steps with dependencies), give you a UI, retries, alerting, and backfills.

The consultant's rule mirrors batch-vs-streaming: **start with cron.** A client with three nightly jobs does not need Airflow's operational weight. Reach for a real orchestrator when you have dozens of interdependent pipelines and need the visibility. Project 3 uses cron on purpose - master the fundamentals before the framework.

---

## 9. Anonymization and masking

Before data can be used for AI - especially before it leaves the client's control or trains a model - personal and sensitive information must be protected. This is often a legal requirement (GDPR, HIPAA, CCPA), not a nicety.

Techniques, from weakest to strongest:

- **Masking** - hide part of a value: `****-****-****-1234` for a card number. The real value still exists underneath; this is display-level protection.
- **Pseudonymization** - replace an identifier with a consistent token (`user_42` for a real name), so you can still join and count per-user without knowing who they are. Reversible if you keep the mapping.
- **Hashing** - one-way transform of an identifier (SHA-256 of an email). Same input always gives the same hash, so joins still work, but you cannot reverse it - as long as the input space is not guessable. Add a secret salt for emails and phone numbers, which are guessable.
- **Generalization/binning** - replace a precise value with a range: exact age 37 becomes "30-40," full ZIP becomes just the state. Reduces re-identification risk.
- **Suppression** - remove the column entirely when it is not needed.

The key insight: **anonymization is hard because of re-identification.** Removing names is not enough - a birth date plus a ZIP code plus a gender can uniquely identify most people. True anonymization means no combination of remaining fields can single someone out. When in doubt, remove or generalize, and get legal sign-off. You will apply this in USE 3.1 (the AI-readiness checklist has a privacy and residency section).

A quick, safe hash in Python:

```python
import hashlib
def pseudonymize(value, salt="stepup-secret-salt"):
    return hashlib.sha256((salt + str(value)).encode()).hexdigest()[:16]

print(pseudonymize("alice@example.com"))
print(pseudonymize("alice@example.com"))   # same input -> same token, so joins still work
```

Expected output (yours will differ if you change the salt):

```
85ba3da1ede53b42
85ba3da1ede53b42
```

Same email hashes to the same token every time, so you can still group and join by user, but you cannot recover the email. The salt keeps guessable inputs (emails, phone numbers) from being brute-forced against a rainbow table.

---

## 10. Data residency

**Data residency** is the legal requirement that data physically live in a specific country or region. EU citizens' personal data may have to stay on EU servers; some governments require citizen data never leave national borders. This directly constrains AI architecture: you cannot send EU customer data to a US-hosted model API if residency law forbids it.

As a consultant you must ask, early: where does this data legally have to live, and does our proposed AI setup respect that? Getting this wrong is not a bug - it is a fine and a lawsuit. It is the last item on the readiness checklist for exactly this reason.

---

## 11. Why this matters for AI

- Models need data delivered reliably, cleanly, and on schedule. That delivery system is data engineering, and it is where most AI projects actually succeed or fail.
- The trade-offs here - ETL vs ELT, batch vs streaming, lake vs warehouse, cron vs Airflow - are exactly the decisions a client pays a consultant to get right, and the default answer is usually the simpler one.
- Lineage, contracts, and observability are what let you trust an AI system in production and prove its behavior to an auditor.

Analysis makes you useful once. Data engineering makes you useful every night, at scale, which is what companies actually pay for. Project 3 builds one end to end.

---

## References

- ETL vs ELT overview (AWS) - https://aws.amazon.com/compare/the-difference-between-etl-and-elt/
- Data lakehouse (Databricks) - https://www.databricks.com/glossary/data-lakehouse
- Delta Lake - https://delta.io/ and Apache Iceberg - https://iceberg.apache.org/
- Change data capture with Debezium - https://debezium.io/documentation/reference/stable/tutorial.html
- Apache Airflow (DAGs, orchestration) - https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/dags.html
- Data catalogs: DataHub - https://datahubproject.io/ , Amundsen - https://www.amundsen.io/ , AWS Glue Data Catalog - https://docs.aws.amazon.com/glue/latest/dg/catalog-and-crawler.html , Databricks Unity Catalog - https://docs.databricks.com/data-governance/unity-catalog/index.html
- Python `hashlib` (SHA-256) - https://docs.python.org/3/library/hashlib.html
- GDPR pseudonymization vs anonymization guidance (EDPB/ICO) - https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/anonymisation/

Note: the SHA-256 example truncates to 16 hex characters for readability; a real pipeline typically keeps the full 64-character digest to minimize collision risk. The salt shown is a placeholder and must be kept secret and outside version control in production.
