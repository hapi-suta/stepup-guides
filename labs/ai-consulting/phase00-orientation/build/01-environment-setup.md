# BUILD: Set Up Your Linux Working Environment

**Phase 0, Module 0.2**

Every tier in this curriculum uses the command line, Python, Docker, and PostgreSQL. This guide builds that working environment from scratch on a fresh Linux server, and you will reuse it the whole way through.

**Validated on:** CentOS Stream 9, 2 vCPU / 3.5 GB RAM, on 2026-07-23. Every command below was run on a real server and the output you see is the actual output (truncated where long).

> **A note on your machine.** This guide uses a Linux server (a cloud box or a Linux virtual machine) because that is what you will deploy to for the rest of the curriculum. If you also want desktop tools on your own laptop - **Visual Studio Code**, **Docker Desktop**, **pgAdmin** - install those separately from their official sites. They are graphical apps and are not covered by the server steps below.

Throughout this guide, each command block starts by telling you **which server** and **which user** you are. Follow that exactly.

---

## What you will install

1. git - version control
2. Python 3.12 + pip - the language and its package installer
3. A virtual environment - an isolated space for a project's packages
4. Docker - to run software in containers
5. PostgreSQL - the database used across the curriculum

---

## Step 1: Update the package list and install git

`git` is how you track changes to your work and push it to GitHub.

On your **lab server**, as **ec2-user**:

```bash
sudo dnf install -y git
```

`sudo` runs the command as administrator. `dnf` is the CentOS package manager. `install -y` installs and auto-answers "yes".

Now confirm it installed:

```bash
git --version
```

Expected output (yours will differ):

```
git version 2.52.0
```

---

## Step 2: Install Python 3.12 and pip

CentOS ships with an older Python 3.9. Modern AI work wants 3.12, so install it explicitly.

Still on your **lab server**, as **ec2-user**:

```bash
sudo dnf install -y python3.12 python3.12-pip
```

`python3.12` is the interpreter. `python3.12-pip` is `pip`, the tool that installs Python packages.

Confirm both:

```bash
python3.12 --version
```

```bash
python3.12 -m pip --version
```

Expected output (yours will differ):

```
Python 3.12.13
pip 23.2.1 from /usr/lib/python3.12/site-packages/pip (python 3.12)
```

You may see a notice that a newer pip exists. That is fine to ignore for now.

---

## Step 3: Create and use a virtual environment

A virtual environment keeps one project's packages separate from another's, so they never clash. You make one per project.

On your **lab server**, as **ec2-user**, move to your home directory and create it:

```bash
cd ~
```

```bash
python3.12 -m venv myenv
```

This creates a folder `myenv` holding an isolated Python. Now **activate** it:

```bash
source myenv/bin/activate
```

Your prompt now starts with `(myenv)`. While active, `python` means the environment's Python:

```bash
python --version
```

Expected output (yours will differ):

```
Python 3.12.13
```

Install a package into the environment:

```bash
pip install requests
```

Confirm the package is usable:

```bash
python -c "import requests; print('requests version:', requests.__version__)"
```

Expected output (yours will differ):

```
requests version: 2.34.2
```

When you are done working in the environment, leave it:

```bash
deactivate
```

The `(myenv)` prefix disappears. You are back to the system Python.

---

## Step 4: Install Docker

Docker runs software inside **containers** - self-contained boxes that work the same on any machine.

On your **lab server**, as **ec2-user**, add the Docker repository and install:

```bash
sudo dnf install -y dnf-plugins-core
```

```bash
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
```

```bash
sudo dnf install -y docker-ce docker-ce-cli containerd.io
```

Confirm it installed:

```bash
docker --version
```

Expected output (yours will differ):

```
Docker version 29.6.2, build dfc4efb
```

Now start Docker and set it to launch on boot:

```bash
sudo systemctl enable --now docker
```

Add your user to the `docker` group so you can run Docker without `sudo`:

```bash
sudo usermod -aG docker ec2-user
```

> **Important:** the group change only takes effect after you log out and back in. Log out now (`exit`) and SSH back in before running Docker without `sudo`. Until then, prefix Docker commands with `sudo`.

Confirm Docker is running:

```bash
systemctl is-active docker
```

Expected output:

```
active
```

---

## Step 5: Run your first containers

On your **lab server**, as **ec2-user**, run the Docker test image:

```bash
docker run --rm hello-world
```

`run` starts a container. `--rm` deletes it when it finishes. `hello-world` is a tiny official test image.

Expected output (yours will differ, truncated):

```
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
...
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

Now run Python inside a container:

```bash
docker run --rm python:3.12-slim python -c "print('hello from python container')"
```

Expected output (yours will differ, truncated):

```
Status: Downloaded newer image for python:3.12-slim
hello from python container
```

---

## Step 6: Install PostgreSQL

PostgreSQL is the database you will use across the curriculum.

On your **lab server**, as **ec2-user**, install the server and client:

```bash
sudo dnf install -y postgresql-server postgresql
```

Confirm the client version:

```bash
psql --version
```

Expected output (yours will differ):

```
psql (PostgreSQL) 13.23
```

Initialize the database storage (done once):

```bash
sudo postgresql-setup --initdb
```

Expected output (yours will differ):

```
 * Initializing database in '/var/lib/pgsql/data'
 * Initialized, logs are in /var/lib/pgsql/initdb_postgresql.log
```

Start PostgreSQL and set it to launch on boot:

```bash
sudo systemctl enable --now postgresql
```

Confirm it is running:

```bash
systemctl is-active postgresql
```

Expected output:

```
active
```

---

## Step 7: Create a database user and database

You will connect to PostgreSQL as a normal user, not the admin. First switch to the `postgres` system user.

On your **lab server**, as **ec2-user**, switch user:

```bash
sudo su - postgres
```

Your prompt is now the `postgres` user. Create a login role with a password:

```bash
psql -c "CREATE USER labuser WITH PASSWORD 'labpass';"
```

Expected output:

```
CREATE ROLE
```

Create a database owned by that user:

```bash
psql -c "CREATE DATABASE labdb OWNER labuser;"
```

Expected output:

```
CREATE DATABASE
```

Now return to your `ec2-user`:

```bash
exit
```

---

## Step 8: Allow password login, then connect

By default CentOS PostgreSQL only allows the system-account (`ident`) login, so a password connection over the network is refused. You must switch the local rules to password (`md5`) auth. This is a common first-time gotcha.

On your **lab server**, as **ec2-user**, open the host-based auth file:

```bash
sudo vi /var/lib/pgsql/data/pg_hba.conf
```

Find the two lines near the bottom that read:

```
host    all             all             127.0.0.1/32            ident
host    all             all             ::1/128                 ident
```

Change the word `ident` to `md5` on both lines so they read:

```
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
```

In `vi`: move the cursor onto `ident`, press `cw`, type `md5`, press `Esc`. Repeat for the second line. Save and quit with `:wq` then Enter.

Reload PostgreSQL so it picks up the change:

```bash
sudo systemctl reload postgresql
```

Now connect as `labuser` over the network:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT version();"
```

`-h 127.0.0.1` connects over TCP. `-U labuser` is the user. `-d labdb` is the database. `PGPASSWORD` supplies the password for this one command.

Expected output (yours will differ, truncated):

```
                             version
------------------------------------------------------------------
 PostgreSQL 13.23 on x86_64-redhat-linux-gnu, compiled by gcc ...
(1 row)
```

If you see that version line, your environment is complete: Python, a virtual environment, Docker, and a database you can reach with a password. Everything the rest of the curriculum needs is now in place.

---

## What you just built

- git for version control
- Python 3.12 with pip and an isolated virtual environment
- Docker, proven by running two containers
- PostgreSQL, initialized, running, and reachable as a password user

Next: the USE exercises stand up your study and portfolio system, and you create the `ai-consulting-learning-journey` repository.
