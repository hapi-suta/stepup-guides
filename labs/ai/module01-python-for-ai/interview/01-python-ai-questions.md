# Interview: Python for AI

These questions test whether you understand the WHY behind the tools, not just the HOW. In an AI engineering interview, they want to know you can work with data at scale, not that you memorized syntax.

---

## Question 1: NumPy vs Python Lists

**Q: Why would you use a NumPy array instead of a Python list for AI workloads? Give a specific example.**

**Model Answer:**

Python lists store pointers to objects scattered in memory. A list of 1 million floats uses ~28 MB because each float is a separate Python object (28 bytes overhead per number). NumPy stores raw numbers in a contiguous block of memory - the same million floats takes ~8 MB.

But memory isn't the main reason. Speed is. When you do `numpy_array * 2`, NumPy loops in optimized C code over that contiguous memory block. When you do `[x * 2 for x in python_list]`, Python interprets each iteration, does type checking, creates new objects. NumPy is typically 50-100x faster for math operations.

Concrete example: computing dot products between embedding vectors in a RAG system. With 10,000 documents, each with a 1,536-dimension embedding, you'd compute 10,000 dot products per query. In pure Python loops, that takes seconds. With NumPy's `np.dot()`, it takes milliseconds.

**Key points to hit:**
- Contiguous memory layout (cache-friendly)
- Vectorized operations (C-level loops, no Python overhead)
- Type homogeneity (all elements same type = no per-element type checking)
- Memory efficiency (no Python object overhead per element)

---

## Question 2: Handling Missing Data

**Q: You receive a dataset for training a classification model and discover 8% of values are missing. What's your approach?**

**Model Answer:**

First, I'd understand the pattern. Are values missing randomly, or is there a pattern? If a column is 80% missing, I might drop it entirely. If a critical column has 2% missing, I'd impute.

Three strategies depending on context:

1. **Drop rows** (`dropna()`) - Simple but you lose data. Only works if missing data is a small fraction AND randomly distributed. Never do this if certain classes are disproportionately missing - you'd bias your model.

2. **Impute with statistics** (`fillna(median)`) - Replace missing values with the column's median (for skewed data) or mean (for normal distributions). Fast, doesn't lose rows, but adds artificial data points that weren't observed.

3. **Flag and fill** - Create a binary column `column_was_missing` (0 or 1), then fill the original column. This lets the model learn that "missing" itself might be informative. For example, if server metrics are missing, it might mean the server was down - that's a signal, not noise.

I'd also check: is the data missing because of a pipeline bug (fix the pipeline) or is it genuinely unobservable (handle statistically)?

**Key points to hit:**
- Investigate the pattern before choosing a strategy
- Consider impact on class balance
- Missingness itself can be a feature
- Different strategies for different column types (mean for numeric, mode for categorical)

---

## Question 3: Data Leakage

**Q: What is data leakage and why is it one of the most dangerous mistakes in ML?**

**Model Answer:**

Data leakage is when your training data contains information that wouldn't be available at prediction time. Your model looks brilliant during training but fails completely in production.

Classic example: predicting which database queries will be slow. If your features include `query_duration_ms` and your label is `is_slow = duration > 200ms`, the model just learns "if duration > 200, predict slow." It gets 99% accuracy in training. But in production, you don't HAVE the duration yet - you're trying to predict it before the query runs.

DBA analogy: it's like predicting whether a patient will be admitted to the hospital, but including "hospital_room_number" as a feature. If they have a room number, they've already been admitted. The model isn't predicting anything - it's just reading the answer.

How to prevent it:
- Always ask: "Would I have this data BEFORE I need the prediction?"
- Split your data chronologically when working with time series (train on past, test on future)
- Be suspicious of any feature that gives you >95% accuracy easily
- Use cross-validation to catch models that are "too good"

**Key points to hit:**
- Definition: future information leaking into training data
- Why it's dangerous: inflates metrics, fails in production
- Time-series specific: must split chronologically, not randomly
- Prevention: think about what's available at prediction time

---

## Question 4: Vectorization

**Q: A junior engineer wrote a data processing script using Python for-loops over a Pandas DataFrame with 10 million rows. It takes 45 minutes. How would you speed it up?**

**Model Answer:**

The core problem is Python loops over DataFrames. Every `iterrows()` call converts a row to a Series object, does type inference, and runs Python's interpreter for each iteration. With 10M rows, that's 10M object allocations and 10M interpreted iterations.

My approach in order of effort:

1. **Vectorize** - Replace the loop with Pandas/NumPy operations. `df[df['cpu'] > 90]` is a single C-level operation over the entire column. This alone typically gives 50-100x speedup, turning 45 minutes into 30 seconds.

2. **Use `.apply()` as a last resort** - If the logic is too complex for pure vectorization, `.apply()` is still faster than `iterrows()` because it avoids converting rows to Series.

3. **Optimize dtypes** - `float64` to `float32` halves memory and improves cache performance. Categorical columns for repeated strings (100 server names repeated across 10M rows saves massive memory).

4. **Chunk processing** - If it still doesn't fit in memory, `pd.read_csv(chunksize=100000)` processes in batches.

5. **Consider the right tool** - If 10M rows is the norm, maybe Pandas isn't the right tool. Polars (Rust-based) is 5-10x faster than Pandas. Or push the computation to PostgreSQL where it belongs.

**Key points to hit:**
- Never iterate rows in Pandas - vectorize
- Dtype optimization for memory
- Know when Pandas is the wrong tool (Polars, DuckDB, SQL)
- Profile before optimizing (find the actual bottleneck)

---

## Question 5: Feature Engineering

**Q: You have a table of database query logs with columns: timestamp, query_text, duration_ms, database_name, user_name. You want to predict which future queries will be slow. What features would you engineer?**

**Model Answer:**

Raw columns aren't enough. I'd engineer features that capture context and patterns:

**From timestamp:**
- Hour of day (queries at 2am behave differently than 2pm)
- Day of week (batch jobs run on weekends)
- Minutes since last query by same user (burst detection)

**From query_text:**
- Query type (SELECT, INSERT, UPDATE, DELETE, DDL)
- Number of JOINs (more joins = potentially slower)
- Has subquery (boolean)
- Table count (how many tables referenced)
- Has LIKE with wildcard prefix (sequential scan indicator)

**From historical patterns:**
- User's average query time over last hour (some users write bad queries)
- Table's average query time over last hour (hot tables)
- Same query template's historical p95 duration
- Current connection count for that database (load indicator)

**From database_name:**
- Current replication lag (if it's a replica)
- Table bloat percentage (from pg_stat_user_tables)
- Last vacuum time (stale stats = bad plans)

I would NOT include query_text as a raw string - that's high cardinality and won't generalize. Instead, normalize queries into templates (replace literal values with placeholders) and use the template as a categorical feature.

**Key points to hit:**
- Time-based features (cyclic patterns, recency)
- Domain knowledge drives feature engineering
- Aggregate/window features (historical averages)
- What NOT to include (raw high-cardinality text)
- Feature engineering is often more impactful than model selection
