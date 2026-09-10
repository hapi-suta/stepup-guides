# Configure the database router

[Classroom home](README.md) · [Previous](03-patroni.md) · [Next](05-app-database.md)

## 14. Configure the HAProxy writer route

**SERVER: db-router-1 | START AS: ec2-user in Linux**


Mattermost needs one stable address that selects only Patroni's current primary.


```bash
sudo vi /etc/haproxy/haproxy.cfg
```



```text
global
  log stdout format raw local0
  maxconn 1024

defaults
  log global
  timeout connect 5s
  timeout client 60s
  timeout server 60s

frontend postgres_writer
  bind *:5432
  mode tcp
  default_backend patroni_primary

backend patroni_primary
  mode tcp
  option httpchk
  http-check connect port 8008
  http-check send meth GET uri /primary ver HTTP/1.1 hdr Host patroni
  http-check expect status 200
  server pg-ha-1 172.31.16.18:5432 check port 8008 inter 2s fall 2 rise 2 on-marked-down shutdown-sessions
  server pg-ha-2 172.31.19.223:5432 check port 8008 inter 2s fall 2 rise 2 on-marked-down shutdown-sessions
  server pg-ha-3 172.31.28.89:5432 check port 8008 inter 2s fall 2 rise 2 on-marked-down shutdown-sessions
```


What happens: Enter the supplied TCP frontend, three PostgreSQL backends and Patroni /primary HTTP health check.

**Check:**

```bash
sudo /usr/local/sbin/haproxy -c -V -f /etc/haproxy/haproxy.cfg
```


Look for: Configuration file is valid
haproxy -c checks the configuration without starting the service, -V makes it say so out loud, -f names the file. Anything other than 'valid' points at the exact line to fix.

Expected: HAProxy's parser accepts the file and exactly one healthy writer backend is eligible.


## 15. Start the writer endpoint

**SERVER: db-router-1 | START AS: ec2-user in Linux**


A valid file must still be loaded by a healthy service before applications can use it.


```bash
sudo systemctl daemon-reload
```


Reload systemd so it sees the saved unit. This does not start the service.


```bash
sudo systemctl enable haproxy
```


Enable startup after reboot.


```bash
sudo systemctl start haproxy
```


Start the service now.

What happens: Enable and start HAProxy after the configuration parser and role-health validator pass.

**Check:**

```bash
systemctl status haproxy --no-pager
```


Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)
Read the Loaded and Active lines in the full status output. Loaded identifies the unit; Active reports the current service state.

Expected: HAProxy listens on port 5432 and routes a rollback-only write check to the current primary.

### Checkpoint

- [ ] The configuration validates and HAProxy is running. Application verification follows after the database is created.

[Classroom home](README.md) · [Previous](03-patroni.md) · [Next](05-app-database.md)

## Why disconnect an unhealthy backend?

`on-marked-down shutdown-sessions` closes existing connections when a node fails the writer health check. Without it, a connection pool can keep using the old primary after it becomes a standby, causing write errors even though a new primary is healthy. In-flight requests may still fail; the application must reconnect and handle retries safely.
