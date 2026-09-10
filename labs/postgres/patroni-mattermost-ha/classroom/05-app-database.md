# Create the application database

[Classroom home](README.md) · [Previous](04-haproxy.md) · [Next](06-verify.md)

## 16. Create the Mattermost database login

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


The application needs its own least-privilege PostgreSQL identity instead of the superuser.

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

Create the application login
Type this at the postgres=# database prompt. Type only the command.

```sql
CREATE ROLE mattermost LOGIN;
```


Create the PostgreSQL role that Mattermost will use. LOGIN allows it to connect; it does not grant superuser privileges.
Expected: Look for CREATE ROLE. If the role already exists, inspect it with the next check.

Check the new role
On pg-ha-1, type this at the postgres=# database prompt. Type only the command.

```bash
\du mattermost
```


List the mattermost database role and its attributes.
Expected: Find mattermost. It must not be a Superuser or show Cannot login.

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


## 17. Set the protected Mattermost database password

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


SCRAM authentication requires a password while chat and logs must never contain it.

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

Start the password change
Type this at the postgres=# database prompt. Type only the command.

```bash
\password mattermost
```


psql securely prompts for a new password without placing it in your SQL command or shell history.
Expected: Wait for Enter new password for user "mattermost":. The next two inputs will be hidden.

Enter the generated password
At the first password prompt, enter the value from Load protected password. Never paste it into Chat.
Type the private Mattermost database password when prompted. Input is hidden.

The terminal hides password input. No stars or letters appearing is normal.
Expected: Press Enter once. Wait for Enter it again:.

Enter the same password again
At Enter it again:, enter the same protected value.
Type the private Mattermost database password when prompted. Input is hidden.

The terminal hides password input. No stars or letters appearing is normal.
Expected: Press Enter. Wait for postgres=# before running the check. If it reports a mismatch, start the password action again.

Check that the role has a SCRAM password
On pg-ha-1, type this at the postgres=# database prompt. Type only the command.

```sql
select rolname, rolpassword like 'SCRAM-SHA-256%' as scram from pg_authid where rolname = 'mattermost';
```


Return the role name and a boolean indicating SCRAM storage. The query does not display the password or its stored hash.
Expected: Find mattermost and t under scram. t means true.

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


## 18. Create the Mattermost database

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Mattermost needs an isolated database owned by its application role.

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

Create the application database
Type this at the postgres=# database prompt. Type only the command.

```sql
CREATE DATABASE mattermost OWNER mattermost;
```


Create one database named mattermost and give its ownership to the application role.
Expected: Look for CREATE DATABASE.

Check the database owner
On pg-ha-1, type this at the postgres=# database prompt. Type only the command.

```bash
\l mattermost
```


List the mattermost database and its ownership.
Expected: Find mattermost in both the Name and Owner columns. If a pager opens, press q to return to postgres=#.

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

### Checkpoint

- [ ] The mattermost role has a SCRAM password and owns the mattermost database.

[Classroom home](README.md) · [Previous](04-haproxy.md) · [Next](06-verify.md)
