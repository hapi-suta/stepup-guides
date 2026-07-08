# Exercise 01 - Filesystem Scavenger Hunt

**Time estimate:** 15-20 minutes
**Prerequisites:** BUILD phase guides 01-04 complete

---

## Objective

Explore your server and answer questions using only commands you learned in
the BUILD phase. Do not look back at the guides - try from memory first.

---

## Questions

**1. What is the full path to your home directory?**

Run a single command that prints it.

<details>
<summary>Answer</summary>

```bash
pwd
```

The answer is `/home/ec2-user`. The `pwd` command prints your current working
directory, and you land in your home directory when you log in.
</details>

---

**2. How many entries (lines) are in the /etc/passwd file?**

<details>
<summary>Answer</summary>

```bash
wc -l /etc/passwd
```

The number will vary by server (typically 25-35). Each line represents one
user account on the system.
</details>

---

**3. What is the hostname of your server?**

Find it TWO different ways.

<details>
<summary>Answer</summary>

Method 1:
```bash
hostname
```

Method 2:
```bash
cat /etc/hostname
```

Both show the same hostname. The `hostname` command reads it from the kernel,
while `/etc/hostname` is the configuration file that sets it at boot.
</details>

---

**4. How many directories are at the top level of the filesystem (directly under /)?**

<details>
<summary>Answer</summary>

```bash
ls -l / | grep "^d" | wc -l
```

Typically around 18-20. The `grep "^d"` filters for lines starting with `d`
(directories). The `wc -l` counts the lines.

Alternative:
```bash
find / -maxdepth 1 -type d | wc -l
```

Note: this includes `/` itself, so subtract 1 from the count.
</details>

---

**5. What shell does the root user use?**

Find the answer inside `/etc/passwd`.

<details>
<summary>Answer</summary>

```bash
grep "^root" /etc/passwd
```

The output shows `root:x:0:0:root:/root:/bin/bash`. The last field
(`/bin/bash`) is the shell. Root uses bash.
</details>

---

**6. What is the IP address of "localhost" according to /etc/hosts?**

<details>
<summary>Answer</summary>

```bash
grep "localhost" /etc/hosts
```

The answer is `127.0.0.1` (IPv4) and `::1` (IPv6). These are loopback
addresses that always point back to the local machine.
</details>

---

**7. How many files and directories are inside /etc/ssh/?**

Give a total count.

<details>
<summary>Answer</summary>

```bash
ls /etc/ssh | wc -l
```

Or for a more detailed breakdown:
```bash
find /etc/ssh -maxdepth 1 | wc -l
```

Subtract 1 from the `find` count because it includes `/etc/ssh` itself.
Typically around 10-12 items.
</details>

---

**8. What are the first 3 lines of /etc/os-release? What operating system is this?**

<details>
<summary>Answer</summary>

```bash
head -3 /etc/os-release
```

You should see something like:
```
NAME="CentOS Stream"
VERSION="9"
ID="centos"
```

This is CentOS Stream 9.
</details>

---

**9. How many users on this system have /bin/bash as their shell?**

<details>
<summary>Answer</summary>

```bash
grep "/bin/bash" /etc/passwd | wc -l
```

Or more directly:
```bash
grep -c "/bin/bash" /etc/passwd
```

Typically 2 (root and ec2-user).
</details>

---

**10. What is the size of /var/log/messages in human-readable format?**

<details>
<summary>Answer</summary>

```bash
sudo ls -lh /var/log/messages
```

The `-lh` flags give long format with human-readable sizes. The size will
vary depending on how long the server has been running.
</details>

---

## Scoring

- **10/10:** Excellent. You have solid command of the basics.
- **7-9/10:** Good. Review the topics you missed.
- **Below 7:** Go back and redo BUILD guides 01-04 before continuing.
