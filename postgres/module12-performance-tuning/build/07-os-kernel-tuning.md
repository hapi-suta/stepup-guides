# Build 07 - OS Kernel Tuning for PostgreSQL

**Module 12 - Performance Tuning**
**Estimated Time: 25-30 minutes**

The Linux kernel has dozens of settings that control how the operating system manages memory, disk writes, and processes. The defaults are designed for general-purpose servers, not databases. In this guide, you will change six key kernel settings to make CentOS work better with PostgreSQL.

**Important:** These changes are safe for a lab environment. In production, always test kernel changes during a maintenance window and have a rollback plan.

---

## Prerequisites

- Your CentOS Stream 9 server is running
- You completed Build 06 (OS-Level Diagnostics)
- You have your SSH key (.pem file) and server IP address from the welcome email

---

## Step 0: Connect to Your Server

Open your terminal (Mac) or PowerShell (Windows).

SSH into your server. Replace `YOUR_SERVER_IP` with the IP from your welcome email.

```bash
ssh -i ~/Downloads/your-key.pem ec2-user@YOUR_SERVER_IP
```

This connects you to your server as the `ec2-user` account. The `-i` flag tells SSH which private key file to use for authentication.

You should now see a prompt like:

```
[ec2-user@pg-primary ~]$
```

---

## Section 1: Checking Current Kernel Settings

Before changing anything, let's see what the current settings look like. The `sysctl` command reads and writes kernel parameters.

### Step 1.1: Check the four main settings

```bash
sysctl vm.swappiness vm.dirty_ratio vm.dirty_background_ratio vm.overcommit_memory
```

This reads the current values for four kernel parameters. The `vm.` prefix means these are all virtual memory settings.

Expected output (yours will differ):

```
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.overcommit_memory = 0
```

### Step 1.2: What each setting does

| Setting | Default | What It Controls |
|---------|---------|-----------------|
| `vm.swappiness` | 10 | How aggressively Linux moves data from RAM to swap. Higher = more swapping. |
| `vm.dirty_ratio` | 20 | Maximum percentage of RAM that can hold "dirty" (unwritten) data before ALL processes are forced to stop and wait for writes to finish. |
| `vm.dirty_background_ratio` | 10 | Percentage of RAM with dirty data that triggers background flushing to disk. The OS starts writing quietly without blocking anything. |
| `vm.overcommit_memory` | 0 | How Linux decides whether to approve a process's request for more memory. 0 = use a heuristic guess. |

Don't worry if these don't make full sense yet. Each section below explains one setting in detail and why the default hurts PostgreSQL.

---

## Section 2: Setting vm.swappiness = 1

### Why this matters

The `swappiness` value tells Linux how eager it should be to move data from RAM to disk (swap). The scale is 0 to 100:

- **100** = Swap aggressively (move data to disk even if there is free RAM)
- **10** = Swap only when RAM is getting low (the current default)
- **1** = Almost never swap - only in emergencies
- **0** = Never swap at all

### Why 1, not 0

Setting swappiness to 0 sounds ideal, but it is dangerous. If the server truly runs out of RAM with swappiness at 0, the Linux OOM (Out Of Memory) killer activates and kills processes to free memory. It often picks PostgreSQL because PostgreSQL uses the most RAM. Getting killed by the OOM killer means your database crashes with no clean shutdown.

Setting swappiness to 1 means "almost never swap, but if the alternative is the OOM killer, use swap as a last resort." This gives you a safety net.

### Step 2.1: Set swappiness to 1 (temporary)

```bash
sudo sysctl -w vm.swappiness=1
```

The `-w` flag tells `sysctl` to write (change) the value. This change takes effect immediately but will be lost on reboot.

Expected output (yours will differ):

```
vm.swappiness = 1
```

### Step 2.2: Verify the change

```bash
sysctl vm.swappiness
```

Expected output (yours will differ):

```
vm.swappiness = 1
```

### Step 2.3: Make it persistent (survives reboot)

To keep this setting after a reboot, we need to add it to a configuration file. We will create one file for all PostgreSQL kernel tunings.

```bash
sudo vi /etc/sysctl.d/99-postgresql.conf
```

This opens the vi text editor to create a new file. The `99-` prefix means this file loads last, so it overrides any earlier defaults. The `.conf` extension is required for sysctl to read it.

Press `i` to enter insert mode, then type:

```
# PostgreSQL kernel tuning - SUTA Labs Module 12
vm.swappiness = 1
```

Press `Esc` to exit insert mode, then type `:wq` and press `Enter` to save and quit.

### Step 2.4: Verify the file was saved

```bash
cat /etc/sysctl.d/99-postgresql.conf
```

Expected output (yours will differ):

```
# PostgreSQL kernel tuning - SUTA Labs Module 12
vm.swappiness = 1
```

---

## Section 3: Tuning dirty_ratio and dirty_background_ratio

### Why this matters

When PostgreSQL writes data, the data does not go directly to disk. It goes into a memory area called the "page cache" and is marked as "dirty" (meaning it has not been written to disk yet). The kernel eventually flushes dirty pages to disk.

Two settings control this flushing:

- **dirty_background_ratio** - When dirty pages reach this percentage of RAM, the kernel starts writing them to disk in the background. Applications (including PostgreSQL) keep running normally.
- **dirty_ratio** - When dirty pages reach THIS percentage of RAM, the kernel STOPS all applications and forces everything to wait until the writes finish. This causes a noticeable freeze.

### The problem with defaults

With `dirty_ratio = 20` and `dirty_background_ratio = 10`, the OS can accumulate a large amount of dirty data before background flushing starts. When a PostgreSQL checkpoint happens, lots of dirty pages get created at once. If they exceed `dirty_ratio`, every query freezes until the writes finish.

### The fix

Lower both values so the OS flushes data more frequently in smaller batches. This prevents the big "freeze and flush" events.

### Step 3.1: Set dirty_background_ratio to 3

```bash
sudo sysctl -w vm.dirty_background_ratio=3
```

This tells the kernel to start background flushing when only 3% of RAM has dirty pages. On our 736 MB server, that is about 22 MB - a small amount that can be written to disk quickly.

Expected output (yours will differ):

```
vm.dirty_background_ratio = 3
```

### Step 3.2: Set dirty_ratio to 10

```bash
sudo sysctl -w vm.dirty_ratio=10
```

This sets the "panic and freeze" threshold to 10% of RAM (about 73 MB on this server). With background flushing starting at 3%, we should rarely reach 10%.

Expected output (yours will differ):

```
vm.dirty_ratio = 10
```

### Step 3.3: Add both to the persistent configuration file

```bash
sudo vi /etc/sysctl.d/99-postgresql.conf
```

Press `G` to go to the last line, then press `o` to open a new line below. Type:

```
vm.dirty_background_ratio = 3
vm.dirty_ratio = 10
```

Press `Esc`, then type `:wq` and press `Enter`.

### Step 3.4: Verify the file

```bash
cat /etc/sysctl.d/99-postgresql.conf
```

Expected output (yours will differ):

```
# PostgreSQL kernel tuning - SUTA Labs Module 12
vm.swappiness = 1
vm.dirty_background_ratio = 3
vm.dirty_ratio = 10
```

### How this interacts with PostgreSQL checkpoints

PostgreSQL periodically runs "checkpoints" that flush all modified data from shared_buffers to disk. This generates a burst of dirty pages. With lower dirty ratios, the OS spreads these writes out more smoothly instead of letting them pile up. The result is steadier I/O performance with fewer latency spikes during checkpoints.

---

## Section 4: Overcommit Memory

### Why this matters

When a program asks Linux for memory, the kernel can either:

- **Mode 0 (default):** Use a heuristic to guess whether enough memory is available. Sometimes it guesses wrong and the OOM killer has to step in later.
- **Mode 1:** Always say yes, even if there is not enough memory. Very dangerous.
- **Mode 2:** Only say yes if the total committed memory (all programs combined) stays below a calculated limit. This is the most predictable behavior.

### Why mode 2 is best for PostgreSQL

With mode 0, the kernel might allow PostgreSQL to allocate memory, then later decide it over-promised and kill PostgreSQL with the OOM killer. With mode 2, the kernel does the math upfront. If there is not enough memory, PostgreSQL gets a clear error message instead of being killed without warning.

### Step 4.1: Set overcommit_memory to 2

```bash
sudo sysctl -w vm.overcommit_memory=2
```

Expected output (yours will differ):

```
vm.overcommit_memory = 2
```

### Step 4.2: Set overcommit_ratio to 80

When using mode 2, the kernel uses this formula to calculate the memory limit:

```
CommitLimit = (overcommit_ratio / 100) * RAM + Swap
```

With 80%:

```
CommitLimit = (80 / 100) * 736 MB + 1024 MB = 588.8 + 1024 = 1612.8 MB
```

This means all programs combined cannot request more than about 1.6 GB of memory. This is a safe limit for our server.

```bash
sudo sysctl -w vm.overcommit_ratio=80
```

Expected output (yours will differ):

```
vm.overcommit_ratio = 80
```

### Step 4.3: Add both to the persistent configuration file

```bash
sudo vi /etc/sysctl.d/99-postgresql.conf
```

Press `G` to go to the last line, then press `o` to open a new line below. Type:

```
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
```

Press `Esc`, then type `:wq` and press `Enter`.

---

## Section 5: Transparent Huge Pages (THP)

### What are Transparent Huge Pages

Normal memory pages in Linux are 4 KB. Transparent Huge Pages (THP) automatically merge groups of small pages into 2 MB "huge pages." This sounds helpful, but it causes serious problems for databases.

### Why THP hurts PostgreSQL

PostgreSQL allocates and frees many small chunks of memory as queries run. THP tries to merge these small chunks into huge pages in the background, which causes:

- **Memory fragmentation** - The kernel spends CPU time defragmenting memory
- **Latency spikes** - Queries randomly pause while the kernel reorganizes pages
- **Unpredictable performance** - The same query might be fast one second and slow the next

Every major database vendor (PostgreSQL, Oracle, MongoDB, Redis) recommends disabling THP.

### Step 5.1: Check the current THP setting

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
```

Expected output (yours will differ):

```
[always] madvise never
```

The brackets `[always]` show which option is currently active. THP is ON - this is bad for PostgreSQL.

### Step 5.2: Disable THP

```bash
sudo sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
```

The `sh -c` wraps the command in a subshell so that `sudo` applies to the whole operation, including the file redirect (`>`). Without `sh -c`, the redirect would run as your regular user and fail with "Permission denied."

### Step 5.3: Verify THP is disabled

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
```

Expected output (yours will differ):

```
always madvise [never]
```

The brackets are now around `[never]` - THP is disabled.

### Step 5.4: Also disable THP defrag

```bash
sudo sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'
```

This disables the background defragmentation process that THP uses. No point running defrag if THP itself is disabled.

### Step 5.5: Verify defrag is disabled

```bash
cat /sys/kernel/mm/transparent_hugepage/defrag
```

Expected output (yours will differ):

```
always defer defer+madvise madvise [never]
```

### Step 5.6: Make THP disabling persistent across reboots

The `/sys/` filesystem resets on every reboot, so we need a systemd service to disable THP at boot time.

```bash
sudo vi /etc/systemd/system/disable-thp.service
```

Press `i` to enter insert mode, then type the following exactly:

```
[Unit]
Description=Disable Transparent Huge Pages for PostgreSQL
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
```

Press `Esc`, then type `:wq` and press `Enter`.

Now enable the service so it runs on every boot:

```bash
sudo systemctl daemon-reload
```

This tells systemd to re-read all service files. Required after creating or modifying a `.service` file.

```bash
sudo systemctl enable disable-thp
```

This configures the service to run automatically on every boot.

Expected output (yours will differ):

```
Created symlink /etc/systemd/system/basic.target.wants/disable-thp.service -> /etc/systemd/system/disable-thp.service.
```

---

## Section 6: Checking ulimits

### What are ulimits

Ulimits (user limits) control how many resources a single user can consume. For PostgreSQL, the two most important are:

- **nofile** - Maximum number of open files. PostgreSQL opens a file for every table, index, and connection. The default of 1024 is too low for production.
- **nproc** - Maximum number of processes. Each PostgreSQL connection is a separate process.

### Step 6.1: Check the current limits for the postgres user

```bash
sudo -u postgres bash -c 'ulimit -n'
```

The `-u postgres` flag runs the command as the postgres user. The `bash -c` wraps it so the ulimit check happens in that user's context. The `-n` flag shows the "nofile" (max open files) limit.

Expected output (yours will differ):

```
1024
```

1024 is the default and is too low for a production database server. A busy PostgreSQL instance can easily have thousands of open files.

### Step 6.2: Check the process limit

```bash
sudo -u postgres bash -c 'ulimit -u'
```

The `-u` flag (inside bash) shows the "nproc" (max processes) limit.

Expected output (yours will differ):

```
3736
```

### Step 6.3: Create a limits configuration file

```bash
sudo vi /etc/security/limits.d/99-postgresql.conf
```

Press `i` to enter insert mode, then type:

```
# PostgreSQL ulimits - SUTA Labs Module 12
postgres soft nofile 65536
postgres hard nofile 65536
postgres soft nproc 65536
postgres hard nproc 65536
```

Press `Esc`, then type `:wq` and press `Enter`.

Here is what each column means:

| Column | Meaning |
|--------|---------|
| `postgres` | The OS user these limits apply to |
| `soft` | The default limit when the user logs in. Can be raised up to the hard limit. |
| `hard` | The absolute maximum. Cannot be exceeded. |
| `nofile` | Maximum number of open file descriptors |
| `nproc` | Maximum number of processes |
| `65536` | The new limit value (64x higher than the default 1024) |

### Step 6.4: Verify the file was saved

```bash
cat /etc/security/limits.d/99-postgresql.conf
```

Expected output (yours will differ):

```
# PostgreSQL ulimits - SUTA Labs Module 12
postgres soft nofile 65536
postgres hard nofile 65536
postgres soft nproc 65536
postgres hard nproc 65536
```

**Note:** These limits take effect the next time the postgres user starts a new session. If PostgreSQL is already running, you will need to restart it for the new limits to apply. We will do that at the end of this guide.

---

## Section 7: File System Mount Options

### Why mount options matter

The file system mount options control how Linux writes data to disk. One option in particular wastes I/O on database servers: `atime`.

By default, every time Linux reads a file, it updates that file's "last accessed time" (atime) metadata. This means every SELECT query that reads data from disk also generates a tiny write operation. On a busy database server, these wasted writes add up.

### Step 7.1: Check current mount options

```bash
mount | grep xfs
```

The `mount` command lists all mounted file systems. The `| grep xfs` filters to show only XFS file systems (which is what CentOS uses by default).

Expected output (yours will differ):

```
/dev/nvme0n1p2 on / type xfs (rw,relatime,seclabel,attr2,inode64,logbufs=8,logbsize=32k,noquota)
```

Look for `relatime` in the parentheses. The `relatime` option is a compromise - it only updates the access time when the file is modified or when the access time is older than 24 hours. This is better than the old `atime` default, but `noatime` (never update access times) is even better for databases.

### Step 7.2: Understanding noatime

The `noatime` mount option tells Linux to never update file access timestamps. For a database server:

- **Benefit:** Eliminates unnecessary write I/O on every read operation
- **Downside:** You lose the ability to see when a file was last accessed (rarely needed on a database server)
- **PostgreSQL impact:** Does not affect any PostgreSQL functionality. PostgreSQL tracks its own statistics internally.

### Step 7.3: Why we will not change it now

Changing mount options on the root filesystem requires either:

- Remounting the filesystem (`mount -o remount,noatime /`) which can be disruptive
- Editing `/etc/fstab` and rebooting

In production, this is a maintenance window activity. On our lab server, the performance difference is negligible because the workload is small. But on a production server handling thousands of queries per second, adding `noatime` to the data partition is recommended.

**For reference, this is what the fstab entry would look like on a production server:**

```
/dev/nvme1n1 /opt/pgsql xfs defaults,noatime,nodiratime 0 0
```

The `nodiratime` option does the same thing as `noatime` but for directories.

---

## Section 8: Huge Pages (Concept Only)

**Note:** On this lab server with only 736 MB of RAM, huge pages are not practical. This section explains the concept so you understand it for production work.

### What are Huge Pages (not Transparent Huge Pages)

Regular Linux memory pages are 4 KB. The CPU uses a lookup table called the TLB (Translation Lookaside Buffer) to translate memory addresses. Each TLB entry maps one page.

If `shared_buffers` is set to 8 GB (a common production setting):

```
8 GB / 4 KB per page = 2,097,152 pages
```

That is over 2 million TLB entries. The TLB is small (a few thousand entries), so the CPU constantly evicts and reloads entries. This is called TLB thrashing and wastes CPU time.

With Huge Pages (2 MB each):

```
8 GB / 2 MB per page = 4,096 pages
```

Only 4,096 TLB entries needed. Much less thrashing, better performance.

### How Huge Pages differ from THP

| Feature | Transparent Huge Pages (THP) | Huge Pages |
|---------|------------------------------|------------|
| Managed by | Kernel automatically | Administrator manually |
| When allocated | Dynamically, on the fly | At boot time, reserved in advance |
| Fragmentation | Yes, causes latency spikes | No, pre-allocated |
| PostgreSQL recommendation | Disable (bad) | Enable (good) |

The key difference: Huge Pages are pre-allocated and stable. THP is dynamic and unpredictable. We disabled THP in Section 5 because it is bad. Huge Pages (when you have enough RAM) are good.

### The calculation for a production server

On a production server with 64 GB RAM and `shared_buffers = 16GB`:

**Step 1:** Find the PostgreSQL shared memory size:

```bash
sudo head -1 /proc/$(sudo cat /opt/pgsql/data/postmaster.pid | head -1)/maps | awk '{print $NF}'
```

**Step 2:** Check the huge page size:

```bash
grep Hugepagesize /proc/meminfo
```

This typically shows `Hugepagesize: 2048 kB` (2 MB).

**Step 3:** Calculate pages needed:

```
Pages needed = shared_buffers / hugepagesize + a small buffer
             = 16 GB / 2 MB + 100
             = 8,192 + 100
             = 8,292
```

**Step 4:** Set the kernel parameter:

```bash
sudo sysctl -w vm.nr_hugepages=8292
```

**Step 5:** Configure PostgreSQL to use them by setting `huge_pages = on` in `postgresql.conf`.

### Step 8.1: Check current huge pages on this server

```bash
grep HugePages /proc/meminfo
```

Expected output (yours will differ):

```
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
```

All zeros - no huge pages are configured. This is expected on our small lab server. With only 736 MB of RAM, reserving huge pages would leave too little memory for the operating system.

---

## Section 9: Apply All Changes

### Step 9.1: Review the final sysctl configuration

```bash
cat /etc/sysctl.d/99-postgresql.conf
```

Expected output (yours will differ):

```
# PostgreSQL kernel tuning - SUTA Labs Module 12
vm.swappiness = 1
vm.dirty_background_ratio = 3
vm.dirty_ratio = 10
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
```

### Step 9.2: Reload all sysctl settings from files

```bash
sudo sysctl --system
```

This re-reads all sysctl configuration files and applies them. The `--system` flag loads settings from all standard config directories.

Expected output (yours will differ):

```
* Applying /etc/sysctl.d/99-postgresql.conf ...
vm.swappiness = 1
vm.dirty_background_ratio = 3
vm.dirty_ratio = 10
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
...
```

### Step 9.3: Verify all settings are active

```bash
sysctl vm.swappiness vm.dirty_ratio vm.dirty_background_ratio vm.overcommit_memory vm.overcommit_ratio
```

Expected output (yours will differ):

```
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
```

### Step 9.4: Restart PostgreSQL to pick up the new ulimits

Switch to the postgres user:

```bash
sudo su - postgres
```

Stop PostgreSQL:

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data
```

The `pg_ctl stop` command gracefully shuts down PostgreSQL. The `-D` flag specifies the data directory.

Expected output (yours will differ):

```
waiting for server to shut down.... done
server stopped
```

Start PostgreSQL:

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data -l /opt/pgsql/log/postgresql.log
```

The `-l` flag specifies the log file for server output.

Expected output (yours will differ):

```
waiting for server to start.... done
server started
```

Verify the new file limit is in effect:

```bash
cat /proc/$(cat /opt/pgsql/data/postmaster.pid | head -1)/limits | grep "Max open files"
```

This reads the actual limits of the running PostgreSQL process. The `postmaster.pid` file contains the process ID of the main PostgreSQL process.

Expected output (yours will differ):

```
Max open files            65536                65536                files
```

65536 - the new limit is active.

Exit the postgres user:

```bash
exit
```

---

## Summary of Changes

| Setting | Before | After | Why |
|---------|--------|-------|-----|
| vm.swappiness | 10 | 1 | Almost never swap - protects PostgreSQL from using slow disk as RAM |
| vm.dirty_background_ratio | 10 | 3 | Flush dirty pages sooner in small batches - smoother I/O during checkpoints |
| vm.dirty_ratio | 20 | 10 | Lower panic threshold - less chance of all queries freezing during heavy writes |
| vm.overcommit_memory | 0 | 2 | Strict memory accounting - prevents OOM killer from targeting PostgreSQL |
| vm.overcommit_ratio | (N/A) | 80 | Sets the memory commit limit to 80% of RAM + swap |
| THP | always | never | Disables unpredictable memory merging that causes latency spikes |
| ulimit nofile | 1024 | 65536 | Allows PostgreSQL to open enough files for busy workloads |
| ulimit nproc | 3736 | 65536 | Allows enough processes for many concurrent connections |

---

## What You Learned

In this guide, you:

1. Reduced swap aggressiveness to keep PostgreSQL data in RAM
2. Tuned dirty page ratios for smoother checkpoint I/O
3. Enabled strict memory overcommit to protect PostgreSQL from the OOM killer
4. Disabled Transparent Huge Pages to prevent latency spikes
5. Increased ulimits so PostgreSQL can handle more files and connections
6. Learned about file system mount options and when to use noatime
7. Understood the concept of Huge Pages for production servers with large shared_buffers

**Next up:** The next Build guide covers PostgreSQL-level configuration tuning, where you will adjust settings like shared_buffers, work_mem, and effective_cache_size inside PostgreSQL itself.
