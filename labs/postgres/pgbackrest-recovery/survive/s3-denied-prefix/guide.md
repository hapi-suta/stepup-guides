# S3 rejects access to the wrong repository prefix

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Inspect the executing job profile

Find which profile the failed wrapper job actually used.

On backup-1 as ec2-user.

### Inspect the executing job profile

Use the Linux terminal.

```bash
sudo cat /etc/pgbackrest/job-s3.json
```

The JSON contains configuration paths and local test destinations, not AWS secrets.

The job points at the injected denied-prefix profile.

## Restore the approved S3 job profile

Select the normal profile containing the assigned bucket and authorized prefix. Keep the IAM policy unchanged. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Restore the approved S3 job profile

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

## Prove the authorized S3 job works

Run a new attempt with the repaired job profile and keep the original failure in its historical log.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the corrected job

Type this in the pgbackrest Linux shell on backup-1.

```bash
/usr/bin/python3 /opt/suta-pgbackrest/backup-job.py --config=/etc/pgbackrest/job-s3.json incr
```

The wrapper records a new job_id and backup label; the old failure remains evidence.

The new attempt succeeds.

### Read the new attempt

Type this in the pgbackrest Linux shell on backup-1.

```bash
cat /var/lib/suta-backup-jobs/s3/last-attempt.json
```

Correlate this new job_id with its log and backup label.

A new successful incr attempt has backup_exit_code0 and a backup_label.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.
