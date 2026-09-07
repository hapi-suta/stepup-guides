# The requested recovery point never existed

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Read the recovery failure

Look for recovery ending before the configured target was reached. Earlier recovery messages alone do not establish success.

On pg-primary as ec2-user.

### Read the recovery failure

Use the Linux terminal.

```bash
sudo tail -n 50 /var/lib/pgsql/incident-missing-target/startup.log
```

Read the retained log from the failed isolated candidate.

The FATAL message says recovery ended before the target was reached.

## Write the isolated existing-target restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated existing-target restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-existing-target-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-existing-target-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-existing-target-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-existing-target-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-existing-target-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-existing-target-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-existing-target-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-existing-target-repo2
```

Only . and .. appear.

## Restore the existing-target backup

A successful backup becomes useful only after its data can be recovered.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Restore the files

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/restore-existing-target-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=name --target="before_bad_update" --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to the recorded target. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-existing-target-repo2/PG_VERSION
```

Read the restored cluster’s major version. File presence does not establish recovery success.

16

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Separate the restored server from the live source

A copied postgresql.conf can still name the original data directory. Set the isolated directory and port before starting the restored copy. This copy accepts only local lab connections. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Separate the restored server from the live source

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-existing-target-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-existing-target-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-existing-target-repo2'
port = 55434
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-existing-target-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-existing-target-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-existing-target-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-existing-target-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated existing-target recovery

Start recovery and then check readiness independently.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Start the restored server

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-existing-target-repo2 -l /var/lib/pgsql/restore-existing-target-repo2/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55434
```

Check the isolated port, not live port 5432. Recovery may initially report rejecting connections. Wait a few seconds and run this same check again until it accepts connections. If rejection persists, inspect startup.log before proceeding. Readiness still does not prove the recovered records.

Continue only when the isolated port reports accepting connections.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Accept the recovered existing-target data

Check location, recovery state and exact records before accepting this restore.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55434
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55434.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-existing-target-repo2

### Confirm recovery completed

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_is_in_recovery();
```

Check whether the restored server has finished recovery.

f

### Inspect the known records

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Compare the restored rows with the backup point.

Rows 1 through 5 remain present.

### Count the payload

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_payload;
```

Check the full known dataset.

10000

### Confirm archiving stays off

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW archive_mode;
```

The isolated copy must not compete with the source archiver.

off

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
