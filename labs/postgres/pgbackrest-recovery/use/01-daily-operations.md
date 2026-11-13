# Operate the backup service

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Create the differential-backup marker

Make the change since the full backup visible and testable.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Insert the differential marker

Type this at postgres=#. Do not type the prompt itself.

```sql
INSERT INTO academy_proof VALUES (2, 'differential');
```

Add one known record after the full backup.

INSERT 0 1

### Read the markers

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Confirm the intended source records before backing up.

Rows1 and2 are present.

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

## Take the direct differential backup

Take a diff backup using the explicit executing role and repository.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Run the backup

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/direct.conf --stanza=academy --repo=1 --type=diff --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy --repo=1 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new diff backup is recorded for academy.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated direct-diff restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated direct-diff restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-direct-diff-repo1.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-direct-diff-repo1.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-direct-diff-repo1
[global]
log-level-console=info
process-max=2
repo1-path=/var/lib/pgbackrest/direct
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-direct-diff-repo1.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-direct-diff-repo1.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-direct-diff-repo1.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-direct-diff-repo1
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-direct-diff-repo1
```

Only . and .. appear.

## Restore the direct-diff backup

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
pgbackrest --config=/etc/pgbackrest/restore-direct-diff-repo1.conf --stanza=academy --repo=1 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-direct-diff-repo1/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-direct-diff-repo1/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-direct-diff-repo1/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-direct-diff-repo1'
port = 55433
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-direct-diff-repo1/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-direct-diff-repo1/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-direct-diff-repo1/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-direct-diff-repo1/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated direct-diff recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-direct-diff-repo1 -l /var/lib/pgsql/restore-direct-diff-repo1/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55433
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

## Accept the recovered direct-diff data

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55433
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55433.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-direct-diff-repo1

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

Rows1 and2 are present. Row3 does not exist at this backup point.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-direct-diff-repo1 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-direct-diff-repo1/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Take the server differential backup

Take a diff backup using the explicit executing role and repository.

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
pgbackrest --stanza=academy --repo=2 --type=diff --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new diff backup is recorded for academy.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated server-diff restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated server-diff restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-server-diff-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-server-diff-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-server-diff-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-server-diff-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-server-diff-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-server-diff-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-server-diff-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-server-diff-repo2
```

Only . and .. appear.

## Restore the server-diff backup

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
pgbackrest --config=/etc/pgbackrest/restore-server-diff-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-server-diff-repo2/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-server-diff-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-server-diff-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-server-diff-repo2'
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
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-server-diff-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-server-diff-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-server-diff-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-server-diff-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated server-diff recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-server-diff-repo2 -l /var/lib/pgsql/restore-server-diff-repo2/startup.log -t 40 -w start
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

## Accept the recovered server-diff data

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

/var/lib/pgsql/restore-server-diff-repo2

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

Rows1 and2 are present. Row3 does not exist at this backup point.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-server-diff-repo2 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-server-diff-repo2/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Take the s3 differential backup

Take a diff backup using the explicit executing role and repository.

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
pgbackrest --stanza=academy --repo=3 --type=diff --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=3 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new diff backup is recorded for academy.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated s3-diff restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated s3-diff restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-s3-diff-repo3.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-s3-diff-repo3.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-s3-diff-repo3
[global]
log-level-console=info
process-max=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
repo3-host=backup-1
repo3-host-user=pgbackrest
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-s3-diff-repo3.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-s3-diff-repo3.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-s3-diff-repo3.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-s3-diff-repo3
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-s3-diff-repo3
```

Only . and .. appear.

## Restore the s3-diff backup

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
pgbackrest --config=/etc/pgbackrest/restore-s3-diff-repo3.conf --stanza=academy --repo=3 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-s3-diff-repo3/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-s3-diff-repo3/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-s3-diff-repo3/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-s3-diff-repo3'
port = 55435
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-s3-diff-repo3/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-s3-diff-repo3/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-s3-diff-repo3/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-s3-diff-repo3/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated s3-diff recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-s3-diff-repo3 -l /var/lib/pgsql/restore-s3-diff-repo3/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55435
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

## Accept the recovered s3-diff data

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55435
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55435.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-s3-diff-repo3

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

Rows1 and2 are present. Row3 does not exist at this backup point.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-s3-diff-repo3 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-s3-diff-repo3/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Create the incremental-backup marker

Make the change since the latest backup visible.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Insert the incremental marker

Type this at postgres=#. Do not type the prompt itself.

```sql
INSERT INTO academy_proof VALUES (3, 'incremental');
```

Add the next known record after the differential backup.

INSERT 0 1

### Read the markers

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Confirm the source records before the next backup.

Rows1,2 and3 are present.

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

## Take the direct incremental backup

Take a incr backup using the explicit executing role and repository.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Run the backup

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/direct.conf --stanza=academy --repo=1 --type=incr --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy --repo=1 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new incr backup is recorded for academy.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated direct-incr restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated direct-incr restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-direct-incr-repo1.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-direct-incr-repo1.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-direct-incr-repo1
[global]
log-level-console=info
process-max=2
repo1-path=/var/lib/pgbackrest/direct
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-direct-incr-repo1.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-direct-incr-repo1.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-direct-incr-repo1.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-direct-incr-repo1
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-direct-incr-repo1
```

Only . and .. appear.

## Restore the direct-incr backup

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
pgbackrest --config=/etc/pgbackrest/restore-direct-incr-repo1.conf --stanza=academy --repo=1 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-direct-incr-repo1/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-direct-incr-repo1/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-direct-incr-repo1/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-direct-incr-repo1'
port = 55433
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-direct-incr-repo1/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-direct-incr-repo1/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-direct-incr-repo1/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-direct-incr-repo1/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated direct-incr recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-direct-incr-repo1 -l /var/lib/pgsql/restore-direct-incr-repo1/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55433
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

## Accept the recovered direct-incr data

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55433
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55433.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-direct-incr-repo1

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

Rows1,2 and3 are present. The restore uses the full/differential/incremental chain automatically.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-direct-incr-repo1 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-direct-incr-repo1/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Take the server incremental backup

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

## Write the isolated server-incr restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated server-incr restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-server-incr-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-server-incr-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-server-incr-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-server-incr-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-server-incr-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-server-incr-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-server-incr-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-server-incr-repo2
```

Only . and .. appear.

## Restore the server-incr backup

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
pgbackrest --config=/etc/pgbackrest/restore-server-incr-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-server-incr-repo2/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-server-incr-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-server-incr-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-server-incr-repo2'
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
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-server-incr-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-server-incr-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-server-incr-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-server-incr-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated server-incr recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-server-incr-repo2 -l /var/lib/pgsql/restore-server-incr-repo2/startup.log -t 40 -w start
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

## Accept the recovered server-incr data

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

/var/lib/pgsql/restore-server-incr-repo2

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

Rows1,2 and3 are present. The restore uses the full/differential/incremental chain automatically.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-server-incr-repo2 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-server-incr-repo2/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Take the s3 incremental backup

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
pgbackrest --stanza=academy --repo=3 --type=incr --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=3 info
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

## Write the isolated s3-incr restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated s3-incr restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-s3-incr-repo3.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-s3-incr-repo3.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-s3-incr-repo3
[global]
log-level-console=info
process-max=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
repo3-host=backup-1
repo3-host-user=pgbackrest
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-s3-incr-repo3.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-s3-incr-repo3.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-s3-incr-repo3.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-s3-incr-repo3
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-s3-incr-repo3
```

Only . and .. appear.

## Restore the s3-incr backup

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
pgbackrest --config=/etc/pgbackrest/restore-s3-incr-repo3.conf --stanza=academy --repo=3 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-s3-incr-repo3/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-s3-incr-repo3/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-s3-incr-repo3/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-s3-incr-repo3'
port = 55435
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-s3-incr-repo3/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-s3-incr-repo3/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-s3-incr-repo3/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-s3-incr-repo3/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated s3-incr recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-s3-incr-repo3 -l /var/lib/pgsql/restore-s3-incr-repo3/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55435
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

## Accept the recovered s3-incr data

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55435
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55435.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-s3-incr-repo3

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

Rows1,2 and3 are present. The restore uses the full/differential/incremental chain automatically.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-s3-incr-repo3 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-s3-incr-repo3/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Record a known safe recovery point

PITR needs a usable backup plus the WAL through a precise target.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Write the before-target record

Type this at postgres=#. Do not type the prompt itself.

```sql
INSERT INTO academy_proof VALUES (4, 'before_target');
```

Place a known record before the recovery boundary.

INSERT 0 1

### Name the recovery point

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_create_restore_point('academy_safe');
```

Write a named restore-point WAL record. Retain this name with the incident evidence.

A WAL location is returned.

### Create the target-time record

Type this at postgres=#. Do not type the prompt itself.

```sql
CREATE TABLE academy_recovery_clock (label text PRIMARY KEY, recorded_at timestamptz NOT NULL);
```

Keep the observed timestamp in a durable source record so the Guide can resolve this learner’s target exactly.

CREATE TABLE

### Record the actual clock time

Type this at postgres=#. Do not type the prompt itself.

```sql
INSERT INTO academy_recovery_clock VALUES ('academy_safe', clock_timestamp());
```

Capture the current server time before the unwanted record.

INSERT 0 1

### Read the recorded time

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT recorded_at FROM academy_recovery_clock WHERE label = 'academy_safe';
```

Keep the timezone with this timestamp. The target is specific to this lab run.

The timestamp includes a timezone offset.

### Confirm the pre-target data

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Check what exists before the next write.

Rows1,2,3 and4 are present.

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

## Create and archive a later write

Create a visible difference between the live source and the desired recovered point.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Write the after-target marker

Type this at postgres=#. Do not type the prompt itself.

```sql
INSERT INTO academy_proof VALUES (5, 'after_target');
```

This committed record must be excluded by the selected earlier recovery target.

INSERT 0 1

### Switch WAL

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_switch_wal();
```

Complete the current WAL segment so the archiver can deliver it. This alone does not prove repository delivery.

A WAL location is returned.

### Read both sides of the boundary

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

The source retains all five markers.

Rows1 through5 are present.

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

## Prove the recovery-target WAL is archived

Do not begin recovery until the needed WAL reaches the repositories.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Check every repository

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy check
```

Read each configured repository’s WAL delivery result.

All configured repositories complete the WAL check successfully.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated direct-safe restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated direct-safe restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-direct-safe-repo1.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-direct-safe-repo1.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-direct-safe-repo1
[global]
log-level-console=info
process-max=2
repo1-path=/var/lib/pgbackrest/direct
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-direct-safe-repo1.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-direct-safe-repo1.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-direct-safe-repo1.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-direct-safe-repo1
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-direct-safe-repo1
```

Only . and .. appear.

## Restore the direct-safe backup

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
pgbackrest --config=/etc/pgbackrest/restore-direct-safe-repo1.conf --stanza=academy --repo=1 --archive-mode=off --type=name --target="academy_safe" --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to the recorded target. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-direct-safe-repo1/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-direct-safe-repo1/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-direct-safe-repo1/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-direct-safe-repo1'
port = 55433
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-direct-safe-repo1/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-direct-safe-repo1/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-direct-safe-repo1/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-direct-safe-repo1/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated direct-safe recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-direct-safe-repo1 -l /var/lib/pgsql/restore-direct-safe-repo1/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55433
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

## Accept the recovered direct-safe data

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55433
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55433.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-direct-safe-repo1

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

Rows1,2,3 and4 are present. Row5 is absent.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-direct-safe-repo1 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-direct-safe-repo1/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated server-time restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated server-time restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-server-time-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-server-time-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-server-time-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-server-time-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-server-time-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-server-time-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-server-time-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-server-time-repo2
```

Only . and .. appear.

## Restore the server-time backup

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
pgbackrest --config=/etc/pgbackrest/restore-server-time-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=time --target="{{recovery_target_time}}" --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to the recorded target. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-server-time-repo2/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-server-time-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-server-time-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-server-time-repo2'
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
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-server-time-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-server-time-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-server-time-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-server-time-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated server-time recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-server-time-repo2 -l /var/lib/pgsql/restore-server-time-repo2/startup.log -t 40 -w start
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

## Accept the recovered server-time data

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

/var/lib/pgsql/restore-server-time-repo2

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

Rows1,2,3 and4 are present. Row5 is absent.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-server-time-repo2 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-server-time-repo2/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated s3-safe restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated s3-safe restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-s3-safe-repo3.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-s3-safe-repo3.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-s3-safe-repo3
[global]
log-level-console=info
process-max=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
repo3-host=backup-1
repo3-host-user=pgbackrest
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-s3-safe-repo3.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-s3-safe-repo3.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-s3-safe-repo3.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-s3-safe-repo3
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-s3-safe-repo3
```

Only . and .. appear.

## Restore the s3-safe backup

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
pgbackrest --config=/etc/pgbackrest/restore-s3-safe-repo3.conf --stanza=academy --repo=3 --archive-mode=off --type=name --target="academy_safe" --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to the recorded target. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-s3-safe-repo3/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-s3-safe-repo3/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-s3-safe-repo3/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-s3-safe-repo3'
port = 55435
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-s3-safe-repo3/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-s3-safe-repo3/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-s3-safe-repo3/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-s3-safe-repo3/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated s3-safe recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-s3-safe-repo3 -l /var/lib/pgsql/restore-s3-safe-repo3/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55435
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

## Accept the recovered s3-safe data

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55435
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55435.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-s3-safe-repo3

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

Rows1,2,3 and4 are present. Row5 is absent.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-s3-safe-repo3 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-s3-safe-repo3/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Read direct backup metadata

Inspect the most recent completed backup and its WAL boundaries.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Inspect the repository

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy --repo=1 info
```

Read the backup type, label, start/stop times, repository size and WAL range. Backup success does not establish the result of a restore.

The expected recent backup chain is listed.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Inspect direct repository usage

Measure repository usage and free filesystem space separately.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Measure repository usage

Type this in the postgres Linux shell on pg-primary.

```bash
du -sh /var/lib/pgbackrest/direct
```

Read the size of files under this repository.

A human-readable repository size appears.

### Read free filesystem space

Type this in the postgres Linux shell on pg-primary.

```bash
df -h /var/lib/pgbackrest/direct
```

Check the mounted filesystem’s capacity and available space.

Read Size, Used, Avail and Use% for the NFS filesystem.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Read server backup metadata

Inspect the most recent completed backup and its WAL boundaries.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Inspect the repository

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Read the backup type, label, start/stop times, repository size and WAL range. Backup success does not establish the result of a restore.

The expected recent backup chain is listed.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Inspect server repository usage

Measure repository usage and free filesystem space separately.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Measure repository usage

Type this in the pgbackrest Linux shell on backup-1.

```bash
du -sh /var/lib/pgbackrest/server
```

Read the size of files under this repository.

A human-readable repository size appears.

### Read free filesystem space

Type this in the pgbackrest Linux shell on backup-1.

```bash
df -h /var/lib/pgbackrest/server
```

Check the mounted filesystem’s capacity and available space.

Read Size, Used, Avail and Use% for the NFS filesystem.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Read s3 backup metadata

Inspect the most recent completed backup and its WAL boundaries.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Inspect the repository

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=3 info
```

Read the backup type, label, start/stop times, repository size and WAL range. Backup success does not establish the result of a restore.

The expected recent backup chain is listed.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Read the pgBackRest execution history

A historical ERROR may remain in a log after a later successful job. Correlate the current execution.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Read recent backup messages

Type this in the pgbackrest Linux shell on backup-1.

```bash
tail -n 80 /var/log/pgbackrest/academy-backup.log
```

Locate command begin, its exec-id, relevant warning/error lines and the matching command end.

Use one execution’s timestamps and exec-id together.

### Locate execution boundaries

Type this in the pgbackrest Linux shell on backup-1.

```bash
grep -n -e "command begin" -e "ERROR:" -e "command end" /var/log/pgbackrest/academy-backup.log
```

One grep command selects relevant lines without a shell pipeline. Old errors do not automatically describe the latest job.

Identify the latest command’s beginning and result before drawing a conclusion.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Read PostgreSQL archive and recovery messages

Choose the database log when the problem concerns PostgreSQL archiving, replay or startup.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Read the database log

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 45 /var/lib/pgsql/16/data/log/postgresql.log
```

Read timestamps, process IDs, severity and the messages around an archive or recovery event. A severity word alone is not a diagnosis.

Connect the current message to its component and the next independent check.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Inspect PostgreSQL archiver counters

Compare the most recent success and failure timestamps. failed_count is cumulative and can remain nonzero after repair.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Inspect PostgreSQL archiver counters

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT archived_count,last_archived_wal,last_archived_time,failed_count,last_failed_wal,last_failed_time FROM pg_stat_archiver;
```

Compare the most recent success and failure timestamps. failed_count is cumulative and can remain nonzero after repair.

A current successful archive is visible. An older failed count alone does not establish a current failure.

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

## Inspect the standby replay position

Received WAL and replayed WAL are different positions. A quiet database makes time-since-last-replay an incomplete lag measure.

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

### Inspect the standby replay position

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_last_wal_receive_lsn(),pg_last_wal_replay_lsn(),pg_is_wal_replay_paused();
```

Received WAL and replayed WAL are different positions. A quiet database makes time-since-last-replay an incomplete lag measure.

Read both WAL positions and confirm replay is not paused.

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

## Create a second full set before the retention comparison

Take a full backup using the explicit executing role and repository.

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
pgbackrest --stanza=academy --repo=2 --type=full --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new full backup is recorded for academy.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Inspect retained chains before another full backup

Retention applies to full sets and their dependent backups. Do not delete individual backup files.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Read the existing sets

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Record the retained full labels and their dependent differential/incremental backups.

Record which full set is oldest.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Create a new full set under the retention policy

Take a full backup using the explicit executing role and repository.

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
pgbackrest --stanza=academy --repo=2 --type=full --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new full backup is recorded for academy.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Inspect the retained sets after expiration

A successful new full backup may expire the oldest full set under repo2-retention-full=2.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Read the retained chains

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Compare the labels with the earlier observation. With at least three full sets created, only the newest two full sets remain.

The configured retention count is satisfied and required dependencies remain.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated retention-latest restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated retention-latest restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-retention-latest-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-retention-latest-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-retention-latest-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-retention-latest-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-retention-latest-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-retention-latest-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-retention-latest-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-retention-latest-repo2
```

Only . and .. appear.

## Restore the retention-latest backup

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
pgbackrest --config=/etc/pgbackrest/restore-retention-latest-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-retention-latest-repo2/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-retention-latest-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-retention-latest-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-retention-latest-repo2'
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
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-retention-latest-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-retention-latest-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-retention-latest-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-retention-latest-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated retention-latest recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-retention-latest-repo2 -l /var/lib/pgsql/restore-retention-latest-repo2/startup.log -t 40 -w start
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

## Accept the recovered retention-latest data

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

/var/lib/pgsql/restore-retention-latest-repo2

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

Rows1 through5 are present in the new full set.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-retention-latest-repo2 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-retention-latest-repo2/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Install cron

Use the requested crontab scheduler.

On pg-primary as ec2-user.

### Install cron

Use the Linux terminal.

```bash
sudo dnf -y install cronie
```

Install the CentOS cron daemon and crontab client.

cronie is installed.

### Check

```bash
rpm -q cronie
```

cronie is installed.

## Enable cron at boot

Scheduling must survive a reboot.

On pg-primary as ec2-user.

### Enable cron at boot

Use the Linux terminal.

```bash
sudo systemctl enable crond
```

Enable the cron service.

crond is enabled.

### Check

```bash
systemctl is-enabled crond
```

crond is enabled.

## Start cron

A crontab cannot run without the scheduler.

On pg-primary as ec2-user.

### Start cron

Use the Linux terminal.

```bash
sudo systemctl start crond
```

Start the daemon now.

crond is active.

### Check

```bash
systemctl is-active crond
```

crond is active.

## Create the job program directory

Keep the reviewed scheduler wrapper in a known path.

On pg-primary as ec2-user.

### Create the job program directory

Use the Linux terminal.

```bash
sudo install -d -m 755 /opt/suta-pgbackrest
```

Create the program directory.

The directory exists.

### Check

```bash
ls -ld /opt/suta-pgbackrest
```

The directory exists.

## Install the reviewed backup-job.py

The manual pgBackRest commands came first. This readable wrapper adds job locking, result metadata, logs, failure alerts and retry; it does not turn a failed backup into success.

On pg-primary as ec2-user.

### Install the reviewed backup-job.py

Use the Linux terminal.

```bash
sudo cp /opt/suta/artifacts/backup-job.py /opt/suta-pgbackrest/backup-job.py
```

Copy the versioned script staged by Ansible. Its source is available for inspection.

The script is installed.

### Check

```bash
sudo cmp /opt/suta/artifacts/backup-job.py /opt/suta-pgbackrest/backup-job.py
```

No difference is reported.

## Set permissions for backup-job.py

Allow the service account to read and execute the reviewed program.

On pg-primary as ec2-user.

### Set permissions for backup-job.py

Use the Linux terminal.

```bash
sudo chmod 755 /opt/suta-pgbackrest/backup-job.py
```

Set the executable file permissions.

The mode is755.

### Check

```bash
stat -c "%U:%G %a %n" /opt/suta-pgbackrest/backup-job.py
```

The mode is755.

## Install the reviewed alert-sink.py

The manual pgBackRest commands came first. This readable wrapper adds job locking, result metadata, logs, failure alerts and retry; it does not turn a failed backup into success.

On pg-primary as ec2-user.

### Install the reviewed alert-sink.py

Use the Linux terminal.

```bash
sudo cp /opt/suta/artifacts/alert-sink.py /opt/suta-pgbackrest/alert-sink.py
```

Copy the versioned script staged by Ansible. Its source is available for inspection.

The script is installed.

### Check

```bash
sudo cmp /opt/suta/artifacts/alert-sink.py /opt/suta-pgbackrest/alert-sink.py
```

No difference is reported.

## Set permissions for alert-sink.py

Allow the service account to read and execute the reviewed program.

On pg-primary as ec2-user.

### Set permissions for alert-sink.py

Use the Linux terminal.

```bash
sudo chmod 755 /opt/suta-pgbackrest/alert-sink.py
```

Set the executable file permissions.

The mode is755.

### Check

```bash
stat -c "%U:%G %a %n" /opt/suta-pgbackrest/alert-sink.py
```

The mode is755.

## Prepare private job state

The wrapper records each attempt, successful backup and pending notification.

On pg-primary as ec2-user.

### Prepare private job state

Use the Linux terminal.

```bash
sudo install -d -m 750 -o postgres -g postgres /var/lib/suta-backup-jobs
```

Create the state parent for the executing account.

The parent belongs to postgres.

### Check

```bash
ls -ld /var/lib/suta-backup-jobs
```

The parent belongs to postgres.

## Prepare the local alert receiver state

This lab proves SMTP and HTTP delivery to a local test receiver. It does not claim external mailbox or Slack delivery.

On pg-primary as ec2-user.

### Prepare the local alert receiver state

Use the Linux terminal.

```bash
sudo install -d -m 700 -o ec2-user -g ec2-user /var/lib/suta-alert-test
```

Create private receiver state owned by the test service account.

The directory is private and belongs to ec2-user.

### Check

```bash
stat -c "%U:%G %a %n" /var/lib/suta-alert-test
```

The directory is private and belongs to ec2-user.

## Configure the local notification test receiver

The receiver binds loopback addresses only and records test receipts. External providers require their own authorized destinations and delivery verification. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Configure the local notification test receiver

Use the Linux terminal.

```bash
sudo vi /etc/systemd/system/suta-alert-test.service
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/systemd/system/suta-alert-test.service.

### File contents

```text
[Unit]
Description=Loopback-only synthetic alert test receiver
[Service]
User=ec2-user
ExecStart=/usr/bin/python3 /opt/suta-pgbackrest/alert-sink.py
Restart=on-failure
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/systemd/system/suta-alert-test.service
```

The exact file path is present. The following service checks establish whether its settings work.

## Reload the receiver unit

Load the saved systemd service definition.

On pg-primary as ec2-user.

### Reload the receiver unit

Use the Linux terminal.

```bash
sudo systemctl daemon-reload
```

Reload unit definitions.

The unit parses.

### Check

```bash
systemd-analyze verify /etc/systemd/system/suta-alert-test.service
```

The unit parses.

## Start the local receiver

Start the test receiver before exercising failure notifications.

On pg-primary as ec2-user.

### Start the local receiver

Use the Linux terminal.

```bash
sudo systemctl start suta-alert-test
```

Start the loopback service.

The test receiver is active.

### Check

```bash
systemctl is-active suta-alert-test
```

The test receiver is active.

## Install cron

Use the requested crontab scheduler.

On backup-1 as ec2-user.

### Install cron

Use the Linux terminal.

```bash
sudo dnf -y install cronie
```

Install the CentOS cron daemon and crontab client.

cronie is installed.

### Check

```bash
rpm -q cronie
```

cronie is installed.

## Enable cron at boot

Scheduling must survive a reboot.

On backup-1 as ec2-user.

### Enable cron at boot

Use the Linux terminal.

```bash
sudo systemctl enable crond
```

Enable the cron service.

crond is enabled.

### Check

```bash
systemctl is-enabled crond
```

crond is enabled.

## Start cron

A crontab cannot run without the scheduler.

On backup-1 as ec2-user.

### Start cron

Use the Linux terminal.

```bash
sudo systemctl start crond
```

Start the daemon now.

crond is active.

### Check

```bash
systemctl is-active crond
```

crond is active.

## Create the job program directory

Keep the reviewed scheduler wrapper in a known path.

On backup-1 as ec2-user.

### Create the job program directory

Use the Linux terminal.

```bash
sudo install -d -m 755 /opt/suta-pgbackrest
```

Create the program directory.

The directory exists.

### Check

```bash
ls -ld /opt/suta-pgbackrest
```

The directory exists.

## Install the reviewed backup-job.py

The manual pgBackRest commands came first. This readable wrapper adds job locking, result metadata, logs, failure alerts and retry; it does not turn a failed backup into success.

On backup-1 as ec2-user.

### Install the reviewed backup-job.py

Use the Linux terminal.

```bash
sudo cp /opt/suta/artifacts/backup-job.py /opt/suta-pgbackrest/backup-job.py
```

Copy the versioned script staged by Ansible. Its source is available for inspection.

The script is installed.

### Check

```bash
sudo cmp /opt/suta/artifacts/backup-job.py /opt/suta-pgbackrest/backup-job.py
```

No difference is reported.

## Set permissions for backup-job.py

Allow the service account to read and execute the reviewed program.

On backup-1 as ec2-user.

### Set permissions for backup-job.py

Use the Linux terminal.

```bash
sudo chmod 755 /opt/suta-pgbackrest/backup-job.py
```

Set the executable file permissions.

The mode is755.

### Check

```bash
stat -c "%U:%G %a %n" /opt/suta-pgbackrest/backup-job.py
```

The mode is755.

## Install the reviewed alert-sink.py

The manual pgBackRest commands came first. This readable wrapper adds job locking, result metadata, logs, failure alerts and retry; it does not turn a failed backup into success.

On backup-1 as ec2-user.

### Install the reviewed alert-sink.py

Use the Linux terminal.

```bash
sudo cp /opt/suta/artifacts/alert-sink.py /opt/suta-pgbackrest/alert-sink.py
```

Copy the versioned script staged by Ansible. Its source is available for inspection.

The script is installed.

### Check

```bash
sudo cmp /opt/suta/artifacts/alert-sink.py /opt/suta-pgbackrest/alert-sink.py
```

No difference is reported.

## Set permissions for alert-sink.py

Allow the service account to read and execute the reviewed program.

On backup-1 as ec2-user.

### Set permissions for alert-sink.py

Use the Linux terminal.

```bash
sudo chmod 755 /opt/suta-pgbackrest/alert-sink.py
```

Set the executable file permissions.

The mode is755.

### Check

```bash
stat -c "%U:%G %a %n" /opt/suta-pgbackrest/alert-sink.py
```

The mode is755.

## Prepare private job state

The wrapper records each attempt, successful backup and pending notification.

On backup-1 as ec2-user.

### Prepare private job state

Use the Linux terminal.

```bash
sudo install -d -m 750 -o pgbackrest -g pgbackrest /var/lib/suta-backup-jobs
```

Create the state parent for the executing account.

The parent belongs to pgbackrest.

### Check

```bash
ls -ld /var/lib/suta-backup-jobs
```

The parent belongs to pgbackrest.

## Prepare the local alert receiver state

This lab proves SMTP and HTTP delivery to a local test receiver. It does not claim external mailbox or Slack delivery.

On backup-1 as ec2-user.

### Prepare the local alert receiver state

Use the Linux terminal.

```bash
sudo install -d -m 700 -o ec2-user -g ec2-user /var/lib/suta-alert-test
```

Create private receiver state owned by the test service account.

The directory is private and belongs to ec2-user.

### Check

```bash
stat -c "%U:%G %a %n" /var/lib/suta-alert-test
```

The directory is private and belongs to ec2-user.

## Configure the local notification test receiver

The receiver binds loopback addresses only and records test receipts. External providers require their own authorized destinations and delivery verification. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Configure the local notification test receiver

Use the Linux terminal.

```bash
sudo vi /etc/systemd/system/suta-alert-test.service
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/systemd/system/suta-alert-test.service.

### File contents

```text
[Unit]
Description=Loopback-only synthetic alert test receiver
[Service]
User=ec2-user
ExecStart=/usr/bin/python3 /opt/suta-pgbackrest/alert-sink.py
Restart=on-failure
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/systemd/system/suta-alert-test.service
```

The exact file path is present. The following service checks establish whether its settings work.

## Reload the receiver unit

Load the saved systemd service definition.

On backup-1 as ec2-user.

### Reload the receiver unit

Use the Linux terminal.

```bash
sudo systemctl daemon-reload
```

Reload unit definitions.

The unit parses.

### Check

```bash
systemd-analyze verify /etc/systemd/system/suta-alert-test.service
```

The unit parses.

## Start the local receiver

Start the test receiver before exercising failure notifications.

On backup-1 as ec2-user.

### Start the local receiver

Use the Linux terminal.

```bash
sudo systemctl start suta-alert-test
```

Start the loopback service.

The test receiver is active.

### Check

```bash
systemctl is-active suta-alert-test
```

The test receiver is active.

## Configure the direct scheduled job

The wrapper checks this repository, prevents overlap, retains job logs and verifies fresh backup metadata. A180-second timeout and seven-hour freshness threshold are lab values, not universal production settings. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Configure the direct scheduled job

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/job-direct.json
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/job-direct.json.

### File contents

```text
{
  "name": "direct",
  "repo": 1,
  "profile": "/etc/pgbackrest/direct.conf",
  "stanza": "academy",
  "state_dir": "/var/lib/suta-backup-jobs/direct",
  "timeout_seconds": 180,
  "max_backup_age_seconds": 25200,
  "alerts": [
    {
      "kind": "webhook",
      "url": "http://127.0.0.1:9009/events"
    },
    {
      "kind": "email",
      "host": "127.0.0.1",
      "port": 1025,
      "from": "backup@suta.invalid",
      "to": "training@suta.invalid"
    }
  ],
  "mount_path": "/var/lib/pgbackrest/direct"
}
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/job-direct.json
```

The exact file path is present. The following service checks establish whether its settings work.

## Allow the service group to read the job configuration

The service needs the reviewed job configuration.

On pg-primary as ec2-user.

### Allow the service group to read the job configuration

Use the Linux terminal.

```bash
sudo chown root:postgres /etc/pgbackrest/job-direct.json
```

Keep root ownership and assign the service group.

The file has root:postgres ownership.

### Check

```bash
stat -c "%U:%G %a %n" /etc/pgbackrest/job-direct.json
```

The file has root:postgres ownership.

## Restrict job configuration permissions

Restrict read access to the service group.

On pg-primary as ec2-user.

### Restrict job configuration permissions

Use the Linux terminal.

```bash
sudo chmod 640 /etc/pgbackrest/job-direct.json
```

Set mode640.

The mode is640.

### Check

```bash
stat -c "%U:%G %a %n" /etc/pgbackrest/job-direct.json
```

The mode is640.

## Create private direct job state

Keep attempt records, locks and pending notifications under the service account.

On pg-primary as ec2-user.

### Create private direct job state

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/suta-backup-jobs/direct
```

Create the private per-repository state directory.

The directory has the intended service owner and mode700.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/suta-backup-jobs/direct
```

The directory has the intended service owner and mode700.

## Run the direct full job manually first

Verify the exact program that cron will execute before scheduling it.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Run the reviewed job

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-direct.json full
```

The wrapper serializes this repository’s backup, runs pgBackRest and verifies new clean metadata. Read its backup_exit_code and backup_label.

The event is backup-succeeded with backup_exit_code0 and a new backup_label.

### Read the last attempt

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/suta-backup-jobs/direct/last-attempt.json
```

Correlate job_id, backup type, start/finish timestamps, exit code, log_path and exec_ids.

The last attempt matches the job you just ran.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Run the direct diff job manually first

Verify the exact program that cron will execute before scheduling it.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Run the reviewed job

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-direct.json diff
```

The wrapper serializes this repository’s backup, runs pgBackRest and verifies new clean metadata. Read its backup_exit_code and backup_label.

The event is backup-succeeded with backup_exit_code0 and a new backup_label.

### Read the last attempt

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/suta-backup-jobs/direct/last-attempt.json
```

Correlate job_id, backup type, start/finish timestamps, exit code, log_path and exec_ids.

The last attempt matches the job you just ran.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Run the direct incr job manually first

Verify the exact program that cron will execute before scheduling it.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Run the reviewed job

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-direct.json incr
```

The wrapper serializes this repository’s backup, runs pgBackRest and verifies new clean metadata. Read its backup_exit_code and backup_label.

The event is backup-succeeded with backup_exit_code0 and a new backup_label.

### Read the last attempt

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/suta-backup-jobs/direct/last-attempt.json
```

Correlate job_id, backup type, start/finish timestamps, exit code, log_path and exec_ids.

The last attempt matches the job you just ran.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Configure the server scheduled job

The wrapper checks this repository, prevents overlap, retains job logs and verifies fresh backup metadata. A180-second timeout and seven-hour freshness threshold are lab values, not universal production settings. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Configure the server scheduled job

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/job-server.json
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/job-server.json.

### File contents

```text
{
  "name": "server",
  "repo": 2,
  "profile": "/etc/pgbackrest/pgbackrest.conf",
  "stanza": "academy",
  "state_dir": "/var/lib/suta-backup-jobs/server",
  "timeout_seconds": 180,
  "max_backup_age_seconds": 25200,
  "alerts": [
    {
      "kind": "webhook",
      "url": "http://127.0.0.1:9009/events"
    },
    {
      "kind": "email",
      "host": "127.0.0.1",
      "port": 1025,
      "from": "backup@suta.invalid",
      "to": "training@suta.invalid"
    }
  ],
  "mount_path": "/var/lib/pgbackrest/server"
}
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/job-server.json
```

The exact file path is present. The following service checks establish whether its settings work.

## Allow the service group to read the job configuration

The service needs the reviewed job configuration.

On backup-1 as ec2-user.

### Allow the service group to read the job configuration

Use the Linux terminal.

```bash
sudo chown root:pgbackrest /etc/pgbackrest/job-server.json
```

Keep root ownership and assign the service group.

The file has root:pgbackrest ownership.

### Check

```bash
stat -c "%U:%G %a %n" /etc/pgbackrest/job-server.json
```

The file has root:pgbackrest ownership.

## Restrict job configuration permissions

Restrict read access to the service group.

On backup-1 as ec2-user.

### Restrict job configuration permissions

Use the Linux terminal.

```bash
sudo chmod 640 /etc/pgbackrest/job-server.json
```

Set mode640.

The mode is640.

### Check

```bash
stat -c "%U:%G %a %n" /etc/pgbackrest/job-server.json
```

The mode is640.

## Create private server job state

Keep attempt records, locks and pending notifications under the service account.

On backup-1 as ec2-user.

### Create private server job state

Use the Linux terminal.

```bash
sudo install -d -m 700 -o pgbackrest -g pgbackrest /var/lib/suta-backup-jobs/server
```

Create the private per-repository state directory.

The directory has the intended service owner and mode700.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/suta-backup-jobs/server
```

The directory has the intended service owner and mode700.

## Run the server full job manually first

Verify the exact program that cron will execute before scheduling it.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the reviewed job

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json full
```

The wrapper serializes this repository’s backup, runs pgBackRest and verifies new clean metadata. Read its backup_exit_code and backup_label.

The event is backup-succeeded with backup_exit_code0 and a new backup_label.

### Read the last attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/server/last-attempt.json
```

Correlate job_id, backup type, start/finish timestamps, exit code, log_path and exec_ids.

The last attempt matches the job you just ran.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Run the server diff job manually first

Verify the exact program that cron will execute before scheduling it.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the reviewed job

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json diff
```

The wrapper serializes this repository’s backup, runs pgBackRest and verifies new clean metadata. Read its backup_exit_code and backup_label.

The event is backup-succeeded with backup_exit_code0 and a new backup_label.

### Read the last attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/server/last-attempt.json
```

Correlate job_id, backup type, start/finish timestamps, exit code, log_path and exec_ids.

The last attempt matches the job you just ran.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Run the server incr job manually first

Verify the exact program that cron will execute before scheduling it.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the reviewed job

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json incr
```

The wrapper serializes this repository’s backup, runs pgBackRest and verifies new clean metadata. Read its backup_exit_code and backup_label.

The event is backup-succeeded with backup_exit_code0 and a new backup_label.

### Read the last attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/server/last-attempt.json
```

Correlate job_id, backup type, start/finish timestamps, exit code, log_path and exec_ids.

The last attempt matches the job you just ran.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Configure the s3 scheduled job

The wrapper checks this repository, prevents overlap, retains job logs and verifies fresh backup metadata. A180-second timeout and seven-hour freshness threshold are lab values, not universal production settings. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Configure the s3 scheduled job

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/job-s3.json
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/job-s3.json.

### File contents

```text
{
  "name": "s3",
  "repo": 3,
  "profile": "/etc/pgbackrest/pgbackrest.conf",
  "stanza": "academy",
  "state_dir": "/var/lib/suta-backup-jobs/s3",
  "timeout_seconds": 180,
  "max_backup_age_seconds": 25200,
  "alerts": [
    {
      "kind": "webhook",
      "url": "http://127.0.0.1:9009/events"
    },
    {
      "kind": "email",
      "host": "127.0.0.1",
      "port": 1025,
      "from": "backup@suta.invalid",
      "to": "training@suta.invalid"
    }
  ]
}
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/job-s3.json
```

The exact file path is present. The following service checks establish whether its settings work.

## Allow the service group to read the job configuration

The service needs the reviewed job configuration.

On backup-1 as ec2-user.

### Allow the service group to read the job configuration

Use the Linux terminal.

```bash
sudo chown root:pgbackrest /etc/pgbackrest/job-s3.json
```

Keep root ownership and assign the service group.

The file has root:pgbackrest ownership.

### Check

```bash
stat -c "%U:%G %a %n" /etc/pgbackrest/job-s3.json
```

The file has root:pgbackrest ownership.

## Restrict job configuration permissions

Restrict read access to the service group.

On backup-1 as ec2-user.

### Restrict job configuration permissions

Use the Linux terminal.

```bash
sudo chmod 640 /etc/pgbackrest/job-s3.json
```

Set mode640.

The mode is640.

### Check

```bash
stat -c "%U:%G %a %n" /etc/pgbackrest/job-s3.json
```

The mode is640.

## Create private s3 job state

Keep attempt records, locks and pending notifications under the service account.

On backup-1 as ec2-user.

### Create private s3 job state

Use the Linux terminal.

```bash
sudo install -d -m 700 -o pgbackrest -g pgbackrest /var/lib/suta-backup-jobs/s3
```

Create the private per-repository state directory.

The directory has the intended service owner and mode700.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/suta-backup-jobs/s3
```

The directory has the intended service owner and mode700.

## Run the s3 full job manually first

Verify the exact program that cron will execute before scheduling it.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the reviewed job

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json full
```

The wrapper serializes this repository’s backup, runs pgBackRest and verifies new clean metadata. Read its backup_exit_code and backup_label.

The event is backup-succeeded with backup_exit_code0 and a new backup_label.

### Read the last attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/s3/last-attempt.json
```

Correlate job_id, backup type, start/finish timestamps, exit code, log_path and exec_ids.

The last attempt matches the job you just ran.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Run the s3 diff job manually first

Verify the exact program that cron will execute before scheduling it.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the reviewed job

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json diff
```

The wrapper serializes this repository’s backup, runs pgBackRest and verifies new clean metadata. Read its backup_exit_code and backup_label.

The event is backup-succeeded with backup_exit_code0 and a new backup_label.

### Read the last attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/s3/last-attempt.json
```

Correlate job_id, backup type, start/finish timestamps, exit code, log_path and exec_ids.

The last attempt matches the job you just ran.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Run the s3 incr job manually first

Verify the exact program that cron will execute before scheduling it.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the reviewed job

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json incr
```

The wrapper serializes this repository’s backup, runs pgBackRest and verifies new clean metadata. Read its backup_exit_code and backup_label.

The event is backup-succeeded with backup_exit_code0 and a new backup_label.

### Read the last attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/s3/last-attempt.json
```

Correlate job_id, backup type, start/finish timestamps, exit code, log_path and exec_ids.

The last attempt matches the job you just ran.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the direct UTC schedule

The five fields are minute, hour, day of month, month and day of week. Sunday0 runs full; Monday–Saturday run differential; three daily times run incremental. Jobs on backup-1 are staggered by repository. Freshness checks and alert retries have separate short intervals. Use cron alone; do not enable duplicate systemd backup timers. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the direct UTC schedule

Use the Linux terminal.

```bash
sudo vi /tmp/pgbackrest-crontab
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /tmp/pgbackrest-crontab.

### File contents

```text
CRON_TZ=UTC
SHELL=/bin/bash
PATH=/usr/pgsql-16/bin:/usr/bin:/bin
MAILTO=""
0 2 * * 0 /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-direct.json full >> /var/lib/suta-backup-jobs/direct/scheduler.log 2>&1
0 2 * * 1-6 /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-direct.json diff >> /var/lib/suta-backup-jobs/direct/scheduler.log 2>&1
0 8,14,20 * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-direct.json incr >> /var/lib/suta-backup-jobs/direct/scheduler.log 2>&1
*/5 * * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-direct.json health >> /var/lib/suta-backup-jobs/direct/scheduler.log 2>&1
*/2 * * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-direct.json retry-alerts >> /var/lib/suta-backup-jobs/direct/scheduler.log 2>&1
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /tmp/pgbackrest-crontab
```

The exact file path is present. The following service checks establish whether its settings work.

## Install the direct service-account crontab

Install this schedule for the account that owns the repository process.

On pg-primary as ec2-user.

### Install the direct service-account crontab

Use the Linux terminal.

```bash
sudo crontab -u postgres /tmp/pgbackrest-crontab
```

crontab -u selects the operating-system user. Installing a schedule does not establish that a job has run.

The service account has the intended schedule.

### Check

```bash
sudo crontab -u postgres -l
```

Check every time, weekday and absolute program/configuration path.

## Write a temporary one-minute schedule

This bounded lab test runs one incremental per repository each minute. The regular schedule remains saved in /tmp/pgbackrest-crontab. Restore it after observing the first new successful attempt; do not leave the one-minute schedule installed. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write a temporary one-minute schedule

Use the Linux terminal.

```bash
sudo vi /tmp/pgbackrest-cron-test
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /tmp/pgbackrest-cron-test.

### File contents

```text
CRON_TZ=UTC
SHELL=/bin/bash
PATH=/usr/pgsql-16/bin:/usr/bin:/bin
MAILTO=""
* * * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-direct.json incr >> /var/lib/suta-backup-jobs/direct/scheduler.log 2>&1
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /tmp/pgbackrest-cron-test
```

The exact file path is present. The following service checks establish whether its settings work.

## Record when this scheduler test begins

A previous manual success cannot prove this scheduled run. Record this UTC time for comparison with started_epoch in the new attempt.

On pg-primary as ec2-user.

### Record when this scheduler test begins

Use the Linux terminal.

```bash
date -u +%s
```

Print UTC time as seconds since 1970. The attempt record uses the same numeric format.

Keep this timestamp while checking the next attempt.

## Install the temporary schedule

Cron will launch the job at the next minute boundary. Wait for that boundary and for the backup to finish.

On pg-primary as ec2-user.

### Install the temporary schedule

Use the Linux terminal.

```bash
sudo crontab -u postgres /tmp/pgbackrest-cron-test
```

Install the test crontab for the repository service account.

The temporary table contains the one-minute incremental job.

### Check

```bash
sudo crontab -u postgres -l
```

The temporary table contains the one-minute incremental job.

## Confirm a new scheduled direct backup

Prove a fresh cron execution. Read started_epoch: it must be later than the UTC time just recorded. If the record is older, wait for the next minute and repeat this check. A manual backup would not prove cron ran.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Read the new attempt

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/suta-backup-jobs/direct/last-attempt.json
```

Compare started_epoch, finished_epoch, backup_type, backup_exit_code, backup_label and job_id. Read again if the old manual attempt is still shown.

A new incr attempt started after the test was installed, finished with backup_exit_code 0, and recorded a new backup_label.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Correlate the attempt with cron execution

Match the new attempt with the scheduled command and timestamp. Then restore the regular table in the next step.

On pg-primary as ec2-user.

### Correlate the attempt with cron execution

Use the Linux terminal.

```bash
sudo journalctl -t CROND --since "20 minutes ago" -o short-iso --no-pager -n 60
```

journalctl reads the cron daemon’s execution records with timestamps. A CMD record proves launch, not backup success.

Find the scheduled backup-job.py invocation, then inspect its new last-attempt record.

## Restore the regular backup schedule

End the frequent test schedule after recording proof. Keep the intended full, differential and incremental policy.

On pg-primary as ec2-user.

### Restore the regular backup schedule

Use the Linux terminal.

```bash
sudo crontab -u postgres /tmp/pgbackrest-crontab
```

Reinstall the regular schedule saved earlier.

No every-minute incremental backup remains in the table.

### Check

```bash
sudo crontab -u postgres -l
```

No every-minute incremental backup remains in the table.

## Write the server UTC schedule

The five fields are minute, hour, day of month, month and day of week. Sunday0 runs full; Monday–Saturday run differential; three daily times run incremental. Jobs on backup-1 are staggered by repository. Freshness checks and alert retries have separate short intervals. Use cron alone; do not enable duplicate systemd backup timers. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Write the server UTC schedule

Use the Linux terminal.

```bash
sudo vi /tmp/pgbackrest-crontab
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /tmp/pgbackrest-crontab.

### File contents

```text
CRON_TZ=UTC
SHELL=/bin/bash
PATH=/usr/pgsql-16/bin:/usr/bin:/bin
MAILTO=""
0 3 * * 0 /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json full >> /var/lib/suta-backup-jobs/server/scheduler.log 2>&1
0 3 * * 1-6 /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json diff >> /var/lib/suta-backup-jobs/server/scheduler.log 2>&1
0 9,15,21 * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json incr >> /var/lib/suta-backup-jobs/server/scheduler.log 2>&1
*/5 * * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json health >> /var/lib/suta-backup-jobs/server/scheduler.log 2>&1
*/2 * * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json retry-alerts >> /var/lib/suta-backup-jobs/server/scheduler.log 2>&1
0 4 * * 0 /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json full >> /var/lib/suta-backup-jobs/s3/scheduler.log 2>&1
0 4 * * 1-6 /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json diff >> /var/lib/suta-backup-jobs/s3/scheduler.log 2>&1
0 10,16,22 * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json incr >> /var/lib/suta-backup-jobs/s3/scheduler.log 2>&1
*/5 * * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json health >> /var/lib/suta-backup-jobs/s3/scheduler.log 2>&1
*/2 * * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json retry-alerts >> /var/lib/suta-backup-jobs/s3/scheduler.log 2>&1
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /tmp/pgbackrest-crontab
```

The exact file path is present. The following service checks establish whether its settings work.

## Install the server service-account crontab

Install this schedule for the account that owns the repository process.

On backup-1 as ec2-user.

### Install the server service-account crontab

Use the Linux terminal.

```bash
sudo crontab -u pgbackrest /tmp/pgbackrest-crontab
```

crontab -u selects the operating-system user. Installing a schedule does not establish that a job has run.

The service account has the intended schedule.

### Check

```bash
sudo crontab -u pgbackrest -l
```

Check every time, weekday and absolute program/configuration path.

## Write a temporary one-minute schedule

This bounded lab test runs one incremental per repository each minute. The regular schedule remains saved in /tmp/pgbackrest-crontab. Restore it after observing the first new successful attempt; do not leave the one-minute schedule installed. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Write a temporary one-minute schedule

Use the Linux terminal.

```bash
sudo vi /tmp/pgbackrest-cron-test
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /tmp/pgbackrest-cron-test.

### File contents

```text
CRON_TZ=UTC
SHELL=/bin/bash
PATH=/usr/pgsql-16/bin:/usr/bin:/bin
MAILTO=""
* * * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json incr >> /var/lib/suta-backup-jobs/server/scheduler.log 2>&1
* * * * * /usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json incr >> /var/lib/suta-backup-jobs/s3/scheduler.log 2>&1
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /tmp/pgbackrest-cron-test
```

The exact file path is present. The following service checks establish whether its settings work.

## Record when this scheduler test begins

A previous manual success cannot prove this scheduled run. Record this UTC time for comparison with started_epoch in the new attempt.

On backup-1 as ec2-user.

### Record when this scheduler test begins

Use the Linux terminal.

```bash
date -u +%s
```

Print UTC time as seconds since 1970. The attempt record uses the same numeric format.

Keep this timestamp while checking the next attempt.

## Install the temporary schedule

Cron will launch the job at the next minute boundary. Wait for that boundary and for the backup to finish.

On backup-1 as ec2-user.

### Install the temporary schedule

Use the Linux terminal.

```bash
sudo crontab -u pgbackrest /tmp/pgbackrest-cron-test
```

Install the test crontab for the repository service account.

The temporary table contains the one-minute incremental job.

### Check

```bash
sudo crontab -u pgbackrest -l
```

The temporary table contains the one-minute incremental job.

## Confirm a new scheduled server backup

Prove a fresh cron execution. Read started_epoch: it must be later than the UTC time just recorded. If the record is older, wait for the next minute and repeat this check. A manual backup would not prove cron ran.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Read the new attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/server/last-attempt.json
```

Compare started_epoch, finished_epoch, backup_type, backup_exit_code, backup_label and job_id. Read again if the old manual attempt is still shown.

A new incr attempt started after the test was installed, finished with backup_exit_code 0, and recorded a new backup_label.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Confirm a new scheduled s3 backup

Prove a fresh cron execution. Read started_epoch: it must be later than the UTC time just recorded. If the record is older, wait for the next minute and repeat this check. A manual backup would not prove cron ran.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Read the new attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/s3/last-attempt.json
```

Compare started_epoch, finished_epoch, backup_type, backup_exit_code, backup_label and job_id. Read again if the old manual attempt is still shown.

A new incr attempt started after the test was installed, finished with backup_exit_code 0, and recorded a new backup_label.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Correlate the attempt with cron execution

Match the new attempt with the scheduled command and timestamp. Then restore the regular table in the next step.

On backup-1 as ec2-user.

### Correlate the attempt with cron execution

Use the Linux terminal.

```bash
sudo journalctl -t CROND --since "20 minutes ago" -o short-iso --no-pager -n 60
```

journalctl reads the cron daemon’s execution records with timestamps. A CMD record proves launch, not backup success.

Find the scheduled backup-job.py invocation, then inspect its new last-attempt record.

## Restore the regular backup schedule

End the frequent test schedule after recording proof. Keep the intended full, differential and incremental policy.

On backup-1 as ec2-user.

### Restore the regular backup schedule

Use the Linux terminal.

```bash
sudo crontab -u pgbackrest /tmp/pgbackrest-crontab
```

Reinstall the regular schedule saved earlier.

No every-minute incremental backup remains in the table.

### Check

```bash
sudo crontab -u pgbackrest -l
```

No every-minute incremental backup remains in the table.

## Correlate a scheduled attempt with its log

Use the wrapper’s job identity to find the current attempt before reading error history.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Read the latest attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/server/last-attempt.json
```

Read the exact job_id, start/finish time, backup_exit_code, backup_label, exec_ids and log_path.

Identify this attempt before consulting older log messages.

### List retained job logs

Type this in the pgbackrest Linux shell on backup-1.

```bash
ls -lt /var/lib/suta-backup-jobs/server/logs
```

The filenames include unique job IDs. Use the log_path recorded in last-attempt.json when opening a specific job log.

The current attempt’s file is present among retained historical jobs.

### Read the scheduler output

Type this in the pgbackrest Linux shell on backup-1.

```bash
tail -n 60 /var/lib/suta-backup-jobs/server/scheduler.log
```

Cron redirects this job’s output here. Compare the job_id and timestamps with last-attempt.json.

A successful current attempt remains distinct from older failed attempts.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Run the freshness and pending-alert check

A job that never ran cannot report its own failure, so check backup age independently.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Check freshness

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json health
```

The check verifies the latest attempt and successful-backup age, records health and sends a local alert on a transition to unhealthy.

healthy is true after a successful recent backup.

### Read the recorded health

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/server/health.json
```

Read the time of the check and its healthy boolean.

healthy is true for the newly protected lab.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Preserve the backup-server profile

Keep an exact rollback copy before experimenting.

On backup-1 as ec2-user.

### Preserve the backup-server profile

Use the Linux terminal.

```bash
sudo cp /etc/pgbackrest/pgbackrest.conf /etc/pgbackrest/pgbackrest.conf.before-tuning
```

Copy this file without changing the active configuration.

The rollback file exists.

### Check

```bash
sudo ls -l /etc/pgbackrest/pgbackrest.conf.before-tuning
```

The rollback file exists.

## Create a stable tuning dataset

Use the same small dataset for the comparisons and acknowledge that it compresses unusually well.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Create the tuning table

Type this at postgres=#. Do not type the prompt itself.

```sql
CREATE TABLE academy_tuning_payload AS SELECT i AS id, repeat(md5(i::text),128) AS payload FROM generate_series(1,20000) i;
```

Create twenty thousand deterministic rows. This is a teaching workload, not a production capacity benchmark.

SELECT 20000

### Count the tuning rows

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_tuning_payload;
```

Fix the dataset size before comparing settings.

20000

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

## Configure one worker

Change only this experiment’s variable in the executing backup server’s file. No PostgreSQL restart is needed for a newly launched pgBackRest process. Leave retention, checksum and security checks intact. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Configure one worker

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/pgbackrest.conf.

### File contents

```text
[academy]
pg1-host=pg-primary
pg1-host-user=postgres
pg1-path=/var/lib/pgsql/16/data
pg2-host=pg-standby
pg2-host-user=postgres
pg2-path=/var/lib/pgsql/16/data
[global]
process-max=1
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=zst
backup-standby=y
repo2-path=/var/lib/pgbackrest/server
repo2-retention-full=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Measure a full backup with one worker

Read the command’s effective options and measure this same small workload.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Measure the backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/time -p pgbackrest --stanza=academy --repo=2 --type=full --backup-standby=y backup
```

time measures one pgBackRest operation and prints real/user/sys durations. Compare duration, stored size and effective options; caching and background load limit this single ordered experiment.

The backup completes successfully and time reports its elapsed duration.

### Read recorded sizes

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Compare repository size and elapsed time against the previous setting.

A new full backup is recorded; a smaller or faster result is an observation, not a guarantee.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated config-process-one-restore restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated config-process-one-restore restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-config-process-one-restore-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-config-process-one-restore-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-config-process-one-restore-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-config-process-one-restore-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-config-process-one-restore-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-config-process-one-restore-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-config-process-one-restore-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-config-process-one-restore-repo2
```

Only . and .. appear.

## Restore the config-process-one-restore backup

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
pgbackrest --config=/etc/pgbackrest/restore-config-process-one-restore-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-config-process-one-restore-repo2/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-config-process-one-restore-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-config-process-one-restore-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-config-process-one-restore-repo2'
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
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-config-process-one-restore-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-config-process-one-restore-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-config-process-one-restore-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-config-process-one-restore-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated config-process-one-restore recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-config-process-one-restore-repo2 -l /var/lib/pgsql/restore-config-process-one-restore-repo2/startup.log -t 40 -w start
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

## Accept the recovered config-process-one-restore data

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

/var/lib/pgsql/restore-config-process-one-restore-repo2

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

Rows1 through5 are present. Also check that academy_tuning_payload still contains20000 rows.

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

### Count the tuning dataset

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_tuning_payload;
```

The tuned backup must preserve the complete comparison dataset.

20000

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-config-process-one-restore-repo2 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-config-process-one-restore-repo2/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Configure two workers

Change only this experiment’s variable in the executing backup server’s file. No PostgreSQL restart is needed for a newly launched pgBackRest process. Leave retention, checksum and security checks intact. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Configure two workers

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/pgbackrest.conf.

### File contents

```text
[academy]
pg1-host=pg-primary
pg1-host-user=postgres
pg1-path=/var/lib/pgsql/16/data
pg2-host=pg-standby
pg2-host-user=postgres
pg2-path=/var/lib/pgsql/16/data
[global]
process-max=2
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=zst
backup-standby=y
repo2-path=/var/lib/pgbackrest/server
repo2-retention-full=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Measure a full backup with two workers

Read the command’s effective options and measure this same small workload.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Measure the backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/time -p pgbackrest --stanza=academy --repo=2 --type=full --backup-standby=y backup
```

time measures one pgBackRest operation and prints real/user/sys durations. Compare duration, stored size and effective options; caching and background load limit this single ordered experiment.

The backup completes successfully and time reports its elapsed duration.

### Read recorded sizes

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Compare repository size and elapsed time against the previous setting.

A new full backup is recorded; a smaller or faster result is an observation, not a guarantee.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated config-process-two-restore restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated config-process-two-restore restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-config-process-two-restore-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-config-process-two-restore-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-config-process-two-restore-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-config-process-two-restore-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-config-process-two-restore-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-config-process-two-restore-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-config-process-two-restore-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-config-process-two-restore-repo2
```

Only . and .. appear.

## Restore the config-process-two-restore backup

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
pgbackrest --config=/etc/pgbackrest/restore-config-process-two-restore-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-config-process-two-restore-repo2/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-config-process-two-restore-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-config-process-two-restore-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-config-process-two-restore-repo2'
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
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-config-process-two-restore-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-config-process-two-restore-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-config-process-two-restore-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-config-process-two-restore-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated config-process-two-restore recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-config-process-two-restore-repo2 -l /var/lib/pgsql/restore-config-process-two-restore-repo2/startup.log -t 40 -w start
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

## Accept the recovered config-process-two-restore data

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

/var/lib/pgsql/restore-config-process-two-restore-repo2

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

Rows1 through5 are present. Also check that academy_tuning_payload still contains20000 rows.

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

### Count the tuning dataset

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_tuning_payload;
```

The tuned backup must preserve the complete comparison dataset.

20000

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-config-process-two-restore-repo2 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-config-process-two-restore-repo2/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Configure lz4 compression

Change only this experiment’s variable in the executing backup server’s file. No PostgreSQL restart is needed for a newly launched pgBackRest process. Leave retention, checksum and security checks intact. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Configure lz4 compression

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/pgbackrest.conf.

### File contents

```text
[academy]
pg1-host=pg-primary
pg1-host-user=postgres
pg1-path=/var/lib/pgsql/16/data
pg2-host=pg-standby
pg2-host-user=postgres
pg2-path=/var/lib/pgsql/16/data
[global]
process-max=2
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=lz4
compress-level=1
backup-standby=y
repo2-path=/var/lib/pgbackrest/server
repo2-retention-full=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Measure a full backup with lz4 compression

Read the command’s effective options and measure this same small workload.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Measure the backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/time -p pgbackrest --stanza=academy --repo=2 --type=full --backup-standby=y backup
```

time measures one pgBackRest operation and prints real/user/sys durations. Compare duration, stored size and effective options; caching and background load limit this single ordered experiment.

The backup completes successfully and time reports its elapsed duration.

### Read recorded sizes

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Compare repository size and elapsed time against the previous setting.

A new full backup is recorded; a smaller or faster result is an observation, not a guarantee.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated config-compression-lz4-restore restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated config-compression-lz4-restore restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-config-compression-lz4-restore-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-config-compression-lz4-restore-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-config-compression-lz4-restore-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-config-compression-lz4-restore-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-config-compression-lz4-restore-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-config-compression-lz4-restore-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-config-compression-lz4-restore-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-config-compression-lz4-restore-repo2
```

Only . and .. appear.

## Restore the config-compression-lz4-restore backup

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
pgbackrest --config=/etc/pgbackrest/restore-config-compression-lz4-restore-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-config-compression-lz4-restore-repo2/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-config-compression-lz4-restore-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-config-compression-lz4-restore-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-config-compression-lz4-restore-repo2'
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
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-config-compression-lz4-restore-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-config-compression-lz4-restore-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-config-compression-lz4-restore-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-config-compression-lz4-restore-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated config-compression-lz4-restore recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-config-compression-lz4-restore-repo2 -l /var/lib/pgsql/restore-config-compression-lz4-restore-repo2/startup.log -t 40 -w start
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

## Accept the recovered config-compression-lz4-restore data

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

/var/lib/pgsql/restore-config-compression-lz4-restore-repo2

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

Rows1 through5 are present. Also check that academy_tuning_payload still contains20000 rows.

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

### Count the tuning dataset

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_tuning_payload;
```

The tuned backup must preserve the complete comparison dataset.

20000

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-config-compression-lz4-restore-repo2 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-config-compression-lz4-restore-repo2/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Restore the original backup profile

Return to the known baseline after comparing the measured tradeoffs.

On backup-1 as ec2-user.

### Restore the original backup profile

Use the Linux terminal.

```bash
sudo cp /etc/pgbackrest/pgbackrest.conf.before-tuning /etc/pgbackrest/pgbackrest.conf
```

Copy back the original file rather than guessing its previous values.

The active file matches the rollback copy.

### Check

```bash
sudo cmp /etc/pgbackrest/pgbackrest.conf.before-tuning /etc/pgbackrest/pgbackrest.conf
```

No difference is reported.

## Preserve the primary archive profile

The primary’s archive profile controls archive-push; the backup server’s process-max does not change the primary archiver.

On pg-primary as ec2-user.

### Preserve the primary archive profile

Use the Linux terminal.

```bash
sudo cp /etc/pgbackrest/pgbackrest.conf /etc/pgbackrest/pgbackrest.conf.before-async
```

Preserve the current primary profile before enabling asynchronous archiving.

The rollback file exists.

### Check

```bash
sudo ls -l /etc/pgbackrest/pgbackrest.conf.before-async
```

The rollback file exists.

## Enable asynchronous archiving on the primary

Use the local postgres-owned spool directory. Per-command process-max applies to archive-push. Keep WAL delivery and consistency checks; do not configure queue dropping as a speed shortcut. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Enable asynchronous archiving on the primary

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/pgbackrest.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/16/data
[global]
process-max=2
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=zst
repo1-path=/var/lib/pgbackrest/direct
repo1-retention-full=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
repo2-retention-full=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
repo3-host=backup-1
repo3-host-user=pgbackrest
archive-async=y
spool-path=/var/spool/pgbackrest
[global:archive-push]
process-max=2
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Prove WAL delivery with asynchronous archiving

A saved setting or a spool file alone does not establish recoverable WAL.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Check archived WAL

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy check
```

Read the successful archived-WAL result for all three repositories.

Each configured repository receives the required WAL.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Create a recovery point through the async archiver

Use a new recovery target to prove that asynchronously archived WAL supports recovery.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Create the named target

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_create_restore_point('academy_tuned_async');
```

Write a new named recovery point.

A WAL location is returned.

### Complete its WAL segment

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_switch_wal();
```

Request a WAL switch before checking repository delivery.

A WAL location is returned.

### Read the current markers

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Retain the source baseline for the recovery comparison.

Rows1 through5 are present.

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

## Check delivery of the new recovery target

Check archived WAL after writing the named point.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Check every repository

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy check
```

Observe successful delivery after the new target.

The required WAL is archived successfully.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated async-safe restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated async-safe restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-async-safe-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-async-safe-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-async-safe-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-async-safe-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-async-safe-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-async-safe-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-async-safe-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-async-safe-repo2
```

Only . and .. appear.

## Restore the async-safe backup

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
pgbackrest --config=/etc/pgbackrest/restore-async-safe-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=name --target="academy_tuned_async" --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to the recorded target. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-async-safe-repo2/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-async-safe-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-async-safe-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-async-safe-repo2'
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
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-async-safe-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-async-safe-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-async-safe-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-async-safe-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated async-safe recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-async-safe-repo2 -l /var/lib/pgsql/restore-async-safe-repo2/startup.log -t 40 -w start
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

## Accept the recovered async-safe data

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

/var/lib/pgsql/restore-async-safe-repo2

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

Rows1 through5 are present.

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

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-async-safe-repo2 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-async-safe-repo2/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Restore the original primary archive profile

End the experiment with the baseline profile restored.

On pg-primary as ec2-user.

### Restore the original primary archive profile

Use the Linux terminal.

```bash
sudo cp /etc/pgbackrest/pgbackrest.conf.before-async /etc/pgbackrest/pgbackrest.conf
```

Restore the saved file. New pgBackRest processes read the restored settings.

The original profile is restored.

### Check

```bash
sudo cmp /etc/pgbackrest/pgbackrest.conf.before-async /etc/pgbackrest/pgbackrest.conf
```

No difference is reported.

## Check protection after the tuning rollback

Finish with a new observation of every repository’s WAL delivery.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Check the stanza

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy check
```

Read the final primary archive results.

All three repositories complete the check successfully.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Create the business recovery dataset

A running database can still contain the wrong recovered data.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Create the orders table

Type this at postgres=#. Do not type the prompt itself.

```sql
CREATE TABLE incident_orders (id integer PRIMARY KEY, amount integer NOT NULL, status text NOT NULL);
```

Use explicit IDs and amounts for acceptance checks.

CREATE TABLE

### Insert the accepted orders

Type this at postgres=#. Do not type the prompt itself.

```sql
INSERT INTO incident_orders VALUES (1,100,'paid'),(2,200,'paid'),(3,300,'paid');
```

The accepted baseline has three orders totaling600.

INSERT 0 3

### Create the limited app account

Type this at postgres=#. Do not type the prompt itself.

```sql
CREATE ROLE app_reader LOGIN;
```

Use a non-superuser to verify the application can read recovered data.

CREATE ROLE

### Grant only the required table access

Type this at postgres=#. Do not type the prompt itself.

```sql
GRANT SELECT ON incident_orders TO app_reader;
```

Grant read access to the business table, not general administration.

GRANT

### Read business acceptance values

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*),sum(amount),string_agg(id::text,',' ORDER BY id) FROM incident_orders;
```

Check row count, total and exact IDs together.

count3, sum600, IDs1,2,3.

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

## Set the protected application-test password

The recovery drill must prove the limited account can authenticate.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Start the password change

Type this at postgres=#. Do not type the prompt itself.

```text
\password app_reader
```

Use psql’s hidden-input flow.

Wait for the app_reader password prompt.

### Enter the generated password

Enter the generated value only at the hidden terminal password prompt.

The input remains hidden.

Wait for Enter it again:.

### Repeat the same password

Enter the generated value only at the hidden terminal password prompt.

The input remains hidden.

Wait for postgres=#.

### Check SCRAM storage

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT rolname, rolpassword LIKE 'SCRAM-SHA-256%' AS scram FROM pg_authid WHERE rolname = 'app_reader';
```

Return only whether SCRAM storage is in use.

app_reader has scram=t.

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

## Create a private file before entering its contents

Prepare an empty file with restrictive permissions before entering the protected value.

On pg-primary as ec2-user.

### Create a private file before entering its contents

Use the Linux terminal.

```bash
sudo install -m 600 -o postgres -g postgres /dev/null /var/lib/pgsql/.pgpass
```

install copies the empty /dev/null input to this new file and sets its owner and mode. Use this once during initial setup.

The new file belongs to the service user with mode600.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.pgpass
```

postgres:postgres 600 /var/lib/pgsql/.pgpass

## Store the application-test credential

This private passfile supports read-only acceptance through the local socket and isolated restore ports. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Store the application-test credential

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/.pgpass
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/.pgpass.

### File contents

```text
/var/run/postgresql:*:postgres:app_reader:{{secret:app_reader}}
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.pgpass
```

The exact file path is present. The following service checks establish whether its settings work.

## Require SCRAM for the application-test account

Place the specific app_reader rule before the general peer rule. Preserve the standby’s TLS replication rule. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Require SCRAM for the application-test account

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/16/data/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/16/data/pg_hba.conf.

### File contents

```text
local all postgres peer
local all app_reader scram-sha-256
local all all peer
hostssl replication replicator {{address:pg-standby}}/32 scram-sha-256
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Reload the authentication rules

Apply pg_hba.conf without restarting the database.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Reload server configuration

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_reload_conf();
```

Request a reload, then separately prove that a new app_reader connection works.

t

### Confirm the business baseline

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*),sum(amount) FROM incident_orders;
```

A successful reload request does not prove new authentication. The next step checks it.

count3, sum600.

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

## Prove the limited application connection

Accept the connection and data through the account the recovery drill will use.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -U app_reader
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=>. You are now entering SQL or psql commands.

### Read the connected role

Type this at postgres=>. Do not type the prompt itself.

```sql
SELECT current_user;
```

Verify the connection uses the limited account.

app_reader

### Read business acceptance values

Type this at postgres=>. Do not type the prompt itself.

```sql
SELECT count(*),sum(amount),string_agg(id::text,',' ORDER BY id) FROM incident_orders;
```

Read the exact expected data without administrative privileges.

count3, sum600, IDs1,2,3.

### Leave PostgreSQL

After reading the result, type this at postgres=>.

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

## Back up the business baseline to direct

Take a full backup using the explicit executing role and repository.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Run the backup

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/direct.conf --stanza=academy --repo=1 --type=full --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy --repo=1 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new full backup is recorded for academy.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Back up the business baseline to server

Take a full backup using the explicit executing role and repository.

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
pgbackrest --stanza=academy --repo=2 --type=full --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new full backup is recorded for academy.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Back up the business baseline to s3

Take a full backup using the explicit executing role and repository.

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
pgbackrest --stanza=academy --repo=3 --type=full --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=3 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new full backup is recorded for academy.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.
