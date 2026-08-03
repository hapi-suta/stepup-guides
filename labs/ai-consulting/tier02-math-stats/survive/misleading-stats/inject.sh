#!/usr/bin/env bash
set -euo pipefail

# SUTA Labs - SURVIVE chaos scenario: misleading-stats
# Injects a dataset + a naive analysis that reports a "significant" result
# which is really an artifact of sampling / selection bias.
#
# Run as ec2-user on CentOS Stream 9. Safe to re-run (idempotent-ish).

WORKDIR="${HOME}/survive-misleading-stats"
VENV="${WORKDIR}/venv"

echo "=== SURVIVE: misleading-stats - injecting scenario ==="
echo

# 1. Create the working directory
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

# 2. Write the dataset generator
cat > "${WORKDIR}/generate_data.py" <<'PYEOF'
"""
Generate a customers.csv where Feature-X users are a BIASED sample.

The trap:
  Feature X was only ever offered to long-tenure customers (tenure >= 24
  months). Long-tenure customers already retain better regardless of Feature
  X. So a raw comparison of "Feature X users vs everyone else" mixes up the
  feature effect with the tenure effect. This is selection / sampling bias.
"""
import numpy as np
import pandas as pd

np.random.seed(42)

N = 4000

# Tenure in months, spread across new and old customers.
tenure = np.random.randint(1, 49, size=N)  # 1..48 months

# Base retention probability rises with tenure. Older customers stick around
# more. This is the real driver, NOT the feature.
base_retention_prob = 0.30 + 0.010 * tenure  # ~0.31 at 1mo, ~0.78 at 48mo
base_retention_prob = np.clip(base_retention_prob, 0.0, 0.95)

# Feature X was ONLY offered to tenure >= 24 customers, and even then only
# some opted in. New/short-tenure customers could never get Feature X.
eligible = tenure >= 24
uses_feature_x = np.zeros(N, dtype=int)
# Among eligible customers, ~60% actually use Feature X.
opt_in = np.random.rand(N) < 0.60
uses_feature_x[eligible & opt_in] = 1

# TRUE feature effect is essentially zero. Retention is driven by tenure.
# (We add a tiny 1% bump so the honest answer is "negligible", not exactly 0.)
true_feature_bump = 0.01 * uses_feature_x
retention_prob = np.clip(base_retention_prob + true_feature_bump, 0.0, 0.98)

retained = (np.random.rand(N) < retention_prob).astype(int)

df = pd.DataFrame(
    {
        "customer_id": np.arange(1, N + 1),
        "tenure_months": tenure,
        "uses_feature_x": uses_feature_x,
        "retained": retained,
    }
)

df.to_csv("customers.csv", index=False)
print("Wrote customers.csv with", len(df), "rows")
print("Feature-X users:", int(df.uses_feature_x.sum()))
print("Non-Feature-X users:", int((df.uses_feature_x == 0).sum()))
PYEOF

# 3. Write the NAIVE analysis (the misleading one)
cat > "${WORKDIR}/naive_analysis.py" <<'PYEOF'
"""
NAIVE analysis. Runs a raw two-sample t-test on retention between
Feature-X users and everyone else, then declares victory.

This is the WRONG analysis. It ignores that the two groups are not
comparable (Feature-X users are all long-tenure customers).
"""
import pandas as pd
from scipy import stats

df = pd.read_csv("customers.csv")

x_users = df[df.uses_feature_x == 1]["retained"]
non_users = df[df.uses_feature_x == 0]["retained"]

x_rate = x_users.mean()
non_rate = non_users.mean()
lift = (x_rate - non_rate) / non_rate * 100.0

t_stat, p_value = stats.ttest_ind(x_users, non_users, equal_var=False)

print("=== NAIVE RETENTION ANALYSIS ===")
print(f"Feature-X retention rate:   {x_rate:.3f}")
print(f"Non-Feature-X retention:    {non_rate:.3f}")
print(f"Relative lift:              {lift:.1f}%")
print(f"t-statistic:                {t_stat:.3f}")
print(f"p-value:                    {p_value:.2e}")
print()
if p_value < 0.001:
    print("CONCLUSION: Feature X drives a HUGE, highly significant lift in")
    print("retention (p < 0.001). SHIP IT to everyone!")
else:
    print("CONCLUSION: No strong evidence.")
PYEOF

# 4. Create a Python virtual environment and install the stats libraries
echo "--- Creating Python 3.12 virtual environment ---"
if [ ! -d "${VENV}" ]; then
  python3.12 -m venv "${VENV}"
fi

# shellcheck disable=SC1091
source "${VENV}/bin/activate"

python -m pip install --quiet --upgrade pip
python -m pip install --quiet numpy pandas scipy

# 5. Generate the data
echo "--- Generating biased dataset ---"
python "${WORKDIR}/generate_data.py"
echo

# 6. Run the naive analysis so the student sees the misleading result
echo "--- Running the naive analysis (this result is a TRAP) ---"
python "${WORKDIR}/naive_analysis.py"

deactivate

echo
echo "=== INJECTION COMPLETE ==="
echo
echo "A 'statistically significant' result has been reported above."
echo "It claims Feature X massively boosts retention. Your job: find out"
echo "why this result is misleading and produce a corrected analysis."
echo
echo "Working directory: ${WORKDIR}"
echo "Open the runbook and follow the 3 layers to fix it."
