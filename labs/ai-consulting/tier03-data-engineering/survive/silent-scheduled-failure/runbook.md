# SURVIVE Runbook: An Overnight Job Fails Silently

**Tier 3 - SURVIVE scenario 3 of 3**

## The situation

Your nightly data-refresh job has been "running fine" - cron reports success every morning. Then a client notices the dashboard has not changed in two days. You investigate: the job has been failing silently. Its work step errored, but the script swallowed the error (`|| true`), exited 0, and recorded nothing, so cron and everyone else believed it succeeded. The data quietly went stale (Concepts 3.4 timeliness and observability).

This is one of the most dangerous failures in data engineering because there is no crash, no alert, no red anywhere - just data that is wrong and getting older. Your job: prove the failure is silent, then build **failure-tracking and a freshness alert**, and prove the alert actually fires.

Every command block tells you which server and which user you are. You do all of this on your **lab server** (CentOS Stream 9) as **ec2-user**.

---

## Step 1: Reproduce the silent failure

On your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/tier03-data-engineering/survive/silent-scheduled-failure/inject.sh
```

(Adjust the path if your copy lives elsewhere.)

Expected output (yours will differ, last lines):

```
[inject] DONE. The nightly job silently failed:
[inject]   - its work step errored, but '|| true' hid it and it exited 0
[inject]   - it recorded NO run, so job_runs still shows a 2-day-old success
...
[inject] Your job: build failure-tracking + a freshness alert, and PROVE it fires.
```

---

## Step 2: Move into the lab

On your **lab server**, as **ec2-user**:

```bash
cd ~/survive-silent-lab
```

---

## Step 3: See why the failure is invisible

Run the broken job yourself and watch it lie.

Still on your **lab server**, as **ec2-user**:

```bash
./nightly_job.sh
```

Expected output:

```
nightly_job finished
```

Now check its exit code - the thing cron trusts:

```bash
echo "exit code: $?"
```

Expected output:

```
exit code: 0
```

The job errored internally but exited 0. To cron, this is a perfect success. That is the whole problem: **a job that hides its own failure is worse than one that crashes.**

---

## Step 4: Confirm the heartbeat is stale

A healthy job leaves a heartbeat - a row saying "I ran, and here is when." Check the last recorded run.

Still on your **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT job_name, status, ran_at, now() - ran_at AS age FROM job_runs ORDER BY ran_at DESC LIMIT 1;"
```

Expected output (yours will differ):

```
    job_name     | status  |            ran_at             |      age
-----------------+---------+-------------------------------+----------------
 nightly_refresh | success | 2026-07-23 09:00:00.000000+00 | 2 days 05:41:12
```

The last success is two days old and the broken job added no new row. The heartbeat is stale - the signal a freshness monitor would catch (Concepts 3.4 observability). Right now, nothing is watching it.

---

## Step 5: Fix the job to fail loudly and record every run

The first fix: the job must record its run (success or failure) and propagate a real exit code. Open it:

```bash
vi nightly_job.sh
```

Press `i`. Delete the existing contents (with the cursor at the top, type `dG`), then enter this corrected version:

```bash
#!/usr/bin/env bash
# Nightly data refresh - FIXED: fails loudly, records every run.
set -uo pipefail
export PGPASSWORD=labpass
JOB="nightly_refresh"

record() {   # record(status)
    psql -h 127.0.0.1 -U labuser -d labdb -c \
      "INSERT INTO job_runs (job_name, status) VALUES ('${JOB}', '$1');" >/dev/null 2>&1
}

# The real work step. Capture its exit code instead of swallowing it.
if psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT count(*) FROM job_runs;" >/dev/null 2>&1; then
    record success
    echo "nightly_job finished OK"
    exit 0
else
    record failed          # <-- record the FAILURE, do not hide it
    echo "nightly_job FAILED" >&2
    exit 1                  # <-- non-zero so cron/monitoring sees it
fi
```

Press `Esc`, type `:wq`, press Enter.

The three fixes: `set -uo pipefail` stops silent swallowing, every run is recorded in `job_runs` (success or failed), and the exit code is real (0 on success, 1 on failure) so a scheduler can act on it.

Run the fixed job:

```bash
./nightly_job.sh
```

Expected output:

```
nightly_job finished OK
```

Confirm it recorded a fresh run:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT status, now() - ran_at AS age FROM job_runs ORDER BY ran_at DESC LIMIT 1;"
```

Expected output (yours will differ):

```
 status  |      age
---------+-----------------
 success | 00:00:00.512331
```

The heartbeat is now fresh - the job recorded its own run.

---

## Step 6: Build the freshness alert

Fixing the job is not enough - jobs will still fail sometimes, and you must be told. Build a **freshness monitor**: a small script that checks how old the last successful run is and raises an alert if it is too stale. This is the observability layer (Concepts 3.4).

Still on your **lab server**, as **ec2-user**, open a new file:

```bash
vi check_freshness.sh
```

Press `i`, then enter:

```bash
#!/usr/bin/env bash
# Freshness monitor: alert if the nightly job has not succeeded within THRESHOLD.
# Writes an alert file (stand-in for a page/email/Slack) and exits non-zero.
set -uo pipefail
export PGPASSWORD=labpass

JOB="nightly_refresh"
THRESHOLD_MINUTES="${1:-1440}"     # default 24h; pass a smaller number to test
ALERT_FILE="${HOME}/survive-silent-lab/ALERT.txt"

# Minutes since the last SUCCESSFUL run. If there is none, treat as infinitely old.
AGE_MIN=$(psql -h 127.0.0.1 -U labuser -d labdb -tAc \
  "SELECT COALESCE(EXTRACT(EPOCH FROM (now() - max(ran_at)))/60, 999999)
   FROM job_runs WHERE job_name='${JOB}' AND status='success';")
AGE_MIN=${AGE_MIN%.*}    # drop the decimal part

echo "[freshness] last success ${AGE_MIN} min ago (threshold ${THRESHOLD_MINUTES} min)"

if [ "${AGE_MIN}" -gt "${THRESHOLD_MINUTES}" ]; then
    MSG="ALERT: ${JOB} has not succeeded in ${AGE_MIN} minutes (threshold ${THRESHOLD_MINUTES}). Data is stale."
    echo "${MSG}" | tee "${ALERT_FILE}" >&2
    exit 1     # non-zero so cron/monitoring escalates
fi

# Healthy: clear any old alert.
rm -f "${ALERT_FILE}"
echo "[freshness] OK - data is fresh"
exit 0
```

Press `Esc`, type `:wq`, press Enter. Make it executable:

```bash
chmod +x check_freshness.sh
```

---

## Step 7: Prove the alert stays quiet when data is fresh

You just ran the fixed job, so the heartbeat is fresh. The monitor should say OK.

Still on your **lab server**, as **ec2-user**:

```bash
./check_freshness.sh
```

Expected output (yours will differ):

```
[freshness] last success 0 min ago (threshold 1440 min)
[freshness] OK - data is fresh
```

Good - no false alarm when things are healthy.

---

## Step 8: Prove the alert FIRES when data is stale

An alert you have never seen fire is an alert you cannot trust. Force a stale condition and confirm the monitor catches it. Use a tiny threshold (1 minute) against the 2-day-old baseline - but first make the fresh run "old" by pointing the check at a strict threshold that even the just-now run exceeds is not possible, so instead re-inject staleness by lowering the threshold below the real age of the OLD success. The cleanest proof: age out the heartbeat and run with a strict threshold.

Set the last success back to 2 days ago to simulate the job having stopped:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "UPDATE job_runs SET ran_at = now() - interval '2 days' WHERE job_name='nightly_refresh';"
```

Expected output:

```
UPDATE 2
```

Now run the monitor with the normal 24h (1440-minute) threshold:

```bash
./check_freshness.sh 1440
```

Expected output (yours will differ):

```
[freshness] last success 2880 min ago (threshold 1440 min)
ALERT: nightly_refresh has not succeeded in 2880 minutes (threshold 1440). Data is stale.
```

Check the exit code and the alert file:

```bash
echo "exit code: $?"
```

Expected output:

```
exit code: 1
```

```bash
cat ALERT.txt
```

Expected output (yours will differ):

```
ALERT: nightly_refresh has not succeeded in 2880 minutes (threshold 1440). Data is stale.
```

The monitor fired: it detected the stale heartbeat, wrote an alert (the stand-in for a page or Slack message), and exited non-zero so a scheduler would escalate. You have proven the alert works, not just assumed it.

---

## Step 9: Restore health and confirm the alert clears

Run the fixed job again to refresh the heartbeat, then re-run the monitor - it should clear the alert.

Still on your **lab server**, as **ec2-user**:

```bash
./nightly_job.sh
```

Then:

```bash
./check_freshness.sh 1440
```

Expected output:

```
[freshness] last success 0 min ago (threshold 1440 min)
[freshness] OK - data is fresh
```

Confirm the alert file was removed:

```bash
ls ALERT.txt 2>&1
```

Expected output:

```
ls: cannot access 'ALERT.txt': No such file or directory
```

The alert self-cleared once the job succeeded. This close-the-loop behavior is what stops alert fatigue.

---

## Step 10: Validate

Still on your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/tier03-data-engineering/survive/silent-scheduled-failure/validate.sh
```

Expected output:

```
[validate] PASS: job records runs, and the freshness monitor fires on stale data and clears when fresh
```

---

## The lesson

A silent failure is the worst kind because your monitoring says green while reality goes red. Three principles you just built defend against it:

1. **Never swallow errors.** `|| true` and unchecked exit codes are how failures hide. A job must exit non-zero when its work fails (Concepts 3.4).
2. **Record every run.** A heartbeat table turns "did it run?" from a guess into a query. No heartbeat is itself a signal.
3. **Monitor freshness, and test the monitor.** A freshness check on the heartbeat catches a job that stopped running entirely - the failure no in-job check can see. And an alert you have watched fire is the only alert you can trust.

This is the observability layer from Concepts 3.4 made concrete: you now have failure tracking, a freshness monitor, and proof that it fires. In production this monitor runs on its own cron, independent of the job it watches, so even a totally dead job gets caught.
