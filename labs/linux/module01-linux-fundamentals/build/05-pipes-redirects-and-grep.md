# Build 05: Pipes, Redirects, and Grep

You will learn how to send command output to files, chain commands together,
and search for text. These are the building blocks of everything a DBA does
on the command line.

**Time estimate:** 60 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. stdout, stderr, and stdin

Every command in Linux has three channels for data:

- **stdin** (standard input) - where a command reads its input from. By default, this is your keyboard
- **stdout** (standard output) - where a command sends its normal output. By default, this is your screen
- **stderr** (standard error) - where a command sends error messages. By default, this is also your screen

When you run `ls /etc`, the list of files goes to stdout (your screen). When
you run `ls /nonexistent`, the error message goes to stderr (also your screen).
They look the same on screen, but Linux treats them as separate streams. This
matters because you can redirect each one to a different place.

> **Concept - Three Streams:** Think of stdin, stdout, and stderr as three
> pipes connected to every command. stdin flows IN to the command. stdout flows
> OUT with results. stderr flows OUT with errors. You can redirect any of these
> pipes to a file or to another command. This is one of the most powerful ideas
> in Linux.

---

## 2. > Redirect output to a file (overwrites)

The `>` symbol sends stdout to a file instead of the screen. If the file
already exists, it is completely overwritten.

```bash
ls /etc > ~/practice/logs/etc-listing.txt
```

This runs `ls /etc` but instead of showing the output on screen, it saves it
to the file `etc-listing.txt`. Nothing appears on screen.

Verify the file was created:

```bash
head -5 ~/practice/logs/etc-listing.txt
```

```
Expected output (yours will differ):
adjtime
alternatives
bash_completion.d
bashrc
chrony.conf
```

Now overwrite it:

```bash
echo "This replaces everything" > ~/practice/logs/etc-listing.txt
```

```bash
cat ~/practice/logs/etc-listing.txt
```

```
Expected output (yours will differ):
This replaces everything
```

The original contents are gone. The `>` operator always overwrites.

---

## 3. >> Append to a file

The `>>` symbol adds output to the end of a file without erasing what is
already there.

```bash
echo "First line" > ~/practice/logs/append-test.txt
```

```bash
echo "Second line" >> ~/practice/logs/append-test.txt
```

```bash
echo "Third line" >> ~/practice/logs/append-test.txt
```

```bash
cat ~/practice/logs/append-test.txt
```

```
Expected output (yours will differ):
First line
Second line
Third line
```

The first `echo` used `>` to create the file. The next two used `>>` to add
lines without erasing the first one.

> **DBA Context - Logging with >>:** When you write shell scripts for backups
> or maintenance, you use `>>` to append output to a log file. For example:
> `echo "Backup started at $(date)" >> /var/log/backup.log`. Using `>` instead
> would erase your previous log entries every time the script runs.

---

## 4. 2> Redirect errors

The `2>` symbol sends stderr (error messages) to a file. The `2` refers to
stderr's file descriptor number.

```bash
ls /nonexistent 2> ~/practice/logs/errors.txt
```

No error appears on screen because it was redirected to the file.

```bash
cat ~/practice/logs/errors.txt
```

```
Expected output (yours will differ):
ls: cannot access '/nonexistent': No such file or directory
```

You can redirect stdout and stderr to different files:

```bash
ls /etc /nonexistent > ~/practice/logs/output.txt 2> ~/practice/logs/errors.txt
```

This sends the successful listing of `/etc` to `output.txt` and the error
about `/nonexistent` to `errors.txt`.

To send both stdout and stderr to the same file:

```bash
ls /etc /nonexistent > ~/practice/logs/all-output.txt 2>&1
```

The `2>&1` means "send stderr to the same place as stdout". This is very
common in scripts.

---

## 5. | Pipe - Send output to another command

The pipe symbol `|` takes the output of one command and feeds it as input to
another command. This is the most powerful concept in Linux command-line work.

```bash
ls /etc | head -5
```

This runs `ls /etc`, then sends that output to `head -5`, which shows only
the first 5 lines.

```
Expected output (yours will differ):
adjtime
alternatives
bash_completion.d
bashrc
chrony.conf
```

You can chain multiple pipes:

```bash
ls /etc | sort | head -5
```

This lists `/etc`, sorts the output alphabetically, then shows the first 5
lines. Each `|` connects the output of the left command to the input of the
right command.

```
Expected output (yours will differ):
adjtime
alternatives
bash_completion.d
bashrc
chrony.conf
```

> **DBA Context - Pipe Chains:** DBAs build pipe chains to process data. For
> example: get all database connections, filter for idle ones, count them.
> Each step in the chain does one small job. You will build these kinds of
> chains every day.

---

## 6. grep - Search for text

`grep` is one of the most important commands for a DBA. It searches for a
pattern in files or in piped input.

### Search inside a file

```bash
grep "ec2-user" /etc/passwd
```

This searches the file `/etc/passwd` for lines containing the text "ec2-user".

```
Expected output (yours will differ):
ec2-user:x:1000:1000:Cloud User:/home/ec2-user:/bin/bash
```

### Search with pipes

```bash
ls /etc | grep "ssh"
```

This lists all files in `/etc`, then filters for lines containing "ssh".

```
Expected output (yours will differ):
ssh
```

### The -i flag (case insensitive)

```bash
grep -i "ROOT" /etc/passwd
```

The `-i` flag means "ignore case". It matches `root`, `ROOT`, `Root`, etc.

```
Expected output (yours will differ):
root:x:0:0:root:/root:/bin/bash
operator:x:11:0:operator:/root:/sbin/nologin
```

### The -r flag (recursive - search all files in a directory)

```bash
sudo grep -r "PasswordAuthentication" /etc/ssh/
```

The `-r` flag means "recursive". It searches every file inside `/etc/ssh/`
and its subdirectories. We use `sudo` because some SSH config files are
only readable by root.

```
Expected output (yours will differ):
/etc/ssh/sshd_config:PasswordAuthentication no
/etc/ssh/sshd_config.d/50-redhat.conf:#PasswordAuthentication yes
```

### The -n flag (show line numbers)

```bash
grep -n "bash" /etc/passwd
```

The `-n` flag adds line numbers to the output. This tells you exactly where
each match is in the file.

```
Expected output (yours will differ):
1:root:x:0:0:root:/root:/bin/bash
28:ec2-user:x:1000:1000:Cloud User:/home/ec2-user:/bin/bash
```

### The -c flag (count matches)

```bash
grep -c "nologin" /etc/passwd
```

The `-c` flag counts the number of matching lines instead of showing them.

```
Expected output (yours will differ):
24
```

This means 24 users on the system have `/sbin/nologin` as their shell (they
cannot log in interactively - they are system accounts).

> **DBA Context - grep for Logs:** `grep` is how you search database logs.
> `grep "ERROR" /var/log/postgresql/postgresql.log` finds all error messages.
> `grep -c "ERROR" /var/log/postgresql/postgresql.log` counts them.
> `grep -i "fatal" /var/log/postgresql/postgresql.log` finds fatal errors
> regardless of case. You will use `grep` every single day.

---

## 7. sort - Sort lines

`sort` arranges lines in alphabetical order.

Create a sample file:

```bash
echo -e "banana\napple\ncherry\napple\nbanana\napple" > ~/practice/logs/fruits.txt
```

```bash
cat ~/practice/logs/fruits.txt
```

```
Expected output (yours will differ):
banana
apple
cherry
apple
banana
apple
```

```bash
sort ~/practice/logs/fruits.txt
```

```
Expected output (yours will differ):
apple
apple
apple
banana
banana
cherry
```

The lines are now in alphabetical order. Notice duplicates appear together.

---

## 8. uniq - Remove duplicate lines

`uniq` removes consecutive duplicate lines. The key word is "consecutive" -
the duplicates must be next to each other. This is why you almost always use
`sort` before `uniq`.

```bash
sort ~/practice/logs/fruits.txt | uniq
```

```
Expected output (yours will differ):
apple
banana
cherry
```

### uniq -c (count occurrences)

```bash
sort ~/practice/logs/fruits.txt | uniq -c
```

The `-c` flag counts how many times each unique line appears.

```
Expected output (yours will differ):
      3 apple
      2 banana
      1 cherry
```

This shows `apple` appeared 3 times, `banana` 2 times, and `cherry` once.

To sort by frequency (most common first):

```bash
sort ~/practice/logs/fruits.txt | uniq -c | sort -rn
```

The `sort -rn` at the end sorts numerically (`-n`) in reverse order (`-r`),
so the most frequent items appear first.

```
Expected output (yours will differ):
      3 apple
      2 banana
      1 cherry
```

---

## 9. cut - Extract columns

`cut` extracts specific columns from each line of input. You need to tell it
what character separates the columns (the delimiter).

```bash
cut -d: -f1 /etc/passwd
```

- `-d:` - the delimiter is `:` (colon). Each line in `/etc/passwd` uses colons to separate fields
- `-f1` - extract field 1 (the first column - the username)

```
Expected output (yours will differ):
root
bin
daemon
adm
lp
...
ec2-user
```

Extract multiple fields:

```bash
cut -d: -f1,6 /etc/passwd | head -5
```

This extracts fields 1 (username) and 6 (home directory).

```
Expected output (yours will differ):
root:/root
bin:/bin
daemon:/sbin
adm:/var/adm
lp:/var/spool/lpd
```

---

## 10. Putting it all together - A practical example

Let's combine everything to answer a real question: "Which shells are used
on this server, and how many users use each one?"

This requires several steps chained together:

```bash
cut -d: -f7 /etc/passwd | sort | uniq -c | sort -rn
```

Let's break down each step:

1. `cut -d: -f7 /etc/passwd` - extract field 7 (the shell) from each line
2. `| sort` - sort the shells alphabetically so duplicates are next to each other
3. `| uniq -c` - count how many times each shell appears
4. `| sort -rn` - sort by count, highest first

```
Expected output (yours will differ):
     24 /sbin/nologin
      2 /bin/bash
      1 /bin/sync
      1 /sbin/shutdown
```

This tells you 24 accounts use `/sbin/nologin` (system accounts that cannot
log in), 2 use `/bin/bash` (real users: root and ec2-user), etc.

> **DBA Context - Pipe Chains for Analysis:** This pattern -
> `extract | sort | uniq -c | sort -rn` - is the Swiss Army knife of log
> analysis. Want to find the most common error messages?
> `grep "ERROR" logfile | sort | uniq -c | sort -rn`. Want to find the busiest
> client IPs? Extract the IP column, sort, count, and sort by frequency. You
> will use this pattern constantly.

### Practice - Find errors in system logs

You can search for multiple words at once by separating them with `\|`
(backslash-pipe). This means "or" - match any of these words.

Let's search the system log for warning or error messages:

```bash
sudo grep -i "error\|fail\|warn" /var/log/messages | tail -10
```

- `"error\|fail\|warn"` - match lines containing "error" OR "fail" OR "warn"
- `-i` - ignore case (matches ERROR, Error, error, etc.)
- `| tail -10` - show only the last 10 matches

Count how many such lines exist:

```bash
sudo grep -ic "error\|fail\|warn" /var/log/messages
```

```
Expected output (yours will differ):
42
```

Save the results to a file for later review:

```bash
sudo grep -i "error\|fail\|warn" /var/log/messages > ~/practice/logs/issues.txt
```

```bash
wc -l ~/practice/logs/issues.txt
```

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Redirect stdout to a file with `>` (overwrites)
- [ ] Append stdout to a file with `>>`
- [ ] Redirect stderr with `2>`
- [ ] Pipe output from one command to another with `|`
- [ ] Use `grep` to search for text in a file
- [ ] Use `grep -i` for case-insensitive search
- [ ] Use `grep -r` to search recursively through directories
- [ ] Use `grep -n` to show line numbers
- [ ] Use `grep -c` to count matches
- [ ] Use `sort` to sort lines
- [ ] Use `uniq -c` to count unique lines
- [ ] Use `cut -d: -f1` to extract columns
- [ ] Chain commands with pipes: `grep | sort | uniq -c | sort -rn`
