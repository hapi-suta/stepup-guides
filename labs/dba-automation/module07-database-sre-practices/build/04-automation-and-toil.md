# BUILD 04: Eliminating Toil - Automation That Matters

**Module 07: Database SRE Practices**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to identify, measure, and eliminate toil - the repetitive manual work that prevents you from doing engineering work that actually improves reliability.

---

## What is Toil?

Toil is work that is:

- **Manual** - a human has to do it
- **Repetitive** - you do it regularly
- **Automatable** - a machine could do it
- **Tactical** - interrupt-driven, reactive
- **No enduring value** - does not permanently improve the system
- **Scales linearly** - more databases = more toil

**DBA Analogy:** Think about your week. How much time do you spend:
- Creating users and granting permissions (manual, repetitive)
- Running backup verification scripts (manual, automatable)
- Checking disk space across servers (repetitive, automatable)
- Rotating SSL certificates (manual, recurring)
- Generating weekly capacity reports (repetitive, automatable)

All of that is toil. Every hour you spend on toil is an hour you are NOT spending on building monitoring, improving automation, or designing better architecture.

---

## Step 1: The SRE Toil Budget

Google's SRE book recommends that teams spend no more than 50% of their time on toil. The other 50% should be spent on engineering work - building systems that reduce future toil.

| Time Allocation | Category | Examples |
|----------------|----------|---------|
| <= 50% | **Toil** | Manual deployments, user provisioning, backup checks |
| >= 50% | **Engineering** | Building monitoring, writing automation, improving architecture |

If you are spending 80% of your time on toil, you have no time to automate - and the toil will only grow as you add more databases.

**DBA Analogy:** If you spend 6 hours a day manually checking replication lag on 50 servers, you never have time to build the monitoring dashboard that checks it automatically. The toil traps you.

---

## Step 2: Measuring Toil

Before you can reduce toil, you need to measure it. Track your tasks for one week:

```bash
mkdir -p ~/dba-labs/sre-practice/toil
vi ~/dba-labs/sre-practice/toil/toil-tracker.md
```

```markdown
# Toil Tracker - Week of [DATE]

## Daily Log

### Monday
| Time | Duration | Task | Toil? | Automatable? |
|------|----------|------|-------|-------------|
| 09:00 | 15 min | Check backup status on all servers | Yes | Yes |
| 09:15 | 30 min | Create 3 new database users for dev team | Yes | Yes |
| 10:00 | 45 min | Investigate slow query report | No | No |
| 11:00 | 20 min | Check disk space on all 15 servers | Yes | Yes |
| 14:00 | 1 hour | Deploy schema migration to staging | Yes | Partially |
| 15:00 | 30 min | Rotate expiring SSL certificate | Yes | Yes |

### Summary
| Metric | Value |
|--------|-------|
| Total hours worked | 8 |
| Hours on toil | 4.5 |
| Hours on engineering | 3.5 |
| Toil percentage | 56% |
| Top toil task | User provisioning (30 min/day) |
```

### Prioritizing What to Automate

Score each toil task on two dimensions:

| Task | Time per Occurrence | Frequency | Annual Hours | Automation Effort | Priority |
|------|-------------------|-----------|-------------|-------------------|----------|
| Backup verification | 15 min | Daily | 65 hrs | 8 hrs (script) | HIGH |
| User provisioning | 30 min | 3x/week | 78 hrs | 16 hrs (self-service) | HIGH |
| Disk space check | 20 min | Daily | 87 hrs | 4 hrs (monitoring) | HIGH |
| SSL cert rotation | 30 min | Monthly | 6 hrs | 8 hrs (script) | LOW |
| Capacity report | 2 hrs | Weekly | 104 hrs | 20 hrs (dashboard) | MEDIUM |

**Rule of thumb:** If automation takes less time than 6 months of manual work, automate it.

---

## Step 3: Automation 1 - User Provisioning

One of the most common DBA toil tasks: creating database users, setting permissions, and managing access.

```bash
vi ~/dba-labs/sre-practice/toil/provision-user.py
```

```python
#!/usr/bin/env python3
"""
Database User Provisioning Tool
Eliminates manual CREATE ROLE + GRANT commands.

Usage:
    python3 provision-user.py --username app_reader \
        --database production \
        --role readonly \
        --requestor "dev-team-lead"
"""

import argparse
import logging
import sys
from datetime import datetime, timezone

import psycopg2  # type: ignore
from psycopg2 import sql  # type: ignore

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(os.path.expanduser("~/pg-user-provisioning.log")),
    ],
)
logger = logging.getLogger(__name__)

# Role templates - predefined permission sets
ROLE_TEMPLATES: dict[str, dict[str, list[str]]] = {
    "readonly": {
        "database_privs": ["CONNECT"],
        "schema_privs": ["USAGE"],
        "table_privs": ["SELECT"],
        "description": "Read-only access to all tables in public schema",
    },
    "readwrite": {
        "database_privs": ["CONNECT"],
        "schema_privs": ["USAGE", "CREATE"],
        "table_privs": ["SELECT", "INSERT", "UPDATE", "DELETE"],
        "description": "Read-write access to all tables in public schema",
    },
    "admin": {
        "database_privs": ["ALL"],
        "schema_privs": ["ALL"],
        "table_privs": ["ALL"],
        "description": "Full access (use sparingly)",
    },
}


def provision_user(
    host: str,
    port: int,
    admin_user: str,
    database: str,
    username: str,
    role: str,
    requestor: str,
) -> bool:
    """Create a database user with predefined role permissions."""

    if role not in ROLE_TEMPLATES:
        logger.error(f"Unknown role: {role}. Valid roles: {list(ROLE_TEMPLATES.keys())}")
        return False

    template = ROLE_TEMPLATES[role]
    logger.info(f"Provisioning user '{username}' with role '{role}' on '{database}'")
    logger.info(f"Requested by: {requestor}")

    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            user=admin_user,
            dbname=database,
        )
        conn.autocommit = True
        cursor = conn.cursor()

        # Check if user already exists
        cursor.execute(
            "SELECT 1 FROM pg_roles WHERE rolname = %s",
            (username,),
        )
        user_exists = cursor.fetchone() is not None

        if not user_exists:
            # Generate a random password
            cursor.execute("SELECT md5(random()::text || clock_timestamp()::text)")
            password = cursor.fetchone()[0][:16]

            # Create the user
            cursor.execute(
                sql.SQL("CREATE ROLE {} WITH LOGIN PASSWORD %s").format(
                    sql.Identifier(username)
                ),
                (password,),
            )
            logger.info(f"Created user '{username}'")
        else:
            logger.info(f"User '{username}' already exists - updating permissions")
            password = None

        # Grant database privileges
        for priv in template["database_privs"]:
            cursor.execute(
                sql.SQL("GRANT {} ON DATABASE {} TO {}").format(
                    sql.SQL(priv),
                    sql.Identifier(database),
                    sql.Identifier(username),
                )
            )

        # Grant schema privileges
        for priv in template["schema_privs"]:
            cursor.execute(
                sql.SQL("GRANT {} ON SCHEMA public TO {}").format(
                    sql.SQL(priv),
                    sql.Identifier(username),
                )
            )

        # Grant table privileges
        for priv in template["table_privs"]:
            cursor.execute(
                sql.SQL("GRANT {} ON ALL TABLES IN SCHEMA public TO {}").format(
                    sql.SQL(priv),
                    sql.Identifier(username),
                )
            )
            # Also set default privileges for future tables
            cursor.execute(
                sql.SQL(
                    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT {} ON TABLES TO {}"
                ).format(
                    sql.SQL(priv),
                    sql.Identifier(username),
                )
            )

        # Add a comment for audit trail
        cursor.execute(
            sql.SQL("COMMENT ON ROLE {} IS %s").format(sql.Identifier(username)),
            (f"Role: {role} | Provisioned: {datetime.now(timezone.utc).isoformat()} | Requestor: {requestor}",),
        )

        cursor.close()
        conn.close()

        logger.info(f"Successfully provisioned '{username}' with '{role}' role on '{database}'")
        if password:
            logger.info(f"Initial password: {password} (user should change immediately)")

        return True

    except psycopg2.Error as e:
        logger.error(f"Database error: {e}")
        return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Provision PostgreSQL database users")
    parser.add_argument("--host", default="localhost", help="Database host")
    parser.add_argument("--port", type=int, default=5432, help="Database port")
    parser.add_argument("--admin-user", default="postgres", help="Admin user for provisioning")
    parser.add_argument("--database", required=True, help="Target database")
    parser.add_argument("--username", required=True, help="Username to create")
    parser.add_argument("--role", required=True, choices=list(ROLE_TEMPLATES.keys()), help="Role template")
    parser.add_argument("--requestor", required=True, help="Who requested this user")

    args = parser.parse_args()

    success = provision_user(
        host=args.host,
        port=args.port,
        admin_user=args.admin_user,
        database=args.database,
        username=args.username,
        role=args.role,
        requestor=args.requestor,
    )

    sys.exit(0 if success else 1)
```

**Usage:**

```bash
python3 provision-user.py \
    --database production \
    --username new_app_reader \
    --role readonly \
    --requestor "alice@company.com"
```

**Time savings:** 30 minutes manual -> 30 seconds automated. Over a year with 3 requests per week: 78 hours saved.

---

## Step 4: Automation 2 - Backup Verification

Backups are worthless if they cannot be restored. Automate the verification.

```bash
vi ~/dba-labs/sre-practice/toil/verify-backup.py
```

```python
#!/usr/bin/env python3
"""
Automated Backup Verification
Tests that the latest backup can be restored and queried.

Usage:
    python3 verify-backup.py --backup-dir /var/lib/pgsql/backups \
        --restore-dir /tmp/pg-restore-test
"""

import argparse
import logging
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def find_latest_backup(backup_dir: str) -> str | None:
    """Find the most recent backup directory."""
    backup_path = Path(backup_dir)
    if not backup_path.exists():
        logger.error(f"Backup directory does not exist: {backup_dir}")
        return None

    backups = sorted(backup_path.iterdir(), key=os.path.getmtime, reverse=True)
    for backup in backups:
        if backup.is_dir() and (backup / "PG_VERSION").exists():
            return str(backup)

    logger.error("No valid backup found")
    return None


def restore_and_verify(backup_path: str, restore_dir: str, pg_port: int) -> dict[str, bool | str]:
    """Restore a backup and run verification queries."""
    results: dict[str, bool | str] = {
        "backup_found": True,
        "backup_path": backup_path,
        "restore_success": False,
        "startup_success": False,
        "query_success": False,
        "table_count": "0",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    # Clean restore directory
    if os.path.exists(restore_dir):
        shutil.rmtree(restore_dir)

    # Copy backup to restore directory
    logger.info(f"Copying backup from {backup_path} to {restore_dir}")
    try:
        shutil.copytree(backup_path, restore_dir)
        results["restore_success"] = True
    except OSError as e:
        logger.error(f"Failed to copy backup: {e}")
        return results

    # Remove recovery.signal / standby.signal if present
    for signal_file in ["recovery.signal", "standby.signal"]:
        signal_path = os.path.join(restore_dir, signal_file)
        if os.path.exists(signal_path):
            os.remove(signal_path)

    # Update postgresql.conf for test instance
    conf_path = os.path.join(restore_dir, "postgresql.conf")
    with open(conf_path, "a") as f:
        f.write(f"\nport = {pg_port}\n")
        f.write("unix_socket_directories = '/tmp'\n")
        f.write("archive_mode = off\n")

    # Start the restored instance
    logger.info(f"Starting restored instance on port {pg_port}")
    try:
        subprocess.run(
            ["pg_ctl", "-D", restore_dir, "-l", f"{restore_dir}/startup.log", "start"],
            check=True,
            capture_output=True,
            text=True,
        )
        results["startup_success"] = True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to start restored instance: {e.stderr}")
        return results

    # Run verification queries
    try:
        result = subprocess.run(
            ["psql", "-p", str(pg_port), "-h", "/tmp", "-U", "postgres", "-d", "postgres",
             "-tAc", "SELECT count(*) FROM pg_tables WHERE schemaname = 'public';"],
            check=True,
            capture_output=True,
            text=True,
        )
        results["query_success"] = True
        results["table_count"] = result.stdout.strip()
        logger.info(f"Verification query succeeded. Public tables: {results['table_count']}")
    except subprocess.CalledProcessError as e:
        logger.error(f"Verification query failed: {e.stderr}")

    # Stop the test instance
    subprocess.run(
        ["pg_ctl", "-D", restore_dir, "stop"],
        capture_output=True,
    )

    # Clean up
    shutil.rmtree(restore_dir, ignore_errors=True)

    return results


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify PostgreSQL backup restorability")
    parser.add_argument("--backup-dir", required=True, help="Directory containing backups")
    parser.add_argument("--restore-dir", default="/tmp/pg-restore-test", help="Temp directory for restore")
    parser.add_argument("--port", type=int, default=5555, help="Port for test instance")

    args = parser.parse_args()

    backup_path = find_latest_backup(args.backup_dir)
    if not backup_path:
        logger.error("FAIL: No backup found")
        sys.exit(1)

    results = restore_and_verify(backup_path, args.restore_dir, args.port)

    # Print summary
    logger.info("=" * 50)
    logger.info("BACKUP VERIFICATION RESULTS")
    logger.info("=" * 50)
    for key, value in results.items():
        status = "PASS" if value and value != "0" else "FAIL"
        if key in ("backup_path", "timestamp", "table_count"):
            logger.info(f"  {key}: {value}")
        else:
            logger.info(f"  {key}: {status}")

    all_passed = all([
        results["restore_success"],
        results["startup_success"],
        results["query_success"],
    ])

    if all_passed:
        logger.info("OVERALL: PASS - Backup is restorable and queryable")
    else:
        logger.error("OVERALL: FAIL - Backup verification failed")

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
```

**Schedule with cron:**

```bash
# Run backup verification daily at 6 AM
0 6 * * * /usr/bin/python3 /opt/dba-scripts/verify-backup.py --backup-dir /var/lib/pgsql/backups >> /var/log/backup-verify.log 2>&1
```

---

## Step 5: Automation 3 - Capacity Reporting

```bash
vi ~/dba-labs/sre-practice/toil/capacity-report.py
```

```python
#!/usr/bin/env python3
"""
Weekly Capacity Report Generator
Collects disk usage, growth trends, and connection stats.

Usage:
    python3 capacity-report.py --host localhost --port 5432
"""

import argparse
import sys
from datetime import datetime, timezone

import psycopg2  # type: ignore


def generate_report(host: str, port: int, user: str) -> str:
    """Generate a capacity report for a PostgreSQL instance."""

    conn = psycopg2.connect(host=host, port=port, user=user, dbname="postgres")
    cursor = conn.cursor()

    report_lines: list[str] = []
    report_lines.append("=" * 60)
    report_lines.append(f"POSTGRESQL CAPACITY REPORT - {datetime.now(timezone.utc).strftime('%Y-%m-%d')}")
    report_lines.append(f"Host: {host}:{port}")
    report_lines.append("=" * 60)

    # Database sizes
    cursor.execute("""
        SELECT
            datname,
            pg_size_pretty(pg_database_size(datname)) AS size,
            pg_database_size(datname) AS size_bytes
        FROM pg_database
        WHERE datname NOT LIKE 'template%'
        ORDER BY pg_database_size(datname) DESC;
    """)
    report_lines.append("\n--- DATABASE SIZES ---")
    report_lines.append(f"{'Database':<30} {'Size':>15}")
    report_lines.append("-" * 45)
    total_bytes = 0
    for row in cursor.fetchall():
        report_lines.append(f"{row[0]:<30} {row[1]:>15}")
        total_bytes += row[2]
    report_lines.append("-" * 45)
    report_lines.append(f"{'TOTAL':<30} {_pretty_size(total_bytes):>15}")

    # Top tables by size
    cursor.execute("""
        SELECT
            schemaname || '.' || relname AS table_name,
            pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
            pg_size_pretty(pg_relation_size(relid)) AS table_size,
            pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_size,
            n_live_tup AS live_rows
        FROM pg_stat_user_tables
        ORDER BY pg_total_relation_size(relid) DESC
        LIMIT 15;
    """)
    report_lines.append("\n--- TOP 15 TABLES BY SIZE ---")
    report_lines.append(f"{'Table':<40} {'Total':>12} {'Data':>12} {'Indexes':>12} {'Rows':>15}")
    report_lines.append("-" * 91)
    for row in cursor.fetchall():
        report_lines.append(f"{row[0]:<40} {row[1]:>12} {row[2]:>12} {row[3]:>12} {row[4]:>15,}")

    # Connection stats
    cursor.execute("""
        SELECT
            count(*) AS total,
            count(*) FILTER (WHERE state = 'active') AS active,
            count(*) FILTER (WHERE state = 'idle') AS idle,
            count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_txn,
            (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn
        FROM pg_stat_activity;
    """)
    row = cursor.fetchone()
    report_lines.append("\n--- CONNECTION STATS ---")
    report_lines.append(f"Total: {row[0]} / {row[4]} ({round(row[0]/row[4]*100, 1)}%)")
    report_lines.append(f"Active: {row[1]} | Idle: {row[2]} | Idle-in-Txn: {row[3]}")

    # Cache hit ratio
    cursor.execute("""
        SELECT
            round(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit + blks_read), 0), 2) AS hit_ratio
        FROM pg_stat_database;
    """)
    row = cursor.fetchone()
    report_lines.append(f"\n--- PERFORMANCE ---")
    report_lines.append(f"Cache Hit Ratio: {row[0]}%")

    # Bloat check
    cursor.execute("""
        SELECT
            schemaname || '.' || relname AS table_name,
            n_dead_tup,
            n_live_tup,
            round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 1) AS dead_pct,
            last_autovacuum
        FROM pg_stat_user_tables
        WHERE n_dead_tup > 10000
        ORDER BY n_dead_tup DESC
        LIMIT 10;
    """)
    rows = cursor.fetchall()
    if rows:
        report_lines.append("\n--- BLOAT WARNING (tables with > 10K dead tuples) ---")
        report_lines.append(f"{'Table':<40} {'Dead Tuples':>15} {'Dead %':>10} {'Last Vacuum':>25}")
        report_lines.append("-" * 90)
        for row in rows:
            report_lines.append(f"{row[0]:<40} {row[1]:>15,} {row[3] or 0:>9.1f}% {str(row[4] or 'Never'):>25}")

    cursor.close()
    conn.close()

    report_lines.append("\n" + "=" * 60)
    report_lines.append("END OF REPORT")

    return "\n".join(report_lines)


def _pretty_size(bytes_val: int) -> str:
    """Convert bytes to human-readable size."""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(bytes_val) < 1024:
            return f"{bytes_val:.1f} {unit}"
        bytes_val /= 1024
    return f"{bytes_val:.1f} PB"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate PostgreSQL capacity report")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--user", default="postgres")
    args = parser.parse_args()

    report = generate_report(args.host, args.port, args.user)
    print(report)
```

**Schedule with cron:**

```bash
# Weekly capacity report every Monday at 8 AM
0 8 * * 1 /usr/bin/python3 /opt/dba-scripts/capacity-report.py --host localhost > /var/log/capacity-report-$(date +\%Y\%m\%d).txt 2>&1
```

---

## Step 6: Building Self-Service (with Guardrails)

The ultimate toil reduction is letting developers do things themselves - with guardrails that prevent mistakes.

### Guardrails for Self-Service Database Provisioning

| Guardrail | Implementation |
|-----------|---------------|
| Size limits | Max database size of 100GB for dev environments |
| Naming conventions | Database names must match pattern: `{team}_{service}_{env}` |
| User permissions | Self-service users get `readwrite` role, never `admin` |
| Expiration | Dev databases auto-drop after 90 days if not renewed |
| Audit trail | Every provisioning action is logged with requestor and timestamp |
| No production access | Self-service only works for dev/staging environments |

---

## Step 7: Operational Reviews

SRE teams conduct regular operational reviews to track reliability metrics and toil trends.

### Weekly Review Checklist

```markdown
## Weekly Operational Review

### SLO Status
- [ ] Availability: __% (SLO: 99.9%)
- [ ] Error budget remaining: __ minutes
- [ ] Latency p95: __ms (SLO: < 100ms)
- [ ] Replication lag max: __s (SLO: < 5s)

### Incidents This Week
- [ ] Number of SEV1/SEV2 incidents: __
- [ ] MTTR for this week: __ minutes
- [ ] Outstanding action items from PIRs: __

### Toil This Week
- [ ] Hours spent on toil: __
- [ ] Toil percentage: __% (target: <= 50%)
- [ ] New automation completed: __
- [ ] Toil reduction from new automation: __ hours/week

### Capacity
- [ ] Disk usage trend: growing/stable/shrinking
- [ ] Projected disk full date: __
- [ ] Connection utilization peak: __%
```

---

## Step 8: Capacity Planning

Use historical data to predict when you will run out of resources:

```sql
-- Simple growth rate calculation
-- Run daily, store results, project forward

SELECT
    datname,
    pg_database_size(datname) AS current_size_bytes,
    pg_size_pretty(pg_database_size(datname)) AS current_size,
    -- If you have historical data, calculate growth rate:
    -- (current_size - size_30_days_ago) / 30 = daily growth
    -- current_size / daily_growth = days until [threshold]
    now() AS measured_at
FROM pg_database
WHERE datname NOT LIKE 'template%'
ORDER BY pg_database_size(datname) DESC;
```

Store daily measurements and trend:

```sql
CREATE TABLE IF NOT EXISTS capacity_history (
    measured_at DATE DEFAULT CURRENT_DATE,
    database_name TEXT,
    size_bytes BIGINT,
    PRIMARY KEY (measured_at, database_name)
);

-- Insert daily measurement
INSERT INTO capacity_history (database_name, size_bytes)
SELECT datname, pg_database_size(datname)
FROM pg_database
WHERE datname NOT LIKE 'template%'
ON CONFLICT (measured_at, database_name)
DO UPDATE SET size_bytes = EXCLUDED.size_bytes;

-- Calculate growth rate and project
SELECT
    database_name,
    pg_size_pretty(latest.size_bytes) AS current_size,
    pg_size_pretty(latest.size_bytes - oldest.size_bytes) AS growth_30d,
    round((latest.size_bytes - oldest.size_bytes)::numeric / 30 / 1024 / 1024, 1) AS daily_growth_mb,
    CASE
        WHEN latest.size_bytes > oldest.size_bytes THEN
            round(
                (100::bigint * 1024 * 1024 * 1024 - latest.size_bytes)::numeric /
                NULLIF((latest.size_bytes - oldest.size_bytes) / 30, 0),
                0
            )
        ELSE NULL
    END AS days_until_100gb
FROM
    (SELECT database_name, size_bytes FROM capacity_history WHERE measured_at = CURRENT_DATE) latest
JOIN
    (SELECT database_name, size_bytes FROM capacity_history WHERE measured_at = CURRENT_DATE - 30) oldest
USING (database_name);
```

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Toil | Manual, repetitive, automatable work with no enduring value |
| Toil budget | SRE principle: spend <= 50% on toil, >= 50% on engineering |
| Measuring toil | Track tasks for a week - categorize as toil or engineering |
| Prioritization | Automate tasks with highest (frequency x time per occurrence) |
| User provisioning | Python script with role templates replaces manual CREATE ROLE + GRANT |
| Backup verification | Automated restore + query test replaces manual spot-checks |
| Capacity reporting | Automated weekly reports replace manual df + psql checks |
| Self-service | Let developers provision their own dev databases (with guardrails) |
| Operational reviews | Weekly check on SLOs, incidents, toil, and capacity |
| Capacity planning | Store daily measurements, calculate growth rate, project forward |

---

**This completes Module 07: Database SRE Practices.** You now have the tools to measure reliability, respond to incidents, test resilience, and eliminate toil.
