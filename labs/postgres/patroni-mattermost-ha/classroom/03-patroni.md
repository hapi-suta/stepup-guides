# Configure Patroni and join replicas

[Classroom home](README.md) · [Previous](02-etcd.md) · [Next](04-haproxy.md)

## Prepare the service to survive a reboot

**On each of pg-ha-1, pg-ha-2 and pg-ha-3, as ec2-user**, confirm the instructor installed the following systemd drop-in. If it is missing, create it before starting Patroni:

```bash
sudo mkdir -p /etc/systemd/system/patroni.service.d
```

```bash
sudo vi /etc/systemd/system/patroni.service.d/runtime-directory.conf
```

Save this content:

```ini
[Service]
RuntimeDirectory=postgresql
RuntimeDirectoryMode=0755
RuntimeDirectoryPreserve=yes
```

```bash
sudo systemctl daemon-reload
```

```bash
systemctl cat patroni
```

Look for the three RuntimeDirectory settings. systemd creates `/run/postgresql` owned by the unit's postgres user before starting the service. `/var/run` points to `/run`; its contents do not survive a reboot. Creating the directory once by hand is insufficient.

## 8. Configure Patroni on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Save this member’s generated identity and cluster configuration.


```bash
sudo vi /etc/patroni/patroni.yml
```



```yaml
scope: suta-ha001
namespace: /service/
name: pg-ha-1
restapi:
  listen: 172.31.16.18:8008
  connect_address: 172.31.16.18:8008
etcd3:
  hosts: 172.31.22.177:2379,172.31.17.244:2379,172.31.23.72:2379
  protocol: https
  cacert: /etc/patroni/etcd-ca.crt
  cert: /etc/patroni/etcd-client.crt
  key: /etc/patroni/etcd-client.key
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: 'on'
        max_wal_senders: 10
        max_replication_slots: 10
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - local all all peer
    - host all postgres 172.31.16.18/32 scram-sha-256
    - host all postgres 172.31.19.223/32 scram-sha-256
    - host all postgres 172.31.28.89/32 scram-sha-256
    - host replication replicator 172.31.16.18/32 scram-sha-256
    - host replication replicator 172.31.19.223/32 scram-sha-256
    - host replication replicator 172.31.28.89/32 scram-sha-256
    - host mattermost mattermost 172.31.31.45/32 scram-sha-256
postgresql:
  listen: 172.31.16.18:5432
  connect_address: 172.31.16.18:5432
  data_dir: /opt/pgsql/data
  bin_dir: /opt/pgsql/bin
  pgpass: /etc/patroni/pgpass
  authentication:
    superuser:
      username: postgres
      password: REPLACE_POSTGRES_SUPERUSER_PASSWORD
    replication:
      username: replicator
      password: REPLACE_REPLICATION_PASSWORD
  parameters:
    unix_socket_directories: /var/run/postgresql
    password_encryption: scram-sha-256
  create_replica_methods:
    - basebackup
  basebackup:
    checkpoint: fast
tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
```


What happens: Enter the role-resolved pg-ha-1 YAML supplied for this step. Secret tokens are inserted through the protected field and are never rendered into chat.


```bash
sudo chown postgres:postgres /etc/patroni/patroni.yml
```



```bash
sudo chmod 0600 /etc/patroni/patroni.yml
```


Only postgres and root can read the database passwords.

**Check:**

```bash
sudo grep -n -E "^(scope|name|restapi|etcd3|postgresql):" /etc/patroni/patroni.yml
```


Look for: the scope, name, restapi, etcd3 and postgresql top-level keys, each on its own numbered line
grep -E matches several patterns at once; -n adds line numbers. Every top-level section of patroni.yml must be present. A missing key means the file was saved incomplete.

Expected: The saved configuration passes YAML, secret-permission and Patroni contract validation.


## 9. Configure Patroni on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Save this member’s generated identity and cluster configuration.


```bash
sudo vi /etc/patroni/patroni.yml
```



```yaml
scope: suta-ha001
namespace: /service/
name: pg-ha-2
restapi:
  listen: 172.31.19.223:8008
  connect_address: 172.31.19.223:8008
etcd3:
  hosts: 172.31.22.177:2379,172.31.17.244:2379,172.31.23.72:2379
  protocol: https
  cacert: /etc/patroni/etcd-ca.crt
  cert: /etc/patroni/etcd-client.crt
  key: /etc/patroni/etcd-client.key
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: 'on'
        max_wal_senders: 10
        max_replication_slots: 10
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - local all all peer
    - host all postgres 172.31.16.18/32 scram-sha-256
    - host all postgres 172.31.19.223/32 scram-sha-256
    - host all postgres 172.31.28.89/32 scram-sha-256
    - host replication replicator 172.31.16.18/32 scram-sha-256
    - host replication replicator 172.31.19.223/32 scram-sha-256
    - host replication replicator 172.31.28.89/32 scram-sha-256
    - host mattermost mattermost 172.31.31.45/32 scram-sha-256
postgresql:
  listen: 172.31.19.223:5432
  connect_address: 172.31.19.223:5432
  data_dir: /opt/pgsql/data
  bin_dir: /opt/pgsql/bin
  pgpass: /etc/patroni/pgpass
  authentication:
    superuser:
      username: postgres
      password: REPLACE_POSTGRES_SUPERUSER_PASSWORD
    replication:
      username: replicator
      password: REPLACE_REPLICATION_PASSWORD
  parameters:
    unix_socket_directories: /var/run/postgresql
    password_encryption: scram-sha-256
  create_replica_methods:
    - basebackup
  basebackup:
    checkpoint: fast
tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
```


What happens: Enter the supplied pg-ha-2 YAML. Protected secrets resolve outside chat.


```bash
sudo chown postgres:postgres /etc/patroni/patroni.yml
```



```bash
sudo chmod 0600 /etc/patroni/patroni.yml
```


Only postgres and root can read the database passwords.

**Check:**

```bash
sudo grep -n -E "^(scope|name|restapi|etcd3|postgresql):" /etc/patroni/patroni.yml
```


Look for: the scope, name, restapi, etcd3 and postgresql top-level keys, each on its own numbered line
grep -E matches several patterns at once; -n adds line numbers. Every top-level section of patroni.yml must be present. A missing key means the file was saved incomplete.

Expected: The file names pg-ha-2 and passes the Patroni contract validator.


## 10. Configure Patroni on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Save this member’s generated identity and cluster configuration.


```bash
sudo vi /etc/patroni/patroni.yml
```



```yaml
scope: suta-ha001
namespace: /service/
name: pg-ha-3
restapi:
  listen: 172.31.28.89:8008
  connect_address: 172.31.28.89:8008
etcd3:
  hosts: 172.31.22.177:2379,172.31.17.244:2379,172.31.23.72:2379
  protocol: https
  cacert: /etc/patroni/etcd-ca.crt
  cert: /etc/patroni/etcd-client.crt
  key: /etc/patroni/etcd-client.key
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: 'on'
        max_wal_senders: 10
        max_replication_slots: 10
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - local all all peer
    - host all postgres 172.31.16.18/32 scram-sha-256
    - host all postgres 172.31.19.223/32 scram-sha-256
    - host all postgres 172.31.28.89/32 scram-sha-256
    - host replication replicator 172.31.16.18/32 scram-sha-256
    - host replication replicator 172.31.19.223/32 scram-sha-256
    - host replication replicator 172.31.28.89/32 scram-sha-256
    - host mattermost mattermost 172.31.31.45/32 scram-sha-256
postgresql:
  listen: 172.31.28.89:5432
  connect_address: 172.31.28.89:5432
  data_dir: /opt/pgsql/data
  bin_dir: /opt/pgsql/bin
  pgpass: /etc/patroni/pgpass
  authentication:
    superuser:
      username: postgres
      password: REPLACE_POSTGRES_SUPERUSER_PASSWORD
    replication:
      username: replicator
      password: REPLACE_REPLICATION_PASSWORD
  parameters:
    unix_socket_directories: /var/run/postgresql
    password_encryption: scram-sha-256
  create_replica_methods:
    - basebackup
  basebackup:
    checkpoint: fast
tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
```


What happens: Enter the supplied pg-ha-3 YAML using the same protected cluster credentials.


```bash
sudo chown postgres:postgres /etc/patroni/patroni.yml
```



```bash
sudo chmod 0600 /etc/patroni/patroni.yml
```


Only postgres and root can read the database passwords.

**Check:**

```bash
sudo grep -n -E "^(scope|name|restapi|etcd3|postgresql):" /etc/patroni/patroni.yml
```


Look for: the scope, name, restapi, etcd3 and postgresql top-level keys, each on its own numbered line
grep -E matches several patterns at once; -n adds line numbers. Every top-level section of patroni.yml must be present. A missing key means the file was saved incomplete.

Expected: The file names pg-ha-3 and passes the Patroni contract validator.


## 11. Bootstrap the first Patroni leader

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Start Patroni on pg-ha-1 and inspect the service status.


```bash
sudo systemctl daemon-reload
```


Reload systemd so it sees the saved unit. This does not start the service.


```bash
sudo systemctl enable patroni
```


Enable startup after reboot.


```bash
sudo systemctl start patroni
```


Start the service now.

What happens: Enable Patroni for boot and start only pg-ha-1; Patroni initializes PostgreSQL with checksums and writes cluster state to etcd.

**Check:**

```bash
systemctl status patroni --no-pager
```


Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)
Read the Loaded and Active lines in the full status output. Loaded identifies the unit; Active reports the current service state.

Expected: pg-ha-1 becomes one running leader before either replica starts.

Before starting either replica, prove pg-ha-1 became the writer:

```bash
sudo -iu postgres
```



```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```



```bash
exit
```


Expect pg-ha-1 as Leader and running. If no leader appears, read Patroni logs
and fix it before joining replicas. A running systemd process alone is insufficient.


## 12. Join pg-ha-2 as the first replica

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Start pg-ha-2 and watch it join the established cluster.


```bash
sudo systemctl daemon-reload
```


Reload systemd so it sees the saved unit. This does not start the service.


```bash
sudo systemctl enable patroni
```


Enable startup after reboot.


```bash
sudo systemctl start patroni
```


Start the service now.

What happens: Start Patroni on pg-ha-2 only after the leader and pg-ha-2 configuration validators pass.

**Check:**

```bash
systemctl status patroni --no-pager
```


Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)
Read the Loaded and Active lines in the full status output. Loaded identifies the unit; Active reports the current service state.

Expected: pg-ha-2 joins as a streaming replica while pg-ha-1 remains leader.


## 13. Join pg-ha-3 as the second replica

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Start Patroni on pg-ha-3 and inspect the service status.


```bash
sudo systemctl daemon-reload
```


Reload systemd so it sees the saved unit. This does not start the service.


```bash
sudo systemctl enable patroni
```


Enable startup after reboot.


```bash
sudo systemctl start patroni
```


Start the service now.

What happens: Start Patroni on pg-ha-3 after the first replica is already streaming.

**Check:**

```bash
systemctl status patroni --no-pager
```


Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)
Read the Loaded and Active lines in the full status output. Loaded identifies the unit; Active reports the current service state.

Expected: The cluster reports one leader and two streaming replicas on one timeline.

Now verify all members:

```bash
sudo -iu postgres
```



```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```



```bash
exit
```


Expect one Leader and two streaming Replicas. Wait for cloning to finish.

### Checkpoint

- [ ] One member is Leader and two members are streaming Replicas.

[Classroom home](README.md) · [Previous](02-etcd.md) · [Next](04-haproxy.md)
