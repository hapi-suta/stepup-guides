#!/usr/bin/env python3
"""
backup_report.py - Check pgBackRest backup status for the Voleon lab stanza.

Runs `pgbackrest info --output=json`, parses the result, and reports:
  - Last full backup time and age
  - Last differential backup time and age
  - Total repository size on disk
  - WAL archive status
  - WARN if last full backup > 24 hours old
  - WARN if last diff backup > 6 hours old

Usage:
    python3 backup_report.py
    python3 backup_report.py --stanza voleon-lab
    python3 backup_report.py --stanza voleon-lab --full-warn-hours 12
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone

DEFAULT_STANZA         = "voleon-lab"
WARN_FULL_HOURS        = 24
WARN_DIFF_HOURS        = 6
PGBACKREST_BIN         = "/usr/bin/pgbackrest"


def indicator(status: str) -> str:
    return {"PASS": "[ PASS ]", "WARN": "[ WARN ]", "FAIL": "[ FAIL ]"}.get(status, "[ INFO ]")


def run_pgbackrest(stanza: str) -> dict:
    cmd = [PGBACKREST_BIN, "--stanza", stanza, "info", "--output=json"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except FileNotFoundError:
        print(f"ERROR: pgbackrest not found at {PGBACKREST_BIN}")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("ERROR: pgbackrest info timed out after 30 seconds")
        sys.exit(1)

    if result.returncode != 0:
        print(f"ERROR: pgbackrest returned exit code {result.returncode}")
        print(result.stderr.strip())
        sys.exit(1)

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print(f"ERROR: Could not parse pgbackrest JSON output - {exc}")
        print(result.stdout[:200])
        sys.exit(1)


def age_hours(timestamp_str: str) -> float:
    """Return age in hours given an ISO-8601 or pgBackRest timestamp string."""
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
        try:
            dt = datetime.strptime(timestamp_str, fmt).replace(tzinfo=timezone.utc)
            now = datetime.now(tz=timezone.utc)
            return (now - dt).total_seconds() / 3600
        except ValueError:
            continue
    return float("inf")


def bytes_human(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"


def report_backup(backup: dict, btype: str, warn_hours: float) -> None:
    stop_time = backup.get("timestamp", {}).get("stop", "")
    start_time = backup.get("timestamp", {}).get("start", "")
    age = age_hours(stop_time)
    size_repo = backup.get("info", {}).get("repository", {}).get("size", 0)
    size_db   = backup.get("info", {}).get("size", 0)
    label     = backup.get("label", "unknown")

    status = "WARN" if age > warn_hours else "PASS"
    print(f"  {indicator(status)} Last {btype.upper():4s} backup")
    print(f"           Label      : {label}")
    print(f"           Start      : {start_time}")
    print(f"           Stop       : {stop_time}")
    print(f"           Age        : {age:.1f} hours  (warn > {warn_hours}h)")
    print(f"           DB size    : {bytes_human(size_db)}")
    print(f"           Repo size  : {bytes_human(size_repo)}")


def parse_args():
    p = argparse.ArgumentParser(description="pgBackRest backup status report")
    p.add_argument("--stanza",          default=DEFAULT_STANZA)
    p.add_argument("--full-warn-hours", type=float, default=WARN_FULL_HOURS,
                   help="Warn if last FULL backup is older than N hours (default 24)")
    p.add_argument("--diff-warn-hours", type=float, default=WARN_DIFF_HOURS,
                   help="Warn if last DIFF backup is older than N hours (default 6)")
    return p.parse_args()


def main():
    args = parse_args()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print("=" * 60)
    print("  Voleon quantdb - pgBackRest Backup Report")
    print(f"  Stanza: {args.stanza}  |  {now}")
    print("=" * 60)

    data = run_pgbackrest(args.stanza)

    if not data:
        print("  [ INFO ] No stanza data returned by pgbackrest")
        sys.exit(0)

    stanza_info = data[0] if isinstance(data, list) else data
    backups = stanza_info.get("backup", [])

    if not backups:
        print("  [ FAIL ] No backups found for stanza")
        sys.exit(1)

    last_full = next((b for b in reversed(backups) if b.get("type") == "full"), None)
    last_diff = next((b for b in reversed(backups) if b.get("type") == "diff"), None)
    last_incr = next((b for b in reversed(backups) if b.get("type") == "incr"), None)

    if last_full:
        report_backup(last_full, "full", args.full_warn_hours)
    else:
        print(f"  {indicator('FAIL')} No FULL backup found")

    if last_diff:
        report_backup(last_diff, "diff", args.diff_warn_hours)
    else:
        print(f"  {indicator('WARN')} No DIFF backup found")

    if last_incr:
        report_backup(last_incr, "incr", args.diff_warn_hours)

    # Archive status
    archive = stanza_info.get("archive", [])
    if archive:
        print(f"\n  {indicator('INFO')} WAL Archive")
        for a in archive:
            print(f"           id={a.get('id','?')}  min={a.get('min','?')}  max={a.get('max','?')}")

    # Total backup count
    print(f"\n  {indicator('PASS')} Total backups in stanza : {len(backups)}")
    print("=" * 60)


if __name__ == "__main__":
    main()
