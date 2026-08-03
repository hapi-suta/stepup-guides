# Build 02: Classification - Yes or No?

Linear regression predicts a number. Classification predicts a category - usually yes/no. "Will this server have an incident?" is a classification problem.

---

## Step 1. Logistic regression - predicting yes/no

Logistic regression is like linear regression, but it outputs a probability (0 to 1) instead of a number. It uses the sigmoid function from Module 05.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report

# --- Create classification data ---
# Server metrics -> will there be an incident? (yes=1, no=0)
np.random.seed(42)
n = 200

cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)

# Rule: incident if CPU > 70 AND connections > 180
# np.random.random(n) adds randomness (some borderline cases go either way)
# & means AND for arrays (not Python's "and" keyword - that only works on single values)
# | means OR for arrays
# DBA analogy: same as AND/OR in a WHERE clause, but for array operations
incident = ((cpu > 70) & (connections > 180) |
            ((cpu > 85) & (memory > 80))).astype(int)
# .astype(int) converts True/False to 1/0 (True becomes 1, False becomes 0)
# DBA analogy: like CAST(boolean_col AS INTEGER) in SQL

# Add some noise - flip 5% of labels randomly
# This makes it realistic (real data has noise)
noise_mask = np.random.random(n) < 0.05
incident[noise_mask] = 1 - incident[noise_mask]

df = pd.DataFrame({
    'cpu_percent': cpu,
    'connections': connections,
    'memory_percent': memory,
    'incident': incident,
})

print(f"Data: {n} servers")
# .value_counts() counts how many of each value - like GROUP BY with COUNT
print(f"Incidents: {incident.sum()} ({incident.mean()*100:.1f}%)")
print(f"Healthy:   {n - incident.sum()} ({(1-incident.mean())*100:.1f}%)")
print()

# --- Prepare and split ---
X = df.drop('incident', axis=1)
y = df['incident']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# --- Train logistic regression ---
# Same pattern as linear regression: create, fit, predict
model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)

# --- Evaluate ---
predictions = model.predict(X_test)
accuracy = accuracy_score(y_test, predictions)

print(f"Accuracy: {accuracy*100:.1f}%")
print()

# classification_report gives precision, recall, and F1 for each class
print("Classification Report:")
print(classification_report(y_test, predictions,
                           target_names=['Healthy', 'Incident']))

# --- See probabilities ---
# .predict_proba() returns probabilities instead of just yes/no
# Each row has [probability_of_0, probability_of_1]
probabilities = model.predict_proba(X_test)
print("First 5 predictions with probabilities:")
for i in range(5):
    actual = "Incident" if y_test.iloc[i] == 1 else "Healthy"
    prob_incident = probabilities[i][1]  # [1] = probability of class 1 (incident)
    predicted = "Incident" if prob_incident > 0.5 else "Healthy"
    print(f"  P(incident)={prob_incident:.3f}  Predicted: {predicted:8s}  Actual: {actual}")
PYEOF
```

Expected output (yours will differ):
```
Data: 200 servers
Incidents: 46 (23.0%)
Healthy:   154 (77.0%)

Accuracy: 92.5%

Classification Report:
              precision    recall  f1-score   support

     Healthy       0.94      0.97      0.95        30
    Incident       0.89      0.80      0.84        10

    accuracy                           0.92        40
   macro avg       0.91      0.88      0.90        40
weighted avg       0.92      0.92      0.92        40

First 5 predictions with probabilities:
  P(incident)=0.034  Predicted: Healthy   Actual: Healthy
  P(incident)=0.891  Predicted: Incident  Actual: Incident
  ...
```

Key metrics explained:
- **Precision** (Healthy=0.94): When the model says "healthy," it's right 94% of the time
- **Recall** (Incident=0.80): Of all real incidents, the model catches 80%
- **F1**: Balances precision and recall into one number

---

## Step 2. Decision trees - a flowchart

A decision tree makes predictions by asking yes/no questions - just like a troubleshooting runbook.

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.tree import DecisionTreeClassifier, export_text
from sklearn.metrics import accuracy_score, classification_report

# --- Same data as Step 1 ---
np.random.seed(42)
n = 200
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)
incident = ((cpu > 70) & (connections > 180) | ((cpu > 85) & (memory > 80))).astype(int)
noise_mask = np.random.random(n) < 0.05
incident[noise_mask] = 1 - incident[noise_mask]

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'memory_percent': memory, 'incident': incident,
})

X = df.drop('incident', axis=1)
y = df['incident']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# --- Train a decision tree ---
# max_depth=4 limits the tree to 4 levels of questions
# Without a limit, the tree will memorize every training example (overfit)
tree = DecisionTreeClassifier(max_depth=4, random_state=42)
tree.fit(X_train, y_train)

# --- Print the tree (human-readable!) ---
# This is the main advantage of decision trees: you can READ the model
print("Decision Tree Rules:")
print("=" * 50)
tree_rules = export_text(tree, feature_names=list(X.columns))
print(tree_rules)

# --- Evaluate ---
predictions = tree.predict(X_test)
accuracy = accuracy_score(y_test, predictions)
print(f"Accuracy: {accuracy*100:.1f}%")
print()

# --- Feature importance ---
# The tree tells you which features it found most useful
# Higher number = more important for making predictions
print("Feature importance:")
# sorted() puts items in order. key=lambda x: x[1] means "sort by the second item"
# lambda is a tiny one-line function: lambda x: x[1] takes x and returns x[1]
# reverse=True means highest first
# DBA analogy: ORDER BY importance DESC
for feature, importance in sorted(
    zip(X.columns, tree.feature_importances_),
    key=lambda x: x[1], reverse=True
):
    bar = "#" * int(importance * 40)
    print(f"  {feature:17s}: {importance:.3f} {bar}")

print()
print("The tree learned that CPU and connections are the most important")
print("features for predicting incidents - matching our actual formula!")
print()
print("DBA analogy: This IS a runbook.")
print("  If CPU > 70%?")
print("    Yes -> If connections > 180?")
print("      Yes -> INCIDENT")
print("      No  -> Check memory...")
PYEOF
```

Expected output (yours will differ):
```
Decision Tree Rules:
==================================================
|--- cpu_percent <= 70.32
|   |--- class: 0
|--- cpu_percent > 70.32
|   |--- connections <= 180.45
|   |   |--- memory_percent <= 80.12
|   |   |   |--- class: 0
|   |   |--- memory_percent > 80.12
|   |   |   |--- cpu_percent <= 85.23
|   |   |   |   |--- class: 0
|   |   |   |--- cpu_percent > 85.23
|   |   |   |   |--- class: 1
|   |--- connections > 180.45
|   |   |--- class: 1

Accuracy: 95.0%

Feature importance:
  cpu_percent      : 0.523 ####################
  connections      : 0.301 ############
  memory_percent   : 0.176 #######

The tree learned that CPU and connections are the most important
features for predicting incidents - matching our actual formula!
```

---

## Step 3. Compare models side by side

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.tree import DecisionTreeClassifier
from sklearn.metrics import accuracy_score, f1_score

# --- Same data ---
np.random.seed(42)
n = 200
cpu = np.random.uniform(10, 95, n)
connections = np.random.uniform(5, 290, n)
memory = np.random.uniform(20, 95, n)
incident = ((cpu > 70) & (connections > 180) | ((cpu > 85) & (memory > 80))).astype(int)
noise_mask = np.random.random(n) < 0.05
incident[noise_mask] = 1 - incident[noise_mask]

df = pd.DataFrame({
    'cpu_percent': cpu, 'connections': connections,
    'memory_percent': memory, 'incident': incident,
})

X = df.drop('incident', axis=1)
y = df['incident']
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# --- Train multiple models ---
models = {
    "Logistic Regression": LogisticRegression(random_state=42),
    "Decision Tree (depth=3)": DecisionTreeClassifier(max_depth=3, random_state=42),
    "Decision Tree (depth=5)": DecisionTreeClassifier(max_depth=5, random_state=42),
    "Decision Tree (no limit)": DecisionTreeClassifier(random_state=42),
}

print(f"{'Model':<28s} {'Accuracy':>10s} {'F1 Score':>10s} {'Train Acc':>10s}")
print("-" * 62)

for name, model in models.items():
    model.fit(X_train, y_train)

    train_acc = accuracy_score(y_train, model.predict(X_train))
    test_acc = accuracy_score(y_test, model.predict(X_test))
    f1 = f1_score(y_test, model.predict(X_test))

    # Flag overfitting: train accuracy much higher than test accuracy
    overfit = " OVERFIT!" if (train_acc - test_acc) > 0.1 else ""

    print(f"{name:<28s} {test_acc:>9.1%} {f1:>9.3f} {train_acc:>9.1%}{overfit}")

print()
print("Key observations:")
print("  - 'No limit' tree has high train accuracy but may overfit")
print("  - Depth=3 is simpler and may generalize better")
print("  - F1 score matters more than accuracy for imbalanced data")
print("    (23% incidents means accuracy can be misleading)")
PYEOF
```

Expected output (yours will differ):
```
Model                         Accuracy   F1 Score  Train Acc
--------------------------------------------------------------
Logistic Regression              92.5%      0.842      91.9%
Decision Tree (depth=3)          95.0%      0.875      96.2%
Decision Tree (depth=5)          95.0%      0.875      98.8%
Decision Tree (no limit)         92.5%      0.800    100.0% OVERFIT!

Key observations:
  - 'No limit' tree has high train accuracy but may overfit
  - Depth=3 is simpler and may generalize better
  - F1 score matters more than accuracy for imbalanced data
    (23% incidents means accuracy can be misleading)
```

The "no limit" tree got 100% on training data (memorized it) but performs worse on test data. That's overfitting.

---

## What You Learned

| Concept | What It Is | When to Use |
|---------|-----------|-------------|
| Logistic Regression | Linear model for yes/no predictions | First model to try for classification |
| Decision Tree | Flowchart of yes/no questions | When you need explainable predictions |
| accuracy_score | % of correct predictions | Quick check (misleading with imbalanced data) |
| precision | "When model says yes, how often is it right?" | When false positives are costly |
| recall | "Of all real yes, how many did model catch?" | When missing a real event is costly |
| F1 score | Balance of precision and recall | Best single metric for classification |
| max_depth | Limits tree complexity | Prevents overfitting |
| Overfitting | Model memorizes training data | Train accuracy >> test accuracy = problem |
| feature_importances_ | Which features matter most | Feature selection, model interpretation |
