# Concepts 2.4: Statistics for AI

**Tier 2 - Mathematics and statistics for AI.** Teaching reference. Probability (2.3) asks "given the rules, what could happen?" Statistics asks the reverse: "given what happened, what are the rules?" This is the skill that separates a consultant who ships trustworthy conclusions from one who ships confident nonsense. As an AI consultant you will be asked "is this result real?" constantly. This is how you answer.

**Who this is for:** DBAs. You run `AVG()`, `PERCENTILE_CONT()`, and `CORR()` in SQL already. Here you learn what they mean and when they lie.

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import numpy as np`.

---

## 1. Population vs sample

- The **population** is everyone or everything you care about: all customers, all queries ever run.
- A **sample** is the subset you actually measured: the 500 customers you surveyed.

You almost never have the whole population. You work with a sample and try to conclude something about the population. Every risk in statistics comes from this gap: your sample might not represent the population. Keep this distinction burned in - most bad analysis is a sample masquerading as the population.

---

## 2. Mean, median, mode

Three ways to say "the typical value":

- **Mean:** the average. Add everything, divide by count. Sensitive to outliers.
- **Median:** the middle value when sorted. Half above, half below. Robust to outliers.
- **Mode:** the most common value.

```python
import numpy as np
salaries = np.array([50, 55, 60, 62, 65, 70, 500])  # thousands; last one is an exec
print("mean:", salaries.mean())
print("median:", np.median(salaries))
```

Expected output:

```
mean: 123.14285714285714
median: 62.0
```

One executive salary drags the mean up to 123k, but the median stays at a realistic 62k. This is why you report median income, median latency, median response time. When someone quotes an average, always ask about outliers. In AI, a mean latency of 200ms can hide a p99 of 4 seconds that is ruining the user experience.

---

## 3. Percentiles

A **percentile** is the value below which a given percentage of data falls. The p95 latency is the value that 95% of requests come in under. Percentiles are how you talk about tails - the slow requests, the extreme cases, the things averages hide.

```python
latencies = np.array([10, 12, 15, 18, 20, 25, 30, 45, 90, 400])  # milliseconds
print("p50 (median):", np.percentile(latencies, 50))
print("p95:", np.percentile(latencies, 95))
```

Expected output:

```
p50 (median): 22.5
p95: 260.5
```

Half the requests finish under 22.5ms, but 5% take longer than 260.5ms. As a DBA you live in p95 and p99. Carry that habit into AI: report tail latency for model inference, not just the average. (NumPy's default percentile method is `linear` interpolation between the two nearest ranks, which is why p95 lands between the 90 and 400 data points rather than exactly on one - see: numpy.percentile docs.)

---

## 4. Covariance and correlation

Both measure whether two variables move together.

- **Covariance** tells you the direction (positive = rise together, negative = one rises as the other falls) but its size depends on the units, so it is hard to interpret.
- **Correlation** rescales covariance to a clean range from -1 to +1:
  - `+1` = perfect positive relationship.
  - `0` = no linear relationship.
  - `-1` = perfect negative relationship.

```python
hours_studied = np.array([1, 2, 3, 4, 5, 6, 7, 8])
exam_score    = np.array([52, 58, 61, 67, 70, 76, 79, 85])
corr = np.corrcoef(hours_studied, exam_score)[0, 1]
print("correlation:", round(corr, 3))
```

Expected output:

```
correlation: 0.998
```

Almost a perfect line: more study, higher score. But be careful - the Pearson correlation `np.corrcoef` computes only catches **linear** relationships (see: NIST e-Handbook 1.3.5.11), and, critically, **correlation is not causation** (Concepts 2.4 SURVIVE scenario 3 drills this). Ice cream sales and drowning deaths correlate; ice cream does not cause drowning. Summer causes both.

---

## 5. Confidence intervals

A single estimate ("average order is $50") hides its uncertainty. A **confidence interval** gives a range plus a confidence level: "we are 95% confident the true average is between $47 and $53".

It means: if we repeated the sampling many times, about 95% of the intervals we build this way would contain the true value. Wider interval = less certain (small sample or high spread). Narrower = more certain.

```python
import numpy as np
sample = np.random.normal(loc=50, scale=10, size=200)
mean = sample.mean()
sem = sample.std(ddof=1) / np.sqrt(len(sample))   # standard error of the mean (ddof=1 = sample std, divide by n-1)
lo, hi = mean - 1.96 * sem, mean + 1.96 * sem      # 95% interval
print(f"mean {mean:.2f}, 95% CI [{lo:.2f}, {hi:.2f}]")
```

Expected output (yours will differ):

```
mean 49.83, 95% CI [48.44, 51.21]
```

The `1.96` is the magic number for 95% under a normal distribution: 95% of a standard normal's area lies within plus or minus 1.96 standard deviations of the mean (see: Wikipedia 97.5th percentile point). Note this z-based interval assumes a large sample; for small samples the more exact choice is the t-distribution critical value, which for a few hundred observations is already about 1.97, effectively the same (see: NIST e-Handbook 1.3.5.2). When you present results to an executive, give the interval, not just the point estimate. "Conversion improved 2%, plus or minus 3%" is honest; "conversion improved 2%" pretends to a precision you do not have.

---

## 6. Hypothesis testing and statistical significance

The core question: "Could this result be pure luck?"

You start with a **null hypothesis** - the boring assumption that there is no real effect (the new button did not change conversion). Then you ask: if the null were true, how surprising is the data I saw? That surprise is measured by the **p-value**.

- A **small p-value** (conventionally below 0.05) means "this data would be very unlikely if there were no real effect" - so you reject the null and call the result **statistically significant**.
- A **large p-value** means "this could easily be luck" - you do not have evidence of a real effect.

```python
from scipy import stats
group_a = np.random.normal(100, 15, 500)          # control
group_b = np.random.normal(103, 15, 500)          # treatment, small real effect
t_stat, p_value = stats.ttest_ind(group_a, group_b)  # independent two-sample t-test; defaults to equal_var=True
print("p-value:", round(p_value, 4))
```

Expected output (yours will differ):

```
p-value: 0.0018
```

A p-value of 0.0018 is well below 0.05, so we would call this difference significant. Two warnings you must internalize:

- **Significant does not mean large or important.** With a huge sample, a tiny meaningless difference can be "significant". Always report the effect size too.
- **p < 0.05 is a convention, not a law of nature.** It still means roughly a 1-in-20 chance of a false alarm. Run enough tests and some will "pass" by luck.

One technical note: `ttest_ind` defaults to `equal_var=True` (Student's t-test, assumes both groups have the same variance). If you are not sure the variances match, pass `equal_var=False` for Welch's t-test, which is the safer default in practice (see: scipy.stats.ttest_ind docs).

---

## 7. Sampling bias

**Sampling bias** happens when your sample does not represent the population. If you survey app satisfaction only among users who opened the app today, you miss everyone who quit in frustration - your results will look far rosier than reality. The math can be flawless and the conclusion still wrong, because the data going in was skewed. This is the single most common way a "significant" result is actually garbage, and it is the subject of a SURVIVE scenario in this tier.

---

## 8. Selection bias

**Selection bias** is the broader family: any time the way you chose what to measure distorts the result. Classic case: in World War II, engineers wanted to armor the areas of returning planes that had the most bullet holes. Abraham Wald pointed out the opposite - armor the areas with no holes, because planes hit there never made it back. The sample (planes that returned) was selected by survival. In AI you meet this as **survivorship bias** in training data: you only have data on the loans you approved, the customers you kept, the queries that completed.

---

## 9. Experimental design and A/B testing

The cleanest way to establish cause is a controlled experiment. An **A/B test** does exactly this:

1. Randomly split users into group A (control, old version) and group B (treatment, new version). Randomization is what breaks selection bias - it makes the groups comparable on everything except the change.
2. Show each group its version and measure the metric you care about (conversion, clicks, revenue).
3. Use a hypothesis test to check whether the difference is bigger than luck would produce.

Good design also means: decide your sample size and metric **before** you start (not after you peek), run long enough to cover normal variation (a full week to average out weekdays vs weekends), and change only one thing at a time so you know what caused the difference. You will run a full A/B test in the USE lab.

---

## Key takeaways

- Population = all of it; sample = what you measured. Never confuse the two.
- Mean is pulled by outliers; median and percentiles (p95/p99) tell the real story of tails.
- Correlation runs -1 to +1 and is NOT causation.
- A confidence interval reports honesty about uncertainty; always give the range.
- A small p-value (below 0.05) means "probably not luck", but significant is not the same as important.
- Sampling and selection bias can wreck a mathematically perfect analysis; randomized A/B tests are the fix.

Next: **Concepts 2.5 - Calculus intuition**, the last piece, where we learn how models actually learn.

---

## References

- numpy.percentile (default `linear` method): https://numpy.org/doc/stable/reference/generated/numpy.percentile.html
- numpy.std / numpy.var (`ddof` parameter, sample vs population): https://numpy.org/doc/stable/reference/generated/numpy.std.html
- numpy.corrcoef (Pearson linear correlation): https://numpy.org/doc/stable/reference/generated/numpy.corrcoef.html
- scipy.stats.ttest_ind (signature, `equal_var` default): https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats.ttest_ind.html
- NIST/SEMATECH e-Handbook, correlation coefficient (linear only): https://www.itl.nist.gov/div898/handbook/eda/section3/eda35c.htm
- NIST/SEMATECH e-Handbook, confidence limits for the mean: https://www.itl.nist.gov/div898/handbook/eda/section3/eda352.htm
- 97.5th percentile point (why 1.96 for 95%): https://en.wikipedia.org/wiki/97.5th_percentile_point
