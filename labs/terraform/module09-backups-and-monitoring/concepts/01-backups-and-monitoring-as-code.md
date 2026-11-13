# Backups and Monitoring as Code

This explains how RDS backups work, what the backup and maintenance windows are, and how a
CloudWatch alarm watches the database. Read it before the tutorial, where you write all of it as
Terraform.

## Why write backups and monitoring as code

Backup and alerting settings are the ones nobody looks at until the worst day. In the console they
are set once, by one person, and forgotten. As code they are visible in `main.tf`: anyone can read
the retention, the windows, and the alarm threshold, and every change is a reviewed commit.

## Automated backups and point-in-time restore

RDS takes a daily snapshot of the storage and continuously saves the transaction logs. Together
they let you restore to **any second** inside the retention period (point-in-time recovery).

- `backup_retention_period` is the number of days kept, 0 to 35. The AWS default is only 1 day, which
  is rarely enough.
- **Setting it to 0 turns automated backups off**, and with them point-in-time recovery. This is
  one of the most dangerous one-line changes in the whole file.
- Raising retention is an in-place change and is safe on a live database.

## The two windows

- `backup_window` - the daily slot (for example `03:00-04:00`) when the snapshot is taken. On a
  single-AZ instance there can be a brief pause in I/O.
- `maintenance_window` - the weekly slot (for example `sun:04:30-sun:05:30`) when AWS applies
  patches and some modifications.

Three rules:

- Both are in **UTC**, not your local time. Pick them for your quietest hour in UTC.
- They **must not overlap.** AWS rejects an overlap at apply time. `terraform plan` will not warn
  you, because only AWS knows the rule.
- Put the maintenance window **after** the backup, so a patch never starts mid-snapshot.

## Snapshots and what survives a delete

- `copy_tags_to_snapshot` makes each snapshot inherit your tags, which keeps cost reports honest.
- `skip_final_snapshot = true` lets a database be deleted with no last backup. It is fine for a lab
  and **wrong for production**, where you set it to `false` and give a `final_snapshot_identifier`.
- By default, the automated backups are deleted along with the instance. A manual or final
  snapshot is what outlives it.

## Logs

`enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]` streams the PostgreSQL log and the
upgrade log to CloudWatch Logs. They are searchable and kept after the instance is gone, which
helps after an incident.

## Alarms: the metric, the threshold, and who is told

A CloudWatch alarm watches one metric and changes state when it crosses a line. The tutorial
alarm watches `FreeStorageSpace`.

- `threshold` is in **bytes**. `2147483648` is 2 GiB (2 x 1024 x 1024 x 1024).
- `period = 300` is the length of one check in seconds. `evaluation_periods = 3` means three
  checks in a row must be bad, so the alarm needs 15 minutes of low storage before it fires.
  This avoids false alarms from a momentary dip.
- `treat_missing_data` decides what a gap in data means. `notBreaching` ignores gaps;
  `breaching` treats missing data as a problem. Choose by how bad silence is for that metric.
- `alarm_actions` is the list of things to do when the alarm fires. **An empty list is a silent
  alarm** - it changes state on a dashboard and tells nobody. In production you point it at an SNS
  topic that emails or pages the team, and the topic needs a subscriber.

## Plan versus reality

A plan only shows the change to your settings. Two habits close the gap:

- After an apply, read the real value back from AWS (`aws rds describe-db-instances`), not just
  Terraform's output.
- If an apply fails on an AWS rule, check what AWS actually has. A rejected modification is
  normally all-or-nothing, so the old values usually remain.

## What is next

In the tutorial you write the instance with retention, windows, log exports and a storage alarm,
apply it, and verify each setting directly in AWS.
