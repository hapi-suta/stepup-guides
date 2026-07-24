# Build 01: Connecting to Your Server

You will learn how to connect to your Linux server using SSH, understand what
you see when you log in, and run your first commands.

**Time estimate:** 45 minutes

---

## Step 0 - What is SSH?

SSH stands for Secure Shell. It is the tool you use to connect to a remote
Linux server over the internet. Think of it like a phone call to your server -
once connected, you type commands and the server runs them. Everything you
send is encrypted, so no one can see your commands or passwords in transit.

As a DBA, you will use SSH every single day. Every time you need to check
database logs, restart a service, or run a backup - you start by connecting
with SSH.

---

## Step 1 - Connecting from Mac or Linux

Open the **Terminal** application on your Mac. You can find it by pressing
`Cmd + Space` and typing "Terminal".

First, you need to set the correct permissions on your SSH key file. The key
file is the `.pem` file from your welcome email.

```bash
chmod 600 ~/Downloads/your-key.pem
```

`chmod 600` sets the file so only you can read and write it. SSH refuses to
use key files that other users can read - this is a security feature.

Now connect to your server. Replace the IP address with the one from your
welcome email:

```bash
ssh -i ~/Downloads/your-key.pem ec2-user@YOUR_SERVER_IP
```

Let's break down each part:

- `ssh` - the command to start a secure connection
- `-i ~/Downloads/your-key.pem` - the `-i` flag means "identity file". This tells SSH which key file to use for authentication instead of a password
- `ec2-user` - the username you are logging in as. On CentOS servers in AWS, this is the default user
- `@YOUR_SERVER_IP` - the `@` separates the username from the server address

The first time you connect, you will see a message like this:

```
Expected output (yours will differ):
The authenticity of host '10.0.1.50 (10.0.1.50)' can't be established.
ED25519 key fingerprint is SHA256:abc123def456...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Type `yes` and press Enter. This message only appears the first time you
connect to a new server. It is SSH confirming you trust this server.

After typing `yes`, you should see something like:

```
Expected output (yours will differ):
Warning: Permanently added '10.0.1.50' (ED25519) to the list of known hosts.
Last login: Sat Apr 19 10:30:00 2026 from 192.168.1.100
[ec2-user@ip-10-0-1-50 ~]$
```

You are now on the server. The blinking cursor is waiting for your commands.

> **Concept - SSH Keys vs Passwords:** SSH keys are more secure than passwords.
> A key pair has two parts: a private key (your `.pem` file - keep this secret)
> and a public key (already installed on the server). When you connect, SSH uses
> math to prove you have the private key without ever sending it over the
> network. This is why you never share your `.pem` file with anyone.

---

## Step 2 - Connecting from Windows (MobaXterm)

Download MobaXterm from [https://mobaxterm.mobatek.net](https://mobaxterm.mobatek.net).
The free "Home Edition" is fine.

1. Open MobaXterm
2. Click **Session** in the top-left corner
3. Click **SSH**
4. Fill in:
   - **Remote host:** your server IP from the welcome email
   - **Specify username:** check this box and type `ec2-user`
5. Click **Advanced SSH settings**
6. Check **Use private key**
7. Click the file icon and browse to your `.pem` key file
8. Click **OK**

You should see the same login prompt as the Mac/Linux section above.

MobaXterm also shows a file browser on the left side - you can drag and drop
files between your computer and the server. This is handy but we will learn
the command-line way first.

> **DBA Context - Why Command Line?** GUIs are convenient, but as a DBA you
> will often work on servers that only have command-line access. Some servers
> are in locked-down networks where you can only connect through a jump host.
> Learning the command line first means you can work on any server, anywhere.

---

## Step 3 - What you see when you connect (the prompt)

After connecting, look at your cursor line:

```
[ec2-user@ip-10-0-1-50 ~]$
```

Every part of this prompt tells you something:

- `ec2-user` - the username you are logged in as
- `@` - separates the username from the hostname
- `ip-10-0-1-50` - the hostname (name) of this server
- `~` - your current directory. The `~` symbol is a shortcut for your home directory (`/home/ec2-user`)
- `$` - means you are a regular user. If you see `#` instead, you are the root (administrator) user

The prompt changes as you move around the server. If you move to the `/etc`
directory, it will show `[ec2-user@ip-10-0-1-50 etc]$`.

> **Concept - Root vs Regular User:** The root user has unlimited power on a
> Linux server - it can delete anything, change anything, and break anything.
> The `ec2-user` account is a regular user. You will use `sudo` (which you will
> learn later) to run commands that need root privileges. This is a safety
> net - you cannot accidentally destroy the server as a regular user.

---

## Step 4 - Your first commands

Now that you are connected, let's run some basic commands. Type each one and
press Enter.

### Who am I?

```bash
whoami
```

This prints the username you are logged in as.

```
Expected output (yours will differ):
ec2-user
```

### What server am I on?

```bash
hostname
```

This prints the name of the server.

```
Expected output (yours will differ):
ip-10-0-1-50
```

### What time is it?

```bash
date
```

This prints the current date and time on the server.

```
Expected output (yours will differ):
Sat Apr 19 14:30:00 UTC 2026
```

Notice the timezone says `UTC`. Most servers are set to UTC (Coordinated
Universal Time) regardless of where they are physically located. This is
standard practice - especially for database servers - because it avoids
confusion when servers are in different time zones.

> **DBA Context - Server Time:** Database servers should always run in UTC.
> When you see a timestamp in a database log, it should be UTC. When you
> compare logs across multiple servers, they should all be in UTC. If a server
> is set to a local timezone, it causes confusion during outages when your
> team is spread across time zones.

### How long has the server been running?

```bash
uptime
```

This shows how long the server has been running since its last reboot, how
many users are logged in, and the system load.

```
Expected output (yours will differ):
 14:30:00 up 3 days, 2:15,  1 user,  load average: 0.00, 0.01, 0.05
```

- `up 3 days, 2:15` - the server has been running for 3 days and 2 hours
- `1 user` - one person is currently logged in (you)
- `load average` - how busy the CPU is (we will cover this in a later module)

---

## Step 5 - Exiting the server

When you are done working, always disconnect cleanly. You have two options:

### Option A - Type exit

```bash
exit
```

This closes your SSH session and returns you to your local terminal.

### Option B - Press Ctrl+D

Hold the `Ctrl` key and press `D`. This sends an "end of file" signal which
closes the session. It does the same thing as typing `exit`.

After disconnecting, you will see your local terminal prompt again (it will
look different from the server prompt).

To reconnect, run the same `ssh` command from Step 1.

> **Concept - Sessions:** Every time you connect with SSH, you start a
> session. When you disconnect, that session ends and any commands still
> running in it will stop. In later modules, you will learn tools like
> `tmux` and `screen` that keep your session alive even after you disconnect.
> This is important for DBAs running long backups or migrations.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Connect to your server using SSH from your computer
- [ ] Read the prompt and identify the username, hostname, and current directory
- [ ] Run `whoami` and confirm it shows `ec2-user`
- [ ] Run `hostname` and see your server name
- [ ] Run `date` and see the current time in UTC
- [ ] Run `uptime` and see how long the server has been running
- [ ] Disconnect from the server using `exit` or `Ctrl+D`
- [ ] Reconnect to the server

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.
