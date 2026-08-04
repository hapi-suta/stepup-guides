# Phase 2 (USE) - Knowledge Check

Answer each question before moving to Phase 3 (SURVIVE).

---

## Questions

**1. You SSH into a server you have never seen before. What two methods do you use to determine the running PostgreSQL version, and what is the difference between them?**

<details>
<summary>Answer</summary>

Method 1 - Query the running server:

Switch to the postgres OS user:

```bash
sudo -iu postgres
```

Query the server version:

```bash
psql -c "SELECT version();"
```

Return to your previous user:

```bash
exit
```

This returns the full version string including major version, architecture, and compiler. It always reflects the actual running server, regardless of which client you use.

Method 2 - Check the binary directly:

```bash
/usr/pgsql-16/bin/postgres --version
```

This reads the binary's embedded version and does not require a running server. Use this when PostgreSQL is down or you need to check a binary that is not currently active.

The key difference: `SELECT version()` tells you what is running right now. `postgres --version` tells you what a specific binary was built as - which might not be the binary that is currently running.
</details>

---

**2. How do you determine whether PostgreSQL was installed from PGDG RPMs or compiled from source?**

<details>
<summary>Answer</summary>

Query the RPM database:

```bash
rpm -q postgresql16-server
```

If it returns a version string like `postgresql16-server-16.x-1PGDG.rhel9.x86_64`, it was installed from RPMs. If it says "package is not installed", it was likely compiled from source.

To confirm the repository source:

```bash
dnf list installed | grep postgres
```

The rightmost column shows the repo (e.g., `@pgdg16`). Source-compiled binaries are invisible to the RPM database. Check for them by inspecting known paths like `/opt/pg-src/bin/postgres`.
</details>

---

**3. What three SQL commands should you always run to find the active configuration file locations on a running PostgreSQL server, and why should you never rely on filesystem assumptions?**

<details>
<summary>Answer</summary>

```sql
SHOW config_file;    -- /opt/pgsql/data/postgresql.conf
SHOW hba_file;       -- /opt/pgsql/data/pg_hba.conf
SHOW data_directory; -- /opt/pgsql/data
```

Never assume the location because:

- A systemd drop-in override might change PGDATA (check `/etc/systemd/system/postgresql-16.service.d/override.conf`)
- Someone may have started PostgreSQL with a `-D` flag pointing to a non-default location
- The RPM default PGDATA is `/opt/pgsql/data/`, but many shops relocate it

The `SHOW` commands read from the running server's memory, so they always reflect the truth.
</details>

---

**4. PostgreSQL 15 runs on port 5433 and PostgreSQL 16 runs on port 5432 on the same server. How do you stop PG15 without affecting PG16? How do you verify PG16 is unaffected?**

<details>
<summary>Answer</summary>

Stop only the PG15 service:

```bash
sudo systemctl stop postgresql-15
```

Verify PG15 is down:

```bash
pg_isready -p 5433
# Expected: /var/run/postgresql:5433 - no response
```

Verify PG16 is still running:

```bash
pg_isready -p 5432
# Expected: /var/run/postgresql:5432 - accepting connections
```

Each major version runs as an independent systemd service with its own processes, data directory, and configuration. Stopping one has zero effect on the other. They share only OS-level resources (CPU, memory, disk I/O).
</details>

---

**5. What does `pg_config --configure` show you, and what is the practical difference between the RPM build output and a minimal source build?**

<details>
<summary>Answer</summary>

`pg_config --configure` displays the exact `./configure` flags used at compile time.

RPM build (PGDG):

```bash
/usr/pgsql-16/bin/pg_config --configure
# Returns many flags: --with-llvm --with-lz4 --with-zstd --with-openssl
# --with-gssapi --with-icu --with-systemd --with-pam --with-ldap ...
```

Minimal source build:

```bash
/opt/pg-src/bin/pg_config --configure
# Returns only: '--prefix=/opt/pg-src' '--with-openssl' '--with-libxml'
```

The RPM includes virtually every optional feature (JIT, compression, Kerberos, ICU collation). A source build only includes what you explicitly requested. This directly affects runtime capabilities - for example, the source build cannot use `lz4` or `zstd` for WAL compression, and JIT is unavailable.
</details>

---

**6. Explain the difference between a feature being "compiled in" and "enabled." Give an example using SSL.**

<details>
<summary>Answer</summary>

"Compiled in" means the code for a feature was included at build time. "Enabled" means the feature is actively configured and running.

SSL example:

Check the build flags to see if SSL was compiled in:

```bash
/usr/pgsql-16/bin/pg_config --configure | tr ' ' '\n' | grep ssl
# Output: '--with-openssl'
```

Switch to the postgres user to check the runtime setting:

```bash
sudo -iu postgres
```

Query whether SSL is enabled:

```bash
psql -c "SHOW ssl;"
# Output: off
```

Return to your previous user:

```bash
exit
```

Even though `--with-openssl` is present, `ssl = off` means the server does not accept SSL connections. To enable it, you need to set `ssl = on` in `postgresql.conf` and provide certificate files (`server.crt`, `server.key`).

The same pattern applies to JIT: `--with-llvm` compiles it in, but `jit = on/off` in `postgresql.conf` controls whether it activates at runtime.
</details>

---

**7. A developer reports: "I installed an extension on PG16 but PG15 cannot find it." What is happening, and how do you fix it?**

<details>
<summary>Answer</summary>

Each PostgreSQL installation has its own independent library path. Extensions (`.so` files and `.control` files) are installed into that version's directories:

- PG16 extensions: `/usr/pgsql-16/share/extension/` and `/usr/pgsql-16/lib/`
- PG15 extensions: `/usr/pgsql-15/share/extension/` and `/usr/pgsql-15/lib/`

Installing an extension's RPM for PG16 does not make it available in PG15. You must install the PG15-specific RPM package:

```bash
# PG16 package (already installed):
sudo dnf install -y pg_trgm_16

# PG15 needs its own package:
sudo dnf install -y pg_trgm_15
```

For contrib extensions, install the version-specific contrib package:

```bash
sudo dnf install -y postgresql15-contrib
```

Then run `CREATE EXTENSION` inside the PG15 database.
</details>

---

**8. What is the `pg_trgm.similarity_threshold` setting, and how does the `%` operator use it for fuzzy search?**

<details>
<summary>Answer</summary>

`pg_trgm.similarity_threshold` controls the minimum similarity score that the `%` operator considers a match. The default is `0.3` (30% similarity).

```sql
-- Check current threshold:
SHOW pg_trgm.similarity_threshold;

-- Lower it to catch more fuzzy matches:
SET pg_trgm.similarity_threshold = 0.15;

-- The % operator returns rows where similarity >= threshold:
SELECT product_name, similarity(product_name, 'Postgrss') AS score
FROM catalog
WHERE product_name % 'Postgrss'
ORDER BY score DESC;
```

Trigrams split strings into overlapping 3-character sequences. "cat" becomes `{"  c", " ca", "cat", "at "}`. Two strings sharing many trigrams score higher. Unlike `LIKE`, trigrams tolerate typos, transposed characters, and missing letters.

For performance, create a GIN index:

```sql
CREATE INDEX idx_catalog_trgm ON catalog USING gin (product_name gin_trgm_ops);
```
</details>

---

**9. How do you hash a password using pgcrypto, and how do you verify a password attempt against the stored hash?**

<details>
<summary>Answer</summary>

Hash a password with bcrypt:

```sql
INSERT INTO app_users (username, password_hash)
VALUES ('alice', crypt('s3cur3P@ss', gen_salt('bf')));
```

`gen_salt('bf')` generates a bcrypt salt. The `'bf'` parameter selects the Blowfish (bcrypt) algorithm. Each call produces a different salt, so the same password generates a different hash every time.

Verify a password attempt:

```sql
SELECT username,
       (password_hash = crypt('s3cur3P@ss', password_hash)) AS password_correct
FROM app_users
WHERE username = 'alice';
-- password_correct = t (true)
```

`crypt()` re-hashes the input using the salt embedded in the stored hash. If the result matches, the password is correct. The salt is part of the 60-character bcrypt output, so you never store it separately.
</details>

---

**10. A developer reports: "The app feels slow but I don't know which queries are the problem." Walk through how you use pg_stat_statements to identify the bottleneck.**

<details>
<summary>Answer</summary>

Step 1 - Find queries with the highest cumulative execution time:

```sql
SELECT
    substring(query, 1, 60) AS query_preview,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    rows
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'labdb')
ORDER BY total_exec_time DESC
LIMIT 10;
```

Step 2 - Check for high-frequency queries (potential missing cache):

```sql
SELECT substring(query, 1, 60) AS query_preview, calls, rows,
       round(mean_exec_time::numeric, 4) AS avg_ms
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'labdb')
ORDER BY calls DESC
LIMIT 5;
```

Step 3 - Run `EXPLAIN ANALYZE` on the worst offenders, add indexes or rewrite.

Step 4 - Reset stats and monitor again:

```sql
SELECT pg_stat_statements_reset();
```

Key columns: `calls` (how many times), `total_exec_time` (cumulative ms), `mean_exec_time` (average per call), `rows` (total rows returned across all calls).
</details>

---

**11. What do the `t_xmin` and `t_xmax` columns in `heap_page_items()` tell you, and how does an UPDATE appear in the page layout?**

<details>
<summary>Answer</summary>

`t_xmin` is the transaction ID that created (INSERT) the tuple. `t_xmax` is the transaction ID that deleted or updated it. A `t_xmax` of 0 means the tuple is live.

```sql
SELECT lp AS line_pointer, t_xmin AS created_by_txn,
       t_xmax AS deleted_by_txn, t_ctid AS current_location
FROM heap_page_items(get_raw_page('catalog', 0));
```

When you UPDATE a row:

1. The old tuple gets its `t_xmax` set to the updating transaction's ID
2. The old tuple's `t_ctid` changes to point to the new tuple's location (e.g., `(0,11)`)
3. A brand new tuple is written with `t_xmax = 0` and `t_ctid` pointing to itself

Both versions exist on the page simultaneously. This is MVCC - transactions that started before the UPDATE still see the old version. VACUUM later removes dead tuples once no transaction can see them.
</details>

---

**12. What is the required permission mode for the PGDATA directory, and what happens if it is wrong? How do you fix it?**

<details>
<summary>Answer</summary>

PGDATA must be mode `0700` (owner-only read/write/execute). PostgreSQL refuses to start with any other mode.

If permissions are wrong (e.g., `chmod 750`):

```bash
sudo systemctl restart postgresql-16
# Fails with: Active: failed
```

Check the logs to see the error:

```bash
sudo journalctl -u postgresql-16 --no-pager -n 20
# FATAL: data directory "/opt/pgsql/data" has group or world access
# DETAIL: Permissions should be u=rwx (0700) or u=rwx,g=rx (0750).
```

Fix:

Set the directory permissions to owner-only access:

```bash
sudo chmod 0700 /opt/pgsql/data
```

Ensure the postgres user owns the directory:

```bash
sudo chown postgres:postgres /opt/pgsql/data
```

Start PostgreSQL now that permissions are correct:

```bash
sudo systemctl start postgresql-16
```

PostgreSQL enforces this because PGDATA contains data files, `pg_hba.conf`, and authentication configuration. If other users could read these files, they would bypass all database-level access controls.
</details>

---

**13. What is the difference between `systemctl reload` and `systemctl restart` for PostgreSQL? Name one parameter that requires a restart and one that requires only a reload.**

<details>
<summary>Answer</summary>

`reload` sends a SIGHUP to the running server. It re-reads configuration files without disconnecting clients. No downtime.

`restart` fully stops the server and starts it again. All connections are terminated. Brief downtime.

Requires **restart**:
- `shared_preload_libraries` - loaded into memory during initialization. Changing it with only a reload has no effect. Example:

```
shared_preload_libraries = 'pg_stat_statements'
```

Requires only **reload**:
- `pg_hba.conf` changes - authentication rules are re-read on reload:

```bash
sudo -iu postgres
```

Reload the configuration from inside psql:

```bash
psql -c "SELECT pg_reload_conf();"
```

Return to your previous user:

```bash
exit
```

Or:

```bash
sudo systemctl reload postgresql-16
```

Other reload-safe parameters: `work_mem`, `log_min_duration_statement`, `max_connections` (requires restart in versions before PG 17).
</details>

---

**14. A developer runs `CREATE EXTENSION ip4r;` and gets: "could not open extension control file." Explain the two-step extension installation process and how you fix this.**

<details>
<summary>Answer</summary>

Extensions require two steps:

**Step 1 - Install the OS package** (places `.control` and `.so` files on disk):

```bash
# Search for the package:
dnf search ip4r

# Install it:
sudo dnf install -y ip4r_16
```

This puts the control file at `/usr/pgsql-16/share/extension/ip4r.control` and the shared library at `/usr/pgsql-16/lib/ip4r.so`.

**Step 2 - Create the extension in the database:**

```sql
CREATE EXTENSION ip4r;
```

The error "could not open extension control file" means Step 1 was skipped. The `.control` file does not exist on the filesystem, so PostgreSQL cannot read the extension metadata.

To verify the current state of extensions:

```sql
-- What is installed in this database:
SELECT extname, extversion FROM pg_extension ORDER BY extname;

-- What is available on the filesystem but not yet installed:
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE installed_version IS NULL;
```
</details>

---

**15. How does `pg_hba.conf` evaluate rules, and what happens if you put a broad reject rule before a specific allow rule? How do you verify your rules after editing?**

<details>
<summary>Answer</summary>

`pg_hba.conf` is evaluated top-to-bottom. PostgreSQL uses the **first matching rule** and ignores everything below it.

If you add this broad rule first:

```
host    all    all    0.0.0.0/0    reject
host    labdb  appuser  10.0.1.50/32  scram-sha-256
```

The `appuser` rule is never reached because `0.0.0.0/0` matches every IP address. All TCP connections are rejected. Order matters - specific rules must come before broad rules.

After editing, reload and verify:

```bash
sudo -iu postgres
```

Reload the configuration:

```bash
psql -c "SELECT pg_reload_conf();"
```

Check for syntax errors in the rules:

```bash
psql -c "SELECT line_number, type, database, user_name, address, auth_method, error
         FROM pg_hba_file_rules ORDER BY line_number;"
```

Return to your previous user:

```bash
exit
```

If the `error` column is non-NULL for any row, that rule has a syntax error. A broken `pg_hba.conf` can lock everyone out, including you.
</details>

---

**16. You inherit a server with both RPM and source-compiled PostgreSQL. The RPM install shows `wal_compression` options of `{off,pglz,lz4,zstd,on}` but the source build only shows `{off,pglz,on}`. Why? How would you verify this yourself?**

<details>
<summary>Answer</summary>

The difference is in compile-time flags. The RPM was built with `--with-lz4` and `--with-zstd`, so those compression algorithms are available. The source build was compiled without those flags, so only the built-in `pglz` is available.

Verify the build flags:

RPM build:

```bash
/usr/pgsql-16/bin/pg_config --configure | tr ' ' '\n' | grep -E 'lz4|zstd'
# Output: '--with-lz4'  '--with-zstd'
```

Source build:

```bash
/opt/pg-src/bin/pg_config --configure | tr ' ' '\n' | grep -E 'lz4|zstd'
# Output: (empty - not compiled in)
```

Verify at runtime by querying `pg_settings`:

```sql
SELECT name, enumvals FROM pg_settings WHERE name = 'wal_compression';
```

The `pg_settings` view reflects what the running server is capable of, not just what is configured. If a feature was not compiled in, the corresponding enum values are absent.

To add `lz4`/`zstd` to the source build, you would need to recompile with those flags and install the development libraries (`lz4-devel`, `libzstd-devel`).
</details>

---

## Scoring

Count each correct answer as 1 point. Partial answers with the right concept but missing commands count as 0.5.

| Score | Result |
|-------|--------|
| 14-16 | Ready for Phase 3 (SURVIVE) |
| 10-13 | Review the exercises for topics you missed, then retake those questions |
| Below 10 | Repeat the USE phase exercises before attempting SURVIVE |
