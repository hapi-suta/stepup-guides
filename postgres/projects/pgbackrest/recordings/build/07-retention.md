# Video Script: BUILD 07 - Retention Policy and Automated Scheduling

**Video file:** `pgbackrest-build-07-retention.mp4`
**Estimated length:** 10 minutes
**Guide:** [Link to guide](../../build/07-retention-and-scheduling.md)
**Server state required:** Guides 01-06 complete. At least one full backup exists on the current timeline. PostgreSQL 16 running. WAL archiving working.

---

## INTRO [0:00]

[SAY] "This is pgBackRest BUILD 7: Retention Policy and Automated Scheduling."
[SAY] "Every backup takes disk space. Without a retention policy, your backup disk eventually fills up and your next backup fails - usually at the worst possible time."
[SAY] "By the end of this video, your backups will clean themselves up automatically and run on a schedule with zero manual intervention."
[SAY] "Make sure you have completed guides 01 through 06 before starting."

---

## STEP 1: Connect to the server [0:30]

[SAY] "Let's connect."
[TYPE] `ssh -i your-key.pem ec2-user@your-server-ip`
[WAIT for login]

---

## STEP 2: Check the current retention setting [0:45]

[SAY] "First, let's look at our current pgBackRest configuration to see what retention is already set."
[TYPE] `sudo cat /etc/pgbackrest.conf`
[WAIT for output]
[SHOW] the repo1-retention-full=2 line
[SAY] "Right there - repo1-retention-full equals 2. This means pgBackRest keeps the 2 most recent full backups. When a 3rd full backup is taken, the oldest one gets automatically deleted."
[CONCEPT] "Think about what retention means for your recovery window. If you take weekly full backups and keep 2, your recovery window is about 2 weeks. If someone comes to you and says 'we accidentally deleted data 3 weeks ago,' you can't help them. Those backups are gone. Choose your retention based on how far back you might need to go."
[PAUSE]

---

## STEP 3: Switch to postgres and check current backups [1:30]

[SAY] "Let's switch to the postgres user and see what backups we have."
[TYPE] `sudo -i -u postgres`
[WAIT for prompt change]
[TYPE] `pgbackrest --stanza=main info`
[WAIT for output]
[SAY] "Note how many full backups are listed right now. We're going to take enough full backups to trigger the retention limit and watch pgBackRest automatically clean up."
[PAUSE]

---

## STEP 4: Take full backup - round 1 [2:15]

[SAY] "Let's take our first full backup."
[TYPE] `pgbackrest --stanza=main --type=full backup`
[WAIT for backup to complete]
[SAY] "Done. Let's check."
[TYPE] `pgbackrest --stanza=main info`
[WAIT for output]
[SAY] "Count the full backups. We might already be at 2 depending on what's left from earlier guides."
[PAUSE]

---

## STEP 5: Take full backup - round 2 [3:15]

[SAY] "Another full backup."
[TYPE] `pgbackrest --stanza=main --type=full backup`
[WAIT for backup to complete]
[TYPE] `pgbackrest --stanza=main info`
[WAIT for output]
[SAY] "If you already had 2 full backups, you might see expiration messages during this backup. That's normal - pgBackRest is enforcing the retention limit."
[PAUSE]

---

## STEP 6: Take full backup - round 3 (trigger expiration) [4:15]

[SAY] "One more. This should definitely trigger expiration. Watch the output carefully."
[TYPE] `pgbackrest --stanza=main --type=full backup`
[WAIT for backup to complete]
[SHOW] the expire and remove messages in the output
[SAY] "There it is. See those expire and remove lines? pgBackRest automatically deleted the oldest full backup to stay within our retention limit of 2."
[SAY] "Let's confirm."
[TYPE] `pgbackrest --stanza=main info`
[WAIT for output]
[SHOW] only 2 full backups listed
[SAY] "Only 2 full backups remain. The oldest one was automatically expired and removed. You didn't have to do anything - pgBackRest handles it."
[PAUSE]

---

## STEP 7: Add differential retention [5:30]

[SAY] "Right now we only have retention for full backups. Let's also configure how many differential backups to keep. We need to edit the configuration file."
[SAY] "I need to exit the postgres user because we're editing a system config file."
[TYPE] `exit`
[WAIT for prompt change]
[TYPE] `sudo vi /etc/pgbackrest.conf`
[WAIT for vi to open]
[SAY] "Find the line that says repo1-retention-full equals 2."
[SHOW] the repo1-retention-full=2 line
[SAY] "Move your cursor to that line. Press lowercase o to open a new line below and enter insert mode."
[TYPE] press `o`
[SAY] "Now type repo1-retention-diff equals 3."
[TYPE] `repo1-retention-diff=3`
[SAY] "This means pgBackRest keeps the 3 most recent differential backups per full backup. Older diffs get expired automatically."
[SAY] "Press Escape to exit insert mode."
[TYPE] press `Esc`
[SAY] "Type colon w q and press Enter to save and quit."
[TYPE] `:wq`
[WAIT for shell prompt]
[SAY] "Let's verify the change took effect."
[TYPE] `sudo cat /etc/pgbackrest.conf`
[WAIT for output]
[SHOW] both retention lines - repo1-retention-full=2 and repo1-retention-diff=3
[SAY] "Good. We now have retention for both full and differential backups."
[PAUSE]

---

## STEP 8: Set up automated backups with cron [7:00]

[SAY] "Now let's automate everything. Instead of manually running backup commands, we'll schedule them to run automatically using cron."
[CONCEPT] "Cron is a built-in Linux scheduler. Each cron entry has 5 time fields: minute, hour, day of month, month, and day of week. An asterisk means every. So 0 2 star star 0 means at minute 0, hour 2, every day of month, every month, on day of week 0 which is Sunday. In other words: every Sunday at 2 AM."
[PAUSE]
[SAY] "Cron jobs should run as the postgres user since that's who owns the database. Let's switch."
[TYPE] `sudo -i -u postgres`
[WAIT for prompt change]
[SAY] "Open the crontab editor."
[TYPE] `crontab -e`
[WAIT for editor to open]
[SAY] "Press i to enter insert mode and add these two entries."
[TYPE] press `i`
[SAY] "First line - full backup every Sunday at 2 AM."
[TYPE] `# pgBackRest full backup every Sunday at 2:00 AM`
[SAY] "Press Enter."
[TYPE] `0 2 * * 0 pgbackrest --stanza=main --type=full backup`
[SAY] "Press Enter twice for a blank line, then the second entry."
[TYPE] blank line
[TYPE] `# pgBackRest differential backup Mon-Sat at 2:00 AM`
[TYPE] `0 2 * * 1-6 pgbackrest --stanza=main --type=diff backup`
[PAUSE]
[SAY] "Let me break down those cron fields. Zero two star star zero means minute 0, hour 2 AM, every day, every month, Sunday. Zero two star star one dash six means the same time, but Monday through Saturday."
[SAY] "So every Sunday at 2 AM: full backup. Monday through Saturday at 2 AM: differential backup."
[SAY] "Press Escape, then colon w q to save."
[TYPE] press `Esc`
[TYPE] `:wq`
[WAIT for shell prompt]
[PAUSE]

---

## STEP 9: Verify the cron entries [8:30]

[SAY] "Let's confirm the cron entries were saved."
[TYPE] `crontab -l`
[WAIT for output]
[SHOW] both cron entries
[SAY] "Both entries are there. Full backup on Sunday, differential Monday through Saturday, both at 2 AM."
[PAUSE]

---

## STEP 10: Test the cron command manually [8:50]

[SAY] "Let's make sure the command that cron will run actually works. We'll run a differential backup manually."
[TYPE] `pgbackrest --stanza=main --type=diff backup`
[WAIT for backup to complete]
[SAY] "It works. If it works manually, it will work from cron."
[PAUSE]

---

## STEP 11: Check the log files [9:15]

[SAY] "One last thing. pgBackRest writes detailed logs for every operation. This is how you monitor and troubleshoot."
[TYPE] `ls /var/log/pgbackrest/`
[WAIT for output]
[SHOW] the log files
[SAY] "You can see log files for backup, expire, restore, and stanza-create. Each one is named after the stanza and the command."
[SAY] "Let's peek at the latest backup log."
[TYPE] `tail -20 /var/log/pgbackrest/main-backup.log`
[WAIT for output]
[SHOW] the DETAIL lines showing individual files
[SAY] "At the detail level, you can see every individual file that was backed up, with checksums and sizes. This is extremely useful when a backup is slow and you need to figure out why."
[SAY] "Now exit the postgres user."
[TYPE] `exit`
[WAIT for prompt change]
[PAUSE]

---

## OUTRO [9:45]

[SAY] "That's BUILD 7 complete. And with it, you've finished the entire pgBackRest BUILD series."
[PAUSE]
[SAY] "Congratulations. Let me recap what you've built across all seven guides."
[SAY] "You installed pgBackRest from scratch on CentOS Stream 9."
[SAY] "You configured a stanza to connect it to your PostgreSQL cluster."
[SAY] "You enabled WAL archiving so every transaction is safely stored."
[SAY] "You took full, differential, and incremental backups."
[SAY] "You restored from a backup after a simulated disaster."
[SAY] "You performed point-in-time recovery - restoring to an exact moment in time."
[SAY] "And now you have retention policies cleaning up old backups automatically, and cron jobs running backups on a schedule."
[PAUSE]
[SAY] "Your database has a real safety net. pgBackRest is installed, configured, archiving WAL, taking backups on schedule, and cleaning up after itself. This is a production-grade backup and recovery setup."
[SAY] "Pause this video and practice on your own server. Then move on to the SURVIVE exercises where we'll break things on purpose and you'll fix them under pressure."
