#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# SURVIVE scenario: concept-drift
# Tier 4 - Classical machine learning (ai-consulting track)
#
# What this injects:
#   A model (model_v1) trained on "old" data (period 1) that scored ~0.90 in
#   training. It is deployed and now scores "new" production data (period 2)
#   whose distribution has SHIFTED - feature means moved and the boundary
#   changed. Live accuracy has degraded to ~0.63. A monitor.py shows both the
#   accuracy drop and a simple feature-mean shift signal.
#
# Student goal (see runbook.md):
#   Detect the accuracy drop and the distribution shift, diagnose concept
#   drift / dataset shift, decide to RETRAIN on recent data (justified over
#   retire), write retrain.py that recovers accuracy to ~0.88, and document
#   the detection, decision, and a monitoring plan.
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
# =============================================================================

WORKDIR="${HOME}/survive-concept-drift"

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
"""Generate two periods of data with a distribution + concept shift.

Period 1 (train_old.csv): the world the model was trained on.
Period 2 (prod_new.csv): production data after the world shifted. Feature means
move and the label rule changes, so a model fit on period 1 degrades on
period 2.
"""
import numpy as np
import pandas as pd

np.random.seed(42)

def make_period(n, shift, seed):
    rng = np.random.default_rng(seed)
    # Two features. In period 2 both means shift upward.
    f1 = rng.normal(0.0 + shift, 1.0, n)
    f2 = rng.normal(0.0 + shift, 1.0, n)
    f3 = rng.normal(0.0, 1.0, n)  # noise feature, stable across periods
    noise = rng.normal(0.0, 0.5, n)
    if shift == 0.0:
        # Period 1 concept: label driven mostly by f1 + f2.
        score = 1.2 * f1 + 1.0 * f2 + noise
    else:
        # Period 2 concept drift: the relationship changes. f2 flips sign and
        # f3 now matters. A period-1 model has the wrong rule.
        score = 1.2 * f1 - 1.0 * f2 + 0.8 * f3 + noise
    y = (score > np.median(score)).astype(int)
    return pd.DataFrame({"f1": f1, "f2": f2, "f3": f3, "label": y})

old = make_period(3000, shift=0.0, seed=1)
new = make_period(3000, shift=1.5, seed=2)

old.to_csv("train_old.csv", index=False)
new.to_csv("prod_new.csv", index=False)

print("Wrote train_old.csv (period 1) and prod_new.csv (period 2)")
print("period 1 feature means:")
print(old[["f1", "f2", "f3"]].mean().round(3).to_string())
print("period 2 feature means:")
print(new[["f1", "f2", "f3"]].mean().round(3).to_string())
PYEOF

echo "==> Writing train_v1.py (trains the deployed model on OLD data)"
cat > train_v1.py <<'PYEOF'
"""Train model_v1 on period-1 data and save it. This is the deployed model."""
import pandas as pd
import pickle
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

old = pd.read_csv("train_old.csv")
X = old[["f1", "f2", "f3"]]
y = old["label"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

model = RandomForestClassifier(n_estimators=200, random_state=42)
model.fit(X_train, y_train)

acc = accuracy_score(y_test, model.predict(X_test))
print(f"training_accuracy_period1: {acc:.4f}")

with open("model_v1.pkl", "wb") as fh:
    pickle.dump(model, fh)
print("Saved model_v1.pkl")
PYEOF

echo "==> Writing monitor.py (scores the deployed model on NEW data)"
cat > monitor.py <<'PYEOF'
"""Monitor model_v1 against period-2 production data.

Shows the live accuracy drop plus a simple distribution-shift signal: the
change in each feature's mean between the training period and production.
"""
import pandas as pd
import pickle
from sklearn.metrics import accuracy_score

with open("model_v1.pkl", "rb") as fh:
    model = pickle.load(fh)

old = pd.read_csv("train_old.csv")
new = pd.read_csv("prod_new.csv")

X_new = new[["f1", "f2", "f3"]]
y_new = new["label"]

live_acc = accuracy_score(y_new, model.predict(X_new))
print(f"live_accuracy_period2: {live_acc:.4f}")
print("")

print("Feature-mean shift (period2 - period1):")
for col in ["f1", "f2", "f3"]:
    delta = new[col].mean() - old[col].mean()
    flag = "  <-- SHIFTED" if abs(delta) > 0.5 else ""
    print(f"  {col}: {delta:+.3f}{flag}")
PYEOF

echo "==> Generating the two periods of data"
python generate_data.py

echo "==> Training the deployed model on OLD data"
echo "-----------------------------------------------------------------"
python train_v1.py
echo "-----------------------------------------------------------------"

echo "==> Running the monitor against NEW production data"
echo "-----------------------------------------------------------------"
python monitor.py
echo "-----------------------------------------------------------------"

cat <<EOF

==> Injection complete.

model_v1 scored about 0.90 in training on period-1 data, but the monitor shows
it scores about 0.63 on period-2 production data, and the feature means have
moved. The world the model learned no longer matches production.

Working directory: ${WORKDIR}
Files:
  generate_data.py  - builds train_old.csv + prod_new.csv (do not edit)
  train_v1.py       - trains the deployed model_v1 (do not edit)
  monitor.py        - scores model_v1 on new data + shows shift (do not edit)
  model_v1.pkl      - the deployed model
  train_old.csv     - period 1 (training world)
  prod_new.csv      - period 2 (production world)

Now follow runbook.md to detect the drift, decide retrain vs retire, retrain,
and document your findings.
Reference: Concepts 4.6 (Concept drift and model monitoring).
EOF
