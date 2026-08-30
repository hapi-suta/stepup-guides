# Build: the dependency-ordered HA stack

This phase follows the same order used to build the validated reference system.
The platform creates private machines, stages immutable artifacts and generates
secrets. You inspect and prove every meaningful configuration boundary; never copy
a private key or database password into chat or terminal history.

## 1. Establish the software supply chain

The immutable artifacts are PostgreSQL 16.15, Patroni 4.1.4, HAProxy 3.2.22,
Mattermost Team 11.10.1 and reproducible `etcd 3.6.14+suta.2`. Verify etcd on
`dcs-1`; do not replace it with an unpinned package.

```bash
sudo /usr/local/bin/etcd --version
```

Rollback: an artifact mismatch stops configuration before service startup. Replace
the staged bytes with the approved digest; never weaken the checksum.

## 2. Build the DCS mutual TLS and membership layer

Each member has a unique role, data directory, certificate and private-address SAN.
Shared CA/client material stays in the protected control-plane store.

```bash
sudo openssl x509 -in /etc/etcd/member.crt -noout -subject -ext subjectAltName
```

Inspect the systemd contract for unique `--name`, client/peer URLs, three initial
members, and both certificate-authentication flags.

```bash
sudo systemctl cat etcd
```

Use the certificate-bound private address. Loopback intentionally fails SAN
verification because it is not a valid advertised identity.

```bash
sudo /usr/local/bin/etcdctl --endpoints="https://$(hostname -I | awk '{print $1}'):2379" --cacert=/etc/etcd/ca.crt --cert=/etc/etcd/member.crt --key=/etc/etcd/member.key endpoint health
```

Rollback: rebuild a failed initial member with its original stable role. Never
force a new cluster or discard quorum state as a shortcut.

## 3. Prepare PostgreSQL and Patroni

PostgreSQL lives beneath `/opt/pgsql`; data, WAL, backup and logs have distinct
operational meanings even when the first release uses one attached volume.

```bash
sudo find /opt/pgsql -maxdepth 1 -mindepth 1 -type d -printf '%p\n' | sort
```

Inspect only non-secret Patroni fields. The full file contains generated credentials.

```bash
sudo grep -E '^(scope:|namespace:|name:|  protocol:|  data_dir:|  bin_dir:|  pgpass:)' /etc/patroni/patroni.yml
```

Verify checksums, slots, `pg_rewind`, and exact-node SCRAM rules.

```bash
sudo grep -E 'use_pg_rewind|use_slots|data-checksums|scram-sha-256' /etc/patroni/patroni.yml
```

The first node bootstraps alone; replicas start only after its leader endpoint is
ready, preventing three nodes from racing to initialize one scope.

```bash
sudo -u postgres /usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```

Rollback: stop an incomplete bootstrap and preserve it in a rollback directory
before clean initialization. Never delete ambiguous data while diagnosing.

## 4. Build the HAProxy writer route

TCP-open is insufficient: a healthy replica must not receive writes. HAProxy asks
Patroni `GET /primary` before considering a backend writer-eligible.

```bash
sudo /usr/local/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg
```

```bash
sudo grep -E 'http-check|server pg-ha-' /etc/haproxy/haproxy.cfg
```

Rollback: validate before reload so the last valid configuration remains active.

## 5. Connect the Mattermost workload

Mattermost is the end-to-end consumer, not proof of application HA. Its single node
targets `db-router-1:5432`; this command redacts credentials before display.

```bash
sudo jq -r '.SqlSettings.DataSource | sub("://[^:]+:[^@]+@";"://[REDACTED]@")' /opt/mattermost/config/config.json
```

```bash
curl -fsS http://$(hostname -I | awk '{print $1}'):8065/api/v4/system/ping
```

Rollback: restore Mattermost independently without altering DCS or PostgreSQL
membership. HAProxy and Mattermost remain declared single points of failure.
