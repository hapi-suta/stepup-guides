# Phase 2 (USE) - Knowledge Checklist

Answer each question before moving to Phase 3 (SURVIVE).

---

## Questions

**1. What does the -i flag do when used with SSH?**

<details>
<summary>Answer</summary>

The `-i` flag specifies the identity file (private key) to use for
authentication. Example: `ssh -i ~/my-key.pem ec2-user@10.0.1.50`. Without
it, SSH tries the default keys in `~/.ssh/`.
</details>

---

**2. What is the difference between an absolute path and a relative path?**

<details>
<summary>Answer</summary>

An absolute path starts with `/` and spells out the full location from the
root of the filesystem. Example: `/var/log/messages`.

A relative path does NOT start with `/` and is relative to your current
directory. Example: `log/messages` (only works if you are currently in `/var`).

Absolute paths work from anywhere. Relative paths depend on where you are.
</details>

---

**3. What does mkdir -p do that plain mkdir cannot?**

<details>
<summary>Answer</summary>

`mkdir -p` creates parent directories automatically if they do not exist. For
example, `mkdir -p /opt/pgsql/data/base` creates `/opt`, `/opt/pgsql`,
`/opt/pgsql/data`, and `/opt/pgsql/data/base` all at once. Without `-p`,
`mkdir` fails if any parent directory is missing. The `-p` flag also does not
error if the directory already exists.
</details>

---

**4. What command do you use to watch a log file in real time? How do you stop it?**

<details>
<summary>Answer</summary>

`tail -f /path/to/logfile` follows the file and shows new lines as they are
added. Press `Ctrl+C` to stop watching and return to the command prompt. This
is the primary way DBAs monitor database logs during troubleshooting.
</details>

---

**5. What is the difference between > and >> when redirecting output?**

<details>
<summary>Answer</summary>

`>` overwrites the file. If the file exists, its contents are completely
replaced. If it does not exist, it is created.

`>>` appends to the file. New output is added to the end without erasing
existing contents. If the file does not exist, it is created.

Use `>` when you want a fresh file. Use `>>` when you want to add to an
existing log.
</details>

---

**6. What does grep -c do?**

<details>
<summary>Answer</summary>

`grep -c` counts the number of matching lines instead of printing them. For
example, `grep -c "ERROR" /var/log/messages` returns a number like `42`
instead of showing all 42 matching lines. This is useful for quick counts.
</details>

---

**7. What does the pipe chain `sort | uniq -c | sort -rn` do?**

<details>
<summary>Answer</summary>

This is a three-step frequency analysis:

1. `sort` - sorts lines alphabetically so duplicate lines are next to each other
2. `uniq -c` - collapses consecutive duplicates into one line with a count
3. `sort -rn` - sorts the counts numerically (`-n`) in reverse order (`-r`), putting the most frequent items first

This pattern is the standard way to answer "what are the most common X?"
questions in log analysis.
</details>

---

**8. What does chmod 700 mean? What does each digit represent?**

<details>
<summary>Answer</summary>

`chmod 700` sets permissions to `rwx------`:

- First digit `7` = owner gets `rwx` (4+2+1 = read + write + execute)
- Second digit `0` = group gets `---` (no permissions)
- Third digit `0` = others get `---` (no permissions)

Only the file/directory owner has any access. This is the standard permission
for database data directories.
</details>

---

**9. Why does PostgreSQL refuse to start if the data directory has permission 777?**

<details>
<summary>Answer</summary>

Permission 777 means every user on the server can read and write the database
files. This is a critical security risk - anyone could read sensitive data,
modify tables, or corrupt the database. PostgreSQL checks the data directory
permissions on startup and refuses to start if group or world access is
enabled. The error message is: `FATAL: data directory has group or world
access`.
</details>

---

**10. What is the difference between find and locate?**

<details>
<summary>Answer</summary>

`find` searches the actual filesystem in real time. It is always accurate but
can be slow on large filesystems because it reads every directory.

`locate` searches a pre-built database (index) of filenames. It is very fast
but can show stale results if files were created or deleted after the last
`updatedb` run.

Use `find` when accuracy matters (troubleshooting, finding recent files). Use
`locate` for quick searches of files you know have existed for a while.
</details>

---

**11. How do you search for a word inside a file while viewing it with less?**

<details>
<summary>Answer</summary>

Press `/` (forward slash), type the word you want to find, and press Enter.
`less` highlights the first match and jumps to it. Press `n` to go to the
next match. Press `N` to go to the previous match. Press `q` to quit `less`.
</details>

---

**12. What does 2>/dev/null do at the end of a command?**

<details>
<summary>Answer</summary>

`2>` redirects stderr (standard error, file descriptor 2) and `/dev/null` is
a special file that discards anything written to it. Together, `2>/dev/null`
silences all error messages. This is commonly used with `find` to suppress
"Permission denied" errors when searching directories you do not have access
to.
</details>

---

**13. Name three directories under / and explain what each one stores.**

<details>
<summary>Answer</summary>

- `/etc` - Configuration files for the system and installed services. PostgreSQL config files live here when installed from packages.
- `/var` - Variable data that changes at runtime: logs (`/var/log`), database data (`/var/lib`), temporary files (`/var/tmp`).
- `/opt` - Optional/custom software installations. Many organizations install PostgreSQL here (e.g., `/opt/pgsql`).
- `/home` - User home directories. Each user gets a directory here (e.g., `/home/ec2-user`).
- `/tmp` - Temporary files. Cleaned automatically. Used by database operations for temp tables and sorts.
- `/proc` - Virtual filesystem showing live kernel and process information.

(Any three with correct explanations count.)
</details>

---

**14. What command shows which directories Linux searches when you type a command name?**

<details>
<summary>Answer</summary>

```bash
echo $PATH
```

This prints the PATH environment variable - a colon-separated list of
directories. When you type a command like `grep`, Linux checks each directory
in PATH (left to right) until it finds an executable with that name. If no
match is found, you get "command not found".
</details>

---

## Scoring Guide

| Score | Assessment | Action |
|-------|------------|--------|
| 13-14 | Excellent | Ready for Phase 3 (SURVIVE) |
| 10-12 | Good | Review the topics you missed, then proceed |
| 7-9 | Fair | Redo the BUILD guide for each missed topic |
| Below 7 | Needs work | Redo the entire BUILD phase before continuing |
