# USE: operate and inspect

Run one action at a time on the named server. Read every result before continuing. Opening a shell or client is preparation; the independent validator supplies completion evidence.

## 1. Inspect streaming replication

On **pg-ha-1** as **ec2-user**.

The writer reports its replication connections. In this three-node lab, expect two connections in streaming state.

Run one action at a time. Prompt examples identify where to type; do not type the prompt.

1. Switch to the postgres user
Start in the Linux terminal on pg-ha-1, as ec2-user.
```bash
sudo -iu postgres
```
sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
The prompt should identify postgres: [postgres@pg-ha-1 ~]$.

2. Connect to PostgreSQL
Type this in the postgres Linux shell.
```bash
/opt/pgsql/bin/psql -h /var/run/postgresql -d postgres
```
The full path selects this lab’s psql program. -h selects the local socket directory; -d selects the postgres database.
Wait for postgres=#. You are now entering SQL or psql commands.

3. Check replication
Type this at the postgres=# database prompt. Type only the command.
```sql
select state,count(*) from pg_stat_replication group by state;
```
Count the writer’s replication connections in each state. The semicolon ends this one SQL statement.
Look for streaming with count 2. This does not measure replay lag.

4. Leave PostgreSQL
After reading the checks, type this at postgres=#.
```text
\q
```
Leave the database client and return to Linux.
You should see the postgres shell prompt again.

5. Return to your original user
Type this in the postgres Linux shell.
```bash
exit
```
Close the nested shell before the next lesson.
The prompt should identify ec2-user again.

Expected: The result table has a row with state streaming and count 2.

## 2. Verify data placement and checksums

On **pg-ha-2** as **ec2-user**.

Correct storage and checksums are prerequisites for safe recovery.

Run one action at a time. Prompt examples identify where to type; do not type the prompt.

1. Switch to the postgres user
Start in the Linux terminal on pg-ha-2, as ec2-user.
```bash
sudo -iu postgres
```
sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
The prompt should identify postgres: [postgres@pg-ha-2 ~]$.

2. Connect to PostgreSQL
Type this in the postgres Linux shell.
```bash
/opt/pgsql/bin/psql -h /var/run/postgresql -d postgres
```
The full path selects this lab’s psql program. -h selects the local socket directory; -d selects the postgres database.
Wait for postgres=#. You are now entering SQL or psql commands.

3. Check the data directory
Type this at the postgres=# database prompt. Type only the command.
```sql
show data_directory;
```
SHOW reports the current setting. data_directory identifies where PostgreSQL stores the cluster files.
Look for /opt/pgsql/data.

4. Check whether checksums are enabled
Type this at the postgres=# database prompt. Type only the command.
```sql
show data_checksums;
```
Page checksums help detect corrupted data pages. This separate SHOW reports whether they are enabled.
Look for on. Both this result and the data-directory result are required.

5. Leave PostgreSQL
After reading the checks, type this at postgres=#.
```text
\q
```
Leave the database client and return to Linux.
You should see the postgres shell prompt again.

6. Return to your original user
Type this in the postgres Linux shell.
```bash
exit
```
Close the nested shell before the next lesson.
The prompt should identify ec2-user again.

Expected: PGDATA is /opt/pgsql/data and checksums are on.

## 3. Check Mattermost from the workload node

On **mattermost-1** as **ec2-user**.

The application is the end-to-end consumer of the HA database path.

```bash
curl -fsS http://127.0.0.1:8065/api/v4/system/ping
```

curl requests Mattermost’s system ping endpoint on this workload node. 127.0.0.1 means this same machine. -f treats HTTP errors as failure; -s hides the progress meter; -S still shows errors. A successful ping does not prove a workload write succeeds.

Expected: The API reports status OK.

## 4. Perform a planned Patroni switchover

On **pg-ha-1** as **ec2-user**.

Maintenance requires moving leadership without pretending an outage occurred.

Run one action at a time. Prompt examples identify where to type; do not type the prompt.

1. Switch to the postgres user
Start in the Linux terminal on pg-ha-1, as ec2-user.
```bash
sudo -iu postgres
```
sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
The prompt should identify postgres: [postgres@pg-ha-1 ~]$.

2. Move leadership to pg-ha-2
Type this in the postgres Linux shell.
```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml switchover --leader pg-ha-1 --candidate pg-ha-2 --force
```
Request a planned leadership change from pg-ha-1 to pg-ha-2. --force confirms the request without another question. Confirm the candidate is streaming before running it.
pg-ha-2 is leader, the former leader rejoins as streaming replica, and the application route is unchanged.

3. Check the cluster topology
On pg-ha-1, type this in the postgres Linux shell.
```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```
patronictl list shows the cluster from the DCS point of view: who leads, who streams, and each member's lag. A switchover is only done when the candidate is Leader and the old leader is back as a streaming Replica.
pg-ha-2 in the Leader role and every other member as Replica with state streaming

4. Return to your original user
Type this in the postgres Linux shell.
```bash
exit
```
Close the nested shell before the next lesson.
The prompt should identify ec2-user again.

Expected: pg-ha-2 is leader, the former leader rejoins as streaming replica, and the application route is unchanged.

## 5. Apply a dynamic Patroni configuration change

On **pg-ha-2** as **ec2-user**.

Daily operations change cluster-wide settings through the DCS, not stale bootstrap YAML.

Run one action at a time. Prompt examples identify where to type; do not type the prompt.

1. Switch to the postgres user
Start in the Linux terminal on pg-ha-2, as ec2-user.
```bash
sudo -iu postgres
```
sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
The prompt should identify postgres: [postgres@pg-ha-2 ~]$.

2. Change the slow-query logging threshold
Type this in the postgres Linux shell.
```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml edit-config --set postgresql.parameters.log_min_duration_statement=1000 --force
```
Set the cluster-wide threshold to 1000 milliseconds in the DCS. This changes one setting, not the bootstrap file.
The DCS contains the setting and Patroni reports whether reload or restart is required.

3. Check the configured value
On pg-ha-2, type this in the postgres Linux shell.
```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml show-config
```
Read the dynamic configuration stored in the DCS. Locate the named field yourself.
Under postgresql → parameters, find log_min_duration_statement: 1000. This proves the DCS value; it does not prove every running process has applied it.

4. Return to your original user
Type this in the postgres Linux shell.
```bash
exit
```
Close the nested shell before the next lesson.
The prompt should identify ec2-user again.

Expected: The DCS contains the setting and Patroni reports whether reload or restart is required.

## 6. Restart one replica under Patroni control

On **pg-ha-3** as **ec2-user**.

A controlled replica restart rehearses safe maintenance without removing writer availability.

Run one action at a time. Prompt examples identify where to type; do not type the prompt.

1. Switch to the postgres user
Start in the Linux terminal on pg-ha-3, as ec2-user.
```bash
sudo -iu postgres
```
sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
The prompt should identify postgres: [postgres@pg-ha-3 ~]$.

2. Restart only pg-ha-3
Type this in the postgres Linux shell.
```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml restart {{cluster_scope}} pg-ha-3 --force
```
Ask Patroni to restart this replica. The Guide inserts your assigned cluster name. Check that pg-ha-3 is a replica first.
pg-ha-3 returns streaming with zero byte lag and the leader never changes.

3. Check the cluster topology
On pg-ha-3, type this in the postgres Linux shell.
```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```
After a restart or reinit the member must come back as a streaming Replica with zero lag, and the Leader must be unchanged. Run it again after a few seconds if the state is still starting.
pg-ha-3 as Replica with state streaming and Lag in MB 0

4. Return to your original user
Type this in the postgres Linux shell.
```bash
exit
```
Close the nested shell before the next lesson.
The prompt should identify ec2-user again.

Expected: pg-ha-3 returns streaming with zero byte lag and the leader never changes.

## 7. Reinitialize a disposable replica

On **pg-ha-3** as **ec2-user**.

Operators must know how to replace an unhealthy replica from the current leader.

Run one action at a time. Prompt examples identify where to type; do not type the prompt.

1. Switch to the postgres user
Start in the Linux terminal on pg-ha-3, as ec2-user.
```bash
sudo -iu postgres
```
sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
The prompt should identify postgres: [postgres@pg-ha-3 ~]$.

2. Rebuild the disposable replica
Type this in the postgres Linux shell.
```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml reinit {{cluster_scope}} pg-ha-3 --force
```
Replace this replica’s local data from the leader. This lab action destroys the replica copy: confirm pg-ha-3 is a replica with no unique data first.
pg-ha-3 is freshly cloned and returns to streaming on the current timeline.

3. Check the cluster topology
On pg-ha-3, type this in the postgres Linux shell.
```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```
After a restart or reinit the member must come back as a streaming Replica with zero lag, and the Leader must be unchanged. Run it again after a few seconds if the state is still starting.
pg-ha-3 as Replica with state streaming and Lag in MB 0

4. Return to your original user
Type this in the postgres Linux shell.
```bash
exit
```
Close the nested shell before the next lesson.
The prompt should identify ec2-user again.

Expected: pg-ha-3 is freshly cloned and returns to streaming on the current timeline.

## 8. Create and verify an etcd snapshot

On **dcs-1** as **ec2-user**.

DCS recovery requires a real snapshot whose integrity is checked before an incident.

```bash
sudo /usr/local/bin/etcdctl --endpoints=https://dcs-1:2379 --cacert=/etc/etcd/ca.crt --cert=/etc/etcd/member.crt --key=/etc/etcd/member.key snapshot save /var/lib/etcd/suta-baseline.db
```

Run the single registered workplace operation; the independent observer proves its postcondition.

Expected: etcd writes a snapshot that etcdutl validates and that contains cluster keys.

### Prove it worked

```bash
sudo /usr/local/bin/etcdutl snapshot status /var/lib/etcd/suta-baseline.db --write-out=table
```

a table with HASH, REVISION, TOTAL KEYS and TOTAL SIZE for /var/lib/etcd/suta-baseline.db

## 9. Prove Mattermost after planned maintenance

On **mattermost-1** as **ec2-user**.

Database topology is only useful when the unchanged application endpoint still works.

```bash
curl -fsS http://127.0.0.1:8065/api/v4/system/ping
```

curl requests Mattermost’s system ping endpoint on this workload node. 127.0.0.1 means this same machine. -f treats HTTP errors as failure; -s hides the progress meter; -S still shows errors. A successful ping does not prove a workload write succeeds.

Expected: Mattermost returns status OK after switchover, config work and replica maintenance.
