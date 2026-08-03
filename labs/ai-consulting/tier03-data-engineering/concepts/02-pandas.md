# Concepts 3.2: pandas for AI

**Tier 3 - Data analysis and data engineering.** Teaching reference. pandas is SQL that lives in Python. It is the single most-used tool in data work: loading files, cleaning them, joining them, aggregating them, and shipping the result somewhere useful. If NumPy is the engine, pandas is the car you actually drive.

**Who this is for:** DBAs. Almost everything here has a SQL twin, and I call it out each time. Your existing instincts transfer directly.

**Run the snippets:** on your **lab server** (CentOS Stream 9), as **ec2-user**, inside a virtual environment with pandas installed:

```bash
python3.12
```

Type `exit()` to leave. Every snippet assumes `import pandas as pd` and `import numpy as np`.

---

## 1. Series and DataFrame - the two objects

A **Series** is one column: a labeled 1-D array. A **DataFrame** is a whole table: many Series sharing one index (the row labels). Think of a DataFrame as a query result set held in memory.

```python
import pandas as pd
s = pd.Series([10, 20, 30], name="spend")
print(s)

df = pd.DataFrame({
    "name": ["Ada", "Ben", "Cy"],
    "age": [30, 25, 41],
    "spend": [120.0, 80.5, 200.0],
})
print(df)
```

Expected output:

```
0    10
1    20
2    30
Name: spend, dtype: int64
   name  age  spend
0   Ada   30  120.0
1   Ben   25   80.5
2    Cy   41  200.0
```

The left-hand `0 1 2` is the **index** (row labels). By default it is a row number, but it can be a date or an ID.

---

## 2. Reading files - your daily entry point

You rarely type data by hand. You read it from CSV, JSON, Excel, or a database.

```python
import pandas as pd
# df = pd.read_csv("customers.csv")          # the workhorse
# df = pd.read_json("events.json")           # JSON records
# df = pd.read_sql("SELECT * FROM orders", conn)  # straight from Postgres
```

For this concepts doc we build a small frame inline so it always runs:

```python
import pandas as pd
import numpy as np
df = pd.DataFrame({
    "customer": ["Ada", "Ben", "Cy", "Dee", "Ada"],
    "region": ["East", "West", "East", None, "East"],
    "spend": [120.0, 80.5, 200.0, 50.0, np.nan],
    "orders": [3, 1, 5, 2, 1],
})
print(df.shape)      # (rows, columns)
print(df.head(2))    # first 2 rows - always sanity-check like this
```

Expected output:

```
(5, 4)
  customer region  spend  orders
0      Ada   East  120.0       3
1      Ben   West   80.5       1
```

`.head(n)` is the first thing you run after loading anything. Trust nothing until you have looked at it.

---

## 3. Inspecting - the first five minutes with any dataset

```python
print(df.info())        # column names, types, non-null counts
print(df.describe())    # numeric summary: count, mean, std, min, quartiles, max
print(df.dtypes)        # just the types
print(df["region"].value_counts())   # frequency of each category
```

Expected output (truncated):

```
<class 'pandas.core.frame.DataFrame'>
RangeIndex: 5 entries, 0 to 4
Data columns (total 4 columns):
 #   Column    Non-Null Count  Dtype
---  ------    --------------  -----
 0   customer  5 non-null      object
 1   region    4 non-null      object
 2   spend     4 non-null      float64
 3   orders    5 non-null      int64
...
region
East    3
West    1
Name: count, dtype: int64
```

`Non-Null Count` is gold: `region` has 4 of 5, `spend` has 4 of 5. You just found your missing data in one glance. `object` type means text (or mixed). Note that `value_counts()` returns a Series whose name is `count` in current pandas (it used to be named after the column) and whose own index carries the category labels (see: pandas Series.value_counts docs). With `normalize=True` the name is `proportion` instead.

---

## 4. Selecting columns and rows

```python
print(df["spend"])              # one column -> a Series
print(df[["customer", "spend"]])  # two columns -> a DataFrame (note double brackets)

# rows by boolean mask - this is your WHERE clause
print(df[df["spend"] > 100])

# combine conditions with & (and), | (or), wrap each in parentheses
print(df[(df["region"] == "East") & (df["orders"] >= 3)])
```

Expected output (last block):

```
  customer region  spend  orders
0      Ada   East  120.0       3
2       Cy   East  200.0       5
```

SQL twin: `df[df["spend"] > 100]` is `WHERE spend > 100`. The most common beginner error is forgetting the parentheses around each condition, or using Python's `and` instead of `&`. Use `&` and `|`, always parenthesize.

---

## 5. Sorting

```python
print(df.sort_values("spend", ascending=False))   # ORDER BY spend DESC
print(df.sort_values(["region", "spend"]))         # ORDER BY region, spend
```

Expected output (first block):

```
  customer region  spend  orders
2       Cy   East  200.0       5
0      Ada   East  120.0       3
1      Ben   West   80.5       1
3      Dee   None   50.0       2
4      Ada   East    NaN       1
```

NaN sorts to the bottom by default. `ascending` takes a list too, one per sort column.

---

## 6. Missing data - the everyday reality

Real data has holes. pandas marks them `NaN`. You must decide, per column, whether to drop, fill, or flag them - a judgment call, not a default. See Concepts 3.4 for the full framework.

```python
import pandas as pd
import numpy as np
df = pd.DataFrame({"region": ["East", None, "West"], "spend": [120.0, np.nan, 80.0]})
print(df.isna())              # True where missing
print(df.isna().sum())        # count missing per column - run this often

df_dropped = df.dropna()      # drop any row with a missing value
df_filled = df.copy()
df_filled["spend"] = df_filled["spend"].fillna(df_filled["spend"].median())  # fill with median
df_filled["region"] = df_filled["region"].fillna("Unknown")   # fill text with a label
print(df_filled)
```

Expected output (last block):

```
    region  spend
0     East  120.0
1  Unknown  100.0
2     West   80.0
```

Dropping is easy but throws away rows. Filling keeps them but invents values - so fill numbers with the median (robust to outliers) and fill categories with an explicit "Unknown" so nobody mistakes it for real data.

---

## 7. Grouping and aggregating - GROUP BY

This is the heart of analysis. Split the data into groups, compute something per group, combine the results.

```python
import pandas as pd
df = pd.DataFrame({
    "region": ["East", "West", "East", "West", "East"],
    "spend": [120.0, 80.0, 200.0, 60.0, 90.0],
    "orders": [3, 1, 5, 2, 1],
})
print(df.groupby("region")["spend"].sum())      # total spend per region
print(df.groupby("region").agg(
    total_spend=("spend", "sum"),
    avg_orders=("orders", "mean"),
    customers=("spend", "count"),
))
```

Expected output:

```
region
East    410.0
West    140.0
Name: spend, dtype: float64
        total_spend  avg_orders  customers
region
East          410.0         3.0          3
West          140.0         1.5          2
```

SQL twin: exactly `SELECT region, SUM(spend), AVG(orders), COUNT(*) FROM t GROUP BY region`. The named-aggregation form (`total_spend=("spend","sum")`) is the clearest way to write it and gives you tidy column names.

---

## 8. Joining - merge

Combining two tables on a key is `merge`, and it maps one-to-one onto SQL joins.

```python
import pandas as pd
customers = pd.DataFrame({"cid": [1, 2, 3], "name": ["Ada", "Ben", "Cy"]})
orders = pd.DataFrame({"cid": [1, 1, 2, 4], "amount": [50, 30, 80, 10]})

inner = customers.merge(orders, on="cid", how="inner")   # only matching keys
left = customers.merge(orders, on="cid", how="left")      # keep all customers
print(inner)
print(left)
```

Expected output:

```
   cid name  amount
0    1  Ada      50
1    1  Ada      30
2    2  Ben      80
   cid name  amount
0    1  Ada    50.0
1    1  Ada    30.0
2    2  Ben    80.0
3    3   Cy     NaN
```

`how="inner"` drops Cy (no orders) and order for cid 4 (no customer). `how="left"` keeps Cy with a NaN amount. Choosing the wrong join type silently changes your row count and your totals - the top cause of "the numbers don't add up." Always check row counts before and after a merge.

To stack rows from two frames on top of each other (a UNION, not a join), use `pd.concat([df1, df2])`. The old `DataFrame.append` method was deprecated in pandas 1.4 and removed in pandas 2.0 (see: pandas 2.0 what's new), so any tutorial that calls `df.append(...)` is out of date - use `pd.concat` instead.

---

## 9. Dates

Real data has timestamps, and pandas has real date support once you convert the column.

```python
import pandas as pd
df = pd.DataFrame({"ts": ["2026-01-05", "2026-02-11", "2026-02-28"], "sales": [100, 200, 150]})
df["ts"] = pd.to_datetime(df["ts"])    # convert text to real dates
df["month"] = df["ts"].dt.month        # extract the month number
df["weekday"] = df["ts"].dt.day_name() # day-of-week name
print(df)
print(df.groupby(df["ts"].dt.to_period("M"))["sales"].sum())  # monthly totals
```

Expected output:

```
          ts  sales  month   weekday
0 2026-01-05    100      1    Monday
1 2026-02-11    200      2 Wednesday
2 2026-02-28    150      2  Saturday
ts
2026-01    100
2026-02    350
Freq: M, Name: sales, dtype: int64
```

Until you run `to_datetime`, a date column is just text and `.dt` will not work. Converting first is the fix for most "why can't I group by month" confusion.

---

## 10. Text cleaning

Text arrives dirty: stray spaces, mixed case, inconsistent labels. The `.str` accessor vectorizes string operations across a column.

```python
import pandas as pd
df = pd.DataFrame({"city": [" New York ", "new york", "BOSTON", "Boston "]})
df["clean"] = df["city"].str.strip().str.title()   # trim spaces, Title Case
print(df["clean"].value_counts())
```

Expected output:

```
clean
New York    2
Boston      2
Name: count, dtype: int64
```

Before cleaning, pandas saw four distinct cities; after, two. Inconsistent text is why counts and joins fail silently, and `.str.strip().str.lower()` (or `.title()`) fixes most of it.

---

## 11. Transform - new columns

Deriving columns is how raw data becomes AI features.

```python
import pandas as pd
df = pd.DataFrame({"spend": [120.0, 80.0, 200.0], "orders": [3, 1, 5]})
df["avg_order_value"] = df["spend"] / df["orders"]    # vectorized, no loop
df["is_big_spender"] = df["spend"] > 150               # a boolean feature
df["tier"] = pd.cut(df["spend"], bins=[0, 100, 150, 1000],
                    labels=["low", "mid", "high"])      # bucket a number into bands
print(df)
```

Expected output:

```
   spend  orders  avg_order_value  is_big_spender  tier
0  120.0       3             40.0           False   mid
1   80.0       1             80.0           False   low
2  200.0       5             40.0            True  high
```

`pd.cut` turning a continuous number into labeled bands ("low/mid/high") is a very common feature-engineering move an AI model can use.

---

## 12. Exporting

When the work is done, write it out for the next stage - a file, or straight into a database.

```python
# df.to_csv("curated.csv", index=False)   # index=False so the row number is not a column
# df.to_json("curated.json", orient="records")
# df.to_sql("curated_customers", conn, if_exists="replace", index=False)
```

`index=False` on CSV is the flag beginners forget - without it, you get a mystery unnamed first column every time you round-trip a file.

---

## 13. Why this matters for AI

- Roughly 80% of an AI project is data work, and pandas is where that work happens: load, clean, join, aggregate, feature, export.
- A model is only as good as the table you feed it. Silent join errors, unhandled NaNs, and dirty text are how bad data reaches a model and produces confident garbage.
- The habits that save you: `.head()` and `.info()` after every load, `.isna().sum()` before you trust a column, and a row-count check before and after every merge.

You already think in tables. pandas is your existing SQL brain, in Python, sitting one step upstream of every model you will build.

---

## References

- pandas Getting started / 10 minutes to pandas - https://pandas.pydata.org/docs/user_guide/10min.html
- pandas `Series.value_counts` (returns a Series named `count`) - https://pandas.pydata.org/docs/reference/api/pandas.Series.value_counts.html
- pandas merge / join / concatenate - https://pandas.pydata.org/docs/user_guide/merging.html
- pandas `groupby` (named aggregation) - https://pandas.pydata.org/docs/user_guide/groupby.html
- pandas missing data (`isna`, `dropna`, `fillna`) - https://pandas.pydata.org/docs/user_guide/missing_data.html
- pandas `.dt` and `.str` accessors - https://pandas.pydata.org/docs/user_guide/text.html and https://pandas.pydata.org/docs/user_guide/timeseries.html
- pandas 2.0 what's new (removal of `DataFrame.append`) - https://pandas.pydata.org/docs/whatsnew/v2.0.0.html

Outputs in this doc were produced on pandas 2.3.x (Python 3.12). Note: `df.info()`'s exact `memory usage` line varies by version and platform, and pandas trims trailing zeros in float display, so a whole-number mean prints as `3.0`, not `3.000000`.
