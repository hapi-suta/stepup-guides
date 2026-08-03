#!/usr/bin/env bash
#
# SURVIVE: kms-rotation-break
# A mock Secrets Manager / KMS stores secret versions in secrets_store.json. The
# app (app_secret.py) reads the secret by a PINNED version id. inject.sh then
# ROTATES the secret: a new active version is created and the old one is disabled
# - exactly what a scheduled KMS/Secrets rotation does. The app, pinned to the
# old version, now fails to decrypt/read - the feature breaks after rotation.
#
# No real cloud / credentials needed - the mock store is local JSON, so you fix
# the resilience LOGIC (read the ACTIVE version, not a pinned one) for free.
#
# Run on your lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-kms-rotation"
echo "==> Creating working directory: ${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Writing secrets_store.json (initial: version v1 is ACTIVE)"
cat > secrets_store.json <<'JSON'
{
  "secret_name": "ai-app/model-api-key",
  "versions": {
    "v1": {"status": "ACTIVE", "value": "key-AAAA-initial"}
  }
}
JSON

echo "==> Writing secrets_client.py (the mock Secrets Manager reader)"
cat > secrets_client.py <<'PYEOF'
#!/usr/bin/env python3
"""Mock Secrets Manager. get_secret(version=None):
  - version given  -> return that version ONLY if it is ACTIVE (else raise)
  - version None   -> return whichever version is ACTIVE (rotation-safe)
Mirrors real behavior: a disabled/old version cannot be read after rotation."""
import json


class SecretError(Exception):
    pass


def _load():
    with open("secrets_store.json") as fh:
        return json.load(fh)


def get_secret(version=None):
    store = _load()
    versions = store["versions"]
    if version is not None:
        v = versions.get(version)
        if v is None:
            raise SecretError(f"version {version} does not exist")
        if v["status"] != "ACTIVE":
            raise SecretError(f"version {version} is {v['status']}, cannot read")
        return v["value"]
    # No version pinned: return the current ACTIVE version (rotation-safe).
    for name, v in versions.items():
        if v["status"] == "ACTIVE":
            return v["value"]
    raise SecretError("no ACTIVE version found")
PYEOF

echo "==> Writing app_secret.py (BROKEN: pins version v1)"
cat > app_secret.py <<'PYEOF'
#!/usr/bin/env python3
"""App that reads the model API key from the mock secrets store.

BUG (this is the SURVIVE scenario): it PINS version 'v1'. After a rotation makes
v1 inactive and v2 active, this call fails and the app cannot authenticate.
Your job (runbook.md) is to read the ACTIVE version instead of a pinned one.
"""
from secrets_client import get_secret

PINNED_VERSION = "v1"  # BUG: pinned to a version that rotation will disable


def load_api_key() -> str:
    return get_secret(version=PINNED_VERSION)


if __name__ == "__main__":
    key = load_api_key()
    # RESULT line lets the validator confirm the app read a working key.
    print("RESULT api_key_loaded=" + key)
PYEOF

echo
echo "==> Confirming the app works BEFORE rotation:"
python3 app_secret.py || true

echo
echo "==> ROTATING the secret now (v2 becomes ACTIVE, v1 becomes DISABLED)..."
cat > secrets_store.json <<'JSON'
{
  "secret_name": "ai-app/model-api-key",
  "versions": {
    "v1": {"status": "DISABLED", "value": "key-AAAA-initial"},
    "v2": {"status": "ACTIVE", "value": "key-BBBB-rotated"}
  }
}
JSON

echo
echo "==> Running the app AFTER rotation so you can see it break:"
echo "-------------------------------------------------------------"
python3 app_secret.py || true
echo "-------------------------------------------------------------"
echo
echo "Rotation disabled v1, but the app is pinned to v1, so it can no longer read"
echo "the key. Open runbook.md and make the app read the ACTIVE version."
