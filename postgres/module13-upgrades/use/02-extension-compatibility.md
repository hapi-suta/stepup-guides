# Exercise 02 - Extension Compatibility

List every extension installed in a PG15 cluster, verify which ones exist in PG16, and identify any that would block or require action during an upgrade.

**Run on:** NODE1 only

---

## Setup

Start the PG15 cluster.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l /opt/pgsql/log/pg15.log start
```

Expected output:

```
waiting for server to start.... done
server started
```

---

## Task 1: List All Installed Extensions

List extensions in every non-template database.

```
/usr/pgsql-15/bin/psql -p 5433 -c "SELECT datname FROM pg_database WHERE datistemplate = false;" -t -A
```

Expected output (yours will differ):

```
postgres
upgradetest
```

Check extensions in the postgres database.

```
/usr/pgsql-15/bin/psql -p 5433 -d postgres -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
```

Expected output (yours will differ):

```
       extname        | extversion
----------------------+------------
 pg_stat_statements   | 1.10
 plpgsql              | 1.0
(2 rows)
```

Check extensions in upgradetest.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
```

Expected output (yours will differ):

```
       extname        | extversion
----------------------+------------
 pg_stat_statements   | 1.10
 plpgsql              | 1.0
(2 rows)
```

```
exit
```

---

## Task 2: Install an Additional Extension in PG15

Install the `uuid-ossp` extension so you have more extensions to audit.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
```

Expected output:

```
CREATE EXTENSION
```

Also install `pg_buffercache`.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "CREATE EXTENSION IF NOT EXISTS pg_buffercache;"
```

Expected output:

```
CREATE EXTENSION
```

Verify all three are installed.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
```

Expected output (yours will differ):

```
       extname        | extversion
----------------------+------------
 pg_buffercache       | 1.3
 pg_stat_statements   | 1.10
 plpgsql              | 1.0
 uuid-ossp            | 1.1
(4 rows)
```

```
exit
```

---

## Task 3: Check Each Extension Exists in PG16

For each extension installed in PG15, verify the binary and control file exist in the PG16 directories.

Check `pg_stat_statements`.

```
ls /usr/pgsql-16/lib/pg_stat_statements.so
```

Expected output:

```
/usr/pgsql-16/lib/pg_stat_statements.so
```

```
ls /usr/pgsql-16/share/extension/pg_stat_statements.control
```

Expected output:

```
/usr/pgsql-16/share/extension/pg_stat_statements.control
```

Check `uuid-ossp`.

```
ls /usr/pgsql-16/lib/uuid-ossp.so
```

Expected output:

```
/usr/pgsql-16/lib/uuid-ossp.so
```

Check `pg_buffercache`.

```
ls /usr/pgsql-16/lib/pg_buffercache.so
```

Expected output:

```
/usr/pgsql-16/lib/pg_buffercache.so
```

Check `plpgsql` (built-in, always present).

```
ls /usr/pgsql-16/lib/plpgsql.so
```

Expected output:

```
/usr/pgsql-16/lib/plpgsql.so
```

---

## Task 4: Check Version Compatibility

Look at the control file to see what version is available in PG16.

```
cat /usr/pgsql-16/share/extension/pg_stat_statements.control
```

Expected output (yours will differ):

```
# pg_stat_statements extension
comment = 'track planning and execution statistics of all SQL statements executed'
default_version = '1.10'
module_pathname = '$libdir/pg_stat_statements'
relocatable = true
```

The `default_version` in PG16 is `1.10`. The installed version in PG15 was also `1.10`. If the installed version in PG15 is older than the `default_version` in PG16, you will need to run `ALTER EXTENSION ... UPDATE` after the upgrade.

Check uuid-ossp.

```
cat /usr/pgsql-16/share/extension/uuid-ossp.control
```

Expected output (yours will differ):

```
# uuid-ossp extension
comment = 'generate universally unique identifiers (UUIDs)'
default_version = '1.1'
module_pathname = '$libdir/uuid-ossp'
relocatable = false
```

---

## Task 5: Simulate a Missing Extension Binary

What happens if an extension exists in PG15 but not in PG16? Simulate this by stopping PG15 and running `pg_upgrade --check`.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 stop -m fast
```

Temporarily rename the pg_buffercache binary in PG16 to simulate it being missing.

```
exit
```

```
sudo mv /usr/pgsql-16/lib/pg_buffercache.so /usr/pgsql-16/lib/pg_buffercache.so.bak
```

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
Checking for presence of required libraries                   fatal

Your installation references loadable libraries that are missing from the
new installation.  You can add these libraries to the new installation,
or remove the functions using them from the old installation.  A list of
problem libraries is in the file:
    loadable_libraries.txt
...
Failure, exiting
```

```
exit
```

Restore the binary.

```
sudo mv /usr/pgsql-16/lib/pg_buffercache.so.bak /usr/pgsql-16/lib/pg_buffercache.so
```

```
sudo -iu postgres
```

Re-run `pg_upgrade --check` to confirm it passes now.

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --check
```

Expected output:

```
*Clusters are compatible*
```

```
exit
```

---

## Checkpoint

- [ ] Listed all extensions across all databases in PG15
- [ ] Verified each extension's `.so` and `.control` files exist in PG16
- [ ] Compared installed versions in PG15 against the default version in PG16
- [ ] Simulated a missing extension binary and observed the `pg_upgrade --check` fatal error
- [ ] Restored the binary and confirmed the check passes
