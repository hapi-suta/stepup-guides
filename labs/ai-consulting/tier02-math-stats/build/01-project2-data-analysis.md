# BUILD: Project 2 - Data Analysis and Executive Findings

**Tier 2 - the analysis capstone.** You will take a dataset, profile it, find the missing values and outliers, compute correlations, test a hypothesis, build charts, and write up the findings for a non-technical executive. This is the day-to-day work of an AI consultant: turning raw data into a decision someone can act on.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25. All output shown is real (truncated where long, and random draws will differ on your machine).

**Prerequisite:** you finished Tier 1 (Python foundations) and have read Concepts 2.4 (Statistics). We use no internet download - we generate a realistic dataset locally so the lab always works.

**What you build:** a folder `project2-analysis/` with a data generator, an analysis script, and two saved chart images. You will read a printed report and a written executive summary.

---

## Step 1: Create the project folder

On your **lab server**, as **ec2-user**, make a working folder:

```bash
mkdir -p ~/project2-analysis
```

Move into it:

```bash
cd ~/project2-analysis
```

`mkdir -p` creates the folder (the `-p` flag means "do not error if it already exists"). `cd` changes into it so every file we write lands here.

---

## Step 2: Create a virtual environment

A virtual environment keeps this project's packages separate from the system Python.

Still on your **lab server**, as **ec2-user**, in `~/project2-analysis`:

```bash
python3.12 -m venv .venv
```

`-m venv` runs Python's built-in venv module. `.venv` is the folder name it creates. Activate it:

```bash
source .venv/bin/activate
```

`source` runs the activate script in your current shell. Your prompt now shows `(.venv)` at the front, which means the environment is on.

---

## Step 3: Install the data libraries

Still in the activated environment:

```bash
pip install numpy pandas matplotlib scipy
```

`pip install` downloads and installs packages. `numpy` is arrays and math, `pandas` is table handling (like SQL for Python), `matplotlib` draws charts, `scipy` has the statistical tests. Confirm they landed:

```bash
pip list | grep -Ei "numpy|pandas|matplotlib|scipy"
```

`pip list` prints installed packages; the `grep -Ei` filters to just the four we want (`-E` enables the `|` alternation, `-i` ignores case).

Expected output (yours will differ):

```
matplotlib        3.9.2
numpy             2.1.1
pandas            2.2.2
scipy             1.14.1
```

---

## Step 4: Write the data generator

We will create a realistic dataset: an e-commerce company's customers, with signup channel, age, monthly spend, support tickets, and whether they churned. We deliberately bake in missing values, a couple of outliers, and a real relationship so the analysis has something to find.

Still on your **lab server**, as **ec2-user**, in `~/project2-analysis`, open a new file with vi:

```bash
vi generate_data.py
```

Press `i` to enter insert mode, then type (or paste) the following:

```python
import numpy as np
import pandas as pd

np.random.seed(42)   # fixed seed so everyone gets the same data
n = 1000

# signup channel
channel = np.random.choice(["organic", "paid_ads", "referral"], size=n, p=[0.5, 0.3, 0.2])

# age: mostly 20-60, roughly normal
age = np.random.normal(38, 11, size=n).round().clip(18, 90)

# monthly spend depends a bit on age (older customers spend more) plus noise
monthly_spend = (age * 1.8 + np.random.normal(0, 20, size=n)).round(2).clip(0, None)

# support tickets: a count, most people have few
support_tickets = np.random.poisson(1.2, size=n)

# churn: more tickets and lower spend -> more likely to churn
churn_prob = 0.05 + 0.06 * support_tickets - 0.0008 * monthly_spend
churn_prob = churn_prob.clip(0.01, 0.95)
churned = (np.random.random(n) < churn_prob).astype(int)

df = pd.DataFrame({
    "channel": channel,
    "age": age,
    "monthly_spend": monthly_spend,
    "support_tickets": support_tickets,
    "churned": churned,
})

# inject realistic messiness:
# 1) 40 random missing ages
missing_idx = np.random.choice(n, size=40, replace=False)
df.loc[missing_idx, "age"] = np.nan

# 2) two data-entry outliers in spend
df.loc[7, "monthly_spend"] = 9999.0
df.loc[123, "monthly_spend"] = 8500.0

df.to_csv("customers.csv", index=False)
print(f"Wrote customers.csv with {len(df)} rows and {df.isna().sum().sum()} missing values")
```

Press `Esc` to leave insert mode, then type `:wq` and press Enter to save and quit vi.

---

## Step 5: Generate the dataset

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python generate_data.py
```

This runs the script and writes `customers.csv`.

Expected output:

```
Wrote customers.csv with 1000 rows and 40 missing values
```

Peek at the first few rows to confirm it looks like a table:

```bash
head -5 customers.csv
```

`head -5` prints the first 5 lines of the file.

Expected output (yours will differ):

```
channel,age,monthly_spend,support_tickets,churned
organic,40.0,43.87,0,0
referral,23.0,39.74,1,0
paid_ads,42.0,45.51,0,0
paid_ads,45.0,96.2,0,0
```

---

## Step 6: Write the analysis script

This is the heart of the project. Open a new file:

```bash
vi analyze.py
```

Press `i`, then enter the following. Read the comments as you go - each block is one analysis step from Concepts 2.4.

```python
import numpy as np
import pandas as pd
from scipy import stats
import matplotlib
matplotlib.use("Agg")   # draw to files, no display needed on a headless server
import matplotlib.pyplot as plt

df = pd.read_csv("customers.csv")

print("=" * 55)
print("STEP A: PROFILE THE DATA")
print("=" * 55)
print(f"Rows: {len(df)}, Columns: {list(df.columns)}")
print("\nData types:")
print(df.dtypes)
print("\nNumeric summary:")
print(df.describe().round(2))

print("\n" + "=" * 55)
print("STEP B: MISSING VALUES")
print("=" * 55)
missing = df.isna().sum()
print(missing)
# Fill missing age with the median (robust to outliers, per Concepts 2.4)
median_age = df["age"].median()
df["age"] = df["age"].fillna(median_age)
print(f"\nFilled missing ages with median = {median_age}")

print("\n" + "=" * 55)
print("STEP C: OUTLIERS (IQR method)")
print("=" * 55)
# The IQR rule: anything beyond 1.5*IQR past the quartiles is an outlier
q1 = df["monthly_spend"].quantile(0.25)
q3 = df["monthly_spend"].quantile(0.75)
iqr = q3 - q1
upper = q3 + 1.5 * iqr
outliers = df[df["monthly_spend"] > upper]
print(f"Q1={q1:.2f}, Q3={q3:.2f}, IQR={iqr:.2f}, upper fence={upper:.2f}")
print(f"Found {len(outliers)} spend outliers above the fence:")
print(outliers[["monthly_spend"]].to_string())
# Cap outliers at the fence rather than deleting rows (keeps the customer)
df["monthly_spend"] = df["monthly_spend"].clip(upper=upper)
print("Capped outliers at the upper fence.")

print("\n" + "=" * 55)
print("STEP D: CORRELATIONS")
print("=" * 55)
numeric = df[["age", "monthly_spend", "support_tickets", "churned"]]
corr = numeric.corr().round(3)
print(corr)
print("\nStrongest driver of churn:")
churn_corr = corr["churned"].drop("churned").abs().sort_values(ascending=False)
print(churn_corr)

print("\n" + "=" * 55)
print("STEP E: HYPOTHESIS TEST")
print("=" * 55)
# Question: do churned customers file more support tickets than retained ones?
# Null hypothesis: no difference in mean tickets.
churned_tickets = df[df["churned"] == 1]["support_tickets"]
retained_tickets = df[df["churned"] == 0]["support_tickets"]
t_stat, p_value = stats.ttest_ind(churned_tickets, retained_tickets, equal_var=False)
print(f"Mean tickets - churned: {churned_tickets.mean():.2f}, retained: {retained_tickets.mean():.2f}")
print(f"t-statistic: {t_stat:.3f}, p-value: {p_value:.5f}")
if p_value < 0.05:
    print("RESULT: statistically significant (p < 0.05). Churned customers file more tickets.")
else:
    print("RESULT: not significant. Could be luck.")

print("\n" + "=" * 55)
print("STEP F: VISUALIZATIONS")
print("=" * 55)
# Chart 1: spend distribution before capping context
fig, ax = plt.subplots(figsize=(7, 4))
ax.hist(df["monthly_spend"], bins=30, color="#4C72B0", edgecolor="white")
ax.set_title("Monthly Spend Distribution (outliers capped)")
ax.set_xlabel("Monthly spend ($)")
ax.set_ylabel("Number of customers")
fig.tight_layout()
fig.savefig("chart_spend.png", dpi=100)
print("Saved chart_spend.png")

# Chart 2: churn rate by support-ticket count
by_tickets = df.groupby("support_tickets")["churned"].mean()
fig, ax = plt.subplots(figsize=(7, 4))
ax.bar(by_tickets.index, by_tickets.values, color="#C44E52")
ax.set_title("Churn Rate by Number of Support Tickets")
ax.set_xlabel("Support tickets filed")
ax.set_ylabel("Churn rate")
fig.tight_layout()
fig.savefig("chart_churn.png", dpi=100)
print("Saved chart_churn.png")

print("\nAnalysis complete.")
```

Press `Esc`, type `:wq`, press Enter to save and quit.

---

## Step 7: Run the analysis

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python analyze.py
```

Expected output (yours will differ, truncated):

```
=======================================================
STEP A: PROFILE THE DATA
=======================================================
Rows: 1000, Columns: ['channel', 'age', 'monthly_spend', 'support_tickets', 'churned']
...
=======================================================
STEP B: MISSING VALUES
=======================================================
channel             0
age                40
monthly_spend       0
churned             0
support_tickets     0
dtype: int64

Filled missing ages with median = 39.0
...
=======================================================
STEP C: OUTLIERS (IQR method)
=======================================================
Q1=52.91, Q3=89.56, IQR=36.65, upper fence=144.54
Found 4 spend outliers above the fence:
     monthly_spend
7          9999.00
123        8500.00
255         154.19
835         144.77
Capped outliers at the upper fence.
...
=======================================================
STEP E: HYPOTHESIS TEST
=======================================================
Mean tickets - churned: 1.94, retained: 1.11
t-statistic: 6.524, p-value: 0.00000
RESULT: statistically significant (p < 0.05). Churned customers file more tickets.
...
Saved chart_spend.png
Saved chart_churn.png

Analysis complete.
```

The exact numbers will vary, but the shape holds: 40 missing ages filled, 2 huge outliers caught and capped, support tickets significantly higher for churned customers.

---

## Step 8: Confirm the charts were created

Still on your **lab server**, as **ec2-user**:

```bash
ls -lh chart_spend.png chart_churn.png
```

`ls -lh` lists the files with human-readable sizes (`-l` long format, `-h` human sizes).

Expected output (yours will differ):

```
-rw-rw-r-- 1 ec2-user ec2-user 24K Jul 25 14:02 chart_churn.png
-rw-rw-r-- 1 ec2-user ec2-user 31K Jul 25 14:02 chart_spend.png
```

Two PNG files, a few dozen KB each. If you have SCP access you can copy them to your laptop to view; on the server, existence and non-zero size confirm success.

---

## Step 9: Write the executive summary

The technical work is only half the job. Now translate it for someone who will never read the code. Open a plain-text file:

```bash
vi executive-summary.md
```

Press `i` and write your own summary based on YOUR numbers. Use this structure as a guide (do not copy blindly - use what your run produced):

```markdown
# Customer Churn: What the Data Says

## The bottom line
Customers who contact support more often are far more likely to leave.
This relationship is strong and unlikely to be chance.

## What we found
- We analyzed 1,000 customers. About 4% of records had a missing age,
  which we filled with the typical (median) value.
- Two spend records were clearly data-entry errors ($9,999 and $8,500)
  and were corrected before analysis, so they did not distort the averages.
- Churned customers filed nearly twice as many support tickets on average
  as customers who stayed (about 2.0 vs 1.1).
- This difference is statistically significant, meaning it is very unlikely
  to be a fluke of who happened to be in our sample.

## What we recommend
- Treat a rising support-ticket count as an early warning of churn.
- Reach out proactively to customers after their second ticket.

## What we are NOT claiming
- We found a correlation, not proof of cause. It is possible that unhappy
  customers both file tickets and leave for the same underlying reason.
  A controlled follow-up (see the A/B test in the USE lab) would test whether
  faster support actually reduces churn.
```

Press `Esc`, type `:wq`, press Enter.

Note the last section. Refusing to overclaim - correlation is not causation (Concepts 2.4) - is what makes an executive trust you. That honesty is the deliverable.

---

## What you accomplished

- Profiled a messy dataset and described its shape, types, and summary stats.
- Found and handled missing values (median fill) and outliers (IQR cap) with justified choices.
- Computed correlations and identified the strongest driver of the outcome.
- Ran a real hypothesis test and interpreted the p-value correctly.
- Produced two charts and a plain-language executive summary that separates correlation from causation.

You have done the core loop of an AI/data consultant. Next: the second BUILD lab, where you implement cosine similarity and gradient descent by hand.
