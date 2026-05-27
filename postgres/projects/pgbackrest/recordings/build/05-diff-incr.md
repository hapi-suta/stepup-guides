# Video Script: BUILD 05 - Differential and Incremental Backups

**Video file:** `pgbackrest-build-05-diff-incr.mp4`
**Estimated length:** 12 minutes
**Guide:** [Link to guide](../../build/05-differential-incremental.md)
**Server state required:** Guides 01-04 complete. pgBackRest installed, stanza configured, WAL archiving working, at least 1 full backup exists. PostgreSQL 16 running.

---

## INTRO [0:00]

[SAY] "This is pgBackRest BUILD 5: Differential and Incremental Backups."
[SAY] "Full backups copy everything. But if your database is 800MB and only 10MB changed, why copy all 800MB again? That's where differential and incremental backups come in."
[SAY] "By the end of this video, you will know how to take both types, understand the size differences, and know when to use each one."
[SAY] "Make sure you have completed guides 01 through 04 before starting. You need at least one full backup already taken."

---

## STEP 1: Connect and switch to postgres [0:30]

[SAY] "Let's connect to our server and switch to the postgres user."
[TYPE] `ssh -i your-key.pem ec2-user@your-server-ip`
[WAIT for login]
[SAY] "Now switching to the postgres user."
[TYPE] `sudo -i -u postgres`
[WAIT for prompt change]

---

## STEP 2: Verify the full backup exists [1:00]

[SAY] "Before we take a differential backup, let's confirm we have a full backup to build on."
[TYPE] `pgbackrest --stanza=main info`
[WAIT for output]
[SHOW] the full backup entry
[SAY] "Good. We have one full backup. Look at the repo backup size - remember this number. We're going to compare it to the differential and incremental backups in a few minutes."
[PAUSE]

---

## STEP 3: Generate data changes with pgbench [1:45]

[SAY] "Right now, our database hasn't changed much since the last full backup. We need to create some changes so the differential backup has something new to capture."
[SAY] "We'll use pgbench - it's a benchmarking tool that ships with PostgreSQL. It generates thousands of small transactions against the database. Think of it as simulating a busy application."
[TYPE] `/usr/pgsql-16/bin/pgbench -c 2 -T 30 labdb`
[SAY] "The dash c 2 flag means two concurrent connections. Dash capital T 30 means run for 30 seconds. And labdb is the database to run against."
[WAIT for output - about 30 seconds]
[SAY] "There we go. About 12 or 13 thousand transactions processed. That's a lot of changed data pages."
[SHOW] the "number of transactions actually processed" line
[PAUSE]

---

## STEP 4: Take a differential backup [3:00]

[SAY] "Now let's take a differential backup. A differential backup only copies data that changed since the last full backup."
[TYPE] `pgbackrest --stanza=main --type=diff backup`
[WAIT for output]
[SHOW] the backup label in the output
[SAY] "Look at the backup label. See that D at the end? That stands for Differential. Full backups end with F. This naming convention makes it easy to tell them apart."
[SAY] "Notice how much faster that was compared to the full backup. It only had to copy the pages that changed."
[PAUSE]

---

## STEP 5: Compare sizes - full vs diff [4:00]

[SAY] "Let's look at both backups side by side."
[TYPE] `pgbackrest --stanza=main info`
[WAIT for output]
[SHOW] the full backup's repo backup size
[SAY] "Here's the full backup. Look at the repo backup size."
[PAUSE]
[SHOW] the diff backup's repo backup size
[SAY] "And here's the differential backup. Look at how much smaller the repo backup size is. The full backup was the entire database. The differential was just the pages that changed since that full backup."
[SHOW] the "backup reference" line on the diff
[SAY] "Also notice the backup reference line - it says this differential backup depends on 1 full backup. It can't exist on its own. To restore from this diff, pgBackRest would need the full backup plus the diff."
[PAUSE]

---

## STEP 6: Generate more changes [5:30]

[SAY] "Let's create more changes for an incremental backup."
[TYPE] `/usr/pgsql-16/bin/pgbench -c 2 -T 30 labdb`
[WAIT for output - about 30 seconds]
[SAY] "Another round of transactions. More changed pages."
[PAUSE]

---

## STEP 7: Take an incremental backup [6:30]

[SAY] "Now here's the key difference. A differential backup copies everything that changed since the last full backup. An incremental backup copies everything that changed since the last backup of any type - full, diff, or incremental."
[SAY] "Since we just took a diff backup a minute ago, the incremental only needs to capture changes since that diff."
[TYPE] `pgbackrest --stanza=main --type=incr backup`
[WAIT for output]
[SHOW] the backup label
[SAY] "See the I at the end of the label? That's for Incremental."
[PAUSE]

---

## STEP 8: Compare all three backups [7:30]

[SAY] "Now let's see all three backups together. This is the payoff."
[TYPE] `pgbackrest --stanza=main info`
[WAIT for output]
[SAY] "Look at the three repo backup sizes from top to bottom."
[SHOW] full backup size
[SAY] "Full - the largest. That's the entire database."
[SHOW] diff backup size
[SAY] "Differential - smaller. That's everything that changed since the full."
[SHOW] incr backup size
[SAY] "Incremental - even smaller. That's only what changed since the diff."
[PAUSE]
[SHOW] the backup reference line on the incremental
[SAY] "And look at the incremental's backup reference - it depends on 1 full and 1 diff. This is the dependency chain."
[PAUSE]

---

## STEP 9: The dependency chain [9:00]

[CONCEPT] "Let me explain the dependency chain because this is critical for understanding restore speed."
[SAY] "A full backup stands alone. It needs nothing else. You can restore from just that one backup."
[PAUSE]
[SAY] "A differential backup needs the full backup. Two backups total to restore."
[PAUSE]
[SAY] "An incremental backup needs the full, plus every incremental backup in the chain before it. If you took five incremental backups in a row, restoring from the fifth one requires all five plus the full. That's six backups."
[SAY] "So there's a trade-off. Incremental backups are faster to take - less data each time. But they're slower to restore because pgBackRest has to reconstruct from the whole chain."
[PAUSE]

---

## STEP 10: Scheduling strategies [10:15]

[SAY] "So how do you use this in practice? Here's the most common strategy."
[SAY] "Sunday: take a full backup. Fresh start for the week."
[SAY] "Monday through Saturday: take differential backups. Each one only needs Sunday's full to restore. At most, you need two backups to restore from any day of the week."
[PAUSE]
[SAY] "Another strategy mixes all three. Full on Sunday, differential on Wednesday as a mid-week safety net, and incremental on the other days. This saves more space but has a slightly more complex restore chain."
[SAY] "For most teams, weekly full plus daily differential is the sweet spot. It's simple, it's fast to restore, and it doesn't use much extra space."
[SAY] "We'll set up automated scheduling in guide 07."

---

## STEP 11: Clean up [11:15]

[SAY] "Let's exit the postgres user."
[TYPE] `exit`
[WAIT for prompt change]

---

## OUTRO [11:30]

[SAY] "That's BUILD 5 complete. You now understand all three backup types - full, differential, and incremental. You know how they compare in size and how the dependency chain works."
[SAY] "Next up is the big one - BUILD 6: Restore and Point-in-Time Recovery. We're going to simulate a disaster and recover from it. Then we'll do time travel - restoring the database to an exact moment in time."
[SAY] "Pause this video and practice on your own server before moving on."
