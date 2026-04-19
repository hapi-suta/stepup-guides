# Scenario 03 - Locale Mismatch: New Cluster Initialized with Wrong Locale

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: pg_upgrade is failing with a locale incompatibility.
The new cluster was initialized with a different locale
than the old cluster. The upgrade cannot proceed.
```

---

## Key Concepts for Revision

- **What locale controls** - The locale setting determines how PostgreSQL sorts strings, compares characters, and classifies characters (upper/lower case, digits). It is embedded in every index that involves text columns. A change in locale invalidates all text indexes because the sort order may differ between locales.

- **Why pg_upgrade checks locale** - If the old and new clusters have different locales, indexes in the new cluster would be sorted incorrectly - the data would be there but the index entries would be in the wrong order. This causes silent data corruption where queries return wrong results or miss rows. pg_upgrade refuses to proceed rather than allow this.

- **pg_controldata shows locale** - `pg_controldata` reads the `pg_control` binary file inside the data directory and prints cluster metadata including the locale, encoding, and block size. You do not need a running cluster to read it.

- **The only fix is reinitialize** - You cannot change a cluster's locale after `initdb`. The locale is baked into every database and every text index. The resolution is always: wipe the incorrectly initialized target directory and re-run `initdb` with the correct locale.

- **Where to find the old cluster's locale** - `pg_controldata` on the old cluster, or `SHOW lc_collate;` on a running old cluster. Always capture this before starting the upgrade preparation.

---

## Diagnostic Steps

### Step 1 - Attempt pg_upgrade --check and read the error

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
Checking cluster versions                                     ok
Checking database user is the install user                    ok
Checking database connection settings                         ok
lc_collate cluster values do not match:  old "en_US.UTF-8", new "C"
Failure, exiting
```

The error is clear: `lc_collate` differs between old (`en_US.UTF-8`) and new (`C`).

### Step 2 - Confirm the old cluster's locale

```
/usr/pgsql-15/bin/pg_controldata /opt/pgsql/data15 | grep -i lc_
```

Expected output:

```
LC_COLLATE:                           en_US.UTF-8
LC_CTYPE:                             en_US.UTF-8
```

### Step 3 - Confirm the new cluster's (wrong) locale

```
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data16 | grep -i lc_
```

Expected output:

```
LC_COLLATE:                           C
LC_CTYPE:                             C
```

Mismatch confirmed. The new cluster was initialized with locale `C` instead of `en_US.UTF-8`.

```
exit
```

---

## Resolution

### Step 1 - Wipe the incorrectly initialized target directory

```
sudo -iu postgres
```

```
rm -rf /opt/pgsql/data16
```

### Step 2 - Create the directory again

```
mkdir -p /opt/pgsql/data16
```

### Step 3 - Re-initialize with the correct locale

Use the same locale, encoding, and collation as the old cluster.

```
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data16 --encoding=UTF8 --locale=en_US.UTF-8
```

Expected output (yours will differ):

```
The files belonging to this database system will be owned by user "postgres".
...
Success. You can now start the database server using:

    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 -l logfile start
```

### Step 4 - Verify the new cluster has the correct locale

```
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data16 | grep -i lc_
```

Expected output:

```
LC_COLLATE:                           en_US.UTF-8
LC_CTYPE:                             en_US.UTF-8
```

### Step 5 - Re-run pg_upgrade --check

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

## Validation

```
./validate.sh
```

Expected checks:
- PG15 cluster is stopped
- PG16 target cluster has correct locale (en_US.UTF-8)
- pg_upgrade --check passes with matching locales
- PG16 production cluster is still running

---

## Interview Discussion Points

1. **Why can't you change a PostgreSQL cluster's locale after initdb?** - The locale is embedded in every text index that was ever created. Changing the locale on a live cluster would mean every text index is now sorted in the wrong order. PostgreSQL would return incorrect query results without any error. The design decision to make locale immutable after initialization prevents this class of silent corruption.

2. **What is the difference between `lc_collate` and `lc_ctype`?** - `lc_collate` determines the sort order for text (how `ORDER BY name` sequences strings). `lc_ctype` determines character classification (what counts as upper case, lower case, or a digit for functions like `upper()`, `lower()`, and regex character classes). Both must match between old and new clusters.

3. **If your production cluster has locale `en_US.UTF-8` but you need to upgrade to a cluster with `en_US.UTF-8` only for some databases, what do you do?** - PostgreSQL sets the default locale at the cluster level via `initdb`, but you can override it per-database at creation time with `CREATE DATABASE dbname LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0`. However, pg_upgrade requires the cluster-level locale to match, not per-database. The cluster-level locale is the default for new databases.

4. **What does `pg_controldata` tell you and when would you use it?** - `pg_controldata` reads the `global/pg_control` binary file and prints metadata about the cluster: version, locale, block size, WAL segment size, checkpoint information, and system identifier. You use it when the cluster is stopped and you cannot run SQL queries. It is the authoritative source for locale and encoding information before an upgrade.

5. **A junior DBA re-initialized the target cluster with locale `C` because they thought it would be faster. What is the actual performance difference and is it worth the tradeoff?** - Locale `C` is faster for text comparisons because it uses byte-by-byte comparison without language-aware collation rules. The difference is measurable (5-15% for heavy text workloads) but the tradeoff is significant: queries that rely on locale-aware sorting or case-insensitive comparison will behave differently. More importantly, if your application ever ran on `en_US.UTF-8`, sort orders that users or applications depend on may silently change. The performance gain is almost never worth changing the locale of a production system.
