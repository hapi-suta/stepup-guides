#!/usr/bin/env bash
#
# SURVIVE: cost-anomaly
# A mock cloud AI usage meter (meter.py) accumulates per-call cost. The client
# app (batch_job.py) runs a batch that HAMMERS the model in a loop with NO
# budget cap, driving spend far past the monthly budget - a cost anomaly, the
# kind a CloudWatch/Cloud Monitoring alarm would catch. The monitor (alarm.py)
# fires when spend crosses the budget. Because the app has no cap, it blows the
# budget wide open.
#
# No real cloud / credentials / spend needed - the meter is a local mock, so you
# test the cost-control LOGIC (a hard budget cap that HALTS the run) for free.
#
# Run on your lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-cost-anomaly"
echo "==> Creating working directory: ${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Writing meter.py (mock cloud usage meter - tracks accumulated cost)"
cat > meter.py <<'PYEOF'
#!/usr/bin/env python3
"""Mock cloud AI usage meter. Persists accumulated spend to spend.json so an
alarm can read it. charge(cost) adds to the running total and returns it."""
import json
import os

SPEND_FILE = "spend.json"
# Mock price: dollars per call (stands in for tokens * per-token price).
PRICE_PER_CALL = 0.02


def _read():
    if os.path.exists(SPEND_FILE):
        with open(SPEND_FILE) as fh:
            return json.load(fh)
    return {"total_usd": 0.0, "calls": 0}


def _write(state):
    with open(SPEND_FILE, "w") as fh:
        json.dump(state, fh)


def reset():
    _write({"total_usd": 0.0, "calls": 0})


def charge():
    """Record one model call. Returns the new running total in USD."""
    state = _read()
    state["total_usd"] = round(state["total_usd"] + PRICE_PER_CALL, 4)
    state["calls"] += 1
    _write(state)
    return state["total_usd"]


def total():
    return _read()["total_usd"]
PYEOF

echo "==> Writing alarm.py (the cost-anomaly monitor / CloudWatch-style alarm)"
cat > alarm.py <<'PYEOF'
#!/usr/bin/env python3
"""Cost-anomaly alarm. Reads accumulated spend and reports whether it breached
the monthly budget - the mock of a CloudWatch/Cloud Monitoring cost alarm."""
import sys
import meter

MONTHLY_BUDGET_USD = 5.00

if __name__ == "__main__":
    spent = meter.total()
    if spent > MONTHLY_BUDGET_USD:
        print(f"ALARM: spend ${spent:.2f} BREACHED budget ${MONTHLY_BUDGET_USD:.2f}")
        sys.exit(1)
    print(f"OK: spend ${spent:.2f} within budget ${MONTHLY_BUDGET_USD:.2f}")
    sys.exit(0)
PYEOF

echo "==> Writing batch_job.py (BROKEN: no budget cap, runaway loop)"
cat > batch_job.py <<'PYEOF'
#!/usr/bin/env python3
"""Batch job that calls the model many times.

BUG (this is the SURVIVE scenario): a bug (or a bad input set) makes it loop
1000 times with NO budget cap, blowing far past the monthly budget. Your job
(runbook.md) is to add a hard budget cap that HALTS the run before it exceeds
the limit - not just a dashboard you look at afterward.

No real spend - meter.py is a local mock.
"""
import meter

MONTHLY_BUDGET_USD = 5.00
TASKS = 1000  # a runaway batch (imagine a retry storm or a bad input file)


def run():
    meter.reset()
    for _ in range(TASKS):
        # BUG: charges on every call with no check against the budget.
        meter.charge()
    print(f"RESULT final_spend={meter.total():.2f}")


if __name__ == "__main__":
    run()
PYEOF

echo
echo "==> Running the broken batch_job.py so you can see the cost blow past budget:"
echo "-------------------------------------------------------------"
python3 batch_job.py || true
echo "==> Now the alarm evaluates the spend:"
python3 alarm.py || true
echo "-------------------------------------------------------------"
echo
echo "The batch ran 1000 calls with no cap and blew past the \$5 budget; the alarm"
echo "fired AFTER the money was already spent. Open runbook.md and add a hard cap"
echo "that HALTS the run before it exceeds the budget."
