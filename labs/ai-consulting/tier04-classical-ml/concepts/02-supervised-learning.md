# Concepts 4.2: Supervised Learning

**Tier 4 - Classical machine learning.** Teaching reference. Supervised learning is learning from labeled examples. You show the model thousands of rows where you already know the answer, and it learns the pattern that maps inputs to answers. Then it predicts the answer for new rows it has never seen.

**Who this is for:** DBAs. Think of it like this: you have a table with a bunch of feature columns and one answer column. Supervised learning studies that table and learns to fill in the answer column for future rows.

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import numpy as np` and the relevant `sklearn` imports shown inline.

---

## 1. What "supervised" means

**Supervised** = the training data is labeled. Every example comes with the correct answer (the "label" or "target"). The model's job is to learn the relationship between the input columns (features) and that answer.

- Inputs (features): the columns you know - age, balance, num_logins.
- Output (label): the column you want to predict - churned yes/no, or next month's spend.

Contrast: unsupervised learning (Concepts 4.3) has no labels; it just finds structure. Supervised learning has an answer key.

---

## 2. Classification vs regression

There are two flavors of supervised learning, decided entirely by what kind of answer you want:

- **Classification** predicts a category. Spam or not spam. Churn or stay. Which of 5 product types. The output is a label from a fixed set.
- **Regression** predicts a number on a continuous scale. Next month's revenue. House price. Days until failure. The output is a quantity.

A quick test: if the answer is "which bucket?" it is classification. If the answer is "how much?" it is regression. Same data, different question. "Will this customer churn?" is classification; "how many days until they churn?" is regression.

---

## 3. Linear regression

The simplest regressor. It fits a straight line (or a flat plane in many dimensions) through the data. Prediction = a weighted sum of the features plus a constant.

- **Intuition:** "price goes up about $150 for every extra square foot." Each feature gets a weight; add them up.
- **When to use:** predicting a number, when the relationship is roughly linear and you want an explainable model. Great baseline.
- **Strengths:** fast, simple, the weights tell you exactly how each feature pushes the prediction.
- **Weaknesses:** assumes a straight-line relationship. Curvy or complex patterns break it. Sensitive to outliers, which drag the line.

---

## 4. Logistic regression

Despite the name, this is a CLASSIFIER, not a regressor. It predicts the probability that a row belongs to a class, then thresholds it (usually at 0.5) to pick a label.

- **Intuition:** it draws a boundary line and says "everything on this side is probably class 1." It outputs a probability like 0.92, not just a yes/no.
- **When to use:** the go-to baseline for classification, especially yes/no problems. Fast and explainable.
- **Strengths:** simple, quick, gives calibrated-ish probabilities, weights are interpretable.
- **Weaknesses:** only draws straight boundaries. If the two classes are tangled in a curvy way, it struggles.

One thing that surprises people: sklearn's `LogisticRegression` applies L2 regularization by default (`penalty="l2"`, `C=1.0`, default solver `lbfgs`), so it is a regularized linear model out of the box - which means it, too, benefits from scaled features (see: scikit-learn LogisticRegression API and Concepts 4.4).

Tiny example on a synthetic dataset. On your **lab server**, as **ec2-user**:

```python
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression

X, y = make_classification(
    n_samples=400, n_features=8, n_informative=5,
    random_state=42
)
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42
)

model = LogisticRegression(max_iter=1000, random_state=42)
model.fit(X_train, y_train)
print("test accuracy:", round(model.score(X_test, y_test), 2))
```

Expected output (yours will differ slightly):

```
test accuracy: 0.86
```

The model got about 86% of the held-out rows right. Accuracy on the TEST set is the honest number; accuracy on the training set is always flattering.

---

## 5. Decision trees

A tree of yes/no questions. "Is balance > 5000? If yes, is age > 40? ..." Each answer sends you down a branch until you reach a leaf that holds the prediction.

- **Intuition:** exactly like a flowchart a human might draw, or a nested `CASE WHEN`.
- **When to use:** when you want something a non-technical stakeholder can read and follow. Works for both classification and regression.
- **Strengths:** very interpretable, needs no feature scaling, handles mixed data types easily.
- **Weaknesses:** a single tree overfits badly - it can memorize the training data and fail on new rows. Small data changes can reshape the whole tree.

---

## 6. Random forests

Not one tree, but hundreds, each trained on a slightly different random slice of the data and columns. To predict, all the trees vote (classification) or average (regression).

- **Intuition:** a committee. One tree is opinionated and error-prone; a crowd of diverse trees cancels out individual mistakes. This is called an ensemble.
- **When to use:** a strong, reliable default for tabular data. If your baseline is not good enough, try this next.
- **Strengths:** accurate, robust, hard to overfit, needs little tuning, tells you which features mattered most.
- **Weaknesses:** slower and heavier than one tree, and you lose the simple "read the flowchart" interpretability.

Same dataset, random forest instead. On your **lab server**, as **ec2-user**:

```python
from sklearn.ensemble import RandomForestClassifier

# n_estimators is the number of trees; sklearn's default is 100, we use 200 here
rf = RandomForestClassifier(n_estimators=200, random_state=42)
rf.fit(X_train, y_train)
print("RF test accuracy:", round(rf.score(X_test, y_test), 2))
```

Expected output (yours will differ slightly):

```
RF test accuracy: 0.91
```

The forest edged out logistic regression here (0.91 vs 0.86) because the pattern was not perfectly linear. On easier or truly linear data, the simple model often ties it - which is exactly why you always start simple.

---

## 7. Gradient boosting

Another ensemble of trees, but built differently. Instead of a crowd voting at once, boosting builds trees one at a time, each new tree fixing the mistakes of the ones before it.

- **Intuition:** a student who reviews every wrong answer and studies exactly those weak spots next. Errors shrink round by round.
- **When to use:** when you want top accuracy on tabular data and can afford more tuning. Often the winner on structured/tabular problems. Libraries: sklearn's `GradientBoostingClassifier`, and popular external ones like XGBoost and LightGBM.
- **Strengths:** frequently the most accurate classical method on tables.
- **Weaknesses:** more sensitive to settings, easier to overfit if you push too hard, slower to train, less interpretable.

---

## 8. Support Vector Machines (SVM)

Finds the boundary that separates the classes with the widest possible margin - the cleanest dividing line with the most breathing room on each side.

- **Intuition:** draw a street between two groups and make the street as wide as you can. With a "kernel" trick, SVMs can bend that street into curves.
- **When to use:** smaller datasets with clear separation, especially with many features. Text classification historically loved SVMs.
- **Strengths:** effective in high dimensions, works well when classes are cleanly separable.
- **Weaknesses:** slow on large datasets, sensitive to feature scaling (you MUST scale first - see Concepts 4.4), and the probabilities and internals are hard to interpret.

---

## 9. K-Nearest Neighbors (KNN)

The laziest algorithm and proud of it. It does not really "train." To predict a new row, it finds the K most similar rows in the training data and lets them vote.

- **Intuition:** "you are like the people nearest you." To classify a new customer, look at the 5 most similar past customers and go with the majority.
- **When to use:** small datasets, simple problems, quick baselines.
- **Strengths:** dead simple, no training step, naturally handles messy nonlinear boundaries.
- **Weaknesses:** slow to predict on big data (it compares against everything), sensitive to feature scaling, and it degrades badly when you have many features (the "curse of dimensionality" - everything looks equally far away).

---

## 10. Naive Bayes

A probability-based classifier built on Bayes' theorem. It is "naive" because it pretends every feature is independent of the others, which is rarely true, yet it often works anyway.

- **Intuition:** count how often each word shows up in spam vs not-spam, then multiply the odds together for a new email.
- **When to use:** text classification (spam filters, sentiment), and any time you need something extremely fast on many features.
- **Strengths:** very fast, tiny memory, works surprisingly well on text, fine with lots of features.
- **Weaknesses:** the independence assumption is a simplification, so its probability estimates can be off even when its labels are right. Struggles when features are strongly correlated.

---

## 11. Choosing an algorithm - a rough guide

- **Predicting a number?** Start with linear regression, then random forest / gradient boosting regressors.
- **Predicting a category?** Start with logistic regression, then random forest, then gradient boosting.
- **Need to explain it to a human?** Decision tree or logistic/linear regression.
- **Text data?** Naive Bayes or SVM (or a linear model on TF-IDF features).
- **Small, clean, few rows?** KNN or SVM can shine.
- **Tabular data and you want to win a bake-off?** Gradient boosting, usually.

The honest workflow: fit a simple baseline, get a number, then try a random forest. Only chase the fancy stuff if the gap between "good enough" and "what you have" is worth the extra complexity.

---

## 12. Key takeaways

- Supervised learning needs labeled data - an answer key.
- Classification predicts a category ("which bucket"); regression predicts a number ("how much").
- Always start with a simple, explainable baseline (logistic or linear regression).
- Ensembles (random forest, gradient boosting) usually beat single models on tabular data.
- SVM and KNN require feature scaling; trees and forests do not.
- Score on the TEST set for the honest number, never the training set.
- The best algorithm depends on the problem; there is no single winner.

---

## References

- scikit-learn User Guide, Supervised learning: https://scikit-learn.org/stable/supervised_learning.html
- scikit-learn API, `LogisticRegression` (default `solver="lbfgs"`, `penalty="l2"`, `C=1.0`, `max_iter=100`; regularization applied by default): https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.LogisticRegression.html
- scikit-learn API, `RandomForestClassifier` (default `n_estimators=100`, `max_features="sqrt"`, `criterion="gini"`): https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.RandomForestClassifier.html
- scikit-learn User Guide, Ensembles (random forests, gradient boosting): https://scikit-learn.org/stable/modules/ensemble.html
- scikit-learn User Guide, Support Vector Machines: https://scikit-learn.org/stable/modules/svm.html
- scikit-learn User Guide, Nearest Neighbors: https://scikit-learn.org/stable/modules/neighbors.html
- scikit-learn User Guide, Naive Bayes: https://scikit-learn.org/stable/modules/naive_bayes.html
