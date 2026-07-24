# Build 06: Scheduling with Cron and Systemd Timers

You will learn how to schedule jobs that repeat. This is the backbone of database
maintenance. You will write a cron schedule and build a nightly backup example.
You will also learn the modern alternative, systemd timers. Backups, log
rotation, vacuum jobs, and cleanup all run on schedules a DBA sets up and watches.

**Time estimate:** 60 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. What is cron?

`cron` is a service that runs commands on a schedule. You give it a schedule and
a command. It runs that command at the right time, every time, with no one logged
in. This is how nightly backups and routine maintenance run by themselves.

Each user has their own list of scheduled jobs called a **crontab** (cron table).

> **Concept - Cron Runs Unattended:** The whole point of cron is that jobs run
> when no human is watching. That leads to two rules you must respect. First, cron
> jobs run with a bare-bones environment (a short `PATH`, no shell profile). So
> always use full paths to commands inside cron jobs. Second, no one sees the
> output live. So send it to a log file, or you will never know if the job failed.

---

## 2. Cron syntax - The five time fields

A crontab line has five time fields, then the command to run. The fields, in
order, are:

```
* * * * *  command-to-run
| | | | |
| | | | +--- day of week   (0-6, 0 = Sunday)
| | | +----- month         (1-12)
| | +------- day of month  (1-31)
| +--------- hour          (0-23)
+----------- minute        (0-59)
```

A `*` in a field means "every value". Here are common examples:

- `0 2 * * *` - every day at 02:00 (2 AM)
- `30 3 * * 0` - every Sunday at 03:30
- `*/15 * * * *` - every 15 minutes
- `0 */6 * * *` - every 6 hours, on the hour
- `0 0 1 * *` - at midnight on the first day of every month

> **Concept - Read Fields Left to Right, Small to Big:** The fields go from the
> smallest unit (minute) to the largest (day of week). A common beginner mistake
> is reading the first field as the hour. Say it out loud: "minute, hour, day of
> month, month, day of week". `0 2 * * *` reads as "minute 0, hour 2, every day".
> That is 2 AM daily.

---

## 3. crontab -e - Edit your schedule

`crontab -e` opens your personal crontab in an editor. The first time you run it,
you may be asked which editor to use. Choose `vi`.

Set `vi` as the editor for this session, then open the crontab:

```bash
export EDITOR=vi
```

```bash
crontab -e
```

- `export EDITOR=vi` - tell `crontab` to use `vi` as the editor
- `crontab -e` - the `-e` flag means "edit"

Press `i` to enter insert mode, then add a simple test job that writes the date
to a file every minute:

```
* * * * * /usr/bin/date >> /home/ec2-user/cron-test.log 2>&1
```

- `* * * * *` - every minute
- `/usr/bin/date` - the full path to the `date` command (full path because cron
  has a minimal `PATH`)
- `>> /home/ec2-user/cron-test.log` - add the output to the end of a log file
- `2>&1` - also send any error messages to the same log

Press `Esc`, type `:wq`, and press Enter to save. Cron confirms the new schedule:

```
Expected output (yours will differ):
crontab: installing new crontab
```

Wait about a minute, then check the log:

```bash
cat /home/ec2-user/cron-test.log
```

```
Expected output (yours will differ):
Wed Jul  8 07:23:01 PM UTC 2026
Wed Jul  8 07:24:01 PM UTC 2026
```

Each line proves cron ran the job on schedule.

---

## 4. crontab -l - List, and cleaning up

View your current crontab without editing it:

```bash
crontab -l
```

The `-l` flag lists your jobs.

```
Expected output (yours will differ):
* * * * * /usr/bin/date >> /home/ec2-user/cron-test.log 2>&1
```

Remove the test job so it does not fill your log forever. Open the crontab again:

```bash
crontab -e
```

Move the cursor to the test line, press `dd` to delete the whole line, then press
`Esc`, type `:wq`, and press Enter.

---

## 5. A nightly backup example

Here is a real-world DBA cron job. It runs a PostgreSQL logical backup every
night at 2 AM and logs the result. Do not add this now unless PostgreSQL is
installed. Just read it to see the shape of a real backup job.

```
0 2 * * * /usr/bin/pg_dump -U postgres appdb > /opt/pgsql/backup/appdb-$(date +\%Y\%m\%d).sql 2>> /opt/pgsql/backup/backup.log
```

Break it down:

- `0 2 * * *` - every day at 2 AM
- `/usr/bin/pg_dump -U postgres appdb` - dump the `appdb` database as user
  `postgres`, using the full path to `pg_dump`
- `> /opt/pgsql/backup/appdb-$(date +\%Y\%m\%d).sql` - write to a file named with
  today's date, like `appdb-20260706.sql`
- `2>> .../backup.log` - append any errors to a backup log

Note the backslashes before each `%` in the date format. In a crontab, a bare `%`
has a special meaning. It marks the end of the command. So when you want a real
percent sign, you must escape it as `\%`.

> **DBA Context - Cron Is Where Backups Live:** Almost every backup you run in
> production is triggered by cron or a timer. The job itself is a script. Cron
> just decides when. Two rules keep you out of trouble. Always log the output
> (`2>>` to a log) so a silent failure cannot hide. And always use full paths so
> the bare-bones cron environment does not break the job. A backup that fails
> silently is worse than no backup. You think you are protected, but you are not.

---

## 6. Systemd timers - The modern alternative

CentOS Stream 9 also offers **systemd timers**, a newer way to schedule jobs.
Timers can do more than cron. They log to the central journal. They can run a
missed job after the server was off (`Persistent=true`). And they handle
dependencies between jobs.

A timer needs two files. A `.service` says what to run. A `.timer` says when to
run it. You do not need to create these for this course. The goal is just to
recognize them and inspect them.

List all timers on the system:

```bash
systemctl list-timers
```

`list-timers` shows every active timer, when it last ran, and when it runs next.

```
Expected output (yours will differ):
NEXT                        LEFT          LAST PASSED UNIT                 ACTIVATES
Wed 2026-07-08 20:10:49 UTC 48min left    -    -      dnf-makecache.timer  dnf-makecache.service
Thu 2026-07-09 00:00:00 UTC 4h 37min left -    -      logrotate.timer      logrotate.service

3 timers listed.
```

- `NEXT` - when the timer fires next
- `LAST` - when it last fired
- `UNIT` - the timer's name

On your server, these built-in timers already handle two jobs. `logrotate.timer`
rotates logs. `dnf-makecache.timer` updates the package cache.

> **DBA Context - Cron or Timer?** Both work. Cron is simpler and works
> everywhere, so it is still common. Timers tie into systemd's logging. They are
> better when a job must run after downtime or depends on other services. Many
> teams use cron for quick jobs and timers for anything that must be reliable and
> easy to watch. Know both. You will inherit servers using either one.

---

## 7. Checking that scheduled jobs actually ran

A schedule you never check is a schedule you cannot trust. Here are two ways to
confirm a job ran.

For cron, the system logs each run to the journal. Each command run is logged
under the `CROND` identifier (a separate name from the `crond` daemon itself), so
filter by that identifier with `-t`:

```bash
sudo journalctl -t CROND --since "1 hour ago"
```

- `journalctl` - read the systemd journal (the central log)
- `-t CROND` - only entries tagged with the `CROND` identifier (the per-run
  command log lines)
- `--since "1 hour ago"` - limit to the last hour

```
Expected output (yours will differ):
Jul 08 19:23:01 ip-172-31-6-0.ec2.internal CROND[16500]: (ec2-user) CMD (/usr/bin/date >> /home/ec2-user/cron-test.log 2>&1)
Jul 08 19:23:01 ip-172-31-6-0.ec2.internal CROND[16498]: (ec2-user) CMDEND (/usr/bin/date >> /home/ec2-user/cron-test.log 2>&1)
```

For a systemd timer, check its status or the service it triggers:

```bash
sudo systemctl status logrotate.timer
```

```
Expected output (yours will differ):
● logrotate.timer - Daily rotation of log files
     Loaded: loaded (/usr/lib/systemd/system/logrotate.timer; enabled; preset: enabled)
     Active: active (waiting) since Wed 2026-07-08 19:19:11 UTC; 4min ago
    Trigger: Thu 2026-07-09 00:00:00 UTC; 4h 36min left
   Triggers: ● logrotate.service
```

`Trigger:` tells you when it fires next. Press `q` to exit.

> **DBA Context - Trust But Verify:** The most dangerous words in database
> operations are "the backup runs every night" when no one has checked the log in
> months. Whether you use cron or a timer, build the habit of checking that jobs
> actually ran and succeeded. The journal (`journalctl`) is where the proof lives.
> A job that is scheduled but silently failing is a disaster waiting for a
> restore.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what cron is and why jobs need full paths and logged output
- [ ] Read the five cron time fields in order (minute, hour, day, month, weekday)
- [ ] Write a schedule for "every day at 2 AM" and "every 15 minutes"
- [ ] Add a job with `crontab -e` and confirm it ran
- [ ] List your jobs with `crontab -l` and delete one
- [ ] Explain the shape of a nightly `pg_dump` backup cron job
- [ ] Explain why `%` must be escaped as `\%` in a crontab
- [ ] List systemd timers with `systemctl list-timers`
- [ ] Explain when a timer is a better choice than cron
- [ ] Verify a cron run with `journalctl -t CROND`
