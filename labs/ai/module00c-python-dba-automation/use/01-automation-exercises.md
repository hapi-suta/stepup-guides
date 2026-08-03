# USE: DBA Automation Exercises

**Module:** 00c - Python DBA Automation
**Prerequisites:** BUILD 01-04
**Time:** 90-120 minutes (all 5 exercises)

Each exercise gives you a scenario, starter code with TODOs, expected output, and hints. Write real scripts that solve real DBA problems.

---

## Exercise 1: Connection Tester

**Scenario:** You manage databases across 11 datacenters. Before a maintenance window, you need to verify connectivity to every database. Write a script that reads a config file with connection details and tests each one.

**Create the config file:**

```bash
vi ~/db_connections.conf
```

Enter:

```
# format: name,host,port,dbname,user,password
local_postgres,localhost,5432,postgres,postgres,
dev_db,localhost,5432,mydb,postgres,
# Add your real databases here
```

**Starter code - create with `vi`:**

```bash
vi ~/connection_tester.py
```

```python
#!/usr/bin/env python3
"""Test connectivity to multiple PostgreSQL databases from a config file."""

import sys
import time
import psycopg2


def load_config(config_path: str) -> list[dict]:
    """Read connection config file and return list of connection dicts."""
    connections = []
    # TODO: Open the file, skip blank lines and comments (lines starting with #)
    # TODO: Split each line by comma into: name, host, port, dbname, user, password
    # TODO: Return a list of dicts with those keys
    return connections


def test_connection(conn_info: dict) -> dict:
    """Test a single database connection. Return result dict."""
    result = {
        'name': conn_info['name'],
        'host': conn_info['host'],
        'status': 'UNKNOWN',
        'latency_ms': 0,
        'version': '',
        'error': ''
    }

    # TODO: Try to connect using psycopg2.connect()
    # TODO: Measure connection time (use time.time() before and after)
    # TODO: Run "SELECT version()" to get server version
    # TODO: Set status to 'OK' on success, 'FAIL' on exception
    # TODO: Store the error message if connection fails
    # TODO: Always close the connection

    return result


def print_report(results: list[dict]) -> None:
    """Print a formatted connection test report."""
    # TODO: Print header row
    # TODO: Print each result with name, host, status, latency, version
    # TODO: Print summary: total, passed, failed
    pass


def main() -> None:
    config_path = sys.argv[1] if len(sys.argv) > 1 else 'db_connections.conf'
    connections = load_config(config_path)

    if not connections:
        print(f'No connections found in {config_path}')
        sys.exit(1)

    results = []
    for conn_info in connections:
        result = test_connection(conn_info)
        results.append(result)

    print_report(results)

    # Exit code: 1 if any failures
    failed = [r for r in results if r['status'] == 'FAIL']
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
```

**Expected output:**

```
Connection Test Report
==================================================
Name                Host            Status  Latency   Version
---------------------------------------------------------------
local_postgres      localhost       OK      12ms      PostgreSQL 16.4...
dev_db              localhost       OK      8ms       PostgreSQL 16.4...

Summary: 2 tested, 2 passed, 0 failed
```

**Hints:**
- Use `with open(config_path) as f:` to read the file
- `line.strip()` removes whitespace; `line.startswith('#')` checks for comments
- `line.split(',')` splits by comma
- Measure latency: `start = time.time()` before connect, `(time.time() - start) * 1000` after for milliseconds
- Catch `psycopg2.OperationalError` specifically for connection failures

---

## Exercise 2: Replication Monitor

**Scenario:** You run streaming replication across multiple standbys. Write a script that queries `pg_stat_replication` on the primary and formats a clean replication lag report with status indicators.

**Starter code:**

```bash
vi ~/replication_monitor.py
```

```python
#!/usr/bin/env python3
"""Monitor PostgreSQL streaming replication and report lag status."""

import os
import sys
import psycopg2
from contextlib import closing
from datetime import datetime

# Thresholds
LAG_WARN_BYTES = 50 * 1024 * 1024   # 50 MB
LAG_CRIT_BYTES = 200 * 1024 * 1024  # 200 MB


def get_connection():
    """Connect to the primary server."""
    # TODO: Connect using environment variables
    pass


def check_is_primary(cur) -> bool:
    """Verify we are connected to the primary, not a replica."""
    # TODO: Use pg_is_in_recovery() - returns false on primary, true on replica
    pass


def get_replication_status(cur) -> list[dict]:
    """Query pg_stat_replication and return structured data."""
    # TODO: Query pg_stat_replication for:
    #   client_addr, application_name, state, sync_state,
    #   sent_lsn, write_lsn, flush_lsn, replay_lsn,
    #   lag in bytes (pg_wal_lsn_diff(sent_lsn, replay_lsn))
    # TODO: Return list of dicts with status (OK/WARNING/CRITICAL) based on lag
    return []


def format_bytes(num_bytes: int) -> str:
    """Convert bytes to human-readable format."""
    # TODO: Convert to KB, MB, or GB as appropriate
    pass


def print_report(replicas: list[dict]) -> None:
    """Print formatted replication report."""
    # TODO: Print timestamp header
    # TODO: For each replica: address, app name, state, sync mode, lag (human readable), status
    # TODO: Color-code status (OK=green, WARNING=yellow, CRITICAL=red)
    pass


def main() -> None:
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            if not check_is_primary(cur):
                print('ERROR: This server is a replica, not the primary')
                sys.exit(1)

            replicas = get_replication_status(cur)

            if not replicas:
                print('No replicas connected')
                sys.exit(0)

            print_report(replicas)
    finally:
        conn.close()


if __name__ == '__main__':
    main()
```

**Expected output (when replicas are connected):**

```
Replication Report - 2026-06-09 14:30:00
==================================================
Replica              App Name        State       Sync     Lag         Status
---------------------------------------------------------------------------------
10.0.1.50            standby1        streaming   async    1.2 MB      OK
10.0.2.50            standby2        streaming   async    78.5 MB     WARNING
10.0.3.50            standby3        streaming   sync     0.0 MB      OK

Summary: 3 replicas, 1 warning, 0 critical
```

**Hints:**
- `pg_is_in_recovery()` returns a boolean - `cur.fetchone()[0]` will be True on replicas
- `pg_wal_lsn_diff(sent_lsn, replay_lsn)` gives lag in bytes
- For format_bytes: divide by 1024 for KB, 1024*1024 for MB, 1024*1024*1024 for GB
- If no replicas exist (standalone server), the query returns 0 rows - handle that gracefully

---

## Exercise 3: Table Growth Tracker

**Scenario:** You need to find which tables are growing fastest to plan storage. Write a script that snapshots table sizes to CSV, then compares two snapshots to find the fastest-growing tables.

**Starter code:**

```bash
vi ~/table_growth.py
```

```python
#!/usr/bin/env python3
"""Track table size growth by comparing snapshots over time."""

import os
import sys
import csv
from datetime import datetime
from contextlib import closing
import psycopg2

SNAPSHOT_DIR = '/tmp/table_snapshots'


def take_snapshot(conn) -> str:
    """Snapshot all table sizes to a CSV file. Return the file path."""
    os.makedirs(SNAPSHOT_DIR, exist_ok=True)
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    filepath = os.path.join(SNAPSHOT_DIR, f'tables_{timestamp}.csv')

    # TODO: Query pg_stat_user_tables joined with pg_total_relation_size
    # TODO: Get: schemaname, relname, total_size_bytes, n_live_tup
    # TODO: Write results to CSV with columns: schema, table, size_bytes, row_count, timestamp
    # TODO: Return the filepath

    return filepath


def load_snapshot(filepath: str) -> dict:
    """Load a snapshot CSV into a dict keyed by schema.table."""
    # TODO: Read the CSV file
    # TODO: Return dict like {'public.orders': {'size_bytes': 123456, 'row_count': 5000, 'timestamp': '...'}}
    return {}


def compare_snapshots(old_path: str, new_path: str) -> list[dict]:
    """Compare two snapshots and return growth data sorted by size increase."""
    old_data = load_snapshot(old_path)
    new_data = load_snapshot(new_path)

    growth = []
    # TODO: For each table in new_data, check if it exists in old_data
    # TODO: Calculate size_diff = new_size - old_size
    # TODO: Calculate row_diff = new_rows - old_rows
    # TODO: Calculate growth_pct = (size_diff / old_size * 100) if old_size > 0
    # TODO: Flag tables that are new (in new but not in old)
    # TODO: Sort by size_diff descending

    return growth


def print_growth_report(growth: list[dict]) -> None:
    """Print a formatted growth report."""
    # TODO: Print header with old and new snapshot timestamps
    # TODO: For each table: name, old size, new size, growth (bytes and %), row change
    # TODO: Highlight tables growing > 10% or > 100MB
    pass


def main() -> None:
    if len(sys.argv) < 2:
        print('Usage:')
        print('  python3 table_growth.py snapshot          - take a new snapshot')
        print('  python3 table_growth.py compare OLD NEW   - compare two snapshots')
        print(f'  python3 table_growth.py list              - list snapshots in {SNAPSHOT_DIR}')
        sys.exit(1)

    command = sys.argv[1]

    if command == 'snapshot':
        conn = psycopg2.connect(
            host=os.environ.get('PGHOST', 'localhost'),
            dbname=os.environ.get('PGDATABASE', 'postgres'),
            user=os.environ.get('PGUSER', 'postgres'),
            password=os.environ.get('PGPASSWORD', '')
        )
        try:
            filepath = take_snapshot(conn)
            print(f'Snapshot saved: {filepath}')
        finally:
            conn.close()

    elif command == 'compare':
        if len(sys.argv) < 4:
            print('Usage: python3 table_growth.py compare OLD_FILE NEW_FILE')
            sys.exit(1)
        growth = compare_snapshots(sys.argv[2], sys.argv[3])
        print_growth_report(growth)

    elif command == 'list':
        if os.path.exists(SNAPSHOT_DIR):
            files = sorted(os.listdir(SNAPSHOT_DIR))
            for f in files:
                path = os.path.join(SNAPSHOT_DIR, f)
                size = os.path.getsize(path)
                print(f'  {f} ({size} bytes)')
        else:
            print(f'No snapshots directory: {SNAPSHOT_DIR}')


if __name__ == '__main__':
    main()
```

**Expected output:**

```
# Take first snapshot
$ python3 table_growth.py snapshot
Snapshot saved: /tmp/table_snapshots/tables_20260609_143000.csv

# Wait some time, take second snapshot
$ python3 table_growth.py snapshot
Snapshot saved: /tmp/table_snapshots/tables_20260609_150000.csv

# Compare
$ python3 table_growth.py compare /tmp/table_snapshots/tables_20260609_143000.csv /tmp/table_snapshots/tables_20260609_150000.csv
Table Growth Report
Old: 2026-06-09 14:30:00 | New: 2026-06-09 15:00:00
==================================================
Table                    Old Size    New Size    Growth      Growth%  Row Change
----------------------------------------------------------------------------------
public.orders            180 MB      195 MB      +15 MB      +8.3%   +12000
public.events            45 MB       48 MB       +3 MB       +6.7%   +5000
public.users             32 MB       32 MB       +0 MB       +0.0%   +10
```

**Hints:**
- For `take_snapshot`, use `pg_total_relation_size(relid)` for total size (includes indexes + toast)
- `csv.DictReader` and `csv.DictWriter` make reading/writing CSVs with named columns easy
- When comparing, handle the case where a table is new (exists in new snapshot but not old)
- Also handle the case where a table was dropped (exists in old but not new)

---

## Exercise 4: Security Auditor

**Scenario:** Before a SOC 2 audit, you need a complete security report on your PostgreSQL roles. Write a script that checks for common security issues.

**Starter code:**

```bash
vi ~/security_auditor.py
```

```python
#!/usr/bin/env python3
"""PostgreSQL Security Auditor - find common role and permission issues."""

import os
import sys
from datetime import datetime
from contextlib import closing
import psycopg2

# Security thresholds
PASSWORD_EXPIRY_WARN_DAYS = 30  # Warn if password expires within N days


def get_connection():
    # TODO: Connect using environment variables
    pass


def find_superusers(cur) -> list[dict]:
    """Find all roles with superuser privilege."""
    # TODO: Query pg_roles WHERE rolsuper = true
    # TODO: Return list of dicts with: rolname, rolvaliduntil, rolcanlogin
    # TODO: Flag superusers that can also login (higher risk)
    return []


def find_no_password_expiry(cur) -> list[dict]:
    """Find login roles with no password expiration date."""
    # TODO: Query pg_roles WHERE rolcanlogin = true AND rolvaliduntil IS NULL
    # TODO: Exclude system roles (pg_*)
    return []


def find_expiring_passwords(cur) -> list[dict]:
    """Find roles with passwords expiring within threshold."""
    # TODO: Query pg_roles WHERE rolvaliduntil < now() + interval 'N days'
    # TODO: Include already-expired passwords
    return []


def find_no_login_roles(cur) -> list[dict]:
    """Find roles that can login but have NOLOGIN (potential misconfig)."""
    # TODO: Query pg_roles WHERE rolcanlogin = false
    # TODO: These might be group roles (expected) or misconfigured users
    return []


def check_pg_hba_trust(cur) -> list[str]:
    """Check for trust authentication in pg_hba.conf (PG 15+)."""
    # TODO: Query pg_hba_file_rules WHERE auth_method = 'trust'
    # TODO: Return list of warning strings
    # TODO: Wrap in try/except for older PG versions that lack this view
    return []


def print_report(findings: dict) -> None:
    """Print formatted security audit report."""
    # TODO: Print each category with findings count
    # TODO: Print details for each finding
    # TODO: Print overall risk assessment: HIGH/MEDIUM/LOW
    pass


def main() -> None:
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            findings = {
                'superusers': find_superusers(cur),
                'no_expiry': find_no_password_expiry(cur),
                'expiring': find_expiring_passwords(cur),
                'no_login': find_no_login_roles(cur),
                'trust_auth': check_pg_hba_trust(cur),
            }
        print_report(findings)
    finally:
        conn.close()


if __name__ == '__main__':
    main()
```

**Expected output:**

```
PostgreSQL Security Audit - 2026-06-09 14:30:00
==================================================

[HIGH] Superusers (2):
  postgres       - can login, no password expiry
  admin_user     - can login, expires 2027-01-01

[MEDIUM] Roles with no password expiry (3):
  postgres
  app_user
  monitor_user

[MEDIUM] Passwords expiring within 30 days (1):
  temp_user      - expires 2026-06-25 (16 days)

[LOW] No-login roles (2):
  readonly       - group role (expected)
  reporting      - group role (expected)

[HIGH] Trust authentication entries (1):
  local  all  all  trust  (line 84)

Risk Assessment: HIGH
  - 2 superusers with login capability
  - 1 trust authentication entry in pg_hba.conf
```

**Hints:**
- `pg_roles` has columns: rolname, rolsuper, rolcanlogin, rolvaliduntil, rolpassword
- `rolvaliduntil` is a timestamp - compare with `now() + interval '30 days'`
- `pg_hba_file_rules` is available in PostgreSQL 15+ - use `try/except` for older versions
- Risk assessment: HIGH if any trust auth or multiple superusers with login; MEDIUM if password issues; LOW otherwise

---

## Exercise 5: Automated VACUUM Advisor

**Scenario:** You need a script that analyzes `pg_stat_user_tables` and recommends which tables need VACUUM, with priority levels and ready-to-run commands.

**Starter code:**

```bash
vi ~/vacuum_advisor.py
```

```python
#!/usr/bin/env python3
"""Analyze table stats and recommend VACUUM operations with priority levels."""

import os
import sys
from datetime import datetime
from contextlib import closing
import psycopg2

# Thresholds
DEAD_PCT_LOW = 5       # Suggest VACUUM above this
DEAD_PCT_MED = 15      # Recommend VACUUM above this
DEAD_PCT_HIGH = 30     # Urgent VACUUM above this
MIN_DEAD_TUPLES = 1000 # Ignore tables with fewer dead tuples than this
DAYS_SINCE_VACUUM = 7  # Warn if no vacuum in N days


def get_connection():
    # TODO: Connect using environment variables
    pass


def analyze_tables(cur) -> list[dict]:
    """Query pg_stat_user_tables and analyze each table's vacuum needs."""
    # TODO: Query pg_stat_user_tables for:
    #   schemaname, relname, n_live_tup, n_dead_tup,
    #   last_vacuum, last_autovacuum, last_analyze, last_autoanalyze,
    #   vacuum_count, autovacuum_count
    # TODO: Calculate dead_pct for each table
    # TODO: Calculate days since last vacuum (any type)
    # TODO: Assign priority: HIGH (>30% or never vacuumed), MEDIUM (>15%), LOW (>5%)
    # TODO: Filter out tables below MIN_DEAD_TUPLES
    # TODO: Sort by priority then dead_pct descending
    return []


def generate_commands(recommendations: list[dict]) -> list[str]:
    """Generate VACUUM commands for recommended tables."""
    commands = []
    # TODO: For HIGH priority: VACUUM FULL ANALYZE schema.table;
    # TODO: For MEDIUM priority: VACUUM ANALYZE schema.table;
    # TODO: For LOW priority: VACUUM schema.table;
    # TODO: Add comments with table stats above each command
    return commands


def print_report(recommendations: list[dict]) -> None:
    """Print analysis report with recommendations."""
    # TODO: Group by priority (HIGH, MEDIUM, LOW)
    # TODO: For each table show: name, dead%, dead tuples, last vacuum, priority
    # TODO: Print total reclaimable estimate
    pass


def print_commands(commands: list[str]) -> None:
    """Print ready-to-run VACUUM commands."""
    # TODO: Print as a SQL script that can be piped to psql
    # TODO: Add SET statement_timeout at the top
    # TODO: Add timing comment
    pass


def main() -> None:
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            recommendations = analyze_tables(cur)

        if not recommendations:
            print('All tables are healthy - no VACUUM recommendations')
            sys.exit(0)

        print_report(recommendations)
        commands = generate_commands(recommendations)

        # If --sql flag, print just the commands (for piping to psql)
        if '--sql' in sys.argv:
            print_commands(commands)
        else:
            print('\nTo generate SQL commands, run with --sql flag')
            print(f'  python3 vacuum_advisor.py --sql | psql')

    finally:
        conn.close()


if __name__ == '__main__':
    main()
```

**Expected output:**

```
VACUUM Advisor Report - 2026-06-09 14:30:00
==================================================

[HIGH PRIORITY] (2 tables):
  public.sessions        45.2% dead (180000 tuples)  last vacuum: never
  public.temp_data       32.1% dead (95000 tuples)   last vacuum: 14 days ago

[MEDIUM PRIORITY] (3 tables):
  public.orders          18.5% dead (42000 tuples)   last vacuum: 3 days ago
  public.events          16.2% dead (28000 tuples)   last vacuum: 5 days ago
  public.audit_log       15.8% dead (22000 tuples)   last vacuum: 2 days ago

[LOW PRIORITY] (1 table):
  public.users           7.3% dead (3500 tuples)     last vacuum: 1 day ago

Summary: 6 tables need attention
  HIGH: 2 | MEDIUM: 3 | LOW: 1

To generate SQL commands, run with --sql flag
  python3 vacuum_advisor.py --sql | psql
```

**With --sql flag:**

```sql
-- VACUUM Advisor - Generated 2026-06-09 14:30:00
-- 6 tables recommended for VACUUM
SET statement_timeout = '2h';

-- HIGH: public.sessions (45.2% dead, 180000 dead tuples)
VACUUM FULL ANALYZE public.sessions;

-- HIGH: public.temp_data (32.1% dead, 95000 dead tuples)
VACUUM FULL ANALYZE public.temp_data;

-- MEDIUM: public.orders (18.5% dead, 42000 dead tuples)
VACUUM ANALYZE public.orders;

-- MEDIUM: public.events (16.2% dead, 28000 dead tuples)
VACUUM ANALYZE public.events;

-- MEDIUM: public.audit_log (15.8% dead, 22000 dead tuples)
VACUUM ANALYZE public.audit_log;

-- LOW: public.users (7.3% dead, 3500 dead tuples)
VACUUM public.users;
```

**Hints:**
- `last_vacuum` and `last_autovacuum` are timestamps - use `EXTRACT(EPOCH FROM age(now(), last_vacuum))/86400` for days
- `COALESCE(last_vacuum, last_autovacuum)` gives the most recent vacuum of either type
- `VACUUM FULL` rewrites the table and reclaims space but locks it exclusively - only recommend for HIGH priority
- Remember that `VACUUM FULL` cannot run inside a transaction - scripts executing it need `autocommit = True`
- The `--sql` output should be valid SQL that can be piped directly to `psql -f -`
