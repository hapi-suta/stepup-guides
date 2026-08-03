# SURVIVE: Cost Anomaly on Bedrock / Vertex - Alarm Fires, Triage and Cap

A batch job hammered your cloud model in a runaway loop with no budget cap, and
spend blew far past the monthly budget. A cost alarm fired - but only AFTER the
money was already spent, because the app had no hard cap to stop it. A dashboard
that tells you about an overspend the next morning is not a control; a cap that
HALTS the run before it exceeds the budget is (Concepts 13.1, CloudWatch alarms).

In this runbook you will see the cost anomaly, diagnose the real cause (no
enforced budget cap), and fix it with a hard cap that stops the run before the
budget is breached.

**No real cloud, no credentials, and no real spend are involved.** The usage
meter is a LOCAL mock that accumulates a pretend per-call cost, so you test the
cost-control LOGIC for free. In a real system the meter is the provider's billing
and the alarm is a CloudWatch / Cloud Monitoring cost alarm - but the fix, a hard
cap that halts, is the same.

This runbook uses the SUTA 3-layer structure:

1. Detect - confirm something is wrong.
2. Diagnose - find the real cause.
3. Fix and verify - repair it and prove the repair.

---

## Layer 1: Detect

First run the injector so you can see the cost blow past budget.

On your lab server, as ec2-user:

```
bash inject.sh
```

`bash` runs the script. It writes a mock usage meter, a cost alarm (budget $5),
and a batch job that runs 1000 calls with no cap; runs the batch; then runs the
alarm.

Expected output (yours will differ):

```
==> Running the broken batch_job.py so you can see the cost blow past budget:
-------------------------------------------------------------
RESULT final_spend=20.00
==> Now the alarm evaluates the spend:
ALARM: spend $20.00 BREACHED budget $5.00
-------------------------------------------------------------
```

`final_spend=20.00` against a `$5.00` budget, and the alarm reads `BREACHED`.
That is the cost anomaly - and the alarm only noticed after the $20 was gone.

---

## Layer 2: Diagnose

Move into the working directory.

On your lab server, as ec2-user:

```
cd ~/survive-cost-anomaly
```

Look at the batch job.

Still on your lab server, as ec2-user:

```
grep -n "BUDGET\|charge\|for " batch_job.py
```

`grep -n` prints matching lines with line numbers.

Expected output (yours will differ):

```
6:MONTHLY_BUDGET_USD = 5.00
7:TASKS = 1000  # a runaway batch (imagine a retry storm or a bad input file)
13:    for _ in range(TASKS):
15:        meter.charge()
```

The loop calls `meter.charge()` on every iteration and never checks the running
total against `MONTHLY_BUDGET_USD`. The budget is defined but never enforced. The
real cause is not that the batch was large - runaway loops and bad input files
happen. The cause is that there is no hard cap that stops the run before it
overspends. A dashboard alarm that fires after the fact does not prevent the
loss; only a cap that halts does.

---

## Layer 3: Fix and verify

Add a hard budget cap that halts the run before the next call would exceed the
budget.

Still on your lab server, as ec2-user, open the batch job:

```
vi batch_job.py
```

Press `i` to enter insert mode. Replace the `run` function so it checks the
budget BEFORE each call and stops when the next call would breach it:

```python
def run():
    meter.reset()
    stopped_early = False
    for _ in range(TASKS):
        # FIX: check the budget BEFORE each call. If the NEXT call would exceed
        # the budget, HALT the run - a hard cap, not just a dashboard.
        if meter.total() + meter.PRICE_PER_CALL > MONTHLY_BUDGET_USD:
            stopped_early = True
            print(f"[halt] budget cap ${MONTHLY_BUDGET_USD:.2f} reached; "
                  f"stopping the batch to prevent overspend")
            break
        meter.charge()
    print(f"RESULT final_spend={meter.total():.2f} halted={stopped_early}")
```

Press `Esc`, type `:wq`, press Enter. Run the batch again.

Still on your lab server, as ec2-user:

```
python3 batch_job.py
```

Expected output (yours will differ):

```
[halt] budget cap $5.00 reached; stopping the batch to prevent overspend
RESULT final_spend=5.00 halted=True
```

Now check the alarm.

Still on your lab server, as ec2-user:

```
python3 alarm.py
```

Expected output (yours will differ):

```
OK: spend $5.00 within budget $5.00
```

Signs of a cost-controlled deployment:

- The batch stopped itself at the budget instead of running to $20.
- It logged that it halted, so the runaway is visible, not silent.
- The cost alarm reads `OK` - spend stayed within budget.

In a real AWS or GCP deployment this maps to layered controls (Concepts 13.1):
a CloudWatch / Cloud Monitoring alarm to detect the anomaly, plus a hard cap in
the application (or a budget action / spend limit) that actually stops work -
backed by token counting, caching, batching, and right-sizing the model. The
alarm tells you; the cap saves you.

---

## Verify

Run the scenario validator to confirm the fix.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validator. It runs your batch job and checks that it halted early
AND that the alarm reports spend within budget.

Expected output (yours will differ):

```
Running the batch job ...
[halt] budget cap $5.00 reached; stopping the batch to prevent overspend
RESULT final_spend=5.00 halted=True
Evaluating the cost alarm ...
OK: spend $5.00 within budget $5.00
PASS: the hard budget cap halted the run and spend stayed within budget.
```

If you see `PASS`, you are done.

---

Prof. Happy (SUTA Labs)
