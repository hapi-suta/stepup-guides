# Interview 01: Classical ML Questions

Five questions you might get in an interview about machine learning fundamentals.

---

## Question 1: Walk Me Through an ML Project End to End

**Question:** You're building a model to predict database incidents from server metrics. Walk through every step from raw data to production deployment.

**Strong answer should include:**

**Step 1 - Data Collection:**
- Pull historical metrics from monitoring (CPU, memory, connections, disk, WAL growth)
- Pull incident labels from your ticketing system (PagerDuty, Jira)
- Join them by timestamp and server ID
- SQL: `SELECT metrics.*, incidents.severity FROM metrics LEFT JOIN incidents ON ...`

**Step 2 - Exploration:**
- Check for missing values, class distribution, feature ranges
- `df.describe()`, `df.isnull().sum()`, `y.value_counts()`
- Identify: is this balanced or imbalanced? (incidents are usually rare - imbalanced)

**Step 3 - Feature Engineering:**
- Create lag features (CPU 5 minutes ago, CPU trend)
- Create aggregates (max CPU in last hour, p95 connections)
- Handle missing values (fill with median or drop)
- Encode any categorical features (server type, region)

**Step 4 - Split:**
- Train/test split (80/20) or time-based split for time series
- NEVER normalize before splitting (data leakage)

**Step 5 - Preprocessing:**
- `scaler.fit_transform(X_train)` then `scaler.transform(X_test)`
- Keep scaler object for production

**Step 6 - Model Selection:**
- Start with LogisticRegression (baseline)
- Try RandomForest and gradient boosting
- Use 5-fold cross-validation with F1 score (not accuracy - imbalanced data)

**Step 7 - Evaluation:**
- Confusion matrix, precision, recall, F1
- Prioritize recall for incident detection
- Check train vs test performance for overfitting

**Step 8 - Deployment:**
- Save model + scaler with pickle or joblib
- Wrap in an API endpoint
- Monitor prediction distribution (all zeros = something is wrong)

---

## Question 2: Explain Overfitting vs Underfitting

**Question:** Your model has 99% training accuracy but 72% test accuracy. What's happening and how do you fix it?

**Strong answer:**

**Diagnosis: Overfitting.** The model memorized the training data instead of learning general patterns. It's like studying the answer key - you ace that specific test but fail any other version.

**How to spot it:**
- Training accuracy >> Test accuracy (big gap)
- Decision tree has too many levels (perfectly splits training data)
- Model is too complex for the amount of data

**Fixes (in order of effort):**
1. **Reduce model complexity:** Lower `max_depth` for trees, fewer features
2. **Get more data:** More training examples dilute noise
3. **Cross-validation:** Use 5-fold CV instead of single split
4. **Regularization:** Add L1/L2 penalties (LogisticRegression C parameter)
5. **Feature selection:** Remove noisy or redundant features
6. **Early stopping:** Stop training when validation performance stops improving

**Underfitting (the opposite):**
- BOTH training and test accuracy are low
- Model is too simple to capture the pattern
- Fix: use a more complex model, add more features, engineer better features

**DBA analogy:**
- Overfitting: A runbook written for ONE specific incident that doesn't generalize
- Underfitting: A runbook that just says "restart the server" for everything

---

## Question 3: When Would You Use Random Forest vs Gradient Boosting vs Logistic Regression?

**Question:** You have three algorithms available. When would you choose each?

**Strong answer:**

| Algorithm | Use When | Strengths | Weaknesses |
|-----------|----------|-----------|------------|
| Logistic Regression | Simple baseline, need interpretability, few features | Fast, interpretable, works with small data | Can't capture non-linear patterns |
| Random Forest | Need something that "just works," feature importance | Robust, minimal tuning, handles missing data | Can be slow with many trees, memory-heavy |
| Gradient Boosting (XGBoost) | Need maximum accuracy, have enough data | Best accuracy for tabular data, fast | Needs careful tuning, easier to overfit |

**Decision process:**
1. Always start with logistic regression as a baseline
2. If the baseline is insufficient, try random forest (minimal tuning)
3. If you need more accuracy, try XGBoost/LightGBM (requires tuning)
4. If model must be explainable (regulatory, stakeholder trust), stick with logistic regression or single decision tree

**For tabular data (databases, monitoring):** Gradient boosting (XGBoost/LightGBM) is the default in 2026. It consistently wins Kaggle competitions on structured data and is the standard at most companies.

**Key insight:** The algorithm choice matters less than the data quality. A logistic regression on good features often beats a complex model on bad features.

---

## Question 4: What Is Data Leakage and How Do You Prevent It?

**Question:** You built a model that gets 99.5% accuracy in testing but only 80% in production. What likely happened?

**Strong answer:**

**Most likely cause: data leakage.** Information from the test set or future data influenced the training process.

**Common types:**

1. **Preprocessing leakage:** Normalizing before splitting. The scaler saw test data.
   - Fix: Split first, `fit_transform` on train only, `transform` on test

2. **Feature leakage:** Using a feature that won't be available at prediction time
   - Example: Including "incident_resolution_time" to predict if an incident will happen
   - The resolution time only exists AFTER the incident - it's a future variable
   - Fix: Only use features available at the time of prediction

3. **Time leakage:** Training on future data, testing on past data
   - Fix: For time series, use time-based splits (train on months 1-6, test on month 7)

4. **Target leakage:** A feature that's directly derived from the label
   - Example: "was_paged" feature when predicting incidents (paging = there was an incident)
   - Fix: Trace every feature back to its source, check if it depends on the label

**Prevention checklist:**
- Split data BEFORE any preprocessing
- `fit_transform()` on train, `transform()` on test
- For time series, use chronological splits
- Ask: "Would I have this feature at prediction time?"
- Sanity check: if accuracy seems too good to be true, it probably is

---

## Question 5: How Do You Handle Class Imbalance?

**Question:** You're building an anomaly detection system. Only 0.5% of events are anomalies. How do you handle this?

**Strong answer should include:**

**Problem:** Standard models optimize for accuracy. A model that always predicts "normal" gets 99.5% accuracy while detecting zero anomalies.

**Metrics to use instead of accuracy:**
- **Recall** (sensitivity): What % of anomalies did we catch?
- **Precision:** When we flag an anomaly, how often is it real?
- **F1:** Harmonic mean of precision and recall
- **AUC-ROC:** How well does the model separate the two classes?

**Techniques (ranked by practicality):**

1. **class_weight='balanced'** - Easiest. Tells the model that misclassifying the rare class is more costly. Available in LogisticRegression, RandomForest, and most sklearn models.

2. **Lower the decision threshold** - Instead of 0.5, use 0.3 or 0.2. Catches more anomalies at the cost of more false positives.

3. **Oversampling (SMOTE)** - Creates synthetic examples of the rare class. Good when you have very few positive examples (< 50).

4. **Undersampling** - Randomly remove examples of the majority class. Simple but loses data.

5. **Anomaly-specific algorithms** - Isolation Forest, One-Class SVM. Designed for extreme imbalance where you only model "normal" and flag deviations.

**For a DBA monitoring system:**
- Use `class_weight='balanced'` + lower threshold (0.2-0.3)
- Prioritize recall over precision (better to have false alarms than miss incidents)
- Track false positive rate in production (too many false alarms cause alert fatigue)
- Set up feedback loop: when an alert is dismissed, label it for retraining
