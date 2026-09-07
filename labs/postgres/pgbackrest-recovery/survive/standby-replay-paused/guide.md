# The standby is connected but cannot reach the backup point

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Inspect replay state

Check replay directly instead of treating reachability as backup readiness.

On pg-standby as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-standby, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-standby.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-standby.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Inspect replay state

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_is_wal_replay_paused();
```

Check replay directly instead of treating reachability as backup readiness.

t while the fault is active.

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Resume WAL replay

Allow the standby to apply WAL again.

On pg-standby as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-standby, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-standby.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-standby.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Resume replay

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_wal_replay_resume();
```

Resume the existing standby without changing its role.

The function completes.

### Check replay state

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_is_wal_replay_paused();
```

Confirm replay is no longer paused.

f

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Prove the standby reaches the backup point

Take a incr backup using the explicit executing role and repository.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 --type=incr --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new incr backup is recorded for academy.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.
