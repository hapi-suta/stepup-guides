# Runbook: Linux System Crisis

## Scenario Overview

Three simultaneous Linux-level issues are degrading your PostgreSQL primary:

1. **/tmp is nearly full** - PG uses /tmp for sorting, hashing, and temp files. When it fills up, queries that need temp space fail.
2. **vm.swappiness is set to 100** - The kernel aggressively swaps memory to disk, causing PG shared buffers and working memory to be paged out. Queries slow to a crawl.
3. **50% packet loss between primary and replica** - An iptables rule is randomly dropping half the traffic, causing replication lag to spike and possible WAL sender timeouts.

---

## Phase 1: Triage - What Are You Seeing?

Before diving into fixes, confirm the symptoms. A Voleon-style production alert might look like:

- Grafana shows replication lag climbing from milliseconds to seconds (or minutes)
- Application response times have doubled or tripled
- Some large analytical queries are returning errors about "could not write to file" in temp space
- `top` or Prometheus node exporter shows swap usage climbing

**Your first 60 seconds should be spent confirming the system is actually sick, not chasing ghosts.**

---

## Phase 2: Diagnose Each Issue

### Issue 1: /tmp Space Exhaustion

On **pg-primary**, as **ec2-user**:

Check disk usage on /tmp:

```bash
df -h /tmp
```

Expected output (yours will differ):

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       8G   7.6G  400M  95% /
```

If /tmp is on the root partition (common on EC2), the entire root filesystem may be at 95%.

Find the largest files in /tmp:

```bash
ls -lhS /tmp/ | head -20
```

Expected output (yours will differ):

```
total 7.2G
-rw-r--r-- 1 root root 7.0G Jun 18 14:30 .chaos_tmpfill
drwxrwxrwt 2 root root 4.0K Jun 18 14:00 .ICE-unix
...
```

Check if PostgreSQL is having temp file issues. Still as **ec2-user** on **pg-primary**:

```bash
sudo -u postgres psql -d quantdb -c "SELECT datname, temp_files, temp_bytes FROM pg_stat_database WHERE datname = 'quantdb';"
```

Expected output (yours will differ):

```
 datname  | temp_files | temp_bytes
----------+------------+------------
 quantdb  |         42 |  104857600
```

Try to reproduce the symptom - run a query that needs temp space. Still as **ec2-user** on **pg-primary**:

```bash
sudo -u postgres psql -d quantdb -c "SELECT * FROM generate_series(1, 10000000) s ORDER BY random() LIMIT 10;"
```

If /tmp is full, you may see an error like:

```
ERROR:  could not write block 12345 of temporary file: No space left on device
```

### Issue 2: Aggressive Swapping

On **pg-primary**, as **ec2-user**:

Check current swappiness value:

```bash
cat /proc/sys/vm/swappiness
```

Expected output (yours will differ):

```
100
```

A value of 100 tells the kernel to aggressively swap pages to disk. For PostgreSQL, this should be 1 (or at most 10). PostgreSQL manages its own memory via shared_buffers - letting the OS swap those pages destroys performance.

Check current swap usage:

```bash
free -h
```

Expected output (yours will differ):

```
              total        used        free      shared  buff/cache   available
Mem:          3.7Gi       2.1Gi       256Mi       128Mi       1.4Gi       1.3Gi
Swap:         2.0Gi       1.2Gi       800Mi
```

If the Swap "used" column is significant, the system is actively swapping.

Check which processes are using swap. Still as **ec2-user** on **pg-primary**:

```bash
for pid in $(ls /proc/[0-9]*/status 2>/dev/null | cut -d'/' -f3); do
  SWAP=$(grep VmSwap /proc/$pid/status 2>/dev/null | awk '{print $2}')
  if [ -n "$SWAP" ] && [ "$SWAP" -gt 0 ] 2>/dev/null; then
    NAME=$(grep Name /proc/$pid/status 2>/dev/null | awk '{print $2}')
    echo "$SWAP kB - PID $pid ($NAME)"
  fi
done | sort -rn | head -10
```

Expected output (yours will differ):

```
524288 kB - PID 1234 (postgres)
131072 kB - PID 1235 (postgres)
65536 kB - PID 1240 (postgres)
...
```

If PostgreSQL processes are high on the swap list, that confirms the problem.

### Issue 3: Network Packet Loss to Replica

On **pg-primary**, as **ec2-user**:

Check replication status from the primary:

```bash
sudo -u postgres psql -d quantdb -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
```

Expected output (yours will differ):

```
  client_addr   |   state   |  sent_lsn   | write_lsn   | flush_lsn   | replay_lsn  | write_lag | flush_lag | replay_lag
----------------+-----------+-------------+-------------+-------------+-------------+-----------+-----------+------------
 172.31.22.69   | streaming | 0/1A000060  | 0/19FFF8E0  | 0/19FFF8E0  | 0/19FFF8E0  | 00:00:45  | 00:00:45  | 00:00:45
```

Large lag values (seconds or more) confirm the issue.

Check for iptables rules on the primary. Still as **ec2-user** on **pg-primary**:

```bash
sudo iptables -L OUTPUT -n -v --line-numbers
```

Expected output (yours will differ):

```
Chain OUTPUT (policy ACCEPT 12345 packets, 1234K bytes)
num   pkts bytes target     prot opt in     out     source               destination
1     6789  456K DROP       all  --  *      *       0.0.0.0/0            172.31.22.69       statistic mode random probability 0.50000000000
```

This confirms a DROP rule targeting 50% of traffic to the replica's private IP.

Verify packet loss with a quick ping test. Still as **ec2-user** on **pg-primary**:

```bash
ping -c 20 172.31.22.69 | tail -3
```

Expected output (yours will differ):

```
--- 172.31.22.69 ping statistics ---
20 packets transmitted, 10 received, 50% packet loss, time 19032ms
rtt min/avg/max/mdev = 0.345/0.567/0.789/0.123 ms
```

~50% packet loss confirms the iptables rule is active.

---

## Phase 3: Fix Each Issue

### Fix 1: Clear /tmp

On **pg-primary**, as **ec2-user**:

Remove the large file filling /tmp:

```bash
sudo rm -f /tmp/.chaos_tmpfill
```

Verify /tmp has space again:

```bash
df -h /tmp
```

Expected output (yours will differ):

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       8G   600M  7.4G   8% /
```

Usage should drop well below 80%.

### Fix 2: Restore vm.swappiness

On **pg-primary**, as **ec2-user**:

Set swappiness back to 1 (recommended for PostgreSQL servers):

```bash
sudo sysctl -w vm.swappiness=1
```

Expected output (yours will differ):

```
vm.swappiness = 1
```

Verify the change took effect:

```bash
cat /proc/sys/vm/swappiness
```

Expected output (yours will differ):

```
1
```

If the system accumulated swap during the incident, you can reclaim it. This forces all swapped pages back into RAM. Only do this if you have enough free RAM.

Check free RAM first. Still as **ec2-user** on **pg-primary**:

```bash
free -h
```

If "available" memory is larger than swap "used", you can safely clear swap:

```bash
sudo swapoff -a && sudo swapon -a
```

This may take a minute. PostgreSQL performance should improve immediately after pages return to RAM.

**Make it permanent.** The sysctl change above is runtime only - it will revert on reboot. To persist it, still as **ec2-user** on **pg-primary**:

```bash
echo 'vm.swappiness = 1' | sudo tee /etc/sysctl.d/99-postgres-swap.conf
```

Expected output (yours will differ):

```
vm.swappiness = 1
```

### Fix 3: Remove iptables Packet Drop Rule

On **pg-primary**, as **ec2-user**:

First, identify the rule number:

```bash
sudo iptables -L OUTPUT -n --line-numbers
```

Expected output (yours will differ):

```
Chain OUTPUT (policy ACCEPT)
num  target     prot opt source               destination
1    DROP       all  --  0.0.0.0/0            172.31.22.69       statistic mode random probability 0.50000000000
```

Delete rule number 1 (adjust if your rule number differs):

```bash
sudo iptables -D OUTPUT -d 172.31.22.69 -m statistic --mode random --probability 0.5 -j DROP
```

Verify the rule is gone:

```bash
sudo iptables -L OUTPUT -n --line-numbers
```

Expected output (yours will differ):

```
Chain OUTPUT (policy ACCEPT)
num  target     prot opt source               destination
```

The OUTPUT chain should now be empty (or only contain your legitimate rules).

Confirm connectivity is restored. Still as **ec2-user** on **pg-primary**:

```bash
ping -c 10 172.31.22.69 | tail -3
```

Expected output (yours will differ):

```
--- 172.31.22.69 ping statistics ---
10 packets transmitted, 10 received, 0% packet loss, time 9012ms
rtt min/avg/max/mdev = 0.312/0.456/0.567/0.078 ms
```

0% packet loss confirms the fix.

---

## Phase 4: Verify Full Recovery

### Check 1: PostgreSQL is Running and Accepting Connections

On **pg-primary**, as **ec2-user**:

```bash
sudo -u postgres psql -d quantdb -c "SELECT version();"
```

Expected output (yours will differ):

```
                                                  version
-----------------------------------------------------------------------------------------------------------
 PostgreSQL 17.x on x86_64-pc-linux-gnu, compiled by gcc ...
```

### Check 2: Temp Files Work Again

On **pg-primary**, as **ec2-user**:

```bash
sudo -u postgres psql -d quantdb -c "SELECT count(*) FROM generate_series(1, 5000000) s ORDER BY random();"
```

Expected output (yours will differ):

```
  count
---------
 5000000
```

No "No space left on device" error means temp files are working.

### Check 3: Swap is Under Control

On **pg-primary**, as **ec2-user**:

```bash
cat /proc/sys/vm/swappiness
```

Expected output (yours will differ):

```
1
```

```bash
free -h
```

Swap usage should be at 0 or very low after the swapoff/swapon cycle.

### Check 4: Replication is Healthy

On **pg-primary**, as **ec2-user**:

```bash
sudo -u postgres psql -d quantdb -c "SELECT client_addr, state, replay_lag FROM pg_stat_replication;"
```

Expected output (yours will differ):

```
  client_addr   |   state   | replay_lag
----------------+-----------+------------
 172.31.22.69   | streaming | 00:00:00
```

The state should be "streaming" and replay_lag should be near zero (under 1 second).

On **pg-replica** (54.144.241.128), as **ec2-user**:

```bash
sudo -u postgres psql -d quantdb -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();"
```

Expected output (yours will differ):

```
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp
-------------------------+------------------------+-------------------------------
 0/1A000060              | 0/1A000060             | 2026-06-18 14:45:12.345678+00
```

The receive and replay LSNs should match (or be very close), and the timestamp should be recent.

---

## Phase 5: Post-Mortem - What Monitoring Would Catch This?

### For /tmp Exhaustion

- **Prometheus node_exporter** metric: `node_filesystem_avail_bytes{mountpoint="/tmp"}` or `node_filesystem_avail_bytes{mountpoint="/"}` if /tmp is on root
- **Alert rule**: Fire when filesystem usage exceeds 80%
- **Grafana dashboard**: Disk usage panel per mountpoint
- **PG-level**: Monitor `pg_stat_database.temp_bytes` for sudden spikes

### For Swap Issues

- **Prometheus node_exporter** metrics: `node_memory_SwapFree_bytes`, `node_vmstat_pswpin`, `node_vmstat_pswpout`
- **Alert rule**: Fire when swap usage exceeds 10% of total swap, or when pswpin/pswpout rates spike
- **sysctl audit**: Use a config management tool (Ansible, Chef) to enforce `vm.swappiness=1` and detect drift
- **PG-level**: Monitor query latency percentiles - swap storms cause p99 spikes

### For Network Degradation

- **Prometheus blackbox_exporter**: TCP connect checks between primary and replica
- **pg_stat_replication monitoring**: Alert when `replay_lag` exceeds 5 seconds
- **Network metrics**: `node_netstat_Tcp_RetransSegs` from node_exporter shows TCP retransmissions
- **iptables audit**: Periodically dump and hash iptables rules, alert on unexpected changes
- **PgBouncer stats**: Monitor `avg_query_time` for sudden increases

### Summary Table

| Issue               | Key Metric                           | Alert Threshold      |
|---------------------|--------------------------------------|----------------------|
| /tmp full           | node_filesystem_avail_bytes          | > 80% used           |
| Swap storm          | node_memory_SwapFree_bytes           | > 10% swap used      |
| Network degradation | pg_stat_replication replay_lag       | > 5 seconds          |
| Network degradation | node_netstat_Tcp_RetransSegs (rate)  | > 100/sec            |

### Interview Talking Points

When discussing this scenario in a Voleon DBA interview, emphasize:

1. **Triage order matters** - You checked all three issues before fixing any of them. This prevents "fix one thing, break another" loops.
2. **Linux fundamentals are DBA fundamentals** - A DBA who cannot diagnose /tmp, swap, and iptables issues will struggle in production.
3. **vm.swappiness=1 is industry standard for PG** - Not 0 (which disables swap entirely and risks OOM kills), but 1 (swap only under extreme pressure).
4. **iptables rules are invisible to application monitoring** - You need network-layer monitoring to catch this. Application metrics only show the symptom (lag), not the cause.
5. **Persistence matters** - Runtime sysctl changes are lost on reboot. Always persist to /etc/sysctl.d/ and manage via config management.
