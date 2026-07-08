# Build 03: Signals and kill

Sometimes a process misbehaves. It hangs, runs away with CPU, or refuses to
stop. You will learn how to send signals to processes. A signal can ask a
process to stop politely, or, as a last resort, force it to stop. For a
database, knowing the difference between a polite stop and a forced kill is
critical.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. What is a signal?

A signal is a small message the kernel delivers to a process. It tells the
process that something happened, or asks it to do something. When you press
`Ctrl+C` to stop a command, you are sending a signal. When you use `kill`, you
are sending a signal too.

The two signals a DBA uses most are:

- `SIGTERM` (signal 15) - "please shut down cleanly". The process gets a chance to finish its work, save its data, and exit gracefully. This is the default.
- `SIGKILL` (signal 9) - "stop immediately, no cleanup". The kernel destroys the process on the spot. It cannot be caught or ignored.

> **Concept - Graceful vs Forced:** SIGTERM (15) is a request. The process can
> run its shutdown routine: close files, save buffers, release locks. SIGKILL
> (9) is not a request. The process is killed instantly, with no chance to
> clean up. Always try SIGTERM first. SIGKILL is a last resort because it can
> leave things in a messy, half-finished state.

---

## 2. Set up a practice process

`kill` needs something to kill. Let's start a harmless background process we
can safely stop. The `sleep` command just waits for a number of seconds and
does nothing else.

```bash
sleep 600 &
```

- `sleep 600` - do nothing for 600 seconds (10 minutes)
- `&` - run it in the background so you get your prompt back right away

```
Expected output (yours will differ):
[1] 2450
```

The `[1]` is the job number and `2450` is the PID (yours will differ). Find it
again any time with `pgrep`:

```bash
pgrep -a sleep
```

```
Expected output (yours will differ):
2450 sleep 600
```

Note your PID. The examples below use `2450`, but you must use the number your
server printed.

---

## 3. kill - Send SIGTERM (the polite stop)

By default, `kill` sends SIGTERM (signal 15). This is the graceful "please shut
down" request.

```bash
kill 2450
```

Replace `2450` with your `sleep` PID. This sends SIGTERM to that process.
Nothing prints, but the process is asked to stop.

Confirm it is gone:

```bash
pgrep -a sleep
```

If `pgrep` returns nothing and your prompt returns, the process stopped. You
may also see a job-done message like:

```
Expected output (yours will differ):
[1]+  Terminated              sleep 600
```

> **DBA Context - Stopping a Database:** You almost never `kill` a database by
> PID directly. You use `systemctl stop` (Build 04), which sends the database a
> proper shutdown signal. But under the hood, a clean database stop is a
> SIGTERM. PostgreSQL finishes active transactions, runs a checkpoint, saves
> everything to disk, and exits cleanly. That is exactly why SIGTERM is the
> right default.

---

## 4. kill -9 - Send SIGKILL (the forced stop)

If a process ignores SIGTERM and will not die, you can force it with SIGKILL
(signal 9). Start a fresh practice process first:

```bash
sleep 600 &
```

```
Expected output (yours will differ):
[1] 2510
```

Now force-kill it. You can name the signal three equal ways: `-9`, `-KILL`, or
`-SIGKILL`.

```bash
kill -9 2510
```

Replace `2510` with your PID. The `-9` tells `kill` to send SIGKILL instead of
the default SIGTERM. The process is destroyed right away.

```
Expected output (yours will differ):
[1]+  Killed                  sleep 600
```

Notice the message says `Killed`, not `Terminated`. That difference tells you
whether a process stopped gracefully or was force-killed.

> **DBA Context - Why -9 Is a Last Resort for a Database:** Never make
> `kill -9` your first move on a database process. SIGKILL gives the database
> no chance to save its buffers, finish a checkpoint, or release locks. On
> restart the database must do crash recovery: it replays its write-ahead log
> to get back to a healthy state. That takes time. And if storage is damaged,
> it can put data at risk. Always try `systemctl stop` (SIGTERM) and wait. Only
> reach for `-9` when a process is truly stuck and nothing else works.

---

## 5. See all available signals

To list every signal the system supports, use `kill -l` (lowercase L for
"list").

```bash
kill -l
```

```
Expected output (yours will differ):
 1) SIGHUP       2) SIGINT       3) SIGQUIT      4) SIGILL       5) SIGTRAP
 6) SIGABRT      7) SIGBUS       8) SIGFPE       9) SIGKILL     10) SIGUSR1
11) SIGSEGV     12) SIGUSR2     13) SIGPIPE     14) SIGALRM     15) SIGTERM
...
```

Two more worth knowing:

- `SIGHUP` (1) - "reload your configuration". Many services, including PostgreSQL, re-read their config file when they receive SIGHUP, without a full restart.
- `SIGINT` (2) - "interrupt". This is what `Ctrl+C` sends to a foreground command.

> **DBA Context - SIGHUP to Reload Config:** After you change certain
> PostgreSQL settings, you can apply them with no downtime by sending SIGHUP.
> `pg_ctl reload` and `systemctl reload postgresql` both do this. The database
> re-reads `postgresql.conf` and `pg_hba.conf` while staying up. This is far
> better than a restart when you only changed a reloadable setting.

---

## 6. pkill - Kill by name

Sometimes you do not know the PID, but you know the process name. `pkill` finds
processes by name and signals them. It is like `pgrep`, but it kills instead of
listing.

Start two practice processes:

```bash
sleep 700 &
```

```bash
sleep 800 &
```

```
Expected output (yours will differ):
[1] 2600
[2] 2601
```

Now stop both by name with a single command:

```bash
pkill sleep
```

`pkill` sends SIGTERM (the default) to every process whose name matches
"sleep". Both stop at once.

```
Expected output (yours will differ):
[1]-  Terminated              sleep 700
[2]+  Terminated              sleep 800
```

You can force with `-9` here too, but be careful. `pkill` matches by pattern
and can hit more processes than you meant to.

```bash
pkill -9 sleep
```

> **DBA Context - The Danger of pkill:** `pkill postgres` would signal EVERY
> process with "postgres" in its name: the main server and all backends and
> helpers at once. On a real database server that is almost never what you
> want. And `pkill -9 postgres` could force-kill the whole database with no
> clean shutdown. Prefer `systemctl stop postgresql`. Use `pkill` for your own
> scratch processes, not for managing a running database.

---

## 7. Confirm a signal worked

After sending any signal, always check that the process is actually gone. Do
not assume.

```bash
sleep 900 &
```

```bash
pgrep sleep
```

```
Expected output (yours will differ):
2700
```

```bash
kill 2700
```

Replace `2700` with your PID, then check again:

```bash
pgrep sleep
```

If `pgrep` prints nothing (empty output, prompt returns), the process is gone.
If it still shows a PID, the process ignored SIGTERM. You may need to
investigate or, as a last resort, use `kill -9`.

> **DBA Context - Verify, Then Escalate:** Here is the correct order for a
> stuck process: send SIGTERM, wait a few seconds, then check with `pgrep`.
> Only if it is still there do you consider SIGKILL. Blindly running `kill -9`
> without first trying a clean stop is how DBAs cause avoidable crash recovery
> and, sometimes, data problems.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what a signal is
- [ ] Explain the difference between SIGTERM (15) and SIGKILL (9)
- [ ] Start a background process with `sleep 600 &`
- [ ] Send a graceful stop with `kill <PID>`
- [ ] Force a stop with `kill -9 <PID>` and explain why it is a last resort
- [ ] List all signals with `kill -l`
- [ ] Explain what SIGHUP does and why it matters for reloading DB config
- [ ] Kill processes by name with `pkill` and explain its danger
- [ ] Verify a process actually stopped with `pgrep` before escalating
