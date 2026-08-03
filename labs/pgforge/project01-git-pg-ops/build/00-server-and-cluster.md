# Build 0: Create the PostgreSQL Server and Cluster (45 min)

Before we version-control configs, we need a real server with a real cluster. This lab builds one: CentOS Stream 9 with PostgreSQL 16 from the PGDG repo. Its postgresql.conf is what the rest of the project manages.

Create a CentOS Stream 9 server your usual way (a t3.small EC2 works - AMI owner 125523088429, SSH user ec2-user). We call it **pgforge-1** in these guides.

All commands tested on a live t3.small on 2026-07-22. Outputs are real captured outputs.

---

## Step 1: Install the PGDG repository

SSH into **pgforge-1**.

```bash
ssh -i ~/.ssh/yourkey.pem ec2-user@YOUR_SERVER_IP
```

On **pgforge-1**, as **ec2-user**:

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

Installs the PostgreSQL community repo file. `-y` answers yes to prompts.

Expected output (last lines, yours will differ):
```
Installed:
  pgdg-redhat-repo-42.0-51PGDG.noarch
Complete!
```

## Step 2: Disable the built-in postgresql module

Still on **pgforge-1**, as **ec2-user**:

```bash
sudo dnf -qy module disable postgresql
```

CentOS ships an older PostgreSQL. This tells dnf to ignore it so version 16 from PGDG wins. `-q` is quiet, `-y` answers yes.

## Step 3: Install PostgreSQL 16

```bash
sudo dnf install -y postgresql16-server
```

Expected output (last lines, yours will differ):
```
  postgresql16-16.11-1PGDG.rhel9.x86_64
  postgresql16-libs-16.11-1PGDG.rhel9.x86_64
  postgresql16-server-16.11-1PGDG.rhel9.x86_64
Complete!
```

## Step 4: Initialize the cluster

```bash
sudo /usr/pgsql-16/bin/postgresql-16-setup initdb
```

Creates the data directory at `/var/lib/pgsql/16/data` - including the real postgresql.conf this whole project is about.

Expected output:
```
Initializing database ... OK
```

## Step 5: Enable and start PostgreSQL

```bash
sudo systemctl enable --now postgresql-16
```

`enable` makes it start on boot. `--now` also starts it right now.

Check it is running:

```bash
sudo systemctl status postgresql-16 --no-pager
```

Expected output (first lines, yours will differ):
```
● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled; preset: disabled)
     Active: active (running) since Wed 2026-07-23 06:32:29 UTC; 1s ago
```

`Active: active (running)` is what you want.

## Step 6: Confirm the cluster works

Switch to the postgres user:

```bash
sudo su - postgres
```

Ask PostgreSQL its version:

```bash
/usr/pgsql-16/bin/psql -c "SELECT version();"
```

Expected output (first lines, yours will differ):
```
                                 version
--------------------------------------------------------------------------
 PostgreSQL 16.11 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.5.0 ...
```

## Step 7: Find the real config file

Still as **postgres** on **pgforge-1**:

```bash
/usr/pgsql-16/bin/psql -c "SHOW config_file;"
```

Expected output:
```
              config_file
----------------------------------------
 /var/lib/pgsql/16/data/postgresql.conf
```

That file is the star of this project.

## Step 8: Note the default shared_buffers

```bash
/usr/pgsql-16/bin/psql -c "SHOW shared_buffers;"
```

Expected output:
```
 shared_buffers
----------------
 128MB
```

Remember this number - you will change it later and watch what reload does and does not do.

Exit back to ec2-user:

```bash
exit
```

The server is ready. Continue to Build 1 (on your Mac).
