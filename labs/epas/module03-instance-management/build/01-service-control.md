# BUILD 01 - Controlling the EPAS Service

The EPAS database runs as a systemd service called `edb-as-16`. Everything you do
to start, stop, or reload the database goes through this one service. In this guide
you will drive it end to end.

You run every command in this guide on **epas-single**, as the **ec2-user** login.
`systemctl` needs root, so each command uses `sudo` - you do **not** switch to the
`enterprisedb` user for service control.

## 1. Check the current status

First, see what the service is doing right now.

On **epas-single**, as **ec2-user**:

```bash
sudo systemctl status edb-as-16
```

- `systemctl status` asks systemd for the live state of one service.
- `edb-as-16` is the EPAS 16 service unit (EDB names it by major version, so on a
  15 server it would be `edb-as-15`).

Expected output (yours will differ):

```
● edb-as-16.service - EDB Postgres Advanced Server 16
     Loaded: loaded (/usr/lib/systemd/system/edb-as-16.service; enabled; preset: disabled)
     Active: active (running) since Tue 2026-08-04 14:51:42 UTC; 20min ago
    Process: 9752 ExecStartPre=/usr/edb/as16/bin/edb-as-16-check-db-dir ${PGDATA} (code=exited, status=0/SUCCESS)
   Main PID: 9766 (edb-postgres)
     CGroup: /system.slice/edb-as-16.service
             ├─9766 /usr/edb/as16/bin/edb-postgres -D /var/lib/edb/as16/data
             ├─9789 "postgres: logger "
             ├─9803 "postgres: checkpointer "
             ...
```

Read the two lines that matter:

- **`Active: active (running)`** - the instance is up. If it said `inactive (dead)`
  or `failed`, the database would be down.
- **`Main PID: 9766 (edb-postgres)`** - the postmaster process. `-D
  /var/lib/edb/as16/data` is its data directory (`PGDATA`) - the home of this
  cluster.

Press **q** to exit the status view and return to your prompt.

## 2. Stop the service

On **epas-single**, as **ec2-user**:

```bash
sudo systemctl stop edb-as-16
```

- `stop` shuts the database down cleanly (a "fast" shutdown - it disconnects
  clients and flushes to disk).
- On success it prints **nothing** and returns you to the prompt. Silence is good.

Confirm it is really down:

```bash
sudo systemctl is-active edb-as-16
```

- `is-active` prints one word - the state - instead of the full block.

Expected output (yours will differ):

```
inactive
```

## 3. Start the service

Bring it back up.

On **epas-single**, as **ec2-user**:

```bash
sudo systemctl start edb-as-16
```

- `start` boots the instance. Like `stop`, it prints nothing on success.

Confirm it is up:

```bash
sudo systemctl is-active edb-as-16
```

Expected output (yours will differ):

```
active
```

## 4. Restart vs reload - the distinction that matters

There are two ways to make the server pick up changes, and using the wrong one is
one of the most common EPAS mistakes.

**Restart** stops and starts the instance - it drops every connection. You need it
for parameters that can only change at startup (you will see which ones in BUILD
03).

On **epas-single**, as **ec2-user**:

```bash
sudo systemctl restart edb-as-16
```

- No output on success. Every client is disconnected and reconnects fresh.

**Reload** tells the running server to re-read its config files **without** dropping
connections (it sends the postmaster a SIGHUP). Use it whenever the change allows
it - production stays online.

On **epas-single**, as **ec2-user**:

```bash
sudo systemctl reload edb-as-16
```

- No output on success. Connected sessions keep working.

> **Oracle bridge:** a reload is like `ALTER SYSTEM ... SCOPE=BOTH` for a dynamic
> parameter - it takes effect live. A restart is like bouncing the instance for a
> static parameter you changed in the `spfile`.

## 5. Make sure it starts on boot

If the server reboots, you want the database to come back on its own.

On **epas-single**, as **ec2-user**:

```bash
sudo systemctl is-enabled edb-as-16
```

- `is-enabled` tells you whether systemd will start this service at boot.

Expected output (yours will differ):

```
enabled
```

If it ever prints `disabled`, turn it on with:

```bash
sudo systemctl enable edb-as-16
```

## Checkpoint

You can now:

- [x] Read the service status and spot `active (running)` and the data directory
- [x] Stop and start the instance and verify each with `is-active`
- [x] Explain when to reload versus restart
- [x] Confirm the service is enabled for boot

Next: **BUILD 02 - Connecting with edb-psql and edbplus.**
