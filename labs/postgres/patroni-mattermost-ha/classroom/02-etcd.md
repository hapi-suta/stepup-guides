# Configure etcd

[Classroom home](README.md) · [Previous](01-prepare.md) · [Next](03-patroni.md)

## 1. Configure dcs-1

**SERVER: dcs-1 | START AS: ec2-user in Linux**


The first member needs a unique name, addresses, peer list, data directory and mutual-TLS rules.


```bash
sudo vi /etc/systemd/system/etcd.service
```


The backslashes continue ONE ExecStart instruction across lines. They do not
chain commands. Keep them exactly as shown.


```ini
[Unit]
Description=SUTA etcd member
After=network-online.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/etcd \
  --name=dcs-1 \
  --data-dir=/var/lib/etcd \
  --listen-client-urls=https://DCS_1_IP:2379 \
  --advertise-client-urls=https://DCS_1_IP:2379 \
  --listen-peer-urls=https://DCS_1_IP:2380 \
  --initial-advertise-peer-urls=https://DCS_1_IP:2380 \
  --initial-cluster=dcs-1=https://DCS_1_IP:2380,dcs-2=https://DCS_2_IP:2380,dcs-3=https://DCS_3_IP:2380 \
  --initial-cluster-state=new \
  --initial-cluster-token=suta-ha001-etcd \
  --client-cert-auth=true \
  --trusted-ca-file=/etc/etcd/ca.crt \
  --cert-file=/etc/etcd/member.crt \
  --key-file=/etc/etcd/member.key \
  --peer-client-cert-auth=true \
  --peer-trusted-ca-file=/etc/etcd/ca.crt \
  --peer-cert-file=/etc/etcd/member.crt \
  --peer-key-file=/etc/etcd/member.key
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```


What happens: sudo opens the systemd unit with permission to save; vi lets you enter the exact role-resolved configuration supplied for this step.

**Check:**

```bash
sudo grep -n "ExecStart" /etc/systemd/system/etcd.service
```


Look for: one ExecStart= line with the full path of the binary
grep -n prints matching lines with their line numbers. A saved unit file must contain exactly one ExecStart line; if grep prints nothing, the file was not saved or is empty.

Expected: vi opens the new etcd.service file; after saving, systemctl can parse the unit.


## 2. Configure dcs-2

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Every voting member needs its own identity while sharing the same initial cluster definition.


```bash
sudo vi /etc/systemd/system/etcd.service
```


The backslashes continue ONE ExecStart instruction across lines. They do not
chain commands. Keep them exactly as shown.


```ini
[Unit]
Description=SUTA etcd member
After=network-online.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/etcd \
  --name=dcs-2 \
  --data-dir=/var/lib/etcd \
  --listen-client-urls=https://DCS_2_IP:2379 \
  --advertise-client-urls=https://DCS_2_IP:2379 \
  --listen-peer-urls=https://DCS_2_IP:2380 \
  --initial-advertise-peer-urls=https://DCS_2_IP:2380 \
  --initial-cluster=dcs-1=https://DCS_1_IP:2380,dcs-2=https://DCS_2_IP:2380,dcs-3=https://DCS_3_IP:2380 \
  --initial-cluster-state=new \
  --initial-cluster-token=suta-ha001-etcd \
  --client-cert-auth=true \
  --trusted-ca-file=/etc/etcd/ca.crt \
  --cert-file=/etc/etcd/member.crt \
  --key-file=/etc/etcd/member.key \
  --peer-client-cert-auth=true \
  --peer-trusted-ca-file=/etc/etcd/ca.crt \
  --peer-cert-file=/etc/etcd/member.crt \
  --peer-key-file=/etc/etcd/member.key
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```


What happens: Create the dcs-2 unit using the exact role-resolved configuration supplied for this step.

**Check:**

```bash
sudo grep -n "ExecStart" /etc/systemd/system/etcd.service
```


Look for: one ExecStart= line with the full path of the binary
grep -n prints matching lines with their line numbers. A saved unit file must contain exactly one ExecStart line; if grep prints nothing, the file was not saved or is empty.

Expected: The saved unit names dcs-2 and uses the common three-member initial cluster.


## 3. Configure dcs-3

**SERVER: dcs-3 | START AS: ec2-user in Linux**


The third voting member completes the odd-sized quorum design.


```bash
sudo vi /etc/systemd/system/etcd.service
```


The backslashes continue ONE ExecStart instruction across lines. They do not
chain commands. Keep them exactly as shown.


```ini
[Unit]
Description=SUTA etcd member
After=network-online.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/etcd \
  --name=dcs-3 \
  --data-dir=/var/lib/etcd \
  --listen-client-urls=https://DCS_3_IP:2379 \
  --advertise-client-urls=https://DCS_3_IP:2379 \
  --listen-peer-urls=https://DCS_3_IP:2380 \
  --initial-advertise-peer-urls=https://DCS_3_IP:2380 \
  --initial-cluster=dcs-1=https://DCS_1_IP:2380,dcs-2=https://DCS_2_IP:2380,dcs-3=https://DCS_3_IP:2380 \
  --initial-cluster-state=new \
  --initial-cluster-token=suta-ha001-etcd \
  --client-cert-auth=true \
  --trusted-ca-file=/etc/etcd/ca.crt \
  --cert-file=/etc/etcd/member.crt \
  --key-file=/etc/etcd/member.key \
  --peer-client-cert-auth=true \
  --peer-trusted-ca-file=/etc/etcd/ca.crt \
  --peer-cert-file=/etc/etcd/member.crt \
  --peer-key-file=/etc/etcd/member.key
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```


What happens: Create the dcs-3 unit using the exact role-resolved configuration supplied for this step.

**Check:**

```bash
sudo grep -n "ExecStart" /etc/systemd/system/etcd.service
```


Look for: one ExecStart= line with the full path of the binary
grep -n prints matching lines with their line numbers. A saved unit file must contain exactly one ExecStart line; if grep prints nothing, the file was not saved or is empty.

Expected: The saved unit names dcs-3 and contains authenticated client and peer TLS settings.


## 4. Start dcs-1

**SERVER: dcs-1 | START AS: ec2-user in Linux**


dcs-1 can start only after all three initial member configurations pass validation.


```bash
sudo systemctl daemon-reload
```


Reload systemd so it sees the saved unit. This does not start the service.


```bash
sudo systemctl enable etcd
```


Enable startup after reboot.


```bash
sudo systemctl start etcd
```


Start the service now.

What happens: enable registers etcd for boot; --now starts the service on dcs-1 immediately.

**Check:**

```bash
systemctl status etcd --no-pager
```


Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)
Read the Loaded and Active lines in the full status output. Loaded identifies the unit; Active reports the current service state.

Expected: The command returns without error and dcs-1 enters its initial member startup.

The first member alone cannot form a majority. Continue starting dcs-2 and
dcs-3, then run the three-endpoint health check. Do not change the cluster list
just because the first member reports that it has no leader yet.


## 5. Start dcs-2

**SERVER: dcs-2 | START AS: ec2-user in Linux**


The second configured voting member allows the initial cluster to reach a majority.


```bash
sudo systemctl daemon-reload
```


Reload systemd so it sees the saved unit. This does not start the service.


```bash
sudo systemctl enable etcd
```


Enable startup after reboot.


```bash
sudo systemctl start etcd
```


Start the service now.

What happens: enable registers etcd for boot and starts the service on dcs-2.

**Check:**

```bash
systemctl status etcd --no-pager
```


Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)
Read the Loaded and Active lines in the full status output. Loaded identifies the unit; Active reports the current service state.

Expected: The command returns without error and dcs-2 becomes active.


## 6. Start dcs-3

**SERVER: dcs-3 | START AS: ec2-user in Linux**


The third configured voter restores the intended one-member failure tolerance.


```bash
sudo systemctl daemon-reload
```


Reload systemd so it sees the saved unit. This does not start the service.


```bash
sudo systemctl enable etcd
```


Enable startup after reboot.


```bash
sudo systemctl start etcd
```


Start the service now.

What happens: enable registers etcd for boot and starts the service on dcs-3.

**Check:**

```bash
systemctl status etcd --no-pager
```


Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)
Read the Loaded and Active lines in the full status output. Loaded identifies the unit; Active reports the current service state.

Expected: The command returns without error and dcs-3 becomes active.


## 7. Prove quorum over mutual TLS

**SERVER: dcs-1 | START AS: ec2-user in Linux**


A running process is weaker evidence than three reachable voting members that can commit.


```bash
sudo /usr/local/bin/etcdctl --endpoints=https://dcs-1:2379,https://dcs-2:2379,https://dcs-3:2379 --cacert=/etc/etcd/ca.crt --cert=/etc/etcd/member.crt --key=/etc/etcd/member.key endpoint health
```


What happens: etcdctl contacts every named endpoint with the member certificate and asks each endpoint to commit a health proposal.

Expected: Three lines report healthy endpoints and successful proposal commits.

### Checkpoint

- [ ] All three endpoints report healthy. A single running etcd service is not enough.

[Classroom home](README.md) · [Previous](01-prepare.md) · [Next](03-patroni.md)
