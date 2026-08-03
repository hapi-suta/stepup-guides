#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# SURVIVE scenario: class-imbalance
# Tier 4 - Classical machine learning (ai-consulting track)
#
# What this injects:
#   A synthetic critical-incident dataset where the positive class (a real
#   incident) is only about 3% of rows. The naive train.py reports ~0.97
#   accuracy and declares success - but the model just predicts "no incident"
#   almost every time, so recall on the rare class is near zero (~0.05). A
#   useless model hiding behind a high accuracy number.
#
# Student goal (see runbook.md):
#   Detect that accuracy is misleading via the confusion matrix and per-class
#   recall, diagnose class imbalance, correct with class_weight="balanced",
#   and show recall on the rare class jump to ~0.70. Document the finding.
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-class-imbalance"

echo "==> Creating working directory at ${WORKDIR}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Creating Python 3.12 virtual environment"
python3.12 -m venv .venv
# shellcheck disable=SC1091
source "${WORKDIR}/.venv/bin/activate"

echo "==> Installing numpy, pandas, scikit-learn (quiet)"
python -m pip install --quiet --upgrade pip
python -m pip install --quiet numpy pandas scikit-learn

echo "==> Writing generate_data.py"
cat > generate_data.py <<'PYEOF'
"""Generate a severely imbalanced critical-incident dataset.

Label `is_incident` is positive on only about 3% of rows. Features carry a
real (but not perfect) signal, so a model that actually tries can recall the
rare class. The trap is that a lazy model can score ~0.97 accuracy just by
always predicting the majority class.
"""
import numpy as np
import pandas as pd
from sklearn.datasets import make_classification

np.random.seed(42)

X, y = make_classification(
    n_samples=6000,
    n_features=8,
    n_informative=4,
    n_redundant=1,
    n_clusters_per_class=1,
    weights=[0.97, 0.03],   # ~3% positive (rare incidents)
    flip_y=0.01,
    class_sep=1.2,
    random_state=42,
)

cols = [f"metric_{i}" for i in range(X.shape[1])]
df = pd.DataFrame(X, columns=cols)
df["is_incident"] = y

df.to_csv("incidents.csv", index=False)
pos = int(df["is_incident"].sum())
print("Wrote incidents.csv with", len(df), "rows")
print(f"positive (incident) rows: {pos} ({pos / len(df):.1%})")
PYEOF

echo "==> Writing train.py (the naive, accuracy-only analysis)"
cat > train.py <<'PYEOF'
"""Naive training that reports ACCURACY only and declares success.

The model predicts the majority class almost every time, so accuracy looks
great while recall on the rare class is near zero. This is the misleading
result the student must catch.
"""
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

df = pd.read_csv("incidents.csv")

X = df.drop(columns=["is_incident"])
y = df["is_incident"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

model = LogisticRegression(max_iter=1000)
model.fit(X_train, y_train)

pred = model.predict(X_test)
acc = accuracy_score(y_test, pred)

print(f"accuracy: {acc:.4f}")
print("Model looks great. Shipping it.")
PYEOF

echo "==> Generating the dataset"
python generate_data.py

echo "==> Running the NAIVE analysis so you can see the misleading result"
echo "-----------------------------------------------------------------"
python train.py
echo "-----------------------------------------------------------------"

cat <<EOF

==> Injection complete.

The naive model reports about 0.97 accuracy and says "shipping it." But the
positive class is only ~3% of the data. A model that always predicts "no
incident" would also score ~0.97 while catching zero real incidents.

Working directory: ${WORKDIR}
Files:
  generate_data.py  - builds incidents.csv (do not edit)
  train.py          - the naive, accuracy-only training (do not edit)
  incidents.csv     - the dataset

Now follow runbook.md to expose the useless model, fix the imbalance, and
document your findings.
Reference: Concepts 4.5 (Evaluation metrics and class imbalance).
EOF
