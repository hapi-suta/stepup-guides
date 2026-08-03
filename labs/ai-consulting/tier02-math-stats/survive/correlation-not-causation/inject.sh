#!/usr/bin/env bash
#
# SURVIVE chaos injector: correlation-not-causation
#
# Sets up a working directory where a stakeholder has written a claim that
# treats a real correlation (webinar attendance vs revenue) as if it were
# causation. The truth is that company size is a lurking/confounding variable
# that drives BOTH webinar attendance AND revenue. The student must catch the
# error, demonstrate the confound, and correct the write-up.
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12
#
set -euo pipefail

WORKDIR="${HOME}/survive-corr-causation"
VENV="${WORKDIR}/.venv"

echo "==> Creating working directory: ${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Creating Python virtual environment"
if [ ! -d "${VENV}" ]; then
  python3.12 -m venv "${VENV}"
fi

# shellcheck disable=SC1091
source "${VENV}/bin/activate"

echo "==> Upgrading pip and installing numpy + pandas (quietly)"
python -m pip install --quiet --upgrade pip
python -m pip install --quiet numpy pandas

echo "==> Writing dataset generator: generate_data.py"
cat > "${WORKDIR}/generate_data.py" <<'PYEOF'
"""
Generate a SaaS customer dataset where company size is a confounder.

Reality baked into the data:
  - company_size (1=small, 2=medium, 3=large, 4=enterprise) is the hidden
    driver.
  - Bigger companies attend MORE webinars (they have more staff and budget).
  - Bigger companies spend MORE revenue (they have bigger budgets).
  - The DIRECT effect of webinars on revenue is essentially zero.

Result: the raw correlation between webinars_attended and revenue looks
strong, but it is driven entirely by company size, not by webinars causing
revenue.
"""
import numpy as np
import pandas as pd

np.random.seed(42)

N = 800

# Hidden confounder: company size bucket 1..4, roughly even split.
company_size = np.random.randint(1, 5, size=N)

# Webinars attended increase with company size (bigger = attends more).
# Small noise so the buckets overlap a little but the trend is clear.
webinars_attended = (
    company_size * 3.0
    + np.random.normal(0, 1.2, size=N)
).round().clip(0, None).astype(int)

# Revenue is driven by company size, NOT by webinars.
# base_by_size makes bigger companies spend more.
# The coefficient on webinars_attended is 0 (no direct causal effect).
base_by_size = company_size * 20000.0
direct_webinar_effect = 0.0  # webinars do NOT cause revenue in this world
revenue = (
    base_by_size
    + direct_webinar_effect * webinars_attended
    + np.random.normal(0, 4000, size=N)
).round(2).clip(0, None)

size_label = {1: "small", 2: "medium", 3: "large", 4: "enterprise"}

df = pd.DataFrame(
    {
        "customer_id": np.arange(1, N + 1),
        "company_size": company_size,
        "company_size_label": [size_label[s] for s in company_size],
        "webinars_attended": webinars_attended,
        "revenue": revenue,
    }
)

df.to_csv("customers.csv", index=False)
print("Wrote customers.csv with {} rows".format(len(df)))
PYEOF

echo "==> Generating customers.csv"
cd "${WORKDIR}"
python generate_data.py

echo "==> Writing the naive analysis: analysis.py"
cat > "${WORKDIR}/analysis.py" <<'PYEOF'
"""
Naive analysis the stakeholder used to justify the claim.

It only looks at the RAW correlation between webinars_attended and revenue.
It does NOT account for company size, so it reaches a misleading conclusion.
"""
import pandas as pd

df = pd.read_csv("customers.csv")

raw_corr = df["webinars_attended"].corr(df["revenue"])

print("=== Naive analysis (what the stakeholder saw) ===")
print("Rows analyzed:", len(df))
print("Raw correlation (webinars_attended vs revenue): {:.3f}".format(raw_corr))
print()
print("Naive conclusion: 'Webinars are strongly correlated with revenue,")
print("therefore webinars CAUSE revenue. Mandate more webinars.'")
PYEOF

echo "==> Writing the stakeholder claim: stakeholder_claim.md"
cat > "${WORKDIR}/stakeholder_claim.md" <<'MDEOF'
# Proposal: Mandate Webinars to Boost Revenue

Author: VP of Customer Success
Status: Awaiting analyst sign-off

## The finding

I pulled our customer data and analyzed it. Customers who attend more
webinars have much higher revenue. The correlation is very strong.

Run `python analysis.py` to see it for yourself - the correlation between
webinars attended and revenue is over 0.6.

## The claim

The data proves that webinars drive revenue.

## The decision

We will mandate that ALL customers attend at least 5 webinars this quarter.
Based on the correlation, this should boost revenue by roughly 40 percent.
We are budgeting 250,000 dollars to run these mandatory webinars.

Please sign off so we can start spending.
MDEOF

echo "==> Running the naive analysis so you can see the misleading result"
echo "-----------------------------------------------------------------"
python "${WORKDIR}/analysis.py"
echo "-----------------------------------------------------------------"

deactivate || true

echo ""
echo "==> Chaos injected."
echo "    Working dir: ${WORKDIR}"
echo "    Read stakeholder_claim.md, then follow the runbook."
