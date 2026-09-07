# The backup failed and one alert channel also failed

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Read the failed job identity

Correlate the alert with one specific backup attempt.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Read the last attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/server/last-attempt.json
```

Record job_id and the nonzero backup_exit_code. A delivered alert must not change that code.

The failed job has a unique job_id.

### Inspect pending delivery records

Type this in the pgbackrest Linux shell on backup-1.

```bash
ls -l /var/lib/suta-backup-jobs/server/outbox
```

A pending-channel record remains until delivery is acknowledged.

The outbox retains the rejected notification.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Restore the local webhook receiver

Remove only the deliberate local rejection flag.

On backup-1 as ec2-user.

### Restore the local webhook receiver

Use the Linux terminal.

```bash
sudo rm /var/lib/suta-alert-test/reject-webhook
```

This restores acceptance by the test receiver; it does not repair the repository fault.

The rejection flag is gone.

### Check

```bash
ls -la /var/lib/suta-alert-test
```

The rejection flag is gone.

## Retry only pending alert channels

Preserve already acknowledged delivery and retry the failed channel.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Retry notifications

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json retry-alerts
```

The outbox tracks which channel already accepted the event. Delivery is at least once; receivers can deduplicate by job_id.

The pending webhook is delivered without resending the already acknowledged SMTP event.

### Inspect the outbox

Type this in the pgbackrest Linux shell on backup-1.

```bash
ls -la /var/lib/suta-backup-jobs/server/outbox
```

An empty outbox means all configured channels acknowledged their pending events.

No pending JSON event remains.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Correlate actual local receipts

Use the exact failed job_id to distinguish this event from older test notifications.

On backup-1 as ec2-user.

### Correlate actual local receipts

Use the Linux terminal.

```bash
sudo tail -n 12 /var/lib/suta-alert-test/delivered.ndjson
```

Read the local test receiver’s retained receipts.

The failed job has one email and one webhook receipt after retry.

## Repair the failed backup repository

Notification recovery does not make the underlying backup succeed.

On nfs-1 as ec2-user.

### Repair the failed backup repository

Use the Linux terminal.

```bash
sudo chmod 750 /srv/pgbackrest/server
```

Restore the NFS directory’s intended mode.

The mode is750.

### Check

```bash
stat -c "%u:%g %a %n" /srv/pgbackrest/server
```

The mode is750.

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

## Run a new successful backup job after the incident

Keep the original failed job and its delivery receipts. A new attempt must succeed after repository repair.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run a fresh job

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-server.json incr
```

This new attempt has a different job_id; delivering the old alert did not make its backup successful.

The new backup attempt succeeds.

### Read the new attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/server/last-attempt.json
```

Compare the new successful job with the retained failed job.

The new job has backup_exit_code0 and a new backup_label.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.
