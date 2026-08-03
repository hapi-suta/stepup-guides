#!/usr/bin/env bash
# SURVIVE validate: prove the loop now stops on a sane limit, not the demo's
# hard safety backstop.
#
# PASS conditions (re-run the looping agent):
#   1. It stops for the right reason - "max_tool_calls" or "budget_exhausted" -
#      NOT "hard_safety_stop" (which would mean your real limits never fired).
#   2. The number of tool calls is small (bounded by your limit), proving the
#      cap actually bit.
#
# Run on the lab server (CentOS Stream 9), as ec2-user, from this directory:
#   bash validate.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE" || { echo "FAIL: cannot cd to scenario dir"; exit 1; }

if [ ! -f scenario.py ] || [ ! -f limits.json ]; then
    echo "FAIL: run inject.sh first (scenario.py / limits.json missing)"; exit 1
fi

python3 - <<'PY' || exit 1
import json, subprocess, sys

out = json.loads(subprocess.check_output([sys.executable, "scenario.py"], text=True))

# 1. Must stop for a real termination reason, not the demo backstop.
if out["stopped"] == "hard_safety_stop":
    print("FAIL: the loop only stopped at the demo backstop - your real limits never fired")
    sys.exit(1)
if out["stopped"] not in ("max_tool_calls", "budget_exhausted"):
    print(f"FAIL: unexpected stop reason '{out['stopped']}'")
    sys.exit(1)
print(f"OK: loop stopped on a real termination condition ({out['stopped']})")

# 2. The cap must actually bound the run to a small number.
if out["tool_calls"] > 1000:
    print(f"FAIL: {out['tool_calls']} tool calls is not a bounded loop")
    sys.exit(1)
print(f"OK: run bounded to {out['tool_calls']} tool calls (limit {out['limits']['MAX_TOOL_CALLS']})")

print("PASS: the runaway loop is now bounded by termination conditions.")
PY
