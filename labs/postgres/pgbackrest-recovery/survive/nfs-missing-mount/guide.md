# The backup path is an ordinary local directory

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Inspect the backing filesystem

A directory path can exist even when NFS is not mounted.

On backup-1 as ec2-user.

### Inspect the backing filesystem

Use the Linux terminal.

```bash
findmnt -T /var/lib/pgbackrest/server -o SOURCE,TARGET,FSTYPE,OPTIONS
```

Read the actual backing filesystem and mount target.

The NFS export is missing; the path resolves under the local filesystem.

## Mount the configured NFS export

Restore the intended repository, preserving its backup chain.

On backup-1 as ec2-user.

### Mount the configured NFS export

Use the Linux terminal.

```bash
sudo mount /var/lib/pgbackrest/server
```

Use the reviewed fstab entry.

The correct NFS export is mounted.

### Check

```bash
findmnt -T /var/lib/pgbackrest/server -o SOURCE,TARGET,FSTYPE,OPTIONS
```

The correct NFS export is mounted.

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

## Prove backup works on the restored mount

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
