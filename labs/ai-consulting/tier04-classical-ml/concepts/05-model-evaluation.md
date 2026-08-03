# Concepts 4.5: Model Evaluation

**Tier 4 - Classical machine learning.** Teaching reference. Training a model is easy. Knowing whether it is any good is the hard part - and picking the wrong measuring stick is one of the most common and most expensive mistakes in ML. A model that looks 99% accurate can be completely worthless.

**Who this is for:** DBAs. You would never judge a query by "it returned rows." You check the plan, the timing, the row counts. Same here: you need the right metric, and you need to know what it hides.

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import numpy as np` and the `sklearn.metrics` imports shown inline.

---

## 1. Always score on unseen data

Every number in this doc must come from data the model did NOT train on - the validation or test set (Concepts 4.1, step 5). A model can memorize its training data and score perfectly on it while being useless on anything new. Training-set scores are vanity; test-set scores are truth.

---

## 2. Accuracy (and why it lies)

**Accuracy** = fraction of predictions that were correct. Simple and intuitive.

The trap: accuracy is meaningless when classes are imbalanced. Suppose 1% of transactions are fraud. A model that predicts "not fraud" for EVERYTHING is 99% accurate and catches zero fraud. High accuracy, total failure.

- **Use accuracy when:** classes are roughly balanced and every kind of mistake costs about the same.
- **Do NOT trust accuracy when:** one class is rare (fraud, disease, churn, defects). This is most interesting problems.

When classes are imbalanced, reach for precision, recall, and F1 instead.

---

## 3. The confusion matrix - where all metrics come from

For a yes/no classifier, every prediction falls into one of four boxes:

- **True Positive (TP):** predicted yes, and it was yes. Correct catch.
- **True Negative (TN):** predicted no, and it was no. Correct pass.
- **False Positive (FP):** predicted yes, but it was no. False alarm.
- **False Negative (FN):** predicted no, but it was yes. Missed it.

Laid out as a grid:

```
                 Predicted No   Predicted Yes
Actual No           TN              FP
Actual Yes          FN              TP
```

Every classification metric is just a ratio of these four numbers. Learn to read this grid and the rest is easy.

---

## 4. Precision, recall, and F1

- **Precision** = TP / (TP + FP). Of everything the model FLAGGED as positive, how much was really positive? "When it says yes, how often is it right?" Low precision = lots of false alarms.
- **Recall** = TP / (TP + FN). Of all the REAL positives out there, how many did the model catch? "How much of the real thing did it find?" Low recall = lots of misses.
- **F1** = the harmonic mean of precision and recall - a single number that is high only when BOTH are high. Useful when you need one number and classes are imbalanced.

**The precision-recall tradeoff (business examples):**

- **Medical screening for a serious disease:** you want high RECALL. Missing a sick patient (false negative) is far worse than a false alarm that leads to one more test. You accept more false positives to catch every real case.
- **Spam filter:** you want high PRECISION. Wrongly sending a real, important email to the spam folder (false positive) is worse than letting the occasional spam through. You accept a few misses to avoid killing legitimate mail.
- **Fraud detection:** depends on cost. Blocking a legitimate purchase (FP) annoys a customer; missing fraud (FN) loses money. You balance the two with F1 or by tuning the threshold.

You usually cannot maximize both. Push recall up and precision tends to fall, and vice versa. Which one to favor is a BUSINESS decision, not a math one.

---

## 5. A worked classification example

On your **lab server**, as **ec2-user**:

```python
from sklearn.metrics import confusion_matrix, classification_report

# tiny hand-made example: 1 = positive (e.g. "fraud")
y_true = [0, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1, 0]
y_pred = [0, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1, 0]

print(confusion_matrix(y_true, y_pred))
print(classification_report(y_true, y_pred, digits=2))
```

Expected output (yours will differ slightly):

```
[[6 1]
 [1 4]]
              precision    recall  f1-score   support

           0       0.86      0.86      0.86         7
           1       0.80      0.80      0.80         5

    accuracy                           0.83        12
   macro avg       0.83      0.83      0.83        12
weighted avg       0.83      0.83      0.83        12
```

Reading the confusion matrix: TN=6, FP=1 (top row), FN=1, TP=4 (bottom row). For class 1 (the positive): precision = 4/(4+1) = 0.80 (when it said fraud, 80% were fraud), recall = 4/(4+1) = 0.80 (it caught 80% of real fraud). `support` is how many real rows of each class existed. Overall accuracy is 0.83, but for an imbalanced problem you would care far more about the class-1 precision and recall than that headline number.

---

## 6. ROC curve and AUC

Most classifiers output a probability (0 to 1), not just yes/no. The ROC curve plots the true positive rate (TPR = recall = TP/(TP+FN)) against the false positive rate (FPR = FP/(FP+TN)) as you slide the decision threshold from strict to loose (see: scikit-learn Model Evaluation User Guide). In plain terms, it shows how the model trades off catching positives against raising false alarms.

- **AUC** (Area Under the ROC Curve) squeezes that whole curve into one number from 0 to 1:
  - 1.0 = perfect separation.
  - 0.5 = no better than a coin flip.
  - below 0.5 = worse than random (something is backwards).
- **Why it is useful:** AUC measures the model's ranking ability independent of any single threshold, and it holds up better than accuracy on imbalanced data.
- **Rough reading:** a common rule-of-thumb (not an official sklearn standard) is 0.9+ excellent, 0.8-0.9 good, 0.7-0.8 fair, below 0.7 weak. What counts as "good enough" is always relative to your baseline and the problem.

---

## 7. The decision threshold (and moving it)

By default, a classifier calls anything with probability above 0.5 "yes." But 0.5 is not sacred - it is a dial you can turn.

- **Lower the threshold** (say to 0.3): the model says "yes" more readily. Recall goes UP (catches more real cases), precision goes DOWN (more false alarms).
- **Raise the threshold** (say to 0.8): the model says "yes" only when very confident. Precision goes UP, recall goes DOWN.

So for the medical screener you would LOWER the threshold to catch more sick patients. For the spam filter you would RAISE it so only near-certain spam gets filtered. Tuning the threshold is a free lever that requires no retraining - you just change where you cut the probability.

---

## 8. Regression metrics

When the model predicts a number (not a category), accuracy makes no sense. You measure how far off the predictions are.

- **MAE (Mean Absolute Error):** the average size of the error, in the same units as the target. "On average we are off by $4,200." Easy to explain, forgiving of outliers.
- **MSE (Mean Squared Error):** averages the SQUARED errors, so big misses are punished harder. Units are squared (dollars-squared), so it is less intuitive but useful for optimization.
- **RMSE (Root Mean Squared Error):** the square root of MSE, back in the original units. Like MAE but heavier on large errors. If a few big misses are especially bad, watch RMSE.
- **R2 (R-squared):** the coefficient of determination, `1 - SS_residual / SS_total`, where SS_total is measured against always predicting the mean. Best possible value is 1.0; 0 means no better than always guessing the average; it can go negative for a model worse than that baseline (see: scikit-learn r2_score API). "Our model explains 78% of the variance in price."

MAE vs RMSE: if RMSE is much larger than MAE, you have a few large errors dragging things - investigate those outliers.

---

## 9. A worked regression example

On your **lab server**, as **ec2-user**:

```python
import numpy as np
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

y_true = np.array([100, 150, 200, 250, 300])
y_pred = np.array([110, 140, 210, 245, 280])

mae  = mean_absolute_error(y_true, y_pred)
mse  = mean_squared_error(y_true, y_pred)
rmse = np.sqrt(mse)
# In scikit-learn 1.4+ you can compute RMSE directly:
#   from sklearn.metrics import root_mean_squared_error
#   rmse = root_mean_squared_error(y_true, y_pred)
# (the old mean_squared_error(..., squared=False) form is deprecated)
r2   = r2_score(y_true, y_pred)

print("MAE :", round(mae, 2))
print("RMSE:", round(rmse, 2))
print("R2  :", round(r2, 2))
```

Expected output (yours will differ slightly):

```
MAE : 13.0
RMSE: 13.78
R2  : 0.96
```

MAE of 13 means we are off by about 13 on average (same units as the target). RMSE (13.78) sits just above MAE, so no single wild miss - the errors are fairly even. R2 of 0.96 says the model explains 96% of the variation, which is very strong.

---

## 10. Residual analysis (regression)

A residual is the leftover error for one row: actual minus predicted. Plotting residuals reveals problems a single number hides:

- Residuals should look like random noise scattered around zero.
- A pattern (residuals grow with the prediction, or curve) means the model is missing something - maybe a nonlinear relationship or a needed feature.
- A few huge residuals point to outliers or data errors worth investigating.

The headline metric tells you IF the model is off; residuals tell you WHERE and WHY.

---

## 11. Key takeaways

- Always evaluate on unseen (validation/test) data; training scores lie.
- Accuracy is fine for balanced classes and dangerous for imbalanced ones.
- The confusion matrix (TP/TN/FP/FN) is the source of every classification metric.
- Precision = "when it says yes, is it right?"; recall = "did it find all the real ones?"; F1 balances both.
- The precision-recall tradeoff is a business decision (medical favors recall, spam favors precision).
- AUC summarizes threshold-independent ranking; 0.5 is a coin flip, 0.9+ is excellent.
- The 0.5 threshold is a dial - move it to favor precision or recall without retraining.
- For regression use MAE, RMSE, and R2; if RMSE >> MAE you have big outlier errors.
- Plot residuals to find WHERE the model is wrong, not just how wrong.

---

## References

- scikit-learn User Guide, Metrics and scoring (precision, recall, F1, ROC/AUC, TPR/FPR formulas): https://scikit-learn.org/stable/modules/model_evaluation.html
- scikit-learn API, `confusion_matrix`: https://scikit-learn.org/stable/modules/generated/sklearn.metrics.confusion_matrix.html
- scikit-learn API, `classification_report`: https://scikit-learn.org/stable/modules/generated/sklearn.metrics.classification_report.html
- scikit-learn API, `roc_auc_score`: https://scikit-learn.org/stable/modules/generated/sklearn.metrics.roc_auc_score.html
- scikit-learn API, `mean_absolute_error`: https://scikit-learn.org/stable/modules/generated/sklearn.metrics.mean_absolute_error.html
- scikit-learn API, `root_mean_squared_error` (added in 1.4; the `squared=False` arg of `mean_squared_error` is deprecated): https://scikit-learn.org/stable/modules/generated/sklearn.metrics.root_mean_squared_error.html
- scikit-learn API, `r2_score` (coefficient of determination; best 1.0, can be negative): https://scikit-learn.org/stable/modules/generated/sklearn.metrics.r2_score.html
