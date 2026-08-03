#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# SURVIVE scenario: provider-model-deprecation
# Tier 10 - MLOps and LLMOps (ai-consulting track)
#
# What this injects:
#   An LLM app that pins a specific provider model VERSION in a model registry.
#   The provider has deprecated that version: calls to it now fail ("model
#   deprecated"). The app's health probe FAILS because the active model no
#   longer exists. A replacement version is available and registered.
#
# Student goal (see runbook.md):
#   Detect the deprecation via the failing probe, cut over to the replacement
#   model version by promoting it in the registry (no code change, no downtime),
#   prove the probe passes on the new version, and document the cutover.
#   Everything runs offline (mock provider simulates the deprecation).
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12. Fully self-contained.
# =============================================================================

WORKDIR="${HOME}/survive-model-deprecation"

echo "==> Creating working directory at ${WORKDIR}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Creating Python 3.12 virtual environment"
python3.12 -m venv .venv
# shellcheck disable=SC1091
source "${WORKDIR}/.venv/bin/activate"
python -m pip install --quiet --upgrade pip

echo "==> Writing provider.py (mock provider that deprecates one model version)"
cat > provider.py <<'PYEOF'
"""Mock LLM provider. Some model versions are DEPRECATED and now fail.

This simulates a real provider retiring a model version. Calling a deprecated
model raises an error, exactly as the real API would return an error for a
retired model. Available versions answer normally. No network or key needed.
"""

# Which model versions the provider still serves. The pinned one is gone.
DEPRECATED = {"support-model-2024-01"}
AVAILABLE = {"support-model-2025-06", "support-model-2025-11"}


class ModelDeprecatedError(RuntimeError):
    pass


def call(model_version, prompt):
    if model_version in DEPRECATED:
        raise ModelDeprecatedError(
            f"model {model_version} has been deprecated by the provider"
        )
    if model_version in AVAILABLE:
        return f"[{model_version}] answer: refunds are within 30 days with a receipt."
    raise RuntimeError(f"unknown model version: {model_version}")
PYEOF

echo "==> Writing model_registry.py (which model version the app is pinned to)"
cat > model_registry.py <<'PYEOF'
"""Registry of provider model versions. 'active' is what the app calls.

Commands:
  list            show registered model versions and their status
  active          show the active model version
  promote <ver>   make <ver> the active version (cut over)
"""
import sqlite3
import sys

DB = "model_registry.db"


def c():
    return sqlite3.connect(DB)


def cmd_list():
    rows = c().execute("SELECT version, status FROM model_versions ORDER BY version").fetchall()
    if not rows:
        print("registry empty")
        return 1
    for version, status in rows:
        print(f"{version:<26} {status}")
    return 0


def cmd_active():
    row = c().execute("SELECT version FROM model_versions WHERE status='active'").fetchone()
    if not row:
        print("no active model version")
        return 1
    print(f"active model version: {row[0]}")
    return 0


def cmd_promote(version):
    con = c()
    if not con.execute("SELECT 1 FROM model_versions WHERE version=?", (version,)).fetchone():
        print(f"version {version} not registered")
        return 1
    con.execute("UPDATE model_versions SET status='standby' WHERE status='active'")
    con.execute("UPDATE model_versions SET status='active' WHERE version=?", (version,))
    con.commit()
    print(f"cut over: {version} is now the active model version")
    return 0


def main():
    a = sys.argv[1:]
    if not a:
        print("usage: model_registry.py [list|active|promote <version>]")
        return 1
    if a[0] == "list":
        return cmd_list()
    if a[0] == "active":
        return cmd_active()
    if a[0] == "promote":
        return cmd_promote(a[1])
    print(f"unknown command: {a[0]}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
PYEOF

echo "==> Writing seed_models.py (pins the app to the soon-deprecated version)"
cat > seed_models.py <<'PYEOF'
"""Register model versions and pin the app to the (now deprecated) 2024 model."""
import sqlite3

DB = "model_registry.db"
con = sqlite3.connect(DB)
con.execute("DROP TABLE IF EXISTS model_versions")
con.execute("CREATE TABLE model_versions (version TEXT PRIMARY KEY, status TEXT)")
# The app is pinned to the 2024 version - which the provider has now retired.
con.execute("INSERT INTO model_versions VALUES ('support-model-2024-01', 'active')")
con.execute("INSERT INTO model_versions VALUES ('support-model-2025-06', 'standby')")
con.execute("INSERT INTO model_versions VALUES ('support-model-2025-11', 'standby')")
con.commit()
con.close()
print("registered 3 model versions; active = support-model-2024-01 (now deprecated)")
PYEOF

echo "==> Writing probe.py (health probe: calls the active model version)"
cat > probe.py <<'PYEOF'
"""Health probe: call the ACTIVE model version once.

Exit 0 if the active model answers, 1 if it fails (e.g. deprecated). This is
what an uptime check or deploy gate calls to know the app can reach its model.
"""
import sqlite3
import sys

import provider

DB = "model_registry.db"


def main():
    row = sqlite3.connect(DB).execute(
        "SELECT version FROM model_versions WHERE status='active'"
    ).fetchone()
    if not row:
        print("PROBE: FAIL - no active model version")
        return 1
    version = row[0]
    try:
        provider.call(version, "What is the refund policy?")
    except Exception as exc:
        print(f"PROBE: FAIL - active model {version} unusable: {exc}")
        return 1
    print(f"PROBE: OK - active model {version} answered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

echo "==> Seeding the model registry"
python seed_models.py

echo "==> Running the health probe so you can see the app is DOWN"
echo "-----------------------------------------------------------------"
python probe.py || true
echo "-----------------------------------------------------------------"

cat <<EOF

==> Injection complete.

The provider deprecated support-model-2024-01, which the app is pinned to. The
health probe FAILS because the active model version no longer exists. A
replacement (support-model-2025-06 or -2025-11) is already registered on
standby.

Working directory: ${WORKDIR}
Files:
  provider.py         - mock provider; the 2024 model is deprecated; do not edit
  model_registry.py   - the model-version registry CLI
  seed_models.py      - seeded the versions; do not edit
  probe.py            - the health probe; do not edit
  model_registry.db   - the registry (active = the dead 2024 version)

Now follow runbook.md to cut over to a supported model version via the registry
(no code change, no downtime), prove the probe passes, and document the cutover.
Reference: Concepts 10.3 (model versioning) and 10.5 (model-provider changes).
EOF
