# The standby backup cannot find a standby

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Inspect the standby service

Separate an unavailable database from an unavailable host.

On pg-standby as ec2-user.

### Inspect the standby service

Use the Linux terminal.

```bash
systemctl status postgresql-16 --no-pager
```

Read the current unit state and its recent messages.

The database service is stopped; the terminal host is reachable.

## Restart the stopped standby

Restore the original standby identity and data.

On pg-standby as ec2-user.

### Restart the stopped standby

Use the Linux terminal.

```bash
sudo systemctl start postgresql-16
```

Start its existing database service.

The service becomes active.

### Check

```bash
systemctl is-active postgresql-16
```

The service becomes active.

## Prove standby backup works again

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
