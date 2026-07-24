# Build 02: Ports and Listening Sockets

You will learn what a port is. You will see which programs are listening for
network connections. You will confirm that PostgreSQL is actually accepting
connections on port 5432. This is the check a DBA runs most often when an app
reports it cannot connect.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. What is a port?

An IP address gets data to the right server. A port gets it to the right program
on that server. Think of the IP address as the street address of an apartment
building. The port is the apartment number.

Some ports are well known by convention:

- `22` - SSH (how you connected to this server)
- `80` - HTTP (web)
- `443` - HTTPS (secure web)
- `5432` - PostgreSQL

When someone says "PostgreSQL listens on 5432", they mean the PostgreSQL process
is waiting for connections that arrive on port 5432.

> **Concept - A Socket:** A listening program binds to an address and a port
> together. That pair - address plus port - is called a socket. `0.0.0.0:5432`
> means "port 5432 on every address this server has". `127.0.0.1:5432` means
> "port 5432, but only on the loopback". This difference decides whether remote
> clients can connect at all. Pay close attention to it.

---

## 2. ss - See what is listening

`ss` (socket statistics) is the modern tool for looking at network sockets. It
replaced the older `netstat`.

```bash
ss -tulpn
```

Each letter is a flag doing one job:

- `-t` - show TCP sockets (most services, including PostgreSQL, use TCP)
- `-u` - show UDP sockets (used by things like DNS)
- `-l` - show only listening sockets (programs waiting for connections)
- `-p` - show the process (program name and PID) that owns each socket
- `-n` - show numbers, not names (show `5432` instead of resolving it to a name)

You will need `sudo` to see the process names for services you do not own:

```bash
sudo ss -tulpn
```

```
Expected output (yours will differ):
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
udp   UNCONN 0      0          127.0.0.1:323       0.0.0.0:*     users:(("chronyd",pid=620,fd=5))
udp   UNCONN 0      0              [::1]:323          [::]:*     users:(("chronyd",pid=620,fd=6))
tcp   LISTEN 0      128          0.0.0.0:22        0.0.0.0:*     users:(("sshd",pid=801,fd=7))
tcp   LISTEN 0      128             [::]:22           [::]:*     users:(("sshd",pid=801,fd=8))
```

Read it column by column:

- `State LISTEN` - this socket is waiting for incoming connections
- `Local Address:Port` - the socket the program is bound to
- `Process` - which program owns it

In the output above, `sshd` listens on `0.0.0.0:22` (SSH on every address) and
`chronyd` (the time service) listens on `127.0.0.1:323`. PostgreSQL is not
installed yet at this stage, so you will not see a `5432` line. Once PostgreSQL
is running, you would see a line like this added to the list:

```
tcp   LISTEN 0      244        127.0.0.1:5432       0.0.0.0:*     users:(("postgres",pid=1450,fd=6))
```

That line means `postgres` listens on `127.0.0.1:5432` (PostgreSQL, but only on
the loopback).

---

## 3. Is PostgreSQL listening? Filter with grep

To answer the exact question "is PostgreSQL listening on 5432", pipe the output
through `grep`:

```bash
sudo ss -tulpn | grep 5432
```

This runs `ss` and keeps only the lines containing `5432`.

Because PostgreSQL is not installed yet at this stage, this returns nothing (an
empty result). Once PostgreSQL is running, the same command returns a line like
this:

```
Expected output (once PostgreSQL is running, yours will differ):
tcp    LISTEN  0  244  127.0.0.1:5432  0.0.0.0:*  users:(("postgres",pid=1450,fd=6))
```

If you get a line back, PostgreSQL is listening. If you get nothing back, either
PostgreSQL is not running or it is not configured to listen on that port.

> **DBA Context - The First Check:** When an app team says "we cannot connect to
> the database", run this first on the database server:
> `sudo ss -tulpn | grep 5432`. If nothing comes back, the problem is on the
> database side. The service is down or misconfigured. If it comes back but only
> on `127.0.0.1`, remote clients are being ignored. This one command narrows the
> whole investigation.

---

## 4. 127.0.0.1 vs 0.0.0.0 - Why remote clients cannot connect

This is the most important idea in this guide.

- `127.0.0.1:5432` - PostgreSQL listens only on the loopback. Only programs on
  the **same server** can connect. A client on another machine gets
  "connection refused"
- `0.0.0.0:5432` - PostgreSQL listens on **all addresses**. Clients from other
  machines can connect (assuming the firewall allows it)

In PostgreSQL, the `listen_addresses` setting in `postgresql.conf` controls this.
The default is `localhost`, which gives the `127.0.0.1` binding. To accept remote
connections, a DBA sets `listen_addresses = '*'` and reloads PostgreSQL. That
changes the binding to `0.0.0.0`.

You can see the current setting without changing anything:

```bash
sudo grep -n "listen_addresses" /var/lib/pgsql/data/postgresql.conf
```

- `-n` - show the line number
- The path is the default PostgreSQL data directory on CentOS

```
Expected output (yours will differ):
59:#listen_addresses = 'localhost'		# what IP address(es) to listen on;
```

A leading `#` means the line is commented out, so PostgreSQL uses the default of
`localhost`. That is why the socket showed `127.0.0.1` above.

> **DBA Context - The Classic Trap:** A new DBA opens the firewall, tests from a
> client, and still gets "connection refused". The reason is almost always this:
> `listen_addresses` is still `localhost`. So PostgreSQL never listens on an
> address the client can reach. Opening the firewall does nothing if the program
> is not bound to a reachable address. Always check both the socket binding
> (`ss`) and the firewall (next guide).

---

## 5. LISTEN vs ESTABLISHED - Two kinds of connections

The `State` column tells you what a socket is doing.

- **LISTEN** - a program is waiting for new connections (a server accepting work)
- **ESTABLISHED** - an active, connected session (a client and server talking)

Drop the `-l` flag to see established connections too:

```bash
sudo ss -tupn
```

Without `-l`, `ss` shows all sockets, not just the listeners. Here you will see
live connections.

```
Expected output (yours will differ):
Netid State Recv-Q Send-Q   Local Address:Port   Peer Address:Port Process
udp   ESTAB 0      0      172.31.6.0%eth0:68       172.31.0.1:67    users:(("NetworkManager",pid=659,fd=26))
tcp   ESTAB 0      0           172.31.6.0:22   76.145.243.188:56151 users:(("sshd-session",pid=5026,fd=4))
```

The `tcp ESTAB` line is your own SSH session - a live connection between your
laptop (`Peer Address`) and the server on port 22.

> **DBA Context - Counting Connections:** PostgreSQL has a connection limit. When
> the database says "too many clients", counting established connections helps.
> `sudo ss -tn state established '( dport = :5432 or sport = :5432 )'` shows every
> active connection to the database. Pipe it to `wc -l` to count them. This is a
> quick way to see whether you are near the limit.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what a port is and name the well-known port for PostgreSQL
- [ ] Explain what a socket is (address plus port)
- [ ] Run `sudo ss -tulpn` and read the State, Local Address, and Process columns
- [ ] Use `sudo ss -tulpn | grep 5432` to check if PostgreSQL is listening
- [ ] Explain the difference between `127.0.0.1:5432` and `0.0.0.0:5432`
- [ ] Explain why opening the firewall does not help if `listen_addresses` is `localhost`
- [ ] Explain the difference between LISTEN and ESTABLISHED sockets
