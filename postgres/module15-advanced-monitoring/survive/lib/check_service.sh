#!/bin/bash
# lib/check_service.sh
# Common helpers for validating systemd service state.
# Source this file from validate.sh scripts.

# check_service_running <service_name> <pass_var> <fail_var>
# Increments PASS if active+running, FAIL otherwise.
check_service_running() {
  local svc="$1"
  local -n _pass=$2
  local -n _fail=$3

  if systemctl is-active --quiet "$svc"; then
    echo "  [PASS] Service '${svc}' is active"
    (( _pass++ ))
  else
    echo "  [FAIL] Service '${svc}' is NOT active"
    systemctl status "$svc" --no-pager -l | tail -10
    (( _fail++ ))
  fi
}

# check_service_enabled <service_name> <pass_var> <fail_var>
check_service_enabled() {
  local svc="$1"
  local -n _pass=$2
  local -n _fail=$3

  if systemctl is-enabled --quiet "$svc"; then
    echo "  [PASS] Service '${svc}' is enabled"
    (( _pass++ ))
  else
    echo "  [FAIL] Service '${svc}' is NOT enabled"
    (( _fail++ ))
  fi
}
