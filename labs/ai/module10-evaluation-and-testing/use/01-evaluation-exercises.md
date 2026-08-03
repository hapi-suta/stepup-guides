# USE 01: Evaluation & Testing Exercises

Practice what you built. Each exercise reinforces a concept from Builds 01-04.

---

## Exercise 1: Metric Selection (Build 01)

Choose the right metric for each scenario.

**Task:**
1. For each scenario below, state which metric to prioritize and why:
   - Automated server restart based on model prediction
   - Alert system that pages the on-call engineer
   - Database health dashboard (informational only)
   - Automated query kill for detected runaway queries
   - Incident post-mortem classification
2. Implement a function that calculates all metrics (accuracy, precision, recall, F1, AUC-ROC) for a given set of predictions
3. Test with a deliberately imbalanced dataset (95% healthy, 5% incident)

---

## Exercise 2: Threshold Optimizer (Build 01)

Build a tool that finds the optimal threshold for your use case.

**Task:**
1. Generate 1000 predictions with probabilities
2. Implement `find_optimal_threshold(y_true, probs, target_metric='f1')`
3. Support three modes: optimize for F1, optimize for recall > 0.95, optimize for precision > 0.90
4. Print the optimal threshold and corresponding metrics for each mode
5. Show how the trade-off changes across thresholds (text-based chart)

---

## Exercise 3: Behavioral Test Suite (Build 03)

Write a comprehensive test suite for an alert classifier.

**Task:**
1. Write 5 invariance tests (case, whitespace, abbreviations, number format, date format)
2. Write 5 directional tests (adding context changes prediction)
3. Write 10 minimum functionality tests (must-pass cases)
4. Write 3 "negative" tests (things the model should NOT do)
5. Run all tests and print a pass/fail report with total score

---

## Exercise 4: Drift Detector (Build 04)

Build a drift detection system.

**Task:**
1. Generate "training" data with 5 features
2. Generate 4 weeks of "production" data where:
   - Week 1: same distribution
   - Week 2: one feature drifts slightly
   - Week 3: two features drift significantly
   - Week 4: concept drift (same inputs, different correct labels)
3. Implement KS test for data drift on each feature
4. Implement chi-squared test for prediction drift
5. Print a weekly monitoring report showing which weeks have drift

---

## Exercise 5: Complete Evaluation Pipeline (All Builds)

Build an end-to-end evaluation system.

**Task:**
1. Train a model on the Module 07 server incident dataset
2. Evaluate with: accuracy, precision, recall, F1, confusion matrix, AUC-ROC
3. Tune the threshold for recall > 0.90
4. Write 10 behavioral tests and run them
5. Simulate 4 weeks of production data with gradual drift
6. Print a combined report: model metrics + behavioral tests + drift status
7. Make a recommendation: retrain or keep the current model?

---

## Scoring Guide

| Exercise | Skill Tested | Difficulty |
|----------|-------------|------------|
| 1 | Metric selection and implementation | Beginner |
| 2 | Threshold tuning | Intermediate |
| 3 | Behavioral testing | Intermediate |
| 4 | Drift detection | Intermediate |
| 5 | Complete evaluation pipeline | Advanced |
