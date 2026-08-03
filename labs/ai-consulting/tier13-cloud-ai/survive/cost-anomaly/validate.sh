#!/usr/bin/env bash
#
# SURVIVE validator: cost-anomaly
# PASS only if, after running the batch, (1) the alarm reports spend WITHIN
# budget and (2) the batch printed that it HALTED early. Proves a hard budget
# cap stopped the runaway BEFORE the money was spent. Local mock meter only -
# no real cloud, no credentials, no spend.
# Run on the lab server as ec2-user.
#
set -euo pipefail

WORKDIR="${HOME}/survive-cost-anomaly"
fail() { echo "FAIL: $1"; exit 1; }

[[ -f "${WORKDIR}/batch_job.py" ]] || fail "batch_job.py not found. Run inject.sh first."
[[ -f "${WORKDIR}/alarm.py" ]]     || fail "alarm.py not found. Run inject.sh first."
[[ -f "${WORKDIR}/meter.py" ]]     || fail "meter.py not found. Run inject.sh first."

cd "${WORKDIR}"
echo "Running the batch job ..."
if ! OUTPUT="$(python3 batch_job.py 2>&1)"; then
  echo "${OUTPUT}"
  fail "batch_job.py crashed."
fi
echo "${OUTPUT}"

RESULT_LINE="$(printf '%s\n' "${OUTPUT}" | grep -E '^RESULT ' | tail -n 1 || true)"
[[ -n "${RESULT_LINE}" ]] || fail "no RESULT line printed."

if ! printf '%s\n' "${RESULT_LINE}" | grep -q 'halted=True'; then
  fail "batch did not halt early. Add a hard budget cap that stops the run."
fi

echo "Evaluating the cost alarm ..."
if ALARM_OUT="$(python3 alarm.py 2>&1)"; then
  echo "${ALARM_OUT}"
  echo "PASS: the hard budget cap halted the run and spend stayed within budget."
  exit 0
else
  echo "${ALARM_OUT}"
  fail "the alarm still shows a budget breach - the cap did not stop the overspend."
fi
