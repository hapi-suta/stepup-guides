# Video Script: BUILD 02 - Configure Your First Stanza

**Video file:** `pgbackrest-build-02-stanza.mp4`
**Estimated length:** 10 minutes
**Guide:** [Link to guide](../../build/02-configure-stanza.md)
**Server state required:** PostgreSQL 16 running. pgBackRest installed (BUILD 01 complete). archive_command still set to /bin/false.

---

## INTRO [0:00]

[SAY] "This is pgBackRest BUILD 2: Configure Your First Stanza."

[SAY] "pgBackRest is installed, but it doesn't know anything about your database. It doesn't know where PostgreSQL stores its data. It doesn't know where you want backups to go. We fix that by creating a stanza."

[CONCEPT] "A stanza is a named configuration. Think of it as a label. When you run any pgBackRest command, you pass the stanza name so it knows which database cluster you're working with. We're going to name ours 'main'."

[SAY] "By the end of this video, you'll have a working stanza with a fully initialized backup repository."

[SAY] "Make sure you've completed BUILD 1 and have pgBackRest installed. Let's go."

---

## STEP 1: SSH into the server [0:40]

[SAY] "Connect to your server."

[TYPE] `ssh -i your-key.pem ec2-user@your-server-ip`

[WAIT for login]

---

## STEP 2: Write the configuration file [1:00]

[SAY] "The pgBackRest configuration file lives at /etc/pgbackrest.conf. Let's open it with vi."

[TYPE] `sudo vi /etc/pgbackrest.conf`

[WAIT for vi to open]

[SAY] "The file might be empty or have some comments. We're going to replace everything."

[SAY] "If there's existing content, press Escape to make sure you're in normal mode, then type g-g-d-G to delete all lines."

[SAY] "Now press i to enter insert mode. You should see INSERT at the bottom of the screen."

[PAUSE]

[SAY] "Now type this configuration with me. I'm going to go line by line and explain each setting."

[SAY] "First, the global section. This applies to all stanzas."

[TYPE] `[global]`

[SAY] "Next, where do we store backups?"

[TYPE] `repo1-path=/opt/pgsql/backup/pgbackrest`

[SAY] "repo1-path tells pgBackRest the directory where all backups and archived WAL files will be stored. repo1 means repository number 1 - pgBackRest supports multiple repositories, but we only need one."

[PAUSE]

[TYPE] `repo1-retention-full=2`

[SAY] "Retention full equals 2. This means keep the 2 most recent full backups. When you take a third full backup, the oldest one gets automatically deleted. This prevents your disk from filling up."

[TYPE] `process-max=2`

[SAY] "process-max equals 2. This tells pgBackRest to use 2 CPU threads for compression and other work. More threads means faster backups, but we keep it modest on a lab server."

[TYPE] `log-level-console=info`

[SAY] "log-level-console equals info. When you run pgBackRest commands, you'll see informational messages on screen so you know what's happening."

[TYPE] `log-level-file=detail`

[SAY] "log-level-file equals detail. The log file gets more verbose output. This is useful when you need to troubleshoot a problem later."

[TYPE] `start-fast=y`

[CONCEPT] "start-fast equals y. When a backup starts, PostgreSQL needs to do something called a checkpoint - flushing all buffered data to disk. Normally it waits for the next scheduled checkpoint, which could be minutes away. With start-fast, pgBackRest tells PostgreSQL to checkpoint immediately so the backup starts right away."

[TYPE] `compress-type=lz4`

[SAY] "compress-type equals lz4. This tells pgBackRest to compress backups and WAL archives using lz4 compression. lz4 is fast and gives a good compression ratio - you'll typically see 5 to 6x savings."

[PAUSE]

[SAY] "Now, a blank line, then the stanza section."

[TYPE] (blank line)

[TYPE] `[main]`

[SAY] "This is our stanza named 'main'. If we had a second database cluster, we'd add another section with a different name."

[TYPE] `pg1-path=/opt/pgsql/data`

[SAY] "pg1-path tells pgBackRest where the PostgreSQL data directory is. This is where PostgreSQL stores all your databases, tables, and indexes."

[PAUSE]

[SAY] "That's the entire configuration. Press Escape to exit insert mode, then type colon-w-q and press Enter to save and quit."

---

## STEP 3: Verify the configuration [4:00]

[SAY] "Let's make sure the file was saved correctly."

[TYPE] `sudo cat /etc/pgbackrest.conf`

[WAIT for output]

[SHOW] the full configuration

[SAY] "Check yours against mine. Make sure there are no typos - especially in the paths. A wrong path here will cause errors later."

---

## STEP 4: Create the backup repository directory [4:30]

[SAY] "The repo1-path directory doesn't exist yet. Let's create it."

[TYPE] `sudo mkdir -p /opt/pgsql/backup/pgbackrest`

[SAY] "mkdir -p creates the directory and any parent directories that are missing. The -p flag also prevents an error if the directory already exists."

---

## STEP 5: Set ownership [4:50]

[SAY] "pgBackRest runs as the postgres user, so postgres needs to own this directory."

[TYPE] `sudo chown postgres:postgres /opt/pgsql/backup/pgbackrest`

[SAY] "And the config file too."

[TYPE] `sudo chown postgres:postgres /etc/pgbackrest.conf`

[SAY] "chown changes the owner of a file or directory. postgres:postgres means user postgres, group postgres."

---

## STEP 6: Create the stanza [5:20]

[SAY] "Now the big moment. Let's create the stanza. Switch to the postgres user first."

[TYPE] `sudo -i -u postgres`

[SAY] "Run the stanza-create command."

[TYPE] `pgbackrest --stanza=main stanza-create`

[WAIT for output]

[SHOW] the "completed successfully" line

[SAY] "Completed successfully. The stanza is created."

[CONCEPT] "What did stanza-create actually do? It initialized the repository structure. It created subdirectories for backups and WAL archives, and it wrote metadata files that pgBackRest uses to track everything. You only run stanza-create once per stanza. After this, you never run it again."

---

## STEP 7: Run the check command [6:10]

[SAY] "Let's verify the stanza is properly configured."

[TYPE] `pgbackrest --stanza=main check`

[WAIT for output]

[SHOW] the error about archive_command

[SAY] "You'll see an error about archive_command. Don't panic - this is expected. We haven't changed archive_command yet. It's still set to /bin/false from before. We'll fix that in BUILD 3."

[SAY] "The important thing here is that there's no configuration error. pgBackRest can see your database and the repository is valid."

---

## STEP 8: Explore the repository structure [6:50]

[SAY] "Let's look at what stanza-create built inside the repository."

[TYPE] `ls /opt/pgsql/backup/pgbackrest/`

[WAIT for output]

[SHOW] archive and backup directories

[SAY] "Two directories. archive - where archived WAL files will go. backup - where your full, differential, and incremental backups will go."

[TYPE] `ls /opt/pgsql/backup/pgbackrest/archive/`

[WAIT for output]

[SHOW] main directory

[SAY] "Inside archive, there's a directory called main - that's our stanza name."

[TYPE] `ls /opt/pgsql/backup/pgbackrest/backup/`

[WAIT for output]

[SAY] "Same thing inside backup. A main directory."

[TYPE] `ls /opt/pgsql/backup/pgbackrest/backup/main/`

[WAIT for output]

[SHOW] backup.info and backup.info.copy

[SAY] "Inside the backup/main directory, there are two files: backup.info and backup.info.copy. These are metadata files that pgBackRest uses to track all your backups. The .copy file is a redundant copy for safety - if one gets corrupted, pgBackRest can fall back to the other."

[PAUSE]

[SAY] "Let's exit the postgres user."

[TYPE] `exit`

---

## OUTRO [8:45]

[SAY] "That's BUILD 2 complete."

[SAY] "We wrote the pgBackRest configuration file with all the settings - repository path, retention, compression, logging. We created the backup directory, set the ownership, and initialized the stanza."

[SAY] "The repository structure is built and ready. But we still have that broken archive_command. Every WAL file is still failing to archive."

[SAY] "In the next video, BUILD 3, we fix the archive_command and watch the first successful WAL archive happen. See you there."
