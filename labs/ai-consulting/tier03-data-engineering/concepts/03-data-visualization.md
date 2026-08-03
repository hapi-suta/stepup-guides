# Concepts 3.3: Data Visualization for AI

**Tier 3 - Data analysis and data engineering.** Teaching reference. A chart is how you make a stakeholder feel a number. As an AI consultant you will show clients what the data says and how a model performs - and you must do it honestly, because a chart can lie faster than any sentence. This doc covers the handful of chart types you actually need, plus how to spot and avoid misleading ones.

**Who this is for:** DBAs who read dashboards but have rarely built one from raw data. matplotlib is the base library everything else sits on. Learn it and Seaborn, Plotly, and pandas plotting all make sense.

**Run the snippets:** on your **lab server** (CentOS Stream 9), as **ec2-user**, inside a virtual environment with matplotlib installed. The server is headless (no screen), so we always save charts to files instead of showing a window.

```bash
python3.12
```

Every snippet assumes:

```python
import matplotlib
matplotlib.use("Agg")   # "Agg" draws to files, never tries to open a window
import matplotlib.pyplot as plt
import numpy as np
```

`matplotlib.use("Agg")` must come before `import ... pyplot`. On a server with no display, skipping it gives a confusing error - this line is the fix.

---

## 1. The mental model

Every matplotlib chart has two objects:

- **Figure** - the whole canvas (the sheet of paper).
- **Axes** - one plot on that canvas (the actual chart with its own x and y).

You create both with `fig, ax = plt.subplots()`, draw on `ax`, then save `fig`. That pattern handles 95% of what you need.

```python
fig, ax = plt.subplots(figsize=(6, 4))   # 6 inches wide, 4 tall
ax.plot([1, 2, 3], [10, 20, 15])
ax.set_title("My first chart")
ax.set_xlabel("x")
ax.set_ylabel("y")
fig.savefig("first.png", dpi=100, bbox_inches="tight")
plt.close(fig)   # free the memory - important in loops and scripts
```

`bbox_inches="tight"` trims wasted whitespace. `plt.close(fig)` matters: in a pipeline that draws many charts, forgetting it leaks memory until the job dies.

---

## 2. Histogram - the shape of one number

A histogram bins a single numeric column and shows how often each range occurs. It is the fastest way to see distribution: skew, outliers, whether it is one hump or two.

```python
import numpy as np
rng = np.random.default_rng(42)
latency = rng.normal(200, 40, size=1000)   # response times in ms
fig, ax = plt.subplots(figsize=(6, 4))
ax.hist(latency, bins=30, color="steelblue", edgecolor="white")
ax.set_title("Response latency distribution")
ax.set_xlabel("Latency (ms)")
ax.set_ylabel("Count")
fig.savefig("hist.png", dpi=100, bbox_inches="tight")
plt.close(fig)
```

When to reach for it: "what does this column look like?" Bimodal (two humps) often means two hidden populations mixed together - a signal worth chasing. Too few bins hides structure; too many turns it into noise. Around 20-40 bins is a sane start.

---

## 3. Scatter - the relationship between two numbers

A scatter plot puts one variable on x, another on y, one dot per row. It is how you eyeball correlation before you compute it.

```python
import numpy as np
rng = np.random.default_rng(0)
age = rng.integers(18, 70, size=200)
spend = age * 2 + rng.normal(0, 15, size=200)   # spend rises with age plus noise
fig, ax = plt.subplots(figsize=(6, 4))
ax.scatter(age, spend, alpha=0.5, s=20)   # alpha=transparency, s=dot size
ax.set_title("Spend vs age")
ax.set_xlabel("Age")
ax.set_ylabel("Monthly spend")
fig.savefig("scatter.png", dpi=100, bbox_inches="tight")
plt.close(fig)
```

`alpha=0.5` makes overlapping dots readable - with thousands of points, solid dots become a blob. A visible upward tilt means positive correlation. Remember Concepts 2.4: correlation is not causation. The chart shows the pattern; it does not explain it.

---

## 4. Line - change over time

A line chart connects points in order, so it is for time series and trends. The x-axis should be ordered (usually dates); a line over an unordered category is misleading.

```python
import numpy as np
months = np.arange(1, 13)
revenue = np.array([100, 110, 108, 130, 145, 160, 158, 170, 185, 190, 210, 230])
fig, ax = plt.subplots(figsize=(7, 4))
ax.plot(months, revenue, marker="o", color="darkgreen")
ax.set_title("Monthly revenue 2026")
ax.set_xlabel("Month")
ax.set_ylabel("Revenue ($k)")
ax.grid(True, alpha=0.3)
fig.savefig("line.png", dpi=100, bbox_inches="tight")
plt.close(fig)
```

`marker="o"` puts a dot on each real data point so nobody mistakes an interpolated line for measured values. A faint grid (`alpha=0.3`) helps readers read values without dominating the chart.

---

## 5. Bar - comparing categories

Bars compare a value across discrete groups. Use bars for categories (regions, products), lines for time.

```python
regions = ["East", "West", "North", "South"]
sales = [410, 320, 280, 500]
fig, ax = plt.subplots(figsize=(6, 4))
ax.bar(regions, sales, color="slateblue")
ax.set_title("Sales by region")
ax.set_ylabel("Sales ($k)")
fig.savefig("bar.png", dpi=100, bbox_inches="tight")
plt.close(fig)
```

The one rule that matters: **bar charts must start the y-axis at zero.** Starting higher exaggerates small differences into big-looking ones - the most common way a chart lies (see section 8).

---

## 6. Box plot - distribution and outliers at a glance

A box plot summarizes a distribution with the five-number summary: the first quartile, the median, and the third quartile form the box, and two whiskers reach out toward the extremes. In matplotlib the whiskers stop at the most distant point still within 1.5 times the interquartile range (not necessarily the true min and max), and points beyond the whiskers are flagged as outliers (fliers). It is the fastest way to compare groups and spot anomalies.

```python
import numpy as np
rng = np.random.default_rng(1)
group_a = rng.normal(50, 10, size=100)
group_b = rng.normal(60, 20, size=100)
group_b = np.append(group_b, [150, 160])   # two outliers
fig, ax = plt.subplots(figsize=(6, 4))
ax.boxplot([group_a, group_b], tick_labels=["A", "B"])   # tick_labels is the current name
ax.set_title("Score distribution by group")
ax.set_ylabel("Score")
fig.savefig("box.png", dpi=100, bbox_inches="tight")
plt.close(fig)
```

The line inside the box is the median. The box spans the middle 50% (the interquartile range, IQR). By default matplotlib draws the whiskers out to the last data point within 1.5 * IQR of the box, and anything past that is drawn as a separate flier point - so "outlier" here has a precise definition, not a visual guess (see: matplotlib boxplot docs). Box plots side by side answer "is group B really higher, or just more spread out?"

Note on the argument name: use `tick_labels=` (as above), not `labels=`. The `labels` parameter was renamed to `tick_labels` in Matplotlib 3.9 and the old name is deprecated and slated for removal in 3.11 (see: Matplotlib 3.9 API changes).

---

## 7. Confusion matrix - reading a classifier

When you evaluate a model that predicts categories (spam or not, fraud or not), a confusion matrix is the standard scorecard. Rows are the truth, columns are the prediction; the diagonal is "got it right."

```python
import numpy as np
# rows = actual, cols = predicted; classes: Not spam (0), Spam (1)
cm = np.array([[85, 5],    # 85 real not-spam correct, 5 wrongly flagged (false positives)
               [10, 40]])  # 10 real spam missed (false negatives), 40 caught
fig, ax = plt.subplots(figsize=(5, 4))
im = ax.imshow(cm, cmap="Blues")
ax.set_xticks([0, 1]); ax.set_xticklabels(["Not spam", "Spam"])
ax.set_yticks([0, 1]); ax.set_yticklabels(["Not spam", "Spam"])
ax.set_xlabel("Predicted"); ax.set_ylabel("Actual")
for i in range(2):
    for j in range(2):
        ax.text(j, i, cm[i, j], ha="center", va="center",
                color="white" if cm[i, j] > 50 else "black")
ax.set_title("Confusion matrix")
fig.savefig("confusion.png", dpi=100, bbox_inches="tight")
plt.close(fig)
```

Reading it: 5 false positives (real mail flagged as spam - annoying) and 10 false negatives (real spam that got through - risky). Which error is worse depends on the business. For fraud, a missed fraud (false negative) may cost far more than a false alarm, so you tune the model to accept more false positives. The confusion matrix is where you have that conversation with a client, in concrete counts, not abstract accuracy.

---

## 8. Misleading charts - how to lie, so you can refuse to

You will be handed charts that mislead, sometimes on purpose. Know the tricks:

- **Truncated y-axis.** A bar chart starting at 90 instead of 0 turns a 91-vs-93 tie into a "twice as tall" story. Fix: bars start at zero.
- **Dual y-axes.** Two lines on two different scales can be lined up to fake a relationship. Fix: distrust any chart with two y-axes; ask for both on the same scale.
- **Cherry-picked range.** Showing revenue only from the good quarter hides the year-long decline. Fix: ask "why does the x-axis start here?"
- **3-D and pie charts.** 3-D perspective distorts sizes; pies make it hard to compare slices. Fix: use a flat bar chart instead.
- **Cumulative counts.** A "total users ever" line only ever goes up and hides that new signups are falling. Fix: ask for the per-period rate, not the running total.
- **Missing baseline or sample size.** "Satisfaction up 40%" from 5 to 7 responses is noise. Fix: always show n.

The consultant's job is often to redraw a client's misleading chart honestly and explain the difference. That single act builds more trust than any model you ship.

---

## 9. Practical rules for every chart

- **Always label** the title, both axes (with units), and the source. An unlabeled chart is not evidence.
- **One message per chart.** If you cannot say the takeaway in a sentence, split it.
- **Color with meaning, not decoration.** Reserve red for bad/attention. Do not use ten colors because you can.
- **Save at `dpi=100` or higher** with `bbox_inches="tight"` so it looks sharp in a slide.
- **Close every figure** (`plt.close(fig)`) in scripts and loops or you leak memory.

---

## 10. Why this matters for AI

- You will present model performance to non-technical clients constantly. A confusion matrix and a well-chosen bar chart decide whether they trust the model.
- Exploratory charts (histogram, scatter, box) are how you find the data problems from Concepts 3.4 before they reach a model.
- Being the person in the room who spots a misleading chart - and can redraw it straight - is a durable reputation. Models come and go; honest analysis is why clients call you back.

You do not need to be a designer. You need five chart types, the discipline to label them, and the honesty to refuse to lie with the y-axis.

---

## References

- Matplotlib Figure/Axes and the object-oriented interface - https://matplotlib.org/stable/users/explain/quick_start.html
- Matplotlib pyplot / Axes API (`hist`, `scatter`, `plot`, `bar`, `boxplot`, `imshow`) - https://matplotlib.org/stable/api/axes_api.html
- Matplotlib `Axes.boxplot` (whiskers, IQR, fliers, `tick_labels`) - https://matplotlib.org/stable/api/_as_gen/matplotlib.axes.Axes.boxplot.html
- Matplotlib 3.9.0 API changes (`labels` -> `tick_labels`) - https://matplotlib.org/stable/api/prev_api_changes/api_changes_3.9.0.html
- Matplotlib backends (the `Agg` non-interactive backend) - https://matplotlib.org/stable/users/explain/figure/backends.html

Snippets were checked on Matplotlib 3.10.x (Python 3.12). The `Agg` backend renders to files with no display, which is why it is set before importing `pyplot` on a headless server.
