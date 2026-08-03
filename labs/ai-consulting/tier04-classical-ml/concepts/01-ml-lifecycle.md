# Concepts 4.1: The Machine Learning Lifecycle

**Tier 4 - Classical machine learning.** Teaching reference. Machine learning is not magic and it is not a single command. It is a project with stages, exactly like standing up a new database: you plan, you gather data, you build, you test, you deploy, and then you babysit it forever.

**Who this is for:** DBAs. You already run projects end to end - capacity planning, migration, cutover, monitoring. ML is the same discipline pointed at a different problem. If you skip a stage here you get the same kind of pain you get when you skip a backup test.

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import numpy as np` and `import pandas as pd` unless noted.

---

## 1. ML is a project, not a spell

People imagine ML as: pour data into a model, get answers. Reality: the model training call is often 1 line out of a project that is 90% data work and 10% math. The famous saying is "garbage in, garbage out". A perfect algorithm on bad data gives you confident nonsense.

Think of it like a query plan. The optimizer (the algorithm) is clever, but if your statistics are stale and your data is dirty, you get a terrible plan. In ML, your data IS the statistics.

The lifecycle below is 10 steps. You walk them roughly in order, but you loop back constantly. Steps 6, 7, and 8 (train, evaluate, tune) are a tight cycle you repeat many times.

---

## 2. Step 1 - Define the problem (is ML even the right tool?)

Before any code, write down in one plain sentence what you are predicting and why it matters. Example: "Predict which customers will cancel next month, so support can call them first."

Then ask the hardest question: **do you even need ML?** If a simple rule works ("flag any account with 0 logins in 30 days"), use the rule. ML earns its keep when the pattern is complex, changes over time, or hides in many columns at once.

- **Why it matters:** the whole project is judged against this sentence. No target, no project.
- **Common failure:** building a model when a `WHERE` clause would do. Or defining a fuzzy goal ("understand our customers") that can never be measured, so you can never say if you succeeded.

---

## 3. Step 2 - Collect and understand the data

Gather the raw data and then actually look at it. Count rows. Check ranges. Look at distributions. Find the weird stuff (negative ages, prices of 999999, timestamps from 1970).

This is exploratory data analysis (EDA). For a DBA it is the equivalent of `SELECT count(*)`, `min`, `max`, `distinct`, and eyeballing a sample before you trust a table.

- **Why it matters:** you cannot fix or model data you do not understand. Surprises found now are cheap; found in production they are expensive.
- **Common failure:** trusting the data dictionary instead of the data. The column called `active` is 40% NULL and nobody told you.

---

## 4. Step 3 - Clean and prepare the data

Handle missing values, remove duplicates, fix obvious errors, standardize formats (dates, units, categories spelled three different ways). This is the unglamorous majority of every ML project.

- **Why it matters:** models take numbers literally. A missing value or a typo of `10000` instead of `100` will drag predictions off course.
- **Common failure:** cleaning inconsistently, or cleaning the test data differently from the training data (that quietly ruins your evaluation - more on leakage in step 5 and Concepts 4.6).

---

## 5. Step 4 - Feature engineering

Turn raw columns into signals the model can use. Extract `weekday` from a timestamp, combine `height` and `weight` into a ratio, encode text categories as numbers. Good features often matter more than the choice of algorithm.

Feature engineering has its own concept doc (4.4) because it is that important.

- **Why it matters:** the model can only learn from what you feed it. Better features, better model, often by a lot.
- **Common failure:** creating a feature that secretly contains the answer (leakage), so your model looks brilliant in testing and is useless live.

---

## 6. Step 5 - Split the data (train / validation / test)

Never test a model on the same data it learned from. That is like grading students on the exact questions they got the answer key for. You split your rows into three buckets:

- **Train** (about 60-70%): the model learns from these.
- **Validation** (about 15-20%): you tune settings against these while building.
- **Test** (about 15-20%): touched ONCE, at the very end, to get an honest score.

The test set is sacred. If you peek at it while tuning, its score stops being honest.

- **Why it matters:** this is the only way to estimate how the model behaves on data it has never seen, which is the whole point.
- **Common failure:** shuffling time-ordered data so future rows leak into training, or using the test set to make decisions.

Here is the core split on a tiny synthetic dataset. On your **lab server**, as **ec2-user**:

```python
import numpy as np
from sklearn.model_selection import train_test_split

# 200 rows, 5 feature columns, 1 target column
rng = np.random.default_rng(42)
X = rng.normal(size=(200, 5))
y = rng.integers(0, 2, size=200)   # binary label: 0 or 1

# First carve off 20% as the final test set
X_temp, X_test, y_temp, y_test = train_test_split(
    X, y, test_size=0.20, random_state=42
)
# Then split the rest into train (75%) and validation (25%)
X_train, X_val, y_train, y_val = train_test_split(
    X_temp, y_temp, test_size=0.25, random_state=42
)

print("train:", X_train.shape, "val:", X_val.shape, "test:", X_test.shape)
```

Expected output:

```
train: (120, 5) val: (40, 5) test: (40, 5)
```

200 rows became 120 train, 40 validation, 40 test. Because we set `random_state=42`, you get the exact same split every time you run it. That reproducibility is not optional in ML; without it you cannot compare two experiments fairly. Note that `train_test_split` shuffles the rows before splitting by default (`shuffle=True`), which is why time-ordered data needs special care - see step 5 above (see: scikit-learn train_test_split API).

---

## 7. Step 6 - Choose and train models

Pick one or more algorithms and fit them to the training data. "Training" (or "fitting") means the algorithm adjusts its internal numbers until it predicts the training labels well.

Start simple. A logistic regression or a decision tree is a great baseline. If a simple model does fine, you are done. Only reach for heavier tools (random forests, gradient boosting) when the baseline is not good enough.

- **Why it matters:** a cheap baseline tells you if the problem is even learnable, and gives you a number to beat.
- **Common failure:** jumping straight to the fanciest model, which is harder to debug, slower, and often no better on tabular data.

Which algorithm to use is covered in Concepts 4.2 (supervised) and 4.3 (unsupervised).

---

## 8. Step 7 - Evaluate

Score the trained model on data it did not learn from (validation, then finally test). Use the right metric for the job. Accuracy is fine when classes are balanced and lies badly when they are not. A model that always predicts "not fraud" is 99.9% accurate and 100% useless.

Evaluation gets its own doc (4.5) because picking the wrong metric is one of the most common and expensive mistakes.

- **Why it matters:** this is how you know if the model is good, and good ENOUGH to ship.
- **Common failure:** reporting accuracy on an imbalanced problem and declaring victory.

---

## 9. Step 8 - Tune and iterate

Adjust the model's settings (hyperparameters), try better features, try another algorithm, and re-evaluate. This is the loop: train, evaluate, change one thing, repeat. Use the validation set here, not the test set.

- **Why it matters:** the first model is rarely the best. Steady iteration is where most of the gains come from.
- **Common failure:** tuning against the test set (which secretly overfits to it), or endless tweaking for a 0.2% gain nobody will notice.

---

## 10. Step 9 - Deploy

Put the model somewhere it can make predictions on new, live data - behind an API, in a batch job, inside an app. This is a software and ops problem as much as an ML one: versioning, latency, rollback, the same concerns you have deploying a schema change.

- **Why it matters:** a model in a notebook helps nobody. Value happens only when live data flows through it.
- **Common failure:** the training environment and the production environment compute features differently, so the live model sees different numbers than it trained on. This is called training-serving skew and it silently wrecks accuracy.

---

## 11. Step 10 - Monitor and maintain (retrain)

The world changes, so the data changes, so your model slowly goes stale. This is **concept drift** (Concepts 4.6). You monitor prediction quality over time and retrain on fresh data when it degrades.

- **Why it matters:** a model is not a "set and forget" object. It is more like an index that fragments; it needs maintenance.
- **Common failure:** deploying and walking away. Six months later the model is quietly worse than a coin flip and nobody noticed because nobody was watching.

---

## 12. The whole loop, at a glance

1. Define the problem - is ML even right?
2. Collect and understand data (EDA).
3. Clean and prepare data.
4. Feature engineering.
5. Split into train / validation / test.
6. Choose and train models.
7. Evaluate with the right metric.
8. Tune and iterate.
9. Deploy.
10. Monitor and retrain.

Steps 6-8 are a tight loop you repeat many times. Steps 1-5 decide whether that loop ever produces anything useful. Most failures happen in 1-5 (bad problem, bad data) or in 9-10 (deploy and forget), not in the algorithm itself.

---

## 13. Key takeaways

- ML is a project with stages, not a single training call.
- Data work (steps 2-5) is the majority of the effort and the majority of the risk.
- Always ask if a simple rule beats ML before building ML.
- The test set is sacred: touch it once, at the end.
- `random_state=42` makes experiments reproducible so you can compare them honestly.
- Start with a simple baseline model, then iterate.
- Deploy is not the finish line; monitoring and retraining never stop.

---

## References

- scikit-learn User Guide, Cross-validation and data splitting: https://scikit-learn.org/stable/modules/cross_validation.html
- scikit-learn API, `train_test_split` (default `test_size` complements `train_size`, both `None` -> test is 0.25; `shuffle=True` by default): https://scikit-learn.org/stable/modules/generated/sklearn.model_selection.train_test_split.html
