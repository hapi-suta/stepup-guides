#!/bin/bash
# lib/check_port.sh
# Common helpers for validating network port availability.
# Source this file from validate.sh scripts.

# check_port_listening <port> <description> <pass_var> <fail_var>
check_port_listening() {
  local port="$1"
  local desc="$2"
  local -n _pass=$3
  local -n _fail=$4

  if ss -tlnp | grep -q ":${port} "; then
    echo "  [PASS] Port ${port} is listening (${desc})"
    (( _pass++ ))
  else
    echo "  [FAIL] Port ${port} is NOT listening (${desc})"
    (( _fail++ ))
  fi
}

# check_http_endpoint <url> <expected_string> <description> <pass_var> <fail_var>
# Curls the URL and checks that expected_string appears in the response.
check_http_endpoint() {
  local url="$1"
  local expected="$2"
  local desc="$3"
  local -n _pass=$4
  local -n _fail=$5

  local response
  response=$(curl -s --max-time 5 "$url" 2>/dev/null)

  if echo "$response" | grep -q "$expected"; then
    echo "  [PASS] HTTP endpoint ${url} returned expected content (${desc})"
    (( _pass++ ))
  else
    echo "  [FAIL] HTTP endpoint ${url} did not return expected content (${desc})"
    echo "         Expected: '${expected}'"
    echo "         Got:      $(echo "$response" | head -3)"
    (( _fail++ ))
  fi
}

# check_prometheus_target_up <job_name> <pass_var> <fail_var>
# Queries the Prometheus API to check if a scrape target is UP.
check_prometheus_target_up() {
  local job="$1"
  local -n _pass=$2
  local -n _fail=$3

  local health
  health=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
targets = data.get('data', {}).get('activeTargets', [])
for t in targets:
    if t.get('labels', {}).get('job') == '${job}':
        print(t.get('health', 'unknown'))
        break
else:
    print('not_found')
" 2>/dev/null)

  if [ "$health" = "up" ]; then
    echo "  [PASS] Prometheus target job='${job}' is UP"
    (( _pass++ ))
  else
    echo "  [FAIL] Prometheus target job='${job}' is '${health}' (expected 'up')"
    (( _fail++ ))
  fi
}
