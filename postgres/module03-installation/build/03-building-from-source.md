# Build 03: Building PostgreSQL from Source

Compile PostgreSQL 16 from source code into `/opt/pg-src/`. You already have PG16
and PG15 installed from RPM packages - this source build is a completely separate
installation that teaches you what happens "under the hood" when you install
from a package.

The source-compiled PostgreSQL will NOT run as a service. You will build it,
test it briefly, and clean up.

**Server:** your lab server (1 node)
**Duration:** 60-90 minutes
**User context:** commands run as `ec2-user` unless noted otherwise

---

## 1. Install build dependencies

Before you can compile C code, you need a compiler and several development
libraries. These are the headers and static libraries that PostgreSQL links
against during the build.

Install `gcc` (the C compiler) and `make` (the build automation tool):

```bash
sudo dnf install -y gcc make
```

```
Expected output (yours will differ):
Dependencies resolved.
...
Installed:
  gcc-11.x.x  make-4.x.x  ...
Complete!
```

Install the development headers for readline, zlib, libxml2, and OpenSSL. The
`-devel` packages contain header files that the compiler needs - the regular
packages only contain the runtime libraries:

```bash
sudo dnf install -y readline-devel zlib-devel libxml2-devel openssl-devel libicu-devel
```

(`libicu-devel` is required because PostgreSQL 16 enables ICU collation support by default. Without it, `./configure` will fail with `ICU library not found`.)

```
Expected output (yours will differ):
Dependencies resolved.
...
Installed:
  readline-devel-8.x  zlib-devel-1.x  libxml2-devel-2.x  openssl-devel-3.x  libicu-devel-70.x  ...
Complete!
```

> **Concept - Why devel packages?**
> When you install `readline` (the regular package), you get the shared library
> file (`.so`) that programs use at runtime. The `readline-devel` package adds
> header files (`.h`) that the compiler needs to build programs that use readline.
> RPM-installed PostgreSQL doesn't need these because it was already compiled
> before you installed it.

---

## 2. Download PostgreSQL source code

Download the PostgreSQL 16.8 source tarball from the official FTP server. The
`-O` flag tells curl to save the file with its original filename:

```bash
curl -O https://ftp.postgresql.org/pub/source/v16.8/postgresql-16.8.tar.gz
```

```
Expected output:
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 30.1M  100 30.1M    0     0  15.2M      0  0:00:01  0:00:01 --:--:-- 15.2M
```

Verify the file downloaded. The `-lh` flags show a long listing with
human-readable file sizes:

```bash
ls -lh postgresql-16.8.tar.gz
```

```
Expected output:
-rw-r--r--. 1 ec2-user ec2-user 31M Apr 18 00:00 postgresql-16.8.tar.gz
```

Extract the tarball. The `x` flag extracts, `z` decompresses gzip, `f` specifies
the filename:

```bash
tar xzf postgresql-16.8.tar.gz
```

Change into the extracted source directory:

```bash
cd postgresql-16.8
```

List the top-level contents so you can see what's inside:

```bash
ls
```

```
Expected output:
aclocal.m4  config  configure  configure.ac  contrib  doc  GNUmakefile.in
HISTORY  INSTALL  Makefile  README  src  ...
```

> **Concept - What's in the source tree?**
> The `src/` directory contains all of PostgreSQL's C source code. The `contrib/`
> directory contains optional extension modules like `pg_stat_statements`. The
> `configure` script is a shell script that detects your system's libraries and
> generates the Makefiles that control the actual compilation.

---

## 3. Configure the build

Run the `configure` script to prepare the build. This script checks your system
for required libraries, sets compilation options, and generates Makefiles.

- `--prefix=/opt/pg-src` tells it where to install the final binaries (not the
  default `/usr/local/pgsql`)
- `--with-openssl` enables SSL/TLS support for encrypted connections
- `--with-libxml` enables XML data type support

```bash
./configure --prefix=/opt/pg-src --with-openssl --with-libxml
```

The script prints many lines as it checks for each library and feature. The last
few lines are the important ones:

```
Expected output (last lines):
...
checking for library containing xmlParseMemory... -lxml2
configure: creating ./config.status
config.status: creating GNUmakefile
config.status: creating src/Makefile.global
...
config.status: linking src/include/port/linux.h to src/include/pg_config_os.h
config.status: linking src/makefiles/Makefile.linux to src/Makefile.port
```

If configure fails, it prints a clear error telling you which library is missing.
If you see errors, go back to Step 1 and make sure all `-devel` packages are
installed.

> **Concept - What does configure actually do?**
> The `configure` script is an autotools-generated shell script (over 30,000
> lines). It probes your system to answer questions like: "Where is the OpenSSL
> header file?", "Does this system have 64-bit integers?", "Which flags does
> the C compiler need?" The answers get written into `src/Makefile.global` and
> `src/include/pg_config.h`, which the compiler reads during the next step.

---

## 4. Compile PostgreSQL

Run `make` to compile all of the source code into binary executables. The `-j2`
flag tells make to run 2 compilation jobs in parallel, which is appropriate for
a t3.small instance (2 vCPUs):

```bash
make -j2
```

This takes 3-5 minutes on a t3.small. You will see hundreds of lines of compiler
output scrolling by. Each line shows a `.c` file being compiled into a `.o`
object file.

```
Expected output (first and last lines):
make -C src/port all
make[1]: Entering directory '.../src/port'
gcc -Wall -Wmissing-prototypes ...
...
... (many lines of compilation output) ...
...
make[1]: Leaving directory '.../src/bin/scripts'
All of PostgreSQL successfully made. Ready to install.
```

The key line is the last one: **"All of PostgreSQL successfully made. Ready to
install."** If you see errors instead, scroll up to find the first error message.

> **Concept - What does make do?**
> `make` reads the Makefiles generated by `configure` and executes the build
> rules in order. Each rule typically runs `gcc` to compile a `.c` source file
> into a `.o` object file, then links object files together into executables
> like `postgres`, `psql`, and `pg_dump`. The `-j2` flag lets it compile two
> files at the same time instead of one at a time.

---

## 5. Install the compiled binaries

Run `make install` with sudo to copy the compiled binaries, libraries, and
headers into `/opt/pg-src/`. You need sudo because `/opt/` is owned by root:

```bash
sudo make install
```

```
Expected output (last lines):
...
/usr/bin/install -c -m 644 ./errcodes.txt '/opt/pg-src/share/postgresql'
...
PostgreSQL installation complete.
```

Now explore the installed directory tree. The `-F` flag adds a `/` after
directory names so you can see what's a directory:

```bash
ls -F /opt/pg-src/
```

```
Expected output:
bin/  include/  lib/  share/
```

List the binaries that were installed:

```bash
ls /opt/pg-src/bin/
```

```
Expected output:
clusterdb   dropdb    initdb       pg_basebackup  pg_dump      pg_isready    pg_restore     pg_verifybackup  psql
createdb    dropuser  oid2name     pg_checksums   pg_dumpall   pg_receivewal pg_rewind      pg_waldump       reindexdb
createuser  ecpg      pg_amcheck   pg_config      pg_export    pg_recvlogical pg_test_fsync  postgres         vacuumdb
```

List the shared libraries:

```bash
ls /opt/pg-src/lib/
```

```
Expected output:
libecpg.a        libecpg.so.6      libecpg_compat.so    libpgcommon_shlib.a  libpgtypes.so.3  libpq.so.5      postgresql/
libecpg.so       libecpg.so.6.16   libecpg_compat.so.3  libpgfeutils.a       libpgtypes.so.3.16  libpq.so.5.16
...
```

List what's in the share directory - this is where SQL scripts and extension
files live:

```bash
ls /opt/pg-src/share/postgresql/
```

```
Expected output:
errcodes.txt  information_schema.sql  postgres.bki  snowball_create.sql
extension/    pg_hba.conf.sample      postgresql.conf.sample  sql_features.txt
...
```

> **Concept - The four directories**
> Every PostgreSQL installation (source or RPM) has four key directories:
> - `bin/` - executable programs (postgres, psql, pg_dump, etc.)
> - `lib/` - shared libraries (.so files) that executables link against at runtime
> - `share/` - SQL scripts, sample configs, extension files, timezone data
> - `include/` - C header files, used only if you build extensions against this install

---

## 6. Quick test - initialize, start, connect, stop

Create a temporary test cluster to verify the build works. You do NOT need to
be the postgres user for this - but we will switch to postgres so the data
directory ownership is correct.

First, make sure the postgres user can access the source-built binaries:

```bash
sudo chmod 755 /opt/pg-src
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Initialize a test cluster in `/tmp/pg-src-test`. The `-D` flag specifies the
data directory:

```bash
/opt/pg-src/bin/initdb -D /tmp/pg-src-test
```

```
Expected output:
The files belonging to this database system will be owned by user "postgres".
This user must also own the server process.
...
Success. You can now start the database server using:
    /opt/pg-src/bin/pg_ctl -D /tmp/pg-src-test -l logfile start
```

Start the test server on port 5434 so it doesn't conflict with your existing
RPM-installed PostgreSQL on port 5432. The `-l` flag sets the log file location.
The `-o` flag passes options to the postgres server process, and `-p 5434` tells
it to listen on port 5434:

```bash
/opt/pg-src/bin/pg_ctl -D /tmp/pg-src-test -l /tmp/pg-src-test.log start -o '-p 5434'
```

```
Expected output:
waiting for server to start.... done
server started
```

Connect with psql and check the version. The `-p` flag specifies the port:

```bash
/opt/pg-src/bin/psql -p 5434 -c "SELECT version();"
```

```
Expected output:
                                                  version
-----------------------------------------------------------------------------------------------------------
 PostgreSQL 16.8 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x ..., 64-bit
(1 row)
```

Notice the output says "compiled by gcc" - this confirms you are connected to
your source-compiled build, not the RPM version.

Now stop the test server:

```bash
/opt/pg-src/bin/pg_ctl -D /tmp/pg-src-test stop
```

```
Expected output:
waiting for server to shut down.... done
server stopped
```

Remove the test cluster directory. The `-rf` flags remove recursively without
prompting:

```bash
rm -rf /tmp/pg-src-test
```

Remove the log file too:

```bash
rm -f /tmp/pg-src-test.log
```

Exit back to ec2-user:

```bash
exit
```

**You are now ec2-user again.**

---

## 7. Compare source vs RPM install

Now that you have both installations, compare them side by side. This shows you
what the RPM packaging adds on top of the raw source build.

Compare the binary locations:

```bash
ls /opt/pg-src/bin/postgres
```

```
Expected output:
/opt/pg-src/bin/postgres
```

```bash
ls /usr/pgsql-16/bin/postgres
```

```
Expected output:
/usr/pgsql-16/bin/postgres
```

Both contain the same `postgres` binary - just in different directories.

Check if the RPM install has a systemd service file (source builds don't create
one):

```bash
ls /usr/lib/systemd/system/postgresql-16.service
```

```
Expected output:
/usr/lib/systemd/system/postgresql-16.service
```

Check if a matching file exists for the source build:

```bash
ls /usr/lib/systemd/system/postgresql-src.service 2>/dev/null
```

```
Expected output:
(no output - the file does not exist)
```

Check what the `alternatives` system provides for the RPM install. The
`alternatives` command manages symbolic links so you can type `psql` instead of
the full path:

```bash
alternatives --display pgsql-psql 2>/dev/null
```

```
Expected output (yours may differ):
pgsql-psql - status is auto.
 link currently points to /usr/pgsql-16/bin/psql
...
```

Check if the RPM added a logrotate configuration:

```bash
ls /etc/logrotate.d/postgresql-16 2>/dev/null
```

```
Expected output (if present):
/etc/logrotate.d/postgresql-16
```

### Summary: what RPM adds beyond the raw source build

| Feature | Source build | RPM install |
|---------|-------------|-------------|
| PostgreSQL binaries | Yes (`/opt/pg-src/bin/`) | Yes (`/usr/pgsql-16/bin/`) |
| Shared libraries | Yes (`/opt/pg-src/lib/`) | Yes (`/usr/pgsql-16/lib/`) |
| systemd service file | No | Yes |
| `alternatives` symlinks | No | Yes |
| Logrotate config | No | Yes |
| Auto-created `postgres` user | No | Yes |
| Default data directory setup | No | Yes (`/opt/pgsql/data/`) |
| SELinux labels | No | Yes |
| Dependency tracking (dnf) | No | Yes |

> **Concept - Why use RPMs in production?**
> Source builds give you maximum control and are great for learning. But in
> production, RPM packages handle service management (systemd), log rotation,
> automatic user creation, security labels (SELinux), and clean upgrades through
> `dnf update`. You don't want to manage all of that manually across dozens of
> servers. Source builds are for development, custom patching, or environments
> where you need non-standard compile flags.

---

## Clean up the source directory (optional)

The extracted source tree uses about 500MB of disk space. If you want to reclaim
that space, remove it. If you want to keep it for reference, skip this step.

```bash
cd ~
```

```bash
rm -rf postgresql-16.8
```

```bash
rm -f postgresql-16.8.tar.gz
```

The compiled installation at `/opt/pg-src/` stays in place - you may use it in
later exercises.

---

## Checkpoint

Verify your work before moving on:

- [ ] `gcc --version` runs without error (build tools installed)
- [ ] `/opt/pg-src/bin/postgres --version` prints `postgres (PostgreSQL) 16.8`
- [ ] `/opt/pg-src/bin/psql --version` prints `psql (PostgreSQL) 16.8`
- [ ] `/usr/pgsql-16/bin/postgres --version` also works (RPM install still intact)
- [ ] No test cluster left behind (`ls /tmp/pg-src-test` returns "No such file")
- [ ] No stray postgres process on port 5434 (`ss -tlnp | grep 5434` returns nothing)

Run this final check to confirm the test cluster was cleaned up:

```bash
ls /tmp/pg-src-test
```

If you see files listed, the test cluster still exists - go back and run the `rm -rf /tmp/pg-src-test` command from Step 6. If you see `ls: cannot access '/tmp/pg-src-test': No such file or directory`, the cleanup was successful.

Confirm no postgres process is running on port 5434:

```bash
ss -tlnp | grep 5434
```

```
Expected output:
(no output - nothing is listening on port 5434)
```

---

**Proceed to Guide 04 - Extensions**
