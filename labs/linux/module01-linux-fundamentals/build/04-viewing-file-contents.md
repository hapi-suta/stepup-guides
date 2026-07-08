# Build 04: Viewing File Contents

You will learn five different ways to look at file contents. Each tool is
suited for different situations - small files, large files, and live logs.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. cat - View an entire file

`cat` stands for "concatenate" but it is most commonly used to display the
entire contents of a file on screen.

```bash
cat /etc/hostname
```

```
Expected output (yours will differ):
ip-10-0-1-50
```

This file is tiny (one line), so `cat` is perfect for it.

Try a slightly larger file:

```bash
cat /etc/passwd
```

```
Expected output (yours will differ):
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/bin:/sbin/nologin
daemon:x:2:2:daemon:/sbin:/sbin/nologin
adm:x:3:4:adm:/var/adm:/sbin/nologin
...
ec2-user:x:1000:1000:Cloud User:/home/ec2-user:/bin/bash
```

The `/etc/passwd` file contains one line per user on the system. Each line has
fields separated by colons (`:`): username, password placeholder, user ID,
group ID, description, home directory, and shell.

### When NOT to use cat

Do not use `cat` on large files. If a file has thousands of lines, `cat` dumps
them all to your screen at once and you cannot read them. For large files, use
`less` (covered next).

> **Concept - /etc/passwd:** Despite the name, this file does not contain
> actual passwords. The `x` in the second field means the password is stored
> in `/etc/shadow` (a protected file). Every user on the system has an entry
> here - including system users like `root`, `bin`, and `daemon` that run
> background services.

---

## 2. less - Page through large files

`less` lets you scroll through a file one screen at a time. It is the best
tool for reading files that are too long to fit on one screen.

```bash
less /etc/passwd
```

You are now inside the `less` viewer. The file content fills your screen and
you can navigate with these keys:

| Key | Action |
|-----|--------|
| `Space` | Move forward one screen |
| `b` | Move backward one screen |
| `Enter` | Move forward one line |
| `q` | Quit and return to the command line |
| `/` then type a word | Search forward for that word |
| `n` | Jump to the next search match |
| `N` | Jump to the previous search match |
| `g` | Jump to the beginning of the file |
| `G` | Jump to the end of the file |

Try it now:

1. Press `Space` to scroll down
2. Press `b` to scroll back up
3. Press `/` then type `ec2-user` and press Enter - this searches for your username
4. Press `q` to quit

Let's try it on a bigger file:

```bash
sudo less /var/log/messages
```

We use `sudo` here because `/var/log/messages` is only readable by root.

This file is the main system log. It can be thousands of lines long. Use
`Space` to scroll through it, then press `q` to quit.

> **DBA Context - less for Logs:** You will use `less` constantly to read
> database log files. PostgreSQL's log can grow to gigabytes. Opening it with
> `cat` would flood your terminal. With `less`, you can search for specific
> error messages using `/` and jump around the file efficiently. Learn the `less`
> keyboard shortcuts well - they will save you time every day.

---

## 3. head - First N lines of a file

`head` shows the beginning of a file. By default, it shows the first 10 lines.

```bash
head /etc/passwd
```

```
Expected output (yours will differ):
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/bin:/sbin/nologin
daemon:x:2:2:daemon:/sbin:/sbin/nologin
adm:x:3:4:adm:/var/adm:/sbin/nologin
lp:x:4:7:lp:/var/spool/lpd:/sbin/nologin
sync:x:5:0:sync:/sbin:/bin/sync
shutdown:x:6:0:shutdown:/sbin:/sbin/shutdown
halt:x:7:0:halt:/sbin:/sbin/halt
mail:x:8:12:mail:/var/spool/mail:/sbin/nologin
operator:x:11:0:operator:/root:/sbin/nologin
```

### The -n flag (specify number of lines)

To see a specific number of lines:

```bash
head -n 3 /etc/passwd
```

The `-n 3` flag means "show the first 3 lines".

```
Expected output (yours will differ):
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/bin:/sbin/nologin
daemon:x:2:2:daemon:/sbin:/sbin/nologin
```

You can also write this as:

```bash
head -3 /etc/passwd
```

Both `-n 3` and `-3` do the same thing.

---

## 4. tail - Last N lines of a file

`tail` shows the end of a file. By default, it shows the last 10 lines.

```bash
tail /etc/passwd
```

```
Expected output (yours will differ):
systemd-oom:x:977:977:systemd Userspace OOM Killer:/:/usr/sbin/nologin
dbus:x:81:81:System message bus:/:/sbin/nologin
polkitd:x:998:997:User for polkitd:/:/sbin/nologin
tss:x:59:59:Account used for TPM access:/dev/null:/sbin/nologin
sssd:x:976:976:User for sssd:/:/sbin/nologin
...
ec2-user:x:1000:1000:Cloud User:/home/ec2-user:/bin/bash
```

### The -n flag (specify number of lines)

```bash
tail -n 3 /etc/passwd
```

The `-n 3` flag means "show the last 3 lines".

```
Expected output (yours will differ):
sssd:x:976:976:User for sssd:/:/sbin/nologin
chrony:x:975:975::/var/lib/chrony:/sbin/nologin
ec2-user:x:1000:1000:Cloud User:/home/ec2-user:/bin/bash
```

### The -f flag (follow - watch a file in real time)

This is the most important `tail` flag for DBAs:

```bash
sudo tail -f /var/log/messages
```

The `-f` flag means "follow". Instead of showing the last 10 lines and
exiting, `tail -f` keeps running and shows new lines as they are added to the
file in real time.

You will see the last 10 lines appear, then the cursor sits and waits. Any
new log entries will appear instantly.

To stop watching, press `Ctrl+C`. Do that now.

> **DBA Context - tail -f:** This is how you watch database logs in real time.
> When troubleshooting a problem, you open one terminal with
> `tail -f /var/log/postgresql/postgresql.log` and use another terminal to run
> commands. You can see exactly what the database is doing as it happens. You
> will use `tail -f` nearly every day as a DBA.

---

## 5. wc - Count lines, words, and bytes

`wc` stands for "word count". It counts lines, words, and bytes in a file.

```bash
wc /etc/passwd
```

```
Expected output (yours will differ):
  28   42  1407 /etc/passwd
```

The three numbers are:

- `28` - number of lines
- `42` - number of words
- `1407` - number of bytes (characters)

### The -l flag (count lines only)

The `-l` flag is the one you will use most:

```bash
wc -l /etc/passwd
```

The `-l` flag means "lines only". This tells you how many users are defined
on the system.

```
Expected output (yours will differ):
28 /etc/passwd
```

This means there are 28 lines (28 user entries) in the passwd file.

Try it on the hosts file:

```bash
wc -l /etc/hosts
```

```
Expected output (yours will differ):
2 /etc/hosts
```

> **DBA Context - wc -l:** You will use `wc -l` to count things constantly.
> How many connections are open? Pipe the query output through `wc -l`. How
> many errors in the log today? Grep for errors and pipe through `wc -l`.
> How many lines in a SQL dump file? `wc -l dump.sql`. It is a simple but
> powerful tool.

---

## 6. Practice with real files

Let's practice these commands on real system files.

### Look at the hosts file

```bash
cat /etc/hosts
```

```
Expected output (yours will differ):
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
```

This file maps hostnames to IP addresses. When the system needs to resolve
a hostname, it checks this file first before going to DNS.

### View the beginning and end of the system log

```bash
sudo head -5 /var/log/messages
```

This shows the oldest entries (first 5 lines) in the system log.

```bash
sudo tail -5 /var/log/messages
```

This shows the newest entries (last 5 lines) in the system log.

### Count lines in the system log

```bash
sudo wc -l /var/log/messages
```

```
Expected output (yours will differ):
1847 /var/log/messages
```

This tells you how many log entries the system has recorded.

### Create a practice file and view it

Let's create a file with some content using a redirect (you will learn more
about redirects in Build 05):

```bash
echo "Line 1: This is a practice file" > ~/practice/logs/test.log
```

```bash
echo "Line 2: Created for viewing practice" >> ~/practice/logs/test.log
```

```bash
echo "Line 3: Learning head and tail" >> ~/practice/logs/test.log
```

```bash
echo "Line 4: This is the last line" >> ~/practice/logs/test.log
```

Now view it different ways:

```bash
cat ~/practice/logs/test.log
```

```
Expected output (yours will differ):
Line 1: This is a practice file
Line 2: Created for viewing practice
Line 3: Learning head and tail
Line 4: This is the last line
```

```bash
head -2 ~/practice/logs/test.log
```

```
Expected output (yours will differ):
Line 1: This is a practice file
Line 2: Created for viewing practice
```

```bash
tail -2 ~/practice/logs/test.log
```

```
Expected output (yours will differ):
Line 3: Learning head and tail
Line 4: This is the last line
```

```bash
wc -l ~/practice/logs/test.log
```

```
Expected output (yours will differ):
4 /home/ec2-user/practice/logs/test.log
```

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Use `cat` to view a small file
- [ ] Use `less` to page through a large file and search with `/`
- [ ] Quit `less` by pressing `q`
- [ ] Use `head -n 5` to see the first 5 lines of a file
- [ ] Use `tail -n 5` to see the last 5 lines of a file
- [ ] Use `tail -f` to watch a file in real time (and `Ctrl+C` to stop)
- [ ] Use `wc -l` to count lines in a file
- [ ] Know when to use each tool: `cat` for small files, `less` for large files, `head`/`tail` for quick peeks
