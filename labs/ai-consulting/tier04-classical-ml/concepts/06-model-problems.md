# Concepts 4.6: What Goes Wrong (Model Problems)

**Tier 4 - Classical machine learning.** Teaching reference. Most ML failures are not exotic. They are a handful of the same problems, over and over. Learn to name them, spot them, and fix them, and you will avoid the pitfalls that quietly sink real projects.

**Who this is for:** DBAs. You know the difference between "the query works on my test table" and "the query melts in production." Every problem here is a version of that gap: the model looks fine in the lab and disappoints in the real world.

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import numpy as np` and the `sklearn` imports shown inline.

---

## 1. Overfitting

The model memorized the training data instead of learning the general pattern. It aces the data it has seen and flops on anything new.

- **Analogy:** a student who memorized last year's exact exam answers. Change the questions and they are lost.
- **Cause:** model too complex for the amount of data (a deep tree, too many features, too little data).
- **How to detect:** training score is high but test score is much lower. That gap is the tell.
- **How to fix:** simplify the model (shallower tree, fewer features), get more training data, add regularization, use ensembles like random forests, or use cross-validation to catch it early.

Quick illustration - an unrestricted deep tree memorizing. On your **lab server**, as **ec2-user**:

```python
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from sklearn.tree import DecisionTreeClassifier

X, y = make_classification(n_samples=300, n_features=15,
                           n_informative=5, random_state=42)
X_tr, X_te, y_tr, y_te = train_test_split(
    X, y, test_size=0.30, random_state=42)

# no depth limit -> the tree can memorize the training set
tree = DecisionTreeClassifier(random_state=42)
tree.fit(X_tr, y_tr)

print("train accuracy:", round(tree.score(X_tr, y_tr), 2))
print("test  accuracy:", round(tree.score(X_te, y_te), 2))
```

Expected output (yours will differ slightly):

```
train accuracy: 0.99
test  accuracy: 0.71
```

Near-perfect on training (0.99), much worse on the test set (0.71). That gap of roughly 28 points is textbook overfitting. By default `DecisionTreeClassifier` has no `max_depth` limit, so it grows until leaves are pure - which is exactly what lets it memorize (see: scikit-learn DecisionTreeClassifier API). Limit the tree depth (`max_depth=4`) or switch to a random forest and the gap shrinks.

---

## 2. Underfitting

The opposite problem. The model is too simple to capture the real pattern, so it does poorly on BOTH training and test data.

- **Analogy:** trying to fit a straight line through data that clearly curves. It is wrong everywhere.
- **Cause:** model too simple, too few or too weak features, or too much regularization.
- **How to detect:** both training and test scores are low and similar. No gap, just bad.
- **How to fix:** use a more expressive model, add better features, reduce regularization, train longer.

---

## 3. The bias-variance tradeoff

Overfitting and underfitting are two ends of one dial:

- **High bias (underfitting):** the model is too rigid; it misses the pattern. Wrong in a consistent way.
- **High variance (overfitting):** the model is too flexible; it chases noise. Its answers swing wildly with small data changes.

The goal is the sweet spot in the middle - flexible enough to catch the real pattern, disciplined enough to ignore the noise. Every model choice (tree depth, number of features, regularization strength) is really you turning this one dial. You find the sweet spot by watching the train-vs-test gap as you adjust.

---

## 4. Class imbalance

One class vastly outnumbers the other (fraud is 1% of transactions, defects are 0.5% of parts). The model learns it can score high by just predicting the majority class and ignoring the rare one.

- **Cause:** the rare class is genuinely rare, so the model sees too few examples of it.
- **How to detect:** high accuracy but terrible recall on the rare class. Always check the confusion matrix (Concepts 4.5), not just accuracy.
- **How to fix:** use precision/recall/F1 instead of accuracy; oversample the minority (e.g. SMOTE, from the separate imbalanced-learn library) or undersample the majority; set `class_weight="balanced"` (supported by many sklearn estimators, e.g. LogisticRegression, RandomForestClassifier, SVC) so mistakes on the rare class cost more; adjust the decision threshold (see: scikit-learn User Guide).

---

## 5. Data leakage

Information that would not be available at prediction time sneaks into training. The model looks brilliant in testing and fails in production. This is the sneakiest and most damaging problem.

- **Examples:** fitting a scaler on the whole dataset before splitting; a feature like "account_closed_date" used to predict churn (it is only known after churn); using future data to predict the past.
- **Cause:** the pipeline lets test-time or future information touch training.
- **How to detect:** suspiciously high scores (99% on a hard problem). A single feature dominating importance. Performance that collapses in production.
- **How to fix:** fit all transforms on TRAIN only (`fit_transform` on train, `transform` on test); use sklearn Pipelines so this is automatic; split by time for time-dependent problems; audit each feature by asking "would I actually know this at prediction time?" See Concepts 4.4, section 10.

---

## 6. Concept drift

The world changes, so the relationship the model learned goes stale. A model trained on 2024 buying habits slowly gets worse as habits shift.

- **Analogy:** a spam filter trained before a new spam tactic existed. It was accurate; the spammers moved on.
- **Cause:** customer behavior, prices, seasonality, or the environment shift over time.
- **How to detect:** prediction quality slowly (or suddenly) degrades in production monitoring; the live data distribution moves away from the training distribution.
- **How to fix:** monitor performance continuously (Concepts 4.1, step 10); retrain regularly on fresh data; set up automated alerts when accuracy drops below a threshold. A model is not "set and forget."

---

## 7. Correlation vs causation

The model finds that two things move together, but that does not mean one causes the other. Models learn correlations; they say nothing about cause.

- **Classic example:** ice cream sales and drowning deaths rise together. Ice cream does not cause drowning; hot weather drives both.
- **Why it matters:** a model can PREDICT fine on correlation alone, but if you act on it as if it were causal, you make bad decisions. "People who cancel also called support twice" does not mean support calls cause cancellations - maybe unhappy customers do both.
- **How to handle:** use correlational models for prediction, but be very careful before recommending ACTIONS based on them. Establishing cause needs experiments (A/B tests), not just observed data.

---

## 8. Poor or noisy labels

If the answer key is wrong, the model learns the wrong thing. "Garbage in, garbage out" applies especially to labels.

- **Examples:** inconsistent human labeling ("is this review positive?" answered differently by different people); mislabeled training rows; labels derived from a flawed rule.
- **Cause:** rushed, ambiguous, or subjective labeling; automated labels from a buggy process.
- **How to detect:** a ceiling on accuracy that better models cannot break; disagreement between labelers; spot-checking flagged errors reveals the label was wrong, not the model.
- **How to fix:** write clear labeling guidelines; have multiple people label and measure their agreement; clean or re-label the worst offenders; remember the model can never be more accurate than its labels.

---

## 9. Proxy variables and fairness

A proxy variable is a feature that stands in for something you did not intend to use - often something sensitive like race, gender, or age. Even if you exclude the sensitive column, other columns can quietly encode it.

- **Example:** you drop "race" from a loan model, but "zip code" is strongly tied to race in your data, so the model discriminates anyway through the proxy.
- **Cause:** correlated features carry hidden information; historical data reflects historical bias, which the model faithfully reproduces.
- **How to detect:** test model outcomes across groups (does approval rate differ by a protected group?); check which features carry the most weight and ask what they might be proxying for.
- **How to fix:** audit for disparate outcomes, not just disparate inputs; remove or carefully handle proxy features; use fairness-aware techniques; involve humans for high-stakes decisions. Fairness is not automatic just because you deleted the obvious column.

---

## 10. Dataset shift (train vs production mismatch)

The data the model was trained on does not match the data it sees in production. Related to concept drift, but this is a mismatch from day one, not a slow change.

- **Examples:** trained on data from one region, deployed in another; trained on clean lab data, fed messy real-world inputs; a sensor recalibrated so its readings shifted.
- **Cause:** the training sample was not representative of production reality.
- **How to detect:** the model works great in testing and disappoints immediately on launch; the distributions of input features differ between your training data and live traffic.
- **How to fix:** make training data as representative of production as possible; compare feature distributions (train vs live) before and after deploy; retrain on real production data once you have it; keep monitoring.

---

## 11. A quick diagnosis table

- High train score, low test score -> **overfitting**.
- Low train AND low test score -> **underfitting**.
- High accuracy, low recall on the rare class -> **class imbalance**.
- Suspiciously perfect score -> **data leakage**.
- Was good, slowly getting worse in production -> **concept drift**.
- Great in testing, bad from day one in production -> **dataset shift** (or leakage).
- Model plateaus and cannot improve -> suspect **noisy labels**.
- Different outcomes across groups -> **proxy variables / fairness** issue.

---

## 12. Key takeaways

- Overfitting = memorized training data (high train, low test); simplify, add data, regularize.
- Underfitting = too simple (low train and test); add complexity and better features.
- Bias vs variance is one dial; aim for the middle by watching the train-test gap.
- Class imbalance breaks accuracy; use precision/recall and rebalance or reweight.
- Data leakage produces fake-great scores; fit transforms on train only and audit features.
- Concept drift and dataset shift both mean production data differs from training; monitor and retrain.
- Correlation is not causation; predict on it, but do not blindly act on it.
- Bad labels cap your accuracy; fix the answer key.
- Proxy variables can smuggle in bias; audit outcomes across groups, not just inputs.

---

## References

- scikit-learn User Guide, Underfitting vs. overfitting: https://scikit-learn.org/stable/auto_examples/model_selection/plot_underfitting_overfitting.html
- scikit-learn User Guide, Validation curves and bias-variance: https://scikit-learn.org/stable/modules/learning_curve.html
- scikit-learn API, `DecisionTreeClassifier` (default `max_depth=None`, grows until leaves are pure): https://scikit-learn.org/stable/modules/generated/sklearn.tree.DecisionTreeClassifier.html
- scikit-learn User Guide, Cross-validation (detecting overfitting): https://scikit-learn.org/stable/modules/cross_validation.html
- scikit-learn User Guide, Common pitfalls / data leakage: https://scikit-learn.org/stable/common_pitfalls.html
- scikit-learn API, `class_weight` on `LogisticRegression` (`class_weight="balanced"`): https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.LogisticRegression.html
- imbalanced-learn documentation (SMOTE and resampling, external library): https://imbalanced-learn.org/stable/references/generated/imblearn.over_sampling.SMOTE.html
