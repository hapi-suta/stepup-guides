# Prove: deterministic release evidence

Prove topology, snapshot readiness and the complete cleanup inventory. Evidence is
derived from server observers; pasted output and tutor prose cannot complete steps.

```bash
sudo -u postgres /usr/local/bin/patronictl -c /etc/patroni/patroni.yml list --format=json
```

```bash
sudo /usr/local/bin/etcdutl snapshot status /var/lib/etcd/suta-baseline.db --write-out=json
```

```bash
suta-lab reset --plan
```
