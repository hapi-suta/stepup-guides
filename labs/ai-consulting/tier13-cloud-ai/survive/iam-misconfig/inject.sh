#!/usr/bin/env bash
#
# SURVIVE: iam-misconfig
# A mock cloud stores an IAM-style policy (JSON) for the AI app plus a mock S3
# bucket policy. Both are MISCONFIGURED: the IAM policy grants "bedrock:*" and
# "s3:*" on "*" (full wildcard), and the bucket allows public "*" principal
# read. So the app's identity is wildly over-privileged and the model-input
# bucket is world-readable - the classic cloud AI exposure.
#
# No real cloud / credentials needed - everything is local JSON that a checker
# script evaluates, so you fix the resilience/security LOGIC for free.
#
# Run on your lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-iam-misconfig"
echo "==> Creating working directory: ${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Writing iam_policy.json (MISCONFIGURED: full wildcards)"
cat > iam_policy.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AppPermissions",
      "Effect": "Allow",
      "Action": ["bedrock:*", "s3:*"],
      "Resource": "*"
    }
  ]
}
JSON

echo "==> Writing bucket_policy.json (MISCONFIGURED: public read)"
cat > bucket_policy.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::client-ai-inputs/*"
    }
  ]
}
JSON

echo "==> Writing check_iam.py (evaluates the policies for exposure)"
cat > check_iam.py <<'PYEOF'
#!/usr/bin/env python3
"""Evaluate the mock IAM + bucket policy for exposure. Exit 0 only if BOTH are
locked down: no wildcard action/resource in IAM, no public principal on bucket.
Mirrors what an AWS security review (or Access Analyzer) would flag."""
import json
import sys


def load(path):
    with open(path) as fh:
        return json.load(fh)


def findings():
    issues = []
    iam = load("iam_policy.json")
    for stmt in iam.get("Statement", []):
        actions = stmt.get("Action", [])
        actions = [actions] if isinstance(actions, str) else actions
        resources = stmt.get("Resource", [])
        resources = [resources] if isinstance(resources, str) else resources
        if any(a.endswith(":*") or a == "*" for a in actions):
            issues.append(f"IAM: wildcard action {actions}")
        if "*" in resources:
            issues.append("IAM: wildcard resource '*'")

    bucket = load("bucket_policy.json")
    for stmt in bucket.get("Statement", []):
        if stmt.get("Effect") == "Allow" and stmt.get("Principal") == "*":
            issues.append("BUCKET: public principal '*' can read objects")
    return issues


if __name__ == "__main__":
    issues = findings()
    if issues:
        print("EXPOSED")
        for i in issues:
            print(" - " + i)
        sys.exit(1)
    print("LOCKED_DOWN: no wildcard IAM and no public bucket access")
    sys.exit(0)
PYEOF

echo
echo "==> Running check_iam.py so you can see the exposure:"
echo "-------------------------------------------------------------"
cd "${WORKDIR}"
python3 check_iam.py || true
echo "-------------------------------------------------------------"
echo
echo "The IAM policy grants full wildcards and the bucket is world-readable."
echo "Open runbook.md and lock both down to least privilege."
