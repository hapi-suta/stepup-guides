#!/usr/bin/env bash
#
# SURVIVE validator: kms-rotation-break
# PASS only if, AFTER rotation (v1 DISABLED, v2 ACTIVE), the app runs cleanly
# and loads the ROTATED key (v2's value). Proves the app reads the ACTIVE
# version instead of a pinned one. All local JSON - no real cloud, no creds.
# Run on the lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-kms-rotation"
fail() { echo "FAIL: $1"; exit 1; }

[[ -f "${WORKDIR}/app_secret.py" ]]    || fail "app_secret.py not found. Run inject.sh first."
[[ -f "${WORKDIR}/secrets_store.json" ]] || fail "secrets_store.json not found. Run inject.sh first."

cd "${WORKDIR}"

# Ensure the store is in the ROTATED state (v1 disabled, v2 active).
echo "Ensuring the secret is in the rotated state (v1 DISABLED, v2 ACTIVE) ..."
cat > secrets_store.json <<'JSON'
{
  "secret_name": "ai-app/model-api-key",
  "versions": {
    "v1": {"status": "DISABLED", "value": "key-AAAA-initial"},
    "v2": {"status": "ACTIVE", "value": "key-BBBB-rotated"}
  }
}
JSON

echo "Running app_secret.py after rotation ..."
if ! OUTPUT="$(python3 app_secret.py 2>&1)"; then
  echo "${OUTPUT}"
  fail "app_secret.py crashed after rotation. Read the ACTIVE version, not a pinned one."
fi
echo "${OUTPUT}"

RESULT_LINE="$(printf '%s\n' "${OUTPUT}" | grep -E '^RESULT ' | tail -n 1 || true)"
[[ -n "${RESULT_LINE}" ]] || fail "no RESULT line printed."

if printf '%s\n' "${RESULT_LINE}" | grep -q 'api_key_loaded=key-BBBB-rotated'; then
  echo "PASS: after rotation the app loaded the new ACTIVE key (v2) with no downtime."
  exit 0
else
  fail "app did not load the rotated key. It must read the ACTIVE version."
fi
