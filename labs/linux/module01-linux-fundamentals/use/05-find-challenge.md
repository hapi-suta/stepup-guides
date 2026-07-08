# Exercise 05 - Find Challenge

**Time estimate:** 15-20 minutes
**Prerequisites:** BUILD phase guide 07 complete

---

## Objective

Use the `find` command (and combine it with other tools) to locate specific
files on the server. Every task represents a real DBA scenario.

---

## Tasks

**1. Find all files named "sshd_config" anywhere under /etc.**

<details>
<summary>Answer</summary>

```bash
find /etc -name "sshd_config" 2>/dev/null
```

Expected:
```
/etc/ssh/sshd_config
```
</details>

---

**2. Count all .conf files under /etc (files only, not directories).**

<details>
<summary>Answer</summary>

```bash
find /etc -name "*.conf" -type f 2>/dev/null | wc -l
```

The `-type f` ensures you only count regular files.
</details>

---

**3. Find all files under /var/log that are larger than 1MB.**

<details>
<summary>Answer</summary>

```bash
sudo find /var/log -size +1M -type f 2>/dev/null
```

The `+1M` means "larger than 1 megabyte".
</details>

---

**4. Find all files under /var/log that were modified in the last 24 hours.**

<details>
<summary>Answer</summary>

```bash
sudo find /var/log -mtime 0 -type f 2>/dev/null
```

The `-mtime 0` means "modified less than 1 day ago" (within the last
24 hours).
</details>

---

**5. Find all empty files under /home/ec2-user.**

<details>
<summary>Hint</summary>

The `find` command has an `-empty` flag.
</details>

<details>
<summary>Answer</summary>

```bash
find /home/ec2-user -empty -type f 2>/dev/null
```

The `-empty` flag matches files with zero bytes.
</details>

---

**6. Find all directories named "log" or "logs" anywhere under /var.**

<details>
<summary>Answer</summary>

```bash
find /var -type d \( -name "log" -o -name "logs" \) 2>/dev/null
```

The `\(` and `\)` group the two name conditions together. The `-o` means
"or". The backslashes prevent the shell from interpreting the parentheses.
</details>

---

**7. Find where the `grep` command binary is located using two different methods.**

<details>
<summary>Answer</summary>

Method 1:
```bash
which grep
```

Method 2:
```bash
find /usr -name "grep" -type f 2>/dev/null
```

Both should show `/usr/bin/grep`.
</details>

---

**8. Find all .conf files under /etc that contain the word "Listen" (case insensitive).**

<details>
<summary>Answer</summary>

```bash
find /etc -name "*.conf" -type f 2>/dev/null | xargs grep -il "Listen" 2>/dev/null
```

The `xargs` takes each filename from `find` and passes it to `grep`.
The `-i` flag makes grep case insensitive. The `-l` flag shows only
filenames (not the matching lines).
</details>

---

**9. Find the 5 largest files on the entire server.**

<details>
<summary>Hint</summary>

You cannot use `find -size` for this because you do not know the threshold.
Instead, use `find` to list all files with their sizes, then sort.
</details>

<details>
<summary>Answer</summary>

```bash
sudo find / -type f -exec ls -s {} \; 2>/dev/null | sort -rn | head -5
```

The `-exec ls -s {} \;` runs `ls -s` (show size in blocks) on each file found.
Then `sort -rn` sorts by size (numeric, reverse). `head -5` shows the top 5.

Alternative (faster):
```bash
sudo find / -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -5
```

The `-printf '%s %p\n'` prints size in bytes followed by the path.
</details>

---

**10. Find all files under /etc/ssh that have permission 600 (owner read+write only).**

<details>
<summary>Answer</summary>

```bash
find /etc/ssh -perm 600 -type f 2>/dev/null
```

The `-perm 600` flag matches files with exactly permission 600. These are
the SSH private key files (they must be 600 for security).

Expected:
```
/etc/ssh/ssh_host_ecdsa_key
/etc/ssh/ssh_host_ed25519_key
/etc/ssh/ssh_host_rsa_key
```
</details>

---

## Scoring

- **10/10:** Outstanding. You can find anything on a Linux server.
- **7-9/10:** Good. Practice the ones you missed.
- **Below 7:** Go back to BUILD guide 07 and review `find` syntax.
