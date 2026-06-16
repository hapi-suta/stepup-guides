#!/usr/bin/env python3
"""
ansible_drift_check.py - Compare running PostgreSQL config against expected baseline.

Queries pg_settings for current values and compares them to a defined
expected-values dictionary. Also checks pg_hba_file_rules (PG 17+) for
expected auth entries.

Flags any mismatches as DRIFT. Outputs a clean expected vs actual report.

Usage:
    python3 ansible_drift_check.py
    python3 ansible_drift_check.py --host 172.31.19.86
    python3 ansible_drift_check.py --strict   # non-zero exit if any drift found
"""

import argparse
import sys
from datetime import datetime

import psycopg2
from psycopg2.extras import RealDictCursor

DEFAULT_HOST = "172.31.19.86"
DEFAULT_PORT = 5432
DEFAULT_DB   = "quantdb"
DEFAULT_USER = "quant_readonly"
DEFAULT_PASS = "quant_readonly_2026"

# Expected PostgreSQL GUC values for the Voleon lab configuration.
# Values are strings because pg_settings returns text. Use None to skip assertion.
EXPECTED_SETTINGS: dict[str, str] = {
    "wal_level":                "replica",
    "max_connections":          "200",
    "shared_buffers":           "4GB",
    "effective_cache_size":     "12GB",
    "maintenance_work_mem":     "1GB",
    "checkpoint_completion_target": "0.9",
    "wal_buffers":              "64MB",
    "default_statistics_target": "100",
    "random_page_cost":         "1.1",
    "effective_io_concurrency": "200",
    "max_worker_processes":     "8",
    "max_parallel_workers_per_gather": "4",
    "max_parallel_workers":     "8",
    "max_wal_size":             "4GB",
    "min_wal_size":             "1GB",
    "log_min_duration_statement": "1000",
    "log_checkpoints":          "on",
    "log_connections":          "off",
    "log_disconnections":       "off",
    "log_lock_waits":           "on",
    "log_temp_files":           "0",
    "track_activity_query_size": "4096",
    "shared_preload_libraries": "pg_stat_statements,auto_explain",
    "hot_standby":              "on",
    "hot_standby_feedback":     "on",
    "archive_mode":             "on",
    "max_replication_slots":    "10",
    "max_wal_senders":          "10",
    "wal_keep_size":            "1GB",
    "synchronous_commit":       "on",
}

# Expected pg_hba_file_rules entries (PG 17+ view).
# Each dict is checked as a subset match against actual rows.
EXPECTED_HBA_RULES: list[dict] = [
    {"type": "local", "database": ["all"], "user_name": ["all"], "auth_method": "peer"},
    {"type": "host",  "database": ["all"], "user_name": ["all"], "auth_method": "scram-sha-256"},
    {"type": "host",  "database": ["replication"], "auth_method": "scram-sha-256"},
]


def connect(host, port, dbname, user, password):
    try:
        return psycopg2.connect(
            host=host, port=port, dbname=dbname,
            user=user, password=password, connect_timeout=5
        )
    except psycopg2.OperationalError as exc:
        print(f"ERROR: Cannot connect - {exc}")
        sys.exit(1)


def get_pg_version(cur) -> int:
    cur.execute("SELECT current_setting('server_version_num')::int AS v")
    return cur.fetchone()["v"]


def get_settings(cur) -> dict[str, str]:
    cur.execute("""
        SELECT name, setting, unit
        FROM   pg_settings
        WHERE  name = ANY(%s)
    """, (list(EXPECTED_SETTINGS.keys()),))
    result = {}
    for r in cur.fetchall():
        # Normalize by appending unit where present for comparison
        unit = r["unit"] or ""
        result[r["name"]] = f"{r['setting']}{unit}"
    return result


def normalize(value: str) -> str:
    """Lower-case and strip for comparison."""
    return value.strip().lower() if value else ""


def check_settings(actual: dict[str, str]) -> tuple[list, list]:
    drifted = []
    matched = []
    for key, expected_val in EXPECTED_SETTINGS.items():
        actual_val = actual.get(key, "<not found>")
        if normalize(actual_val) != normalize(expected_val):
            drifted.append((key, expected_val, actual_val))
        else:
            matched.append(key)
    return drifted, matched


def check_hba_rules(cur, pg_version: int) -> list[str]:
    issues = []
    if pg_version < 170000:
        issues.append(f"pg_hba_file_rules view not available (PG version < 17, got {pg_version})")
        return issues

    try:
        cur.execute("""
            SELECT rule_number, type, database, user_name, address, auth_method
            FROM   pg_hba_file_rules
            ORDER  BY rule_number
        """)
        actual_rules = cur.fetchall()
    except psycopg2.Error as exc:
        issues.append(f"Cannot query pg_hba_file_rules: {exc}")
        return issues

    for expected in EXPECTED_HBA_RULES:
        found = False
        for r in actual_rules:
            match = True
            for k, v in expected.items():
                actual_val = r.get(k)
                if isinstance(v, list):
                    if actual_val != v:
                        match = False
                        break
                else:
                    if str(actual_val).lower() != str(v).lower():
                        match = False
                        break
            if match:
                found = True
                break
        if not found:
            issues.append(f"Missing HBA rule: {expected}")

    return issues


def print_drift_report(drifted, matched, hba_issues, pg_version):
    total   = len(EXPECTED_SETTINGS)
    n_drift = len(drifted)
    n_ok    = len(matched)

    print(f"\n  GUC Settings  ({n_ok}/{total} match, {n_drift} drift)")
    if drifted:
        fmt = "  {:<42}  {:<25}  {:<25}  {:<6}"
        print(fmt.format("setting", "expected", "actual", "status"))
        print("  " + "-" * 100)
        for key, exp, act in drifted:
            print(fmt.format(key[:42], str(exp)[:25], str(act)[:25], "DRIFT"))
    else:
        print("  All GUC settings match expected baseline.")

    print(f"\n  pg_hba.conf Rules  (PG version {pg_version // 10000})")
    if hba_issues:
        for issue in hba_issues:
            print(f"  [ WARN ] {issue}")
    else:
        print("  All expected HBA rules present.")


def parse_args():
    p = argparse.ArgumentParser(description="Config drift check: running PG vs expected baseline")
    p.add_argument("--host",     default=DEFAULT_HOST)
    p.add_argument("--port",     type=int, default=DEFAULT_PORT)
    p.add_argument("--dbname",   default=DEFAULT_DB)
    p.add_argument("--user",     default=DEFAULT_USER)
    p.add_argument("--password", default=DEFAULT_PASS)
    p.add_argument("--strict",   action="store_true",
                   help="Exit with code 1 if any drift or HBA issues are found")
    return p.parse_args()


def main():
    args = parse_args()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    print("=" * 65)
    print("  Voleon quantdb - Ansible Config Drift Check")
    print(f"  Host: {args.host}  |  {now}")
    print("=" * 65)

    conn = connect(args.host, args.port, args.dbname, args.user, args.password)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        pg_version = get_pg_version(cur)
        actual     = get_settings(cur)
        drifted, matched = check_settings(actual)
        hba_issues = check_hba_rules(cur, pg_version)
    conn.close()

    print_drift_report(drifted, matched, hba_issues, pg_version)

    print("\n" + "=" * 65)
    total_issues = len(drifted) + len(hba_issues)
    if total_issues:
        print(f"  SUMMARY: {total_issues} issue(s) found - review drift above")
        if args.strict:
            sys.exit(1)
    else:
        print("  SUMMARY: No drift detected - configuration matches baseline")


if __name__ == "__main__":
    main()
