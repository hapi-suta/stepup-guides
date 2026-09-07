# Understand PostgreSQL backup and recovery

A connected course in repository design, standby backups, daily operations, logs, tuning and recovery—grounded in the tested four-host lab.

## Understand what must survive

### The service is back. Are the right records back?

A recovery succeeds when the required data and application operation are correct.

In this illustrative incident, three orders total 600. A mistaken update changes every amount to zero, and the standby faithfully repeats it.

#### Follow the business fact

The number 600 gives the team a concrete acceptance condition. A server can answer connections, return three rows and still return the wrong amounts. Before touching recovery, record what was known before the incident, when the unwanted change happened and which later valid writes must be considered. Choose the evidence the recovered application must satisfy.

#### Meet the four hosts

pg-primary accepts writes; pg-standby replays its WAL. backup-1 can run pgBackRest with a repository mounted from nfs-1. The alternate direct mode runs pgBackRest on the primary with its own NFS mount. S3 supplies another repository path. These are different responsibilities, not five interchangeable copies of a running database.

#### Separate preparation from learning

Terraform owns the AWS resources and their lifetime. Ansible manages the platform handoff. The student configures the database and backup system through BUILD, operates it in USE, and practices incidents in SURVIVE. This course explains the mechanisms first. Reading a topic, seeing a diagram or receiving a helpful Chat answer does not prove a lab action completed.

Which observation is stronger: the port is open, or the recovered application reads the expected orders?

The application check is stronger because it exercises access and business data. It still needs the chosen target, recovery state and data-loss boundary to make the complete recovery claim.

[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)
[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)

### Why a standby does not replace a backup

Replication follows current changes; a backup and retained WAL can preserve a recoverable past.

The primary commits the wrong update. Moments later the standby has the same wrong values.

#### What streaming replication copies

PostgreSQL streams write-ahead log records, which describe changes needed to reproduce database state. The standby receives and replays those records. A valid but unwanted UPDATE or DROP is part of that history, so replication normally carries the mistake too. The standby is useful for availability and backup read offload; it is not automatically a protected earlier version.

#### What a backup retains

A physical backup stores a database file set with information about its consistency boundary. Required WAL lets PostgreSQL make that copy consistent and potentially recover it to a later chosen target. Retained older backups and continuous archived WAL provide options that current primary and standby files alone may no longer offer. Both the file set and its dependencies matter.

#### Different failures need different paths

A stopped primary service may be an availability incident. An unwanted committed change is a data incident. A lost NFS server affects both NFS repositories in this lab. Decide what failed before choosing a standby, a restore or PITR. The lab deliberately observes the wrong update on the standby before using an earlier recovery point to repair the data.

Would promoting the standby undo a committed accidental deletion it has already replayed?

No. Promotion changes its role, not its existing data history. Recover an earlier valid state from an appropriate backup and WAL, then verify the lost record and excluded later work.

[PostgreSQL 16: standby servers](https://www.postgresql.org/docs/16/warm-standby.html)
[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)

### Choose recovery objectives before a schedule

RPO concerns the acceptable recovery point; RTO concerns time until useful service is restored.

A team says “nightly backup” but cannot say how much data it may lose or how long restoration takes.

#### Connect the objective to evidence

A recovery-point objective defines acceptable loss exposure in time or business terms. A nightly full backup does not necessarily mean a whole day of exposure if continuous WAL is safely archived, but it also does not guarantee recovery to the latest commit. A usable chain, surviving WAL, credentials and a reachable repository all participate in the actual recovery boundary.

#### Measure the whole recovery path

Recovery time includes detecting the incident, containing writes, locating the correct backup and target, making storage available, restoring files, replaying WAL and validating the application. A short backup duration or quick PostgreSQL startup measures only one part. Use a restore rehearsal to discover which part dominates for the data size and infrastructure you intend to run.

#### Keep the lab claim bounded

This lab uses small synthetic tables and same-region resources. Its observed outage-to-application times are evidence of the tested procedure, not production RTO promises. In the cutover drill, a later acknowledged order is excluded by choosing an earlier safe point. Name that loss explicitly instead of reporting a green service as proof that every write survived.

Can a successful 02:00 full backup prove a 15-minute RPO at 17:00?

No. Check the archived WAL continuity and freshness, surviving dependencies and an actual recovery to the intended boundary. The full-backup timestamp alone does not establish the latest recoverable point.

[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)
[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)

### Why copied files still need WAL

An online backup spans time. PostgreSQL must reconcile that file copy into a consistent database.

The backup is copying one table while an application is modifying another.

#### The copy is not one frozen instant

Different database files can be read at different moments during an online backup. PostgreSQL coordinates a backup boundary, and WAL covers changes needed to make the resulting files consistent during recovery. pgBackRest records the file inventory and backup metadata. An arbitrary filesystem copy of a running cluster does not acquire those guarantees simply because every copy command returned zero.

#### Keep the archive and checksum checks

The lab initializes PostgreSQL with data checksums and retains pgBackRest consistency checks. Backup logs and metadata must be inspected: checksum warnings require investigation, and a clean process exit alone is not enough to dismiss them. The tested acceptance checks require a fresh backup of the requested type with error=false, followed by recovery checks against the restored data.

#### Prove the restored copy separately

Successful restore output says the tool copied the requested files. PostgreSQL may still need recovery and may initially reject connections. Wait for readiness, connect to the isolated instance and check its actual data directory, recovery state and expected records. The lab caught exactly this distinction: “server started” appeared before the restored database was ready for SQL.

Why does the Guide check both backup metadata and restored rows?

They establish different claims. Metadata describes the saved backup and detected errors; restored SQL and application checks show that the selected recovery procedure produced the required usable data.

[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)
[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)
[pgBackRest: command reference](https://pgbackrest.org/command.html)

## Choose and secure the repository path

### Mode 1: the database server mounts NFS

The primary runs pgBackRest and writes through a local mount path whose storage lives on nfs-1.

A backup writes to /var/lib/pgbackrest/direct, but the disk that holds those bytes belongs to another host.

#### Local path, remote storage

The mount makes an NFS export look like a directory on pg-primary. pgBackRest uses that local filesystem path for repo1; NFS sends the storage operations to nfs-1. The direct profile can still read bulk database files from the standby. “Direct” describes the repository placement and executing host, not a requirement to read every data file from the primary.

#### Permissions cross the mount

The lab matches the postgres numeric user identity on the client and NFS server. The export permits only the assigned primary client and uses root_squash, so a root request does not receive unrestricted server-side root access. Inspect the mount, export and service-user ownership together. Merely granting broad local directory permissions does not establish the remote access you intended.

#### Distinguish a mount from an ordinary directory

If NFS is missing, the same pathname may expose the underlying local directory. A backup written there could create a false sense of remote protection. The tested baseline keeps that unmounted directory root-owned and unwritable to the service account. Students verify the actual source and filesystem type with findmnt, then test access as the account that will run the backup.

Does the existence of /var/lib/pgbackrest/direct prove NFS is mounted?

No. Inspect the mounted source and filesystem type, then verify the service account can use the intended export. A directory with that name may exist when the remote filesystem is absent.

[Red Hat Enterprise Linux 9: deploying an NFS server](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_using_network_file_services/deploying-an-nfs-server_configuring-and-using-network-file-services)
[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)

### Mode 2: a dedicated backup server mounts NFS

backup-1 runs pgBackRest, connects to the database hosts and writes repo2 through its own NFS mount.

The database hosts are busy; the team wants backup orchestration and repository access on a separate machine.

#### Move the executing process

The pgbackrest account on backup-1 runs the backup command. Its configuration names pg-primary and pg-standby as remote PostgreSQL hosts. The process coordinates the backup, transfers files through its authenticated connections and writes to /var/lib/pgbackrest/server. That directory is the mounted export from nfs-1; placing an orchestrator on another server does not itself create another independent storage system.

#### Keep the host-placement rules straight

In this tested version, the executing configuration cannot combine remote PostgreSQL hosts with a remote repo-host arrangement. The dedicated backup server therefore sees its NFS repository as a local path. On a database host, archive-push can instead reach repo2 through backup-1. Different commands on different hosts need deliberately different profiles; copying one configuration everywhere caused a real rejected setup attempt.

#### Compare the failure boundary

Mode 1 and mode 2 use separate NFS exports and service users, but both exports live on one NFS host. Losing nfs-1 can interrupt both paths. The dedicated server changes orchestration placement and operational load; it does not remove that shared dependency. The course adds S3 and tests recovery with NFS stopped to explore a separate repository boundary.

Why is repo2-path local on backup-1 even though the storage is remote?

pgBackRest sees a mounted filesystem path. NFS provides the remote storage below that filesystem interface; repo-host is a different pgBackRest transport relationship.

[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)
[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)
[Red Hat Enterprise Linux 9: deploying an NFS server](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_using_network_file_services/deploying-an-nfs-server_configuring-and-using-network-file-services)

### Add an S3 repository without putting AWS keys in the file

An object repository needs its own path, access policy, identity and recovery check.

NFS is unavailable, but the private S3 repository and its permitted credentials still survive.

#### Name the storage boundary

repo3-type=s3 selects object storage; repo3-path names a prefix within the assigned bucket. The endpoint and region must match the environment. This lab uses a private, versioned, encrypted bucket with TLS required, managed through Terraform. It is a separate storage service from nfs-1, but the tested layout is not a cross-account or cross-region disaster-recovery design.

#### Use the executing host identity

The primary and backup server receive a narrowly scoped EC2 role. pgBackRest uses repo3-s3-key-type=auto to obtain temporary credentials, so students do not paste long-lived AWS keys into pgbackrest.conf. The role can access only the assigned repository prefix. A forbidden-prefix test produced AccessDenied, proving that a working network connection does not imply permission to write anywhere in the bucket.

#### Operate and recover the repository

Students create the stanza, check archiving and perform full, differential and incremental backups in S3. Each type is restored and checked. The outage drill also restores through S3 while both original database services and NFS are stopped. Versioning retains previous object versions and adds storage cost; it is not a guarantee against deletion or a substitute for tested access, retention and recovery procedures.

If the bucket exists and HTTPS works, is the backup path ready?

Not yet. Verify the correct prefix, executing role, permitted object operations, stanza, archived WAL, backup metadata and an actual restore. Transport, authorization and recoverability are separate checks.

[Amazon S3: security best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
[Amazon S3: using versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
[IAM: roles for Amazon EC2](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html)
[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)

### Back up from the standby without forgetting the primary

pgBackRest coordinates with the primary and waits for the standby to replay the required WAL boundary.

The standby connection says streaming, but replay has been paused and a backup cannot proceed.

#### Receive and replay are different

A standby may receive WAL while replay is delayed or paused. The backup needs an appropriate replay boundary before it can safely use standby data. The actual detail logs show the primary backup-start location, a wait for standby replay and confirmation that the standby reached it. A single streaming status line does not establish all those conditions.

#### Choose the fallback policy deliberately

backup-standby=y requires the standby; n reads from the primary. The prefer setting permits primary fallback when a suitable standby is unavailable. A fallback can place unexpected read load on the writer, so it is an operating policy rather than an automatic improvement. This lab tests mandatory standby failure and successful primary and standby backups, recording where files were actually read.

#### Follow the evidence in the log

Bulk file lines identify pg-standby during the tested standby backup. Some files and backup coordination still involve pg-primary. When replay was paused, the bounded operation failed; after replay resumed, backups succeeded. Increasing a timeout might make a transient wait tolerable, but it cannot make a deliberately paused standby advance. Diagnose the role, replay state and current execution before changing limits.

Can backup-standby=y be treated as “the primary is never involved”?

No. The primary participates in backup coordination and some reads. The setting requires standby use for the applicable data-copy work; inspect the actual replay and file-source logs.

[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)
[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)
[PostgreSQL 16: standby servers](https://www.postgresql.org/docs/16/warm-standby.html)

### Protect data, credentials and host identity together

A usable backup path must also restrict who can read, change or destroy its contents.

A connection works after disabling a verification check, but it now trusts the wrong server.

#### Keep identities explicit

The platform pins host keys using authenticated EC2 console evidence. Service SSH uses restricted authorized keys and strict host checking. PostgreSQL replication uses TLS with server identity verification and SCRAM credentials. These controls answer different questions: which host is this, which account may connect, and what may that account do? Do not replace a failed identity check with automatic trust.

#### Keep the service-user boundary

postgres owns database data; pgbackrest on backup-1 owns its backup operations. NFS exports match the intended numeric owners and clients, with root_squash retained. Generated passwords and private keys stay in protected files and hidden-input flows. Teach students to inspect ownership and modes without displaying credential contents. Logs and copied troubleshooting messages must not become another credential store.

#### Describe the protection actually present

The lab uses encrypted EBS and S3 storage, verified SSH/TLS links where configured, and restricted private service ingress. Its NFS setup does not claim encryption in transit. Both NFS paths share one host, and the S3 role still has necessary repository write/delete privileges. Stronger administrative separation or immutable retention requires its own design and tests; the current configuration must not be described as providing them.

Does root_squash mean the NFS repository is encrypted?

No. It changes how client root identity is mapped for access checks. Confidentiality in transit is a separate property and is not established by that option.

[Red Hat Enterprise Linux 9: deploying an NFS server](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_using_network_file_services/deploying-an-nfs-server_configuring-and-using-network-file-services)
[PostgreSQL 16: TLS client verification](https://www.postgresql.org/docs/16/libpq-ssl.html)
[PostgreSQL 16: client authentication](https://www.postgresql.org/docs/16/client-authentication.html)
[IAM: roles for Amazon EC2](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html)

## Build an operating strategy

### Full, differential and incremental: follow the references

Backup types trade copy work for dependencies; restore follows the retained chain.

Sunday has a full backup, Monday a differential and Tuesday an incremental. A teammate wants to remove Sunday to save space.

#### Start with the full set

A full backup stores the required database files for that backup. It still needs the WAL required to become consistent. A differential records changes relative to the relevant full backup. An incremental records changes since the prior backup in its chain. Their manifests can reference earlier files, so a small incremental directory is not an independent miniature database.

#### Connect backup type to restore work

Restoring a selected incremental can require files from the full, a differential and earlier incrementals, plus WAL. pgBackRest resolves the references rather than asking the learner to manually concatenate directories. The lab inserted distinguishable rows around backup boundaries and restored full, differential and incremental selections to verify exactly which rows each recovery produced. The labels and observed records made the difference visible.

#### Use schedules to bound recovery effort

More frequent full backups can reduce dependency depth but consume copy time and repository space. Differential backups limit how far an incremental chain grows between fulls. Frequent incrementals reduce repeated copy work but do not eliminate continuous WAL or restore testing. Select the pattern using the backup window, change rate, storage budget and measured restore behavior, then preserve the complete selected chain.

Can Tuesday’s incremental be restored after removing a full backup it references?

No. Its metadata can identify files it did not copy again. Removing those referenced bytes breaks the chain, even if Tuesday’s own files are intact.

[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)
[pgBackRest: command reference](https://pgbackrest.org/command.html)

### Retain recoverable chains, not a count of folders

Retention affects both the available recovery history and repository growth.

The repository is filling up, and the oldest folder looks like an easy deletion target.

#### Read what the retention setting counts

The lab uses count-based full-backup retention. Keeping two full backups means preserving two full sets and the dependent backups required by that policy; it is not simply keeping two arbitrary files or two calendar days. Differential retention and time-based policies answer different requirements. Read the configured mode and the actual available backup history together before predicting what expire will remove.

#### Let the tool understand dependencies

Manual deletion can leave metadata that points at missing files. pgBackRest expiry understands the backup relationships and relevant WAL requirements. In the tested retention exercise, a third full backup caused the oldest full set to expire while the intended remaining chains stayed available. The separate broken-chain drill damaged only a disposable repository copy, so students could see the failure without destroying the original recovery options.

#### Relate retention to incident discovery

A mistake discovered after the retained recovery window may no longer have an available clean target. Define how long incidents might go unnoticed and which business or compliance history is required. Include WAL continuity and repository availability in the decision. S3 versioning can retain storage beyond the visible pgBackRest history, so account for object versions and lifecycle behavior instead of assuming expire instantly eliminates every billed byte.

Is keeping two full backups the same as keeping two days of recoverable history?

No. The retained times depend on when full backups actually succeeded, the policy mode and the available WAL. Inspect real timestamps and verify an appropriate restore boundary.

[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)
[pgBackRest: command reference](https://pgbackrest.org/command.html)
[Amazon S3: using versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)

### Monitor capacity and the newest usable recovery evidence

A quiet backup system may be healthy, stuck or no longer running at all.

Yesterday’s successful backup is still visible, but tonight’s cron job never started.

#### Watch more than repository bytes

Monitor the mounted filesystem, free capacity, inode pressure where relevant, database WAL growth and repository growth. An unavailable archive destination can cause unarchived WAL to accumulate on the primary. A growing replication slot can create another retention pressure. Identify which path is consuming space before deleting anything; database WAL and repository backup retention are related but different mechanisms.

#### Use freshness with an explicit expectation

The newest successful backup timestamp must be compared with the intended schedule and an allowed delay. A metadata file that still exists says nothing about whether the latest job ran. The tested job wrapper tracks the latest attempt separately from the latest verified success and detects an elapsed freshness threshold. A missing run is an incident even when there is no new ERROR line.

#### Validate recovery after repair

Freeing space or restoring a mount addresses a cause; it does not create the missed backup. Run the intended backup again, verify new clean metadata and check current archive health. Confirm alert state and schedule activity separately. Capacity alerts should arrive early enough to act, and their own delivery must be tested. Record the observed latest execution rather than repeatedly pointing to a historical green result.

Why can “last successful backup” remain green while protection is deteriorating?

The prior backup remains a historical success while current jobs fail or stop running. Compare freshness and the latest attempt with the expected schedule and the required recovery point.

[PostgreSQL 16: monitoring statistics](https://www.postgresql.org/docs/16/monitoring-stats.html)
[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)
[pgBackRest: command reference](https://pgbackrest.org/command.html)

### Schedule full, differential and incremental backups deliberately

A saved crontab describes intent; a fresh execution proves the scheduler actually ran it.

You install a Sunday full backup at 02:00 and expect incremental backups during the week.

#### Read the five time fields

A user crontab specifies minute, hour, day of month, month and day of week before the command. In this CentOS Cronie lab, CRON_TZ=UTC makes the intended timezone explicit. Sunday is written as day-of-week 0 in the examples; 1-6 selects Monday through Saturday. Comma-separated hours select several runs, while */5 in the minute field selects every five minutes. These are schedule syntax, not chained shell actions.

#### Use the real execution identity

Install the direct schedule as postgres on pg-primary and the server/S3 schedules as pgbackrest on backup-1. Cron has a smaller environment than an interactive login, so the exercise uses explicit paths and a declared PATH. Separate the full, differential and incremental entries. Disable an alternate scheduler for the same job to avoid accidentally running both cron and systemd copies.

#### Prove the run after installation

The proof uses a short-lived canary schedule, waits for its actual time and accepts only a job that started after that schedule was installed. It checks the job identity, requested type, fresh metadata and exit status. journalctl with the CROND identifier shows per-user execution entries that a crond service-unit filter alone may miss. Restore the regular schedule after the canary and inspect it again.

Does crontab -l prove that the scheduled backup succeeded?

It proves which entries are installed for that user. Confirm a later CROND execution and correlate it to the wrapper result and fresh clean pgBackRest metadata.

[Cronie: crontab format](https://github.com/cronie-crond/cronie/blob/master/man/crontab.5)
[systemd: journalctl](https://www.freedesktop.org/software/systemd/man/latest/journalctl.html)
[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)

## Operate, observe and tune

### Keep backup failure separate from notification delivery

A delivered alert does not repair a backup, and a failed notification must not disappear.

Backup job J42 fails. The local email receiver accepts its alert, but the HTTP receiver returns 503.

#### First establish the job result

The tested wrapper serializes one job with a lock, runs pgBackRest and preserves its failure exit. A successful exit is accepted only when metadata contains a new backup of the requested type without recorded checksum errors. The wrapper stores the current attempt, last verified success and a private log path. Another overlapping invocation is refused instead of starting an uncontrolled second copy.

#### Track each notification channel

A failure creates an event correlated to its job ID and pgBackRest execution ID. Each channel keeps its own delivery status. In the lab, local SMTP accepted the event while the HTTP receiver rejected it; the pending webhook was retained and retried without resending the already acknowledged email. Crash timing can still require at-least-once delivery, so downstream deduplication should use the event identity.

#### Test what the recipient claim means

The demonstrated email and HTTP receivers run locally in the lab. Their acceptance does not prove Slack, Teams or a person’s inbox received the message. A real provider needs its correct payload, credentials, transport and delivery checks. After repairing the original backup cause, run a new backup and verify its data protection result. Retrying an alert changes notification state, not the failed backup’s historical outcome.

If the webhook retry returns 2xx, may the failed backup be marked successful?

No. It proves acknowledgement of that notification. The backup needs a new successful attempt with fresh clean metadata and the appropriate recovery checks.

[pgBackRest: command reference](https://pgbackrest.org/command.html)
[Cronie: crontab format](https://github.com/cronie-crond/cronie/blob/master/man/crontab.5)

### Read a log as a timeline of one attempt

Choose the component, identify the execution and connect the error to a fresh recovery check.

The first ERROR in the file is from yesterday, while the current job has a different execution ID.

#### Find the right layer

The wrapper log tells you which scheduled job ran and its exit status. pgBackRest logs explain options, stanza, repository, file source and archive or protocol errors. PostgreSQL logs explain archiving and recovery behavior; NFS/service logs explain availability below the repository. CROND entries show that the scheduler invoked a user command. Start at the symptom and follow the responsible layer instead of treating every failure as a database outage.

#### Correlate before interpreting

Read the timestamp, host, execution ID, command-begin line and matching command-end line. Keep timezone and the job’s start time in view. An INFO startup line can precede a FATAL recovery failure, while a WARN about a new timeline may accompany a successful, expected operation. The lab retains both old failed attempts and later successful attempts; severity alone cannot tell you which result is current.

#### Turn a cause into a bounded action

For Permission denied, inspect the relevant path, mount and service-user ownership. For AccessDenied, inspect the selected S3 prefix and executing role. For an archive wait, correlate the missing segment with primary archiving. Make one justified repair and rerun the same check with a new timestamp or execution ID. Share a minimal excerpt without passwords, private keys, session tokens or signed request headers.

What makes “the error is fixed” stronger than “I no longer see ERROR”?

A new execution after the repair completes the intended operation and passes its independent checks. Correlate that success with the job, repository, archive and recovered data rather than absence of a word.

[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)
[PostgreSQL 16: monitoring statistics](https://www.postgresql.org/docs/16/monitoring-stats.html)
[systemd: journalctl](https://www.freedesktop.org/software/systemd/man/latest/journalctl.html)

### Edit the file used by the process you are testing

Configuration scope begins with the host, user, command and selected profile.

You increase process-max on backup-1, but a direct backup running on pg-primary behaves exactly as before.

#### Identify the executing command

The primary’s archive command reads its default pgbackrest.conf. A direct backup explicitly selects /etc/pgbackrest/direct.conf. A backup launched on backup-1 reads that host’s default file and has remote PostgreSQL hosts plus a locally mounted repository. Those files may look similar but control different invocations. Read the command-begin log to see which effective settings actually reached the process.

#### Understand section and option precedence

The academy stanza contains database-specific connection information. Global options apply broadly, and command-specific sections such as global:archive-push can narrow a setting to one operation. Command-line options can override a value in the file. Keep one intended value in the correct section and inspect the resolved options; a successful edit or matching line in an unrelated file is not evidence that the command used it.

#### Apply and roll back deliberately

Preserve the current file, make one change, run the relevant operation and compare results. A new pgBackRest invocation reads its configuration; there is no general pgBackRest database service to restart for every edit. PostgreSQL has its own settings with reload or restart requirements. For example, archive_mode requires restart while archive_timeout is a different server setting. Verify the owning component and effective value, then restore the previous file when the experiment ends.

Why might a correct edit appear to have no effect?

The command may execute on another host, select a different profile or override the value on its command line. A long-running owning service may also require reload or restart for that particular parameter.

[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)
[PostgreSQL 16: WAL and recovery configuration](https://www.postgresql.org/docs/16/runtime-config-wal.html)

### Make the backup faster only when the evidence supports it

Parallelism, compression, source choice and checkpoint behavior trade resources against elapsed time.

A backup window is too long, and someone proposes setting every concurrency limit to a large value.

#### Change one meaningful variable

process-max changes permitted parallel work; more processes may help until CPU, disk, network or repository throughput becomes the constraint. Compression reduces stored or transferred bytes at a CPU cost, depending on the algorithm, level and data. start-fast requests a faster starting checkpoint, which can increase immediate database I/O. Standby read offload still requires primary coordination. None of these settings is a universal “make it fast” switch.

#### Read the measured tradeoff

One tiny-lab comparison measured approximately 10.43 seconds with one process and Zstandard, 7.45 seconds with two processes and Zstandard, and 7.20 seconds with two processes and LZ4, including the harness SSH overhead. LZ4 stored roughly 6.01 MB versus 3.70 MB for Zstandard. These were single ordered runs over small compressible data, affected by caching and background activity; they do not establish production capacity or a guaranteed speedup.

#### Keep correctness in the experiment

Each tested variant produced clean full-backup metadata and restored the expected payload and business total. Invalid process-max and timeout relationships were also rejected before acceptance. Preserve archive consistency and page-checksum checks, monitor the source workload, and compare restore behavior as well as backup duration. Record the baseline and revert the file after the exercise so later results have a known starting configuration.

Would you choose LZ4 solely because its single run was 0.25 seconds faster here?

No. That difference may reflect normal run variation. Evaluate repeatable timing, CPU/I/O impact, storage/network cost and recovery behavior against a representative workload and the required backup window.

[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)
[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)

### Use asynchronous archiving without losing the recovery chain

Understand where WAL waits, what the spool records and what success actually acknowledges.

A burst of WAL arrives while the repository has limited throughput.

#### Separate PostgreSQL from pgBackRest settings

PostgreSQL archive_mode and archive_command enable and invoke archiving. Its archive_timeout can force a segment switch during activity so partially filled segments are offered sooner. pgBackRest archive-timeout is a different setting: it bounds how long backup/check waits for required WAL to appear in the archive. Increasing that wait does not increase transfer throughput or prove a fresher recovery point.

#### Understand the asynchronous worker

With archive-async enabled, pgBackRest can reuse connections and parallelize archive work. The tested setup uses a local postgres-owned spool and two archive-push processes. For archive-push, source WAL remains under PostgreSQL’s pg_wal while the spool records status and errors; it is not a second remote backup repository. Inspect worker logs and confirm the actual WAL segment reached every required repository.

#### Protect the boundary under pressure

The lab verifies async worker completion, archived WAL in all three repositories and PITR through that WAL, then restores the previous settings. Do not casually set a queue-dropping limit to hide storage pressure: archive-push-queue-max can acknowledge and discard WAL when its limit is exceeded, breaking continuous recovery beyond the gap. Repair the cause, establish what WAL survives and take a new valid backup when the old continuity cannot be recovered.

Does a larger archive-timeout make WAL move faster?

No. It permits a longer wait in backup/check. Diagnose generation rate, network/storage throughput, archive errors and effective worker settings; verify the resulting archived segments.

[PostgreSQL 16: WAL and recovery configuration](https://www.postgresql.org/docs/16/runtime-config-wal.html)
[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)

## Recover deliberately and prove the result

### Create a safe place to inspect a restore

Separate the recovered copy’s path, port, access rules and archive behavior from the source.

You need to inspect last night’s backup while the source database remains available.

#### Keep original evidence intact

Choose a new empty recovery directory and a separate port. The lab uses isolated paths under /var/lib/pgsql and ports separate from 5432 for rehearsal. Preserve the original cluster instead of restoring over it. A copied postgresql.conf can contain paths that redirect startup to the original data directory, so explicitly inspect and set the recovered instance’s actual configuration before starting it.

#### Contain the recovered instance

Rehearsal configuration binds locally, uses explicit local access rules and disables archiving on the recovered copy. This avoids accidentally publishing rehearsal WAL into the source repository. The restore needs the correct repository configuration and credentials, and its generated restore_command must remain usable during recovery. Changing the final listen port alone does not address copied file paths, authentication or archive settings.

#### Check all the boundaries after startup

Wait until PostgreSQL accepts connections, then use the intended socket and recovery port. Check data_directory, archive_mode, pg_is_in_recovery and the expected records. A response from an already-running source instance can make a misdirected check look successful. Stop the rehearsal copy after collecting proof unless the exercise explicitly continues toward cutover. Preserve its logs and the selected backup/target for diagnosis.

Why does the Guide ask the restored server to report data_directory?

It confirms which database instance answered the query. Otherwise a correct-looking result from the source could be mistaken for evidence about the recovered copy.

[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)
[PostgreSQL 16: database file layout](https://www.postgresql.org/docs/16/storage-file-layout.html)
[pgBackRest: command reference](https://pgbackrest.org/command.html)

### Choose a timestamp or named recovery point

PITR starts from a suitable backup and replays a continuous WAL history to the selected target.

You know the safe state existed before an unwanted transaction committed.

#### Choose a reachable boundary

The chosen backup must precede the target in a usable history, and all required WAL must remain available. A timestamp should include an explicit timezone and be understood relative to transaction commit. A named restore point is a WAL record created at a deliberate safe point. Record the target when it is established; inventing a convenient name after the incident does not create that record in old WAL.

#### Understand stopping behavior

A recovery target and target-action control what happens when PostgreSQL reaches the requested boundary. The rehearsal explicitly promotes the isolated copy after the target is reached, then verifies that it left recovery. A nonexistent or unavailable target can make recovery terminate before reaching the configured target. Do not treat restored files or initial startup output as proof that the requested stopping point was achieved.

#### Connect the target to business data

The lab places distinguishable records before and after named and timestamp boundaries. Correct PITR includes the intended records and excludes the later marker. The incident drill also recovers amounts, a deleted row and a dropped table. Verify both presence and absence conditions, and state which later valid writes are omitted by the earlier target. A target that is technically reachable can still be the wrong business choice.

Can a backup made after the bad update undo it by replaying to an earlier time?

A physical restore cannot replay WAL backward. Choose a usable backup before the intended safe target and replay forward through a continuous history to that boundary.

[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)
[PostgreSQL 16: WAL and recovery configuration](https://www.postgresql.org/docs/16/runtime-config-wal.html)
[pgBackRest: command reference](https://pgbackrest.org/command.html)

### Diagnose the missing WAL segment instead of guessing a target

A broken WAL history can prevent consistency or prevent reaching a requested recovery point.

Recovery reports that it ended before the configured target was reached.

#### Read the recovery attempt

Identify the recovered instance, selected backup, requested target and current startup log. Look for the exact missing segment or timeline history and compare it with the repository and archive-push history. A missing target message can mean the named point never existed in that history, required WAL is unavailable, or the target selection is wrong. The message alone does not identify which of those causes applies.

#### Repair only with valid surviving evidence

The lab removes a required segment from a disposable repository copy and observes recovery fail. Returning the exact preserved segment allows the same intended target to recover. In a real incident, locate a valid surviving copy through approved recovery sources; do not fabricate a segment, rename an unrelated file or skip required WAL. If the gap is permanent, the desired target may no longer be attainable.

#### Reassess the recovery claim

A reachable earlier target may have a different data-loss boundary, while a later fresh backup may establish a new usable starting point. Document what can be proved and obtain the appropriate business acceptance for the chosen path. Recheck archive health after the cause is fixed. A backup job succeeding later does not retrospectively restore continuity in an older broken recovery window.

Does increasing archive-timeout reconstruct a missing historical WAL file?

No. Waiting can help only if a valid required segment is still expected to arrive. Investigate actual surviving WAL and the target history before changing the wait.

[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)
[PostgreSQL 16: WAL and recovery configuration](https://www.postgresql.org/docs/16/runtime-config-wal.html)
[pgBackRest: configuration reference](https://pgbackrest.org/configuration.html)

### A readable incremental can still depend on missing files

Follow manifest references and preserve the original repository during diagnosis.

The latest incremental exists, but its referenced full backup was manually removed.

#### Identify the selected chain

Read pgBackRest info and the selected backup label, then inspect the failure and its referenced set. Incremental and differential backups can refer to files in older backups rather than storing every byte again. The newest directory being present therefore does not prove all data required for restore exists. Separate missing backup files from missing WAL because the repair sources and failure stage can differ.

#### Use a disposable copy for the exercise

The lab copies a repository to an isolated incident path before removing a base set. A dependent incremental restore fails and does not leave a valid completed pg_control suitable for startup. Restoring the preserved missing set repairs the chain and the required records recover. The original repository remains available, so the exercise teaches diagnosis without consuming the only good recovery option.

#### Fix the operating process too

If manual deletion or an external storage lifecycle broke the chain, correct that process as well as the immediate files. Let pgBackRest retention reason about its own dependencies. Inspect S3 lifecycle/version behavior and administrative deletion permissions separately. After repair, run an actual restore of the intended selection and retain the observed data result; listing a returned folder is not the final proof.

Why practice missing-chain faults on a repository copy?

It preserves the verified original recovery path and lets the learner compare failure, repair and exact recovered data without damaging the only available backup.

[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)
[pgBackRest: command reference](https://pgbackrest.org/command.html)
[Amazon S3: using versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)

### Recover an UPDATE, deletion or dropped table with the right target

A healthy database can contain validly committed damage, including on its standby.

An application maintenance command removes a row that should still exist.

#### Contain the incident before adding more ambiguity

Record the current state and stop the harmful workload or change path. Determine when the unwanted operation committed and what valid work occurred afterward. Avoid immediately destroying the current cluster: it may contain later valid records that an earlier PITR target would exclude. The course uses synthetic data and explicitly preserves the old source state during its recovery drills.

#### Test the target against the incident

The lab deliberately restores a point after the bad update. PostgreSQL starts and the row count looks normal, but the order total is zero, so that copy is rejected. A safe earlier point returns the expected total of 600. Timestamp recovery restores an accidentally deleted row, and an S3-backed recovery restores a dropped business table. Each case needs a data-specific acceptance check.

#### Decide how recovered data will be used

Whole-cluster PITR selects one history for the recovered cluster; it is not an automatic per-table undo facility. An isolated recovery may instead provide data for a carefully designed reconciliation, which requires its own integrity checks. The lab’s capstone performs a bounded whole-cluster cutover and names the later order excluded by the chosen target. Do not describe that result as preserving every acknowledged write.

Why is the expected row count insufficient for the wrong-update drill?

All three rows can still exist while their values are wrong. Check the business values and target boundary as well as count, connectivity and recovery state.

[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)
[PostgreSQL 16: WAL and recovery configuration](https://www.postgresql.org/docs/16/runtime-config-wal.html)

### Recover when the original database services are unavailable

Use the surviving repository, validate an isolated copy and accept the data-loss boundary before cutover.

Both original database services are stopped. In another drill, the NFS service is stopped too.

#### Identify what actually survived

The backup-server NFS path can serve a restore when database services are down if its repository and host remain available. S3 can serve the tested recovery when NFS is also unavailable. The restore still needs a host, storage capacity, network access, credentials and the retained backup/WAL chain. These drills prove service/storage-outage recovery on surviving lab hosts; they do not prove replacement after every physical host is lost.

#### Accept the recovered copy before directing traffic

The lab restores to an isolated directory and validates the intended records. A limited application account authenticates and reads the expected order total before the recovered data is moved to the canonical service path. Keep the old writer excluded from application writes while choosing the recovered history. Declare the exact target and excluded later work; a successful connection alone cannot make that decision for the business.

#### Measure the complete cutover

Start timing from the defined outage point and stop at the required application acceptance check, not when file copy ends. Preserve the old data and record the selected backup, target, logs and final endpoint. Check service configuration after moving the recovered data. The tiny synthetic lab’s elapsed time demonstrates the procedure, while a production recovery rehearsal must account for realistic data size, restore throughput and WAL replay.

If S3 survives, is disaster recovery automatically complete?

No. A surviving repository is one dependency. Prove access, a usable chain, correct recovery, application authentication/data and an accepted cutover boundary on the actual recovery host.

[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)
[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)
[IAM: roles for Amazon EC2](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html)

### After promotion, rebuild redundancy and restart protection

Recovery creates a new history to protect; a successful cutover is not the last operational step.

The recovered primary works, but the old standby still belongs to the previous history.

#### Recognize the new timeline

Promotion after recovery creates a new PostgreSQL timeline. The tested capstone verifies timeline 2 and keeps the previous data directories as evidence. A timeline-change warning in a subsequent backup can be expected, but the warning is interpreted alongside the selected history, fresh backup metadata and archived segment names. Neither suppressing the warning nor seeing it once proves the whole recovery is healthy.

#### Rebuild the replica deliberately

The lab preserves the old standby directory and takes a fresh TLS-verified base backup from the accepted primary, with a physical replication slot and recorded access settings. It then starts the standby and verifies streaming plus the accepted business data. A merely running standby service could still point at the wrong source or fail to replay the new history, so confirm those relationships directly.

#### Restore the next recovery option

Run new backups against every configured repository and confirm clean metadata and WAL from the new timeline. Recheck cron ownership, schedule entries, freshness and notification state after the repair. Review the cause and revise the operating procedure where necessary. The system should leave the exercise with an accepted primary, a verified standby and new recovery evidence, rather than a single recovered database with silently broken backups.

Why run backups again after the restored application succeeds?

The accepted history and operational paths may have changed. Fresh backups and archive evidence establish that the next incident has a working recovery path on that new history.

[PostgreSQL 16: standby servers](https://www.postgresql.org/docs/16/warm-standby.html)
[PostgreSQL 16: pg_basebackup](https://www.postgresql.org/docs/16/app-pgbasebackup.html)
[PostgreSQL 16: continuous archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html)
[pgBackRest: RHEL user guide](https://pgbackrest.org/user-guide-rhel.html)

