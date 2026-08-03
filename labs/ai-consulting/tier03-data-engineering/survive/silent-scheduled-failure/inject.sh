#!/usr/bin/env bash
#
# SURVIVE scenario: silent-scheduled-failure
# inject.sh - an overnight scheduled job fails, but nobody is told. The job
#             swallows its own error and exits 0, so cron sees "success" while
#             the data silently goes stale.
#
# What this does (the "break"):
#   1. Builds a self-contained lab in ~/survive-silent-lab with:
#        - a heartbeat table (job_runs) in labdb that a healthy job updates
#        - a nightly_job.sh that is SUPPOSED to refresh the data
#   2. The job has the classic bug: it runs a step that fails, but the whole
#      script does `|| true` / swallows the error and exits 0, so the failure
#      is invisible. It also does NOT record a run, so the heartbeat goes stale.
#   3. Runs the broken job once so the failure has already happened "overnight".
#
# The student must: prove the failure is silent, then build failure-tracking +
# an alert (a freshness/heartbeat monitor) and PROVE the alert fires.
#
# Safe to run on CentOS Stream 9 as ec2-user. Self-contained. Idempotent.
# Requires: psql to labdb. No pip needed.

set -u

LAB="${HOME}/survive-silent-lab"
export PGPASSWORD=labpass

echo "[inject] Setting up silent-scheduled-failure scenario in ${LAB}"
rm -rf "${LAB}"
mkdir -p "${LAB}"
cd "${LAB}" || exit 1

# --- heartbeat table: a healthy job writes a row here every run ---
psql -h 127.0.0.1 -U labuser -d labdb >/dev/null 2>&1 <<'SQL'
DROP TABLE IF EXISTS job_runs;
CREATE TABLE job_runs (
    id          SERIAL PRIMARY KEY,
    job_name    TEXT NOT NULL,
    status      TEXT NOT NULL,          -- success | failed
    ran_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Pretend the job last succeeded 2 days ago (data is going stale).
INSERT INTO job_runs (job_name, status, ran_at)
VALUES ('nightly_refresh', 'success', now() - interval '2 days');
SQL

echo "[inject] Heartbeat table job_runs created; last success was 2 days ago."

# --- the BROKEN nightly job: swallows its error, exits 0, records nothing ---
cat > nightly_job.sh <<'JOB'
#!/usr/bin/env bash
# Nightly data refresh. THIS VERSION IS BROKEN ON PURPOSE.
export PGPASSWORD=labpass

# The real work step. It fails here (simulated: query a table that doesn't exist).
psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT * FROM table_that_does_not_exist;" >/dev/null 2>&1 || true
#                                                                                              ^^^^^^^
# BUG 1: '|| true' swallows the failure. BUG 2: we never record the run in job_runs.
# BUG 3: no exit-code check, so the script exits 0 and cron thinks all is well.

echo "nightly_job finished"
exit 0
JOB
chmod +x nightly_job.sh

echo "[inject] Running the broken nightly job once (the 'overnight' run)..."
./nightly_job.sh
echo "[inject] Note it printed 'finished' and exited 0 - looks fine, but did nothing."

echo
echo "[inject] DONE. The nightly job silently failed:"
echo "[inject]   - its work step errored, but '|| true' hid it and it exited 0"
echo "[inject]   - it recorded NO run, so job_runs still shows a 2-day-old success"
echo "[inject]   - cron would report SUCCESS while the data quietly goes stale"
echo "[inject] Your job: build failure-tracking + a freshness alert, and PROVE it fires."
echo "[inject] See runbook.md. Then run: bash validate.sh"
