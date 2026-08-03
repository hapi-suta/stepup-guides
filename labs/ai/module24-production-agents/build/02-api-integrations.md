# Build 02: API Integrations

## Why Agents Need API Access

A DBA agent that can diagnose problems but cannot notify anyone is like a monitoring system with no alerting - it sees the fire but never pulls the alarm.

**DBA analogy:** Your existing monitoring scripts already call APIs. Nagios sends emails. PagerDuty fires pages. Slack webhooks post to #dba-alerts. Your agent needs to do the same things, but it decides *what* to send based on its diagnosis, not just a static threshold.

```
Traditional monitoring:
  metric > threshold --> static alert --> PagerDuty

Agent-based monitoring:
  metric anomaly --> agent diagnoses root cause --> crafts specific message
                 --> posts diagnosis to Slack
                 --> creates PagerDuty incident if P1/P2
                 --> creates Jira ticket with runbook link
```

---

## Step 1: HTTP Requests in Python

### The Concept

All API integrations use HTTP requests. Python's built-in `urllib` handles this, but we will use a simple wrapper to keep things clean.

**DBA analogy:** HTTP requests are like database connections. You open a connection, send a command (the request), and get back a result (the response). The HTTP method (GET, POST, PUT) is like the SQL command type (SELECT, INSERT, UPDATE).

| HTTP Method | What It Does | SQL Equivalent |
|-------------|-------------|----------------|
| GET | Retrieve data | SELECT |
| POST | Create something new | INSERT |
| PUT | Update something existing | UPDATE |
| DELETE | Remove something | DELETE |

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Makes HTTP requests to httpbin.org - a public test API.
#   httpbin.org echoes back whatever you send it, so you can
#   verify your request was formatted correctly.
#   Think of it like a PostgreSQL ECHO command that shows
#   you exactly what the server received.
# ---------------------------------------------------------

# urllib is Python's built-in HTTP library - no pip install needed
# urllib.request handles sending requests
# urllib.parse handles encoding data
import urllib.request
import urllib.parse

# json converts Python dicts to JSON strings and back
import json

print("=" * 60)
print("HTTP REQUEST BASICS")
print("=" * 60)

# ---------------------------------------------------------
# GET REQUEST - like SELECT
# ---------------------------------------------------------
# A GET request retrieves data from a URL.
# httpbin.org/get echoes back the request headers and parameters.

print("\n--- GET request (like SELECT) ---")

# urllib.request.urlopen sends the request and returns the response
# .read() gets the response body as bytes
# .decode() converts bytes to a string - like converting bytea to text in PostgreSQL
response = urllib.request.urlopen("https://httpbin.org/get")
body = response.read().decode()
data = json.loads(body)  # parse JSON string into a Python dict

# Print just the origin IP and URL to keep output clean
print(f"  Status: {response.status}")
print(f"  Origin: {data['origin']}")
print(f"  URL:    {data['url']}")

# ---------------------------------------------------------
# POST REQUEST - like INSERT
# ---------------------------------------------------------
# A POST request sends data to create something new.
# httpbin.org/post echoes back the data you sent.

print("\n--- POST request (like INSERT) ---")

# The data we want to send - this would be your alert payload
payload = {
    "alert_name": "high_connections",
    "severity": "CRITICAL",
    "database": "production",
    "value": "199/200 connections",
    "timestamp": "2026-06-15T14:30:00Z"
}

# Convert the dict to a JSON string, then encode to bytes
# This is like converting a Python dict to a SQL INSERT statement
payload_bytes = json.dumps(payload).encode("utf-8")

# Create a Request object with the URL, data, and headers
# Content-Type tells the server we are sending JSON
req = urllib.request.Request(
    url="https://httpbin.org/post",
    data=payload_bytes,
    headers={"Content-Type": "application/json"},
    method="POST"
)

response = urllib.request.urlopen(req)
body = response.read().decode()
data = json.loads(body)

print(f"  Status: {response.status}")
# httpbin echoes back what we sent in the "json" field
print(f"  Server received: {json.dumps(data['json'], indent=4)}")

EOF
```

Expected output (yours will differ):
```
============================================================
HTTP REQUEST BASICS
============================================================

--- GET request (like SELECT) ---
  Status: 200
  Origin: 203.0.113.42
  URL:    https://httpbin.org/get

--- POST request (like INSERT) ---
  Status: 200
  Server received: {
      "alert_name": "high_connections",
      "severity": "CRITICAL",
      "database": "production",
      "value": "199/200 connections",
      "timestamp": "2026-06-15T14:30:00Z"
  }
```

---

## Step 2: Slack Integration

### The Concept

Slack webhooks let you POST a JSON message to a URL and it appears in a channel. No authentication token needed for incoming webhooks - the URL itself is the secret.

**DBA analogy:** Slack webhooks are like `pg_notify()`. You send a payload to a channel name, and any listener on that channel receives it. The difference is Slack is external and uses HTTP instead of the PostgreSQL listen/notify protocol.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a Slack notification function for DBA alerts.
#   Uses httpbin.org as a stand-in for a real Slack webhook URL.
#   In production, replace the URL with your actual Slack webhook.
# ---------------------------------------------------------

import urllib.request
import json
import datetime

# ---------------------------------------------------------
# SLACK NOTIFIER
# ---------------------------------------------------------

def send_slack_alert(
    webhook_url: str,
    severity: str,
    database: str,
    summary: str,
    diagnosis: str,
    recommendation: str
) -> dict:
    """
    Send a formatted alert to a Slack channel via webhook.

    Parameters:
        webhook_url    - the Slack incoming webhook URL (or httpbin for testing)
        severity       - CRITICAL, WARNING, or OK
        database       - which database is affected
        summary        - one-line description of the problem
        diagnosis      - root cause analysis
        recommendation - suggested fix

    Returns:
        dict with status and response details

    DBA analogy: this is like pg_notify('dba_alerts', payload::json).
    The channel is the webhook URL, and the payload is the alert data.
    """

    # Choose an emoji based on severity - Slack renders these in the message
    severity_emoji = {
        "CRITICAL": ":rotating_light:",
        "WARNING":  ":warning:",
        "OK":       ":white_check_mark:"
    }
    emoji = severity_emoji.get(severity, ":question:")

    # Build the Slack message payload
    # Slack uses a specific JSON format called "Block Kit"
    # "blocks" is a list of message sections - like rows in a report
    slack_payload = {
        "text": f"{emoji} [{severity}] {summary}",
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"{emoji} Database Alert: {severity}"
                }
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Database:*\n{database}"},
                    {"type": "mrkdwn", "text": f"*Severity:*\n{severity}"},
                    {"type": "mrkdwn", "text": f"*Summary:*\n{summary}"},
                    {"type": "mrkdwn", "text": f"*Time:*\n{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"}
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Diagnosis:*\n{diagnosis}"
                }
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Recommended Action:*\n```{recommendation}```"
                }
            }
        ]
    }

    # Send the POST request
    payload_bytes = json.dumps(slack_payload).encode("utf-8")

    req = urllib.request.Request(
        url=webhook_url,
        data=payload_bytes,
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    try:
        response = urllib.request.urlopen(req, timeout=10)
        return {
            "success": True,
            "status_code": response.status,
            "message": "Alert sent to Slack"
        }
    except Exception as e:
        return {
            "success": False,
            "status_code": None,
            "message": f"Failed to send Slack alert: {str(e)}"
        }


# ---------------------------------------------------------
# TEST IT
# ---------------------------------------------------------
# We use httpbin.org/post as a stand-in for a real Slack webhook.
# In production, you would replace this URL with:
#   https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXX

print("=" * 60)
print("SLACK INTEGRATION TEST")
print("=" * 60)

result = send_slack_alert(
    webhook_url="https://httpbin.org/post",
    severity="CRITICAL",
    database="production",
    summary="Connection pool exhausted - 199/200 connections in use",
    diagnosis="The reporting_app is holding 142 idle connections. "
              "Connection pooling is not configured. Each web request "
              "opens a new connection and never closes it.",
    recommendation="1. Kill idle connections older than 10 min:\n"
                   "   SELECT pg_terminate_backend(pid) FROM pg_stat_activity\n"
                   "   WHERE state = 'idle' AND state_change < NOW() - INTERVAL '10 min';\n"
                   "2. Deploy PgBouncer with pool_mode = transaction"
)

print(f"\nSend result:")
print(f"  Success:     {result['success']}")
print(f"  Status code: {result['status_code']}")
print(f"  Message:     {result['message']}")

EOF
```

Expected output (yours will differ):
```
============================================================
SLACK INTEGRATION TEST
============================================================

Send result:
  Success:     True
  Status code: 200
  Message:     Alert sent to Slack
```

---

## Step 3: PagerDuty Integration

### The Concept

PagerDuty creates incidents that page on-call engineers. The Events API v2 accepts a JSON payload and routes it through the escalation policy.

**DBA analogy:** PagerDuty is like `pg_ctl promote` for humans - it wakes someone up and forces them to act. Your monitoring detects the problem; PagerDuty ensures a human sees it.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a PagerDuty incident creator for the DBA agent.
#   Uses httpbin.org as a stand-in for the PagerDuty Events API.
#   In production, replace with https://events.pagerduty.com/v2/enqueue
# ---------------------------------------------------------

import urllib.request
import json
import datetime

# ---------------------------------------------------------
# PAGERDUTY NOTIFIER
# ---------------------------------------------------------

def create_pagerduty_incident(
    api_url: str,
    routing_key: str,
    severity: str,
    summary: str,
    source: str,
    database: str,
    details: dict
) -> dict:
    """
    Create a PagerDuty incident via the Events API v2.

    Parameters:
        api_url     - PagerDuty Events API URL (or httpbin for testing)
        routing_key - the integration key from PagerDuty (like a connection string)
        severity    - critical, warning, error, or info
        summary     - one-line description (max 1024 chars)
        source      - where the alert came from (e.g., "dba-agent-prod")
        database    - which database is affected
        details     - dict of additional context (metrics, queries, etc.)

    Returns:
        dict with status and dedup_key for future reference

    DBA analogy: this is like INSERT INTO incidents (severity, summary, ...)
    The routing_key determines which on-call schedule receives the page -
    like a schema search_path determines which table gets the INSERT.
    """

    # PagerDuty Events API v2 payload format
    # This is a fixed schema - every field must be in the right place
    # Think of it like a COPY command - the columns must match exactly
    payload = {
        "routing_key": routing_key,
        "event_action": "trigger",
        "dedup_key": f"dba-agent-{database}-{datetime.datetime.now().strftime('%Y%m%d%H%M')}",
        "payload": {
            "summary": summary,
            "severity": severity.lower(),
            "source": source,
            "component": database,
            "group": "database",
            "class": "dba-agent-alert",
            "custom_details": details
        }
    }

    payload_bytes = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        url=api_url,
        data=payload_bytes,
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    try:
        response = urllib.request.urlopen(req, timeout=10)
        return {
            "success": True,
            "status_code": response.status,
            "dedup_key": payload["dedup_key"],
            "message": "PagerDuty incident created"
        }
    except Exception as e:
        return {
            "success": False,
            "status_code": None,
            "dedup_key": payload["dedup_key"],
            "message": f"Failed to create incident: {str(e)}"
        }


# ---------------------------------------------------------
# TEST IT
# ---------------------------------------------------------

print("=" * 60)
print("PAGERDUTY INTEGRATION TEST")
print("=" * 60)

result = create_pagerduty_incident(
    api_url="https://httpbin.org/post",
    routing_key="FAKE_ROUTING_KEY_replace_with_real_one",
    severity="critical",
    summary="PostgreSQL connection pool exhausted on production (199/200)",
    source="dba-agent-prod",
    database="production",
    details={
        "active_connections": 199,
        "max_connections": 200,
        "top_application": "reporting_app",
        "idle_connections": 142,
        "diagnosis": "reporting_app not using connection pooling",
        "recommended_action": "Kill idle connections, deploy PgBouncer"
    }
)

print(f"\nIncident creation result:")
print(f"  Success:     {result['success']}")
print(f"  Status code: {result['status_code']}")
print(f"  Dedup key:   {result['dedup_key']}")
print(f"  Message:     {result['message']}")

EOF
```

Expected output (yours will differ):
```
============================================================
PAGERDUTY INTEGRATION TEST
============================================================

Incident creation result:
  Success:     True
  Status code: 200
  Dedup key:   dba-agent-production-202606151430
  Message:     PagerDuty incident created
```

---

## Step 4: Jira Ticket Creation

### The Concept

When the agent diagnoses a problem, it creates a Jira ticket with structured data so the DBA team has a clear record of what happened, what was diagnosed, and what the recommended fix is.

**DBA analogy:** Creating a Jira ticket is like an `INSERT INTO incident_log`. The ticket captures the who, what, when, where, and recommended action - the same fields you would put in a postmortem table.

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a Jira ticket creator for the DBA agent.
#   Uses httpbin.org as a stand-in for the Jira REST API.
#   In production, replace with https://your-domain.atlassian.net/rest/api/3/issue
# ---------------------------------------------------------

import urllib.request
import json
import datetime

# ---------------------------------------------------------
# JIRA TICKET CREATOR
# ---------------------------------------------------------

def create_jira_ticket(
    api_url: str,
    project_key: str,
    severity: str,
    summary: str,
    database: str,
    diagnosis: str,
    recommendation: str,
    runbook_url: str
) -> dict:
    """
    Create a Jira issue for a database incident.

    Parameters:
        api_url        - Jira REST API URL (or httpbin for testing)
        project_key    - Jira project key (e.g., "DBA")
        severity       - CRITICAL, WARNING, or OK
        summary        - one-line title for the ticket
        database       - which database is affected
        diagnosis      - root cause analysis from the agent
        recommendation - suggested fix
        runbook_url    - link to the relevant runbook

    Returns:
        dict with ticket key and status

    DBA analogy: INSERT INTO incident_log (project, severity, summary, ...)
    """

    # Map severity to Jira priority
    # Jira uses priority IDs - 1 is highest
    priority_map = {
        "CRITICAL": {"id": "1", "name": "Highest"},
        "WARNING":  {"id": "2", "name": "High"},
        "OK":       {"id": "4", "name": "Low"}
    }
    priority = priority_map.get(severity, {"id": "3", "name": "Medium"})

    # Build the Jira issue payload
    # This follows Jira's REST API v3 schema
    jira_payload = {
        "fields": {
            "project": {"key": project_key},
            "summary": summary,
            "issuetype": {"name": "Bug"},
            "priority": priority,
            "description": {
                "type": "doc",
                "version": 1,
                "content": [
                    {
                        "type": "heading",
                        "attrs": {"level": 2},
                        "content": [{"type": "text", "text": "Database Incident Report"}]
                    },
                    {
                        "type": "paragraph",
                        "content": [
                            {"type": "text", "text": f"Database: {database}\n"},
                            {"type": "text", "text": f"Severity: {severity}\n"},
                            {"type": "text", "text": f"Detected: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"}
                        ]
                    },
                    {
                        "type": "heading",
                        "attrs": {"level": 3},
                        "content": [{"type": "text", "text": "Diagnosis"}]
                    },
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": diagnosis}]
                    },
                    {
                        "type": "heading",
                        "attrs": {"level": 3},
                        "content": [{"type": "text", "text": "Recommended Action"}]
                    },
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": recommendation}]
                    },
                    {
                        "type": "heading",
                        "attrs": {"level": 3},
                        "content": [{"type": "text", "text": "Runbook"}]
                    },
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": runbook_url}]
                    }
                ]
            },
            "labels": ["dba-agent", "auto-created", severity.lower()]
        }
    }

    payload_bytes = json.dumps(jira_payload).encode("utf-8")

    req = urllib.request.Request(
        url=api_url,
        data=payload_bytes,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Basic FAKE_BASE64_TOKEN"
        },
        method="POST"
    )

    try:
        response = urllib.request.urlopen(req, timeout=10)
        return {
            "success": True,
            "status_code": response.status,
            "ticket_key": f"{project_key}-{datetime.datetime.now().strftime('%H%M%S')}",
            "message": "Jira ticket created"
        }
    except Exception as e:
        return {
            "success": False,
            "status_code": None,
            "ticket_key": None,
            "message": f"Failed to create ticket: {str(e)}"
        }


# ---------------------------------------------------------
# TEST IT
# ---------------------------------------------------------

print("=" * 60)
print("JIRA INTEGRATION TEST")
print("=" * 60)

result = create_jira_ticket(
    api_url="https://httpbin.org/post",
    project_key="DBA",
    severity="CRITICAL",
    summary="Connection pool exhausted on production database",
    database="production",
    diagnosis="The reporting_app application is holding 142 idle connections "
              "without a connection pooler. Each web request opens a new "
              "connection and never releases it.",
    recommendation="1. Terminate idle connections older than 10 minutes\n"
                   "2. Deploy PgBouncer in transaction pooling mode\n"
                   "3. Set idle_in_transaction_session_timeout = 60s",
    runbook_url="https://wiki.example.com/runbooks/connection-exhaustion"
)

print(f"\nTicket creation result:")
print(f"  Success:     {result['success']}")
print(f"  Status code: {result['status_code']}")
print(f"  Ticket key:  {result['ticket_key']}")
print(f"  Message:     {result['message']}")

EOF
```

Expected output (yours will differ):
```
============================================================
JIRA INTEGRATION TEST
============================================================

Ticket creation result:
  Success:     True
  Status code: 200
  Ticket key:  DBA-143000
  Message:     Jira ticket created
```

---

## Step 5: The Complete Alert Pipeline Agent

### The Concept

Now we wire everything together: an agent that receives an alert, diagnoses it, and then triggers all three integrations (Slack, PagerDuty, Jira) based on the severity.

**DBA analogy:** This is your complete incident response runbook encoded as code. Instead of: "If P1, page the on-call, post to Slack, create a Jira ticket" being a human process, the agent does it automatically.

```
Alert arrives
    |
    v
[Agent diagnoses the problem]
    |
    v
[Decide severity: P1/P2/P3]
    |
    +--> P1/P2: PagerDuty incident + Slack + Jira
    +--> P3:    Slack + Jira (no page)
    +--> OK:    Slack only (informational)
```

### The Code

On your **Mac terminal**, run:

```bash
python3 << 'EOF'
# ---------------------------------------------------------
# What this script does:
#   Builds a complete alert pipeline agent that:
#   1. Receives an alert
#   2. Diagnoses the problem
#   3. Posts to Slack
#   4. Creates PagerDuty incident (if P1/P2)
#   5. Creates Jira ticket with runbook link
#
#   All API calls go to httpbin.org for testing.
#   Replace URLs with real endpoints in production.
# ---------------------------------------------------------

import urllib.request
import json
import datetime


# -----------------------------------------------------------------------
# INTEGRATION FUNCTIONS (simplified from previous steps)
# -----------------------------------------------------------------------

def send_to_slack(severity, database, summary, diagnosis, recommendation):
    """Post alert to Slack channel."""
    payload = {
        "text": f"[{severity}] {database}: {summary}",
        "blocks": [
            {"type": "header", "text": {"type": "plain_text", "text": f"Database Alert: {severity}"}},
            {"type": "section", "text": {"type": "mrkdwn", "text": f"*DB:* {database}\n*Summary:* {summary}\n*Diagnosis:* {diagnosis}\n*Action:* {recommendation}"}}
        ]
    }
    req = urllib.request.Request(
        url="https://httpbin.org/post",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        response = urllib.request.urlopen(req, timeout=10)
        return {"success": True, "service": "slack"}
    except Exception as e:
        return {"success": False, "service": "slack", "error": str(e)}


def send_to_pagerduty(severity, database, summary, details):
    """Create PagerDuty incident."""
    payload = {
        "routing_key": "FAKE_KEY",
        "event_action": "trigger",
        "dedup_key": f"dba-{database}-{datetime.datetime.now().strftime('%Y%m%d%H%M')}",
        "payload": {
            "summary": summary,
            "severity": severity.lower(),
            "source": "dba-agent",
            "component": database,
            "custom_details": details
        }
    }
    req = urllib.request.Request(
        url="https://httpbin.org/post",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        response = urllib.request.urlopen(req, timeout=10)
        return {"success": True, "service": "pagerduty", "dedup_key": payload["dedup_key"]}
    except Exception as e:
        return {"success": False, "service": "pagerduty", "error": str(e)}


def send_to_jira(severity, database, summary, diagnosis, recommendation):
    """Create Jira ticket."""
    payload = {
        "fields": {
            "project": {"key": "DBA"},
            "summary": summary,
            "issuetype": {"name": "Bug"},
            "description": {"content": f"DB: {database}\nDiagnosis: {diagnosis}\nAction: {recommendation}"}
        }
    }
    req = urllib.request.Request(
        url="https://httpbin.org/post",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        response = urllib.request.urlopen(req, timeout=10)
        return {"success": True, "service": "jira", "ticket": f"DBA-{datetime.datetime.now().strftime('%H%M%S')}"}
    except Exception as e:
        return {"success": False, "service": "jira", "error": str(e)}


# -----------------------------------------------------------------------
# DIAGNOSIS ENGINE (simulated - in production this calls your MCP tools)
# -----------------------------------------------------------------------

def diagnose_alert(alert: dict) -> dict:
    """
    Analyze an alert and return a diagnosis.
    In production, this would call MCP tools or an LLM.
    Here we use simple rule matching.

    DBA analogy: this is the agent's version of your DBA brain -
    the pattern matching you do when you see an alert at 3 AM.
    """

    metric = alert.get("metric", "")
    value = alert.get("value", 0)

    # Simple rule-based diagnosis - like a CASE statement
    if "connection" in metric.lower():
        if value > 180:
            return {
                "severity": "CRITICAL",
                "diagnosis": f"Connection pool near exhaustion ({value}/200). "
                             "Application is likely not releasing connections.",
                "recommendation": "Kill idle connections > 10 min, deploy PgBouncer",
                "runbook": "https://wiki.example.com/runbooks/connection-exhaustion"
            }
        elif value > 150:
            return {
                "severity": "WARNING",
                "diagnosis": f"Connection usage elevated ({value}/200). Monitor closely.",
                "recommendation": "Review connection pool settings, check for connection leaks",
                "runbook": "https://wiki.example.com/runbooks/connection-monitoring"
            }

    elif "replication_lag" in metric.lower():
        if value > 300:
            return {
                "severity": "CRITICAL",
                "diagnosis": f"Replication lag at {value}s. Standby may not be usable for failover.",
                "recommendation": "Check WAL sender state, network bandwidth, standby I/O",
                "runbook": "https://wiki.example.com/runbooks/replication-lag"
            }

    elif "disk" in metric.lower():
        if value > 90:
            return {
                "severity": "CRITICAL",
                "diagnosis": f"Disk usage at {value}%. Database will stop accepting writes soon.",
                "recommendation": "Run VACUUM FULL on bloated tables, archive old data, expand storage",
                "runbook": "https://wiki.example.com/runbooks/disk-full"
            }

    # Default: low severity
    return {
        "severity": "OK",
        "diagnosis": f"Metric {metric} = {value}. Within normal range.",
        "recommendation": "No action required",
        "runbook": "https://wiki.example.com/runbooks/general-monitoring"
    }


# -----------------------------------------------------------------------
# ALERT PIPELINE ORCHESTRATOR
# -----------------------------------------------------------------------

def process_alert(alert: dict) -> dict:
    """
    The main pipeline: receive alert -> diagnose -> notify.

    This is the orchestrator - it calls the diagnosis engine and then
    routes notifications to the right services based on severity.

    DBA analogy: this is the on-call DBA's workflow automated:
      1. Alert comes in
      2. DBA diagnoses (looks at metrics)
      3. DBA communicates (Slack, page, ticket)
    """

    database = alert.get("database", "unknown")
    metric = alert.get("metric", "unknown")
    value = alert.get("value", 0)
    summary = f"{metric} = {value} on {database}"

    print(f"\n{'=' * 60}")
    print(f"ALERT RECEIVED: {summary}")
    print(f"{'=' * 60}")

    # Step 1: Diagnose
    print("\n[1/3] Diagnosing...")
    diagnosis = diagnose_alert(alert)
    severity = diagnosis["severity"]
    print(f"  Severity:       {severity}")
    print(f"  Diagnosis:      {diagnosis['diagnosis']}")
    print(f"  Recommendation: {diagnosis['recommendation']}")

    # Step 2: Route notifications based on severity
    results = []

    # Always send to Slack
    print(f"\n[2/3] Sending notifications...")
    print(f"  Posting to Slack...")
    slack_result = send_to_slack(
        severity, database, summary,
        diagnosis["diagnosis"], diagnosis["recommendation"]
    )
    results.append(slack_result)
    print(f"  Slack: {'sent' if slack_result['success'] else 'FAILED'}")

    # P1/P2 (CRITICAL/WARNING) - also page and create ticket
    if severity in ("CRITICAL", "WARNING"):
        print(f"  Creating PagerDuty incident...")
        pd_result = send_to_pagerduty(
            severity, database, summary,
            {"diagnosis": diagnosis["diagnosis"], "metric": metric, "value": value}
        )
        results.append(pd_result)
        print(f"  PagerDuty: {'created' if pd_result['success'] else 'FAILED'}")

        print(f"  Creating Jira ticket...")
        jira_result = send_to_jira(
            severity, database, summary,
            diagnosis["diagnosis"], diagnosis["recommendation"]
        )
        results.append(jira_result)
        print(f"  Jira: {'created' if jira_result['success'] else 'FAILED'}")
    else:
        print(f"  Severity is OK - skipping PagerDuty and Jira")

    # Step 3: Summary
    print(f"\n[3/3] Pipeline complete")
    successful = sum(1 for r in results if r["success"])
    print(f"  Notifications sent: {successful}/{len(results)}")

    return {
        "alert": alert,
        "diagnosis": diagnosis,
        "notifications": results,
        "processed_at": datetime.datetime.now().isoformat()
    }


# -----------------------------------------------------------------------
# RUN THREE DIFFERENT ALERT SCENARIOS
# -----------------------------------------------------------------------

alerts = [
    {"database": "production", "metric": "active_connections", "value": 199},
    {"database": "production", "metric": "replication_lag_seconds", "value": 450},
    {"database": "staging",    "metric": "cpu_percent", "value": 35},
]

print("DBA ALERT PIPELINE AGENT")
print("=" * 60)

for alert in alerts:
    process_alert(alert)

print(f"\n{'=' * 60}")
print("All alerts processed.")

EOF
```

Expected output (yours will differ):
```
DBA ALERT PIPELINE AGENT
============================================================

============================================================
ALERT RECEIVED: active_connections = 199 on production
============================================================

[1/3] Diagnosing...
  Severity:       CRITICAL
  Diagnosis:      Connection pool near exhaustion (199/200). ...
  Recommendation: Kill idle connections > 10 min, deploy PgBouncer

[2/3] Sending notifications...
  Posting to Slack...
  Slack: sent
  Creating PagerDuty incident...
  PagerDuty: created
  Creating Jira ticket...
  Jira: created

[3/3] Pipeline complete
  Notifications sent: 3/3

============================================================
ALERT RECEIVED: replication_lag_seconds = 450 on production
============================================================
...

============================================================
ALERT RECEIVED: cpu_percent = 35 on staging
============================================================

[1/3] Diagnosing...
  Severity:       OK
  ...

[2/3] Sending notifications...
  Posting to Slack...
  Slack: sent
  Severity is OK - skipping PagerDuty and Jira

[3/3] Pipeline complete
  Notifications sent: 1/1

============================================================
All alerts processed.
```

---

## What You Learned

| Concept | Python Implementation | DBA Analogy |
|---|---|---|
| HTTP requests | `urllib.request.urlopen()` with JSON payload | Opening a database connection and sending a query |
| Slack webhook | POST JSON to a webhook URL | `pg_notify('dba_alerts', payload)` |
| PagerDuty Events API | POST JSON with routing key and severity | `pg_ctl promote` for humans - forces someone to act |
| Jira REST API | POST JSON with project key and issue fields | `INSERT INTO incident_log (...)` |
| Alert pipeline | Sequential: diagnose -> route by severity -> notify | On-call DBA workflow: triage -> diagnose -> communicate |
| Error handling | try/except around every API call | `EXCEPTION WHEN` in PL/pgSQL error blocks |

**Next:** Build 03 covers building feedback loops so your agent learns from DBA corrections.
