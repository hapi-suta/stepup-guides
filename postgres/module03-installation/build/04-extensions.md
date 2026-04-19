# Build 04: Installing and Configuring Extensions

**Lab 3.4 - PostgreSQL Extensions**
**Time:** 45 minutes
**Node:** Your lab server

In this lab you will explore PostgreSQL's extension system - how to discover what extensions are available, install them, and use some of the most important ones. Extensions let you add powerful features to PostgreSQL without modifying the core server code.

## Prerequisites

- PostgreSQL 16 installed and running on port 5432
- Data directory at `/opt/pgsql/data`
- Database `labdb` exists
- Logged in as `ec2-user`

---

## 1. Check What Extensions Are Available

Before installing any extension, you need to understand two things: what is **available** on your system, and what is **installed** in your database. These are different.

- **Available** means the extension's files (shared library + SQL script) exist on the server's filesystem. PostgreSQL knows about them but they are not loaded into any database yet.
- **Installed** means someone ran `CREATE EXTENSION` inside a specific database, which created the extension's objects (functions, types, views) in that database.

Switch to the postgres user.

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Connect to the `labdb` database. The `-d` flag specifies which database to connect to.

```bash
psql -d labdb
```

Query the `pg_available_extensions` view. This shows every extension whose files are present on the server. The `installed_version` column tells you whether it is installed in the current database - NULL means it is available but not installed.

```sql
SELECT name, default_version, installed_version, comment
FROM pg_available_extensions
ORDER BY name
LIMIT 20;
```

Expected output (partial - your list may vary):

```
      name       | default_version | installed_version |                     comment
-----------------+-----------------+-------------------+--------------------------------------------------
 adminpack       | 2.1             |                   | administrative functions for PostgreSQL
 amcheck         | 1.3             |                   | functions for verifying relation integrity
 autoinc         | 1.0             |                   | functions for autoincrementing fields
 bloom           | 1.0             |                   | bloom access method - signature file based index
 btree_gin       | 1.3             |                   | support for indexing common datatypes in GIN
 ...
```

Notice the `installed_version` column is empty for everything. That means none of these extensions are installed in `labdb` yet.

Now check what is currently installed in this database.

```sql
SELECT extname, extversion FROM pg_extension;
```

Expected output:

```
 extname | extversion
---------+------------
 plpgsql | 1.0
```

Only `plpgsql` is installed by default. This is PostgreSQL's built-in procedural language.

> **Concept: Extensions Are Per-Database**
> When you run `CREATE EXTENSION`, it installs the extension only in the database you are connected to. If you have three databases and you want `pgcrypto` in all of them, you must run `CREATE EXTENSION pgcrypto` in each one separately.

Exit psql.

```sql
\q
```

Exit the postgres user.

```bash
exit
```

**You are back to ec2-user.**

---

## 2. Install the Contrib Package

Most popular extensions ship in a package called `postgresql16-contrib`. This package adds the extension files to the server's filesystem, making them **available** - but not yet **installed** in any database.

Check whether the contrib package is already installed. The `rpm -q` command queries whether a specific package is installed on the system.

```bash
rpm -q postgresql16-contrib
```

If installed, you will see something like:

```
postgresql16-contrib-16.x-xPGDG.rhel9.x86_64
```

If not installed, you will see:

```
package postgresql16-contrib is not installed
```

If the package is not installed, install it now. The `-y` flag auto-confirms the installation prompt.

```bash
sudo dnf install -y postgresql16-contrib
```

Expected output (last few lines):

```
Installed:
  postgresql16-contrib-16.x-xPGDG.rhel9.x86_64

Complete!
```

Verify the installation by checking that the contrib package is present.

```bash
rpm -q postgresql16-contrib
```

You should now see the package version printed.

> **Concept: Packages vs. Extensions**
> Installing a package with `dnf` puts files on the filesystem. Installing an extension with `CREATE EXTENSION` loads those files into a specific database. You always need the package first, then the SQL command.

---

## 3. Install pg_stat_statements

`pg_stat_statements` is arguably the most important extension for a DBA. It tracks execution statistics for every SQL statement the server runs - how many times each query executed, total time, rows returned, and more. This is how you find slow queries in production.

Unlike most extensions, `pg_stat_statements` requires a change to `postgresql.conf` because it must load a shared library into PostgreSQL's memory at startup. This means a restart is required.

### Step 3a: Edit postgresql.conf

Switch to the postgres user.

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Open the PostgreSQL configuration file with vi.

```bash
vi /opt/pgsql/data/postgresql.conf
```

In vi, search for the `shared_preload_libraries` setting. Type the following and press Enter:

```
/shared_preload_libraries
```

You will see a commented-out line like:

```
#shared_preload_libraries = ''
```

Press `o` to open a new line below the cursor, then type exactly:

```
shared_preload_libraries = 'pg_stat_statements'
```

Press `Esc`, then type `:wq` and press Enter to save and quit.

Verify your change was saved. The `grep` command searches the file for lines containing the text. The `-v` flag inverts the match, and `^#` matches lines starting with `#` - so this shows only uncommented lines.

```bash
grep shared_preload_libraries /opt/pgsql/data/postgresql.conf | grep -v '^#'
```

Expected output:

```
shared_preload_libraries = 'pg_stat_statements'
```

Exit the postgres user.

```bash
exit
```

**You are back to ec2-user.**

### Step 3b: Restart PostgreSQL

Because `shared_preload_libraries` is read only at server startup, you must restart PostgreSQL for the change to take effect. A reload is not enough.

```bash
sudo systemctl restart postgresql-16
```

Verify the service restarted successfully.

```bash
sudo systemctl status postgresql-16
```

Look for `active (running)` in the output. If you see `failed`, check the log at `/opt/pgsql/log/` for error messages.

> **Concept: Reload vs. Restart**
> Most PostgreSQL settings take effect with a `reload` (no downtime). But `shared_preload_libraries` requires a full `restart` because it loads shared libraries into the server's memory space at startup. In production, this means a brief outage - plan accordingly.

### Step 3c: Create the Extension and Test It

Switch to the postgres user.

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Connect to `labdb`.

```bash
psql -d labdb
```

Create the extension.

```sql
CREATE EXTENSION pg_stat_statements;
```

Expected output:

```
CREATE EXTENSION
```

Run a few queries to generate some statistics.

```sql
SELECT count(*) FROM pg_class;
```

```sql
SELECT count(*) FROM pg_attribute;
```

```sql
SELECT 1 + 1;
```

Now query `pg_stat_statements` to see what it captured. This shows the top 5 queries by total execution time.

```sql
SELECT query, calls, total_exec_time, rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 5;
```

Expected output (your values will differ):

```
                     query                     | calls | total_exec_time | rows
-----------------------------------------------+-------+-----------------+------
 SELECT count(*) FROM pg_attribute             |     1 |           2.145 |    1
 SELECT count(*) FROM pg_class                 |     1 |           1.832 |    1
 SELECT query, calls, total_exec_time, rows... |     0 |           0.000 |    0
```

> **Concept: Why pg_stat_statements Matters**
> In production, this extension is your primary tool for finding slow or frequently-executed queries. Without it, you are flying blind. Most PostgreSQL experts consider this a mandatory extension on every server.

Leave psql open - you will use it in the next section.

---

## 4. Install pgcrypto

`pgcrypto` provides cryptographic functions directly inside the database. The most commonly used feature is `gen_random_uuid()` for generating UUIDs, but it also supports hashing, encryption, and decryption.

Since you are still in psql connected to `labdb`, create the extension.

```sql
CREATE EXTENSION pgcrypto;
```

Expected output:

```
CREATE EXTENSION
```

### Generate a UUID

UUIDs (Universally Unique Identifiers) are 128-bit values commonly used as primary keys in distributed systems. The `gen_random_uuid()` function generates a version 4 (random) UUID.

```sql
SELECT gen_random_uuid();
```

Expected output (your UUID will be different):

```
           gen_random_uuid
--------------------------------------
 a3b7c9d1-4e5f-6a7b-8c9d-0e1f2a3b4c5d
```

### Hash Data with digest()

The `digest()` function computes a cryptographic hash of a string. The second argument specifies the hash algorithm. The `encode()` wrapper converts the raw bytes to a readable hex string.

```sql
SELECT encode(digest('hello world', 'sha256'), 'hex');
```

Expected output:

```
                              encode
------------------------------------------------------------------
 b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
```

### Encrypt and Decrypt with pgp_sym_encrypt / pgp_sym_decrypt

These functions use PGP symmetric encryption. You provide a passphrase to encrypt, and the same passphrase to decrypt.

Encrypt a message. The first argument is the plaintext, the second is the passphrase.

```sql
SELECT pgp_sym_encrypt('my secret data', 'mypassphrase');
```

Expected output (encrypted blob - yours will look different):

```
                          pgp_sym_encrypt
--------------------------------------------------------------------
 \xc30d04070302...  (long hex string)
```

Now decrypt it. You must use the same passphrase you used to encrypt.

```sql
SELECT pgp_sym_decrypt(
  pgp_sym_encrypt('my secret data', 'mypassphrase'),
  'mypassphrase'
);
```

Expected output:

```
 pgp_sym_decrypt
-----------------
 my secret data
```

If you provide the wrong passphrase, PostgreSQL raises an error:

```sql
SELECT pgp_sym_decrypt(
  pgp_sym_encrypt('my secret data', 'mypassphrase'),
  'wrongpassphrase'
);
```

Expected output:

```
ERROR:  Wrong key or corrupt data
```

Leave psql open for the next section.

---

## 5. Install pg_trgm

`pg_trgm` (trigram) provides functions for measuring the similarity between strings and supports fast `LIKE` / `ILIKE` searches using GIN or GiST indexes. A trigram is a group of three consecutive characters from a string.

Create the extension.

```sql
CREATE EXTENSION pg_trgm;
```

Expected output:

```
CREATE EXTENSION
```

### Measure String Similarity

The `similarity()` function returns a number between 0 and 1, where 1 means an exact match. This is useful for fuzzy matching - finding strings that are close but not identical.

```sql
SELECT similarity('PostgreSQL', 'PostGreSQL');
```

Expected output:

```
 similarity
------------
        0.7
```

```sql
SELECT similarity('PostgreSQL', 'MySQL');
```

Expected output:

```
 similarity
------------
   0.076923
```

### View Trigrams

The `show_trgm()` function shows you the actual trigrams extracted from a string. Each trigram is a 3-character slice.

```sql
SELECT show_trgm('hello');
```

Expected output:

```
          show_trgm
-----------------------------
 {"  h"," he",ell,hel,llo,"lo "}
```

PostgreSQL pads the beginning and end of the string with spaces, then slices every 3 characters. Two strings that share many trigrams are considered similar.

### Speed Up LIKE Queries with a GIN Index

Normally, a `LIKE '%search%'` query requires a full table scan because the database must check every row. A GIN trigram index changes this - it indexes the trigrams of each value, allowing PostgreSQL to quickly find matching rows.

Create a test table with some data.

```sql
CREATE TABLE products (
  id serial PRIMARY KEY,
  name text
);
```

```sql
INSERT INTO products (name) VALUES
  ('PostgreSQL Database'),
  ('MySQL Server'),
  ('MongoDB Atlas'),
  ('Redis Cache'),
  ('PostgreSQL Replication');
```

Create a GIN index using the trigram operator class. The `gin_trgm_ops` operator class tells PostgreSQL to index the trigrams of each value.

```sql
CREATE INDEX idx_products_name_trgm ON products USING gin (name gin_trgm_ops);
```

Expected output:

```
CREATE INDEX
```

Now run a `LIKE` query. With the GIN trigram index, PostgreSQL can use the index instead of scanning every row.

```sql
EXPLAIN SELECT * FROM products WHERE name LIKE '%Postgre%';
```

Expected output (on a small table the planner may still choose a sequential scan - in production with thousands of rows, it will use the index):

```
                                    QUERY PLAN
----------------------------------------------------------------------------------
 Bitmap Heap Scan on products  (cost=...)
   Recheck Cond: (name ~~ '%Postgre%'::text)
   ->  Bitmap Index Scan on idx_products_name_trgm  (cost=...)
         Index Cond: (name ~~ '%Postgre%'::text)
```

> **Concept: Trigram Indexes Solve the LIKE Problem**
> Without a trigram index, `LIKE '%something%'` always does a full table scan - even if you have a regular B-tree index. B-tree indexes only help with prefix searches like `LIKE 'something%'`. If your application needs to search for patterns in the middle of strings, a GIN trigram index is the solution.

Leave psql open for the next section.

---

## 6. Install pageinspect

`pageinspect` lets you look inside the physical pages (8KB blocks) that make up PostgreSQL's data files. This ties directly back to Module 02 where you learned about storage architecture - now you can actually see the internal structure of a page.

Create the extension.

```sql
CREATE EXTENSION pageinspect;
```

Expected output:

```
CREATE EXTENSION
```

### Examine a Page Header

Every 8KB page starts with a header that contains metadata about the page. The `page_header()` function reads the raw bytes of a page and decodes its header.

The `get_raw_page()` function reads page number 0 (the first page) from the `products` table.

```sql
SELECT * FROM page_header(get_raw_page('products', 0));
```

Expected output (your values will differ):

```
    lsn    | checksum | flags | lower | upper | special | pagesize | version | prune_xid
-----------+----------+-------+-------+-------+---------+----------+---------+-----------
 0/1A8B3D0 |        0 |     0 |    44 |  7936 |    8192 |     8192 |       4 |         0
```

Here is what the key fields mean:

| Field | Meaning |
|---|---|
| `lsn` | The WAL position when this page was last modified |
| `lower` | Offset where free space begins (end of line pointers) |
| `upper` | Offset where free space ends (start of actual tuples) |
| `special` | Start of the special area at the end of the page (8192 for heap pages) |
| `pagesize` | Size of the page in bytes (always 8192) |

The free space on this page is `upper - lower` bytes. This is where new rows will be placed.

### Examine Individual Tuples

The `heap_page_items()` function shows you every tuple (row) stored on a page, including the hidden system columns that PostgreSQL uses internally.

```sql
SELECT lp, lp_off, lp_len, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('products', 0));
```

Expected output:

```
 lp | lp_off | lp_len | t_xmin | t_xmax | t_ctid
----+--------+--------+--------+--------+--------
  1 |   8144 |     48 |    750 |      0 | (0,1)
  2 |   8096 |     40 |    750 |      0 | (0,2)
  3 |   8048 |     41 |    750 |      0 | (0,3)
  4 |   8008 |     39 |    750 |      0 | (0,4)
  5 |   7960 |     50 |    750 |      0 | (0,5)
```

Here is what each column means:

| Column | Meaning |
|---|---|
| `lp` | Line pointer number (the row's position in the page's pointer array) |
| `lp_off` | Byte offset within the page where this tuple starts |
| `lp_len` | Length of the tuple in bytes |
| `t_xmin` | Transaction ID that created this row (INSERT) |
| `t_xmax` | Transaction ID that deleted this row (0 means the row is live) |
| `t_ctid` | Current tuple ID - format is (page, item). If it points to itself, the row is the latest version |

Notice that `t_xmax` is 0 for all rows - this means none of them have been deleted or updated. If you update a row and query again, you will see the old row get a `t_xmax` value pointing to the new version.

> **Concept: Seeing MVCC in Action**
> The `t_xmin` and `t_xmax` values are how PostgreSQL implements MVCC (Multi-Version Concurrency Control), which you learned about in Module 02. Every row carries the transaction IDs of its creator and deleter. When a transaction runs a SELECT, it checks these values to decide which version of each row is visible. `pageinspect` lets you see this mechanism directly.

Exit psql.

```sql
\q
```

Exit the postgres user.

```bash
exit
```

**You are back to ec2-user.**

---

## 7. Managing Extensions

Now that you have several extensions installed, let's learn how to manage them - checking versions, updating, handling dependencies, and removing them.

Switch to the postgres user.

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Connect to `labdb`.

```bash
psql -d labdb
```

### Check Installed Extension Versions

List all extensions installed in the current database with their versions.

```sql
SELECT extname, extversion FROM pg_extension ORDER BY extname;
```

Expected output:

```
      extname       | extversion
--------------------+------------
 pageinspect        | 1.12
 pg_stat_statements | 1.10
 pg_trgm            | 1.6
 pgcrypto           | 1.3
 plpgsql            | 1.0
```

### Check for Available Updates

Compare the installed version to the latest available version. If these differ, an update is available.

```sql
SELECT name, installed_version, default_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;
```

If `installed_version` and `default_version` match, your extensions are up to date.

### Update an Extension

If an extension has a newer version available, update it with `ALTER EXTENSION UPDATE`. This runs the extension's upgrade script to migrate from the old version to the new one.

```sql
ALTER EXTENSION pgcrypto UPDATE;
```

Expected output (if already at the latest version):

```
NOTICE:  version "1.3" of extension "pgcrypto" is already installed
ALTER EXTENSION
```

### Check Extension Dependencies

Some extensions depend on others. You can check dependencies with this query.

```sql
SELECT e.extname AS extension,
       d.refobjid::regclass AS depends_on
FROM pg_depend d
JOIN pg_extension e ON d.objid = e.oid
WHERE d.deptype = 'e'
LIMIT 10;
```

### Drop an Extension

When you no longer need an extension, remove it with `DROP EXTENSION`. This removes all objects the extension created (functions, types, etc.) from the database.

```sql
DROP EXTENSION pageinspect;
```

Expected output:

```
DROP EXTENSION
```

If other objects in your database depend on the extension (for example, a view that uses one of its functions), PostgreSQL will refuse to drop it. In that case, you can use `CASCADE` to drop the extension and everything that depends on it - but be careful with this in production.

```sql
DROP EXTENSION pg_trgm CASCADE;
```

Expected output:

```
NOTICE:  drop cascades to index idx_products_name_trgm
DROP EXTENSION
```

Notice that `CASCADE` also dropped the GIN trigram index you created earlier, because that index depended on the `pg_trgm` extension's operator class.

> **Concept: CASCADE Can Be Dangerous**
> `DROP EXTENSION ... CASCADE` removes the extension and every database object that depends on it - indexes, views, functions, and more. In production, always check what depends on an extension before dropping it. Run `DROP EXTENSION name` without CASCADE first to see what PostgreSQL reports as dependent objects.

Reinstall the extensions you dropped, since you may need them for the USE exercises.

```sql
CREATE EXTENSION pg_trgm;
```

```sql
CREATE EXTENSION pageinspect;
```

Verify everything is back.

```sql
SELECT extname, extversion FROM pg_extension ORDER BY extname;
```

Expected output:

```
      extname       | extversion
--------------------+------------
 pageinspect        | 1.12
 pg_stat_statements | 1.10
 pg_trgm            | 1.6
 pgcrypto           | 1.3
 plpgsql            | 1.0
```

Exit psql.

```sql
\q
```

Exit the postgres user.

```bash
exit
```

**You are back to ec2-user.**

---

## Checkpoint

Before moving on, confirm everything is in place:

- [ ] `postgresql16-contrib` package is installed (`rpm -q postgresql16-contrib`)
- [ ] `shared_preload_libraries = 'pg_stat_statements'` is set in `/opt/pgsql/data/postgresql.conf`
- [ ] PostgreSQL was restarted after the config change
- [ ] `pg_stat_statements` extension is installed in `labdb` and capturing query stats
- [ ] `pgcrypto` extension is installed in `labdb` - `gen_random_uuid()`, `digest()`, and `pgp_sym_encrypt/decrypt` all work
- [ ] `pg_trgm` extension is installed in `labdb` - `similarity()` and `show_trgm()` return results
- [ ] `pageinspect` extension is installed in `labdb` - `page_header()` and `heap_page_items()` show page internals
- [ ] You understand the difference between **available** (files on disk) and **installed** (loaded in a database)
- [ ] You know how to update and drop extensions

This is the last BUILD guide for Module 03. You now have PostgreSQL 16 installed, configured, and extended with essential tools.

**Proceed to USE exercises.**
