# Concepts 3.4: Data Quality for AI

**Tier 3 - Data analysis and data engineering.** Teaching reference. AI has a brutal law: garbage in, garbage out, at scale. A model trained on dirty data does not warn you - it confidently produces dirty answers. As an AI consultant, assessing and fixing data quality is often the most valuable thing you do, and it is what separates a project that ships from one that quietly fails six months in.

**Who this is for:** DBAs. You already enforce constraints, foreign keys, and NOT NULL. This doc names the discipline around that instinct and extends it to the messier world of AI data.

**Run the snippets:** on your **lab server** (CentOS Stream 9), as **ec2-user**, inside a virtual environment with pandas installed:

```bash
python3.12
```

Snippets assume `import pandas as pd` and `import numpy as np`.

---

## 1. The six dimensions of data quality

Every data-quality conversation fits into six buckets. Memorize them; they are your checklist.

- **Completeness** - is data missing? (null customer emails)
- **Accuracy** - is the data correct? (an age of 200)
- **Consistency** - does it agree with itself and other systems? ("NY" vs "New York" vs "New York City")
- **Timeliness** - is it fresh enough to use? (yesterday's inventory for a live storefront)
- **Validity** - does it follow the rules/format? (a phone number with letters in it)
- **Uniqueness** - are there duplicates? (the same order counted twice)

A useful mnemonic: **C-A-C-T-V-U**. For any dataset a client hands you, walk these six and you will find the problems.

---

## 2. Completeness - finding what is missing

```python
import pandas as pd
import numpy as np
df = pd.DataFrame({
    "email": ["a@x.com", None, "c@x.com", None, "e@x.com"],
    "age": [30, 25, np.nan, 41, 28],
})
missing = df.isna().sum()
pct = (df.isna().mean() * 100).round(1)
print(missing)
print(pct)
```

Expected output:

```
email    2
age      1
dtype: int64
email    40.0
age      20.0
dtype: float64
```

A column that is 40% empty is a red flag - a model cannot learn much from it, and imputing (filling) that many values invents most of the column. The judgment call: below ~5% missing, fill it (median for numbers, "Unknown" for categories); above ~40%, consider dropping the column and telling the client why.

---

## 3. Accuracy - values that are wrong, not just missing

Accuracy is harder than completeness because wrong data looks like real data. You catch it with range checks and domain knowledge.

```python
import pandas as pd
df = pd.DataFrame({"age": [30, 25, 200, -5, 41], "price": [10.0, 20.0, 0.0, 15.0, -3.0]})
bad_age = df[(df["age"] < 0) | (df["age"] > 120)]     # humans are 0-120
bad_price = df[df["price"] <= 0]                        # price must be positive
print("Impossible ages:\n", bad_age)
print("Non-positive prices:\n", bad_price)
```

Expected output:

```
Impossible ages:
    age  price
2  200    0.0
3   -5   15.0
Non-positive prices:
    age  price
2  200    0.0
4   41   -3.0
```

You cannot check accuracy without knowing the domain. That is why the first hour with a client is spent asking "what is a valid value for this field?" The answers become your validation rules (section 6).

---

## 4. Consistency - the same thing spelled many ways

```python
import pandas as pd
df = pd.DataFrame({"state": ["NY", "New York", "new york", "N.Y.", "CA", "California"]})
print(df["state"].value_counts())   # six distinct values, really two states
# a mapping fixes it
mapping = {"NY": "New York", "new york": "New York", "N.Y.": "New York", "California": "CA"}
df["state_clean"] = df["state"].replace(mapping)
print(df["state_clean"].value_counts())
```

Expected output:

```
state
NY            1
New York      1
new york      1
N.Y.          1
CA            1
California    1
Name: count, dtype: int64
state_clean
New York    4
CA          2
Name: count, dtype: int64
```

Inconsistency inflates your category count, breaks joins, and makes group-bys wrong. A model treats "NY" and "New York" as two unrelated things. Standardizing to one canonical form per value is a core cleaning step.

---

## 5. Timeliness, validity, uniqueness - the rest of the six

**Timeliness** - check the freshest timestamp against now:

```python
import pandas as pd
df = pd.DataFrame({"updated": pd.to_datetime(["2026-07-01", "2026-07-20", "2025-01-01"])})
age_days = (pd.Timestamp("2026-07-25") - df["updated"]).dt.days
print(age_days.describe()[["min", "max"]])
```

Expected output:

```
min      5.0
max    570.0
Name: updated, dtype: float64
```

A max of 570 days means some rows are over a year and a half old. If a model needs current data, that is stale and dangerous.

**Validity** - does it match the required format? Use a regex:

```python
import pandas as pd
df = pd.DataFrame({"email": ["a@x.com", "not-an-email", "c@y.org", "d@"]})
valid = df["email"].str.match(r"^[^@]+@[^@]+\.[^@]+$")
print(df[~valid])   # rows that fail the pattern
```

Expected output:

```
          email
1  not-an-email
3            d@
```

**Uniqueness** - find duplicates:

```python
import pandas as pd
df = pd.DataFrame({"order_id": [1, 2, 2, 3, 3, 3]})
print("Duplicate rows:", df.duplicated(subset=["order_id"]).sum())
print(df["order_id"].value_counts()[lambda s: s > 1])
```

Expected output:

```
Duplicate rows: 3
order_id
3    3
2    2
Name: count, dtype: int64
```

Duplicates double-count revenue and over-weight examples in training. `duplicated()` flags every copy after the first; `drop_duplicates()` removes them.

---

## 6. Data quality rules - turning checks into code

A one-off inspection is not enough. You encode the six dimensions as **rules** that run automatically on every batch, so problems get caught before they reach a model. A rule is just an assertion with a clear message.

```python
import pandas as pd
def check(df):
    errors = []
    if df["email"].isna().any():
        errors.append(f"completeness: {df['email'].isna().sum()} rows missing email")
    if (df["age"] > 120).any() or (df["age"] < 0).any():
        errors.append("accuracy: age outside 0-120")
    if df["order_id"].duplicated().any():
        errors.append(f"uniqueness: {df['order_id'].duplicated().sum()} duplicate order_id")
    return errors

sample = pd.DataFrame({"email": ["a@x.com", None], "age": [30, 200], "order_id": [1, 1]})
for e in check(sample):
    print("FAIL:", e)
```

Expected output:

```
FAIL: completeness: 1 rows missing email
FAIL: accuracy: age outside 0-120
FAIL: uniqueness: 1 duplicate order_id
```

This is the seed of a validation suite. Tools like Great Expectations (USE 3.2) formalize it, but the idea is exactly this: named checks, clear failure messages, run on every batch.

---

## 7. Data contracts

A **data contract** is a written, enforced agreement between a data producer and a data consumer about what the data will look like: the columns, their types, their allowed ranges, which are required, and who owns them. It is a schema plus quality rules plus an owner.

Why it matters: most pipeline breakages come from an upstream team changing something without telling you - renaming a column, changing a type, dropping a field. A contract turns that from a silent 3am failure into a loud, early "this batch violates the contract" that names the responsible team. You will live this in SURVIVE: schema-evolution.

A minimal contract as a Python dict:

```python
CONTRACT = {
    "order_id":  {"type": "int",   "required": True,  "unique": True},
    "email":     {"type": "str",   "required": True,  "pattern": r"^[^@]+@[^@]+\.[^@]+$"},
    "amount":    {"type": "float", "required": True,  "min": 0},
    "region":    {"type": "str",   "required": False, "allowed": ["East", "West", "North", "South"]},
}
```

The contract lives in version control, both teams agree to it, and your pipeline validates every batch against it. When the check fails, the error names the field and the rule, so you know exactly who to call.

---

## 8. Data observability

**Observability** is monitoring the health of your data over time, the way you already monitor a database. The five pillars:

- **Freshness** - when did this table last update? (a table frozen for 3 days is a signal)
- **Volume** - how many rows arrived? (10 rows when you expect 10,000 means an upstream break)
- **Schema** - did the columns or types change unexpectedly?
- **Distribution** - did the values shift? (average order value suddenly 10x - a units bug or fraud)
- **Lineage** - where did this data come from and what depends on it?

The point of observability is to be told about a problem by a monitor, not by an angry client. A silent scheduled job that stopped writing rows (SURVIVE: silent-scheduled-failure) is a volume-and-freshness failure you should catch automatically.

---

## 9. Root cause analysis (RCA)

When data quality breaks, resist the urge to just patch the symptom. RCA finds why it happened so it does not happen again. A simple, effective method is **the five whys**:

1. Duplicate orders appeared in the report. **Why?**
2. The load job inserted the same batch twice. **Why?**
3. The job ran twice because a retry fired after a timeout. **Why?**
4. The insert had no idempotency key, so the retry duplicated rows. **Why?**
5. The pipeline was written assuming the job always succeeds on the first try.

The root cause is not "duplicates" - it is "no idempotency key on inserts." The fix is a unique constraint plus an upsert, not a nightly dedup script. RCA writeups are a deliverable clients pay for: a clear timeline, the root cause, and the durable fix. You practice this in SURVIVE: data-quality-regression.

---

## 10. Why this matters for AI

- A model amplifies whatever is in its training data. Bias, staleness, and errors do not average out - they get learned and repeated with confidence.
- "Is our data AI-ready?" is the question every client actually needs answered, and the six dimensions plus a contract are how you answer it (see USE 3.1, the readiness checklist).
- The most senior move in data work is prevention: contracts and observability that stop bad data at the door, so nobody spends a weekend on RCA in the first place.

Data quality is unglamorous and it is the whole game. The best AI consultants are, underneath, exceptional data-quality engineers.

---

## References

- pandas missing data (`isna`, `dropna`, `fillna`) - https://pandas.pydata.org/docs/user_guide/missing_data.html
- pandas duplicate handling (`duplicated`, `drop_duplicates`) - https://pandas.pydata.org/docs/reference/api/pandas.DataFrame.duplicated.html
- pandas `Series.str.match` (regex validity checks) - https://pandas.pydata.org/docs/reference/api/pandas.Series.str.match.html
- Great Expectations (data validation framework) - https://docs.greatexpectations.io/
- The five pillars of data observability (freshness, volume, schema, distribution, lineage), Monte Carlo - https://www.montecarlodata.com/blog-what-is-data-observability/
- Five whys root-cause technique - https://en.wikipedia.org/wiki/Five_whys

Note on the six dimensions: "completeness, accuracy, consistency, timeliness, validity, uniqueness" is a widely used framework (it aligns with the dimensions defined by DAMA-DMBOK); different sources add or split a dimension or two, so treat the list as a practical checklist rather than a single fixed standard.

Outputs in this doc were produced on pandas 2.3.x. Reminder: `value_counts()` returns a Series named `count` in current pandas and prints its index name on its own line above the values.
