# Survive 01: API Integration Failure

## The Scenario

The PagerDuty API is down. Your DBA agent receives a P1 alert - connection pool
exhausted on production. The agent diagnoses the problem correctly, but when it tries
to create a PagerDuty incident, it gets a 503 error. The notification code has no
error handling - it crashes, and the entire alert pipeline stops. Three more P1 alerts
arrive over the next 45 minutes. None are processed. No one gets paged. The on-call
DBA finds out about the outage from a customer complaint at 4 AM.

---

## The Disaster

On your **Mac terminal**, run the failure scenario:

```bash
python3 << 'PYEOF'

# This script simulates the exact failure: PagerDuty API returns 503,
# the agent crashes, and alerts pile up unprocessed.

import urllib.request
import json
import datetime

print("=" * 60)
print("SCENARIO: PagerDuty API Down - Alert Pipeline Crash")
print("=" * 60)

print("""
Timeline:
  02:15  Alert: active_connections=199/200 on production (P1)
  02:15  Agent diagnoses correctly: connection pool exhaustion
  02:15  Agent tries to create PagerDuty incident
  02:15  PagerDuty returns HTTP 503 (Service Unavailable)
  02:15  Agent crashes - no error handling around the API call
  02:16  Alert: replication_lag=600s on standby-1 (P1)
  02:18  Alert: disk_usage=96% on production (P1)
  02:30  Alert: OOM killer fired on production (P1)
  02:15-03:00  ALL ALERTS UNPROCESSED - no one is paged
  03:00  Customer calls: "The app is down"
  03:05  Manager wakes up on-call DBA manually

Root cause: NO FALLBACK when PagerDuty API fails.
The agent treated the API call as mandatory and crashed when it failed.
""")

# -----------------------------------------------------------------------
# DEMONSTRATE THE CRASH
# -----------------------------------------------------------------------

alerts_queue = [
    {"id": "ALERT-001", "metric": "active_connections", "value": 199, "severity": "CRITICAL"},
    {"id": "ALERT-002", "metric": "replication_lag_seconds", "value": 600, "severity": "CRITICAL"},
    {"id": "ALERT-003", "metric": "disk_usage_percent", "value": 96, "severity": "CRITICAL"},
    {"id": "ALERT-004", "metric": "oom_killer", "value": 1, "severity": "CRITICAL"},
]

processed = []
unprocessed = []

def create_pagerduty_incident_broken(alert: dict):
    """
    The BROKEN version - no error handling.
    Uses a URL that returns 503 to simulate PagerDuty being down.
    """
    # httpbin.org/status/503 always returns HTTP 503
    payload = json.dumps({"summary": f"{alert['metric']}={alert['value']}"}).encode("utf-8")
    req = urllib.request.Request(
        url="https://httpbin.org/status/503",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    # This will raise urllib.error.HTTPError because the response is 503
    # No try/except - the exception propagates up and kills the pipeline
    response = urllib.request.urlopen(req, timeout=10)
    return response.status


print("Processing alert queue with BROKEN pipeline...")
print()

for alert in alerts_queue:
    try:
        print(f"  Processing {alert['id']}: {alert['metric']}={alert['value']}")
        print(f"  Diagnosing... severity={alert['severity']}")
        print(f"  Sending to PagerDuty...")

        # This crashes on the FIRST alert
        create_pagerduty_incident_broken(alert)
        processed.append(alert["id"])
        print(f"  PagerDuty incident created")

    except Exception as e:
        # In the real incident, there was no try/except at this level either.
        # The entire pipeline process crashed and all remaining alerts were lost.
        print(f"  CRASH: {type(e).__name__}: {str(e)[:60]}")
        print(f"  Pipeline stopped. Remaining alerts will NOT be processed.")
        unprocessed = [a["id"] for a in alerts_queue if a["id"] not in processed and a["id"] != alert["id"]]
        unprocessed.insert(0, alert["id"])
        break

print(f"\nProcessed:   {processed if processed else 'NONE'}")
print(f"Unprocessed: {unprocessed}")
print(f"\n{len(unprocessed)} P1 alerts went completely unnotified.")
print("No DBA was paged. The outage lasted 45 minutes longer than necessary.")

PYEOF
```

### Expected output (yours will differ):

```
============================================================
SCENARIO: PagerDuty API Down - Alert Pipeline Crash
============================================================

[scenario text printed here]

Processing alert queue with BROKEN pipeline...

  Processing ALERT-001: active_connections=199
  Diagnosing... severity=CRITICAL
  Sending to PagerDuty...
  CRASH: HTTPError: HTTP Error 503: SERVICE UNAVAILABLE
  Pipeline stopped. Remaining alerts will NOT be processed.

Processed:   NONE
Unprocessed: ['ALERT-001', 'ALERT-002', 'ALERT-003', 'ALERT-004']

4 P1 alerts went completely unnotified.
No DBA was paged. The outage lasted 45 minutes longer than necessary.
```

---

## Investigate

On your **Mac terminal**, identify the three failures that caused this outage:

```bash
python3 << 'PYEOF'

print("Investigation: Why Did 4 P1 Alerts Go Unnotified?")
print("=" * 55)

print("""
FAILURE 1: No error handling around the PagerDuty API call
-------------------------------------------------------
The code called urllib.request.urlopen() with no try/except.
When the API returned 503, Python raised an HTTPError.
That exception was not caught, so it killed the pipeline.

DBA analogy: like running a backup script with no error checking.
  pg_dump production | gzip > /backup/prod.gz
If pg_dump fails (e.g., out of disk), gzip still runs on empty input,
and you get a 0-byte backup file. No alert, no retry.

FAILURE 2: No fallback notification channel
-------------------------------------------------------
PagerDuty was the ONLY notification path.
When it went down, there was no alternative:
  - No Slack fallback
  - No email fallback
  - No SMS fallback
  - No local log that could be monitored

DBA analogy: like having a single standby with no monitoring on it.
If replication breaks, you have no replica AND no alert about it.

FAILURE 3: One alert failure killed ALL subsequent alerts
-------------------------------------------------------
The pipeline processed alerts sequentially with no isolation.
When ALERT-001 crashed, ALERT-002, 003, and 004 were never touched.

DBA analogy: like running all your backup jobs in a single shell script
with set -e (exit on error). If the first backup fails, all remaining
backups are skipped. Each job should be independent.
""")

PYEOF
```

### Expected output (yours will differ):

```
Investigation: Why Did 4 P1 Alerts Go Unnotified?
=======================================================

FAILURE 1: No error handling around the PagerDuty API call
...
FAILURE 2: No fallback notification channel
...
FAILURE 3: One alert failure killed ALL subsequent alerts
...
```

---

## The Fix

Three changes prevent this from ever happening again.

### Fix 1: Wrap every API call with retry and fallback

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 1: Every external API call gets retry logic and a fallback.
# If PagerDuty fails after retries, fall back to Slack. If Slack also
# fails, write to a local alert file that can be monitored.
# DBA analogy: like pg_basebackup with --checkpoint=fast --retry.
# If the backup fails, retry. If retries exhaust, write to a local log.

import urllib.request
import json
import time

print("Fix 1: Retry + Fallback Notification Chain")
print("=" * 50)


def send_with_retry(url: str, payload: dict, max_retries: int = 3,
                    backoff_seconds: float = 1.0) -> dict:
    """
    Send an HTTP POST with exponential backoff retry.

    Parameters:
        url             - endpoint URL
        payload         - JSON payload to send
        max_retries     - how many times to retry on failure
        backoff_seconds - initial wait between retries (doubles each time)

    Returns:
        dict with success status and attempt count

    DBA analogy: like retry logic in a backup script:
      for attempt in 1 2 3; do
        pg_dump ... && break
        sleep $((attempt * 2))
      done
    """
    data = json.dumps(payload).encode("utf-8")

    for attempt in range(1, max_retries + 1):
        try:
            req = urllib.request.Request(
                url=url, data=data,
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            response = urllib.request.urlopen(req, timeout=10)
            return {"success": True, "attempts": attempt, "status": response.status}

        except Exception as e:
            wait = backoff_seconds * (2 ** (attempt - 1))
            print(f"    Attempt {attempt}/{max_retries} failed: {str(e)[:40]}")
            if attempt < max_retries:
                print(f"    Retrying in {wait}s...")
                time.sleep(min(wait, 2))  # cap at 2s for the lab

    return {"success": False, "attempts": max_retries, "error": "All retries exhausted"}


def notify_with_fallback(severity: str, summary: str) -> dict:
    """
    Try PagerDuty first, then Slack, then local file.
    At least one notification channel must succeed.
    """
    payload = {"severity": severity, "summary": summary}

    # Channel 1: PagerDuty (simulated down with 503)
    print(f"\n  Trying PagerDuty...")
    pd_result = send_with_retry("https://httpbin.org/status/503", payload, max_retries=2, backoff_seconds=0.5)
    if pd_result["success"]:
        return {"channel": "pagerduty", "success": True}

    # Channel 2: Slack (simulated up with 200)
    print(f"  PagerDuty failed. Falling back to Slack...")
    slack_result = send_with_retry("https://httpbin.org/post", payload, max_retries=2, backoff_seconds=0.5)
    if slack_result["success"]:
        return {"channel": "slack_fallback", "success": True}

    # Channel 3: Local file (always works)
    print(f"  Slack also failed. Writing to local alert file...")
    with open("/tmp/emergency_alerts.log", "a") as f:
        f.write(f"[{severity}] {summary}\n")
    return {"channel": "local_file", "success": True}


# Test with PagerDuty "down"
result = notify_with_fallback("CRITICAL", "Connection pool exhausted: 199/200")
print(f"\n  Final result: notified via {result['channel']}")
print(f"  At least one channel succeeded: {result['success']}")

PYEOF
```

### Expected output (yours will differ):

```
Fix 1: Retry + Fallback Notification Chain
==================================================

  Trying PagerDuty...
    Attempt 1/2 failed: HTTP Error 503: SERVICE UNAVAIL...
    Retrying in 0.5s...
    Attempt 2/2 failed: HTTP Error 503: SERVICE UNAVAIL...
  PagerDuty failed. Falling back to Slack...

  Final result: notified via slack_fallback
  At least one channel succeeded: True
```

### Fix 2: Isolate alert processing so one failure cannot block others

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 2: Each alert is processed independently.
# If one alert fails, the remaining alerts still get processed.
# DBA analogy: like running each backup in its own subshell:
#   for db in production staging analytics; do
#     (pg_dump $db > /backup/$db.gz) &
#   done
# If one backup fails, the others still complete.

import json

print("Fix 2: Isolated Alert Processing")
print("=" * 50)


def process_alert_safely(alert: dict) -> dict:
    """
    Process one alert with full error isolation.
    If anything fails, log the error and continue.
    Never let one alert block others.
    """
    try:
        # Diagnose
        diagnosis = f"Diagnosed: {alert['metric']}={alert['value']}"

        # Notify (simulated failure for even-numbered alerts)
        if alert["value"] % 2 == 0:
            raise ConnectionError("PagerDuty API timeout")

        return {"id": alert["id"], "status": "processed", "diagnosis": diagnosis}

    except Exception as e:
        # Log the error but DO NOT re-raise
        # The alert is marked as failed, not crashed
        return {"id": alert["id"], "status": "failed", "error": str(e)}


# Process all alerts - failures are isolated
alerts = [
    {"id": "ALERT-001", "metric": "connections", "value": 199, "severity": "CRITICAL"},
    {"id": "ALERT-002", "metric": "lag_seconds", "value": 600, "severity": "CRITICAL"},
    {"id": "ALERT-003", "metric": "disk_percent", "value": 96, "severity": "CRITICAL"},
    {"id": "ALERT-004", "metric": "oom_kills", "value": 1, "severity": "CRITICAL"},
]

results = []
for alert in alerts:
    result = process_alert_safely(alert)
    results.append(result)
    status_icon = "OK" if result["status"] == "processed" else "FAIL"
    print(f"  [{status_icon}] {result['id']}: {result.get('diagnosis', result.get('error', ''))[:50]}")

processed = sum(1 for r in results if r["status"] == "processed")
failed = sum(1 for r in results if r["status"] == "failed")

print(f"\nProcessed: {processed}/{len(alerts)}")
print(f"Failed:    {failed}/{len(alerts)} (these need manual review)")
print(f"\nKey: even failed alerts did NOT block the others.")
print("All 4 alerts were attempted. None were silently dropped.")

PYEOF
```

### Expected output (yours will differ):

```
Fix 2: Isolated Alert Processing
==================================================
  [OK] ALERT-001: Diagnosed: connections=199
  [FAIL] ALERT-002: PagerDuty API timeout
  [OK] ALERT-003: Diagnosed: disk_percent=96
  [FAIL] ALERT-004: PagerDuty API timeout

Processed: 2/4
Failed:    2/4 (these need manual review)

Key: even failed alerts did NOT block the others.
All 4 alerts were attempted. None were silently dropped.
```

### Fix 3: Add a circuit breaker for external services

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# Fix 3: Circuit breaker pattern.
# After N consecutive failures, stop trying the failing service
# and go straight to the fallback. This avoids wasting time on
# retries when the service is clearly down.
#
# DBA analogy: like PgBouncer's server_check_delay.
# If a backend fails health checks 3 times, PgBouncer stops
# sending connections to it. After a cooldown, it tries one
# test connection. If that works, it re-enables the backend.

import time
import datetime

print("Fix 3: Circuit Breaker for External Services")
print("=" * 50)


class CircuitBreaker:
    """
    Tracks failures for an external service.
    After failure_threshold consecutive failures, the circuit "opens"
    and all calls go straight to fallback for cooldown_seconds.

    States:
      CLOSED  - service is healthy, send requests normally
      OPEN    - service is down, skip it and use fallback
      HALF    - cooldown expired, try one test request
    """

    def __init__(self, service_name: str, failure_threshold: int = 3,
                 cooldown_seconds: float = 30.0):
        self.service_name = service_name
        self.failure_threshold = failure_threshold
        self.cooldown_seconds = cooldown_seconds
        self.consecutive_failures = 0
        self.state = "CLOSED"
        self.opened_at = None

    def can_call(self) -> bool:
        """Check if we should attempt to call this service."""
        if self.state == "CLOSED":
            return True

        if self.state == "OPEN":
            # Check if cooldown has expired
            elapsed = time.time() - self.opened_at
            if elapsed >= self.cooldown_seconds:
                self.state = "HALF"
                print(f"    [Circuit {self.service_name}] Cooldown expired. "
                      f"Trying one test call (HALF-OPEN)...")
                return True
            else:
                remaining = round(self.cooldown_seconds - elapsed, 1)
                print(f"    [Circuit {self.service_name}] OPEN - "
                      f"skipping ({remaining}s until retry)")
                return False

        if self.state == "HALF":
            return True

        return False

    def record_success(self):
        """Service call succeeded - reset the breaker."""
        if self.state == "HALF":
            print(f"    [Circuit {self.service_name}] Test call succeeded. "
                  f"Circuit CLOSED - service recovered.")
        self.consecutive_failures = 0
        self.state = "CLOSED"

    def record_failure(self):
        """Service call failed - increment counter, maybe open circuit."""
        self.consecutive_failures += 1

        if self.state == "HALF":
            # Test call failed - re-open the circuit
            self.state = "OPEN"
            self.opened_at = time.time()
            print(f"    [Circuit {self.service_name}] Test call failed. "
                  f"Circuit re-OPENED for {self.cooldown_seconds}s.")
            return

        if self.consecutive_failures >= self.failure_threshold:
            self.state = "OPEN"
            self.opened_at = time.time()
            print(f"    [Circuit {self.service_name}] {self.consecutive_failures} "
                  f"consecutive failures. Circuit OPENED for {self.cooldown_seconds}s.")


# ---------------------------------------------------------
# DEMO
# ---------------------------------------------------------

pagerduty_breaker = CircuitBreaker("PagerDuty", failure_threshold=3, cooldown_seconds=2)

print()
for i in range(1, 9):
    print(f"\nAlert #{i}:")

    if pagerduty_breaker.can_call():
        # Simulate PagerDuty being down for alerts 1-5, recovering at 6+
        if i <= 5:
            print(f"    Calling PagerDuty... FAILED (503)")
            pagerduty_breaker.record_failure()
        else:
            print(f"    Calling PagerDuty... SUCCESS (200)")
            pagerduty_breaker.record_success()
    else:
        print(f"    Skipping PagerDuty (circuit open). Using Slack fallback.")

    # Small delay to let cooldown progress
    if i >= 4:
        time.sleep(0.8)

print(f"\nFinal circuit state: {pagerduty_breaker.state}")
print(f"Consecutive failures: {pagerduty_breaker.consecutive_failures}")

PYEOF
```

### Expected output (yours will differ):

```
Fix 3: Circuit Breaker for External Services
==================================================

Alert #1:
    Calling PagerDuty... FAILED (503)

Alert #2:
    Calling PagerDuty... FAILED (503)

Alert #3:
    Calling PagerDuty... FAILED (503)
    [Circuit PagerDuty] 3 consecutive failures. Circuit OPENED for 2s.

Alert #4:
    [Circuit PagerDuty] OPEN - skipping (1.2s until retry)
    Skipping PagerDuty (circuit open). Using Slack fallback.

Alert #5:
    [Circuit PagerDuty] OPEN - skipping (0.4s until retry)
    Skipping PagerDuty (circuit open). Using Slack fallback.

Alert #6:
    [Circuit PagerDuty] Cooldown expired. Trying one test call (HALF-OPEN)...
    Calling PagerDuty... SUCCESS (200)
    [Circuit PagerDuty] Test call succeeded. Circuit CLOSED - service recovered.

Alert #7:
    Calling PagerDuty... SUCCESS (200)

Alert #8:
    Calling PagerDuty... SUCCESS (200)

Final circuit state: CLOSED
Consecutive failures: 0
```

---

## What You Learned

| Problem | Why It Caused the Incident | Fix |
|---------|---------------------------|-----|
| No error handling on API calls | One 503 response crashed the entire pipeline | Wrap every API call in try/except with retry logic |
| Single notification channel | PagerDuty down = zero notification | Fallback chain: PagerDuty -> Slack -> email -> local file |
| No alert isolation | One failed alert blocked all subsequent alerts | Process each alert independently; log failures, continue |
| No circuit breaker | Kept retrying a dead service, wasting time | After N failures, skip the service for a cooldown period |
| No local alert log | When all APIs fail, alerts vanish | Always write to a local file as last resort |
