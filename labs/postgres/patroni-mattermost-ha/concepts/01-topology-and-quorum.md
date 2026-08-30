# Concepts: topology and quorum

Learn the eight stable roles, why three etcd voters tolerate one loss, how Patroni
uses the DCS, and why HAProxy and Mattermost remain single points of failure.

```bash
hostname
```

```bash
sudo /usr/local/bin/etcdctl --endpoints="https://$(hostname -I | awk '{print $1}'):2379" --cacert=/etc/etcd/ca.crt --cert=/etc/etcd/member.crt --key=/etc/etcd/member.key member list --write-out=table
```

```bash
sudo sed -n '1,120p' /etc/haproxy/haproxy.cfg
```
