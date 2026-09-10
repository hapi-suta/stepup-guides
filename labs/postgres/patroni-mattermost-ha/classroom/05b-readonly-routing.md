# Route read-only connections to standbys

[Classroom home](README.md) · [Previous: app database](05-app-database.md) · [Next: app verification](06-verify.md)

Complete the app database step first. Keep the application on port **5432**. We will add **5433** for connections that should go to a standby.

HAProxy does not inspect SQL and split SELECT from INSERT. The client chooses a connection endpoint. A standby rejects writes because PostgreSQL is in recovery.

## 1. Add the reader endpoint

**Server: db-router-1 · User: ec2-user · Linux terminal**

```bash
sudo vi /etc/haproxy/haproxy.cfg
```

Keep the existing writer configuration. Append the following text, replacing the three IP placeholders with the PostgreSQL private addresses:

```text
frontend postgres_readers
  bind *:5433
  mode tcp
  default_backend patroni_replicas

backend patroni_replicas
  mode tcp
  balance roundrobin
  option httpchk
  http-check connect port 8008
  http-check send meth GET uri /replica?lag=16MB ver HTTP/1.1 hdr Host patroni
  http-check expect status 200
  server pg-ha-1 PG_HA_1_IP:5432 check port 8008 inter 2s fall 2 rise 2 on-marked-down shutdown-sessions
  server pg-ha-2 PG_HA_2_IP:5432 check port 8008 inter 2s fall 2 rise 2 on-marked-down shutdown-sessions
  server pg-ha-3 PG_HA_3_IP:5432 check port 8008 inter 2s fall 2 rise 2 on-marked-down shutdown-sessions
```

The health check requires a running replica with acceptable lag. The leader is excluded. `on-marked-down shutdown-sessions` also closes existing reader sessions when their server stops meeting the replica check, including when it is promoted. Round-robin distributes new connections; a connected session stays on its selected server. The 16 MB lag threshold is a lab choice, not a guarantee of fresh reads. See [Patroni's health-check contract](https://patroni.readthedocs.io/en/latest/rest_api.html).

## 2. Validate before restarting

```bash
sudo /usr/local/sbin/haproxy -c -V -f /etc/haproxy/haproxy.cfg
```

Expect `Configuration file is valid`. Fix any reported error before continuing.

```bash
sudo systemctl restart haproxy
```

This installed unit has no reload action. Restarting can disconnect existing sessions, so do this before handing over the app.

```bash
systemctl status haproxy --no-pager
```

Expect `active (running)`. Allow a few seconds for backend health checks. The instructor must permit the intended lab client to reach the router on 5433; keep it private.

## 3. Write a test row through the writer endpoint

**Server: pg-ha-1 · User: ec2-user · Linux terminal**

```bash
/opt/pgsql/bin/psql -h db-router-1 -p 5432 -U mattermost -d mattermost
```

Enter the Mattermost database password privately. Wait for `mattermost=>`.

```sql
CREATE TABLE classroom_routing_probe (id integer PRIMARY KEY, note text);
```

Expect `CREATE TABLE`. Run this once in the fresh class database.

```sql
INSERT INTO classroom_routing_probe VALUES (1, 'written through the writer endpoint');
```

Expect `INSERT 0 1`.

```text
\q
```

You are back in Linux.

## 4. Connect through the reader endpoint

```bash
/opt/pgsql/bin/psql -h db-router-1 -p 5433 -U mattermost -d mattermost
```

Enter the same database password. At `mattermost=>`:

```sql
SELECT inet_server_addr(), pg_is_in_recovery();
```

Expect a standby's private IP and `t`. Record the IP. Exit with `\q`, reconnect and repeat several times to see how new connections are distributed. Do not expect one existing connection to switch servers between queries.

```sql
TABLE classroom_routing_probe;
```

Expect the row created through 5432. Replication is asynchronous; if it has not arrived yet, wait briefly and repeat this read.

## 5. Prove the standby refuses a write

Still connected through **5433**:

```sql
INSERT INTO classroom_routing_probe VALUES (2, 'must be rejected');
```

Expected failure: `cannot execute INSERT in a read-only transaction`. This error is the successful outcome of this test. If the write succeeds, stop and investigate the endpoint before using it for read-only routing.

```text
\q
```

## Checkpoint

- [ ] A write through 5432 succeeded.
- [ ] Reader connections reached standbys with `pg_is_in_recovery() = t`.
- [ ] The replicated row was readable through 5433.
- [ ] A write through 5433 was rejected.
- [ ] The app still uses the writer endpoint, 5432.

[Next: app verification](06-verify.md)
