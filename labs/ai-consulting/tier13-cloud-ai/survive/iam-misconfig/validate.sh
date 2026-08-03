#!/usr/bin/env bash
#
# SURVIVE validator: iam-misconfig
# PASS only if BOTH policies are locked down: check_iam.py exits 0
# (no wildcard IAM action/resource, no public bucket principal).
# All local JSON - no real cloud, no credentials.
# Run on the lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-iam-misconfig"

fail() { echo "FAIL: $1"; exit 1; }

[[ -f "${WORKDIR}/check_iam.py" ]]     || fail "check_iam.py not found. Run inject.sh first."
[[ -f "${WORKDIR}/iam_policy.json" ]]  || fail "iam_policy.json not found. Run inject.sh first."
[[ -f "${WORKDIR}/bucket_policy.json" ]] || fail "bucket_policy.json not found. Run inject.sh first."

cd "${WORKDIR}"
echo "Evaluating the IAM and bucket policies ..."
if OUTPUT="$(python3 check_iam.py 2>&1)"; then
  echo "${OUTPUT}"
  echo "PASS: IAM is least-privilege and the bucket is not publicly readable."
  exit 0
else
  echo "${OUTPUT}"
  fail "policies still expose access. Remove wildcard actions/resources and the public bucket principal."
fi
