# Verify replication and receive the app

[Classroom home](README.md) · [Previous](05-app-database.md) · [Next](07-switchover.md)

## PART 2 — PROVE THE STACK WORKS

Run these checks before any switchover. pg-ha-1 should still be the writer.


## 19. Inspect streaming replication

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Check the writer’s count of streaming replication connections.

Switch to the postgres user
Start in the Linux terminal on pg-ha-1, as ec2-user.

```bash
sudo -iu postgres
```


sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
Expected: The prompt should identify postgres: [postgres@pg-ha-1 ~]$.

Connect to PostgreSQL
Type this in the postgres Linux shell.

```bash
/opt/pgsql/bin/psql -h /var/run/postgresql -d postgres
```


The full path selects this lab’s psql program. -h selects the local socket directory; -d selects the postgres database.
Expected: Wait for postgres=#. You are now entering SQL or psql commands.

Check replication
Type this at the postgres=# database prompt. Type only the command.

```sql
select state,count(*) from pg_stat_replication group by state;
```


Count the writer’s replication connections in each state. The semicolon ends this one SQL statement.
Expected: Look for streaming with count 2. This does not measure replay lag.

Leave PostgreSQL
After reading the checks, type this at postgres=#.

```bash
\q
```


Leave the database client and return to Linux.
Expected: You should see the postgres shell prompt again.

Return to your original user
Type this in the postgres Linux shell.

```bash
exit
```


Close the nested shell before the next lesson.
Expected: The prompt should identify ec2-user again.


## 20. Verify data placement and checksums

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Correct storage and checksums are prerequisites for safe recovery.

Switch to the postgres user
Start in the Linux terminal on pg-ha-2, as ec2-user.

```bash
sudo -iu postgres
```


sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
Expected: The prompt should identify postgres: [postgres@pg-ha-2 ~]$.

Connect to PostgreSQL
Type this in the postgres Linux shell.

```bash
/opt/pgsql/bin/psql -h /var/run/postgresql -d postgres
```


The full path selects this lab’s psql program. -h selects the local socket directory; -d selects the postgres database.
Expected: Wait for postgres=#. You are now entering SQL or psql commands.

Check the data directory
Type this at the postgres=# database prompt. Type only the command.

```sql
show data_directory;
```


SHOW reports the current setting. data_directory identifies where PostgreSQL stores the cluster files.
Expected: Look for /opt/pgsql/data.

Check whether checksums are enabled
Type this at the postgres=# database prompt. Type only the command.

```sql
show data_checksums;
```


Page checksums help detect corrupted data pages. This separate SHOW reports whether they are enabled.
Expected: Look for on. Both this result and the data-directory result are required.

Leave PostgreSQL
After reading the checks, type this at postgres=#.

```bash
\q
```


Leave the database client and return to Linux.
Expected: You should see the postgres shell prompt again.

Return to your original user
Type this in the postgres Linux shell.

```bash
exit
```


Close the nested shell before the next lesson.
Expected: The prompt should identify ec2-user again.


## INSTRUCTOR APP HANDOFF

The instructor prepares the Mattermost server after the database stack is ready.
Give the instructor DB_ROUTER_1_IP, database name mattermost, username mattermost,
and the database password through the agreed private channel.
The instructor supplies APP_IP and the approved browser URL once the app is connected.
Open that URL (http://APP_IP:8065 when direct lab access is enabled).
Do not put APP_IP into the HAProxy backend list. Those are PostgreSQL nodes.
Do not replace the router address in PostgreSQL pg_hba with APP_IP: PostgreSQL
sees HAProxy as the TCP client in this configuration.
If lab networking requires an application-source allowlist, authorize APP_IP/32
to the router on TCP 5432 through the instructor-managed IaC/network policy.
The app IP is not entered into etcd or Patroni membership.

In the browser, open Mattermost using the approved lab URL or forwarded port.
Create the first account if needed, sign in and post a test message. Reload and
confirm the message is still present. The ping API proves service responsiveness;
it does not prove that users can sign in or that their messages survive.

### Checkpoint

- [ ] Two streaming connections are visible; the instructor app can sign in, save a message and show it after reload.

[Classroom home](README.md) · [Previous](05-app-database.md) · [Next](07-switchover.md)
