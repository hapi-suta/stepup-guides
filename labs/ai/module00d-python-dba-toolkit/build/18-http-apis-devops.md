# BUILD 18: HTTP and APIs - Alert Sender (DevOps)

## What You're Building

By the end of this guide you will have a working script called `alerter.py` in `~/pgdba/` that sends alerts via Slack webhook, email (SMTP), and generic webhooks when your DBA scripts detect problems - high connection counts, replication lag, failed backups. You will also see the complete listing of every script in your toolkit.

**Python concepts covered:** `requests` library, GET/POST, headers, JSON payloads, response handling, status codes, webhooks, basic API design patterns

**DBA task:** Build an alert routing layer on top of your `pg_monitor.py` health checks. When a check fails, the right people get notified through the right channel.

---

## Prerequisites

- Completed BUILD 17 (full toolkit exists in `~/pgdba/`)
- Python 3 installed
- Internet access (for testing with httpbin.org)
- Optional: a Slack workspace where you can create an incoming webhook

---

## Step 1: Install requests

The `requests` library is the standard Python package for making HTTP calls. It is not in Python's standard library, so you must install it separately.

On your Mac terminal, as your normal user:

```bash
pip3 install requests
```

- `pip3 install requests` - downloads and installs the `requests` package from PyPI
- `requests` wraps Python's lower-level `http.client` the way `psycopg2` wraps the libpq C library - you get a clean, high-level interface without dealing with raw socket management

```
Expected output (yours will differ):
Collecting requests
  Downloading requests-2.32.3-py3-none-any.whl (64 kB)
...
Successfully installed certifi-2024.8.30 charset-normalizer-3.3.2 idna-3.8 requests-2.32.3 urllib3-2.2.3
```

Verify:

```bash
python3 -c "import requests; print('requests version:', requests.__version__)"
```

```
Expected output (yours will differ):
requests version: 2.32.3
```

---

## Step 2: requests.get() - Make an HTTP GET Request

**DBA analogy:** `requests.get()` is like `dblink('remote_dsn', 'SELECT ...')` - you reach out to an external service and get data back. The URL is the address, the response is the result set.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import requests

# httpbin.org is a free HTTP testing service - safe to call from anywhere
response = requests.get('https://httpbin.org/get', timeout=10)

print('Status code:   ', response.status_code)
print('Content-Type:  ', response.headers.get('Content-Type'))
print('Response size: ', len(response.text), 'characters')
"
```

- `requests.get(url, timeout=10)` - sends an HTTP GET request to the URL; `timeout=10` raises an exception if no response arrives within 10 seconds (always set a timeout - never wait forever)
- `response.status_code` - the HTTP status code: `200` = OK, `404` = not found, `500` = server error
- `response.headers` - a dictionary of response headers
- `response.text` - the response body as a string

```
Expected output (yours will differ):
Status code:    200
Content-Type:   application/json
Response size:  308 characters
```

---

## Step 3: Response Object - .status_code, .text, .json()

**DBA analogy:** The response object is like a function return value that includes both an error code and the data. `status_code` is the error code (like a PL/pgSQL function returning `0` for success), `.json()` is the parsed payload (like a composite type return value).

On your Mac terminal, as your normal user:

```bash
python3 -c "
import requests

response = requests.get('https://httpbin.org/json', timeout=10)

print('Status code:', response.status_code)
print('Is OK:      ', response.ok)       # True if status_code < 400
print()

# Parse JSON response into a Python dictionary
data = response.json()
print('Type of data:', type(data))
print('Keys:        ', list(data.keys()))
print()

# Access nested data
if 'slideshow' in data:
    slideshow = data['slideshow']
    print('Title:', slideshow.get('title'))
    print('Author:', slideshow.get('author'))
"
```

- `response.ok` - shorthand for `response.status_code < 400`; `True` means no HTTP error
- `response.json()` - parses the response body as JSON and returns a Python dictionary or list; raises `ValueError` if the response is not valid JSON
- Never assume a response is JSON - always check `response.ok` before calling `.json()`

```
Expected output (yours will differ):
Status code: 200
Is OK:       True

Type of data: <class 'dict'>
Keys:         ['slideshow']

Title: Sample Slide Show
Author: Yours Truly
```

---

## Step 4: requests.post() - Send Data to an API

**DBA analogy:** `requests.post()` is like `dblink_exec('remote_dsn', 'INSERT INTO ...')` - you are pushing data to an external service, not just reading from it. Slack webhooks, PagerDuty, and most alerting services receive alerts via POST.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import requests
import json

# httpbin.org/post echoes back whatever you send it
payload = {
    'alert': 'HIGH_CONNECTIONS',
    'database': 'prod_orders',
    'current_connections': 195,
    'max_connections': 200,
    'severity': 'CRITICAL',
}

response = requests.post(
    'https://httpbin.org/post',
    json=payload,
    timeout=10,
)

print('Status:', response.status_code)

echo = response.json()
print('Server received our JSON:')
print(json.dumps(echo.get('json', {}), indent=2))
"
```

- `requests.post(url, json=payload)` - sends a POST request with `payload` serialized as JSON; automatically sets `Content-Type: application/json`
- `json.dumps(data, indent=2)` - pretty-print a Python dictionary as a JSON string with 2-space indentation (like `jsonb_pretty()` in PostgreSQL)
- httpbin.org echoes your payload back in the `json` key of its response - useful for testing without a real webhook

```
Expected output (yours will differ):
Status: 200
Server received our JSON:
{
  "alert": "HIGH_CONNECTIONS",
  "database": "prod_orders",
  "current_connections": 195,
  "max_connections": 200,
  "severity": "CRITICAL"
}
```

---

## Step 5: Headers and JSON Payload - Content-Type, Authorization

On your Mac terminal, as your normal user:

```bash
python3 -c "
import requests

# Many APIs require custom headers for authentication
headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer your_api_token_here',
    'X-DBA-Source': 'pgdba-alerter',
}

payload = {'message': 'test alert from DBA toolkit'}

response = requests.post(
    'https://httpbin.org/post',
    json=payload,
    headers=headers,
    timeout=10,
)

echo = response.json()
print('Headers the server saw:')
for key, val in echo.get('headers', {}).items():
    if key in ('Content-Type', 'Authorization', 'X-Dba-Source'):
        print(f'  {key}: {val}')
"
```

- `headers={}` - a dictionary of HTTP headers to include with the request; header names are case-insensitive in HTTP
- `Authorization: Bearer <token>` - the standard header for API token authentication; the token is like a session cookie, so store it in an environment variable, never hardcode it
- `X-DBA-Source` - custom headers often use the `X-` prefix by convention; useful for identifying the source of requests in server logs

```
Expected output (yours will differ):
Headers the server saw:
  Authorization: Bearer your_api_token_here
  Content-Type: application/json
  X-Dba-Source: pgdba-alerter
```

---

## Step 6: Build send_slack_alert() - POST to a Slack Incoming Webhook

Slack incoming webhooks accept a simple JSON payload with a `text` field. No OAuth, no complex auth - just a POST with a message.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import requests
import os

def send_slack_alert(message: str, webhook_url: str) -> bool:
    '''
    Send a message to a Slack channel via incoming webhook.
    Returns True on success, False on failure.
    '''
    payload = {'text': message}
    try:
        response = requests.post(webhook_url, json=payload, timeout=10)
        if response.ok:
            print(f'Slack alert sent: {response.status_code}')
            return True
        else:
            print(f'Slack returned error: {response.status_code} {response.text}')
            return False
    except requests.exceptions.Timeout:
        print('ERROR: Slack webhook timed out after 10 seconds')
        return False
    except requests.exceptions.ConnectionError as e:
        print(f'ERROR: Could not connect to Slack: {e}')
        return False

# Test with httpbin instead of a real Slack webhook
webhook_url = 'https://httpbin.org/post'
result = send_slack_alert(':rotating_light: HIGH CONNECTIONS on prod-db-01: 195/200 connections used (97.5%)', webhook_url)
print('Send succeeded:', result)
"
```

- `requests.exceptions.Timeout` - raised when the server does not respond within the timeout; always catch this separately
- `requests.exceptions.ConnectionError` - raised when the network is down or the hostname cannot be resolved; catch this too so your monitoring script doesn't crash
- `response.ok` - `True` if status code is 2xx; Slack returns `200` with body `ok` on success

```
Expected output (yours will differ):
Slack alert sent: 200
Send succeeded: True
```

---

## Step 7: Build send_email_alert() Using smtplib

`smtplib` is part of Python's standard library - no install needed. It speaks SMTP, which is the protocol that sends email.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import smtplib
import os
from email.message import EmailMessage

def send_email_alert(
    subject: str,
    body: str,
    to_addr: str,
    from_addr: str = 'dba-alerts@example.com',
    smtp_host: str = 'localhost',
    smtp_port: int = 25,
) -> bool:
    '''
    Send an email alert via SMTP.
    For Gmail/SES: set smtp_host, smtp_port=587, and use credentials from env vars.
    '''
    msg = EmailMessage()
    msg['Subject'] = subject
    msg['From']    = from_addr
    msg['To']      = to_addr
    msg.set_content(body)

    try:
        with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as smtp:
            smtp.send_message(msg)
        print(f'Email sent to {to_addr}')
        return True
    except ConnectionRefusedError:
        print(f'SMTP connection refused at {smtp_host}:{smtp_port} (no local mail server - expected in dev)')
        return False
    except Exception as e:
        print(f'Email error: {type(e).__name__}: {e}')
        return False

# Test call - will fail in dev if no local SMTP server (that is expected)
send_email_alert(
    subject='[CRITICAL] pg-prod-01: connection count 195/200',
    body='Database prod_orders has 195 active connections out of a max of 200.\nImmediate action required.',
    to_addr='dba-oncall@example.com',
)
print()
print('Note: ConnectionRefusedError above is expected in dev - no local SMTP server.')
print('In production: point smtp_host to SES/Sendgrid/your relay.')
"
```

- `EmailMessage()` - a modern Python email object that handles encoding and formatting automatically
- `smtplib.SMTP(host, port, timeout=10)` - connects to an SMTP server; use `smtplib.SMTP_SSL` for port 465, or call `smtp.starttls()` after connect for port 587
- `smtp.send_message(msg)` - sends the composed message; handles the SMTP protocol commands internally

```
Expected output (yours will differ):
SMTP connection refused at localhost:25 (no local mail server - expected in dev)

Note: ConnectionRefusedError above is expected in dev - no local SMTP server.
In production: point smtp_host to SES/Sendgrid/your relay.
```

---

## Step 8: Build send_webhook() - Generic Webhook Sender

On your Mac terminal, as your normal user:

```bash
python3 -c "
import requests
from typing import Any

def send_webhook(
    url: str,
    payload: dict[str, Any],
    headers: dict[str, str] | None = None,
    timeout: int = 10,
) -> bool:
    '''
    Send a JSON payload to any webhook URL.
    Generic sender used for PagerDuty, OpsGenie, custom endpoints.
    '''
    default_headers = {'Content-Type': 'application/json'}
    if headers:
        default_headers.update(headers)

    try:
        response = requests.post(url, json=payload, headers=default_headers, timeout=timeout)
        if response.ok:
            print(f'Webhook delivered: HTTP {response.status_code}')
            return True
        else:
            print(f'Webhook failed: HTTP {response.status_code}: {response.text[:100]}')
            return False
    except requests.exceptions.RequestException as e:
        print(f'Webhook error: {type(e).__name__}: {e}')
        return False

# Test with httpbin
result = send_webhook(
    url='https://httpbin.org/post',
    payload={
        'event_type': 'trigger',
        'routing_key': 'your_pagerduty_key',
        'payload': {
            'summary': 'Replication lag exceeded 60 seconds on pg-standby-01',
            'severity': 'critical',
            'source': 'pgdba-alerter',
        }
    }
)
print('Webhook result:', result)
"
```

- `requests.exceptions.RequestException` - the base class for all `requests` exceptions; catches Timeout, ConnectionError, HTTPError, and others in one `except` block
- `default_headers.update(headers)` - merge caller-supplied headers over the defaults; like `COALESCE` but for dictionaries

```
Expected output (yours will differ):
Webhook delivered: HTTP 200
Webhook result: True
```

---

## Step 9: Build AlertManager Class - Route Alerts by Severity

On your Mac terminal, as your normal user:

```bash
python3 -c "
import requests
import smtplib
from email.message import EmailMessage
from typing import Any

class AlertManager:
    '''
    Routes alerts based on severity level:
      CRITICAL -> Slack + email
      WARNING  -> Slack only
      INFO     -> print to stdout only
    '''

    def __init__(
        self,
        slack_webhook_url: str = '',
        email_to: str = '',
        smtp_host: str = 'localhost',
        smtp_port: int = 25,
    ) -> None:
        self.slack_webhook_url = slack_webhook_url
        self.email_to = email_to
        self.smtp_host = smtp_host
        self.smtp_port = smtp_port

    def send(self, severity: str, message: str) -> None:
        '''
        severity: CRITICAL, WARNING, or INFO
        '''
        severity = severity.upper()
        print(f'[{severity}] {message}')

        if severity in ('CRITICAL', 'WARNING'):
            self._slack(severity, message)

        if severity == 'CRITICAL' and self.email_to:
            self._email(message)

    def _slack(self, severity: str, message: str) -> None:
        if not self.slack_webhook_url:
            print('  (Slack: no webhook URL configured, skipping)')
            return
        emoji = ':rotating_light:' if severity == 'CRITICAL' else ':warning:'
        payload = {'text': f'{emoji} *[{severity}]* {message}'}
        try:
            r = requests.post(self.slack_webhook_url, json=payload, timeout=10)
            print(f'  Slack: HTTP {r.status_code}')
        except requests.exceptions.RequestException as e:
            print(f'  Slack error: {e}')

    def _email(self, message: str) -> None:
        msg = EmailMessage()
        msg['Subject'] = f'[CRITICAL] DBA Alert'
        msg['From']    = 'dba-alerts@example.com'
        msg['To']      = self.email_to
        msg.set_content(message)
        try:
            with smtplib.SMTP(self.smtp_host, self.smtp_port, timeout=5) as smtp:
                smtp.send_message(msg)
            print(f'  Email: sent to {self.email_to}')
        except Exception as e:
            print(f'  Email: {type(e).__name__} (expected in dev)')

# Test routing
am = AlertManager(
    slack_webhook_url='https://httpbin.org/post',
    email_to='oncall@example.com',
)
am.send('CRITICAL', 'pg-prod-01: connection count 195/200 (97.5%)')
print()
am.send('WARNING',  'pg-prod-01: replication lag 45 seconds')
print()
am.send('INFO',     'pg-prod-01: checkpoint completed in 12.3s')
"
```

- `severity.upper()` - normalize input so `'critical'` and `'CRITICAL'` both work
- `self._slack(...)` and `self._email(...)` - private methods by convention (prefixed with `_`); not enforced by Python, but signals to other developers that these are internal implementation details

```
Expected output (yours will differ):
[CRITICAL] pg-prod-01: connection count 195/200 (97.5%)
  Slack: HTTP 200
  Email: ConnectionRefusedError (expected in dev)

[WARNING] pg-prod-01: replication lag 45 seconds
  Slack: HTTP 200

[INFO] pg-prod-01: checkpoint completed in 12.3s
```

---

## Step 10: Error Handling - Retry with Backoff When Slack Is Down

On your Mac terminal, as your normal user:

```bash
python3 -c "
import requests
import time
from typing import Any

def send_with_retry(
    url: str,
    payload: dict[str, Any],
    max_attempts: int = 3,
    backoff_seconds: float = 2.0,
) -> bool:
    '''
    POST to a webhook with exponential backoff on failure.
    Attempt 1: immediate
    Attempt 2: wait 2s
    Attempt 3: wait 4s
    '''
    for attempt in range(1, max_attempts + 1):
        try:
            response = requests.post(url, json=payload, timeout=10)
            if response.ok:
                print(f'Delivered on attempt {attempt}')
                return True
            else:
                print(f'Attempt {attempt}: HTTP {response.status_code} - retrying...')
        except requests.exceptions.RequestException as e:
            print(f'Attempt {attempt}: {type(e).__name__} - retrying...')

        if attempt < max_attempts:
            wait = backoff_seconds * (2 ** (attempt - 1))   # 2s, 4s, 8s...
            print(f'Waiting {wait:.0f}s before retry...')
            time.sleep(wait)

    print(f'All {max_attempts} attempts failed')
    return False

# Test against httpbin (will succeed on first attempt)
result = send_with_retry(
    url='https://httpbin.org/post',
    payload={'alert': 'backup_failed', 'server': 'pg-prod-01'},
)
print('Final result:', result)
"
```

- `2 ** (attempt - 1)` - exponential backoff: attempt 1 waits `2 * 1 = 2s`, attempt 2 waits `2 * 2 = 4s`, attempt 3 waits `2 * 4 = 8s`
- `time.sleep(wait)` - pause execution for the given number of seconds; be careful using this in scripts that also monitor timeouts
- Exponential backoff is standard practice for any network call - avoid hammering a service that is already struggling

```
Expected output (yours will differ):
Delivered on attempt 1
Final result: True
```

---

## Step 11: Environment Variables - Never Hardcode Secrets

**DBA analogy:** You already know this. You never hardcode a database password in a script - you use `~/.pgpass`, `PGPASSWORD`, or `libpq` connection services. The same rule applies to Slack webhook URLs, SMTP passwords, and API tokens.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import os

# Read secrets from environment variables
slack_url    = os.environ.get('SLACK_WEBHOOK_URL', '')
smtp_pass    = os.environ.get('SMTP_PASSWORD', '')
alert_email  = os.environ.get('DBA_ALERT_EMAIL', 'oncall@example.com')

print('SLACK_WEBHOOK_URL set:', bool(slack_url))
print('SMTP_PASSWORD set:    ', bool(smtp_pass))
print('DBA_ALERT_EMAIL:      ', alert_email)
print()

# Pattern: fail loudly if a required variable is missing
required_vars = ['SLACK_WEBHOOK_URL']
missing = [v for v in required_vars if not os.environ.get(v)]
if missing:
    print(f'WARNING: Missing env vars: {missing}')
    print('Set them with: export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...')
else:
    print('All required env vars are set')
"
```

- `os.environ.get('VAR', default)` - returns the environment variable value, or `default` if it is not set; safer than `os.environ['VAR']` which raises `KeyError`
- `bool(slack_url)` - an empty string is falsy; `bool('')` is `False`, `bool('https://...')` is `True`

```
Expected output (yours will differ):
SLACK_WEBHOOK_URL set: False
SMTP_PASSWORD set:     False
DBA_ALERT_EMAIL:       oncall@example.com

WARNING: Missing env vars: ['SLACK_WEBHOOK_URL']
Set them with: export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
```

---

## Step 12: Integrate with pg_monitor.py - Trigger Alerts on Health Check Failure

On your Mac terminal, as your normal user:

```bash
python3 -c "
import os
import requests
from typing import Any

# Simulate the kind of health check results pg_monitor.py would produce
def fake_health_check() -> list[dict[str, Any]]:
    return [
        {'check': 'connection_count', 'status': 'CRITICAL',
         'detail': 'connections=195/200 (97.5%)', 'server': 'pg-prod-01'},
        {'check': 'replication_lag',  'status': 'WARNING',
         'detail': 'standby lag=48s (threshold=30s)', 'server': 'pg-prod-01'},
        {'check': 'disk_usage',       'status': 'OK',
         'detail': 'used=45% of 500GB', 'server': 'pg-prod-01'},
    ]

def run_checks_and_alert(webhook_url: str) -> None:
    results = fake_health_check()

    for result in results:
        status  = result['status']
        check   = result['check']
        detail  = result['detail']
        server  = result['server']

        if status == 'OK':
            print(f'[OK]  {check}: {detail}')
            continue

        message = f'[{status}] {server} / {check}: {detail}'
        print(f'ALERT: {message}')

        payload = {'text': f'*DBA ALERT* {message}'}
        try:
            r = requests.post(webhook_url, json=payload, timeout=10)
            print(f'  -> webhook: HTTP {r.status_code}')
        except requests.exceptions.RequestException as e:
            print(f'  -> webhook failed: {e}')

# Test
run_checks_and_alert('https://httpbin.org/post')
"
```

This is the integration pattern: health check returns structured results, alerter iterates over failures and posts to the webhook.

```
Expected output (yours will differ):
ALERT: [CRITICAL] pg-prod-01 / connection_count: connections=195/200 (97.5%)
  -> webhook: HTTP 200
ALERT: [WARNING] pg-prod-01 / replication_lag: standby lag=48s (threshold=30s)
  -> webhook: HTTP 200
[OK]  disk_usage: used=45% of 500GB
```

---

## Step 13: Build the Final alerter.py Script

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/alerter.py << 'PYEOF'
#!/usr/bin/env python3
"""
alerter.py - DBA alert sender
Sends CRITICAL/WARNING alerts via Slack webhook, email (SMTP),
and generic webhooks. Integrates with pg_monitor.py health checks.

Environment variables:
  SLACK_WEBHOOK_URL  - Slack incoming webhook URL
  DBA_ALERT_EMAIL    - email address to send CRITICAL alerts to
  SMTP_HOST          - SMTP server hostname (default: localhost)
  SMTP_PORT          - SMTP server port (default: 25)
  SMTP_USER          - SMTP username (optional, for authenticated relay)
  SMTP_PASSWORD      - SMTP password (optional, for authenticated relay)
"""

import os
import smtplib
import time
from email.message import EmailMessage
from typing import Any

import requests


# ---------------------------------------------------------------------------
# Low-level senders
# ---------------------------------------------------------------------------

def send_slack_alert(message: str, webhook_url: str, max_attempts: int = 3) -> bool:
    """
    Send a message to Slack via incoming webhook.
    Retries up to max_attempts times with exponential backoff.
    """
    payload = {'text': message}
    for attempt in range(1, max_attempts + 1):
        try:
            response = requests.post(webhook_url, json=payload, timeout=10)
            if response.ok:
                return True
            print(f'Slack attempt {attempt}: HTTP {response.status_code}')
        except requests.exceptions.RequestException as e:
            print(f'Slack attempt {attempt}: {type(e).__name__}: {e}')
        if attempt < max_attempts:
            wait = 2.0 * (2 ** (attempt - 1))
            time.sleep(wait)
    return False


def send_email_alert(
    subject: str,
    body: str,
    to_addr: str,
    from_addr: str = 'dba-alerts@noreply.internal',
) -> bool:
    """
    Send an email alert via SMTP.
    Reads SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD from environment.
    """
    smtp_host = os.environ.get('SMTP_HOST', 'localhost')
    smtp_port = int(os.environ.get('SMTP_PORT', '25'))
    smtp_user = os.environ.get('SMTP_USER', '')
    smtp_pass = os.environ.get('SMTP_PASSWORD', '')

    msg = EmailMessage()
    msg['Subject'] = subject
    msg['From']    = from_addr
    msg['To']      = to_addr
    msg.set_content(body)

    try:
        with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as smtp:
            if smtp_port == 587:
                smtp.starttls()
            if smtp_user and smtp_pass:
                smtp.login(smtp_user, smtp_pass)
            smtp.send_message(msg)
        return True
    except Exception as e:
        print(f'Email error: {type(e).__name__}: {e}')
        return False


def send_webhook(
    url: str,
    payload: dict[str, Any],
    headers: dict[str, str] | None = None,
) -> bool:
    """
    Send a JSON payload to any webhook URL (PagerDuty, OpsGenie, custom endpoints).
    """
    default_headers = {'Content-Type': 'application/json'}
    if headers:
        default_headers.update(headers)
    try:
        response = requests.post(url, json=payload, headers=default_headers, timeout=10)
        return response.ok
    except requests.exceptions.RequestException as e:
        print(f'Webhook error: {type(e).__name__}: {e}')
        return False


# ---------------------------------------------------------------------------
# Alert router
# ---------------------------------------------------------------------------

class AlertManager:
    """
    Routes alerts based on severity:
      CRITICAL -> Slack + email
      WARNING  -> Slack only
      INFO     -> stdout only
    """

    def __init__(self) -> None:
        self.slack_webhook_url = os.environ.get('SLACK_WEBHOOK_URL', '')
        self.email_to          = os.environ.get('DBA_ALERT_EMAIL', '')

    def send(self, severity: str, message: str) -> None:
        """Send an alert. severity must be CRITICAL, WARNING, or INFO."""
        severity = severity.upper()
        print(f'[{severity}] {message}')

        if severity in ('CRITICAL', 'WARNING') and self.slack_webhook_url:
            emoji = ':rotating_light:' if severity == 'CRITICAL' else ':warning:'
            slack_msg = f'{emoji} *[{severity}]* {message}'
            success = send_slack_alert(slack_msg, self.slack_webhook_url)
            print(f'  Slack: {"OK" if success else "FAILED"}')

        if severity == 'CRITICAL' and self.email_to:
            success = send_email_alert(
                subject=f'[CRITICAL] DBA Alert: {message[:60]}',
                body=message,
                to_addr=self.email_to,
            )
            print(f'  Email: {"OK" if success else "FAILED"}')


# ---------------------------------------------------------------------------
# Integration with pg_monitor.py
# ---------------------------------------------------------------------------

def run_and_alert() -> None:
    """
    Example integration: run health checks and send alerts on failures.
    Replace the simulated results with a real call to pg_monitor.py checks.
    """
    # In production, import and call your pg_monitor functions here:
    # from pg_monitor import check_connections, check_replication_lag
    simulated_results: list[dict[str, Any]] = [
        {'check': 'connection_count', 'status': 'CRITICAL',
         'detail': 'connections=195/200 (97.5%)', 'server': 'pg-prod-01'},
        {'check': 'replication_lag',  'status': 'WARNING',
         'detail': 'standby lag=48s (threshold=30s)', 'server': 'pg-prod-01'},
        {'check': 'disk_usage',       'status': 'OK',
         'detail': 'used=45% of 500GB', 'server': 'pg-prod-01'},
    ]

    am = AlertManager()
    for result in simulated_results:
        if result['status'] == 'OK':
            print(f"[OK]  {result['check']}: {result['detail']}")
            continue
        msg = f"{result['server']} / {result['check']}: {result['detail']}"
        am.send(result['status'], msg)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    print('=== alerter.py ===')
    print()
    slack_url   = os.environ.get('SLACK_WEBHOOK_URL', '')
    alert_email = os.environ.get('DBA_ALERT_EMAIL', '')
    print(f'Slack webhook configured: {bool(slack_url)}')
    print(f'Alert email configured:   {bool(alert_email)}')
    print()

    if not slack_url:
        print('TIP: To enable Slack alerts, run:')
        print('  export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL')
        print()

    run_and_alert()


if __name__ == '__main__':
    main()
PYEOF
```

---

## Step 14: Test with a Mock Webhook

On your Mac terminal, as your normal user:

```bash
export SLACK_WEBHOOK_URL="https://httpbin.org/post"
export DBA_ALERT_EMAIL="oncall@example.com"
python3 ~/pgdba/alerter.py
```

- `export SLACK_WEBHOOK_URL=...` - sets the environment variable in your current shell session; the Python script reads it with `os.environ.get()`
- Point at `httpbin.org/post` as a stand-in for Slack - it accepts any POST and returns the payload back; safe for testing

```
Expected output (yours will differ):
=== alerter.py ===

Slack webhook configured: True
Alert email configured:   True

[OK]  disk_usage: used=45% of 500GB
[CRITICAL] pg-prod-01 / connection_count: connections=195/200 (97.5%)
  Slack: OK
  Email: FAILED
[WARNING] pg-prod-01 / replication_lag: standby lag=48s (threshold=30s)
  Slack: OK
```

Email fails because there is no local SMTP server in development - that is expected. In production, point `SMTP_HOST` at your SES endpoint, mail relay, or Sendgrid gateway.

---

## Step 15: Final Demo - Health Check That Triggers an Alert

Run a live health check against your local PostgreSQL and trigger an alert if connections are high.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import os
import psycopg2
import requests

os.environ.setdefault('SLACK_WEBHOOK_URL', 'https://httpbin.org/post')

def get_connection_stats() -> dict[str, int]:
    conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
    cur = conn.cursor()
    cur.execute(\"\"\"
        SELECT
            count(*) AS total,
            current_setting('max_connections')::int AS max_conns
        FROM pg_stat_activity
    \"\"\")
    row = cur.fetchone()
    cur.close()
    conn.close()
    return {'total': row[0], 'max_conns': row[1]}

def check_and_alert() -> None:
    stats = get_connection_stats()
    pct   = (stats['total'] / stats['max_conns']) * 100
    print(f'Connections: {stats[\"total\"]}/{stats[\"max_conns\"]} ({pct:.1f}%)')

    severity = None
    if pct >= 90:
        severity = 'CRITICAL'
    elif pct >= 75:
        severity = 'WARNING'

    if severity:
        message = f':rotating_light: *[{severity}]* pg-local: {stats[\"total\"]}/{stats[\"max_conns\"]} connections ({pct:.1f}%)'
        webhook_url = os.environ['SLACK_WEBHOOK_URL']
        r = requests.post(webhook_url, json={'text': message}, timeout=10)
        print(f'Alert sent: HTTP {r.status_code}')
    else:
        print('Connection count is healthy - no alert needed')

check_and_alert()
"
```

```
Expected output (yours will differ):
Connections: 4/100 (4.0%)
Connection count is healthy - no alert needed
```

---

## Complete ~/pgdba/ Directory - All 18 Scripts

You have built a complete Python DBA toolkit from scratch. Here is the full listing.

On your Mac terminal, as your normal user:

```bash
ls -1 ~/pgdba/*.py && echo "" && ls -1 ~/pgdba/tests/*.py
```

```
Expected output (yours will differ):
/Users/you/pgdba/alerter.py
/Users/you/pgdba/backup_manager.py
/Users/you/pgdba/bloat_analyzer.py
/Users/you/pgdba/conf_parser.py
/Users/you/pgdba/connection_pooler.py
/Users/you/pgdba/data_exporter.py
/Users/you/pgdba/log_parser.py
/Users/you/pgdba/pg_monitor.py
/Users/you/pgdba/replication_monitor.py
/Users/you/pgdba/user_manager.py
...

/Users/you/pgdba/tests/conftest.py
/Users/you/pgdba/tests/test_basics.py
/Users/you/pgdba/tests/test_conf_parser.py
/Users/you/pgdba/tests/test_log_parser.py
/Users/you/pgdba/tests/test_user_manager.py
```

Here is what you built across all 18 guides:

| Build | Script | What It Does |
|-------|--------|--------------|
| 01 | `install_check.py` | Variables, types, verifying Python + psycopg2 setup |
| 02 | `instance_manager.py` | Control flow, subprocess, start/stop/status for PostgreSQL |
| 03 | `db_connector.py` | psycopg2 connections, cursors, parameterized queries |
| 04 | `conf_parser.py` | File I/O, parse postgresql.conf and pg_hba.conf |
| 05 | `error_handler.py` | try/except, specific psycopg2 error types |
| 06 | `module_demo.py` | Functions, modules, imports, __name__ guard |
| 07 | `user_manager.py` | Classes, objects, manage roles and privileges |
| 08 | `schema_inspector.py` | Lists, dicts, comprehensions, query pg_catalog |
| 09 | `backup_manager.py` | Datetime, timedelta, schedule and verify backups |
| 10 | `data_migrator.py` | Iterators, generators, stream large table migrations |
| 11 | `pg_monitor.py` | Decorators, context managers, health check framework |
| 12 | `config_manager.py` | JSON, YAML, environment config management |
| 13 | `replication_monitor.py` | Async/await, concurrent checks across replicas |
| 14 | `connection_pooler.py` | Advanced OOP, connection pool with retry logic |
| 15 | `data_exporter.py` | CSV, Parquet, export query results to files |
| 16 | `log_parser.py` | Regex, parse PostgreSQL logs for errors and slow queries |
| 17 | `tests/` | pytest, mocking, full test suite for the toolkit |
| 18 | `alerter.py` | HTTP, webhooks, Slack/email alerts from health checks |

You started this module knowing PostgreSQL deeply but having zero Python experience. You now have 18 working scripts that automate real DBA tasks - the same tasks you used to do manually with `psql`, `grep`, and shell scripts.

Every script in `~/pgdba/` is yours to keep, modify, and extend. Run the test suite any time you make a change:

```bash
python3 -m pytest ~/pgdba/tests/ -v --tb=short
```

---

## What You Built

Your script `~/pgdba/alerter.py` can:
- Send formatted alerts to a Slack channel via incoming webhook
- Send email alerts via SMTP (works with SES, Sendgrid, or any relay)
- POST to any generic webhook (PagerDuty, OpsGenie, custom endpoints)
- Route alerts by severity: CRITICAL goes to Slack + email, WARNING to Slack only
- Retry failed webhook calls with exponential backoff
- Read all secrets from environment variables - nothing hardcoded
- Integrate with `pg_monitor.py` health check results

**Python concepts used:**
- `requests.get()` and `requests.post()` - HTTP calls to external services
- Response object - `.status_code`, `.text`, `.json()`, `.ok`
- Headers dictionary - `Content-Type`, `Authorization`, custom headers
- JSON payloads - `json=payload` parameter serializes automatically
- `smtplib` - standard library SMTP client for sending email
- `os.environ.get()` - read secrets from environment variables
- Classes (`AlertManager`) - encapsulate routing logic with state
- `requests.exceptions` - catch network errors specifically, not silently

**Next steps for your toolkit:**
- Connect `alerter.py` to your real Slack workspace
- Add `alerter.py` to your crontab alongside `pg_monitor.py`
- Extend `AlertManager.send()` to write alerts to a PostgreSQL audit table
- Add a `send_pagerduty()` method for on-call escalation
