# Concepts: Processes and systemd

This reference explains the ideas behind Module 04. Read it alongside the BUILD
guides. It goes a little deeper than the hands-on labs. The goal is that you
understand not just how to run the commands, but why they work the way they do.
Everything here connects back to a DBA's daily job: keeping a database service
healthy.

---

## 1. The Linux process model

### What a process is

A process is a running copy of a program. The program itself is just a file on
disk (for example `/usr/bin/psql`). When you run it, the kernel loads it into
memory, gives it resources, and starts running it. That running copy is a
process. You can run the same program many times. Each time creates a separate
process with its own memory.

### PID and PPID

Every process has a PID (process ID). This is a unique number the kernel gives
it. When a process ends, its PID can later be reused by a new process. But at
any moment, a PID points to exactly one running process.

Almost every process is created by another process. That other process is its
parent. The parent's PID is stored on the child as the PPID (parent process
ID). This builds a tree. One process starts others, those start others, and so
on.

PID 1 is special. It is the first process the kernel starts at boot. It has no
parent, and every other process comes from it. On CentOS Stream 9, PID 1 is
systemd.

### How processes are born

A new process starts when an existing process forks. Forking means it makes a
copy of itself. It then usually replaces that copy with a new program. This is
why a database is not just one process. The main server process forks a new
backend process for each client that connects. It also runs helper processes
for background work. Understanding the tree explains what you see in `ps -ef`:
a cluster of related processes under one parent.

### Process states

At any moment, a process is in one of a few states. You see the state in the
`STAT` column of `ps` and in the task summary in `top`:

- **Running / Runnable (R)** - using the CPU or ready to
- **Sleeping (S)** - waiting for something (input, a timer, disk). Most processes are here most of the time - this is normal
- **Uninterruptible sleep (D)** - waiting on I/O and cannot be interrupted. Many D-state processes usually means disk trouble
- **Stopped (T)** - paused by a signal
- **Zombie (Z)** - finished, but its parent has not yet collected its exit status. A few zombies are harmless; many suggest a buggy parent

### Memory: RSS vs VSZ

Two memory numbers show up in `ps`:

- **VSZ (virtual size)** - all the memory the process has reserved, including memory it is not actually using and shared libraries. Often large and misleading
- **RSS (resident set size)** - the real physical RAM the process currently occupies. This is the number that matters for "is this process using too much memory?"

When you troubleshoot memory pressure, sort by RSS, not VSZ.

---

## 2. Signals

Signals are how you control processes. A signal is a small message the kernel
delivers to a process. For most signals, a process can install a handler. The
handler decides what to do when that signal arrives. Here are the signals a DBA
cares about:

| Signal | Number | Meaning | Can be caught? |
|--------|--------|---------|----------------|
| SIGHUP | 1 | Hang up / reload configuration | Yes |
| SIGINT | 2 | Interrupt (what Ctrl+C sends) | Yes |
| SIGTERM | 15 | Please terminate gracefully (default of `kill`) | Yes |
| SIGKILL | 9 | Terminate immediately, no cleanup | No |

The key difference to remember:

- **SIGTERM (15)** is a polite request. The process runs its shutdown routine: finish current work, flush buffers to disk, release locks, close files, then exit. This is what a clean database shutdown uses.
- **SIGKILL (9)** cannot be caught, blocked, or handled. The kernel destroys the process instantly. Nothing gets flushed or cleaned up.

For a database, SIGKILL is costly. The next startup has to do crash recovery. It
replays the write-ahead log to rebuild a consistent state. That takes time. On
damaged storage, it also carries risk. This is why `kill -9` on a database is a
last resort. Use it only when a graceful stop has already failed.

SIGHUP is worth a special note. Many services, including PostgreSQL, read it as
"re-read your configuration." They apply the settings that can be reloaded
without a restart. This is how you change config with zero downtime.

---

## 3. Load average and system health

Load average tells you how busy the system is. It is the average number of
processes that are either running or waiting to run. It is sampled over 1, 5,
and 15 minutes. It is not a percentage. It is a count, so you read it against
the number of CPU cores.

- Load equal to the core count = the machine is fully utilized
- Load below the core count = spare capacity
- Load well above the core count = processes are queuing; the system feels slow

The three numbers show a trend. If the 1-minute load is much higher than the
15-minute load, load is spiking right now. If it is lower, a spike is calming
down.

Load is not only about CPU. Processes stuck waiting on disk I/O also add to
load. So a high load average with low CPU usage often points at slow disk. For a
database, that is a common and important finding. The `wa` (I/O wait) figure in
`top` confirms it.

---

## 4. systemd: the init system

### PID 1 and its job

systemd is the init system on CentOS Stream 9. It is the first process the
kernel starts (PID 1) and the ancestor of every other process. Its job is to
run the system. It brings the system up at boot. It starts and watches over
services, and restarts them if they crash. It orders startup so dependencies
come up first. It also collects everyone's logs.

### Units

systemd manages units. A unit is anything systemd knows how to start and stop.
There are several types. The one you touch daily is the `.service` unit. You
will also see others mentioned: `.target` (a group of units representing a
system state, like `multi-user.target`), `.socket`, `.timer`, and `.mount`.

### Unit states: active and enabled are different

Two separate facts describe a service, and it helps to keep them apart:

- **Active** - is it running right now? States include `active (running)`, `inactive (dead)`, and `failed`.
- **Enabled** - will it start automatically at boot? Either `enabled` or `disabled`.

A service can be any combination of these two. Running-and-enabled is the normal
healthy state. Running-but-disabled works now but will not survive a reboot.
Stopped-but-enabled is down now but will start on the next reboot. And
stopped-and-disabled is off both ways.

Mixing up these two ideas causes a classic outage. An admin starts the database
by hand but forgets to enable it. The database then vanishes after the next
reboot.

The `failed` state is worth calling out. It means systemd tried to keep the
service running, but it exited with an error. `systemctl status` and the journal
tell you why.

### Unit files and the override model

Each unit is defined by a plain-text unit file. The file has three sections:
`[Unit]` (identity, dependencies, ordering), `[Service]` (what command to run
and how to supervise it), and `[Install]` (boot behavior used by
enable/disable).

Unit files live in two places, and the difference matters:

- `/usr/lib/systemd/system/` - vendor files shipped by packages. Do not edit; upgrades overwrite them.
- `/etc/systemd/system/` - your local files and overrides. These win over vendor files with the same name.

To customize a service safely, create a drop-in override with
`systemctl edit <service>`. Your change lands in
`/etc/systemd/system/<service>.d/override.conf` and layers on top of the vendor
file. Your change stays small, stays visible, and survives package updates.

After you edit any unit file, run `systemctl daemon-reload`. This tells systemd
to re-read the files on disk. It is not the same as `systemctl reload
<service>`, which tells the running program to re-read its own configuration. So
remember: edit a unit file -> `daemon-reload`. Change a database setting ->
`reload`.

---

## 5. The journal

systemd collects logs in one place called the journal. The journal is a
structured, indexed store. It captures every service's output, plus kernel and
boot messages. Each entry is tagged with the service name, timestamp, PID, and
priority. You query it with `journalctl`.

This replaces the old way of hunting through many separate text files under
`/var/log`. Instead, you ask for exactly the slice you need: one service (`-u`),
a time window (`--since`/`--until`), a severity floor (`-p err`), the newest
lines (`-n`, `-r`), or a live stream (`-f`).

Here are the priorities, from least to most severe: `debug`, `info`, `notice`,
`warning`, `err`, `crit`, `alert`, `emerg`. When you ask for a level, you get
everything at that level and above.

---

## 6. Why all of this matters to a DBA

This module is not abstract systems trivia. It is the core of daily database
operations:

- **Start / stop / restart the database** - `systemctl start|stop|restart postgresql`. A clean stop is a graceful SIGTERM that checkpoints and flushes before exit.
- **Reload config without downtime** - `systemctl reload postgresql` sends SIGHUP so reloadable settings apply while the database stays up.
- **Confirm it survives reboots** - `systemctl enable postgresql`. Running is not the same as enabled.
- **Check health under load** - `top`, `uptime`, `free -h`, and load average tell you whether CPU, memory, or disk is the bottleneck before you dig into the database itself.
- **Find and stop a runaway** - `ps aux --sort=-%cpu`, then a graceful `kill`; `kill -9` only as a last resort.
- **Investigate an incident** - `systemctl status`, then `journalctl -u postgresql` filtered by time and priority, to find the exact error that took the database down.

Master these and you can confidently answer the two questions a DBA is asked
most: "is the database up?" and "why did it go down?"
