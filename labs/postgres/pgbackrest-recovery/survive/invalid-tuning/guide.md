# A tuning change is rejected before backup

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Read the effective configuration file

Identify the file and section used by the failing backup process.

On backup-1 as ec2-user.

### Read the effective configuration file

Use the Linux terminal.

```bash
sudo cat /etc/pgbackrest/pgbackrest.conf
```

Read process-max, db-timeout and protocol-timeout in context.

The injected value is invalid, such as process-max0 or protocol-timeout below db-timeout.

## Restore the tested backup configuration

Restore process-max2 and the tested baseline. Read the next command’s option summary to confirm the effective values. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Restore the tested backup configuration

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

## Prove the corrected configuration works

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
