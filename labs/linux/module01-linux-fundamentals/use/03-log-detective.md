# Exercise 03 - Log Detective

**Time estimate:** 20 minutes
**Prerequisites:** BUILD phase guides 04 and 05 complete

---

## Objective

Use grep, tail, head, pipes, and other tools to find information in system
log files. This is exactly what you will do when troubleshooting database
issues.

---

## Setup

All exercises use `/var/log/messages`, which requires `sudo` to read.

Verify you can access it:

```bash
sudo tail -3 /var/log/messages
```

If you see log entries, you are ready to proceed.

---

## Tasks

**1. How many total lines are in /var/log/messages?**

<details>
<summary>Answer</summary>

```bash
sudo wc -l /var/log/messages
```
</details>

---

**2. Show the first 5 log entries (the oldest ones in the file).**

<details>
<summary>Answer</summary>

```bash
sudo head -5 /var/log/messages
```
</details>

---

**3. Show the last 10 log entries (the most recent ones).**

<details>
<summary>Answer</summary>

```bash
sudo tail -10 /var/log/messages
```
</details>

---

**4. Count how many log entries mention "systemd" (case insensitive).**

<details>
<summary>Answer</summary>

```bash
sudo grep -ic "systemd" /var/log/messages
```

The `-i` flag makes it case insensitive. The `-c` flag counts matches
instead of printing them.
</details>

---

**5. Find all log entries that contain the word "error" (case insensitive) and save them to ~/practice/logs/errors.txt.**

<details>
<summary>Answer</summary>

```bash
sudo grep -i "error" /var/log/messages > ~/practice/logs/errors.txt
```

Verify:
```bash
wc -l ~/practice/logs/errors.txt
```
</details>

---

**6. What are the 5 most common "programs" in the log?**

Log entries in `/var/log/messages` follow this format:
```
Apr 19 14:00:01 hostname program[pid]: message
```

The program name is the 5th field.

<details>
<summary>Hint</summary>

Use `cut` or `awk` to extract the 5th field, then sort and count.
</details>

<details>
<summary>Answer</summary>

```bash
sudo cat /var/log/messages | cut -d' ' -f5 | cut -d'[' -f1 | cut -d':' -f1 | sort | uniq -c | sort -rn | head -5
```

This extracts the program name (5th field, then strips the PID and colon),
sorts, counts occurrences, and shows the top 5.

The exact output varies, but you should see programs like `systemd`,
`dnf`, `sshd`, `chronyd`, etc.
</details>

---

**7. Find log entries from today only.**

<details>
<summary>Hint</summary>

Today's date appears at the start of each log entry. Use `grep` with the
month and day.
</details>

<details>
<summary>Answer</summary>

```bash
sudo grep "$(date '+%b %e')" /var/log/messages | head -10
```

`date '+%b %e'` outputs the current month abbreviation and day (like
"Apr 19"). This filters for only today's entries.

Alternative if the space-padded day does not match:
```bash
sudo grep "$(date '+%b %d')" /var/log/messages | head -10
```
</details>

---

**8. Find all SSH-related log entries and count them.**

<details>
<summary>Answer</summary>

```bash
sudo grep -ic "sshd" /var/log/messages
```

Or to see the entries:
```bash
sudo grep -i "sshd" /var/log/messages | tail -10
```
</details>

---

**9. Find entries that contain both "session" AND "opened" on the same line.**

<details>
<summary>Answer</summary>

```bash
sudo grep "session" /var/log/messages | grep "opened"
```

Chaining two `grep` commands with a pipe: the first grep finds lines with
"session", then the second grep filters those for lines also containing
"opened".
</details>

---

**10. Create a summary report: save the count of entries per program to ~/practice/logs/summary.txt.**

<details>
<summary>Answer</summary>

```bash
sudo cat /var/log/messages | cut -d' ' -f5 | cut -d'[' -f1 | cut -d':' -f1 | sort | uniq -c | sort -rn > ~/practice/logs/summary.txt
```

Verify:
```bash
head -10 ~/practice/logs/summary.txt
```
</details>

---

## Scoring

- **10/10:** Excellent log analysis skills. You are ready for real database logs.
- **7-9/10:** Good. Review pipes and grep flags.
- **Below 7:** Go back to BUILD guides 04 and 05 before continuing.
