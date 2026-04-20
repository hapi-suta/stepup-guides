# Exercise 03 - Source vs. Package

**Time estimate:** 25-30 minutes
**Prerequisites:** BUILD phase complete - CentOS Stream 9 with PostgreSQL 16 (RPM) running on port 5432, PostgreSQL 15 (RPM) running on port 5433, source-compiled PG at `/opt/pg-src/bin/`. PGDATA at `/opt/pgsql/data`. Database `labdb` exists on PG16. Extensions installed: pg_stat_statements, pgcrypto, pg_trgm, pageinspect.

---

## Scenario

The security team asks you to verify the build options of your PostgreSQL installations. They need to confirm that SSL support is compiled in, understand the differences between your RPM and source-compiled builds, and review the shared library layout. You will also briefly start the source build to compare runtime settings.

---

## Step 1 - Compare Build Flags with pg_config

The `pg_config` tool reports how a PostgreSQL installation was compiled. Every PostgreSQL installation includes its own `pg_config` binary. The `--configure` flag shows the exact `./configure` command that was used to build it.

Check the RPM build flags:

```bash
/usr/pgsql-16/bin/pg_config --configure
```

**Expected (one long line, abbreviated):**

```
'--enable-rpath' '--prefix=/usr/pgsql-16' '--includedir=/usr/pgsql-16/include'
'--mandir=/usr/pgsql-16/share/man' '--datadir=/usr/pgsql-16/share'
'--with-icu' '--with-llvm' '--with-lz4' '--with-zstd' '--with-openssl'
'--with-pam' '--with-gssapi' '--with-ldap' '--with-systemd' '--with-libxml'
'--with-libxslt' '--with-uuid=e2fs' ...
```

Now check the source build flags:

```bash
/opt/pg-src/bin/pg_config --configure
```

**Expected:**

```
'--prefix=/opt/pg-src' '--with-openssl' '--with-libxml'
```

Notice the difference. The RPM build includes many more flags: `--with-llvm` (JIT compilation), `--with-lz4` and `--with-zstd` (compression), `--with-systemd` (service integration), `--with-gssapi` (Kerberos authentication), and `--with-icu` (Unicode collation). Your source build only has SSL and XML because those are the only flags you passed to `./configure` in Build Guide 03.

> **Concept: Build Flags Determine Capabilities**
> PostgreSQL is modular at compile time. Features like JIT compilation (`--with-llvm`), WAL compression (`--with-lz4`), and Kerberos authentication (`--with-gssapi`) are only available if they were enabled during compilation. The RPM packages from PGDG enable virtually every optional feature so that DBAs do not need to recompile. A source build only includes what you explicitly request.

---

## Step 2 - Verify SSL Support

The security team specifically needs to confirm SSL support. Check the RPM install:

```bash
/usr/pgsql-16/bin/pg_config --configure | tr ' ' '\n' | grep ssl
```

The `tr ' ' '\n'` command replaces spaces with newlines so each flag appears on its own line. The `grep ssl` command filters for the SSL flag.

**Expected:**

```
'--with-openssl'
```

Check the source build:

```bash
/opt/pg-src/bin/pg_config --configure | tr ' ' '\n' | grep ssl
```

**Expected:**

```
'--with-openssl'
```

Both installations have SSL support. You can also verify from within a running server. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -p 5432 -c "SHOW ssl;"
```

**Expected:**

```
 ssl
-----
 off
(1 row)
```

This shows that SSL is compiled in but not currently enabled in the configuration. The `ssl` parameter controls whether the server actually accepts SSL connections - `off` means it is available but turned off. To enable it, you would set `ssl = on` in `postgresql.conf` and provide a certificate.

Exit the postgres user:

```bash
exit
```

> **Concept: Compiled-In vs. Enabled**
> A feature being compiled in (`--with-openssl` in pg_config) does not mean it is active. SSL requires both compilation support AND runtime configuration (certificate files, `ssl = on`). The same applies to JIT - `--with-llvm` compiles the code, but `jit = on` in postgresql.conf activates it. Always check both the build flags and the runtime configuration.

---

## Step 3 - Compare Shared Library Locations

Shared libraries (`.so` files) are compiled code that PostgreSQL loads at runtime. Extensions, client libraries, and server plugins all live here.

Check the RPM shared library directory:

```bash
ls /usr/pgsql-16/lib/ | head -15
```

**Expected (partial):**

```
bitcode
dict_snowball.so
libecpg.a
libecpg.so
libecpg.so.6
...
libpq.so
libpq.so.5
libpq.so.5.16
pgxs
postgresql
```

Check the source build shared library directory:

```bash
ls /opt/pg-src/lib/ | head -15
```

**Expected (partial):**

```
libecpg.a
libecpg.so
libecpg.so.6
...
libpq.so
libpq.so.5
libpq.so.5.16
postgresql
```

Notice that the RPM install has a `bitcode/` directory. This contains LLVM bitcode files used for JIT compilation. Your source build does not have this directory because you did not compile with `--with-llvm`.

Now check where extensions live. Count the extension control files in each installation:

```bash
ls /usr/pgsql-16/share/extension/*.control | wc -l
```

**Expected:** A number around 50-60. These are all the extensions that ship with the contrib package.

```bash
ls /opt/pg-src/share/postgresql/extension/*.control | wc -l
```

**Expected:** A smaller number (around 40-50). The source build includes only the core contrib extensions - no third-party extensions.

> **Concept: Library Path Matters**
> When PostgreSQL loads a shared library (for an extension like `pg_stat_statements`), it searches the `lib/` directory of its own installation. The RPM install looks in `/usr/pgsql-16/lib/`, the source build looks in `/opt/pg-src/lib/`. You cannot install an extension's `.so` file in one location and expect a different PostgreSQL installation to find it. Each installation is self-contained.

---

## Step 4 - Quick-Start the Source Build

Start the source-compiled PostgreSQL on port 5434, connect to it, compare runtime settings with the RPM install, then shut it down.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Initialize a temporary data directory:

```bash
/opt/pg-src/bin/initdb -D /tmp/pg-src-exercise
```

**Expected (last lines):**

```
Success. You can now start the database server using:
    /opt/pg-src/bin/pg_ctl -D /tmp/pg-src-exercise -l logfile start
```

Start the source-compiled server on port 5434:

```bash
/opt/pg-src/bin/pg_ctl -D /tmp/pg-src-exercise -l /tmp/pg-src-exercise.log start -o '-p 5434'
```

`-D` specifies the data directory. `-l` sends server output to a log file instead of the terminal. `-o '-p 5434'` passes the `-p` option to the postgres process, setting the port to 5434.

**Expected:**

```
waiting for server to start.... done
server started
```

Connect to the source-compiled server:

```bash
/opt/pg-src/bin/psql -p 5434 -c "SELECT version();"
```

**Expected:**

```
                                                  version
-----------------------------------------------------------------------------------------------------------
 PostgreSQL 16.8 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x, 64-bit
(1 row)
```

Now compare a specific setting between the two installations. Check whether JIT is available on each:

```bash
psql -p 5432 -c "SHOW jit;"
```

**Expected:**

```
 jit
-----
 on
(1 row)
```

```bash
/opt/pg-src/bin/psql -p 5434 -c "SHOW jit;"
```

**Expected:**

```
 jit
-----
 off
(1 row)
```

The RPM install has JIT enabled by default (because it was compiled with `--with-llvm`). The source build does not support JIT at all because you compiled without that flag.

Compare compression support. Check if `wal_compression` options differ:

```bash
psql -p 5432 -c "SELECT name, enumvals FROM pg_settings WHERE name = 'wal_compression';"
```

**Expected (PG16 RPM with lz4 and zstd compiled in):**

```
      name       |          enumvals
-----------------+-----------------------------
 wal_compression | {off,pglz,lz4,zstd,on}
(1 row)
```

```bash
/opt/pg-src/bin/psql -p 5434 -c "SELECT name, enumvals FROM pg_settings WHERE name = 'wal_compression';"
```

**Expected (source build without lz4/zstd):**

```
      name       |     enumvals
-----------------+-------------------
 wal_compression | {off,pglz,on}
(1 row)
```

The source build only offers `pglz` (the built-in compression). The RPM build also offers `lz4` and `zstd` because it was compiled with those libraries.

> **Concept: pg_settings Reflects Build Options**
> The `pg_settings` view is not just a configuration reference - it reflects what the running server is actually capable of. If a feature was not compiled in, the corresponding settings either disappear or show reduced options. This is why `pg_config --configure` and `pg_settings` are your two best tools for understanding what a server can do.

---

## Step 5 - Stop and Clean Up

Stop the source-compiled server:

```bash
/opt/pg-src/bin/pg_ctl -D /tmp/pg-src-exercise stop
```

**Expected:**

```
waiting for server to shut down.... done
server stopped
```

Remove the temporary data directory:

```bash
rm -rf /tmp/pg-src-exercise
```

Remove the log file:

```bash
rm -f /tmp/pg-src-exercise.log
```

Verify cleanup:

```bash
ls /tmp/pg-src-exercise
```

If you see `ls: cannot access '/tmp/pg-src-exercise': No such file or directory`, the directory was removed successfully. If you see files listed, go back and run the `rm -rf` command.

Confirm nothing is listening on port 5434:

```bash
ss -tlnp | grep 5434
```

**Expected:** No output (nothing listening on that port).

Exit the postgres user:

```bash
exit
```

---

## Checkpoint

Before moving on, confirm you can:

- [ ] Use `pg_config --configure` to display the build flags for any PostgreSQL installation
- [ ] Identify which features are compiled in (SSL, JIT, LZ4, GSSAPI) by reading the flags
- [ ] Explain the difference between "compiled in" and "enabled" for features like SSL and JIT
- [ ] Locate the shared library directory for both RPM and source builds
- [ ] Start a source-compiled PostgreSQL on a non-default port for testing
- [ ] Use `pg_settings` to verify runtime capabilities
- [ ] Clean up temporary clusters completely (data directory, log file, running process)

---

**Next:** Exercise 04 - Extension Workshop
