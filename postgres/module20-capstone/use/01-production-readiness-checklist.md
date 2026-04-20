# Use 01: Production Readiness Checklist

Score your PostgreSQL deployment against this 30-point production readiness checklist. Each item is worth 1 point. Aim for 28+ before going live.

---

## Instructions

1. Run each check on your primary server
2. Mark PASS or FAIL
3. For any FAIL, write a remediation plan
4. Target: 28/30 minimum for production readiness

---

## A. Configuration (6 points)

### A1. Data checksums enabled

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "Data page checksum"
```

PASS if: `Data page checksum version: 1`
FAIL if: `Data page checksum version: 0`

```bash
exit
```

**Why it matters**: Without checksums, silent data corruption goes undetected until it reaches backups. By then, all your copies are corrupt.

Score: ___

---

### A2. WAL level is replica or logical

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW wal_level;"
```

PASS if: `replica` or `logical`
FAIL if: `minimal`

Score: ___

---

### A3. shared_buffers is at least 25% of RAM

```bash
/usr/pgsql-16/bin/psql -c "SHOW shared_buffers;"
```

```bash
free -h
```

PASS if: shared_buffers is approximately 25% of total RAM
FAIL if: shared_buffers is the default 128MB

Score: ___

---

### A4. random_page_cost is tuned for SSD

```bash
/usr/pgsql-16/bin/psql -c "SHOW random_page_cost;"
```

PASS if: `1.1` to `1.5` (SSD storage)
FAIL if: `4.0` (default, assumes spinning disk)

Score: ___

---

### A5. max_connections is reasonable

```bash
/usr/pgsql-16/bin/psql -c "SHOW max_connections;"
```

PASS if: 100-500 (with connection pooler) or matches your actual need
FAIL if: Default 100 (too low) or 1000+ without pooler (too high)

Score: ___

---

### A6. timezone is UTC

```bash
/usr/pgsql-16/bin/psql -c "SHOW timezone;"
```

PASS if: `UTC`
FAIL if: Any local timezone

```bash
exit
```

Score: ___

---

## B. Security (6 points)

### B1. SSL is enabled and enforced

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW ssl;"
```

```bash
grep -c "hostnossl.*reject" /opt/pgsql/data/pg_hba.conf
```

PASS if: ssl=on AND hostnossl reject rule exists
FAIL if: ssl=off OR no reject rule for unencrypted connections

Score: ___

---

### B2. Password encryption is scram-sha-256

```bash
/usr/pgsql-16/bin/psql -c "SHOW password_encryption;"
```

PASS if: `scram-sha-256`
FAIL if: `md5`

Score: ___

---

### B3. No trust authentication for remote connections

```bash
grep "trust" /opt/pgsql/data/pg_hba.conf
```

Look at the output. Ignore any lines starting with `#` (those are comments). Only active lines matter.

PASS if: No output OR only `local ... trust` for postgres peer auth
FAIL if: Any `host ... trust` line

Score: ___

---

### B4. Minimal superuser roles

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname FROM pg_roles WHERE rolsuper = true;"
```

PASS if: Only postgres and repmgr (or equivalent HA tool)
FAIL if: Application roles have superuser

Score: ___

---

### B5. Connection and disconnection logging enabled

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_connections;"
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_disconnections;"
```

PASS if: Both are `on`
FAIL if: Either is `off`

Score: ___

---

### B6. DDL statements are logged

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_statement;"
```

PASS if: `ddl` or `all`
FAIL if: `none` or `mod`

```bash
exit
```

Score: ___

---

## C. Backup and Recovery (6 points)

### C1. Backups exist and are recent

```bash
su - postgres
```

```bash
pgbackrest --stanza=prod info
```

PASS if: At least one full backup within the last 7 days
FAIL if: No backups or oldest is more than 7 days

Score: ___

---

### C2. WAL archiving is working

```bash
/usr/pgsql-16/bin/psql -c "SELECT archived_count, failed_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;"
```

PASS if: archived_count > 0 AND failed_count = 0 AND last_archived_time is recent
FAIL if: failed_count > 0 or no archives

Score: ___

---

### C3. Backup encryption is enabled

```bash
pgbackrest --stanza=prod info
```

PASS if: Output shows `cipher: aes-256-cbc`
FAIL if: No cipher line

Score: ___

---

### C4. PITR has been tested

Ask yourself: Have you successfully restored to a specific timestamp in the last 30 days?

PASS if: Yes, documented with date and result
FAIL if: Never tested or not tested recently

Score: ___

---

### C5. Backup monitoring exists

```bash
ls /opt/pgsql/scripts/check-backup-age.sh
```

```bash
/opt/pgsql/scripts/check-backup-age.sh
```

PASS if: Script exists and returns OK
FAIL if: No monitoring script

Score: ___

---

### C6. Backup schedule is automated

```bash
crontab -u postgres -l
```

PASS if: Cron entries for full and differential backups
FAIL if: No automated backup schedule

```bash
exit
```

Score: ___

---

## D. High Availability (6 points)

### D1. Streaming replication is active

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming';"
```

PASS if: count >= 1
FAIL if: count = 0

Score: ___

---

### D2. Replication slot is active

```bash
/usr/pgsql-16/bin/psql -c "SELECT slot_name, active FROM pg_replication_slots;"
```

PASS if: At least one active slot
FAIL if: All slots inactive or no slots

Score: ___

---

### D3. Synchronous replication configured

```bash
/usr/pgsql-16/bin/psql -c "SHOW synchronous_standby_names;"
```

PASS if: Not empty (at least one standby listed)
FAIL if: Empty string (async only)

Score: ___

---

### D4. Automatic failover is configured

```bash
systemctl is-active repmgrd
```

PASS if: `active`
FAIL if: `inactive` or service does not exist

Score: ___

---

### D5. Failover has been tested

Ask yourself: Have you tested a failover in the last 30 days?

PASS if: Yes, documented with date and RTO
FAIL if: Never tested

Score: ___

---

### D6. Connection pooler is running

```bash
systemctl is-active pgbouncer
```

PASS if: `active`
FAIL if: `inactive` or not installed

```bash
exit
```

Score: ___

---

## E. Monitoring and Operations (6 points)

### E1. pg_stat_statements is enabled

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM pg_stat_statements;"
```

PASS if: Returns a count (extension is loaded)
FAIL if: Error (extension not installed)

Score: ___

---

### E2. Slow query logging is enabled

```bash
/usr/pgsql-16/bin/psql -c "SHOW log_min_duration_statement;"
```

PASS if: A numeric value (e.g., 1000 for 1 second)
FAIL if: `-1` (disabled)

Score: ___

---

### E3. Autovacuum is tuned (not defaults)

```bash
/usr/pgsql-16/bin/psql -c "SHOW autovacuum_vacuum_scale_factor;"
```

PASS if: 0.05 or lower (production tuning)
FAIL if: 0.2 (default, too lazy for production)

Score: ___

---

### E4. Monitoring stack is running

```bash
systemctl is-active postgres_exporter
```

```bash
systemctl is-active prometheus
```

PASS if: Both active
FAIL if: Either inactive

Score: ___

---

### E5. Alert rules are configured

```bash
curl -s http://localhost:9090/api/v1/rules > /tmp/prom-rules.json
```

```bash
python3 -c "
import json
data = json.load(open('/tmp/prom-rules.json'))
print(f\"Rules: {len(data['data']['groups'][0]['rules'])}\")
"
```

PASS if: At least 5 rules
FAIL if: 0 rules or Prometheus not running

Score: ___

---

### E6. Log rotation is configured

```bash
ls /etc/logrotate.d/postgresql*
```

PASS if: Logrotate config exists
FAIL if: No logrotate config

```bash
exit
```

Score: ___

---

## Scoring

| Category | Score |
|----------|-------|
| A. Configuration | ___/6 |
| B. Security | ___/6 |
| C. Backup and Recovery | ___/6 |
| D. High Availability | ___/6 |
| E. Monitoring and Operations | ___/6 |
| **Total** | **___/30** |

### Rating

- **28-30**: Production ready. Ship it.
- **24-27**: Almost there. Fix the gaps before go-live.
- **18-23**: Significant gaps. Do not go live until addressed.
- **Below 18**: Major rework needed. Review Build guides 01-05.

---

## Remediation Plan

For each FAIL item, write:

1. **Item**: Which check failed
2. **Risk**: What could go wrong
3. **Fix**: Exact steps to remediate
4. **ETA**: How long the fix takes
5. **Owner**: Who is responsible

Example:

```
Item: A1 - Data checksums
Risk: Silent data corruption undetected
Fix: Requires initdb with --data-checksums (destructive)
     Or pg_checksums --enable on stopped cluster (PG 16+)
ETA: 2 hours (requires maintenance window)
Owner: [YOUR NAME]
```
