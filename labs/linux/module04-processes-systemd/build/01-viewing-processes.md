# Build 01: Viewing Processes

You will learn how to see what programs are running on your server. You will
also see who started them and how much CPU and memory they use. This is the
first thing a DBA does when a server feels slow or a database will not respond.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first (see Module 01).

---

## 1. What is a process?

Every program running on a Linux server is a process. When you log in, your
shell is a process. PostgreSQL runs as a group of processes. When you type a
command, that command becomes a process for as long as it runs.

Each process gets a unique number called a PID (process ID). The system uses
the PID to track, control, and stop the process.

> **Concept - Processes and PIDs:** A process is a running copy of a program.
> The kernel (the core of Linux) gives every process a PID, a number that
> uniquely identifies it while it runs. When you want to stop, inspect, or
> prioritize a program, you point to it by its PID. PID 1 is always the first
> process the kernel starts (systemd). Every other process comes from it.

---

## 2. ps aux - The full snapshot

The `ps` command shows a snapshot of running processes. The most common way to
run it is `ps aux`.

```bash
ps aux
```

- `a` - show processes from all users, not just yours
- `u` - show them in a user-friendly format with owner, CPU, and memory columns
- `x` - include processes not attached to a terminal (background services)

```
Expected output (yours will differ):
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  2.1  0.9 108676 16768 ?        Ss   18:33   0:02 /usr/lib/systemd/systemd --switched-root ...
root           2  0.0  0.0      0     0 ?        S    18:33   0:00 [kthreadd]
root         799  0.0  0.4  11784  7800 ?        Ss   18:33   0:00 sshd: /usr/sbin/sshd -D [listener] ...
ec2-user    4635  0.0  0.1 224108  4980 pts/0    R+   18:35   0:00 ps aux
...
```

Here is what each column means:

- `USER` - who owns the process
- `PID` - the process ID
- `%CPU` - percentage of CPU the process is using
- `%MEM` - percentage of physical memory (RAM) it is using
- `VSZ` - virtual memory size in KB (total memory the process has reserved)
- `RSS` - resident set size in KB (actual physical RAM the process is using)
- `STAT` - the process state (R running, S sleeping, Z zombie, and more)
- `START` - when the process started
- `TIME` - total CPU time it has consumed
- `COMMAND` - the command that started it

> **DBA Context - RSS vs VSZ:** When you troubleshoot memory, `RSS` matters
> most. It is the real RAM the process holds. A PostgreSQL backend with a lot
> of `RSS` may be running a heavy query. `VSZ` is often large and misleading
> because it counts memory that is reserved but not used. So do not panic over
> a big `VSZ`.

---

## 3. ps -ef - The other common format

`ps -ef` shows the same processes in a different layout. Many DBAs prefer it
because it clearly shows the parent process.

```bash
ps -ef
```

- `-e` - show every process on the system
- `-f` - full-format listing (adds the PPID column)

```
Expected output (yours will differ):
UID          PID    PPID  C STIME TTY          TIME CMD
root           1       0  2 18:33 ?        00:00:02 /usr/lib/systemd/systemd --switched-root ...
root         799       1  0 18:33 ?        00:00:00 sshd: /usr/sbin/sshd -D [listener] ...
root        4593     799  0 18:35 ?        00:00:00 sshd-session: ec2-user [priv]
ec2-user    1201    4593  0 18:35 pts/0    00:00:00 -bash
ec2-user    4635    1201  0 18:35 pts/0    00:00:00 ps -ef
...
```

The new column here is `PPID` (parent process ID). Every process is started by
another process, called its parent. Look at the example above:

- `sshd -D [listener]` (PID 799) has PPID 1 - it was started by systemd
- `sshd-session: ec2-user` (PID 4593) has PPID 799 - the main sshd started it when you logged in (on CentOS Stream 9 the per-connection helper is named `sshd-session`)
- `-bash` (PID 1201) has PPID 4593 - your login shell was started by that sshd session
- `ps -ef` (PID 4635) has PPID 1201 - your shell started the ps command

> **Concept - Parent and Child (PPID):** Every process except PID 1 is started
> by a parent. Its PPID points back to that parent. This forms a family tree.
> Understanding the tree helps you see that a database is not one process. It
> is a parent process with many child processes underneath it.

---

## 4. Filtering with grep

`ps aux` prints hundreds of lines. To find one program, send the output to
`grep` (from Module 01).

```bash
ps aux | grep sshd
```

This runs `ps aux`, then keeps only the lines that contain "sshd".

```
Expected output (yours will differ):
root         799  0.0  0.4  11784  7800 ?        Ss   18:33   0:00 sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups
root        4593  0.0  0.6  17944 11860 ?        Ss   18:35   0:00 sshd-session: ec2-user [priv]
ec2-user    4606  0.0  0.4  18288  7924 ?        S    18:35   0:00 sshd-session: ec2-user@pts/0
ec2-user    4700  0.0  0.0 221668  1080 pts/0    S+   18:35   0:00 grep --color=auto sshd
```

Notice the last line. The `grep` command matched itself. That is normal, and a
little annoying. There is a classic trick to hide it:

```bash
ps aux | grep '[s]shd'
```

The `[s]shd` uses a character class. It still matches the text `sshd`. But the
`grep` process on your command line shows up as `[s]shd`, which does not match
the pattern. So the self-match disappears.

```
Expected output (yours will differ):
root         799  0.0  0.4  11784  7800 ?        Ss   18:33   0:00 sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups
root        4593  0.0  0.6  17944 11860 ?        Ss   18:35   0:00 sshd-session: ec2-user [priv]
ec2-user    4606  0.0  0.4  18288  7924 ?        S    18:35   0:00 sshd-session: ec2-user@pts/0
```

> **DBA Context - Finding the Database:** When PostgreSQL is running, you find
> its processes with `ps aux | grep postgres`. You will see one main postmaster
> process and several helper processes (checkpointer, background writer, WAL
> writer, autovacuum launcher). If `grep postgres` returns nothing, the
> database is not running. That is often your first clue during an incident.

---

## 5. pgrep - Search by name directly

Instead of piping `ps` to `grep`, you can search for a process by name with
`pgrep`. It returns just the PIDs.

```bash
pgrep sshd
```

`pgrep` searches the process list for names matching "sshd". It prints their
PIDs, one per line.

```
Expected output (yours will differ):
799
4593
4606
```

To see the process name next to each PID, add `-a` (or `-l` for just the name):

```bash
pgrep -a sshd
```

The `-a` flag shows the full command line alongside each PID.

```
Expected output (yours will differ):
799 sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups
4593 sshd-session: ec2-user [priv]
4606 sshd-session: ec2-user@pts/0
```

> **DBA Context - pgrep in Scripts:** `pgrep` is cleaner than `ps | grep` when
> you write scripts. It does not match itself, and it returns PIDs that scripts
> can read easily. A health-check script might run `pgrep postgres` and alert
> if it returns nothing.

---

## 6. Sorting ps by CPU and memory

To find the heaviest processes, sort the `ps` output. The `--sort` flag orders
the list by a column.

Sort by CPU, highest first:

```bash
ps aux --sort=-%cpu | head -6
```

- `--sort=-%cpu` - sort by the `%CPU` column; the leading `-` means descending (highest first)
- `| head -6` - show only the header line plus the top 5 processes

```
Expected output (yours will differ):
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  2.1  0.9 108676 16768 ?        Ss   18:33   0:02 /usr/lib/systemd/systemd ...
root         537  0.4  0.5  24592 10116 ?        Ss   18:33   0:00 /usr/lib/systemd/systemd-journald
root          17  0.3  0.0      0     0 ?        S<   18:33   0:00 [pr/ttyS0]
...
```

Sort by memory, highest first:

```bash
ps aux --sort=-%mem | head -6
```

The `--sort=-%mem` sorts by the memory column, highest first. This answers the
question "what is eating my RAM?"

```
Expected output (yours will differ):
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         659  0.0  1.2 260868 20884 ?        Ssl  18:33   0:00 /usr/sbin/NetworkManager --no-daemon
root           1  2.1  0.9 108676 16768 ?        Ss   18:33   0:02 /usr/lib/systemd/systemd ...
ec2-user    4597  0.0  0.8  25044 14828 ?        Ss   18:35   0:00 /usr/lib/systemd/systemd --user
...
```

> **DBA Context - Finding the Culprit:** When a server alarm fires for high CPU
> or high memory, `ps aux --sort=-%cpu | head` and `ps aux --sort=-%mem | head`
> are the fastest way to see which process is to blame. Often it is a single
> runaway database query showing up as one hungry backend process.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what a process, a PID, and a PPID are
- [ ] Run `ps aux` and read the USER, PID, %CPU, %MEM, RSS, and STAT columns
- [ ] Run `ps -ef` and identify the PPID (parent) of a process
- [ ] Explain the difference between RSS and VSZ
- [ ] Filter processes with `ps aux | grep <name>`
- [ ] Use the `[x]` trick to hide grep from its own results
- [ ] Find PIDs by name with `pgrep` and `pgrep -a`
- [ ] Find the top CPU and memory consumers with `ps aux --sort=`
