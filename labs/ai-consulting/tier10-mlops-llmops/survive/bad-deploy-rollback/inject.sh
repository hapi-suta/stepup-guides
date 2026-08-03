#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# SURVIVE scenario: bad-deploy-rollback
# Tier 10 - MLOps and LLMOps (ai-consulting track)
#
# What this injects:
#   A model registry (SQLite) with a healthy production model (v1) and a broken
#   candidate (v2). A deploy script promotes v2 to production. The serving
#   healthcheck then FAILS because v2's artifact is corrupt - a bad deploy has
#   shipped. Production is down.
#
# Student goal (see runbook.md):
#   Detect the bad deploy via the failing healthcheck, execute the rollback
#   procedure (registry.py rollback) to return production to the known-good v1,
#   prove the healthcheck passes again, and document the incident.
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12. Fully self-contained.
# =============================================================================

WORKDIR="${HOME}/survive-bad-deploy"

echo "==> Creating working directory at ${WORKDIR}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}/models"
cd "${WORKDIR}"

echo "==> Creating Python 3.12 virtual environment"
python3.12 -m venv .venv
# shellcheck disable=SC1091
source "${WORKDIR}/.venv/bin/activate"

echo "==> Installing scikit-learn, joblib (quiet)"
python -m pip install --quiet --upgrade pip
python -m pip install --quiet scikit-learn joblib numpy

echo "==> Writing registry.py (the model registry CLI)"
cat > registry.py <<'PYEOF'
"""Model registry CLI. 'production' is the run the deploy step serves."""
import sqlite3
import sys

DB = "registry.db"


def c():
    return sqlite3.connect(DB)


def cmd_list():
    rows = c().execute(
        "SELECT run_id, stage, artifact FROM models ORDER BY created_at"
    ).fetchall()
    if not rows:
        print("registry empty")
        return 1
    for run_id, stage, artifact in rows:
        print(f"{run_id:<12} {stage:<12} {artifact}")
    return 0


def cmd_current():
    row = c().execute(
        "SELECT run_id, artifact FROM models WHERE stage='production'"
    ).fetchone()
    if not row:
        print("no production model")
        return 1
    print(f"production run_id: {row[0]}")
    print(f"artifact: {row[1]}")
    return 0


def cmd_promote(run_id):
    con = c()
    if not con.execute("SELECT 1 FROM models WHERE run_id=?", (run_id,)).fetchone():
        print(f"run_id {run_id} not found")
        return 1
    con.execute("UPDATE models SET stage='archived' WHERE stage='production'")
    con.execute("UPDATE models SET stage='production' WHERE run_id=?", (run_id,))
    con.commit()
    print(f"promoted {run_id} to production")
    return 0


def cmd_rollback():
    con = c()
    prev = con.execute(
        "SELECT run_id FROM models WHERE stage='archived' ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    if not prev:
        print("no archived run to roll back to")
        return 1
    con.execute("UPDATE models SET stage='archived' WHERE stage='production'")
    con.execute("UPDATE models SET stage='production' WHERE run_id=?", (prev[0],))
    con.commit()
    print(f"rolled back: promoted previous run {prev[0]} to production")
    return 0


def main():
    a = sys.argv[1:]
    if not a:
        print("usage: registry.py [list|current|promote <id>|rollback]")
        return 1
    if a[0] == "list":
        return cmd_list()
    if a[0] == "current":
        return cmd_current()
    if a[0] == "promote":
        return cmd_promote(a[1])
    if a[0] == "rollback":
        return cmd_rollback()
    print(f"unknown command: {a[0]}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
PYEOF

echo "==> Writing seed_registry.py (creates v1 good + v2 broken and promotes v2)"
cat > seed_registry.py <<'PYEOF'
"""Seed the registry with a good v1 and a broken v2, then ship v2 (bad deploy)."""
import sqlite3

import joblib
import numpy as np
from sklearn.ensemble import RandomForestClassifier

DB = "registry.db"

# Train a real, working model and save it as v1's artifact.
rng = np.random.RandomState(0)
X = rng.rand(200, 4)
y = (X[:, 0] + X[:, 3] > 1.0).astype(int)
model = RandomForestClassifier(n_estimators=20, random_state=0).fit(X, y)
joblib.dump({"model": model, "features": ["a", "b", "c", "d"]}, "models/v1.joblib")

# v2's artifact is CORRUPT on purpose - not a valid joblib file.
with open("models/v2.joblib", "w") as fh:
    fh.write("this is not a valid model artifact\n")

con = sqlite3.connect(DB)
con.execute("DROP TABLE IF EXISTS models")
con.execute(
    "CREATE TABLE models (run_id TEXT PRIMARY KEY, created_at TEXT, "
    "stage TEXT, artifact TEXT)"
)
con.execute("INSERT INTO models VALUES ('v1', '2026-07-25T10:00:00', 'archived', 'models/v1.joblib')")
con.execute("INSERT INTO models VALUES ('v2', '2026-07-25T11:00:00', 'archived', 'models/v2.joblib')")
# The bad deploy: promote v2 to production.
con.execute("UPDATE models SET stage='production' WHERE run_id='v2'")
con.commit()
con.close()
print("seeded registry: v1 (good, archived), v2 (broken, production)")
print("a bad deploy just shipped v2 to production")
PYEOF

echo "==> Writing healthcheck.py (loads the production model and predicts once)"
cat > healthcheck.py <<'PYEOF'
"""Healthcheck: load the current production model and make one prediction.

Exit 0 if the production model loads and predicts, 1 if it does not. This is
what a load balancer or deploy gate calls to decide if a deploy is healthy.
"""
import sqlite3
import sys

import joblib

DB = "registry.db"


def main():
    row = sqlite3.connect(DB).execute(
        "SELECT run_id, artifact FROM models WHERE stage='production'"
    ).fetchone()
    if not row:
        print("HEALTH: FAIL - no production model")
        return 1
    run_id, artifact = row
    try:
        bundle = joblib.load(artifact)
        bundle["model"].predict([[0.5, 0.5, 0.5, 0.5]])
    except Exception as exc:
        print(f"HEALTH: FAIL - production model {run_id} did not load/predict: {exc}")
        return 1
    print(f"HEALTH: OK - production model {run_id} loaded and predicted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

echo "==> Seeding the registry (this performs the bad deploy)"
python seed_registry.py

echo "==> Running the healthcheck so you can see production is DOWN"
echo "-----------------------------------------------------------------"
python healthcheck.py || true
echo "-----------------------------------------------------------------"

cat <<EOF

==> Injection complete.

A bad deploy shipped v2 to production, but v2's artifact is corrupt, so the
healthcheck FAILS - production cannot serve predictions.

Working directory: ${WORKDIR}
Files:
  registry.py      - the registry CLI (list/current/promote/rollback)
  seed_registry.py - created v1 (good) and v2 (broken); do not edit
  healthcheck.py   - the deploy healthcheck; do not edit
  models/          - v1.joblib (good), v2.joblib (corrupt)

Now follow runbook.md to detect the bad deploy, roll back to v1, prove the
healthcheck passes, and document the incident.
Reference: Concepts 10.1 (rollback) and 10.4 (canary/validation gates).
EOF
