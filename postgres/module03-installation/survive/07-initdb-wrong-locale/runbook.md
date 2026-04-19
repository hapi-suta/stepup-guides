# Runbook 07: initdb Wrong Locale

## Scenario

PostgreSQL 15 was reinitialized by a teammate, and now the application team reports that string sorting and text searches behave differently from production. The instance is running but was initialized with the C locale instead of en_US.UTF-8. Diagnose the locale mismatch and fix it.

---

## Layer 1: Fix Path

### Step 1 - Confirm PG15 is running

```bash
sudo systemctl status postgresql-15
```

Expected output:
```
● postgresql-15.service - PostgreSQL 15 database server
     Active: active (running) since ...
```

### Step 2 - Check the current locale settings

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-15/bin/psql -p 5433 -d postgres
```

```sql
SHOW lc_collate;
```

Expected output:
```
 lc_collate
------------
 C
(1 row)
```

```sql
SHOW lc_ctype;
```

Expected output:
```
 lc_ctype
----------
 C
(1 row)
```

> **Concept: LC_COLLATE vs LC_CTYPE** - `LC_COLLATE` controls string sorting order (ORDER BY on text). `LC_CTYPE` controls character classification (upper/lower case, what counts as a letter). Both are set at `initdb` time and are baked into the cluster - you cannot change them without reinitializing. The C locale uses byte-order sorting (ASCII values), while en_US.UTF-8 uses linguistic rules that handle accented characters correctly.

### Step 3 - Demonstrate the sorting difference

```sql
SELECT name FROM locale_test ORDER BY name;
```

Expected output with C locale (byte-order sorting):
```
 Banana
 apple
 cherry
 eclair
 elephant
```

Notice that "Banana" sorts before "apple" because uppercase B (ASCII 66) comes before lowercase a (ASCII 97). With en_US.UTF-8, sorting is case-insensitive by default and handles accented characters linguistically.

```sql
\q
```

```bash
exit
```

> **Concept: C locale sorting** - The C (or POSIX) locale sorts strings by raw byte values. This means uppercase letters sort before all lowercase letters (A-Z before a-z), and accented characters sort by their byte encoding rather than their linguistic position. This breaks user expectations for most applications. The C locale is faster for sorting but incorrect for human-readable output.

### Step 4 - Check the OS has the correct locale available

```bash
locale -a | grep en_US
```

Expected output:
```
en_US
en_US.iso88591
en_US.utf8
```

If `en_US.utf8` is not listed, install it:

```bash
sudo dnf install -y glibc-langpack-en
```

### Step 5 - Stop PG15

```bash
sudo systemctl stop postgresql-15
```

```bash
sudo systemctl status postgresql-15
```

Expected output:
```
● postgresql-15.service - PostgreSQL 15 database server
     Active: inactive (dead) since ...
```

### Step 6 - Back up the current data directory

```bash
sudo -iu postgres
```

```bash
mv /opt/pgsql/data15 /opt/pgsql/data15.bad-locale
```

```bash
exit
```

> **Concept: Why backup before reinit?** - Even though the locale is wrong, the data directory may contain databases, tables, or configuration you need. Always move it aside rather than deleting it. You can extract data with pg_dump later if needed (start the old cluster temporarily, dump, then restore into the new cluster).

### Step 7 - Reinitialize with the correct locale

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-15/bin/initdb -D /opt/pgsql/data15 --locale=en_US.UTF-8 --encoding=UTF8
```

Expected output (key lines):
```
The files belonging to this database system will be owned by user "postgres".
...
The default text search configuration will be set to "english".
...
Success. You can now start the database server using:
    /usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l logfile start
```

```bash
exit
```

### Step 8 - Set the port to 5433

The fresh postgresql.conf defaults to port 5432. Change it to 5433.

```bash
sudo -iu postgres
```

```bash
vi /opt/pgsql/data15/postgresql.conf
```

Find the line:
```
#port = 5432
```

Change it to:
```
port = 5433
```

Save and exit (`:wq`).

```bash
exit
```

### Step 9 - Start PG15

```bash
sudo systemctl start postgresql-15
```

```bash
sudo systemctl status postgresql-15
```

Expected output:
```
● postgresql-15.service - PostgreSQL 15 database server
     Active: active (running) since ...
```

### Step 10 - Verify the locale is correct

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-15/bin/psql -p 5433 -d postgres
```

```sql
SHOW lc_collate;
```

Expected output:
```
 lc_collate
--------------
 en_US.UTF-8
(1 row)
```

```sql
SHOW lc_ctype;
```

Expected output:
```
  lc_ctype
--------------
 en_US.UTF-8
(1 row)
```

```sql
SHOW server_encoding;
```

Expected output:
```
 server_encoding
-----------------
 UTF8
(1 row)
```

```sql
\q
```

```bash
exit
```

> **Concept: Encoding vs locale** - Encoding (UTF8, LATIN1, etc.) defines how characters are stored as bytes. Locale defines how those characters are sorted and classified. You can have UTF8 encoding with C locale (fast byte sorting) or UTF8 encoding with en_US.UTF-8 locale (linguistic sorting). Most production systems should use UTF8 encoding with an appropriate UTF-8 locale.

### Step 11 - Clean up the bad data directory

Once you have confirmed everything works:

```bash
sudo rm -rf /opt/pgsql/data15.bad-locale
```

---

## Layer 2: Revision Concepts

### Locale settings in PostgreSQL

Locale is set once during `initdb` and cannot be changed afterward for the default database. Here is what each setting controls:

| Setting | Controls | Example Impact |
|---------|----------|---------------|
| `lc_collate` | String sort order | ORDER BY on text columns |
| `lc_ctype` | Character classification | upper(), lower(), LIKE patterns |
| `lc_messages` | Error message language | Error messages in English vs French |
| `lc_monetary` | Currency formatting | to_char() with money formats |
| `lc_numeric` | Number formatting | Decimal separator (. vs ,) |
| `lc_time` | Date/time formatting | Month/day names |

Only `lc_collate` and `lc_ctype` are immutable after initdb. The others can be changed at runtime with SET.

### Per-database locale override

Starting with PostgreSQL 15, you can create individual databases with different locales:

```sql
CREATE DATABASE french_app
  LOCALE 'fr_FR.UTF-8'
  TEMPLATE template0;
```

This allows multiple locale configurations in a single cluster. The cluster-level locale (from initdb) only sets the default for new databases.

### Impact on indexes

`LC_COLLATE` directly affects B-tree indexes on text columns. An index built with C collation is incompatible with en_US.UTF-8 queries. If you change the locale by reinitializing, you must also `REINDEX` any text-column indexes after restoring data.

### ICU collations (PostgreSQL 15+)

PostgreSQL 15 introduced ICU as an alternative collation provider. ICU collations are:
- Portable across operating systems (same sort order on Linux, macOS, Windows)
- Versioned (you know when sort rules change)
- Not dependent on the OS glibc locale

```sql
CREATE DATABASE myapp
  LOCALE_PROVIDER icu
  ICU_LOCALE 'en-US'
  TEMPLATE template0;
```

> **Concept: Why ICU matters** - The glibc locale library can change sort orders between OS versions (e.g., glibc 2.28 changed sorting rules). This silently corrupts text indexes - they become logically inconsistent because the data was inserted under old rules but queried under new rules. ICU collations are versioned, so PostgreSQL can detect and warn about this.

---

## Layer 3: Interview Discussion Points

1. **Why does locale matter for a database?** - Locale determines how text is sorted, compared, and classified. Wrong locale means ORDER BY gives unexpected results, LIKE patterns may not match correctly, and text indexes could return wrong results. It's a data correctness issue, not just cosmetic.

2. **Can you change the locale of an existing cluster without reinitializing?** - No. `lc_collate` and `lc_ctype` are set at initdb and baked into the template databases. To change them, you must: dump all data, reinitialize with the correct locale, and restore. Starting with PG15, you can create individual databases with different locales, but the cluster default is still fixed.

3. **What happens to indexes when the locale changes?** - B-tree indexes on text columns encode sort order based on the locale at index creation time. If the locale changes (even from a glibc upgrade), the index becomes logically corrupted - it may return wrong results or miss rows. Run `REINDEX` on all text indexes after any locale change. Use `amcheck` extension to detect corruption.

4. **When would you deliberately use the C locale?** - For databases that only store machine-readable data (UUIDs, hashes, JSON keys) where linguistic sorting is irrelevant. C locale is faster because it skips the locale-aware comparison functions. Some analytics and data warehouse workloads use C locale for performance. Always document the choice.

5. **How do you verify locale consistency between production and a new replica or standby?** - Compare `SHOW lc_collate` and `SHOW lc_ctype` on both servers. For streaming replication, the standby inherits the primary's locale automatically. For logical replication or pg_dump restores, you must ensure the target cluster was initialized with the same locale. Also compare `ldd --version` to check glibc versions match.
