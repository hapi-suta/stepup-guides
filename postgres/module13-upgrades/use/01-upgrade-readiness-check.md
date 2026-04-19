# Exercise 01 - Upgrade Readiness Check

Run `pg_upgrade --check` against the PG15 and PG16 test clusters and interpret every line of output.

**Run on:** NODE1 only

---

## Setup

Make sure you have both clusters from Guide 02:

- PG15 at `/opt/pgsql/data15` (port 5433)
- PG16 target at `/opt/pgsql/data16`

Both must be stopped for `pg_upgrade --check`.

```
sudo -iu postgres
```

Stop PG15 if running.

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 stop -m fast
```

Stop PG16 target if running.

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 stop -m fast
```

```
exit
```

---

## Task 1: Run the Check

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --check
```

Expected output (yours will differ):

```
Performing Consistency Checks
-----------------------------
Checking cluster versions                                     ok
Checking database user is the install user                    ok
Checking database connection settings                         ok
Checking for prepared transactions                            ok
Checking for system-defined composite types in user tables    ok
Checking for reg* data types in user tables                   ok
Checking for contrib/isn with bigint-passing mismatch         ok
Checking for tables WITH OIDS                                 ok
Checking for invalid "sql_identifier" user columns            ok
Checking for presence of required libraries                   ok
Checking for multiple databases in the same tablespace        ok

*Clusters are compatible*
```

```
exit
```

---

## Task 2: Interpret Each Check Line

Answer the following questions. Look up the PostgreSQL documentation or release notes if needed.

**1. "Checking cluster versions"**

What does this check verify? What would cause it to fail?

> Write your answer here.

**2. "Checking for prepared transactions"**

What are prepared transactions (two-phase commit)? Why does pg_upgrade require there to be none before running?

> Write your answer here.

**3. "Checking for reg* data types in user tables"**

What is a `reg*` data type (e.g. `regclass`, `regproc`)? Why are these incompatible with pg_upgrade?

> Write your answer here.

**4. "Checking for tables WITH OIDS"**

OIDs on user tables were removed in PG12. If you were upgrading from PG11, why would tables WITH OIDS be a problem?

> Write your answer here.

**5. "Checking for presence of required libraries"**

What does this check look for? What would happen if pg_stat_statements was installed in PG15 but the `.so` file was missing from `/usr/pgsql-16/lib/`?

> Write your answer here.

---

## Task 3: Deliberately Trigger a Warning

Start PG15 and create a prepared transaction, then stop PG15 and re-run the check.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l /opt/pgsql/log/pg15.log start
```

Prepared transactions require `max_prepared_transactions > 0`. The default is 0 (disabled). Enable it first.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "ALTER SYSTEM SET max_prepared_transactions = 5;"
```

Restart PG15 for the setting to take effect (this parameter requires a restart).

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 restart -l /opt/pgsql/log/pg15.log
```

Now create a prepared transaction.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "BEGIN; INSERT INTO employees (name, department, salary) VALUES ('Prepared', 'Test', 60000); PREPARE TRANSACTION 'test_prepared_txn';"
```

Expected output:

```
PREPARE TRANSACTION
```

Stop PG15.

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 stop -m fast
```

Now run the check.

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --check
```

Expected output (yours will differ):

```
Checking for prepared transactions                            fatal

Your installation contains prepared transactions, which are not supported by pg_upgrade.
...
Failure, exiting
```

Now fix the issue. Start PG15, rollback the prepared transaction, stop PG15, and re-run the check to confirm it passes.

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l /opt/pgsql/log/pg15.log start
```

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "ROLLBACK PREPARED 'test_prepared_txn';"
```

Expected output:

```
ROLLBACK PREPARED
```

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 stop -m fast
```

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --check
```

Expected output (yours will differ):

```
*Clusters are compatible*
```

```
exit
```

---

## Checkpoint

- [ ] Ran `pg_upgrade --check` and got `Clusters are compatible`
- [ ] Explained what each check line verifies
- [ ] Deliberately introduced a prepared transaction, observed the fatal error, and fixed it
