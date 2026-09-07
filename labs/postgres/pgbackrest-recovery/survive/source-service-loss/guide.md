# Recover the database service and rebuild its standby

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Confirm the old pg-primary service is stopped

Do not run the old writer or old standby beside the recovered writer.

On pg-primary as ec2-user.

### Confirm the old pg-primary service is stopped

Use the Linux terminal.

```bash
systemctl is-active postgresql-16
```

Read the source service state.

inactive; nonzero status is expected while it is deliberately stopped.

## Confirm the old pg-standby service is stopped

Do not run the old writer or old standby beside the recovered writer.

On pg-standby as ec2-user.

### Confirm the old pg-standby service is stopped

Use the Linux terminal.

```bash
systemctl is-active postgresql-16
```

Read the source service state.

inactive; nonzero status is expected while it is deliberately stopped.

## Write the isolated disaster-candidate restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated disaster-candidate restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-disaster-candidate-repo3.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-disaster-candidate-repo3.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-disaster-candidate-repo3
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
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-disaster-candidate-repo3.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-disaster-candidate-repo3.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-disaster-candidate-repo3.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-disaster-candidate-repo3
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-disaster-candidate-repo3
```

Only . and .. appear.

## Restore the disaster-candidate backup

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
pgbackrest --config=/etc/pgbackrest/restore-disaster-candidate-repo3.conf --stanza=academy --repo=3 --archive-mode=off --type=name --target="before_bad_ddl" --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to the recorded target. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-disaster-candidate-repo3/PG_VERSION
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
sudo vi /var/lib/pgsql/restore-disaster-candidate-repo3/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-disaster-candidate-repo3/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-disaster-candidate-repo3'
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
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-disaster-candidate-repo3/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-disaster-candidate-repo3/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-disaster-candidate-repo3/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-disaster-candidate-repo3/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated disaster-candidate recovery

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-disaster-candidate-repo3 -l /var/lib/pgsql/restore-disaster-candidate-repo3/startup.log -t 40 -w start
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

## Accept the recovered disaster-candidate data

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

/var/lib/pgsql/restore-disaster-candidate-repo3

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
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-disaster-candidate-repo3 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-disaster-candidate-repo3/startup.log
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

## Allow the limited account to verify the candidate

The isolated candidate remains local-only and requires the protected application credential. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Allow the limited account to verify the candidate

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-disaster-candidate-repo3/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-disaster-candidate-repo3/pg_hba.conf.

### File contents

```text
local all postgres peer
local all app_reader scram-sha-256
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-disaster-candidate-repo3/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the candidate for application acceptance

Prove the application account before changing the normal service endpoint.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Start the candidate

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-disaster-candidate-repo3 -l /var/lib/pgsql/restore-disaster-candidate-repo3/startup.log -t 40 -w start
```

Use the isolated data directory.

The isolated candidate starts.

### Check the isolated endpoint

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55435
```

This is the candidate port, not the normal service.

The candidate accepts connections.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Accept the recovered data through the application account

The normal endpoint must wait until authentication and business acceptance pass.

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
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55435 -U app_reader
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55435.

Wait for postgres=>. You are now entering SQL or psql commands.

### Check the database role

Type this at postgres=>. Do not type the prompt itself.

```sql
SELECT current_user;
```

Verify a limited application account.

app_reader

### Read the recovered business records

Type this at postgres=>. Do not type the prompt itself.

```sql
SELECT count(*),sum(amount),string_agg(id::text,',' ORDER BY id) FROM incident_orders;
```

Compare the exact records against the documented recovery target.

Count 3, sum 600, IDs 1,2,3. Order 4 is excluded by this PITR choice.

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

## Stop the verified candidate before moving it

Move a stopped cluster only after accepting its data.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the candidate

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-disaster-candidate-repo3 -m fast -w stop
```

Stop the isolated server cleanly.

The candidate shuts down.

### Read the shutdown log

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 15 /var/lib/pgsql/restore-disaster-candidate-repo3/startup.log
```

Retain the accepted recovery evidence.

A clean shutdown is recorded.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Restore the shared NFS service

The S3 candidate was recovered while NFS was unavailable. Restore NFS before resuming protection to all repositories.

On nfs-1 as ec2-user.

### Restore the shared NFS service

Use the Linux terminal.

```bash
sudo systemctl start nfs-server
```

Restart the assigned NFS service with its existing exports.

The NFS service is active.

### Check

```bash
systemctl is-active nfs-server
```

The NFS service is active.

## Preserve the old primary data

Keep the old writer fenced for investigation. Continue only when the destination does not already exist and both source services are stopped.

On pg-primary as ec2-user.

### Preserve the old primary data

Use the Linux terminal.

```bash
sudo mv /var/lib/pgsql/16/data /var/lib/pgsql/16/pre-dr-data
```

Rename the stopped old data directory. Do not delete it or start it again.

The old data is retained at pre-dr-data.

### Check

```bash
sudo ls -ld /var/lib/pgsql/16/pre-dr-data
```

The old data is retained at pre-dr-data.

## Move the accepted candidate to the service path

Install only the previously accepted stopped candidate.

On pg-primary as ec2-user.

### Move the accepted candidate to the service path

Use the Linux terminal.

```bash
sudo mv /var/lib/pgsql/restore-disaster-candidate-repo3 /var/lib/pgsql/16/data
```

Move its directory into the canonical service path, which is now absent.

The accepted directory is at the normal path.

### Check

```bash
sudo cat /var/lib/pgsql/16/data/PG_VERSION
```

The accepted directory is at the normal path.

## Restore the normal primary settings

Restore port 5432, TLS, streaming and archiving for the recovered writer. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Restore the normal primary settings

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/16/data/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/16/data/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/16/data'
listen_addresses = '*'
port = 5432
unix_socket_directories = '/var/run/postgresql'
wal_level = replica
max_wal_senders = 5
max_replication_slots = 5
wal_keep_size = '128MB'
max_slot_wal_keep_size = '512MB'
hot_standby = on
archive_mode = on
archive_command = 'pgbackrest --stanza=academy archive-push %p'
archive_timeout = 60
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
password_encryption = 'scram-sha-256'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql.log'
log_line_prefix = '%m [%p] '
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Restore the normal primary authentication

Retain local application SCRAM and standby TLS access. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Restore the normal primary authentication

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

## Clear completed recovery settings

The chosen target has already been reached. Preserve the recovery evidence and clear the completed target settings before normal service. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Clear completed recovery settings

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/16/data/postgresql.auto.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/16/data/postgresql.auto.conf.

### File contents

```text
# Recovery completed. Prior target settings are retained with the isolated recovery evidence.
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/postgresql.auto.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Restore labels on the recovered primary

Keep SELinux enforcing.

On pg-primary as ec2-user.

### Restore labels on the recovered primary

Use the Linux terminal.

```bash
sudo restorecon -RF /var/lib/pgsql/16/data
```

Restore the data directory labels.

The directory has its expected PostgreSQL labels.

### Check

```bash
sudo ls -ldZ /var/lib/pgsql/16/data
```

The directory has its expected PostgreSQL labels.

## Start the recovered normal service

Only the recovered writer starts.

On pg-primary as ec2-user.

### Start the recovered normal service

Use the Linux terminal.

```bash
sudo systemctl start postgresql-16
```

Start the canonical PostgreSQL service.

The normal service is active.

### Check

```bash
systemctl is-active postgresql-16
```

The normal service is active.

## Prove the application at the normal endpoint

The recovered service must work through the normal connection and limited account.

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

### Check the connected role

Type this at postgres=>. Do not type the prompt itself.

```sql
SELECT current_user;
```

Confirm the application identity.

app_reader

### Read accepted business records

Type this at postgres=>. Do not type the prompt itself.

```sql
SELECT count(*),sum(amount),string_agg(id::text,',' ORDER BY id) FROM incident_orders;
```

Verify exact data after cutover.

Count 3, sum 600, IDs 1,2,3.

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

## Inspect the recovered writer identity

PITR promotion creates a new timeline; compare it with the recorded source timeline.

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

### Read the timeline

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT timeline_id FROM pg_control_checkpoint();
```

Record the actual timeline rather than assuming a constant on repeated drills.

A new timeline is present.

### Check the writer role

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_is_in_recovery();
```

The recovered service must be the writer.

f

### Check the service directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Confirm this is the canonical recovered service.

/var/lib/pgsql/16/data

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

## Preserve the old standby data

The old standby copied the earlier history. Keep it stopped and preserve its files. Continue only if the destination is absent.

On pg-standby as ec2-user.

### Preserve the old standby data

Use the Linux terminal.

```bash
sudo mv /var/lib/pgsql/16/data /var/lib/pgsql/16/pre-dr-data
```

Rename the old stopped standby directory.

The old directory is retained.

### Check

```bash
sudo ls -ld /var/lib/pgsql/16/pre-dr-data
```

The old directory is retained.

## Create an empty standby destination

The new standby must start from the recovered writer.

On pg-standby as ec2-user.

### Create an empty standby destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/16/data
```

Create a private empty data directory.

Only . and .. are present.

### Check

```bash
sudo ls -la /var/lib/pgsql/16/data
```

Only . and .. are present.

## Rebuild from the recovered writer

Create a new physical standby using the existing strict TLS identity and protected replication password.

On pg-standby as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-standby, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-standby.

### Copy the recovered cluster

Type this in the postgres Linux shell on pg-standby.

```bash
/usr/pgsql-16/bin/pg_basebackup --dbname="host=pg-primary user=replicator application_name=pg-standby sslmode=verify-full sslrootcert=/var/lib/pgsql/root.crt passfile=/var/lib/pgsql/.pgpass" -D /var/lib/pgsql/16/data -R -X stream -C -S academy_standby --checkpoint=fast --progress
```

The restored primary does not carry the old runtime replication slot. -C creates the named physical slot; -R writes standby connection settings.

The base backup finishes successfully.

### Read the copied version

Type this in the postgres Linux shell on pg-standby.

```bash
cat /var/lib/pgsql/16/data/PG_VERSION
```

Inspect the copied major version before startup.

16

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Configure the rebuilt standby

Keep archive_mode off on this standby and preserve the generated standby connection settings. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-standby as ec2-user.

### Configure the rebuilt standby

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/16/data/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/16/data/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/16/data'
listen_addresses = '*'
port = 5432
unix_socket_directories = '/var/run/postgresql'
wal_level = replica
max_wal_senders = 5
max_replication_slots = 5
wal_keep_size = '128MB'
max_slot_wal_keep_size = '512MB'
hot_standby = on
archive_mode = off
archive_command = 'pgbackrest --stanza=academy archive-push %p'
archive_timeout = 60
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
password_encryption = 'scram-sha-256'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql.log'
log_line_prefix = '%m [%p] '
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Restore the standby data labels

Keep SELinux enabled.

On pg-standby as ec2-user.

### Restore the standby data labels

Use the Linux terminal.

```bash
sudo restorecon -RF /var/lib/pgsql/16/data
```

Restore expected labels.

The data labels are correct.

### Check

```bash
sudo ls -ldZ /var/lib/pgsql/16/data
```

The data labels are correct.

## Start the rebuilt standby

Start the new standby from the recovered writer.

On pg-standby as ec2-user.

### Start the rebuilt standby

Use the Linux terminal.

```bash
sudo systemctl start postgresql-16
```

Start its PostgreSQL service.

The service is active.

### Check

```bash
systemctl is-active postgresql-16
```

The service is active.

## Prove rebuilt TLS replication

Read the connection, role and TLS status together.

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

### Prove rebuilt TLS replication

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT r.application_name,r.state,s.ssl FROM pg_stat_replication r JOIN pg_stat_ssl s USING(pid);
```

Read the connection, role and TLS status together.

pg-standby, streaming, ssl=t.

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

## Accept the rebuilt standby data

Confirm the standby carries the accepted recovery data.

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

### Accept the rebuilt standby data

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*),sum(amount),string_agg(id::text,',' ORDER BY id) FROM incident_orders;
```

Confirm the standby carries the accepted recovery data.

Count 3, sum 600, IDs 1,2,3.

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

## Prove current repository protection

A repaired setting needs new outcome evidence.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Check WAL delivery

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy check
```

Read every configured repository result.

The check completes successfully.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Resume direct protection on the new timeline

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

## Resume server protection on the new timeline

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

## Resume s3 protection on the new timeline

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
