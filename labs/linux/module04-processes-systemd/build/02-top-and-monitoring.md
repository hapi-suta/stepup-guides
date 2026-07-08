# Build 02: top and Live Monitoring

`ps` gives you a single snapshot. But when a server is struggling right now,
you want a live view that keeps updating. You will learn `top`, a real-time
process monitor. You will also learn `free`, `uptime`, and load average for a
quick health read. These are the tools a DBA opens the moment a server feels
slow.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. top - The live process monitor

`top` shows a view of the busiest processes that keeps updating. Unlike `ps`,
it refreshes every few seconds. So you can watch what is happening in real
time.

```bash
top
```

`top` takes over your whole terminal. It will not return to the prompt until
you quit. To quit, press `q`.

```
Expected output (yours will differ):
top - 18:35:25 up 2 min,  0 users,  load average: 0.11, 0.13, 0.05
Tasks: 106 total,   1 running, 105 sleeping,   0 stopped,   0 zombie
%Cpu(s):  0.0 us,  0.0 sy,  0.0 ni,100.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
MiB Mem :   1669.3 total,   1303.7 free,    293.9 used,    219.7 buff/cache
MiB Swap:      0.0 total,      0.0 free,      0.0 used.   1375.4 avail Mem

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
      1 root      20   0  108676  16768  11324 S   0.0   1.0   0:02.86 systemd
      2 root      20   0       0      0      0 S   0.0   0.0   0:00.00 kthreadd
      3 root      20   0       0      0      0 S   0.0   0.0   0:00.00 pool_wo+
...
```

Remember: press `q` to quit `top` and get your prompt back.

---

## 2. Reading the top summary (the first 5 lines)

The header at the top is a full server health summary. Read it line by line.

### Line 1 - uptime and load average

```
top - 18:35:25 up 2 min,  0 users,  load average: 0.11, 0.13, 0.05
```

- `up 2 min` - how long the server has been running since its last boot
- `0 users` - how many users are logged in (a batch `top -b` run may show 0; an interactive login shows 1)
- `load average: 0.11, 0.13, 0.05` - the system load over the last 1, 5, and 15 minutes

Load average is the most important number here. It roughly means "the average
number of processes waiting to run". Compare it to the number of CPU cores:

- Load below the core count - the server has spare capacity
- Load equal to the core count - the server is fully busy
- Load far above the core count - processes are queuing and everything feels slow

> **Concept - Load Average and Cores:** A load average of 2.0 is healthy on a
> 4-core machine (half busy). But it means overloaded on a 1-core machine (200%
> busy). Always read load against the number of cores. Check your core count
> with `nproc`. The three numbers (1, 5, 15 minutes) show the trend. If the
> 1-minute number is much higher than the 15-minute number, the load is spiking
> right now.

### Line 2 - task counts

```
Tasks: 106 total,   1 running, 105 sleeping,   0 stopped,   0 zombie
```

This counts processes by state. Most are `sleeping` (waiting for work), which
is normal. Watch the `zombie` count. Zombies are dead processes that were not
cleaned up. A few are harmless, but many can mean a parent process is
misbehaving.

### Line 3 - CPU usage

```
%Cpu(s):  0.0 us,  0.0 sy,  0.0 ni,100.0 id,  0.0 wa, ...
```

- `us` - time spent on user programs (like PostgreSQL)
- `sy` - time spent in the kernel (system calls)
- `id` - idle time (how much CPU is free)
- `wa` - I/O wait (CPU waiting on disk)

> **DBA Context - I/O Wait (wa):** A high `wa` number means the CPU is sitting
> idle, waiting for the disk. For a database this is a red flag. It usually
> means slow storage or too many disk reads and writes. If `wa` is high while
> `us` is low, your bottleneck is the disk, not the CPU.

### Lines 4 and 5 - memory and swap

```
MiB Mem :   1669.3 total,   1303.7 free,    293.9 used,    219.7 buff/cache
MiB Swap:      0.0 total,      0.0 free,      0.0 used.   1375.4 avail Mem
```

These show physical RAM and swap. `buff/cache` is memory Linux borrows for disk
caching. It is not truly "used" and will be freed if a program needs it. On this
lab server swap shows `0.0` because no swap is configured, which is common on a
small default instance. When swap IS present, remember that a little swap use is
not automatically bad, but heavy, growing swap usage means the server is short
on RAM.

---

## 3. Sorting and interacting with top

While `top` is running, you can press single keys to change the view. Start it
again:

```bash
top
```

Now try these keys (press the key, watch the screen change):

- `M` (capital M) - sort by memory usage, highest first
- `P` (capital P) - sort by CPU usage, highest first (this is the default)
- `k` - kill a process (it prompts you for a PID - you will learn kill in Build 03)
- `1` (the number one) - toggle a per-core CPU breakdown instead of one combined line
- `q` - quit

Press `M` and watch the process list re-order by the `%MEM` column. Press `P`
to go back to CPU order. Press `q` to quit when done.

> **DBA Context - top During an Incident:** When a database server is slow, a
> DBA opens `top`. They check the load average against the core count, then
> glance at `wa` for disk trouble. Then they press `M` to see if one process is
> hogging RAM, or `P` to see if one is hogging CPU. Within seconds you know
> whether the problem is CPU, memory, or disk.

---

## 4. free -h - Memory at a glance

If you only want the memory picture without the full `top` display, use `free`.

```bash
free -h
```

The `-h` flag means "human-readable". It shows sizes in MB and GB instead of
raw bytes.

```
Expected output (yours will differ):
               total        used        free      shared  buff/cache   available
Mem:           1.6Gi       293Mi       1.3Gi       4.0Mi       219Mi       1.3Gi
Swap:             0B          0B          0B
```

Here is what each column means:

- `total` - total physical RAM
- `used` - RAM actively used by programs
- `free` - completely unused RAM
- `buff/cache` - RAM used for disk caching (can be reclaimed)
- `available` - the number that matters most - RAM actually free for new programs, including cache that can be reclaimed

> **DBA Context - available vs free:** Beginners panic when `free` is low. But
> `available` is the real measure. Linux uses spare RAM for disk cache on
> purpose to speed things up, and gives it back when needed. Only worry when
> `available` is low AND swap usage is climbing. That means true memory
> pressure, which can slow or crash a database.

---

## 5. uptime - The quick load check

When you just want the load average and how long the server has been up,
`uptime` gives it in one line. It does not take over the terminal.

```bash
uptime
```

```
Expected output (yours will differ):
 18:35:25 up 2 min,  1 user,  load average: 0.11, 0.13, 0.05
```

This is the same load average shown at the top of `top`. But you get it
instantly and return to your prompt. It is the fastest possible health check.

To confirm how many cores you have (so the load numbers mean something):

```bash
nproc
```

`nproc` prints the number of processing units (cores) available.

```
Expected output (yours will differ):
2
```

With 2 cores, a load average around 2.0 means fully busy. Anything well above
that means the server is overloaded.

> **DBA Context - The First 30 Seconds:** When a "server slow" alert fires, a
> common DBA routine is: run `uptime` to read the load, run `nproc` to know the
> core count, run `free -h` to check memory, then open `top` to find the
> offending process. These four commands take under a minute. They point you at
> CPU, memory, or disk before you even touch the database.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Open `top` and quit it with `q`
- [ ] Read the load average and compare it to the core count from `nproc`
- [ ] Explain what `us`, `sy`, `id`, and `wa` mean in the CPU line
- [ ] Explain why a high `wa` (I/O wait) matters for a database
- [ ] Sort `top` by memory (`M`) and by CPU (`P`)
- [ ] Run `free -h` and explain why `available` matters more than `free`
- [ ] Run `uptime` for a fast load check
- [ ] Explain why load average must be read against the number of cores
