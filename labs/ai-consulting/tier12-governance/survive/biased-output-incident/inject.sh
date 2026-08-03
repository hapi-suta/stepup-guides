#!/usr/bin/env bash
set -euo pipefail

# SUTA Labs - SURVIVE chaos scenario: biased-output-incident
# A "model update" ships that silently pushes the disparate-impact ratio of a
# hiring-screen model below the 0.80 four-fifths threshold - a biased/harmful
# output incident. The student must detect it with the fairness monitor, run
# the incident-reporting process end to end (fill an incident report), and
# remediate (revert the change or fix the feature) so the ratio recovers.
#
# Run as ec2-user on CentOS Stream 9. Uses a Python venv with pandas + sklearn.
# Safe to re-run (idempotent-ish).

WORKDIR="${HOME}/survive-biased-output"
VENV="${WORKDIR}/venv"

echo "=== SURVIVE: biased-output-incident - injecting scenario ==="
echo

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

# 1. Write the model+monitor. It has TWO modes controlled by model_config.txt:
#    "v1" = balanced feature set (fair), "v2" = the bad update that drops a
#    balancing feature and leans on a proxy (unfair).
cat > "${WORKDIR}/model_config.txt" <<'CFGEOF'
v2
CFGEOF

cat > "${WORKDIR}/fairness_monitor.py" <<'PYEOF'
"""
Fairness monitor for the hiring-screen model. Reads model_config.txt to
decide which model version is deployed, trains it, and reports the
disparate-impact ratio per the four-fifths rule (flag below 0.80).

  v1 = balanced model (uses experience + a skills score) -> fair
  v2 = bad update (uses experience only, a proxy for group) -> biased

Exit code 0 if fair (ratio >= 0.80), 1 if biased (ratio < 0.80).
"""
import sys
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression

version = open("model_config.txt").read().strip()

rng = np.random.default_rng(7)
N = 2000
group = rng.choice(["A", "B"], size=N)

# experience is correlated with group in this dataset (a proxy).
experience = np.where(
    group == "A", rng.normal(8, 3, size=N), rng.normal(6, 3, size=N)
).clip(0, None)

# skills_score is a fair, group-INDEPENDENT signal of true ability, on the
# same scale as experience so the model can weigh them together.
skills_score = rng.normal(7, 3, size=N).clip(0, None)

# True qualification depends MOSTLY on skills (the fair signal) with a small
# real contribution from experience. A model that keeps skills (v1) is fair.
# A model that keeps ONLY experience (v2) has to lean on a proxy for group
# and reproduces the group gap - but still advances a healthy fraction, so
# the rates are realistic (not all-zero).
score = 3.0 * skills_score + 1.0 * experience + rng.normal(0, 1, size=N)
qualified = (score > np.percentile(score, 55)).astype(int)

df = pd.DataFrame(
    {"group": group, "experience": experience,
     "skills_score": skills_score, "qualified": qualified}
)

if version == "v1":
    features = ["experience", "skills_score"]  # balanced -> fair
else:
    features = ["experience"]                   # proxy only -> biased

X = df[features].values
y = df["qualified"].values
model = LogisticRegression(max_iter=1000).fit(X, y)
df["advanced"] = model.predict(X)

print(f"=== FAIRNESS MONITOR (deployed model: {version}) ===")
rates = {}
for g, sub in df.groupby("group"):
    r = sub["advanced"].mean()
    rates[g] = r
    print(f"  Group {g}: selection rate = {r:.3f}")

lo, hi = min(rates.values()), max(rates.values())
ratio = lo / hi if hi > 0 else float("nan")
print(f"\nDisparate-impact ratio: {ratio:.3f}")
if ratio < 0.80:
    print("ALERT: below 0.80 four-fifths threshold. BIASED OUTPUT INCIDENT.")
    sys.exit(1)
else:
    print("OK: at or above 0.80.")
    sys.exit(0)
PYEOF

# 2. Create the venv and install libraries.
echo "--- Creating Python 3.12 virtual environment ---"
if [ ! -d "${VENV}" ]; then
  python3.12 -m venv "${VENV}"
fi
# shellcheck disable=SC1091
source "${VENV}/bin/activate"
python -m pip install --quiet --upgrade pip
python -m pip install --quiet numpy pandas scikit-learn

# 3. Run the monitor to show the incident.
echo "--- Running the fairness monitor (this should ALERT) ---"
python "${WORKDIR}/fairness_monitor.py" || true
deactivate

echo
echo "=== INJECTION COMPLETE ==="
echo
echo "A model update (v2) shipped and the disparate-impact ratio dropped below"
echo "0.80: the model now advances one group far more than the other. This is a"
echo "biased-output incident. Your job: run the incident process end to end -"
echo "file an incident report AND remediate so the monitor is fair again."
echo
echo "Working directory: ${WORKDIR}"
echo "Open the runbook and follow the 3 layers."
