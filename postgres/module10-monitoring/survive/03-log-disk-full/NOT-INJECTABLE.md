# Not injectable: Log Disk Full

This scenario needs /opt/pgsql/log to be a small, separate volume that is genuinely 99% full
(the runbook reads `df -h /opt/pgsql/log` and a `/dev/xvdf` mount). On the lab node that path
is a plain directory on the root filesystem, and the survive contract forbids touching the
root filesystem's free space below 1 GB. A loop-device mount over /opt/pgsql/log would also
hide the live log files that the running logging collector holds open, and on CentOS Stream 9
a freshly formatted loop filesystem has the wrong SELinux label, so postgres could not write
to it. Faking only the `chaos_fill.bin` file or the `log_min_duration_statement = 0` setting
would not reproduce the disk-full symptom the runbook diagnoses.

Tutor instead: ask the learner to run the runbook's diagnostic commands (`df -h /opt/pgsql/log`,
`du -sh /opt/pgsql/log/*`, `SHOW log_min_duration_statement;`) on their own node and paste the
output, or hand them the expected outputs from the runbook, then walk the resolution in order:
free space first (remove the filler file, compress old logs), then tune
`log_min_duration_statement`, `log_rotation_age` and `log_rotation_size`, reload and verify.
