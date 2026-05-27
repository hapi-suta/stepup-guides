# Video Script: BUILD 01 - Install pgBackRest

**Video file:** `pgbackrest-build-01-install.mp4`
**Estimated length:** 8 minutes
**Guide:** [Link to guide](../../build/01-install-pgbackrest.md)
**Server state required:** PostgreSQL 16 installed and running. archive_command set to /bin/false. SSH access as ec2-user.

---

## INTRO [0:00]

[SAY] "This is pgBackRest BUILD 1: Install pgBackRest."

[SAY] "Here's the situation. Your PostgreSQL server has a broken backup setup. The archive_command is set to /bin/false - that means every single WAL archive attempt is failing. Your database has no safety net right now."

[SAY] "By the end of this video, you will have pgBackRest installed and ready to configure."

[SAY] "Make sure you have SSH access to your server and PostgreSQL 16 running. Let's jump in."

---

## STEP 1: SSH into the server [0:30]

[SAY] "First, let's connect to our server."

[TYPE] `ssh -i your-key.pem ec2-user@your-server-ip`

[WAIT for login]

[SAY] "Good, we're in."

---

## STEP 2: Verify PostgreSQL is running [0:50]

[SAY] "Before we do anything, let's make sure PostgreSQL is actually running."

[TYPE] `sudo systemctl status postgresql-16`

[WAIT for output]

[SHOW] the "active (running)" text in green

[SAY] "Right there - active, running. PostgreSQL is up. If yours says inactive or failed, stop and ask your instructor for help."

[PAUSE]

[SAY] "Press q to exit this status view."

---

## STEP 3: See the broken state [1:20]

[SAY] "Now let's see proof that backups are broken. We need to switch to the postgres operating system user first."

[TYPE] `sudo -i -u postgres`

[SAY] "Now open psql - that's the PostgreSQL command-line tool."

[TYPE] `psql`

[WAIT for psql prompt]

[SAY] "Let's check the archive status."

[TYPE] `SELECT archived_count, failed_count, last_failed_time FROM pg_stat_archiver;`

[WAIT for output]

[PAUSE]

[SAY] "Look at this."

[SHOW] the failed_count column

[SAY] "archived_count is zero. Zero WAL files successfully archived. And failed_count - look at that number. Hundreds of failures. Every single archive attempt has failed."

[PAUSE]

[SAY] "Now let's see why."

[TYPE] `SHOW archive_command;`

[WAIT for output]

[SHOW] /bin/false in the output

[SAY] "There it is. archive_command equals /bin/false."

[CONCEPT] "What does /bin/false actually do? It's a Linux command that does absolutely nothing except return an error code. Every time PostgreSQL finishes writing a WAL file and tries to archive it, it runs this command, and it fails. Every time. This means WAL files are piling up and none of them are being safely stored anywhere. If this server crashes right now, those WAL files are gone forever."

[PAUSE]

[SAY] "Let's exit out of psql and the postgres user."

[TYPE] `\q`

[TYPE] `exit`

---

## STEP 4: Install the EPEL repository [3:30]

[SAY] "Now let's fix this. Step one is installing pgBackRest. It lives in a repository called EPEL."

[CONCEPT] "EPEL stands for Extra Packages for Enterprise Linux. CentOS and RHEL come with a limited set of packages by default. EPEL is a free, community-maintained collection of additional software. pgBackRest is one of those additional packages."

[TYPE] `sudo dnf install -y epel-release`

[WAIT for output]

[SAY] "The -y flag means answer yes to all prompts so we don't have to confirm manually."

[SHOW] the "Complete!" line

[SAY] "EPEL is installed."

---

## STEP 5: Install pgBackRest [4:30]

[SAY] "Now we can install pgBackRest itself."

[TYPE] `sudo dnf install -y pgbackrest`

[WAIT for output - this may take 30-60 seconds]

[SAY] "dnf is downloading and installing pgBackRest and any dependencies it needs."

[SHOW] the "Installed: pgbackrest" line

[SHOW] the "Complete!" line

[SAY] "Done. pgBackRest is installed."

---

## STEP 6: Verify the installation [5:30]

[SAY] "Let's confirm it works."

[TYPE] `pgbackrest version`

[WAIT for output]

[SAY] "pgBackRest 2.54 - or whatever version you see. As long as you get a version number back, you're good."

---

## STEP 7: Explore the installation [5:50]

[SAY] "Let's take a quick look at what got installed."

[TYPE] `which pgbackrest`

[WAIT for output]

[SAY] "/usr/bin/pgbackrest - that's where the binary lives. The which command tells you the full path to any command."

[PAUSE]

[SAY] "Now let's see all the files that came with the pgBackRest package."

[TYPE] `rpm -ql pgbackrest | head -20`

[WAIT for output]

[SAY] "rpm -ql lists every file that belongs to an installed package. head -20 just shows the first 20 lines so it doesn't flood your screen."

[SHOW] /etc/pgbackrest.conf in the output

[SAY] "See that? /etc/pgbackrest.conf. The package created a configuration file for us. That's where we'll tell pgBackRest about our database and where to store backups. We'll do that in the next video."

[SHOW] /usr/bin/pgbackrest in the output

[SAY] "And there's the binary we just ran."

---

## OUTRO [7:15]

[SAY] "That's BUILD 1 complete. Let's recap what we did."

[SAY] "We confirmed that WAL archiving was broken - archive_command was set to /bin/false and hundreds of archive attempts had failed."

[SAY] "We installed the EPEL repository, installed pgBackRest, and verified the installation."

[SAY] "pgBackRest is on your server now, but it doesn't know anything about your database yet. In the next video, BUILD 2, we configure pgBackRest by creating a stanza - a named configuration that connects pgBackRest to your PostgreSQL cluster."

[SAY] "See you there."
