# Build 3: Change in the Repo, Reload on the Server (45 min)

This is the loop the whole project exists for: tune the config IN THE REPO, review the diff, commit, push the file to the server, reload - and learn, live, which parameters reload and which demand a restart. Then publish the repo to GitHub.

Tested against a live PostgreSQL 16.11 server on 2026-07-22. Outputs are real captured outputs.

---

## Step 1: Tune in the repo - not on the server

On **your Mac**, in **~/Projects/pg-ops**, open the config:

```bash
vi config/pgforge-1/postgresql.conf
```

Make two changes:

1. Find `#work_mem = 4MB` and change it to `work_mem = 8MB` (remove the `#` - a commented line is a default, uncommenting activates your value)
2. Find `shared_buffers = 128MB` and change it to `shared_buffers = 256MB`

Save and quit with `:wq`.

## Step 2: Review the diff - every time, forever

```bash
git diff
```

Expected output (real, truncated):
```
diff --git a/config/pgforge-1/postgresql.conf b/config/pgforge-1/postgresql.conf
@@ -127,7 +127,7 @@ max_connections = 100			# (change requires restart)
-shared_buffers = 128MB			# min 128kB
+shared_buffers = 256MB			# min 128kB
@@ -138,7 +138,7 @@
-#work_mem = 4MB				# min 64kB
+work_mem = 8MB				# min 64kB
...
```

Removed lines start with `-`, added lines with `+`. Notice the file itself warns you: `max_connections = 100  # (change requires restart)` - PostgreSQL documents which parameters need what, right in the config.

## Step 3: Commit the change

```bash
git add config/pgforge-1/postgresql.conf
```

```bash
git commit -m "perf: raise work_mem 4->8MB and shared_buffers 128->256MB on pgforge-1"
```

## Step 4: Push the repo's file to the server

```bash
cat config/pgforge-1/postgresql.conf | ssh -i ~/.ssh/yourkey.pem ec2-user@YOUR_SERVER_IP 'sudo tee /var/lib/pgsql/16/data/postgresql.conf > /dev/null'
```

What this does: `cat` prints your repo copy, the pipe sends it over SSH, and `sudo tee` writes it into place on the server (tee keeps the file's owner - postgres - intact). The `> /dev/null` just hides tee's echo.

The repo is now the source of truth; the server has a copy. In Project 5, Ansible takes over this push - for now your hands ARE the deployment tool, so you feel every part of it.

## Step 5: Reload - and watch what changes and what does not

SSH into **pgforge-1**. On **pgforge-1**, as **ec2-user**:

```bash
sudo systemctl reload postgresql-16
```

Reload tells PostgreSQL to re-read the config WITHOUT disconnecting anyone. No output on success.

Switch to the postgres user:

```bash
sudo su - postgres
```

Check work_mem:

```bash
/usr/pgsql-16/bin/psql -c "SHOW work_mem;"
```

Expected output:
```
 work_mem
----------
 8MB
```

Changed. Now check shared_buffers:

```bash
/usr/pgsql-16/bin/psql -c "SHOW shared_buffers;"
```

Expected output:
```
 shared_buffers
----------------
 128MB
```

**Still the old value.** work_mem reloads; shared_buffers needs a restart. Getting this wrong in production means either a mystery ("why didn't my change apply?") or an accidental outage ("why did the DBA restart production at 2pm?").

## Step 6: Ask PostgreSQL what is waiting for a restart

Still as **postgres** on **pgforge-1**:

```bash
/usr/pgsql-16/bin/psql -c "SELECT name, setting, pending_restart FROM pg_settings WHERE pending_restart;"
```

Expected output:
```
      name      | setting | pending_restart
----------------+---------+-----------------
 shared_buffers | 16384   | t
(1 row)
```

PostgreSQL itself tracks it: shared_buffers has a pending change that needs a restart. (The 16384 is in 8kB pages - 16384 x 8kB = 128MB, the still-active old value.) This query is your friend before and after every config deployment.

Exit back to ec2-user:

```bash
exit
```

## Step 7: Restart - in a window you chose

On **pgforge-1**, as **ec2-user**:

```bash
sudo systemctl restart postgresql-16
```

Restart disconnects every session - on production this happens in a planned window, never casually.

Switch to postgres and verify:

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SHOW shared_buffers;"
```

Expected output:
```
 shared_buffers
----------------
 256MB
```

Both changes are live, and both are in history with a reviewed diff. That is the loop.

Exit twice - back to ec2-user, then back to your Mac:

```bash
exit
```

```bash
exit
```

## Step 8: Publish the repo to GitHub

On **your Mac**, in **~/Projects/pg-ops** (gh is already logged in as hafopezi10):

```bash
gh repo create pg-ops --public --source . --push
```

`--public` because this is portfolio. `--source .` uses this folder. `--push` uploads your commits right away.

Expected output (yours will differ):
```
https://github.com/hafopezi10/pg-ops
To https://github.com/hafopezi10/pg-ops.git
 * [new branch]      HEAD -> main
branch 'main' set up to track 'origin/main'.
```

Your offsite copy exists. Open the URL and look at the baseline commit and the tuning commit - the server's whole config story so far, readable by anyone you choose. Continue to Build 4 for the branch-and-PR loop.
