#!/usr/bin/env bash
#
# SURVIVE scenario: silent-scheduled-failure
# validate.sh - exits 0 when the job records runs AND a freshness monitor exists
#               that fires on stale data and clears when fresh; 1 otherwise.
#
# Passing criteria (all must hold):
#   1. check_freshness.sh exists and is executable.
#   2. The FIXED nightly_job.sh records a run in job_runs (heartbeat works):
#      running it adds a new success row.
#   3. When data is stale, check_freshness.sh exits NON-ZERO and writes ALERT.txt
#      (the alert fires).
#   4. When data is fresh, check_freshness.sh exits ZERO and removes ALERT.txt
#      (the alert clears).
#
# Run on your lab server as ec2-user. Self-contained. Uses labdb. Leaves data healthy.

LAB="${HOME}/survive-silent-lab"
export PGPASSWORD=labpass
q() { psql -h 127.0.0.1 -U labuser -d labdb -tAc "$1" 2>/dev/null | tr -d '[:space:]'; }
fail() { echo "[validate] FAIL: $1"; exit 1; }

# 0. lab + scripts present
[ -d "$LAB" ] || fail "lab dir ${LAB} missing - run inject.sh."
[ -x "${LAB}/check_freshness.sh" ] || fail "check_freshness.sh missing or not executable (runbook step 6)."
[ -f "${LAB}/nightly_job.sh" ] || fail "nightly_job.sh missing (runbook step 5)."

# 1. heartbeat: running the fixed job must add a success row.
BEFORE="$(q "SELECT count(*) FROM job_runs WHERE job_name='nightly_refresh'")"
( cd "$LAB" && ./nightly_job.sh >/dev/null 2>&1 )
AFTER="$(q "SELECT count(*) FROM job_runs WHERE job_name='nightly_refresh'")"
if [ -z "$BEFORE" ] || [ -z "$AFTER" ] || [ "$AFTER" -le "$BEFORE" ]; then
    fail "nightly_job.sh did not record a run in job_runs - it must log every run (runbook step 5)."
fi
LAST_STATUS="$(q "SELECT status FROM job_runs WHERE job_name='nightly_refresh' ORDER BY ran_at DESC LIMIT 1")"
[ "$LAST_STATUS" = "success" ] || fail "last recorded run is '${LAST_STATUS}', expected 'success' after a healthy run (runbook step 5)."

# 2. ALERT FIRES on stale: age the heartbeat, run monitor with a strict threshold.
psql -h 127.0.0.1 -U labuser -d labdb -c \
  "UPDATE job_runs SET ran_at = now() - interval '2 days' WHERE job_name='nightly_refresh';" >/dev/null 2>&1
rm -f "${LAB}/ALERT.txt"
( cd "$LAB" && ./check_freshness.sh 1440 >/dev/null 2>&1 )
STALE_CODE=$?
[ "$STALE_CODE" -ne 0 ] || fail "monitor exited 0 on stale data - it must alert and exit non-zero (runbook step 8)."
[ -f "${LAB}/ALERT.txt" ] || fail "monitor did not write ALERT.txt on stale data (runbook step 8)."

# 3. ALERT CLEARS on fresh: refresh heartbeat, monitor should pass and remove ALERT.txt.
( cd "$LAB" && ./nightly_job.sh >/dev/null 2>&1 )
( cd "$LAB" && ./check_freshness.sh 1440 >/dev/null 2>&1 )
FRESH_CODE=$?
[ "$FRESH_CODE" -eq 0 ] || fail "monitor exited non-zero on fresh data - it should pass after a successful run (runbook step 9)."
[ ! -f "${LAB}/ALERT.txt" ] || fail "ALERT.txt not cleared after data became fresh (runbook step 9)."

echo "[validate] PASS: job records runs, and the freshness monitor fires on stale data and clears when fresh"
exit 0
