#!/usr/bin/env bash
# SURVIVE validate: prove the agent recovers from a tool timeout without
# corrupting its state.
#
# PASS conditions (re-run the agent with the flaky tool):
#   1. The run did NOT crash.
#   2. The failed tool call is recorded as an error in the audit trail (the
#      failure became an observation, not an exception).
#   3. The agent recovered - it called the cached fallback and still wrote the
#      report.
#
# Run on the lab server (CentOS Stream 9), as ec2-user, from this directory:
#   bash validate.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE" || { echo "FAIL: cannot cd to scenario dir"; exit 1; }

if [ ! -f scenario.py ] || [ ! -f config.json ]; then
    echo "FAIL: run inject.sh first (scenario.py / config.json missing)"; exit 1
fi

python3 - <<'PY' || exit 1
import json, subprocess, sys

out = json.loads(subprocess.check_output([sys.executable, "scenario.py"], text=True))

# 1. Must not crash.
if out.get("crashed"):
    print("FAIL: the run crashed on the tool timeout - state was corrupted mid-plan")
    sys.exit(1)
print("OK: the run did not crash")

# 2. The failure must be an observation (an errored tool_call), not silence.
if not any(a.get("event") == "tool_call" and a.get("ok") is False for a in out["audit"]):
    print("FAIL: no errored tool call recorded - the failure was not turned into an observation")
    sys.exit(1)
print("OK: the tool failure was caught and recorded as an observation")

# 3. Recovery: the fallback ran and the report was written.
if not any(a.get("event") == "tool_call" and a.get("name") == "cached_metrics" and a.get("ok") for a in out["audit"]):
    print("FAIL: the agent did not fall back to cached_metrics")
    sys.exit(1)
if not out.get("report_written"):
    print("FAIL: the report was not written - the agent did not recover")
    sys.exit(1)
print("OK: the agent fell back to cached metrics and wrote the report")

print("PASS: the agent recovered from the tool timeout without corrupting state.")
PY
