#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# SURVIVE scenario: data-leakage
# Tier 4 - Classical machine learning (ai-consulting track)
#
# What this injects:
#   A synthetic fraud-style classification dataset that includes a LEAKED
#   feature - a column (refund_issued) that is set from the true label and
#   would NOT be known at prediction time. The naive train.py leaves it in,
#   so the model reports a suspiciously perfect ~0.99 accuracy.
#
# Student goal (see runbook.md):
#   Detect the too-good-to-be-true accuracy, identify the leaked feature,
#   drop it, retrain honestly (accuracy falls to a realistic ~0.82), and
#   document the finding.
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-data-leakage"

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
"""Generate a synthetic fraud-style dataset with a deliberately leaked feature.

The label is `is_fraud`. Most features (amount, num_prior_claims, account_age_days,
hour_of_day) are legitimate signals knowable at PREDICTION time.

The trap: `refund_issued` is filled in AFTER a case is investigated. It is a
near-perfect proxy for the label because refunds are almost always issued on
confirmed fraud. It is NOT available when we actually need to predict, so it
leaks the answer into training.
"""
import numpy as np
import pandas as pd

np.random.seed(42)

N = 4000

# True label: about 30% fraud so classes are not degenerate.
is_fraud = (np.random.rand(N) < 0.30).astype(int)

# Legitimate, prediction-time-knowable features. They carry SOME signal but
# are noisy, so an honest model lands around 0.82 accuracy.
amount = np.where(
    is_fraud == 1,
    np.random.normal(850, 300, N),
    np.random.normal(500, 250, N),
).clip(1, None)

num_prior_claims = np.where(
    is_fraud == 1,
    np.random.poisson(3.0, N),
    np.random.poisson(1.2, N),
)

account_age_days = np.where(
    is_fraud == 1,
    np.random.normal(120, 90, N),
    np.random.normal(600, 300, N),
).clip(1, None)

hour_of_day = np.random.randint(0, 24, N)

# LEAKED feature: refund_issued is set from the label. On confirmed fraud a
# refund is almost always issued; on legit cases it almost never is. This is
# only knowable AFTER the case is resolved, i.e. after the label exists.
noise = np.random.rand(N)
refund_issued = np.where(
    is_fraud == 1,
    (noise < 0.98).astype(int),   # 98% of fraud -> refund issued
    (noise < 0.02).astype(int),   # 2% of legit -> refund issued (rare mistakes)
)

df = pd.DataFrame({
    "amount": amount.round(2),
    "num_prior_claims": num_prior_claims,
    "account_age_days": account_age_days.round(0).astype(int),
    "hour_of_day": hour_of_day,
    "refund_issued": refund_issued,   # <-- the leak
    "is_fraud": is_fraud,
})

df.to_csv("fraud.csv", index=False)
print("Wrote fraud.csv with", len(df), "rows and columns:", list(df.columns))
PYEOF

echo "==> Writing train.py (the naive, leaky analysis)"
cat > train.py <<'PYEOF'
"""Naive training that INCLUDES the leaked feature.

Reports a suspiciously perfect accuracy. This is the misleading result the
student must catch. Do not trust it.
"""
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

df = pd.read_csv("fraud.csv")

# Everything except the label is used as a feature - including refund_issued.
X = df.drop(columns=["is_fraud"])
y = df["is_fraud"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

model = RandomForestClassifier(n_estimators=200, random_state=42)
model.fit(X_train, y_train)

pred = model.predict(X_test)
acc = accuracy_score(y_test, pred)

print("Features used:", list(X.columns))
print(f"accuracy: {acc:.4f}")
print("")
print("Feature importances:")
for name, imp in sorted(
    zip(X.columns, model.feature_importances_), key=lambda t: -t[1]
):
    print(f"  {name}: {imp:.4f}")
PYEOF

echo "==> Generating the dataset"
python generate_data.py

echo "==> Running the NAIVE analysis so you can see the misleading result"
echo "-----------------------------------------------------------------"
python train.py
echo "-----------------------------------------------------------------"

cat <<EOF

==> Injection complete.

The naive model above reports about 0.99 accuracy. That is almost never real
on a fraud problem. Something is leaking the answer.

Working directory: ${WORKDIR}
Files:
  generate_data.py  - builds fraud.csv (do not edit)
  train.py          - the naive, leaky training (do not edit)
  fraud.csv         - the dataset

Now follow runbook.md to detect the leak, fix it, and document your findings.
Reference: Concepts 4.4 (Data leakage in supervised learning).
EOF
