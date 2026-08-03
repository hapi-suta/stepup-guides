#!/usr/bin/env python3
"""
container_health.py - Docker container health monitoring for the Voleon pg-ops server.

Checks:
  - Running containers (docker ps)
  - Resource usage per container (docker stats --no-stream)
  - Database connectivity test for PG containers
  - Volume disk usage
  - Container restart counts

Requires docker CLI to be available and the running user to have docker access.

Usage:
    python3 container_health.py
    python3 container_health.py --filter voleon
    python3 container_health.py --host 172.31.19.86 --port 5432
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime

import psycopg2

DEFAULT_PG_HOST = "172.31.19.86"
DEFAULT_PG_PORT = 5432
DEFAULT_PG_DB   = "quantdb"
DEFAULT_PG_USER = "quant_readonly"
DEFAULT_PG_PASS = "quant_readonly_2026"

DOCKER_BIN = "docker"


def run_cmd(cmd: list, timeout: int = 30) -> tuple[int, str, str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except FileNotFoundError:
        return 127, "", f"Command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", f"Command timed out after {timeout}s"


def indicator(status: str) -> str:
    return {"PASS": "[ PASS ]", "WARN": "[ WARN ]", "FAIL": "[ FAIL ]"}.get(status, "[ INFO ]")


def get_running_containers(name_filter: str) -> list[dict]:
    fmt = (
        '{"id":"{{.ID}}",'
        '"name":"{{.Names}}",'
        '"image":"{{.Image}}",'
        '"status":"{{.Status}}",'
        '"ports":"{{.Ports}}",'
        '"restarts":"{{.RunningFor}}"}'
    )
    cmd = [DOCKER_BIN, "ps", "--format", fmt]
    if name_filter:
        cmd += ["--filter", f"name={name_filter}"]

    rc, out, err = run_cmd(cmd)
    if rc == 127:
        print(f"  {indicator('FAIL')} Docker CLI not found: {err}")
        return []
    if rc != 0:
        print(f"  {indicator('FAIL')} docker ps failed: {err}")
        return []

    containers = []
    for line in out.splitlines():
        line = line.strip()
        if line:
            try:
                containers.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return containers


def get_container_stats() -> dict[str, dict]:
    """Returns a dict keyed by container name with cpu/mem stats."""
    cmd = [DOCKER_BIN, "stats", "--no-stream", "--format",
           '{"name":"{{.Name}}","cpu":"{{.CPUPerc}}","mem":"{{.MemUsage}}",'
           '"net":"{{.NetIO}}","block":"{{.BlockIO}}","pids":"{{.PIDs}}"}']
    rc, out, err = run_cmd(cmd, timeout=15)
    stats = {}
    if rc != 0:
        return stats
    for line in out.splitlines():
        line = line.strip()
        if line:
            try:
                s = json.loads(line)
                stats[s["name"]] = s
            except json.JSONDecodeError:
                pass
    return stats


def get_restart_counts(container_ids: list[str]) -> dict[str, int]:
    """Returns restart count per container ID."""
    counts = {}
    for cid in container_ids:
        cmd = [DOCKER_BIN, "inspect", "--format",
               "{{.RestartCount}}", cid]
        rc, out, _ = run_cmd(cmd)
        if rc == 0:
            try:
                counts[cid] = int(out.strip())
            except ValueError:
                counts[cid] = -1
    return counts


def test_pg_connectivity(host, port, dbname, user, password) -> tuple[bool, str]:
    try:
        conn = psycopg2.connect(
            host=host, port=port, dbname=dbname,
            user=user, password=password, connect_timeout=3
        )
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        return True, "OK"
    except psycopg2.OperationalError as exc:
        return False, str(exc)[:80]


def get_volume_usage() -> list[dict]:
    cmd = [DOCKER_BIN, "system", "df", "--format",
           '{"type":"{{.Type}}","total":"{{.TotalCount}}",'
           '"active":"{{.Active}}","size":"{{.Size}}","reclaimable":"{{.Reclaimable}}"}']
    rc, out, _ = run_cmd(cmd)
    items = []
    if rc == 0:
        for line in out.splitlines():
            line = line.strip()
            if line:
                try:
                    items.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return items


def parse_args():
    p = argparse.ArgumentParser(description="Docker container health check for Voleon pg-ops")
    p.add_argument("--filter",    default="",
                   help="Filter containers by name pattern (default: all)")
    p.add_argument("--host",      default=DEFAULT_PG_HOST,
                   help="PostgreSQL host for connectivity test")
    p.add_argument("--port",      type=int, default=DEFAULT_PG_PORT)
    p.add_argument("--dbname",    default=DEFAULT_PG_DB)
    p.add_argument("--user",      default=DEFAULT_PG_USER)
    p.add_argument("--password",  default=DEFAULT_PG_PASS)
    p.add_argument("--skip-pg",   action="store_true",
                   help="Skip PostgreSQL connectivity test")
    return p.parse_args()


def main():
    args = parse_args()
    now  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    print("=" * 65)
    print("  Voleon pg-ops - Container Health Report")
    print(f"  {now}")
    print("=" * 65)

    containers = get_running_containers(args.filter)
    if not containers:
        print("  No running containers found (or docker not accessible).")
    else:
        print(f"\n  Running containers: {len(containers)}")
        fmt = "  {:<25}  {:<35}  {:<25}"
        print(fmt.format("name", "image", "status"))
        print("  " + "-" * 85)
        for c in containers:
            print(fmt.format(c["name"][:25], c["image"][:35], c["status"][:25]))

    # Stats
    if containers:
        stats = get_container_stats()
        restart_counts = get_restart_counts([c["id"] for c in containers])
        id_to_name = {c["id"]: c["name"] for c in containers}

        print(f"\n  Resource usage (live):")
        fmt = "  {:<25}  {:<8}  {:<22}  {:<18}  {:<8}  {:>8}"
        print(fmt.format("name", "cpu%", "mem", "net_io", "pids", "restarts"))
        print("  " + "-" * 95)
        for c in containers:
            s = stats.get(c["name"], {})
            rc = restart_counts.get(c["id"], 0)
            restart_status = "WARN" if rc > 3 else "ok"
            print(fmt.format(
                c["name"][:25],
                str(s.get("cpu", "?")),
                str(s.get("mem", "?"))[:22],
                str(s.get("net", "?"))[:18],
                str(s.get("pids", "?")),
                f"{rc} ({restart_status})"
            ))

    # PG connectivity
    if not args.skip_pg:
        ok, msg = test_pg_connectivity(
            args.host, args.port, args.dbname, args.user, args.password
        )
        status = "PASS" if ok else "FAIL"
        print(f"\n  {indicator(status)} PostgreSQL connectivity: {args.host}:{args.port}/{args.dbname} - {msg}")

    # Volume / disk usage
    volumes = get_volume_usage()
    if volumes:
        print(f"\n  Docker disk usage:")
        fmt = "  {:<15}  {:>8}  {:>8}  {:>12}  {:>15}"
        print(fmt.format("type", "total", "active", "size", "reclaimable"))
        print("  " + "-" * 60)
        for v in volumes:
            print(fmt.format(
                v.get("type", "?")[:15],
                v.get("total", "?"),
                v.get("active", "?"),
                v.get("size", "?"),
                v.get("reclaimable", "?")
            ))

    print("\n" + "=" * 65)


if __name__ == "__main__":
    main()
