# Prepare your worksheet

[Classroom home](README.md) · [Next](02-etcd.md)

## PART 0 — BEFORE CLASS

The main lesson assumes software, OS dependencies, service users, directories,
service units for Patroni/HAProxy/Mattermost, and TLS files are already installed.
The sysadmin reference at the end lists the existing installation procedure.
It requires Suta handoff artifacts; it is not a generic download/install guide.

Prepared versions: etcd 3.6.14+suta.2; PostgreSQL 16.15; Patroni 4.1.4;
HAProxy 3.2.22; Mattermost 11.10.1. Use the matching CentOS lab artifacts.

No database should have been initialized. Patroni will run initdb and clone the
replicas. All four application services should initially be stopped.

Fill in the private IPv4 address of each server:

| Worksheet field | Server role | Private IPv4 address |
|---|---|---|
| `DCS_1_IP` | `dcs-1` | `172.31.22.177` |
| `DCS_2_IP` | `dcs-2` | `172.31.17.244` |
| `DCS_3_IP` | `dcs-3` | `172.31.23.72` |
| `PG_HA_1_IP` | `pg-ha-1` | `172.31.16.18` |
| `PG_HA_2_IP` | `pg-ha-2` | `172.31.19.223` |
| `PG_HA_3_IP` | `pg-ha-3` | `172.31.28.89` |
| `DB_ROUTER_1_IP` | `db-router-1` | `172.31.31.45` |
| `MATTERMOST_1_IP` | `mattermost-1` | `172.31.27.193` |

Replace every *_IP token in the configuration text before saving it. These are
worksheet placeholders, not shell variables. Use actual private IPv4 addresses.
All eight hostnames must resolve to their correct private addresses.
Use the assigned terminal/SSH session for each named server as ec2-user.

Prepare three different strong passwords in a private password manager. Do not
write the passwords in this guide or paste them into Chat:

| Secret label | Used by |
|---|---|
| `REPLACE_POSTGRES_SUPERUSER_PASSWORD` | Patroni's PostgreSQL superuser |
| `REPLACE_REPLICATION_PASSWORD` | Patroni's replication user |
| `REPLACE_MATTERMOST_DATABASE_PASSWORD` | Mattermost's database login |
Use the same superuser and replication values on all three Patroni nodes.
For simple substitution in YAML and the application URI, use long random
alphanumeric passwords. Otherwise quote/escape YAML and percent-encode the URI
password correctly. Never use the literal placeholder as a password.

Network prerequisites within this lab: etcd peers 2380; etcd clients 2379;
PostgreSQL replication 5432; Patroni health API 8008 from the router;
app to router 5432; instructor access to Mattermost 8065 through the approved
lab access path. Do not expose PostgreSQL, etcd or the Patroni API to the internet.

TLS prerequisites: each etcd member certificate must cover that node's private
IP and hostname. Certificates must be current and signed by the same CA.
Patroni must have a client certificate and its matching private key.

## Connect to a server before running its steps

Do not run the role helper in your Mac terminal. It is installed on the Suta
control-plane server. From your Mac, first open the control-plane session:

```bash
ssh -4 -i ~/.ssh/suta-openclaw.pem -o StrictHostKeyChecking=yes ec2-user@32.199.6.222
```

If your key is stored elsewhere, use that full path after `-i`. You should now
see a prompt like `[ec2-user@ip-172-31-... ~]$`. The next command must be run
at that control-plane prompt, not at `hafopezi@Happys-MacBook-Pro`.

The lab servers accept SSH through this control plane. In SutaBot, the HA001
terminal may already open at this prompt; if so, skip the first command.

To connect to a role:

```bash
/home/ec2-user/.local/bin/patroni-role-ssh HA001 dcs-1
```

Use one of these role names as the final argument:

```text
dcs-1
dcs-2
dcs-3
pg-ha-1
pg-ha-2
pg-ha-3
db-router-1
mattermost-1
```

The command should leave you at a prompt like `[ec2-user@dcs-1 ~]$`. Confirm
where you landed before doing anything:

```bash
hostname
```

```bash
whoami
```

Expect the role name and `ec2-user`. Run only the commands for that role while
connected. When that role's section is complete, return to the control plane:

```bash
exit
```

Then connect to the next role by changing only the final argument. For example:

```bash
/home/ec2-user/.local/bin/patroni-role-ssh HA001 dcs-2
```

If the helper says the role has no address, the server is not ready; tell the
instructor. Do not bypass strict host-key checking or copy a private key to your
laptop.

How to use this file:
- Run one indented command at a time. Do not paste whole sections into a terminal.
- Text between BEGIN FILE and END FILE goes into the editor, not the shell.
- In vi: press i, paste the file text, press Escape, type :wq, press Enter.
- YAML indentation uses spaces. Keep the indentation shown.
- postgres=# is a database prompt; a prompt ending in $ is a Linux shell.
- Type only commands, never the sample prompt.
- Stop and investigate an unexpected result before the next dependency.

Check your starting terminal on every server:

```bash
hostname
```



```bash
whoami
```


Expect the assigned role name and ec2-user.

On each PostgreSQL server, verify the installed binary:

```bash
/opt/pgsql/bin/postgres --version
```


Expect PostgreSQL 16.15. A version check proves the program runs, not that a
database has been created.


## ARCHITECTURE

Mattermost -> HAProxy:5432 -> current PostgreSQL writer
Patroni on each PostgreSQL server -> etcd:2379 (mutual TLS)
etcd members -> each other:2380 (mutual TLS)
PostgreSQL writer -> streaming replicas

etcd stores coordination state and the leader lock; it does not store application
tables. Patroni manages PostgreSQL and leadership. HAProxy checks /primary on
port 8008 and sends database connections to the node reporting HTTP 200.
This lab uses asynchronous replication. It does not guarantee zero data loss.
A single router and a single app server remain single points of failure.

### Checkpoint

- [ ] You can identify every server and have the prepared software, TLS files and private passwords.

[Classroom home](README.md) · [Next](02-etcd.md)

## Instructor certificate checks before the student starts

On each etcd node, check its member certificate:

```bash
sudo openssl x509 -in /etc/etcd/member.crt -noout -dates
```

```bash
sudo openssl verify -CAfile /etc/etcd/ca.crt /etc/etcd/member.crt
```

On each PostgreSQL node, check the Patroni client certificate:

```bash
sudo openssl x509 -in /etc/patroni/etcd-client.crt -noout -dates
```

```bash
sudo openssl verify -CAfile /etc/patroni/etcd-ca.crt /etc/patroni/etcd-client.crt
```

The validity interval must cover the class and verification must report `OK`. An expired certificate requires instructor renewal and redistribution, not disabling TLS verification. The CA signing key stays on the control plane.
