# Interview 01: Evaluation & Testing Questions

Five questions you might get in an interview about AI evaluation, testing, and monitoring.

---

## Question 1: Your Model Has 95% Accuracy. Is It Good?

**Question:** A colleague says their model has 95% accuracy on the test set. What questions would you ask before trusting that number?

**Strong answer:**

**Five questions I'd ask:**

1. **What's the class distribution?** If 95% of examples are one class, the model could just predict that class every time. For a 95/5 split, a model that always predicts the majority class gets 95% accuracy - while catching zero minority events.

2. **What are the per-class metrics?** Show me precision, recall, and F1 for EACH class. Overall accuracy can hide that the model fails completely on one category.

3. **What's the confusion matrix?** Which classes get confused with each other? A model might be 95% accurate overall but confuse "critical" and "warning" alerts 40% of the time.

4. **How was the test set created?** Was it a proper held-out set? Or was there data leakage (augmentation before split, features computed on full dataset)? A contaminated test set inflates metrics.

5. **What's the baseline?** Is 95% actually good for this problem? If a simple keyword-based classifier gets 93%, the ML model adds only 2 percentage points - maybe not worth the complexity.

**Bottom line:** Accuracy is just one number. Always ask for the full classification report, the confusion matrix, and the baseline comparison.

---

## Question 2: Precision vs Recall - When Does Each Matter?

**Question:** You're building two systems: (1) an automated failover trigger and (2) an alert dashboard. How do you choose between precision and recall?

**Strong answer:**

**Automated failover trigger - prioritize PRECISION:**
- A false positive means unnecessary failover = downtime, data risk, cost
- A false negative means delayed failover = bad but you have manual monitoring as backup
- Target: precision > 95%, recall > 80%
- Better to miss a slow degradation than to trigger false failovers

**Alert dashboard - prioritize RECALL:**
- A false positive means an extra alert on the dashboard = minor annoyance
- A false negative means a missed incident = potential outage nobody sees
- Target: recall > 95%, precision > 50%
- Better to have extra alerts than to miss real incidents

**General rules:**
- If the cost of FALSE ALARM > cost of MISSED EVENT -> precision
- If the cost of MISSED EVENT > cost of FALSE ALARM -> recall
- If costs are equal -> F1 (harmonic mean of both)

**How to control the trade-off:** Threshold tuning.
- Lower threshold (0.3) -> more positive predictions -> higher recall, lower precision
- Higher threshold (0.7) -> fewer positive predictions -> higher precision, lower recall
- Find the threshold that matches your cost structure

---

## Question 3: How Do You Test an AI System?

**Question:** Describe your testing strategy for a machine learning model going to production.

**Strong answer:**

**Four layers of testing:**

1. **Unit tests** (before training):
   - Model output shape matches expected dimensions
   - Loss function returns positive values
   - Preprocessing handles edge cases (NaN, infinity, empty strings)
   - Data pipeline has no train/test overlap
   - Run automatically on every code change

2. **Behavioral tests** (after training):
   - **Invariance:** "CPU at 95%" and "cpu at 95%" should give the same result
   - **Directional:** Adding "disk full" to a message should push toward "storage" category
   - **Minimum functionality:** 10 must-pass cases per category
   - These are like integration tests - they test what the model DOES, not how

3. **Statistical tests** (before deployment):
   - Is the new model significantly better than the old one? (McNemar's test)
   - Is it better than a simple baseline? (paired t-test on cross-validation)
   - Does it work equally well on all subgroups? (fairness testing)

4. **Production monitoring** (after deployment):
   - Sample and label 50 predictions per week (human-in-the-loop)
   - Data drift detection on input features (KS test)
   - Prediction distribution monitoring (chi-squared test)
   - Latency and error rate tracking
   - Automatic alerts when metrics drop below thresholds

**The key insight:** AI testing is different from software testing. You're testing statistical properties and behavior, not exact outputs. A model can be "correct" 90% of the time and still have critical failure modes.

---

## Question 4: What Is Model Drift and How Do You Handle It?

**Question:** Your model has been in production for 6 months. How do you know if it's still working?

**Strong answer:**

**Two types of drift:**

1. **Data drift:** Input distribution changes.
   - New server types (ARM vs x86), different metric ranges
   - New monitoring stack (different alert formats)
   - Seasonal patterns (Black Friday traffic vs normal)
   - Detection: KS test comparing training vs production features weekly

2. **Concept drift:** The relationship between input and output changes.
   - After hardware upgrade, CPU 80% is normal (used to be critical)
   - New team policy: "warning" threshold changed from 60% to 75%
   - Detection: monitor accuracy on sampled labeled data

**My monitoring strategy:**

1. **Daily:** Check prediction distribution (automated, no human needed)
2. **Weekly:** Run KS test on top features vs training distribution
3. **Bi-weekly:** Label 50 production predictions, calculate accuracy/F1
4. **Monthly:** Full evaluation report with behavioral tests
5. **On alert:** When any check fails, investigate and potentially retrain

**When to retrain:**
- Accuracy drops more than 5% from baseline
- Data drift p-value < 0.01 on any feature for 2+ consecutive weeks
- Prediction distribution shift > 10% in any category
- After major infrastructure changes (new servers, new monitoring)

**Key insight:** Model deployment is not "set and forget." It's like database maintenance - you need regular ANALYZE, VACUUM, and monitoring.

---

## Question 5: How Do You Evaluate an LLM (Text Generation)?

**Question:** You built a text-to-SQL system using an LLM. How do you evaluate if it's working?

**Strong answer:**

**LLM evaluation is harder than classification because there's no single "right answer."**

**Four evaluation approaches:**

1. **Functional testing (most important for text-to-SQL):**
   - Does the generated SQL actually execute without errors?
   - Does it return the correct results on test data?
   - Does it handle edge cases (NULL values, empty tables)?
   - This is the gold standard: does the output WORK?

2. **Reference comparison (automated):**
   - BLEU/ROUGE scores compare generated text to reference answers
   - Exact match accuracy for SQL (does the generated SQL match the expected SQL?)
   - Limitation: many valid SQL queries can produce the same result
   - Better: compare query RESULTS, not query TEXT

3. **LLM-as-judge (scalable):**
   - Use a stronger model (Claude) to evaluate a weaker model's output
   - "Is this SQL correct for the given question? Rate 1-5."
   - Faster and cheaper than human evaluation
   - Not as reliable as functional testing

4. **Human evaluation (gold standard):**
   - Have DBAs review 100 generated queries
   - Rate: correctness, efficiency, readability
   - Most accurate but expensive and slow
   - Use for initial validation and periodic spot-checks

**My evaluation pipeline for text-to-SQL:**
1. Parse test: Does the generated SQL parse? (automated)
2. Execute test: Does it run without error on a test database? (automated)
3. Result test: Does it return the expected results? (automated)
4. Efficiency test: Is the query plan reasonable? (automated with EXPLAIN)
5. Human review: Sample 50 queries monthly for a DBA to review

**Key insight:** For LLMs, the best evaluation is task-specific. Don't use generic text metrics (BLEU) when you can test functional correctness directly.
