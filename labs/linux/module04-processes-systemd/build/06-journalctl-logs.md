# Build 06: Reading Service Logs with journalctl

When a service fails or acts up, the answer is almost always in its logs. On a
systemd server, all logs are collected in one place called the journal. You
read them with `journalctl`.

This is where a DBA looks first during an incident. Why did the database stop?
What error came right before the crash? This guide teaches you to read service
logs like an investigator.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

**Note on sudo:** Reading full system logs usually needs extra access, so we
use `sudo` on `journalctl` commands. Run them as **ec2-user** with `sudo` - do
NOT switch to another user.

---

## 1. What is the journal?

Older Linux systems spread their logs across many text files in `/var/log`.
systemd changed this with the journal. The journal is one log store. It is
structured and indexed. It captures output from every service, plus kernel and
boot messages. `journalctl` is the tool that reads it.

The big win: you can ask for exactly the slice you want. One service, a time
window, or only errors. No more grepping through many files.

> **Concept - The Journal:** The journal is systemd's central log store. It
> captures every service's output (stdout and stderr, from Module 01)
> automatically. Each entry is tagged with the service name, timestamp, PID,
> and priority. `journalctl` queries this store. You do not need to know where
> a service writes its logs. The journal already has them.

---

## 2. journalctl -u - Logs for one service

The flag you will use most is `-u` (short for unit). It shows only the log
entries for one named service.

On **your lab server**, as **ec2-user**:

```bash
sudo journalctl -u chronyd
```

`journalctl -u chronyd` shows every journal entry for the `chronyd` service,
oldest first. It opens in a pager (like `less` from Module 01). Use the arrow
keys to scroll and press `q` to quit.

```
Expected output (yours will differ):
Jul 08 18:33:12 localhost systemd[1]: Starting NTP client/server...
Jul 08 18:33:12 localhost chronyd[616]: chronyd version 4.8 starting (+CMDMON +REFCLOCK +RTC ...)
Jul 08 18:33:12 localhost chronyd[616]: Loaded seccomp filter (level 2)
Jul 08 18:33:12 localhost systemd[1]: Started NTP client/server.
Jul 08 18:33:19 ip-172-31-15-28 chronyd[616]: Selected source 169.254.169.123
...
```

Each line shows the timestamp, the hostname, the process name and PID in
brackets, and the message. Press `q` to quit the pager.

> **DBA Context - The First Log You Read:** When the database will not start,
> `sudo journalctl -u postgresql` is where you look. The line right before the
> failure usually names the exact cause. It might be a syntax error in
> `postgresql.conf`, a permission problem on the data directory, or a port
> already in use.

---

## 3. Show only the newest entries

A service's full log can be huge. Two options give you just the recent part.

Show the last 20 lines with `-n`:

```bash
sudo journalctl -u chronyd -n 20
```

The `-n 20` flag limits output to the last 20 entries (newest at the bottom).
This does not open the pager. It prints and returns to your prompt.

```
Expected output (yours will differ):
Jul 08 18:35:43 ip-172-31-15-28 systemd[1]: Starting NTP client/server...
Jul 08 18:35:43 ip-172-31-15-28 chronyd[4770]: chronyd version 4.8 starting (+CMDMON +REFCLOCK ...)
Jul 08 18:35:43 ip-172-31-15-28 chronyd[4770]: Frequency -8.206 +/- 1.155 ppm read from /var/lib/chrony/drift
Jul 08 18:35:43 ip-172-31-15-28 chronyd[4770]: Loaded seccomp filter (level 2)
...
```

Reverse the order so the newest is on top with `-r`:

```bash
sudo journalctl -u chronyd -n 20 -r
```

The `-r` flag reverses the order - most recent first. This is handy when you
only care about what just happened.

> **DBA Context - Newest First:** During an active incident you want the latest
> events right away. `journalctl -u postgresql -n 50 -r` puts the freshest 50
> lines on top. You see the current failure without scrolling.

---

## 4. journalctl -f - Follow the log live

The `-f` flag (short for follow) streams new log lines as they are written,
like a live feed. This is the systemd version of `tail -f` from Module 01.

```bash
sudo journalctl -u chronyd -f
```

The `-f` flag prints the recent lines, then waits and shows new entries as they
arrive. It does not return to your prompt. It keeps running. Press `Ctrl+C` to
stop following.

```
Expected output (yours will differ):
Jul 08 18:35:48 ip-172-31-15-28 chronyd[4780]: Selected source 169.254.169.123
-- (waiting for new entries; press Ctrl+C to stop) --
```

To see it in action, open a second SSH session (or a new terminal). Then
restart the service while `-f` is running in the first:

```bash
sudo systemctl restart chronyd
```

Watch the following window. You will see the stop and start log lines appear
live. Then press `Ctrl+C` in the following window to stop.

> **DBA Context - Watching During a Restart:** Here is a powerful
> troubleshooting move. Run `sudo journalctl -u postgresql -f` in one window,
> then restart the database in another. You watch the startup unfold line by
> line. You catch the exact moment and reason it fails, in real time.

---

## 5. --since - Filter by time

You can ask the journal for a specific time window with `--since` (and its
partner `--until`). This beats scrolling.

```bash
sudo journalctl -u chronyd --since "10 minutes ago"
```

`--since` accepts friendly time phrases. Everything before that time is
skipped.

```
Expected output (yours will differ):
Jul 08 18:33:12 localhost systemd[1]: Starting NTP client/server...
Jul 08 18:33:12 localhost chronyd[616]: chronyd version 4.8 starting (+CMDMON +REFCLOCK ...)
...
```

`--since` also accepts exact dates and times. You can bracket a window with
`--until`:

```bash
sudo journalctl -u chronyd --since "2026-07-08 10:00:00" --until "2026-07-08 11:00:00"
```

This shows only entries between those two timestamps. `--since "today"` and
`--since "yesterday"` also work.

> **DBA Context - Scoping to the Incident:** Say you get a ticket: "the
> database had errors around 2 AM". You go straight to it:
> `sudo journalctl -u postgresql --since "02:00" --until "02:30"`. No wading
> through hours of noise. You read exactly the window that matters.

---

## 6. -p err - Filter by priority (show only errors)

Every journal entry has a priority level. They run from `emerg` (most severe)
down to `debug`. The `-p` flag filters by priority. `-p err` shows only entries
at error level and worse.

```bash
sudo journalctl -u chronyd -p err
```

`-p err` shows only error, critical, alert, and emergency entries. It hides the
routine chatter. On a healthy service this may return nothing, which is a good
sign.

```
Expected output (yours will differ):
-- No entries --
```

The priority names, from least to most severe, are: `debug`, `info`, `notice`,
`warning`, `err`, `crit`, `alert`, `emerg`. Asking for a level includes that
level and everything more severe.

You can combine filters. To see errors across the whole system in the last
hour:

```bash
sudo journalctl -p err --since "1 hour ago"
```

This drops the `-u` so it covers all services. It keeps `-p err` for errors
only, and `--since` for the last hour. This is a fast "what has gone wrong
recently?" sweep of the entire server.

> **DBA Context - Cutting Straight to Errors:** During an incident you do not
> want every log line. You want the failures. `sudo journalctl -u postgresql
> -p err --since today` filters a noisy database log down to just the error and
> fatal entries from today. The real problem jumps out at you.

---

## 7. Putting it together - an incident workflow

Now combine what you learned into the routine a DBA runs when a service is
reported down. Practice it on `chronyd`:

Step 1 - is it even running?

```bash
systemctl status chronyd
```

Step 2 - what does the recent log say, newest first?

```bash
sudo journalctl -u chronyd -n 30 -r
```

Step 3 - narrow to just errors in the recent window:

```bash
sudo journalctl -u chronyd -p err --since "1 hour ago"
```

Step 4 - if you are restarting it, watch the startup live:

```bash
sudo journalctl -u chronyd -f
```

Then, in another window, run `sudo systemctl restart chronyd` and watch the
lines appear. Press `Ctrl+C` to stop following.

> **DBA Context - The Muscle Memory:** Swap `chronyd` for `postgresql` and this
> is the exact sequence you run in a real database outage. Status to confirm it
> is down. `-n -r` to read the latest. `-p err` to isolate the failure. And
> `-f` to watch the fix take hold. Practice it now on a safe service so it is
> automatic when it counts.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what the systemd journal is and how it differs from scattered log files
- [ ] Read one service's logs with `journalctl -u <service>`
- [ ] Quit the journal pager with `q`
- [ ] Limit output with `-n` and reverse it with `-r`
- [ ] Follow a log live with `-f` and stop with `Ctrl+C`
- [ ] Filter by time with `--since` and `--until`
- [ ] Filter to errors only with `-p err` and name the priority levels
- [ ] Run the full incident workflow: status, recent logs, errors, follow
