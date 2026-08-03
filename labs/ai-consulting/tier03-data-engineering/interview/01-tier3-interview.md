# Interview: Tier 3 - Data Analysis and Data Engineering

**Tier 3 interview prep.** These are the questions an AI-consulting client, a data-engineering hiring panel, or a skeptical CTO will actually ask to see whether you can be trusted to move a company's data to where a model can use it - safely, reliably, and legally. Each entry has the question, a model answer in plain language, and "why they ask" so you know what they are really probing.

The skill being tested across all of these is the same: can you make good engineering trade-offs and explain them honestly to someone who is paying for the outcome, not the code? That is the consultant's job.

---

## 1. What is the difference between ETL and ELT, and when do you use each?

**Model answer.** Both move data through three steps - extract, transform, load - the difference is the order. ETL transforms the data on a separate machine before loading only the clean result into the warehouse. ELT loads the raw data into the warehouse first, then transforms it there using the warehouse's own compute. I default to ELT for modern cloud warehouses like Snowflake or BigQuery, because they are cheap and powerful, and loading raw first means I keep the original data and can re-derive features later when the model's needs change - which they always do. I reach for ETL when the destination is expensive or limited, or when I legally cannot land raw sensitive data in the warehouse and must strip or mask it first. In practice many pipelines are a hybrid: transform enough to be safe and typed, but keep a raw landing zone so nothing is lost.

**Why they ask.** This is the single most common data-engineering question, and it separates people who memorized an acronym from people who understand the trade-off. They want to hear that you keep raw data when you can, that you know cloud warehouses changed the default to ELT, and that privacy law can force ETL. A candidate who says "ETL is old, ELT is new, always use ELT" has not thought about the exceptions.

---

## 2. What is data lineage, and why do auditors and regulators care about it?

**Model answer.** Data lineage is the documented map of where every piece of data came from and everywhere it flows - this dashboard number came from this curated table, which was built from that raw file, which came from that API on that date. Auditors and regulators care because they need to answer "can you prove where this number came from, and that it was handled correctly?" If a model decides who gets a loan or a medical flag, a regulator can demand the exact training data and the path it took, and "we are not sure" is a compliance failure and sometimes a legal one. Lineage also makes me faster day to day: when a source breaks, lineage tells me instantly which downstream reports are affected, and when a number looks wrong, it tells me where to look. In my pipelines I record lineage concretely - every curated row carries the run id and timestamp that produced it, and every run logs its sources and row counts.

**Why they ask.** Lineage is where governance meets engineering. They want to know you build for auditability from the start, not bolt it on after a regulator asks. In regulated industries - finance, healthcare, insurance - a consultant who does not think about lineage is a liability, because the fine for "we cannot prove it" can dwarf the project.

---

## 3. How do you assess whether an organization's data is AI-ready?

**Model answer.** I run a structured readiness assessment across about ten dimensions rather than eyeballing it. The big ones: ownership - is there a clear owner who can authorize use; availability - can I actually get the data at the volume and freshness a model needs; quality - the six dimensions of complete, accurate, consistent, timely, valid, unique; privacy - does it contain personal data that must be protected; permissions - am I legally allowed to use it for training; labeling - for supervised learning, do the answers exist or must we create them; and residency - are there legal limits on where the data can live. I back every judgment with a measured signal, not an opinion - "26% of labels are missing, verified by script," not "labeling seems weak." The output is a scorecard with a clear verdict: go, fix-first, or no-go, plus a remediation path. Done in week one, this saves a client from spending three months building a model on data that was never ready.

**Why they ask.** This is the highest-value thing a data/AI consultant does, and most failed AI projects failed here - the data was not ready and nobody checked. They want to see you have a repeatable framework, that you demand evidence over vibes, and that you are willing to tell a client "no-go, fix this first" instead of taking the money and building on sand.

---

## 4. How do you anonymize or mask data for AI training, and what is the hard part?

**Model answer.** There is a ladder of techniques, from weakest to strongest: masking hides part of a value like showing only the last four digits of a card; pseudonymization replaces an identifier with a consistent token so you can still join per-user without knowing who they are; hashing is a one-way transform, and for guessable inputs like emails you must add a secret salt so it cannot be reversed with a lookup table; generalization replaces a precise value with a range, like turning an exact age into a decade or a full ZIP into just the state; and suppression removes the column entirely. The hard part is re-identification: removing names is not enough, because a birth date plus a ZIP plus a gender can uniquely identify most people. True anonymization means no combination of the remaining fields can single anyone out, which usually forces you to generalize or drop quasi-identifiers, not just the obvious ones. When it is genuinely sensitive, I remove or generalize aggressively and get legal sign-off, because getting this wrong is not a bug - it is a fine and a lawsuit.

**Why they ask.** Privacy is where AI projects get companies sued, and it is a legal requirement under GDPR, HIPAA, and CCPA, not a nicety. They want to know you understand the techniques, that you know hashing a raw email is not safe without a salt, and - most importantly - that you understand re-identification, which is the trap that catches people who think deleting the "name" column is enough.

---

## 5. When would you choose batch processing over streaming?

**Model answer.** I default to batch and only move to streaming when the business genuinely cannot wait. Batch processes data in scheduled chunks - hourly, nightly - and it is simple, cheap, easy to reason about, and trivial to re-run when something fails. Streaming processes each record the moment it arrives and it is the right call for fraud detection, live dashboards, or anything where minutes of delay cause real harm - but it roughly triples the complexity and cost, adds a whole class of failure modes, and is much harder to debug. The mistake I see constantly is a client asking for "real-time" when nightly would serve the business perfectly, and paying for streaming complexity they never use. So my rule is: quantify the cost of latency first. If a few hours old is fine - and for reporting and model-training data it almost always is - batch wins.

**Why they ask.** Over-engineering is expensive, and streaming is the most over-requested capability in data. They want a consultant who pushes back on unnecessary complexity and can justify the cheaper, simpler choice to a client who thinks "real-time" sounds impressive. Reaching for streaming by default is a red flag.

---

## 6. Explain data warehouse vs data lake vs lakehouse. Which for an AI project?

**Model answer.** A data warehouse is structured storage optimized for SQL analytics - you define tables up front and only clean, structured data goes in; think Snowflake, BigQuery, Redshift. It is fast and governed but rigid. A data lake is cheap object storage that holds anything - files, logs, images, raw JSON - and you impose structure only when you read it; it is flexible and cheap but easily rots into a "data swamp" nobody trusts. A lakehouse is the modern hybrid: it puts warehouse-style structure, transactions, and governance on top of lake-style cheap storage, using formats like Delta Lake or Iceberg. For an AI project specifically, I usually want a lake or lakehouse, because models eat unstructured data - text, images - that a rigid warehouse handles poorly, and because I want to keep raw data cheaply so I can re-derive features as the model evolves. The lakehouse is increasingly my default recommendation because it gives lake flexibility with warehouse reliability.

**Why they ask.** Clients confuse these three constantly and sometimes buy the wrong one. They want to see you can explain them cleanly and match the storage to the workload - and that you know AI's appetite for unstructured, raw data pulls toward lakes and lakehouses rather than classic warehouses.

---

## 7. A pipeline broke because an upstream team renamed a column. How do you prevent this?

**Model answer.** First, I accept that upstream schemas will always change - that is not preventable, so the pipeline must handle it. The wrong response is a loader that hard-codes column names and either crashes or, worse, silently loads nulls when a column is renamed. The right pattern is detect-and-adapt driven by a data contract: on every batch, compare the incoming schema to the expected one, adapt known changes with a rename map, tolerate additive changes like a harmless new column, and fail loudly - naming the exact missing field - on a breaking change, so I never silently load garbage. Second, the durable organizational fix is a data contract: a written, versioned agreement with the source team about the columns, types, and rules, so they are on the hook to announce changes and my monitor catches them if they forget. The root cause of these outages is never "the rename" - it is "no contract and no drift detection."

**Why they ask.** Schema drift is the number-one cause of broken pipelines in the real world, and how you answer reveals whether you have operated pipelines in production. They want detect-and-adapt, loud failure over silent nulls, and the maturity to name the true root cause - the missing contract - rather than just patching the symptom.

---

## 8. An overnight job has been "succeeding" but the data is stale. What happened and how do you fix it?

**Model answer.** This is a silent failure, the most dangerous kind, because monitoring says green while the data goes red. The usual cause is a job that swallows its own error - an unchecked exit code or a stray `|| true` - so its work step failed but the script still exited 0, and cron reported success. The fix has three parts. One: never swallow errors - the job must exit non-zero when its work fails, so the scheduler can see it. Two: record every run in a heartbeat table, success or failure, so "did it run?" becomes a query instead of a guess. Three, and most important: monitor freshness independently - a separate check, on its own schedule, that looks at the heartbeat and alerts if the last success is too old. That independent monitor is the only thing that catches a job that stopped running entirely, because a dead job cannot report its own death. And I always test the alert by forcing a stale condition and watching it fire - an alert you have never seen fire is one you cannot trust.

**Why they ask.** Silent failures are a rite of passage in data engineering, and the answer shows real operational scars. They want to hear "never swallow errors," "heartbeat and freshness monitoring," and especially "test that the alert actually fires" - the discipline that separates someone who has run production pipelines from someone who has only written them.

---

## 9. How do you handle missing data, and how do you decide between dropping and filling?

**Model answer.** First I measure it - percent missing per column - because the decision depends on how much is gone and why. If only a small fraction is missing, I fill it: median for numbers because it resists outliers, and an explicit label like "Unknown" for categories so nobody mistakes the fill for real data. If a large share is missing - say over 40% - filling invents most of the column, so I usually drop the column and tell the client why, or drop the affected rows if there are few. The judgment also depends on whether the data is missing at random or missing for a reason - if income is blank only for high earners, dropping those rows biases the whole analysis. And whatever I do, I flag it, often with an extra boolean column marking which values were imputed, so the missingness itself stays visible to the model and to auditors. The one thing I never do is silently let NaNs flow downstream, because in NumPy and pandas a single NaN can poison an entire aggregate.

**Why they ask.** Missing data is universal and the naive answers - "just drop the nulls" or "just fill with the mean" - introduce bias or throw away signal. They want to see you measure first, that you know median beats mean for filling, that you consider whether the missingness is random, and that you keep it visible rather than hiding it.

---

## 10. Why is a validation suite or data contract worth the effort, and where does it run?

**Model answer.** Because bad data is far cheaper to stop at the door than to chase after it has corrupted reports, trained a model, or reached a client. A validation suite is a set of named, declarative expectations - customer_id is never null, amount is between zero and some max, region is one of a known set - that runs on every batch and fails loudly, with a clear message and a non-zero exit, when the data violates them. That non-zero exit is what lets an orchestrator or CI job block the bad batch and alert instead of loading it. Tools like Great Expectations formalize this, and dbt does the same for the transformation layer with SQL models and built-in tests, but the idea is tool-independent: checks that gate the pipeline. It runs at the boundary - right after ingest and before the curated load - so nothing bad gets in, plus a lighter freshness-and-volume check in production to catch drift over time. The payoff is that silent data-quality regressions, the ones that quietly destroy trust, become loud early rejections instead.

**Why they ask.** Junior engineers see validation as overhead that slows them down; senior ones see it as the thing that lets them sleep. They want to hear that you gate the pipeline on validation, that you know the real tools (Great Expectations, dbt) but understand the underlying idea, and that you place the checks at the boundary so bad data never reaches production. This question sorts prevention-minded engineers from firefighters.
