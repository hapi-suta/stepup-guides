# Read logs and understand settings

[Classroom home](README.md) · [Previous](07-switchover.md)

## WHEN A CHECK FAILS

On the server with the failing service, read its recent logs. These are separate
commands; run the relevant one. Logs may contain sensitive configuration details.


```bash
sudo journalctl -u etcd -n 80 --no-pager
```



```bash
sudo journalctl -u patroni -n 80 --no-pager
```



```bash
sudo journalctl -u haproxy -n 80 --no-pager
```



```bash
sudo journalctl -u mattermost -n 80 --no-pager
```


Read from the earliest error in the failed start, not only the final exit line.
- etcd: certificate expired/unknown authority means check validity and common CA.
  Address/SAN mismatch means the certificate does not identify this server.
  Connection refused means check peer address, listener and network rules.
- Patroni: YAML errors identify an indentation or syntax problem. Permission
  denied often points at config, TLS keys, socket directory or the data directory.
  DCS connection errors must be fixed before PostgreSQL leadership can work.
- HAProxy: configuration validation gives a line number. If all backends are DOWN,
  inspect Patroni /primary health responses and port 8008 connectivity.
- Mattermost: password authentication failed means compare the role password with
  the URI. Connection refused means verify router listener and healthy backend.
Do not delete data directories or reset etcd to hide a configuration error.


## UNDERSTAND THE IMPORTANT SETTINGS

scope and namespace identify the same Patroni cluster on all three nodes.
name is unique per node; connect_address advertises a reachable private address.
ttl=30 is the DCS leader-lock lifetime; loop_wait=10 is the normal control-loop
interval; retry_timeout=10 bounds retries. These are related settings.
maximum_lag_on_failover=1048576 excludes excessively lagging candidates by this
lag check; it is not a promise that at most 1 MB can ever be lost.
use_pg_rewind allows a former primary to be realigned when rewind prerequisites
hold. data-checksums is enabled at bootstrap to support this setup.
use_slots helps retain WAL needed by replicas; monitor WAL/disk if one is offline.
bootstrap.dcs seeds shared settings only when the cluster is first initialized.
Changing that section later does not automatically update existing DCS settings.
pg_hba permits local peer login, exact database-node addresses for administration
and replication, and the router address for the Mattermost role/database.
HAProxy /primary checks distinguish the writer from a merely reachable database.
The etcd snapshot is coordination metadata, not a PostgreSQL backup.

### Checkpoint

- [ ] Identify the first meaningful error before changing configuration or restarting services.

[Classroom home](README.md) · [Previous](07-switchover.md)
