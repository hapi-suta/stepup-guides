# BUILD 02 - Connecting with edb-psql and edbplus

EPAS ships two command-line clients. `edb-psql` is the PostgreSQL-style client you
will live in day to day. `edbplus` is EDB's drop-in for Oracle's `sqlplus` - same
`SET` commands, same `@script.sql`, same `EXIT`. In this guide you connect with both.

EPAS listens on port **5444** (not 5432 - that difference trips up every new EPAS
DBA), the superuser is **enterprisedb**, and the default database is **edb**.

## 1. Connect with edb-psql over the local socket

`edb-psql` on the same server, run as the `enterprisedb` OS user, connects through a
local Unix socket and is trusted automatically (peer authentication) - no password
needed.

First switch to the `enterprisedb` user.

On **epas-single**, as **ec2-user**:

```bash
sudo -iu enterprisedb
```

- `-iu enterprisedb` starts a login shell as the `enterprisedb` account, the OS user
  that owns the database.

Now connect. Still as **enterprisedb** on **epas-single**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb
```

- `/usr/edb/as16/bin/edb-psql` - the EPAS client (the plain `psql` next to it works
  too; `edb-psql` adds EPAS-specific tab completion).
- `-p 5444` - EPAS's port. Leave this off and it tries 5432 and fails.
- `-d edb` - the default database. Leave this off and it tries to connect to a
  database named after your user (`enterprisedb`), which does not exist.

You are now at the `edb=#` prompt. Confirm who and where you are:

```
edb=# \conninfo
```

Expected output (yours will differ):

```
You are connected to database "edb" as user "enterprisedb" via socket in "/tmp" at port "5444".
```

List the databases with the `\l` meta-command:

```
edb=# \l
```

Expected output (yours will differ):

```
                    List of databases
   Name    |    Owner     | Encoding | ...
-----------+--------------+----------+----
 edb       | enterprisedb | UTF8     | ...
 postgres  | enterprisedb | UTF8     | ...
 template0 | enterprisedb | UTF8     | ...
 template1 | enterprisedb | UTF8     | ...
```

Leave the client:

```
edb=# \q
```

## 2. Give enterprisedb a password (edbplus needs one)

`edbplus` is a Java tool that connects over TCP, not the local socket - so peer
authentication does not apply and it **must** have a password. Set one now.

Still as **enterprisedb** on **epas-single**, open the client and set the password:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb -c "ALTER USER enterprisedb WITH PASSWORD 'LabPass2026';"
```

- `-c "..."` runs one SQL statement and exits - handy for one-liners.
- `ALTER USER ... WITH PASSWORD` stores the password (hashed with scram-sha-256).

Expected output (yours will differ):

```
ALTER ROLE
```

## 3. Allow password logins over TCP, then reload

By default EPAS's `pg_hba.conf` tells TCP connections to use `ident` authentication,
which has no password and will reject edbplus. Switch the localhost rule to
`scram-sha-256` (the method matching the password you just set).

Return to the ec2-user shell first:

```bash
exit
```

Now, on **epas-single**, as **ec2-user**, open the host-based auth file with vi:

```bash
sudo vi /var/lib/edb/as16/data/pg_hba.conf
```

Find this line:

```
host    all             all             127.0.0.1/32            ident
```

Change the last word from `ident` to `scram-sha-256`:

```
host    all             all             127.0.0.1/32            scram-sha-256
```

Save and quit vi (`Esc`, then type `:wq`, then `Enter`).

`pg_hba.conf` is re-read on a reload - no restart needed. Reload:

```bash
sudo systemctl reload edb-as-16
```

- No output on success.

## 4. Connect with edbplus

edbplus lives at `/usr/edb/edbplus/edbplus.sh` (it is not on your PATH, and it is
not under the `as16/bin` directory - use the full path).

Switch back to enterprisedb:

```bash
sudo -iu enterprisedb
```

Launch edbplus, giving it the Oracle-style connect string `user/password@host:port/db`.
Still as **enterprisedb** on **epas-single**:

```bash
/usr/edb/edbplus/edbplus.sh enterprisedb/LabPass2026@localhost:5444/edb
```

You land at the `SQL>` prompt - exactly like sqlplus. Run a query against `dual`, the
Oracle-compatibility table EPAS provides:

```sql
SQL> SELECT dummy FROM dual;
```

Expected output (yours will differ):

```
DUMMY
-----
X
```

That `X` from `dual` is EPAS's Oracle compatibility working - the same query returns
the same thing on an Oracle database. Exit edbplus:

```sql
SQL> EXIT;
```

Return to the ec2-user shell:

```bash
exit
```

## Checkpoint

You can now:

- [x] Connect with `edb-psql` on port 5444 to database `edb` as `enterprisedb`
- [x] Read `\conninfo` and `\l`
- [x] Set a role password and understand why edbplus needs it but edb-psql does not
- [x] Switch a `pg_hba.conf` rule to `scram-sha-256` and reload
- [x] Run `edbplus` with an Oracle-style connect string and query `dual`

Next: **BUILD 03 - Configuration files and making changes take effect.**
