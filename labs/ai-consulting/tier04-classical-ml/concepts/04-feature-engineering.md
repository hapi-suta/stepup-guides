# Concepts 4.4: Feature Engineering

**Tier 4 - Classical machine learning.** Teaching reference. Feature engineering is the craft of turning raw data into signals a model can actually learn from. It is where most of the real gains in a project come from - more than the choice of algorithm. Good features can make a simple model beat a fancy model fed raw junk.

**Who this is for:** DBAs. You already reshape data constantly - computed columns, casts, aggregations, joins to enrich a row. Feature engineering is the same instinct, aimed at making each row maximally informative to a model.

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import numpy as np` and `import pandas as pd`.

---

## 1. Why features matter more than the model

Models are literal. They only know what you feed them. A raw timestamp `2026-07-25 14:03:11` means nothing to most models, but "it was a Saturday afternoon" might be a strong signal. Extracting that signal is your job, not the model's.

The rule of thumb: a good feature is one that carries real information about the answer, in a form the model can use. Most of an ML project's payoff hides here.

---

## 2. Numeric transforms

Raw numbers sometimes need reshaping so the model can use them well.

- **Log transform:** when a column is heavily skewed (a few huge values, many small ones - income, page views, prices), taking the log squashes the giants and spreads out the crowd. Many models behave better on a more even spread.
- **Binning:** turn a continuous number into buckets (age -> "under 18 / 18-35 / 36-65 / 65+"). Useful when the effect is not smooth, or to reduce noise.
- **Ratios and interactions:** combine columns into a more meaningful one. `debt / income` often beats debt and income separately.

```python
import numpy as np
income = np.array([30000, 45000, 60000, 250000, 1000000])
log_income = np.log1p(income)   # log1p handles the +1 so 0 is safe
print(np.round(log_income, 2))
```

Expected output:

```
[10.31 10.71 11.   12.43 13.82]
```

Notice how the raw gap between 250k and 1M (750,000) shrinks to about 1.4 in log space, while the small incomes stay meaningfully spread. The skew is tamed. Use `log1p` (log of 1 + x) so a value of 0 does not blow up.

---

## 3. Categorical encoding

Models need numbers, but many columns are categories (country, product_type, status). You have to encode them, and how you do it matters.

- **One-hot encoding:** make one 0/1 column per category. `color` with values red/green/blue becomes three columns `color_red`, `color_green`, `color_blue`. Safe default for categories with NO natural order. In a real pipeline prefer sklearn's `OneHotEncoder` (from `sklearn.preprocessing`) over pandas `get_dummies`, because the encoder remembers the categories seen at fit time and reapplies them to new data, and its `handle_unknown="ignore"` option copes with categories that only show up in production (see: scikit-learn OneHotEncoder API). `get_dummies` is fine for the quick example below.
- **Ordinal encoding:** map ordered categories to numbers - `small=0, medium=1, large=2`. Only use when the order is real, because the model will treat the numbers as distances.
- **Target encoding:** replace each category with the average target value for that category (e.g. average churn rate per country). Powerful for high-cardinality columns, but dangerous - it can leak the answer if you compute it on the whole dataset instead of just the training folds.

**Cardinality caution:** one-hot on a column with 5,000 distinct values (like zip code) explodes into 5,000 columns. That is slow, sparse, and noisy. For high-cardinality columns, group rare values into "other," or use target encoding (carefully), or a frequency count.

---

## 4. Scaling and normalization

Many algorithms compare distances or sum weighted features. If one column runs 0-1 and another runs 0-1,000,000, the big one silently dominates. Scaling puts columns on comparable ranges.

- **StandardScaler:** rescales each column to mean 0 and standard deviation 1 by subtracting the column mean and dividing by the column standard deviation - `z = (x - mean) / std` (see: scikit-learn StandardScaler API). The common default. It fits the mean and std on the training data (`with_mean=True`, `with_std=True` by default), then applies the same shift and scale to new data.
- **MinMaxScaler:** squeezes each column into a fixed range, `feature_range=(0, 1)` by default. Good when you need bounded values.

**When scaling matters:**

- **Matters a lot:** KNN, SVM, k-means, PCA, logistic/linear regression with regularization, neural nets. Anything distance-based or gradient-based.
- **Does NOT matter:** decision trees, random forests, gradient boosting. Trees split on thresholds one column at a time, so the scale of a column is irrelevant.

So if you are running a random forest, do not bother scaling. If you are running KNN or SVM, scaling is mandatory or your model is broken.

---

## 5. A worked example - one-hot plus scaling

On your **lab server**, as **ec2-user**:

```python
import pandas as pd
from sklearn.preprocessing import StandardScaler

df = pd.DataFrame({
    "age":    [25, 40, 35, 50],
    "salary": [50000, 80000, 62000, 120000],
    "dept":   ["sales", "eng", "sales", "eng"],
})

# 1) one-hot encode the categorical column
df_encoded = pd.get_dummies(df, columns=["dept"], dtype=int)

# 2) scale the numeric columns (fit only on these two)
scaler = StandardScaler()
df_encoded[["age", "salary"]] = scaler.fit_transform(
    df_encoded[["age", "salary"]]
)

print(df_encoded.round(2))
```

Expected output (yours will differ slightly):

```
    age  salary  dept_eng  dept_sales
0 -1.28   -0.95         0           1
1  0.34    0.24         1           0
2 -0.21   -0.47         0           1
3  1.15    1.18         1           0
```

The `dept` column became two 0/1 columns. `age` and `salary` are now centered near 0 with a small spread, so neither drowns the other. This is model-ready data.

---

## 6. Imputation - handling missing values

Real data has holes: NULLs, blanks, "N/A". Most models cannot ingest a missing value, so you fill it in (impute) or drop it.

- **Numeric columns:** fill with the **mean** (if roughly symmetric) or the **median** (safer with outliers or skew).
- **Categorical columns:** fill with the **most frequent** value, or with a literal category called "missing" (sometimes missingness itself is a signal).
- **Dropping rows:** fine if only a tiny fraction is missing. Dangerous if you would throw away half your data or if the missing rows are special.

sklearn's `SimpleImputer(strategy="median")` does this cleanly. And crucially: compute the fill value on TRAIN only (see leakage below).

---

## 7. Date and time features

A raw timestamp is nearly useless to most models. Break it into parts that carry meaning:

- day of month, month, quarter, year
- day of week (Monday-Sunday)
- is_weekend (0/1)
- hour of day
- is_holiday (0/1)
- days since some reference event (e.g. days since signup)

```python
import pandas as pd
s = pd.to_datetime(pd.Series(["2026-07-25", "2026-12-25", "2026-03-02"]))
out = pd.DataFrame({
    "month":      s.dt.month,
    "weekday":    s.dt.day_name(),
    "is_weekend": (s.dt.weekday >= 5).astype(int),
})
print(out)
```

Expected output:

```
   month   weekday  is_weekend
0      7  Saturday           1
1     12    Friday           0
2      3    Monday           0
```

Now the model can learn "weekends behave differently" - something it could never see from the raw string.

---

## 8. Text features (high level)

Free text (reviews, tickets, emails) must become numbers too.

- **Bag of words:** count how many times each word appears in each document. The document becomes a long vector of word counts.
- **TF-IDF:** like bag of words, but down-weights words that appear everywhere (the, and, is) and up-weights words that are rare and therefore distinctive. Usually beats plain counts.

Both produce very wide, mostly-zero (sparse) matrices - one column per word in the vocabulary. Naive Bayes and linear models handle these well (Concepts 4.2). This is the classical approach; modern embeddings are a later-tier topic.

---

## 9. Feature selection - fewer can be better

More features are not always better. Useless or redundant columns add noise, slow training, and can worsen accuracy (especially for KNN and other distance methods - the "curse of dimensionality").

Ways to trim:

- Drop columns with almost no variation (nearly constant).
- Drop one of any pair that is highly correlated with another (they carry the same signal).
- Use a model's built-in importance scores (random forests report feature importance) and keep the top ones.
- Use PCA (Concepts 4.3) to compress many columns into a few.

The goal: keep the signal, drop the noise. A leaner feature set often generalizes better and is easier to maintain.

---

## 10. Leakage prevention - the cardinal sin

**Data leakage** is when information that would not be available at prediction time sneaks into training. It makes your model look amazing in testing and fail in production. Two forms to guard against:

- **Preprocessing leakage:** fit your scalers, encoders, and imputers on the TRAINING data only, then apply them to test/production. If you `fit` a scaler on the whole dataset, the test rows influenced the scaling, and your test score is a lie. In sklearn: `fit_transform` on train, `transform` (not fit) on test. Pipelines enforce this automatically.
- **Time-based leakage:** if predictions are about the future, never let future rows train the model. Split by time (train on Jan-Jun, test on Jul), not by random shuffle. A feature computed using data from after the prediction moment is leakage too (e.g. using "total lifetime spend" to predict an early event).

If a model scores suspiciously well (99% on a hard problem), suspect leakage before you celebrate. More on this in Concepts 4.6.

---

## 11. Key takeaways

- Good features often matter more than the choice of algorithm.
- Log-transform skewed numbers; bin or combine when it adds meaning.
- One-hot for unordered categories, ordinal only for real orders; watch cardinality.
- Scale for KNN / SVM / k-means / PCA / regularized linear models; do NOT bother for trees and forests.
- Impute missing values (median for numbers, most-frequent for categories), fitting on train only.
- Explode dates into weekday, month, is_weekend, hour - the raw timestamp is dead weight.
- Turn text into TF-IDF or bag-of-words vectors.
- Fewer, cleaner features often beat a pile of noisy ones.
- Prevent leakage: fit transforms on train only, split by time when predicting the future. A too-good score usually means leakage.

---

## References

- scikit-learn User Guide, Preprocessing data (scaling, encoding, transforms): https://scikit-learn.org/stable/modules/preprocessing.html
- scikit-learn API, `StandardScaler` (`z = (x - mean) / std`; `with_mean=True`, `with_std=True`): https://scikit-learn.org/stable/modules/generated/sklearn.preprocessing.StandardScaler.html
- scikit-learn API, `MinMaxScaler` (default `feature_range=(0, 1)`): https://scikit-learn.org/stable/modules/generated/sklearn.preprocessing.MinMaxScaler.html
- scikit-learn API, `OneHotEncoder` (`handle_unknown`, remembers fit-time categories): https://scikit-learn.org/stable/modules/generated/sklearn.preprocessing.OneHotEncoder.html
- scikit-learn API, `SimpleImputer` (strategies: mean, median, most_frequent, constant): https://scikit-learn.org/stable/modules/generated/sklearn.impute.SimpleImputer.html
- scikit-learn User Guide, Text feature extraction (bag of words, TF-IDF): https://scikit-learn.org/stable/modules/feature_extraction.html#text-feature-extraction
- scikit-learn User Guide, Common pitfalls / data leakage: https://scikit-learn.org/stable/common_pitfalls.html
- pandas API, `get_dummies`: https://pandas.pydata.org/docs/reference/api/pandas.get_dummies.html
