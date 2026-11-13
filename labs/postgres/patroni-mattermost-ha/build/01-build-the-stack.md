# BUILD: construct the Patroni HA stack

You are the database engineer receiving eight clean, connected servers from the
platform team. The solution has not been installed or configured. You will build
it in dependency order, one observable action at a time.

SutaBot explains the reason for each action, asks you to predict what will happen,
and watches an independent validator. Terminal text and chat claims never complete
a step. Stop on unexpected output instead of copying the next command.

The path begins with immutable artifacts and mutual TLS for etcd, then creates the
PostgreSQL `/opt/pgsql` layout, Patroni membership and recovery policy, HAProxy
writer routing, and the Mattermost workload. Every change has an explicit rollback
through the bounded lab reset and is proved independently before the next dependency.

## Safety contract

- Work only on the role shown for the current step.
- Never print private keys, passwords, connection strings, or complete secret files.
- Run each displayed action exactly as authored. Do not combine separate Guide steps or invent extra commands.
- Do not initialize PostgreSQL manually; Patroni owns first bootstrap.
- Do not start replicas until the first leader validator passes.
- If observed output differs, pause and diagnose before continuing.

## 1. Verify the staged etcd archive

**Work on:** `dcs-1` as `ec2-user`

You must prove the software bytes are approved before installing them.

**Predict first:** Which value proves the staged bytes are the approved bytes?

Run this one action:

```bash
sha256sum /opt/suta/artifacts/etcd-v3.6.14-suta.2-linux-amd64.tar.gz
```

**What the command means:** sha256sum calculates the archive fingerprint. The reviewed SUTA etcd 3.6.14-suta.2 digest is 7f731a8b478d714d779e8f1c596a00f0613abc5bfca376451f594ede9d0d56e9. The same approved value is in the readable /opt/suta/artifacts/SHA256SUMS file on each dcs server; use cat /opt/suta/artifacts/SHA256SUMS to inspect that reference. Printing any digest alone does not prove approval.

**Expected result:** The first field must equal 7f731a8b478d714d779e8f1c596a00f0613abc5bfca376451f594ede9d0d56e9, followed by /opt/suta/artifacts/etcd-v3.6.14-suta.2-linux-amd64.tar.gz. Stop if even one character differs.

**Safety:** This is a read-only observation.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which value proves the staged bytes are the approved bytes?
2. Hint: Look at the first field in the output.
3. Stronger hint: Compare it with /opt/suta/artifacts/SHA256SUMS.
4. Solution: The first field must equal 7f731a8b478d714d779e8f1c596a00f0613abc5bfca376451f594ede9d0d56e9, followed by /opt/suta/artifacts/etcd-v3.6.14-suta.2-linux-amd64.tar.gz. Stop if even one character differs.

**Done when:** the independent `ETCD_ARCHIVE_VERIFIED` validator passes.

## 2. Copy the etcd server program into place

**Work on:** `dcs-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which program runs the voting member service?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/etcd /usr/local/bin/etcd
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcd. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcd now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program runs the voting member service?
2. Hint: Its filename is simply etcd.
3. Stronger hint: Use mode 0755 and destination /usr/local/bin/etcd.
4. Solution: Run the displayed install command, then wait for ETCD_SERVER_INSTALLED.

**Done when:** the independent `ETCD_SERVER_COPIED` validator passes.

## 3. Make the etcd server program runnable

**Work on:** `dcs-1` as `ec2-user`

The etcd program runs one voting member of the distributed configuration store.

**Predict first:** Which program runs the voting member service?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/etcd
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The command returns to the prompt without an error and /usr/local/bin/etcd is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program runs the voting member service?
2. Hint: Its filename is simply etcd.
3. Stronger hint: Use mode 0755 and destination /usr/local/bin/etcd.
4. Solution: Run the displayed install command, then wait for ETCD_SERVER_INSTALLED.

**Done when:** the independent `ETCD_SERVER_INSTALLED` validator passes.

## 4. Copy the etcdctl client program into place

**Work on:** `dcs-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which program will you use to ask the cluster for health?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/etcdctl /usr/local/bin/etcdctl
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdctl. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdctl now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program will you use to ask the cluster for health?
2. Hint: The client name ends in ctl, meaning control.
3. Stronger hint: Install /opt/suta/artifacts/etcdctl to /usr/local/bin/etcdctl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDCTL_INSTALLED.

**Done when:** the independent `ETCDCTL_COPIED` validator passes.

## 5. Make the etcdctl client program runnable

**Work on:** `dcs-1` as `ec2-user`

etcdctl sends authenticated health, membership and snapshot requests to etcd.

**Predict first:** Which program will you use to ask the cluster for health?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/etcdctl
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdctl is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program will you use to ask the cluster for health?
2. Hint: The client name ends in ctl, meaning control.
3. Stronger hint: Install /opt/suta/artifacts/etcdctl to /usr/local/bin/etcdctl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDCTL_INSTALLED.

**Done when:** the independent `ETCDCTL_INSTALLED` validator passes.

## 6. Copy the etcdutl recovery program into place

**Work on:** `dcs-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which utility will inspect an offline snapshot later?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/etcdutl /usr/local/bin/etcdutl
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdutl. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdutl now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which utility will inspect an offline snapshot later?
2. Hint: Its name ends in utl, meaning utility.
3. Stronger hint: Install the staged etcdutl file to /usr/local/bin/etcdutl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDUTL_INSTALLED.

**Done when:** the independent `ETCDUTL_COPIED` validator passes.

## 7. Make the etcdutl recovery program runnable

**Work on:** `dcs-1` as `ec2-user`

etcdutl inspects and restores offline etcd data such as snapshots.

**Predict first:** Which utility will inspect an offline snapshot later?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/etcdutl
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdutl is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which utility will inspect an offline snapshot later?
2. Hint: Its name ends in utl, meaning utility.
3. Stronger hint: Install the staged etcdutl file to /usr/local/bin/etcdutl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDUTL_INSTALLED.

**Done when:** the independent `ETCDUTL_INSTALLED` validator passes.

## 8. Create the /etc/etcd directory

**Work on:** `dcs-1` as `ec2-user`

Create /etc/etcd before setting its ownership and permissions.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo mkdir -p /etc/etcd
```

**What the command means:** sudo mkdir -p creates /etc/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and /etc/etcd exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 9. Give root ownership of the /etc/etcd directory

**Work on:** `dcs-1` as `ec2-user`

The root account owns /etc/etcd so the intended process can use this location.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo chown -R root:root /etc/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** /etc/etcd is owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 10. Set permissions on the /etc/etcd directory

**Work on:** `dcs-1` as `ec2-user`

/etc/etcd holds the member configuration and TLS identity files. Mode 0700 lets only the root account that runs this etcd service traverse or list this protected directory.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo chmod 0700 /etc/etcd
```

**What the command means:** chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Expected result:** The command returns without error and /etc/etcd is owned by root with mode 0700.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE` validator passes.

## 11. Create the /var/lib/etcd directory

**Work on:** `dcs-1` as `ec2-user`

Create /var/lib/etcd before setting its ownership and permissions.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo mkdir -p /var/lib/etcd
```

**What the command means:** sudo mkdir -p creates /var/lib/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and /var/lib/etcd exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 12. Give root ownership of the /var/lib/etcd directory

**Work on:** `dcs-1` as `ec2-user`

The root account owns /var/lib/etcd so the intended process can use this location.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo chown -R root:root /var/lib/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** /var/lib/etcd is owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 13. Set permissions on the /var/lib/etcd directory

**Work on:** `dcs-1` as `ec2-user`

etcd must persist quorum state in a root-only directory that starts empty.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo chmod 0700 /var/lib/etcd
```

**What the command means:** chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Expected result:** The command returns without error and /var/lib/etcd remains empty, root-owned, and mode 0700.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE` validator passes.

## 14. Copy the role-bound TLS public certificate into place

**Work on:** `dcs-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why can this file be 0644?

Run this one action:

```bash
sudo cp /opt/suta/handoff/etcd/member.crt /etc/etcd/member.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/etcd/member.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why can this file be 0644?
2. Hint: It contains identity claims and a public key, not the private key.
3. Stronger hint: Install member.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_MEMBER_CERT_INSTALLED.

**Done when:** the independent `ETCD_MEMBER_CERT_COPIED` validator passes.

## 15. Set permissions on the role-bound TLS public certificate

**Work on:** `dcs-1` as `ec2-user`

Peers need this signed public certificate to authenticate the member name and private address.

**Predict first:** Why can this file be 0644?

Run this one action:

```bash
sudo chmod 0644 /etc/etcd/member.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The certificate is installed without printing its contents.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why can this file be 0644?
2. Hint: It contains identity claims and a public key, not the private key.
3. Stronger hint: Install member.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_MEMBER_CERT_INSTALLED.

**Done when:** the independent `ETCD_MEMBER_CERT_INSTALLED` validator passes.

## 16. Copy the etcd trust anchor into place

**Work on:** `dcs-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which CA material belongs here?

Run this one action:

```bash
sudo cp /opt/suta/handoff/etcd/ca.crt /etc/etcd/ca.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/ca.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/etcd/ca.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which CA material belongs here?
2. Hint: Only the certificate used for verification.
3. Stronger hint: Install ca.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_CA_INSTALLED.

**Done when:** the independent `ETCD_CA_COPIED` validator passes.

## 17. Set permissions on the etcd trust anchor

**Work on:** `dcs-1` as `ec2-user`

The member needs the lab CA certificate to verify certificates presented by clients and peers.

**Predict first:** Which CA material belongs here?

Run this one action:

```bash
sudo chmod 0644 /etc/etcd/ca.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The CA certificate is installed without exposing any private key.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which CA material belongs here?
2. Hint: Only the certificate used for verification.
3. Stronger hint: Install ca.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_CA_INSTALLED.

**Done when:** the independent `ETCD_CA_INSTALLED` validator passes.

## 18. Copy the role-bound TLS private key into place

**Work on:** `dcs-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which permission prevents other users from reading the key?

Run this one action:

```bash
sudo cp /opt/suta/handoff/etcd/member.key /etc/etcd/member.key
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.key. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/etcd/member.key now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which permission prevents other users from reading the key?
2. Hint: The owner needs read and write; everyone else needs no access.
3. Stronger hint: That numeric mode is 0600.
4. Solution: Install the key with mode 0600, then install the CA and member certificate in their separately guided steps.

**Done when:** the independent `ETCD_MEMBER_KEY_COPIED` validator passes.

## 19. Set permissions on the role-bound TLS private key

**Work on:** `dcs-1` as `ec2-user`

Mutual TLS must identify this member without exposing its private key.

**Predict first:** Which permission prevents other users from reading the key?

Run this one action:

```bash
sudo chmod 0600 /etc/etcd/member.key
```

**What the command means:** chmod 0600 sets the file's permissions to 600 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The command returns without displaying key material.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which permission prevents other users from reading the key?
2. Hint: The owner needs read and write; everyone else needs no access.
3. Stronger hint: That numeric mode is 0600.
4. Solution: Install the key with mode 0600, then install the CA and member certificate in their separately guided steps.

**Done when:** the independent `ETCD_MEMBER_KEY_INSTALLED` validator passes.

## 20. Configure dcs-1

**Work on:** `dcs-1` as `ec2-user`

The first member needs a unique name, addresses, peer list, data directory and mutual-TLS rules.

**Predict first:** Which two values must be unique to dcs-1?

Run this one action:

```bash
sudo vi /etc/systemd/system/etcd.service
```

**What the command means:** sudo opens the systemd unit with permission to save; vi lets you enter the exact role-resolved configuration supplied for this step.

Enter this exact systemd content after SutaBot resolves only the registered role addresses and protected secret fields:

```text
[Unit]
Description=SUTA etcd member
After=network-online.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/etcd --name={{role}} --data-dir=/var/lib/etcd --listen-client-urls=https://{{private_ip}}:2379 --advertise-client-urls=https://{{private_ip}}:2379 --listen-peer-urls=https://{{private_ip}}:2380 --initial-advertise-peer-urls=https://{{private_ip}}:2380 --initial-cluster={{initial_cluster}} --initial-cluster-state=new --initial-cluster-token={{cluster_token}} --client-cert-auth=true --trusted-ca-file=/etc/etcd/ca.crt --cert-file=/etc/etcd/member.crt --key-file=/etc/etcd/member.key --peer-client-cert-auth=true --peer-trusted-ca-file=/etc/etcd/ca.crt --peer-cert-file=/etc/etcd/member.crt --peer-key-file=/etc/etcd/member.key
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

**Expected result:** vi opens the new etcd.service file; after saving, systemctl can parse the unit.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which two values must be unique to dcs-1?
2. Hint: Check --name and this node's listen/advertise addresses.
3. Stronger hint: The initial cluster list is identical on all three members; name and local addresses differ.
4. Solution: Open the file, enter the supplied dcs-1 unit, save with :wq, then run the validator.

**Done when:** the independent `ETCD_MEMBER_1_CONFIGURED` validator passes.

## 21. Copy the etcd server program into place

**Work on:** `dcs-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which program runs the voting member service?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/etcd /usr/local/bin/etcd
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcd. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcd now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program runs the voting member service?
2. Hint: Its filename is simply etcd.
3. Stronger hint: Use mode 0755 and destination /usr/local/bin/etcd.
4. Solution: Run the displayed install command, then wait for ETCD_SERVER_INSTALLED.

**Done when:** the independent `ETCD_SERVER_COPIED` validator passes.

## 22. Make the etcd server program runnable

**Work on:** `dcs-2` as `ec2-user`

The etcd program runs one voting member of the distributed configuration store.

**Predict first:** Which program runs the voting member service?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/etcd
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The command returns to the prompt without an error and /usr/local/bin/etcd is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program runs the voting member service?
2. Hint: Its filename is simply etcd.
3. Stronger hint: Use mode 0755 and destination /usr/local/bin/etcd.
4. Solution: Run the displayed install command, then wait for ETCD_SERVER_INSTALLED.

**Done when:** the independent `ETCD_SERVER_INSTALLED` validator passes.

## 23. Copy the etcdctl client program into place

**Work on:** `dcs-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which program will you use to ask the cluster for health?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/etcdctl /usr/local/bin/etcdctl
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdctl. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdctl now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program will you use to ask the cluster for health?
2. Hint: The client name ends in ctl, meaning control.
3. Stronger hint: Install /opt/suta/artifacts/etcdctl to /usr/local/bin/etcdctl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDCTL_INSTALLED.

**Done when:** the independent `ETCDCTL_COPIED` validator passes.

## 24. Make the etcdctl client program runnable

**Work on:** `dcs-2` as `ec2-user`

etcdctl sends authenticated health, membership and snapshot requests to etcd.

**Predict first:** Which program will you use to ask the cluster for health?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/etcdctl
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdctl is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program will you use to ask the cluster for health?
2. Hint: The client name ends in ctl, meaning control.
3. Stronger hint: Install /opt/suta/artifacts/etcdctl to /usr/local/bin/etcdctl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDCTL_INSTALLED.

**Done when:** the independent `ETCDCTL_INSTALLED` validator passes.

## 25. Copy the etcdutl recovery program into place

**Work on:** `dcs-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which utility will inspect an offline snapshot later?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/etcdutl /usr/local/bin/etcdutl
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdutl. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdutl now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which utility will inspect an offline snapshot later?
2. Hint: Its name ends in utl, meaning utility.
3. Stronger hint: Install the staged etcdutl file to /usr/local/bin/etcdutl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDUTL_INSTALLED.

**Done when:** the independent `ETCDUTL_COPIED` validator passes.

## 26. Make the etcdutl recovery program runnable

**Work on:** `dcs-2` as `ec2-user`

etcdutl inspects and restores offline etcd data such as snapshots.

**Predict first:** Which utility will inspect an offline snapshot later?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/etcdutl
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdutl is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which utility will inspect an offline snapshot later?
2. Hint: Its name ends in utl, meaning utility.
3. Stronger hint: Install the staged etcdutl file to /usr/local/bin/etcdutl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDUTL_INSTALLED.

**Done when:** the independent `ETCDUTL_INSTALLED` validator passes.

## 27. Create the /etc/etcd directory

**Work on:** `dcs-2` as `ec2-user`

Create /etc/etcd before setting its ownership and permissions.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo mkdir -p /etc/etcd
```

**What the command means:** sudo mkdir -p creates /etc/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and /etc/etcd exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 28. Give root ownership of the /etc/etcd directory

**Work on:** `dcs-2` as `ec2-user`

The root account owns /etc/etcd so the intended process can use this location.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo chown -R root:root /etc/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** /etc/etcd is owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 29. Set permissions on the /etc/etcd directory

**Work on:** `dcs-2` as `ec2-user`

/etc/etcd holds the member configuration and TLS identity files. Mode 0700 lets only the root account that runs this etcd service traverse or list this protected directory.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo chmod 0700 /etc/etcd
```

**What the command means:** chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Expected result:** The command returns without error and /etc/etcd is owned by root with mode 0700.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE` validator passes.

## 30. Create the /var/lib/etcd directory

**Work on:** `dcs-2` as `ec2-user`

Create /var/lib/etcd before setting its ownership and permissions.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo mkdir -p /var/lib/etcd
```

**What the command means:** sudo mkdir -p creates /var/lib/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and /var/lib/etcd exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 31. Give root ownership of the /var/lib/etcd directory

**Work on:** `dcs-2` as `ec2-user`

The root account owns /var/lib/etcd so the intended process can use this location.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo chown -R root:root /var/lib/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** /var/lib/etcd is owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 32. Set permissions on the /var/lib/etcd directory

**Work on:** `dcs-2` as `ec2-user`

etcd must persist quorum state in a root-only directory that starts empty.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo chmod 0700 /var/lib/etcd
```

**What the command means:** chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Expected result:** The command returns without error and /var/lib/etcd remains empty, root-owned, and mode 0700.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE` validator passes.

## 33. Copy the role-bound TLS public certificate into place

**Work on:** `dcs-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why can this file be 0644?

Run this one action:

```bash
sudo cp /opt/suta/handoff/etcd/member.crt /etc/etcd/member.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/etcd/member.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why can this file be 0644?
2. Hint: It contains identity claims and a public key, not the private key.
3. Stronger hint: Install member.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_MEMBER_CERT_INSTALLED.

**Done when:** the independent `ETCD_MEMBER_CERT_COPIED` validator passes.

## 34. Set permissions on the role-bound TLS public certificate

**Work on:** `dcs-2` as `ec2-user`

Peers need this signed public certificate to authenticate the member name and private address.

**Predict first:** Why can this file be 0644?

Run this one action:

```bash
sudo chmod 0644 /etc/etcd/member.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The certificate is installed without printing its contents.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why can this file be 0644?
2. Hint: It contains identity claims and a public key, not the private key.
3. Stronger hint: Install member.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_MEMBER_CERT_INSTALLED.

**Done when:** the independent `ETCD_MEMBER_CERT_INSTALLED` validator passes.

## 35. Copy the etcd trust anchor into place

**Work on:** `dcs-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which CA material belongs here?

Run this one action:

```bash
sudo cp /opt/suta/handoff/etcd/ca.crt /etc/etcd/ca.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/ca.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/etcd/ca.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which CA material belongs here?
2. Hint: Only the certificate used for verification.
3. Stronger hint: Install ca.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_CA_INSTALLED.

**Done when:** the independent `ETCD_CA_COPIED` validator passes.

## 36. Set permissions on the etcd trust anchor

**Work on:** `dcs-2` as `ec2-user`

The member needs the lab CA certificate to verify certificates presented by clients and peers.

**Predict first:** Which CA material belongs here?

Run this one action:

```bash
sudo chmod 0644 /etc/etcd/ca.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The CA certificate is installed without exposing any private key.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which CA material belongs here?
2. Hint: Only the certificate used for verification.
3. Stronger hint: Install ca.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_CA_INSTALLED.

**Done when:** the independent `ETCD_CA_INSTALLED` validator passes.

## 37. Copy the role-bound TLS private key into place

**Work on:** `dcs-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which permission prevents other users from reading the key?

Run this one action:

```bash
sudo cp /opt/suta/handoff/etcd/member.key /etc/etcd/member.key
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.key. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/etcd/member.key now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which permission prevents other users from reading the key?
2. Hint: The owner needs read and write; everyone else needs no access.
3. Stronger hint: That numeric mode is 0600.
4. Solution: Install the key with mode 0600, then install the CA and member certificate in their separately guided steps.

**Done when:** the independent `ETCD_MEMBER_KEY_COPIED` validator passes.

## 38. Set permissions on the role-bound TLS private key

**Work on:** `dcs-2` as `ec2-user`

Mutual TLS must identify this member without exposing its private key.

**Predict first:** Which permission prevents other users from reading the key?

Run this one action:

```bash
sudo chmod 0600 /etc/etcd/member.key
```

**What the command means:** chmod 0600 sets the file's permissions to 600 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The command returns without displaying key material.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which permission prevents other users from reading the key?
2. Hint: The owner needs read and write; everyone else needs no access.
3. Stronger hint: That numeric mode is 0600.
4. Solution: Install the key with mode 0600, then install the CA and member certificate in their separately guided steps.

**Done when:** the independent `ETCD_MEMBER_KEY_INSTALLED` validator passes.

## 39. Configure dcs-2

**Work on:** `dcs-2` as `ec2-user`

Every voting member needs its own identity while sharing the same initial cluster definition.

**Predict first:** What stays common and what changes from dcs-1?

Run this one action:

```bash
sudo vi /etc/systemd/system/etcd.service
```

**What the command means:** Create the dcs-2 unit using the exact role-resolved configuration supplied for this step.

Enter this exact systemd content after SutaBot resolves only the registered role addresses and protected secret fields:

```text
[Unit]
Description=SUTA etcd member
After=network-online.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/etcd --name={{role}} --data-dir=/var/lib/etcd --listen-client-urls=https://{{private_ip}}:2379 --advertise-client-urls=https://{{private_ip}}:2379 --listen-peer-urls=https://{{private_ip}}:2380 --initial-advertise-peer-urls=https://{{private_ip}}:2380 --initial-cluster={{initial_cluster}} --initial-cluster-state=new --initial-cluster-token={{cluster_token}} --client-cert-auth=true --trusted-ca-file=/etc/etcd/ca.crt --cert-file=/etc/etcd/member.crt --key-file=/etc/etcd/member.key --peer-client-cert-auth=true --peer-trusted-ca-file=/etc/etcd/ca.crt --peer-cert-file=/etc/etcd/member.crt --peer-key-file=/etc/etcd/member.key
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

**Expected result:** The saved unit names dcs-2 and uses the common three-member initial cluster.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What stays common and what changes from dcs-1?
2. Hint: The peer list stays common; member name and local addresses change.
3. Stronger hint: Confirm every dcs role appears once in --initial-cluster.
4. Solution: Enter the supplied dcs-2 unit, save, and let the validator inspect it.

**Done when:** the independent `ETCD_MEMBER_2_CONFIGURED` validator passes.

## 40. Copy the etcd server program into place

**Work on:** `dcs-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which program runs the voting member service?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/etcd /usr/local/bin/etcd
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcd. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcd now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program runs the voting member service?
2. Hint: Its filename is simply etcd.
3. Stronger hint: Use mode 0755 and destination /usr/local/bin/etcd.
4. Solution: Run the displayed install command, then wait for ETCD_SERVER_INSTALLED.

**Done when:** the independent `ETCD_SERVER_COPIED` validator passes.

## 41. Make the etcd server program runnable

**Work on:** `dcs-3` as `ec2-user`

The etcd program runs one voting member of the distributed configuration store.

**Predict first:** Which program runs the voting member service?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/etcd
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The command returns to the prompt without an error and /usr/local/bin/etcd is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program runs the voting member service?
2. Hint: Its filename is simply etcd.
3. Stronger hint: Use mode 0755 and destination /usr/local/bin/etcd.
4. Solution: Run the displayed install command, then wait for ETCD_SERVER_INSTALLED.

**Done when:** the independent `ETCD_SERVER_INSTALLED` validator passes.

## 42. Copy the etcdctl client program into place

**Work on:** `dcs-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which program will you use to ask the cluster for health?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/etcdctl /usr/local/bin/etcdctl
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdctl. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdctl now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program will you use to ask the cluster for health?
2. Hint: The client name ends in ctl, meaning control.
3. Stronger hint: Install /opt/suta/artifacts/etcdctl to /usr/local/bin/etcdctl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDCTL_INSTALLED.

**Done when:** the independent `ETCDCTL_COPIED` validator passes.

## 43. Make the etcdctl client program runnable

**Work on:** `dcs-3` as `ec2-user`

etcdctl sends authenticated health, membership and snapshot requests to etcd.

**Predict first:** Which program will you use to ask the cluster for health?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/etcdctl
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdctl is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program will you use to ask the cluster for health?
2. Hint: The client name ends in ctl, meaning control.
3. Stronger hint: Install /opt/suta/artifacts/etcdctl to /usr/local/bin/etcdctl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDCTL_INSTALLED.

**Done when:** the independent `ETCDCTL_INSTALLED` validator passes.

## 44. Copy the etcdutl recovery program into place

**Work on:** `dcs-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which utility will inspect an offline snapshot later?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/etcdutl /usr/local/bin/etcdutl
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdutl. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdutl now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which utility will inspect an offline snapshot later?
2. Hint: Its name ends in utl, meaning utility.
3. Stronger hint: Install the staged etcdutl file to /usr/local/bin/etcdutl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDUTL_INSTALLED.

**Done when:** the independent `ETCDUTL_COPIED` validator passes.

## 45. Make the etcdutl recovery program runnable

**Work on:** `dcs-3` as `ec2-user`

etcdutl inspects and restores offline etcd data such as snapshots.

**Predict first:** Which utility will inspect an offline snapshot later?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/etcdutl
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The command returns to the prompt and /usr/local/bin/etcdutl is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which utility will inspect an offline snapshot later?
2. Hint: Its name ends in utl, meaning utility.
3. Stronger hint: Install the staged etcdutl file to /usr/local/bin/etcdutl with mode 0755.
4. Solution: Run the displayed command and wait for ETCDUTL_INSTALLED.

**Done when:** the independent `ETCDUTL_INSTALLED` validator passes.

## 46. Create the /etc/etcd directory

**Work on:** `dcs-3` as `ec2-user`

Create /etc/etcd before setting its ownership and permissions.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo mkdir -p /etc/etcd
```

**What the command means:** sudo mkdir -p creates /etc/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and /etc/etcd exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 47. Give root ownership of the /etc/etcd directory

**Work on:** `dcs-3` as `ec2-user`

The root account owns /etc/etcd so the intended process can use this location.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo chown -R root:root /etc/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** /etc/etcd is owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 48. Set permissions on the /etc/etcd directory

**Work on:** `dcs-3` as `ec2-user`

/etc/etcd holds the member configuration and TLS identity files. Mode 0700 lets only the root account that runs this etcd service traverse or list this protected directory.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo chmod 0700 /etc/etcd
```

**What the command means:** chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Expected result:** The command returns without error and /etc/etcd is owned by root with mode 0700.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE` validator passes.

## 49. Create the /var/lib/etcd directory

**Work on:** `dcs-3` as `ec2-user`

Create /var/lib/etcd before setting its ownership and permissions.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo mkdir -p /var/lib/etcd
```

**What the command means:** sudo mkdir -p creates /var/lib/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and /var/lib/etcd exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 50. Give root ownership of the /var/lib/etcd directory

**Work on:** `dcs-3` as `ec2-user`

The root account owns /var/lib/etcd so the intended process can use this location.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo chown -R root:root /var/lib/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** /var/lib/etcd is owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 51. Set permissions on the /var/lib/etcd directory

**Work on:** `dcs-3` as `ec2-user`

etcd must persist quorum state in a root-only directory that starts empty.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo chmod 0700 /var/lib/etcd
```

**What the command means:** chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Expected result:** The command returns without error and /var/lib/etcd remains empty, root-owned, and mode 0700.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE` validator passes.

## 52. Copy the role-bound TLS public certificate into place

**Work on:** `dcs-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why can this file be 0644?

Run this one action:

```bash
sudo cp /opt/suta/handoff/etcd/member.crt /etc/etcd/member.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/etcd/member.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why can this file be 0644?
2. Hint: It contains identity claims and a public key, not the private key.
3. Stronger hint: Install member.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_MEMBER_CERT_INSTALLED.

**Done when:** the independent `ETCD_MEMBER_CERT_COPIED` validator passes.

## 53. Set permissions on the role-bound TLS public certificate

**Work on:** `dcs-3` as `ec2-user`

Peers need this signed public certificate to authenticate the member name and private address.

**Predict first:** Why can this file be 0644?

Run this one action:

```bash
sudo chmod 0644 /etc/etcd/member.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The certificate is installed without printing its contents.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why can this file be 0644?
2. Hint: It contains identity claims and a public key, not the private key.
3. Stronger hint: Install member.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_MEMBER_CERT_INSTALLED.

**Done when:** the independent `ETCD_MEMBER_CERT_INSTALLED` validator passes.

## 54. Copy the etcd trust anchor into place

**Work on:** `dcs-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which CA material belongs here?

Run this one action:

```bash
sudo cp /opt/suta/handoff/etcd/ca.crt /etc/etcd/ca.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/ca.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/etcd/ca.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which CA material belongs here?
2. Hint: Only the certificate used for verification.
3. Stronger hint: Install ca.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_CA_INSTALLED.

**Done when:** the independent `ETCD_CA_COPIED` validator passes.

## 55. Set permissions on the etcd trust anchor

**Work on:** `dcs-3` as `ec2-user`

The member needs the lab CA certificate to verify certificates presented by clients and peers.

**Predict first:** Which CA material belongs here?

Run this one action:

```bash
sudo chmod 0644 /etc/etcd/ca.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The CA certificate is installed without exposing any private key.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which CA material belongs here?
2. Hint: Only the certificate used for verification.
3. Stronger hint: Install ca.crt as root:root with mode 0644.
4. Solution: Run the registered install command and require ETCD_CA_INSTALLED.

**Done when:** the independent `ETCD_CA_INSTALLED` validator passes.

## 56. Copy the role-bound TLS private key into place

**Work on:** `dcs-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which permission prevents other users from reading the key?

Run this one action:

```bash
sudo cp /opt/suta/handoff/etcd/member.key /etc/etcd/member.key
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.key. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/etcd/member.key now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which permission prevents other users from reading the key?
2. Hint: The owner needs read and write; everyone else needs no access.
3. Stronger hint: That numeric mode is 0600.
4. Solution: Install the key with mode 0600, then install the CA and member certificate in their separately guided steps.

**Done when:** the independent `ETCD_MEMBER_KEY_COPIED` validator passes.

## 57. Set permissions on the role-bound TLS private key

**Work on:** `dcs-3` as `ec2-user`

Mutual TLS must identify this member without exposing its private key.

**Predict first:** Which permission prevents other users from reading the key?

Run this one action:

```bash
sudo chmod 0600 /etc/etcd/member.key
```

**What the command means:** chmod 0600 sets the file's permissions to 600 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The command returns without displaying key material.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which permission prevents other users from reading the key?
2. Hint: The owner needs read and write; everyone else needs no access.
3. Stronger hint: That numeric mode is 0600.
4. Solution: Install the key with mode 0600, then install the CA and member certificate in their separately guided steps.

**Done when:** the independent `ETCD_MEMBER_KEY_INSTALLED` validator passes.

## 58. Configure dcs-3

**Work on:** `dcs-3` as `ec2-user`

The third voting member completes the odd-sized quorum design.

**Predict first:** Which connections need certificate authentication?

Run this one action:

```bash
sudo vi /etc/systemd/system/etcd.service
```

**What the command means:** Create the dcs-3 unit using the exact role-resolved configuration supplied for this step.

Enter this exact systemd content after SutaBot resolves only the registered role addresses and protected secret fields:

```text
[Unit]
Description=SUTA etcd member
After=network-online.target
Wants=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/etcd --name={{role}} --data-dir=/var/lib/etcd --listen-client-urls=https://{{private_ip}}:2379 --advertise-client-urls=https://{{private_ip}}:2379 --listen-peer-urls=https://{{private_ip}}:2380 --initial-advertise-peer-urls=https://{{private_ip}}:2380 --initial-cluster={{initial_cluster}} --initial-cluster-state=new --initial-cluster-token={{cluster_token}} --client-cert-auth=true --trusted-ca-file=/etc/etcd/ca.crt --cert-file=/etc/etcd/member.crt --key-file=/etc/etcd/member.key --peer-client-cert-auth=true --peer-trusted-ca-file=/etc/etcd/ca.crt --peer-cert-file=/etc/etcd/member.crt --peer-key-file=/etc/etcd/member.key
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

**Expected result:** The saved unit names dcs-3 and contains authenticated client and peer TLS settings.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which connections need certificate authentication?
2. Hint: Both clients and peer members.
3. Stronger hint: Look for the two certificate-authentication flags.
4. Solution: Enter the supplied dcs-3 unit, save it, and let the validator check identity, peers and TLS.

**Done when:** the independent `ETCD_MEMBER_3_CONFIGURED` validator passes.

## 59. Start dcs-1

**Work on:** `dcs-1` as `ec2-user`

dcs-1 can start only after all three initial member configurations pass validation.

**Predict first:** Which prerequisite protects the initial cluster from mismatched peer definitions?

Run this one action:

```bash
sudo systemctl enable --now etcd
```

**What the command means:** enable registers etcd for boot; --now starts the service on dcs-1 immediately.

**Expected result:** The command returns without error and dcs-1 enters its initial member startup.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which prerequisite protects the initial cluster from mismatched peer definitions?
2. Hint: All three configuration validators must pass first.
3. Stronger hint: Confirm the dcs-1 unit names dcs-1 and contains all three peers.
4. Solution: Run the displayed command on dcs-1 and require ETCD_MEMBER_1_STARTED.

**Done when:** the independent `ETCD_MEMBER_1_STARTED` validator passes.

## 60. Start dcs-2

**Work on:** `dcs-2` as `ec2-user`

The second configured voting member allows the initial cluster to reach a majority.

**Predict first:** How many of three voters are needed for a majority?

Run this one action:

```bash
sudo systemctl enable --now etcd
```

**What the command means:** enable registers etcd for boot and starts the service on dcs-2.

**Expected result:** The command returns without error and dcs-2 becomes active.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: How many of three voters are needed for a majority?
2. Hint: dcs-1 and dcs-2 can form two votes.
3. Stronger hint: If startup fails, inspect the dcs-2 journal without changing member identity.
4. Solution: Run the displayed command on dcs-2 and require ETCD_MEMBER_2_STARTED.

**Done when:** the independent `ETCD_MEMBER_2_STARTED` validator passes.

## 61. Start dcs-3

**Work on:** `dcs-3` as `ec2-user`

The third configured voter restores the intended one-member failure tolerance.

**Predict first:** What does the third healthy voter add after quorum already exists?

Run this one action:

```bash
sudo systemctl enable --now etcd
```

**What the command means:** enable registers etcd for boot and starts the service on dcs-3.

**Expected result:** The command returns without error and dcs-3 becomes active.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What does the third healthy voter add after quorum already exists?
2. Hint: It restores redundancy for one future member failure.
3. Stronger hint: Confirm dcs-3 uses its own certificate and name before starting.
4. Solution: Run the displayed command on dcs-3 and require ETCD_MEMBER_3_STARTED.

**Done when:** the independent `ETCD_MEMBER_3_STARTED` validator passes.

## 62. Prove quorum over mutual TLS

**Work on:** `dcs-1` as `ec2-user`

A running process is weaker evidence than three reachable voting members that can commit.

**Predict first:** How many healthy endpoint lines prove the complete cluster?

Run this one action:

```bash
sudo /usr/local/bin/etcdctl --endpoints=https://dcs-1:2379,https://dcs-2:2379,https://dcs-3:2379 --cacert=/etc/etcd/ca.crt --cert=/etc/etcd/member.crt --key=/etc/etcd/member.key endpoint health
```

**What the command means:** etcdctl contacts every named endpoint with the member certificate and asks each endpoint to commit a health proposal.

**Expected result:** Three lines report healthy endpoints and successful proposal commits.

**Safety:** This is a read-only observation.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: How many healthy endpoint lines prove the complete cluster?
2. Hint: There are three voting members.
3. Stronger hint: A SAN mismatch means the endpoint name is not covered by the certificate.
4. Solution: Run the exact command and require three healthy results before continuing.

**Done when:** the independent `ETCD_QUORUM_BUILT` validator passes.

## 63. Create the postgres operating-system account on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

PostgreSQL and Patroni must run as a dedicated account instead of root.

**Predict first:** Why should the database process not run as root?

Run this one action:

```bash
sudo useradd --system --home-dir /opt/pgsql --shell /bin/bash postgres
```

**What the command means:** useradd creates a system account named postgres with /opt/pgsql as its home and bash for controlled administration.

**Expected result:** The command returns without error and the postgres account exists without a login password.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why should the database process not run as root?
2. Hint: Use least privilege and separate operating-system ownership.
3. Stronger hint: The account name is postgres and its home is /opt/pgsql.
4. Solution: Run the displayed useradd command and require PG_OS_USER_1_CREATED.

**Done when:** the independent `PG_OS_USER_1_CREATED` validator passes.

## 64. Install PostgreSQL on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

Patroni manages PostgreSQL but does not replace the PostgreSQL server binaries.

**Predict first:** Which program proves the server binaries were installed?

Run this one action:

```bash
sudo tar -xzf /opt/suta/artifacts/postgresql-16.15-centos9-amd64.tar.gz -C /
```

**What the command means:** tar extracts the verified PostgreSQL filesystem archive beneath its approved absolute paths.

**Expected result:** The command returns without error and /opt/pgsql/bin/postgres exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which program proves the server binaries were installed?
2. Hint: Look for postgres under /opt/pgsql/bin.
3. Stronger hint: The validator reads the binary version without starting PostgreSQL.
4. Solution: Extract the verified archive to / and require POSTGRESQL_SOFTWARE_1_INSTALLED.

**Done when:** the independent `POSTGRESQL_SOFTWARE_1_INSTALLED` validator passes.

## 65. Create the postgresql-layout-1 directories

**Work on:** `pg-ha-1` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Which four operational purposes need paths?

Run this one action:

```bash
sudo mkdir -p /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```

**What the command means:** sudo mkdir -p creates /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which four operational purposes need paths?
2. Hint: Data, WAL, backups and logs.
3. Stronger hint: Every path is under /opt/pgsql and owned by postgres.
4. Solution: Run the displayed command and require PG_LAYOUT_1_CREATED with no PG_VERSION.

**Done when:** the independent `PG_LAYOUT_1_DIRS_MADE` validator passes.

## 66. Give postgres ownership of the postgresql-layout-1 directories

**Work on:** `pg-ha-1` as `ec2-user`

The postgres service must own these directories to write into them.

**Predict first:** Which four operational purposes need paths?

Run this one action:

```bash
sudo chown -R postgres:postgres /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by postgres.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which four operational purposes need paths?
2. Hint: Data, WAL, backups and logs.
3. Stronger hint: Every path is under /opt/pgsql and owned by postgres.
4. Solution: Run the displayed command and require PG_LAYOUT_1_CREATED with no PG_VERSION.

**Done when:** the independent `PG_LAYOUT_1_DIRS_OWNED` validator passes.

## 67. Lock down the postgresql-layout-1 directory permissions

**Work on:** `pg-ha-1` as `ec2-user`

Data, WAL, backup and log paths have different operational purposes.

**Predict first:** Which four operational purposes need paths?

Run this one action:

```bash
sudo chmod 0700 /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```

**What the command means:** chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Expected result:** All four directories exist with postgres ownership and mode 0700; PGDATA remains uninitialized.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which four operational purposes need paths?
2. Hint: Data, WAL, backups and logs.
3. Stronger hint: Every path is under /opt/pgsql and owned by postgres.
4. Solution: Run the displayed command and require PG_LAYOUT_1_CREATED with no PG_VERSION.

**Done when:** the independent `PG_LAYOUT_1_CREATED` validator passes.

## 68. Create the postgres operating-system account on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

Every PostgreSQL member uses the same dedicated operating-system identity.

**Predict first:** Which layer owns this account?

Run this one action:

```bash
sudo useradd --system --home-dir /opt/pgsql --shell /bin/bash postgres
```

**What the command means:** Create the postgres system account on pg-ha-2 before extracting files owned by it.

**Expected result:** The postgres account exists on pg-ha-2.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which layer owns this account?
2. Hint: It is a Linux operating-system account.
3. Stronger hint: Use the exact account name and home used on pg-ha-1.
4. Solution: Run the displayed command and require PG_OS_USER_2_CREATED.

**Done when:** the independent `PG_OS_USER_2_CREATED` validator passes.

## 69. Install PostgreSQL on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

A future replica needs the exact same PostgreSQL minor-version binaries as the leader.

**Predict first:** Why must the replica use the same minor version?

Run this one action:

```bash
sudo tar -xzf /opt/suta/artifacts/postgresql-16.15-centos9-amd64.tar.gz -C /
```

**What the command means:** Extract the verified PostgreSQL archive into the approved filesystem paths on pg-ha-2.

**Expected result:** PostgreSQL 16.15 is installed without initializing a cluster.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why must the replica use the same minor version?
2. Hint: Keep executable and on-disk expectations compatible.
3. Stronger hint: The validator checks /opt/pgsql/bin/postgres --version.
4. Solution: Extract the archive and require POSTGRESQL_SOFTWARE_2_INSTALLED.

**Done when:** the independent `POSTGRESQL_SOFTWARE_2_INSTALLED` validator passes.

## 70. Create the postgresql-layout-2 directories

**Work on:** `pg-ha-2` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** What file would prove PGDATA was already initialized?

Run this one action:

```bash
sudo mkdir -p /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```

**What the command means:** sudo mkdir -p creates /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What file would prove PGDATA was already initialized?
2. Hint: Its name begins with PG and records the major version.
3. Stronger hint: The validator requires PG_VERSION to be absent.
4. Solution: Create the four paths and require PG_LAYOUT_2_CREATED.

**Done when:** the independent `PG_LAYOUT_2_DIRS_MADE` validator passes.

## 71. Give postgres ownership of the postgresql-layout-2 directories

**Work on:** `pg-ha-2` as `ec2-user`

The postgres service must own these directories to write into them.

**Predict first:** What file would prove PGDATA was already initialized?

Run this one action:

```bash
sudo chown -R postgres:postgres /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by postgres.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What file would prove PGDATA was already initialized?
2. Hint: Its name begins with PG and records the major version.
3. Stronger hint: The validator requires PG_VERSION to be absent.
4. Solution: Create the four paths and require PG_LAYOUT_2_CREATED.

**Done when:** the independent `PG_LAYOUT_2_DIRS_OWNED` validator passes.

## 72. Lock down the postgresql-layout-2 directory permissions

**Work on:** `pg-ha-2` as `ec2-user`

The replica needs the same protected operational paths before it can clone.

**Predict first:** What file would prove PGDATA was already initialized?

Run this one action:

```bash
sudo chmod 0700 /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```

**What the command means:** chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Expected result:** All four directories exist and /opt/pgsql/data has no PG_VERSION.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What file would prove PGDATA was already initialized?
2. Hint: Its name begins with PG and records the major version.
3. Stronger hint: The validator requires PG_VERSION to be absent.
4. Solution: Create the four paths and require PG_LAYOUT_2_CREATED.

**Done when:** the independent `PG_LAYOUT_2_CREATED` validator passes.

## 73. Create the postgres operating-system account on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

The third database member also needs the dedicated least-privilege process identity.

**Predict first:** Why keep process ownership consistent across members?

Run this one action:

```bash
sudo useradd --system --home-dir /opt/pgsql --shell /bin/bash postgres
```

**What the command means:** Create the postgres system account on pg-ha-3.

**Expected result:** The postgres account exists on pg-ha-3.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why keep process ownership consistent across members?
2. Hint: Configuration, files and service units expect the same owner.
3. Stronger hint: The validator checks the account and /opt/pgsql home.
4. Solution: Run the displayed command and require PG_OS_USER_3_CREATED.

**Done when:** the independent `PG_OS_USER_3_CREATED` validator passes.

## 74. Install PostgreSQL on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

The second replica must match the leader and first replica software version.

**Predict first:** Which manager will initialize or clone PGDATA later?

Run this one action:

```bash
sudo tar -xzf /opt/suta/artifacts/postgresql-16.15-centos9-amd64.tar.gz -C /
```

**What the command means:** Extract the same verified PostgreSQL archive on pg-ha-3.

**Expected result:** PostgreSQL 16.15 is installed without an initialized PGDATA.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which manager will initialize or clone PGDATA later?
2. Hint: Patroni owns that lifecycle.
3. Stronger hint: Only verify the binary version at this step.
4. Solution: Extract the archive and require POSTGRESQL_SOFTWARE_3_INSTALLED.

**Done when:** the independent `POSTGRESQL_SOFTWARE_3_INSTALLED` validator passes.

## 75. Create the postgresql-layout-3 directories

**Work on:** `pg-ha-3` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** What must remain absent before Patroni joins this replica?

Run this one action:

```bash
sudo mkdir -p /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```

**What the command means:** sudo mkdir -p creates /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What must remain absent before Patroni joins this replica?
2. Hint: The PostgreSQL version marker inside PGDATA.
3. Stronger hint: Check /opt/pgsql/data/PG_VERSION is absent.
4. Solution: Create the four paths and require PG_LAYOUT_3_CREATED.

**Done when:** the independent `PG_LAYOUT_3_DIRS_MADE` validator passes.

## 76. Give postgres ownership of the postgresql-layout-3 directories

**Work on:** `pg-ha-3` as `ec2-user`

The postgres service must own these directories to write into them.

**Predict first:** What must remain absent before Patroni joins this replica?

Run this one action:

```bash
sudo chown -R postgres:postgres /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by postgres.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What must remain absent before Patroni joins this replica?
2. Hint: The PostgreSQL version marker inside PGDATA.
3. Stronger hint: Check /opt/pgsql/data/PG_VERSION is absent.
4. Solution: Create the four paths and require PG_LAYOUT_3_CREATED.

**Done when:** the independent `PG_LAYOUT_3_DIRS_OWNED` validator passes.

## 77. Lock down the postgresql-layout-3 directory permissions

**Work on:** `pg-ha-3` as `ec2-user`

The second replica needs the same protected layout and empty PGDATA.

**Predict first:** What must remain absent before Patroni joins this replica?

Run this one action:

```bash
sudo chmod 0700 /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```

**What the command means:** chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Expected result:** All paths exist with postgres ownership and PG_VERSION is absent.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What must remain absent before Patroni joins this replica?
2. Hint: The PostgreSQL version marker inside PGDATA.
3. Stronger hint: Check /opt/pgsql/data/PG_VERSION is absent.
4. Solution: Create the four paths and require PG_LAYOUT_3_CREATED.

**Done when:** the independent `PG_LAYOUT_3_CREATED` validator passes.

## 78. Create the /opt/patroni and /etc/patroni directories

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Prepare · 1 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Create separate homes for Patroni’s software and configuration.

```bash
sudo mkdir -p /opt/patroni /etc/patroni
```

**Prove it worked**

```bash
ls -ld /opt/patroni /etc/patroni
```

Look for: 2 lines, one per directory, each starting with d

<details>
<summary>Full explanation</summary>

Create /opt/patroni and /etc/patroni before setting its ownership and permissions.

sudo mkdir -p creates /opt/patroni /etc/patroni (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected result: The command returns to the prompt and /opt/patroni and /etc/patroni exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which account runs Patroni?

</details>

<details>
<summary>hint</summary>

Use the same postgres OS account that owns PostgreSQL.

</details>

<details>
<summary>stronger hint</summary>

Both /opt/patroni and /etc/patroni need postgres ownership.

</details>

<details>
<summary>solution</summary>

Run the displayed command and require PATRONI_DIRS_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_DIRS_DIRS_MADE` validator passes and the required learner-run check is observed.

## 79. Give postgres ownership of the /opt/patroni and /etc/patroni directories

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Prepare · 2 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Give the postgres service account ownership of both locations.

```bash
sudo chown -R postgres:postgres /opt/patroni /etc/patroni
```

**Prove it worked**

```bash
ls -ld /opt/patroni /etc/patroni
```

Look for: owner postgres and group postgres on every line

<details>
<summary>Full explanation</summary>

The postgres account owns /opt/patroni and /etc/patroni so the intended process can use this location.

chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected result: /opt/patroni and /etc/patroni is owned by postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which account runs Patroni?

</details>

<details>
<summary>hint</summary>

Use the same postgres OS account that owns PostgreSQL.

</details>

<details>
<summary>stronger hint</summary>

Both /opt/patroni and /etc/patroni need postgres ownership.

</details>

<details>
<summary>solution</summary>

Run the displayed command and require PATRONI_DIRS_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_DIRS_DIRS_OWNED` validator passes and the required learner-run check is observed.

## 80. Set permissions on the /opt/patroni and /etc/patroni directories

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Prepare · 3 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Set who can enter and change Patroni’s directories.

```bash
sudo chmod 0750 /opt/patroni /etc/patroni
```

**Think first · optional:** After chmod 0750, who can write to these directories?

- The owner
- The owner and group
- Everyone who can enter them

**Prove it worked**

```bash
ls -ld /opt/patroni /etc/patroni
```

Look for: each line reading drwxr-x---

<details>
<summary>Compare your prediction with the check</summary>

Read the owner/group/others groups in drwxr-x---.

If the listing has those bits, the owner has write permission. Group members may read and traverse, but do not receive write permission from this mode.

If the bits differ, use the actual listing to identify which permission group differs. Do not infer success from the command returning.

The directory’s owner and group are separate facts to inspect.

This reflection does not mark the step complete.

</details>

<details>
<summary>Full explanation</summary>

Patroni software and protected configuration need explicit postgres-owned locations.

chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

ls -ld shows the directory itself with its permission bits in the first column. Mode 0750 must appear as drwxr-x---; anything else means the chmod did not apply.

Expected result: Both directories exist with postgres ownership and mode 0750.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which account runs Patroni?

</details>

<details>
<summary>hint</summary>

Use the same postgres OS account that owns PostgreSQL.

</details>

<details>
<summary>stronger hint</summary>

Both /opt/patroni and /etc/patroni need postgres ownership.

</details>

<details>
<summary>solution</summary>

Run the displayed command and require PATRONI_DIRS_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_DIRS_CREATED` validator passes and the required learner-run check is observed.

## 81. Create the /var/run/postgresql directory

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Prepare · 4 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Create the directory for local PostgreSQL connections.

```bash
sudo mkdir -p /var/run/postgresql
```

**Prove it worked**

```bash
ls -ld /var/run/postgresql
```

Look for: one line starting with d

<details>
<summary>Full explanation</summary>

Create /var/run/postgresql before setting its ownership and permissions.

sudo mkdir -p creates /var/run/postgresql (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected result: The command returns to the prompt and /var/run/postgresql exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Is this directory permanent database storage?

</details>

<details>
<summary>hint</summary>

It holds runtime socket files, not table data.

</details>

<details>
<summary>stronger hint</summary>

The path is /var/run/postgresql.

</details>

<details>
<summary>solution</summary>

Create the directory and require PATRONI_SOCKET_DIR_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_MADE` validator passes and the required learner-run check is observed.

## 82. Give postgres ownership of the /var/run/postgresql directory

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Prepare · 5 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Let postgres own the directory where it creates its local socket.

```bash
sudo chown -R postgres:postgres /var/run/postgresql
```

**Prove it worked**

```bash
ls -ld /var/run/postgresql
```

Look for: owner postgres and group postgres on the line

<details>
<summary>Full explanation</summary>

The postgres account owns /var/run/postgresql so the intended process can use this location.

chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected result: /var/run/postgresql is owned by postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Is this directory permanent database storage?

</details>

<details>
<summary>hint</summary>

It holds runtime socket files, not table data.

</details>

<details>
<summary>stronger hint</summary>

The path is /var/run/postgresql.

</details>

<details>
<summary>solution</summary>

Create the directory and require PATRONI_SOCKET_DIR_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_OWNED` validator passes and the required learner-run check is observed.

## 83. Set permissions on the /var/run/postgresql directory

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Prepare · 6 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Allow local clients to enter the socket directory.

```bash
sudo chmod 0755 /var/run/postgresql
```

**Prove it worked**

```bash
ls -ld /var/run/postgresql
```

Look for: the first column reading drwxr-xr-x

<details>
<summary>Full explanation</summary>

Local clients and Patroni need a writable runtime location for the Unix socket.

chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

ls -ld shows the directory itself with its permission bits in the first column. Mode 0755 must appear as drwxr-xr-x; anything else means the chmod did not apply.

Expected result: /var/run/postgresql exists with postgres ownership.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Is this directory permanent database storage?

</details>

<details>
<summary>hint</summary>

It holds runtime socket files, not table data.

</details>

<details>
<summary>stronger hint</summary>

The path is /var/run/postgresql.

</details>

<details>
<summary>solution</summary>

Create the directory and require PATRONI_SOCKET_DIR_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_SOCKET_DIR_CREATED` validator passes and the required learner-run check is observed.

## 84. Install Patroni on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Prepare · 7 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Install the pinned Patroni runtime and inspect its entry point.

```bash
sudo tar -xzf /opt/suta/artifacts/patroni-4.1.4-python39-centos9-amd64.tar.gz -C /opt/patroni --strip-components=1
```

**Think first · optional:** What can the file listing establish?

- The entry point exists and has execute bits
- A leader has been elected
- Mattermost can write data

**Prove it worked**

```bash
sudo ls -l /opt/patroni/bin/patroni
```

Look for: an executable file (-rwxr-xr-x) at /opt/patroni/bin/patroni

<details>
<summary>Compare your prediction with the check</summary>

Read the path and permission bits in the ls output.

If the entry point exists with execute bits, the extraction created that file.

If the file is missing, inspect the extraction path before continuing.

A file listing does not run Patroni or prove that its Python dependencies load.

This reflection does not mark the step complete.

</details>

<details>
<summary>Full explanation</summary>

Each PostgreSQL node needs the same pinned Patroni runtime.

tar extracts the verified Patroni runtime into the prepared directory and removes the archive's outer folder.

tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected result: Patroni 4.1.4 Python modules exist under /opt/patroni.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why install the same version on all members?

</details>

<details>
<summary>hint</summary>

Cluster behavior must not depend on mixed Patroni code.

</details>

<details>
<summary>stronger hint</summary>

The locked version is 4.1.4.

</details>

<details>
<summary>solution</summary>

Extract the staged archive and require PATRONI_SOFTWARE_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_SOFTWARE_INSTALLED` validator passes and the required learner-run check is observed.

## 85. Copy the etcd CA certificate on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Connect securely · 1 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Place the trust certificate Patroni will use to check etcd’s identity.

```bash
sudo cp /opt/suta/handoff/patroni/ca.crt /etc/patroni/etcd-ca.crt
```

**Prove it worked**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```

Look for: one line ending in /etc/patroni/etcd-ca.crt with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-ca.crt. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/patroni/etcd-ca.crt now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does a CA certificate contain the CA private key?

</details>

<details>
<summary>hint</summary>

A .crt file is public verification material.

</details>

<details>
<summary>stronger hint</summary>

The destination is /etc/patroni/etcd-ca.crt.

</details>

<details>
<summary>solution</summary>

Install the CA certificate and require PATRONI_CA_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CA_COPIED` validator passes and the required learner-run check is observed.

## 86. Set permissions on the etcd CA certificate on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Connect securely · 2 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Set mode 644 on /etc/patroni/etcd-ca.crt without displaying its contents.

```bash
sudo chmod 0644 /etc/patroni/etcd-ca.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-ca.crt
```

Look for: the mode field 644 and path /etc/patroni/etcd-ca.crt

<details>
<summary>Full explanation</summary>

The permissions decide who may read this file before ownership is handed to postgres.

chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: /etc/patroni/etcd-ca.crt now has mode 644.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does a CA certificate contain the CA private key?

</details>

<details>
<summary>hint</summary>

A .crt file is public verification material.

</details>

<details>
<summary>stronger hint</summary>

The destination is /etc/patroni/etcd-ca.crt.

</details>

<details>
<summary>solution</summary>

Install the CA certificate and require PATRONI_CA_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CA_MODE_SET` validator passes and the required learner-run check is observed.

## 87. Give postgres ownership of the etcd CA certificate on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Connect securely · 3 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Give the postgres service account the required access to /etc/patroni/etcd-ca.crt.

```bash
sudo chown postgres:postgres /etc/patroni/etcd-ca.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-ca.crt
```

Look for: postgres postgres 644 /etc/patroni/etcd-ca.crt

<details>
<summary>Full explanation</summary>

Patroni must verify that it is talking to the assigned etcd cluster.

chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: The CA certificate is readable by Patroni and contains no private key.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does a CA certificate contain the CA private key?

</details>

<details>
<summary>hint</summary>

A .crt file is public verification material.

</details>

<details>
<summary>stronger hint</summary>

The destination is /etc/patroni/etcd-ca.crt.

</details>

<details>
<summary>solution</summary>

Install the CA certificate and require PATRONI_CA_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CA_INSTALLED` validator passes and the required learner-run check is observed.

## 88. Copy Patroni's etcd client certificate on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Connect securely · 4 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Place the certificate Patroni presents as its client identity.

```bash
sudo cp /opt/suta/handoff/patroni/client.crt /etc/patroni/etcd-client.crt
```

**Prove it worked**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```

Look for: one line ending in /etc/patroni/etcd-client.crt with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.crt. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/patroni/etcd-client.crt now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which side presents this certificate?

</details>

<details>
<summary>hint</summary>

Patroni is the client of etcd.

</details>

<details>
<summary>stronger hint</summary>

This is public identity material; the private key is handled next.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_CERT_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_CERT_COPIED` validator passes and the required learner-run check is observed.

## 89. Set permissions on Patroni's etcd client certificate on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Connect securely · 5 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Set mode 644 on /etc/patroni/etcd-client.crt without displaying its contents.

```bash
sudo chmod 0644 /etc/patroni/etcd-client.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.crt
```

Look for: the mode field 644 and path /etc/patroni/etcd-client.crt

<details>
<summary>Full explanation</summary>

The permissions decide who may read this file before ownership is handed to postgres.

chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: /etc/patroni/etcd-client.crt now has mode 644.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which side presents this certificate?

</details>

<details>
<summary>hint</summary>

Patroni is the client of etcd.

</details>

<details>
<summary>stronger hint</summary>

This is public identity material; the private key is handled next.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_CERT_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_CERT_MODE_SET` validator passes and the required learner-run check is observed.

## 90. Give postgres ownership of Patroni's etcd client certificate on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Connect securely · 6 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Give the postgres service account the required access to /etc/patroni/etcd-client.crt.

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.crt
```

Look for: postgres postgres 644 /etc/patroni/etcd-client.crt

<details>
<summary>Full explanation</summary>

etcd mutual TLS also verifies Patroni's client identity.

chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: The signed client certificate is postgres-owned and mode 0644.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which side presents this certificate?

</details>

<details>
<summary>hint</summary>

Patroni is the client of etcd.

</details>

<details>
<summary>stronger hint</summary>

This is public identity material; the private key is handled next.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_CERT_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_CERT_INSTALLED` validator passes and the required learner-run check is observed.

## 91. Copy Patroni's protected etcd client key on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Connect securely · 7 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Place the private key used with Patroni’s client certificate.

```bash
sudo cp /opt/suta/handoff/patroni/client.key /etc/patroni/etcd-client.key
```

**Prove it worked**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```

Look for: one line ending in /etc/patroni/etcd-client.key with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.key. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/patroni/etcd-client.key now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file more restricted than the certificate?

</details>

<details>
<summary>hint</summary>

Anyone holding the private key can impersonate the client.

</details>

<details>
<summary>stronger hint</summary>

Use mode 0600 and never run cat on it.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_KEY_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_KEY_COPIED` validator passes and the required learner-run check is observed.

## 92. Set permissions on Patroni's protected etcd client key on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Connect securely · 8 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Set mode 600 on /etc/patroni/etcd-client.key without displaying its contents.

```bash
sudo chmod 0600 /etc/patroni/etcd-client.key
```

**Think first · optional:** Why is this file set to 0600 rather than 0644?

- It is a private key
- It is an executable program
- All TLS files need 0600

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.key
```

Look for: the mode field 600 and path /etc/patroni/etcd-client.key

<details>
<summary>Compare your prediction with the check</summary>

Inspect -rw------- in the metadata listing without displaying the key.

If those bits are present, the file mode grants read/write to its owner and no access to the group or others.

If the mode is different, the required key-permission state has not been established.

The ownership step still matters: Patroni needs its service account to own the key.

This reflection does not mark the step complete.

</details>

<details>
<summary>Full explanation</summary>

The permissions decide who may read this file before ownership is handed to postgres.

chmod 0600 sets the file's permissions to 600 (owner read/write, group/others read - or owner-only for a private key).

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: /etc/patroni/etcd-client.key now has mode 600.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file more restricted than the certificate?

</details>

<details>
<summary>hint</summary>

Anyone holding the private key can impersonate the client.

</details>

<details>
<summary>stronger hint</summary>

Use mode 0600 and never run cat on it.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_KEY_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_KEY_MODE_SET` validator passes and the required learner-run check is observed.

## 93. Give postgres ownership of Patroni's protected etcd client key on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Connect securely · 9 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Give the postgres service account the required access to /etc/patroni/etcd-client.key.

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.key
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.key
```

Look for: postgres postgres 600 /etc/patroni/etcd-client.key

<details>
<summary>Full explanation</summary>

The private key proves possession of the client identity and must not be exposed.

chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: The command shows no key material and the destination mode is 0600.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file more restricted than the certificate?

</details>

<details>
<summary>hint</summary>

Anyone holding the private key can impersonate the client.

</details>

<details>
<summary>stronger hint</summary>

Use mode 0600 and never run cat on it.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_KEY_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_KEY_INSTALLED` validator passes and the required learner-run check is observed.

## 94. Copy the Patroni launcher on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 1 of 30**

Set up the launchers, service definition, and identity of each member.

Put the launcher for the Patroni manager in place.

```bash
sudo cp /opt/suta/handoff/patroni/patroni /usr/local/bin/patroni
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patroni
```

Look for: one line ending in /usr/local/bin/patroni with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patroni. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /usr/local/bin/patroni now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why use a wrapper instead of a floating pip command?

</details>

<details>
<summary>hint</summary>

It binds systemd to the pinned runtime path.

</details>

<details>
<summary>stronger hint</summary>

The destination is /usr/local/bin/patroni.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_WRAPPER_COPIED` validator passes and the required learner-run check is observed.

## 95. Make the Patroni launcher on pg-ha-1 runnable

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 2 of 30**

Set up the launchers, service definition, and identity of each member.

Make the launcher executable, then inspect its permissions.

```bash
sudo chmod 0755 /usr/local/bin/patroni
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patroni
```

Look for: the first column reading -rwxr-xr-x

<details>
<summary>Full explanation</summary>

The pinned Python runtime needs one stable command path for systemd.

chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected result: /usr/local/bin/patroni is executable and reports Patroni 4.1.4.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why use a wrapper instead of a floating pip command?

</details>

<details>
<summary>hint</summary>

It binds systemd to the pinned runtime path.

</details>

<details>
<summary>stronger hint</summary>

The destination is /usr/local/bin/patroni.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_WRAPPER_INSTALLED` validator passes and the required learner-run check is observed.

## 96. Copy the patronictl launcher on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 3 of 30**

Set up the launchers, service definition, and identity of each member.

Install the launcher for the cluster administration tool.

```bash
sudo cp /opt/suta/handoff/patroni/patronictl /usr/local/bin/patronictl
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patronictl
```

Look for: one line ending in /usr/local/bin/patronictl with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patronictl. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /usr/local/bin/patronictl now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which tool runs the service and which tool operates the cluster?

</details>

<details>
<summary>hint</summary>

patroni runs; patronictl controls and inspects.

</details>

<details>
<summary>stronger hint</summary>

The operator command ends in ctl.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONICTL_WRAPPER_COPIED` validator passes and the required learner-run check is observed.

## 97. Make the patronictl launcher on pg-ha-1 runnable

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 4 of 30**

Set up the launchers, service definition, and identity of each member.

Make the launcher executable, then inspect its permissions.

```bash
sudo chmod 0755 /usr/local/bin/patronictl
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patronictl
```

Look for: the first column reading -rwxr-xr-x

<details>
<summary>Full explanation</summary>

Operators need a stable absolute path for cluster inspection and planned operations.

chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected result: /usr/local/bin/patronictl is executable.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which tool runs the service and which tool operates the cluster?

</details>

<details>
<summary>hint</summary>

patroni runs; patronictl controls and inspects.

</details>

<details>
<summary>stronger hint</summary>

The operator command ends in ctl.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONICTL_WRAPPER_INSTALLED` validator passes and the required learner-run check is observed.

## 98. Copy the Patroni systemd unit on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 5 of 30**

Set up the launchers, service definition, and identity of each member.

Give systemd the definition it needs to start Patroni.

```bash
sudo cp /opt/suta/handoff/patroni/patroni.service /etc/systemd/system/patroni.service
```

**Prove it worked**

```bash
ls -l /etc/systemd/system/patroni.service
```

Look for: one line ending in /etc/systemd/system/patroni.service with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/patroni.service. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/systemd/system/patroni.service now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which process should systemd start?

</details>

<details>
<summary>hint</summary>

Patroni owns PostgreSQL startup in this cluster.

</details>

<details>
<summary>stronger hint</summary>

ExecStart must call /usr/local/bin/patroni.

</details>

<details>
<summary>solution</summary>

Install the unit and require PATRONI_UNIT_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_UNIT_COPIED` validator passes and the required learner-run check is observed.

## 99. Set permissions on the Patroni systemd unit on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 6 of 30**

Set up the launchers, service definition, and identity of each member.

Set read access on the service definition.

```bash
sudo chmod 0644 /etc/systemd/system/patroni.service
```

**Prove it worked**

```bash
ls -l /etc/systemd/system/patroni.service
```

Look for: the first column reading -rw-r--r--

<details>
<summary>Full explanation</summary>

systemd must run Patroni as the owner of PostgreSQL and recreate its temporary socket directory after every reboot.

chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected result: The unit parses, owns /run/postgresql and starts Patroni with /etc/patroni/patroni.yml.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which process should systemd start?

</details>

<details>
<summary>hint</summary>

Patroni owns PostgreSQL startup in this cluster.

</details>

<details>
<summary>stronger hint</summary>

ExecStart must call /usr/local/bin/patroni and RuntimeDirectory must name postgresql.

</details>

<details>
<summary>solution</summary>

Install the unit and require PATRONI_UNIT_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_UNIT_CREATED` validator passes and the required learner-run check is observed.

## 100. Reload systemd on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 7 of 30**

Set up the launchers, service definition, and identity of each member.

Ask systemd to reread its service definitions.

```bash
sudo systemctl daemon-reload
```

**Prove it worked**

```bash
systemctl cat patroni
```

Look for: # /etc/systemd/system/patroni.service followed by [Unit]

<details>
<summary>Full explanation</summary>

systemd does not use a newly installed unit until its manager configuration is reloaded.

daemon-reload asks systemd to reread unit files without starting Patroni.

systemctl cat prints the unit file exactly as systemd loaded it. If systemd shows your file here, the daemon-reload picked it up; 'No files found' means it did not.

Expected result: The command returns to the prompt and Patroni remains inactive.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does daemon-reload start Patroni?

</details>

<details>
<summary>hint</summary>

It rereads definitions only.

</details>

<details>
<summary>stronger hint</summary>

The service must stay inactive until its ordered start step.

</details>

<details>
<summary>solution</summary>

Reload systemd and require PATRONI_SYSTEMD_RELOADED.

</details>

</details>

**Done when:** the independent `PATRONI_SYSTEMD_RELOADED` validator passes and the required learner-run check is observed.

## 101. Configure Patroni on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 8 of 30**

Set up the launchers, service definition, and identity of each member.

Save this member’s generated identity and cluster configuration.

```bash
sudo vi /etc/patroni/patroni.yml
```

Use this node's generated yaml template. Protected values come from SutaBot; never paste them into Chat.

```text
scope: {{cluster_scope}}
namespace: /service/
name: {{role}}
restapi:
  listen: {{private_ip}}:8008
  connect_address: {{private_ip}}:8008
etcd3:
  hosts: {{etcd_hosts}}
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
{{pg_hba_exact_nodes}}
postgresql:
  listen: {{private_ip}}:5432
  connect_address: {{private_ip}}:5432
  data_dir: /opt/pgsql/data
  bin_dir: /opt/pgsql/bin
  pgpass: /etc/patroni/pgpass
  authentication:
    superuser:
      username: postgres
      password: {{secret:postgres_superuser}}
    replication:
      username: replicator
      password: {{secret:replication}}
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

**Think first · optional:** Which setting should identify a different member on each node?

- name
- scope
- namespace

**Prove it worked**

```bash
sudo grep -n -E "^(scope|name|restapi|etcd3|postgresql):" /etc/patroni/patroni.yml
```

Look for: the scope, name, restapi, etcd3 and postgresql top-level keys, each on its own numbered line

<details>
<summary>Compare your prediction with the check</summary>

Read name: pg-ha-1 and the assigned scope in the narrow identity check.

If this member name and scope match the assigned configuration, the visible identity fields are present.

If a member name belongs to another node, return to this node’s generated template and inspect that mismatch.

A text match does not parse the complete YAML or validate connectivity.

This reflection does not mark the step complete.

</details>

<details>
<summary>Full explanation</summary>

The first Patroni member defines the cluster scope, DCS transport, bootstrap rules and local PostgreSQL identity.

Open the generated pg-ha-1 Patroni YAML in vi, replace the whole file, and save it. This step validates the YAML and cluster settings; the next two steps set its service ownership and protected mode.

grep -E matches several patterns at once; -n adds line numbers. Every top-level section of patroni.yml must be present. A missing key means the file was saved incomplete.

Expected result: The saved configuration passes YAML, secret-permission and Patroni contract validation.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which fields identify this cluster and this member?

</details>

<details>
<summary>hint</summary>

Find scope and name near the top.

</details>

<details>
<summary>stronger hint</summary>

Confirm HTTPS etcd endpoints, /opt/pgsql/data, checksums, slots, rewind and SCRAM rules.

</details>

<details>
<summary>solution</summary>

Enter the supplied pg-ha-1 configuration and save; the validator checks structure without exposing passwords.

</details>

</details>

**Done when:** the independent `PATRONI_MEMBER_1_CONFIGURED` validator passes and the required learner-run check is observed.

## 102. Give postgres ownership of the Patroni configuration on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 9 of 30**

Set up the launchers, service definition, and identity of each member.

Give the Patroni service account ownership of its saved configuration.

```bash
sudo chown postgres:postgres /etc/patroni/patroni.yml
```

**Prove it worked**

```bash
sudo stat -c '%A %U %G' /etc/patroni/patroni.yml
```

Look for: postgres postgres as the final two fields

<details>
<summary>Full explanation</summary>

Patroni runs as postgres, so its service account must own the configuration file it reads.

chown sets the saved configuration file owner and group to the postgres service account.

stat prints only the symbolic mode, owner and group. The owner and group must both read postgres; the permission mode is handled in the next action.

Expected result: The file is owned by postgres:postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which operating-system account runs Patroni?

</details>

<details>
<summary>hint</summary>

The Patroni systemd unit uses postgres.

</details>

<details>
<summary>stronger hint</summary>

Set both owner and group to postgres on /etc/patroni/patroni.yml.

</details>

<details>
<summary>solution</summary>

Run the displayed chown command, then read the owner and group with ls -l.

</details>

</details>

**Done when:** the independent `PATRONI_CONFIG_OWNER_SET` validator passes and the required learner-run check is observed.

## 103. Protect the Patroni configuration on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Configure · 10 of 30**

Set up the launchers, service definition, and identity of each member.

Restrict the credential-bearing YAML to the postgres service account.

```bash
sudo chmod 0600 /etc/patroni/patroni.yml
```

**Prove it worked**

```bash
sudo stat -c '%A %U %G' /etc/patroni/patroni.yml
```

Look for: -rw------- postgres postgres

<details>
<summary>Full explanation</summary>

The file contains database credentials, so only the postgres owner may read or change it.

chmod 0600 grants read and write access only to the file owner and removes all group and other access.

stat prints only the symbolic mode, owner and group. -rw------- proves mode 0600, and the final fields prove Patroni still owns the file.

Expected result: The file mode is 0600 and its owner remains postgres:postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file stricter than a public certificate?

</details>

<details>
<summary>hint</summary>

It contains database passwords.

</details>

<details>
<summary>stronger hint</summary>

Mode 0600 appears as -rw-------.

</details>

<details>
<summary>solution</summary>

Run the displayed chmod command, then verify the symbolic mode with ls -l.

</details>

</details>

**Done when:** the independent `PATRONI_CONFIG_SECURE` validator passes and the required learner-run check is observed.

## 104. Create the /opt/patroni and /etc/patroni directories

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Prepare · 8 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Create separate homes for Patroni’s software and configuration.

**Your turn:** The same paths are used on this node: /opt/patroni and /etc/patroni.

```bash
sudo mkdir -p /opt/patroni /etc/patroni
```

**Think first · optional:** You are on pg-ha-2 now. What should stay the same?

- The two destination paths
- The node name in its YAML
- Every resolved address

**Prove it worked**

```bash
ls -ld /opt/patroni /etc/patroni
```

Look for: 2 lines, one per directory, each starting with d

<details>
<summary>Compare your prediction with the check</summary>

Read the selected terminal role and the two paths in the directory listing.

If those directories exist on pg-ha-2, you have applied the location pattern to the second node.

If a path is missing or you are on another terminal, correct that specific mismatch before relying on the result.

Shared file paths do not make node names or addresses interchangeable.

This reflection does not mark the step complete.

</details>

<details>
<summary>Full explanation</summary>

Create /opt/patroni and /etc/patroni before setting its ownership and permissions.

sudo mkdir -p creates /opt/patroni /etc/patroni (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected result: The command returns to the prompt and /opt/patroni and /etc/patroni exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which account runs Patroni?

</details>

<details>
<summary>hint</summary>

Use the same postgres OS account that owns PostgreSQL.

</details>

<details>
<summary>stronger hint</summary>

Both /opt/patroni and /etc/patroni need postgres ownership.

</details>

<details>
<summary>solution</summary>

Run the displayed command and require PATRONI_DIRS_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_DIRS_DIRS_MADE` validator passes and the required learner-run check is observed.

## 105. Give postgres ownership of the /opt/patroni and /etc/patroni directories

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Prepare · 9 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Give the postgres service account ownership of both locations.

**Your turn:** Keep the same service account: postgres owns the directories on every node.

```bash
sudo chown -R postgres:postgres /opt/patroni /etc/patroni
```

**Prove it worked**

```bash
ls -ld /opt/patroni /etc/patroni
```

Look for: owner postgres and group postgres on every line

<details>
<summary>Full explanation</summary>

The postgres account owns /opt/patroni and /etc/patroni so the intended process can use this location.

chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected result: /opt/patroni and /etc/patroni is owned by postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which account runs Patroni?

</details>

<details>
<summary>hint</summary>

Use the same postgres OS account that owns PostgreSQL.

</details>

<details>
<summary>stronger hint</summary>

Both /opt/patroni and /etc/patroni need postgres ownership.

</details>

<details>
<summary>solution</summary>

Run the displayed command and require PATRONI_DIRS_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_DIRS_DIRS_OWNED` validator passes and the required learner-run check is observed.

## 106. Set permissions on the /opt/patroni and /etc/patroni directories

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Prepare · 10 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Set who can enter and change Patroni’s directories.

**Your turn:** Apply mode 0750 again, then read the permission groups yourself.

```bash
sudo chmod 0750 /opt/patroni /etc/patroni
```

**Prove it worked**

```bash
ls -ld /opt/patroni /etc/patroni
```

Look for: each line reading drwxr-x---

<details>
<summary>Full explanation</summary>

Patroni software and protected configuration need explicit postgres-owned locations.

chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

ls -ld shows the directory itself with its permission bits in the first column. Mode 0750 must appear as drwxr-x---; anything else means the chmod did not apply.

Expected result: Both directories exist with postgres ownership and mode 0750.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which account runs Patroni?

</details>

<details>
<summary>hint</summary>

Use the same postgres OS account that owns PostgreSQL.

</details>

<details>
<summary>stronger hint</summary>

Both /opt/patroni and /etc/patroni need postgres ownership.

</details>

<details>
<summary>solution</summary>

Run the displayed command and require PATRONI_DIRS_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_DIRS_CREATED` validator passes and the required learner-run check is observed.

## 107. Create the /var/run/postgresql directory

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Prepare · 11 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Create the directory for local PostgreSQL connections.

**Your turn:** Use /var/run/postgresql again. The database files live elsewhere.

```bash
sudo mkdir -p /var/run/postgresql
```

**Prove it worked**

```bash
ls -ld /var/run/postgresql
```

Look for: one line starting with d

<details>
<summary>Full explanation</summary>

Create /var/run/postgresql before setting its ownership and permissions.

sudo mkdir -p creates /var/run/postgresql (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected result: The command returns to the prompt and /var/run/postgresql exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Is this directory permanent database storage?

</details>

<details>
<summary>hint</summary>

It holds runtime socket files, not table data.

</details>

<details>
<summary>stronger hint</summary>

The path is /var/run/postgresql.

</details>

<details>
<summary>solution</summary>

Create the directory and require PATRONI_SOCKET_DIR_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_MADE` validator passes and the required learner-run check is observed.

## 108. Give postgres ownership of the /var/run/postgresql directory

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Prepare · 12 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Let postgres own the directory where it creates its local socket.

**Your turn:** Apply the ownership pattern you used on the first node.

```bash
sudo chown -R postgres:postgres /var/run/postgresql
```

**Prove it worked**

```bash
ls -ld /var/run/postgresql
```

Look for: owner postgres and group postgres on the line

<details>
<summary>Full explanation</summary>

The postgres account owns /var/run/postgresql so the intended process can use this location.

chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected result: /var/run/postgresql is owned by postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Is this directory permanent database storage?

</details>

<details>
<summary>hint</summary>

It holds runtime socket files, not table data.

</details>

<details>
<summary>stronger hint</summary>

The path is /var/run/postgresql.

</details>

<details>
<summary>solution</summary>

Create the directory and require PATRONI_SOCKET_DIR_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_OWNED` validator passes and the required learner-run check is observed.

## 109. Set permissions on the /var/run/postgresql directory

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Prepare · 13 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Allow local clients to enter the socket directory.

**Your turn:** Use mode 0755 for this runtime directory, rather than the 0750 used for Patroni’s directories.

```bash
sudo chmod 0755 /var/run/postgresql
```

**Prove it worked**

```bash
ls -ld /var/run/postgresql
```

Look for: the first column reading drwxr-xr-x

<details>
<summary>Full explanation</summary>

Local clients and Patroni need a writable runtime location for the Unix socket.

chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

ls -ld shows the directory itself with its permission bits in the first column. Mode 0755 must appear as drwxr-xr-x; anything else means the chmod did not apply.

Expected result: /var/run/postgresql exists with postgres ownership.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Is this directory permanent database storage?

</details>

<details>
<summary>hint</summary>

It holds runtime socket files, not table data.

</details>

<details>
<summary>stronger hint</summary>

The path is /var/run/postgresql.

</details>

<details>
<summary>solution</summary>

Create the directory and require PATRONI_SOCKET_DIR_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_SOCKET_DIR_CREATED` validator passes and the required learner-run check is observed.

## 110. Install Patroni on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Prepare · 14 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Install the pinned Patroni runtime and inspect its entry point.

**Your turn:** Use the same staged archive and inspect the installed entry point on this node.

```bash
sudo tar -xzf /opt/suta/artifacts/patroni-4.1.4-python39-centos9-amd64.tar.gz -C /opt/patroni --strip-components=1
```

**Prove it worked**

```bash
sudo ls -l /opt/patroni/bin/patroni
```

Look for: an executable file (-rwxr-xr-x) at /opt/patroni/bin/patroni

<details>
<summary>Full explanation</summary>

Each PostgreSQL node needs the same pinned Patroni runtime.

tar extracts the verified Patroni runtime into the prepared directory and removes the archive's outer folder.

tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected result: Patroni 4.1.4 Python modules exist under /opt/patroni.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why install the same version on all members?

</details>

<details>
<summary>hint</summary>

Cluster behavior must not depend on mixed Patroni code.

</details>

<details>
<summary>stronger hint</summary>

The locked version is 4.1.4.

</details>

<details>
<summary>solution</summary>

Extract the staged archive and require PATRONI_SOFTWARE_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_SOFTWARE_INSTALLED` validator passes and the required learner-run check is observed.

## 111. Copy the etcd CA certificate on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Connect securely · 10 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Place the trust certificate Patroni will use to check etcd’s identity.

**Your turn:** Use the handoff file staged on this node, even though the paths look familiar.

```bash
sudo cp /opt/suta/handoff/patroni/ca.crt /etc/patroni/etcd-ca.crt
```

**Prove it worked**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```

Look for: one line ending in /etc/patroni/etcd-ca.crt with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-ca.crt. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/patroni/etcd-ca.crt now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does a CA certificate contain the CA private key?

</details>

<details>
<summary>hint</summary>

A .crt file is public verification material.

</details>

<details>
<summary>stronger hint</summary>

The destination is /etc/patroni/etcd-ca.crt.

</details>

<details>
<summary>solution</summary>

Install the CA certificate and require PATRONI_CA_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CA_COPIED` validator passes and the required learner-run check is observed.

## 112. Set permissions on the etcd CA certificate on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Connect securely · 11 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Set mode 644 on /etc/patroni/etcd-ca.crt without displaying its contents.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-ca.crt on pg-ha-2.

```bash
sudo chmod 0644 /etc/patroni/etcd-ca.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-ca.crt
```

Look for: the mode field 644 and path /etc/patroni/etcd-ca.crt

<details>
<summary>Full explanation</summary>

The permissions decide who may read this file before ownership is handed to postgres.

chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: /etc/patroni/etcd-ca.crt now has mode 644.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does a CA certificate contain the CA private key?

</details>

<details>
<summary>hint</summary>

A .crt file is public verification material.

</details>

<details>
<summary>stronger hint</summary>

The destination is /etc/patroni/etcd-ca.crt.

</details>

<details>
<summary>solution</summary>

Install the CA certificate and require PATRONI_CA_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CA_MODE_SET` validator passes and the required learner-run check is observed.

## 113. Give postgres ownership of the etcd CA certificate on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Connect securely · 12 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Give the postgres service account the required access to /etc/patroni/etcd-ca.crt.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-ca.crt on pg-ha-2.

```bash
sudo chown postgres:postgres /etc/patroni/etcd-ca.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-ca.crt
```

Look for: postgres postgres 644 /etc/patroni/etcd-ca.crt

<details>
<summary>Full explanation</summary>

Patroni must verify that it is talking to the assigned etcd cluster.

chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: The CA certificate is readable by Patroni and contains no private key.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does a CA certificate contain the CA private key?

</details>

<details>
<summary>hint</summary>

A .crt file is public verification material.

</details>

<details>
<summary>stronger hint</summary>

The destination is /etc/patroni/etcd-ca.crt.

</details>

<details>
<summary>solution</summary>

Install the CA certificate and require PATRONI_CA_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CA_INSTALLED` validator passes and the required learner-run check is observed.

## 114. Copy Patroni's etcd client certificate on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Connect securely · 13 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Place the certificate Patroni presents as its client identity.

**Your turn:** Use this node’s staged client certificate, not a resolved file copied from another node.

```bash
sudo cp /opt/suta/handoff/patroni/client.crt /etc/patroni/etcd-client.crt
```

**Prove it worked**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```

Look for: one line ending in /etc/patroni/etcd-client.crt with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.crt. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/patroni/etcd-client.crt now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which side presents this certificate?

</details>

<details>
<summary>hint</summary>

Patroni is the client of etcd.

</details>

<details>
<summary>stronger hint</summary>

This is public identity material; the private key is handled next.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_CERT_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_CERT_COPIED` validator passes and the required learner-run check is observed.

## 115. Set permissions on Patroni's etcd client certificate on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Connect securely · 14 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Set mode 644 on /etc/patroni/etcd-client.crt without displaying its contents.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-client.crt on pg-ha-2.

```bash
sudo chmod 0644 /etc/patroni/etcd-client.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.crt
```

Look for: the mode field 644 and path /etc/patroni/etcd-client.crt

<details>
<summary>Full explanation</summary>

The permissions decide who may read this file before ownership is handed to postgres.

chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: /etc/patroni/etcd-client.crt now has mode 644.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which side presents this certificate?

</details>

<details>
<summary>hint</summary>

Patroni is the client of etcd.

</details>

<details>
<summary>stronger hint</summary>

This is public identity material; the private key is handled next.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_CERT_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_CERT_MODE_SET` validator passes and the required learner-run check is observed.

## 116. Give postgres ownership of Patroni's etcd client certificate on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Connect securely · 15 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Give the postgres service account the required access to /etc/patroni/etcd-client.crt.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-client.crt on pg-ha-2.

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.crt
```

Look for: postgres postgres 644 /etc/patroni/etcd-client.crt

<details>
<summary>Full explanation</summary>

etcd mutual TLS also verifies Patroni's client identity.

chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: The signed client certificate is postgres-owned and mode 0644.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which side presents this certificate?

</details>

<details>
<summary>hint</summary>

Patroni is the client of etcd.

</details>

<details>
<summary>stronger hint</summary>

This is public identity material; the private key is handled next.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_CERT_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_CERT_INSTALLED` validator passes and the required learner-run check is observed.

## 117. Copy Patroni's protected etcd client key on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Connect securely · 16 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Place the private key used with Patroni’s client certificate.

**Your turn:** Use this node’s handoff. Inspect file metadata without printing the key.

```bash
sudo cp /opt/suta/handoff/patroni/client.key /etc/patroni/etcd-client.key
```

**Prove it worked**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```

Look for: one line ending in /etc/patroni/etcd-client.key with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.key. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/patroni/etcd-client.key now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file more restricted than the certificate?

</details>

<details>
<summary>hint</summary>

Anyone holding the private key can impersonate the client.

</details>

<details>
<summary>stronger hint</summary>

Use mode 0600 and never run cat on it.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_KEY_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_KEY_COPIED` validator passes and the required learner-run check is observed.

## 118. Set permissions on Patroni's protected etcd client key on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Connect securely · 17 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Set mode 600 on /etc/patroni/etcd-client.key without displaying its contents.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-client.key on pg-ha-2.

```bash
sudo chmod 0600 /etc/patroni/etcd-client.key
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.key
```

Look for: the mode field 600 and path /etc/patroni/etcd-client.key

<details>
<summary>Full explanation</summary>

The permissions decide who may read this file before ownership is handed to postgres.

chmod 0600 sets the file's permissions to 600 (owner read/write, group/others read - or owner-only for a private key).

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: /etc/patroni/etcd-client.key now has mode 600.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file more restricted than the certificate?

</details>

<details>
<summary>hint</summary>

Anyone holding the private key can impersonate the client.

</details>

<details>
<summary>stronger hint</summary>

Use mode 0600 and never run cat on it.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_KEY_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_KEY_MODE_SET` validator passes and the required learner-run check is observed.

## 119. Give postgres ownership of Patroni's protected etcd client key on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Connect securely · 18 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Give the postgres service account the required access to /etc/patroni/etcd-client.key.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-client.key on pg-ha-2.

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.key
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.key
```

Look for: postgres postgres 600 /etc/patroni/etcd-client.key

<details>
<summary>Full explanation</summary>

The private key proves possession of the client identity and must not be exposed.

chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: The command shows no key material and the destination mode is 0600.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file more restricted than the certificate?

</details>

<details>
<summary>hint</summary>

Anyone holding the private key can impersonate the client.

</details>

<details>
<summary>stronger hint</summary>

Use mode 0600 and never run cat on it.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_KEY_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_KEY_INSTALLED` validator passes and the required learner-run check is observed.

## 120. Copy the Patroni launcher on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 11 of 30**

Set up the launchers, service definition, and identity of each member.

Put the launcher for the Patroni manager in place.

**Your turn:** Use the same launcher path on this node. Copying it does not start the service.

```bash
sudo cp /opt/suta/handoff/patroni/patroni /usr/local/bin/patroni
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patroni
```

Look for: one line ending in /usr/local/bin/patroni with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patroni. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /usr/local/bin/patroni now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why use a wrapper instead of a floating pip command?

</details>

<details>
<summary>hint</summary>

It binds systemd to the pinned runtime path.

</details>

<details>
<summary>stronger hint</summary>

The destination is /usr/local/bin/patroni.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_WRAPPER_COPIED` validator passes and the required learner-run check is observed.

## 121. Make the Patroni launcher on pg-ha-2 runnable

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 12 of 30**

Set up the launchers, service definition, and identity of each member.

Make the launcher executable, then inspect its permissions.

**Your turn:** Apply the executable-file pattern and check this node’s launcher permissions.

```bash
sudo chmod 0755 /usr/local/bin/patroni
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patroni
```

Look for: the first column reading -rwxr-xr-x

<details>
<summary>Full explanation</summary>

The pinned Python runtime needs one stable command path for systemd.

chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected result: /usr/local/bin/patroni is executable and reports Patroni 4.1.4.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why use a wrapper instead of a floating pip command?

</details>

<details>
<summary>hint</summary>

It binds systemd to the pinned runtime path.

</details>

<details>
<summary>stronger hint</summary>

The destination is /usr/local/bin/patroni.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_WRAPPER_INSTALLED` validator passes and the required learner-run check is observed.

## 122. Copy the patronictl launcher on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 13 of 30**

Set up the launchers, service definition, and identity of each member.

Install the launcher for the cluster administration tool.

**Your turn:** This is patronictl, the administration tool. Patroni itself is the manager.

```bash
sudo cp /opt/suta/handoff/patroni/patronictl /usr/local/bin/patronictl
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patronictl
```

Look for: one line ending in /usr/local/bin/patronictl with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patronictl. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /usr/local/bin/patronictl now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which tool runs the service and which tool operates the cluster?

</details>

<details>
<summary>hint</summary>

patroni runs; patronictl controls and inspects.

</details>

<details>
<summary>stronger hint</summary>

The operator command ends in ctl.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONICTL_WRAPPER_COPIED` validator passes and the required learner-run check is observed.

## 123. Make the patronictl launcher on pg-ha-2 runnable

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 14 of 30**

Set up the launchers, service definition, and identity of each member.

Make the launcher executable, then inspect its permissions.

**Your turn:** Apply the executable-file pattern and check this node’s launcher permissions.

```bash
sudo chmod 0755 /usr/local/bin/patronictl
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patronictl
```

Look for: the first column reading -rwxr-xr-x

<details>
<summary>Full explanation</summary>

Operators need a stable absolute path for cluster inspection and planned operations.

chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected result: /usr/local/bin/patronictl is executable.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which tool runs the service and which tool operates the cluster?

</details>

<details>
<summary>hint</summary>

patroni runs; patronictl controls and inspects.

</details>

<details>
<summary>stronger hint</summary>

The operator command ends in ctl.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONICTL_WRAPPER_INSTALLED` validator passes and the required learner-run check is observed.

## 124. Copy the Patroni systemd unit on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 15 of 30**

Set up the launchers, service definition, and identity of each member.

Give systemd the definition it needs to start Patroni.

**Your turn:** Use the supplied service definition on this node; startup comes later.

```bash
sudo cp /opt/suta/handoff/patroni/patroni.service /etc/systemd/system/patroni.service
```

**Prove it worked**

```bash
ls -l /etc/systemd/system/patroni.service
```

Look for: one line ending in /etc/systemd/system/patroni.service with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/patroni.service. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/systemd/system/patroni.service now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which process should systemd start?

</details>

<details>
<summary>hint</summary>

Patroni owns PostgreSQL startup in this cluster.

</details>

<details>
<summary>stronger hint</summary>

ExecStart must call /usr/local/bin/patroni.

</details>

<details>
<summary>solution</summary>

Install the unit and require PATRONI_UNIT_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_UNIT_COPIED` validator passes and the required learner-run check is observed.

## 125. Set permissions on the Patroni systemd unit on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 16 of 30**

Set up the launchers, service definition, and identity of each member.

Set read access on the service definition.

**Your turn:** Check the mode here. File mode alone does not validate the startup command.

```bash
sudo chmod 0644 /etc/systemd/system/patroni.service
```

**Prove it worked**

```bash
ls -l /etc/systemd/system/patroni.service
```

Look for: the first column reading -rw-r--r--

<details>
<summary>Full explanation</summary>

systemd must run Patroni as the owner of PostgreSQL and recreate its temporary socket directory after every reboot.

chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected result: The unit parses, owns /run/postgresql and starts Patroni with /etc/patroni/patroni.yml.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which process should systemd start?

</details>

<details>
<summary>hint</summary>

Patroni owns PostgreSQL startup in this cluster.

</details>

<details>
<summary>stronger hint</summary>

ExecStart must call /usr/local/bin/patroni and RuntimeDirectory must name postgresql.

</details>

<details>
<summary>solution</summary>

Install the unit and require PATRONI_UNIT_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_UNIT_CREATED` validator passes and the required learner-run check is observed.

## 126. Reload systemd on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 17 of 30**

Set up the launchers, service definition, and identity of each member.

Ask systemd to reread its service definitions.

**Your turn:** Reload systemd on this node too. The file check shows the definition; it does not establish service health.

```bash
sudo systemctl daemon-reload
```

**Prove it worked**

```bash
systemctl cat patroni
```

Look for: # /etc/systemd/system/patroni.service followed by [Unit]

<details>
<summary>Full explanation</summary>

systemd does not use a newly installed unit until its manager configuration is reloaded.

daemon-reload asks systemd to reread unit files without starting Patroni.

systemctl cat prints the unit file exactly as systemd loaded it. If systemd shows your file here, the daemon-reload picked it up; 'No files found' means it did not.

Expected result: The command returns to the prompt and Patroni remains inactive.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does daemon-reload start Patroni?

</details>

<details>
<summary>hint</summary>

It rereads definitions only.

</details>

<details>
<summary>stronger hint</summary>

The service must stay inactive until its ordered start step.

</details>

<details>
<summary>solution</summary>

Reload systemd and require PATRONI_SYSTEMD_RELOADED.

</details>

</details>

**Done when:** the independent `PATRONI_SYSTEMD_RELOADED` validator passes and the required learner-run check is observed.

## 127. Configure Patroni on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 18 of 30**

Set up the launchers, service definition, and identity of each member.

Save this member’s generated identity and cluster configuration.

**Your turn:** Keep the shared scope. Use this node’s unique name, addresses, and generated credentials.

```bash
sudo vi /etc/patroni/patroni.yml
```

Use this node's generated yaml template. Protected values come from SutaBot; never paste them into Chat.

```text
scope: {{cluster_scope}}
namespace: /service/
name: {{role}}
restapi:
  listen: {{private_ip}}:8008
  connect_address: {{private_ip}}:8008
etcd3:
  hosts: {{etcd_hosts}}
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
{{pg_hba_exact_nodes}}
postgresql:
  listen: {{private_ip}}:5432
  connect_address: {{private_ip}}:5432
  data_dir: /opt/pgsql/data
  bin_dir: /opt/pgsql/bin
  pgpass: /etc/patroni/pgpass
  authentication:
    superuser:
      username: postgres
      password: {{secret:postgres_superuser}}
    replication:
      username: replicator
      password: {{secret:replication}}
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

**Prove it worked**

```bash
sudo grep -n -E "^(scope|name|restapi|etcd3|postgresql):" /etc/patroni/patroni.yml
```

Look for: the scope, name, restapi, etcd3 and postgresql top-level keys, each on its own numbered line

<details>
<summary>Full explanation</summary>

The first replica shares the cluster contract but has its own member identity and addresses.

Open the generated pg-ha-2 Patroni YAML in vi, replace the whole file, and save it. This step validates the YAML and cluster settings; the next two steps set its service ownership and protected mode.

grep -E matches several patterns at once; -n adds line numbers. Every top-level section of patroni.yml must be present. A missing key means the file was saved incomplete.

Expected result: The file names pg-ha-2 and passes the Patroni contract validator.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which values distinguish pg-ha-2?

</details>

<details>
<summary>hint</summary>

Inspect name, REST address and PostgreSQL address.

</details>

<details>
<summary>stronger hint</summary>

Keep scope, etcd endpoints, credentials and recovery policy unchanged.

</details>

<details>
<summary>solution</summary>

Enter the supplied YAML and require PATRONI_MEMBER_2_CONFIGURED.

</details>

</details>

**Done when:** the independent `PATRONI_MEMBER_2_CONFIGURED` validator passes and the required learner-run check is observed.

## 128. Give postgres ownership of the Patroni configuration on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 19 of 30**

Set up the launchers, service definition, and identity of each member.

Give the Patroni service account ownership of its saved configuration.

**Your turn:** Apply the same service ownership to this member’s own configuration file.

```bash
sudo chown postgres:postgres /etc/patroni/patroni.yml
```

**Prove it worked**

```bash
sudo stat -c '%A %U %G' /etc/patroni/patroni.yml
```

Look for: postgres postgres as the final two fields

<details>
<summary>Full explanation</summary>

Patroni runs as postgres, so its service account must own the configuration file it reads.

chown sets the saved configuration file owner and group to the postgres service account.

stat prints only the symbolic mode, owner and group. The owner and group must both read postgres; the permission mode is handled in the next action.

Expected result: The file is owned by postgres:postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which operating-system account runs Patroni?

</details>

<details>
<summary>hint</summary>

The Patroni systemd unit uses postgres.

</details>

<details>
<summary>stronger hint</summary>

Set both owner and group to postgres on /etc/patroni/patroni.yml.

</details>

<details>
<summary>solution</summary>

Run the displayed chown command, then read the owner and group with ls -l.

</details>

</details>

**Done when:** the independent `PATRONI_CONFIG_OWNER_SET` validator passes and the required learner-run check is observed.

## 129. Protect the Patroni configuration on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Configure · 20 of 30**

Set up the launchers, service definition, and identity of each member.

Restrict the credential-bearing YAML to the postgres service account.

**Your turn:** Apply the same owner-only mode to this member’s configuration.

```bash
sudo chmod 0600 /etc/patroni/patroni.yml
```

**Prove it worked**

```bash
sudo stat -c '%A %U %G' /etc/patroni/patroni.yml
```

Look for: -rw------- postgres postgres

<details>
<summary>Full explanation</summary>

The file contains database credentials, so only the postgres owner may read or change it.

chmod 0600 grants read and write access only to the file owner and removes all group and other access.

stat prints only the symbolic mode, owner and group. -rw------- proves mode 0600, and the final fields prove Patroni still owns the file.

Expected result: The file mode is 0600 and its owner remains postgres:postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file stricter than a public certificate?

</details>

<details>
<summary>hint</summary>

It contains database passwords.

</details>

<details>
<summary>stronger hint</summary>

Mode 0600 appears as -rw-------.

</details>

<details>
<summary>solution</summary>

Run the displayed chmod command, then verify the symbolic mode with ls -l.

</details>

</details>

**Done when:** the independent `PATRONI_CONFIG_SECURE` validator passes and the required learner-run check is observed.

## 130. Create the /opt/patroni and /etc/patroni directories

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Prepare · 15 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Create separate homes for Patroni’s software and configuration.

**Your turn:** The same paths are used on this node: /opt/patroni and /etc/patroni.

```bash
sudo mkdir -p /opt/patroni /etc/patroni
```

**Prove it worked**

```bash
ls -ld /opt/patroni /etc/patroni
```

Look for: 2 lines, one per directory, each starting with d

<details>
<summary>Full explanation</summary>

Create /opt/patroni and /etc/patroni before setting its ownership and permissions.

sudo mkdir -p creates /opt/patroni /etc/patroni (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected result: The command returns to the prompt and /opt/patroni and /etc/patroni exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which account runs Patroni?

</details>

<details>
<summary>hint</summary>

Use the same postgres OS account that owns PostgreSQL.

</details>

<details>
<summary>stronger hint</summary>

Both /opt/patroni and /etc/patroni need postgres ownership.

</details>

<details>
<summary>solution</summary>

Run the displayed command and require PATRONI_DIRS_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_DIRS_DIRS_MADE` validator passes and the required learner-run check is observed.

## 131. Give postgres ownership of the /opt/patroni and /etc/patroni directories

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Prepare · 16 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Give the postgres service account ownership of both locations.

**Your turn:** Keep the same service account: postgres owns the directories on every node.

```bash
sudo chown -R postgres:postgres /opt/patroni /etc/patroni
```

**Prove it worked**

```bash
ls -ld /opt/patroni /etc/patroni
```

Look for: owner postgres and group postgres on every line

<details>
<summary>Full explanation</summary>

The postgres account owns /opt/patroni and /etc/patroni so the intended process can use this location.

chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected result: /opt/patroni and /etc/patroni is owned by postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which account runs Patroni?

</details>

<details>
<summary>hint</summary>

Use the same postgres OS account that owns PostgreSQL.

</details>

<details>
<summary>stronger hint</summary>

Both /opt/patroni and /etc/patroni need postgres ownership.

</details>

<details>
<summary>solution</summary>

Run the displayed command and require PATRONI_DIRS_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_DIRS_DIRS_OWNED` validator passes and the required learner-run check is observed.

## 132. Set permissions on the /opt/patroni and /etc/patroni directories

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Prepare · 17 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Set who can enter and change Patroni’s directories.

**Your turn:** Apply mode 0750 again, then read the permission groups yourself.

```bash
sudo chmod 0750 /opt/patroni /etc/patroni
```

**Prove it worked**

```bash
ls -ld /opt/patroni /etc/patroni
```

Look for: each line reading drwxr-x---

<details>
<summary>Full explanation</summary>

Patroni software and protected configuration need explicit postgres-owned locations.

chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

ls -ld shows the directory itself with its permission bits in the first column. Mode 0750 must appear as drwxr-x---; anything else means the chmod did not apply.

Expected result: Both directories exist with postgres ownership and mode 0750.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which account runs Patroni?

</details>

<details>
<summary>hint</summary>

Use the same postgres OS account that owns PostgreSQL.

</details>

<details>
<summary>stronger hint</summary>

Both /opt/patroni and /etc/patroni need postgres ownership.

</details>

<details>
<summary>solution</summary>

Run the displayed command and require PATRONI_DIRS_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_DIRS_CREATED` validator passes and the required learner-run check is observed.

## 133. Create the /var/run/postgresql directory

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Prepare · 18 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Create the directory for local PostgreSQL connections.

**Your turn:** Use /var/run/postgresql again. The database files live elsewhere.

```bash
sudo mkdir -p /var/run/postgresql
```

**Prove it worked**

```bash
ls -ld /var/run/postgresql
```

Look for: one line starting with d

<details>
<summary>Full explanation</summary>

Create /var/run/postgresql before setting its ownership and permissions.

sudo mkdir -p creates /var/run/postgresql (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected result: The command returns to the prompt and /var/run/postgresql exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Is this directory permanent database storage?

</details>

<details>
<summary>hint</summary>

It holds runtime socket files, not table data.

</details>

<details>
<summary>stronger hint</summary>

The path is /var/run/postgresql.

</details>

<details>
<summary>solution</summary>

Create the directory and require PATRONI_SOCKET_DIR_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_MADE` validator passes and the required learner-run check is observed.

## 134. Give postgres ownership of the /var/run/postgresql directory

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Prepare · 19 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Let postgres own the directory where it creates its local socket.

**Your turn:** Apply the ownership pattern you used on the first node.

```bash
sudo chown -R postgres:postgres /var/run/postgresql
```

**Prove it worked**

```bash
ls -ld /var/run/postgresql
```

Look for: owner postgres and group postgres on the line

<details>
<summary>Full explanation</summary>

The postgres account owns /var/run/postgresql so the intended process can use this location.

chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected result: /var/run/postgresql is owned by postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Is this directory permanent database storage?

</details>

<details>
<summary>hint</summary>

It holds runtime socket files, not table data.

</details>

<details>
<summary>stronger hint</summary>

The path is /var/run/postgresql.

</details>

<details>
<summary>solution</summary>

Create the directory and require PATRONI_SOCKET_DIR_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_OWNED` validator passes and the required learner-run check is observed.

## 135. Set permissions on the /var/run/postgresql directory

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Prepare · 20 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Allow local clients to enter the socket directory.

**Your turn:** Use mode 0755 for this runtime directory, rather than the 0750 used for Patroni’s directories.

```bash
sudo chmod 0755 /var/run/postgresql
```

**Prove it worked**

```bash
ls -ld /var/run/postgresql
```

Look for: the first column reading drwxr-xr-x

<details>
<summary>Full explanation</summary>

Local clients and Patroni need a writable runtime location for the Unix socket.

chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

ls -ld shows the directory itself with its permission bits in the first column. Mode 0755 must appear as drwxr-xr-x; anything else means the chmod did not apply.

Expected result: /var/run/postgresql exists with postgres ownership.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Is this directory permanent database storage?

</details>

<details>
<summary>hint</summary>

It holds runtime socket files, not table data.

</details>

<details>
<summary>stronger hint</summary>

The path is /var/run/postgresql.

</details>

<details>
<summary>solution</summary>

Create the directory and require PATRONI_SOCKET_DIR_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_SOCKET_DIR_CREATED` validator passes and the required learner-run check is observed.

## 136. Install Patroni on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Prepare · 21 of 21**

Get the folders and Patroni runtime ready on all three nodes.

Install the pinned Patroni runtime and inspect its entry point.

**Your turn:** Use the same staged archive and inspect the installed entry point on this node.

```bash
sudo tar -xzf /opt/suta/artifacts/patroni-4.1.4-python39-centos9-amd64.tar.gz -C /opt/patroni --strip-components=1
```

**Prove it worked**

```bash
sudo ls -l /opt/patroni/bin/patroni
```

Look for: an executable file (-rwxr-xr-x) at /opt/patroni/bin/patroni

<details>
<summary>Full explanation</summary>

Each PostgreSQL node needs the same pinned Patroni runtime.

tar extracts the verified Patroni runtime into the prepared directory and removes the archive's outer folder.

tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected result: Patroni 4.1.4 Python modules exist under /opt/patroni.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why install the same version on all members?

</details>

<details>
<summary>hint</summary>

Cluster behavior must not depend on mixed Patroni code.

</details>

<details>
<summary>stronger hint</summary>

The locked version is 4.1.4.

</details>

<details>
<summary>solution</summary>

Extract the staged archive and require PATRONI_SOFTWARE_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_SOFTWARE_INSTALLED` validator passes and the required learner-run check is observed.

## 137. Copy the etcd CA certificate on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Connect securely · 19 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Place the trust certificate Patroni will use to check etcd’s identity.

**Your turn:** Use the handoff file staged on this node, even though the paths look familiar.

```bash
sudo cp /opt/suta/handoff/patroni/ca.crt /etc/patroni/etcd-ca.crt
```

**Prove it worked**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```

Look for: one line ending in /etc/patroni/etcd-ca.crt with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-ca.crt. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/patroni/etcd-ca.crt now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does a CA certificate contain the CA private key?

</details>

<details>
<summary>hint</summary>

A .crt file is public verification material.

</details>

<details>
<summary>stronger hint</summary>

The destination is /etc/patroni/etcd-ca.crt.

</details>

<details>
<summary>solution</summary>

Install the CA certificate and require PATRONI_CA_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CA_COPIED` validator passes and the required learner-run check is observed.

## 138. Set permissions on the etcd CA certificate on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Connect securely · 20 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Set mode 644 on /etc/patroni/etcd-ca.crt without displaying its contents.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-ca.crt on pg-ha-3.

```bash
sudo chmod 0644 /etc/patroni/etcd-ca.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-ca.crt
```

Look for: the mode field 644 and path /etc/patroni/etcd-ca.crt

<details>
<summary>Full explanation</summary>

The permissions decide who may read this file before ownership is handed to postgres.

chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: /etc/patroni/etcd-ca.crt now has mode 644.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does a CA certificate contain the CA private key?

</details>

<details>
<summary>hint</summary>

A .crt file is public verification material.

</details>

<details>
<summary>stronger hint</summary>

The destination is /etc/patroni/etcd-ca.crt.

</details>

<details>
<summary>solution</summary>

Install the CA certificate and require PATRONI_CA_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CA_MODE_SET` validator passes and the required learner-run check is observed.

## 139. Give postgres ownership of the etcd CA certificate on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Connect securely · 21 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Give the postgres service account the required access to /etc/patroni/etcd-ca.crt.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-ca.crt on pg-ha-3.

```bash
sudo chown postgres:postgres /etc/patroni/etcd-ca.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-ca.crt
```

Look for: postgres postgres 644 /etc/patroni/etcd-ca.crt

<details>
<summary>Full explanation</summary>

Patroni must verify that it is talking to the assigned etcd cluster.

chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: The CA certificate is readable by Patroni and contains no private key.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does a CA certificate contain the CA private key?

</details>

<details>
<summary>hint</summary>

A .crt file is public verification material.

</details>

<details>
<summary>stronger hint</summary>

The destination is /etc/patroni/etcd-ca.crt.

</details>

<details>
<summary>solution</summary>

Install the CA certificate and require PATRONI_CA_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CA_INSTALLED` validator passes and the required learner-run check is observed.

## 140. Copy Patroni's etcd client certificate on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Connect securely · 22 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Place the certificate Patroni presents as its client identity.

**Your turn:** Use this node’s staged client certificate, not a resolved file copied from another node.

```bash
sudo cp /opt/suta/handoff/patroni/client.crt /etc/patroni/etcd-client.crt
```

**Prove it worked**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```

Look for: one line ending in /etc/patroni/etcd-client.crt with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.crt. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/patroni/etcd-client.crt now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which side presents this certificate?

</details>

<details>
<summary>hint</summary>

Patroni is the client of etcd.

</details>

<details>
<summary>stronger hint</summary>

This is public identity material; the private key is handled next.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_CERT_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_CERT_COPIED` validator passes and the required learner-run check is observed.

## 141. Set permissions on Patroni's etcd client certificate on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Connect securely · 23 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Set mode 644 on /etc/patroni/etcd-client.crt without displaying its contents.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-client.crt on pg-ha-3.

```bash
sudo chmod 0644 /etc/patroni/etcd-client.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.crt
```

Look for: the mode field 644 and path /etc/patroni/etcd-client.crt

<details>
<summary>Full explanation</summary>

The permissions decide who may read this file before ownership is handed to postgres.

chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: /etc/patroni/etcd-client.crt now has mode 644.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which side presents this certificate?

</details>

<details>
<summary>hint</summary>

Patroni is the client of etcd.

</details>

<details>
<summary>stronger hint</summary>

This is public identity material; the private key is handled next.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_CERT_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_CERT_MODE_SET` validator passes and the required learner-run check is observed.

## 142. Give postgres ownership of Patroni's etcd client certificate on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Connect securely · 24 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Give the postgres service account the required access to /etc/patroni/etcd-client.crt.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-client.crt on pg-ha-3.

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.crt
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.crt
```

Look for: postgres postgres 644 /etc/patroni/etcd-client.crt

<details>
<summary>Full explanation</summary>

etcd mutual TLS also verifies Patroni's client identity.

chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: The signed client certificate is postgres-owned and mode 0644.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which side presents this certificate?

</details>

<details>
<summary>hint</summary>

Patroni is the client of etcd.

</details>

<details>
<summary>stronger hint</summary>

This is public identity material; the private key is handled next.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_CERT_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_CERT_INSTALLED` validator passes and the required learner-run check is observed.

## 143. Copy Patroni's protected etcd client key on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Connect securely · 25 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Place the private key used with Patroni’s client certificate.

**Your turn:** Use this node’s handoff. Inspect file metadata without printing the key.

```bash
sudo cp /opt/suta/handoff/patroni/client.key /etc/patroni/etcd-client.key
```

**Prove it worked**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```

Look for: one line ending in /etc/patroni/etcd-client.key with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.key. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/patroni/etcd-client.key now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file more restricted than the certificate?

</details>

<details>
<summary>hint</summary>

Anyone holding the private key can impersonate the client.

</details>

<details>
<summary>stronger hint</summary>

Use mode 0600 and never run cat on it.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_KEY_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_KEY_COPIED` validator passes and the required learner-run check is observed.

## 144. Set permissions on Patroni's protected etcd client key on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Connect securely · 26 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Set mode 600 on /etc/patroni/etcd-client.key without displaying its contents.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-client.key on pg-ha-3.

```bash
sudo chmod 0600 /etc/patroni/etcd-client.key
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.key
```

Look for: the mode field 600 and path /etc/patroni/etcd-client.key

<details>
<summary>Full explanation</summary>

The permissions decide who may read this file before ownership is handed to postgres.

chmod 0600 sets the file's permissions to 600 (owner read/write, group/others read - or owner-only for a private key).

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: /etc/patroni/etcd-client.key now has mode 600.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file more restricted than the certificate?

</details>

<details>
<summary>hint</summary>

Anyone holding the private key can impersonate the client.

</details>

<details>
<summary>stronger hint</summary>

Use mode 0600 and never run cat on it.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_KEY_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_KEY_MODE_SET` validator passes and the required learner-run check is observed.

## 145. Give postgres ownership of Patroni's protected etcd client key on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Connect securely · 27 of 27**

Prepare the trust, certificate, and private-key files for etcd.

Give the postgres service account the required access to /etc/patroni/etcd-client.key.

**Your turn:** Inspect the owner and mode of /etc/patroni/etcd-client.key on pg-ha-3.

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.key
```

**Prove it worked**

```bash
sudo stat -c '%U %G %a %n' /etc/patroni/etcd-client.key
```

Look for: postgres postgres 600 /etc/patroni/etcd-client.key

<details>
<summary>Full explanation</summary>

The private key proves possession of the client identity and must not be exposed.

chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

stat prints owner, group, numeric mode and path without reading file contents. Compare these fields with this action. The independent validator also retains the required certificate validity, trust and key checks; file metadata alone does not prove TLS health.

Expected result: The command shows no key material and the destination mode is 0600.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file more restricted than the certificate?

</details>

<details>
<summary>hint</summary>

Anyone holding the private key can impersonate the client.

</details>

<details>
<summary>stronger hint</summary>

Use mode 0600 and never run cat on it.

</details>

<details>
<summary>solution</summary>

Install it and require PATRONI_CLIENT_KEY_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_CLIENT_KEY_INSTALLED` validator passes and the required learner-run check is observed.

## 146. Copy the Patroni launcher on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 21 of 30**

Set up the launchers, service definition, and identity of each member.

Put the launcher for the Patroni manager in place.

**Your turn:** Use the same launcher path on this node. Copying it does not start the service.

```bash
sudo cp /opt/suta/handoff/patroni/patroni /usr/local/bin/patroni
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patroni
```

Look for: one line ending in /usr/local/bin/patroni with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patroni. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /usr/local/bin/patroni now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why use a wrapper instead of a floating pip command?

</details>

<details>
<summary>hint</summary>

It binds systemd to the pinned runtime path.

</details>

<details>
<summary>stronger hint</summary>

The destination is /usr/local/bin/patroni.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_WRAPPER_COPIED` validator passes and the required learner-run check is observed.

## 147. Make the Patroni launcher on pg-ha-3 runnable

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 22 of 30**

Set up the launchers, service definition, and identity of each member.

Make the launcher executable, then inspect its permissions.

**Your turn:** Apply the executable-file pattern and check this node’s launcher permissions.

```bash
sudo chmod 0755 /usr/local/bin/patroni
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patroni
```

Look for: the first column reading -rwxr-xr-x

<details>
<summary>Full explanation</summary>

The pinned Python runtime needs one stable command path for systemd.

chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected result: /usr/local/bin/patroni is executable and reports Patroni 4.1.4.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why use a wrapper instead of a floating pip command?

</details>

<details>
<summary>hint</summary>

It binds systemd to the pinned runtime path.

</details>

<details>
<summary>stronger hint</summary>

The destination is /usr/local/bin/patroni.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONI_WRAPPER_INSTALLED` validator passes and the required learner-run check is observed.

## 148. Copy the patronictl launcher on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 23 of 30**

Set up the launchers, service definition, and identity of each member.

Install the launcher for the cluster administration tool.

**Your turn:** This is patronictl, the administration tool. Patroni itself is the manager.

```bash
sudo cp /opt/suta/handoff/patroni/patronictl /usr/local/bin/patronictl
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patronictl
```

Look for: one line ending in /usr/local/bin/patronictl with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patronictl. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /usr/local/bin/patronictl now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which tool runs the service and which tool operates the cluster?

</details>

<details>
<summary>hint</summary>

patroni runs; patronictl controls and inspects.

</details>

<details>
<summary>stronger hint</summary>

The operator command ends in ctl.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONICTL_WRAPPER_COPIED` validator passes and the required learner-run check is observed.

## 149. Make the patronictl launcher on pg-ha-3 runnable

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 24 of 30**

Set up the launchers, service definition, and identity of each member.

Make the launcher executable, then inspect its permissions.

**Your turn:** Apply the executable-file pattern and check this node’s launcher permissions.

```bash
sudo chmod 0755 /usr/local/bin/patronictl
```

**Prove it worked**

```bash
ls -l /usr/local/bin/patronictl
```

Look for: the first column reading -rwxr-xr-x

<details>
<summary>Full explanation</summary>

Operators need a stable absolute path for cluster inspection and planned operations.

chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected result: /usr/local/bin/patronictl is executable.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which tool runs the service and which tool operates the cluster?

</details>

<details>
<summary>hint</summary>

patroni runs; patronictl controls and inspects.

</details>

<details>
<summary>stronger hint</summary>

The operator command ends in ctl.

</details>

<details>
<summary>solution</summary>

Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

</details>

</details>

**Done when:** the independent `PATRONICTL_WRAPPER_INSTALLED` validator passes and the required learner-run check is observed.

## 150. Copy the Patroni systemd unit on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 25 of 30**

Set up the launchers, service definition, and identity of each member.

Give systemd the definition it needs to start Patroni.

**Your turn:** Use the supplied service definition on this node; startup comes later.

```bash
sudo cp /opt/suta/handoff/patroni/patroni.service /etc/systemd/system/patroni.service
```

**Prove it worked**

```bash
ls -l /etc/systemd/system/patroni.service
```

Look for: one line ending in /etc/systemd/system/patroni.service with a size greater than 0

<details>
<summary>Full explanation</summary>

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/patroni.service. It does not set the file's permissions - the next step does that.

cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected result: The command returns to the prompt and /etc/systemd/system/patroni.service now exists.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which process should systemd start?

</details>

<details>
<summary>hint</summary>

Patroni owns PostgreSQL startup in this cluster.

</details>

<details>
<summary>stronger hint</summary>

ExecStart must call /usr/local/bin/patroni.

</details>

<details>
<summary>solution</summary>

Install the unit and require PATRONI_UNIT_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_UNIT_COPIED` validator passes and the required learner-run check is observed.

## 151. Set permissions on the Patroni systemd unit on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 26 of 30**

Set up the launchers, service definition, and identity of each member.

Set read access on the service definition.

**Your turn:** Check the mode here. File mode alone does not validate the startup command.

```bash
sudo chmod 0644 /etc/systemd/system/patroni.service
```

**Prove it worked**

```bash
ls -l /etc/systemd/system/patroni.service
```

Look for: the first column reading -rw-r--r--

<details>
<summary>Full explanation</summary>

systemd must run Patroni as the owner of PostgreSQL and recreate its temporary socket directory after every reboot.

chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected result: The unit parses, owns /run/postgresql and starts Patroni with /etc/patroni/patroni.yml.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which process should systemd start?

</details>

<details>
<summary>hint</summary>

Patroni owns PostgreSQL startup in this cluster.

</details>

<details>
<summary>stronger hint</summary>

ExecStart must call /usr/local/bin/patroni and RuntimeDirectory must name postgresql.

</details>

<details>
<summary>solution</summary>

Install the unit and require PATRONI_UNIT_CREATED.

</details>

</details>

**Done when:** the independent `PATRONI_UNIT_CREATED` validator passes and the required learner-run check is observed.

## 152. Reload systemd on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 27 of 30**

Set up the launchers, service definition, and identity of each member.

Ask systemd to reread its service definitions.

**Your turn:** Reload systemd on this node too. The file check shows the definition; it does not establish service health.

```bash
sudo systemctl daemon-reload
```

**Prove it worked**

```bash
systemctl cat patroni
```

Look for: # /etc/systemd/system/patroni.service followed by [Unit]

<details>
<summary>Full explanation</summary>

systemd does not use a newly installed unit until its manager configuration is reloaded.

daemon-reload asks systemd to reread unit files without starting Patroni.

systemctl cat prints the unit file exactly as systemd loaded it. If systemd shows your file here, the daemon-reload picked it up; 'No files found' means it did not.

Expected result: The command returns to the prompt and Patroni remains inactive.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Does daemon-reload start Patroni?

</details>

<details>
<summary>hint</summary>

It rereads definitions only.

</details>

<details>
<summary>stronger hint</summary>

The service must stay inactive until its ordered start step.

</details>

<details>
<summary>solution</summary>

Reload systemd and require PATRONI_SYSTEMD_RELOADED.

</details>

</details>

**Done when:** the independent `PATRONI_SYSTEMD_RELOADED` validator passes and the required learner-run check is observed.

## 153. Configure Patroni on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 28 of 30**

Set up the launchers, service definition, and identity of each member.

Save this member’s generated identity and cluster configuration.

**Your turn:** Keep the shared scope. Use this node’s unique name, addresses, and generated credentials.

```bash
sudo vi /etc/patroni/patroni.yml
```

Use this node's generated yaml template. Protected values come from SutaBot; never paste them into Chat.

```text
scope: {{cluster_scope}}
namespace: /service/
name: {{role}}
restapi:
  listen: {{private_ip}}:8008
  connect_address: {{private_ip}}:8008
etcd3:
  hosts: {{etcd_hosts}}
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
{{pg_hba_exact_nodes}}
postgresql:
  listen: {{private_ip}}:5432
  connect_address: {{private_ip}}:5432
  data_dir: /opt/pgsql/data
  bin_dir: /opt/pgsql/bin
  pgpass: /etc/patroni/pgpass
  authentication:
    superuser:
      username: postgres
      password: {{secret:postgres_superuser}}
    replication:
      username: replicator
      password: {{secret:replication}}
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

**Prove it worked**

```bash
sudo grep -n -E "^(scope|name|restapi|etcd3|postgresql):" /etc/patroni/patroni.yml
```

Look for: the scope, name, restapi, etcd3 and postgresql top-level keys, each on its own numbered line

<details>
<summary>Full explanation</summary>

The second replica completes the topology with a unique member identity.

Open the generated pg-ha-3 Patroni YAML in vi, replace the whole file, and save it. This step validates the YAML and cluster settings; the next two steps set its service ownership and protected mode.

grep -E matches several patterns at once; -n adds line numbers. Every top-level section of patroni.yml must be present. A missing key means the file was saved incomplete.

Expected result: The file names pg-ha-3 and passes the Patroni contract validator.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

What makes these files members of one cluster?

</details>

<details>
<summary>hint</summary>

They share scope, DCS endpoints and authentication.

</details>

<details>
<summary>stronger hint</summary>

Only member identity and local addresses differ.

</details>

<details>
<summary>solution</summary>

Enter the supplied YAML and require PATRONI_MEMBER_3_CONFIGURED.

</details>

</details>

**Done when:** the independent `PATRONI_MEMBER_3_CONFIGURED` validator passes and the required learner-run check is observed.

## 154. Give postgres ownership of the Patroni configuration on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 29 of 30**

Set up the launchers, service definition, and identity of each member.

Give the Patroni service account ownership of its saved configuration.

**Your turn:** Apply the same service ownership to this member’s own configuration file.

```bash
sudo chown postgres:postgres /etc/patroni/patroni.yml
```

**Prove it worked**

```bash
sudo stat -c '%A %U %G' /etc/patroni/patroni.yml
```

Look for: postgres postgres as the final two fields

<details>
<summary>Full explanation</summary>

Patroni runs as postgres, so its service account must own the configuration file it reads.

chown sets the saved configuration file owner and group to the postgres service account.

stat prints only the symbolic mode, owner and group. The owner and group must both read postgres; the permission mode is handled in the next action.

Expected result: The file is owned by postgres:postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which operating-system account runs Patroni?

</details>

<details>
<summary>hint</summary>

The Patroni systemd unit uses postgres.

</details>

<details>
<summary>stronger hint</summary>

Set both owner and group to postgres on /etc/patroni/patroni.yml.

</details>

<details>
<summary>solution</summary>

Run the displayed chown command, then read the owner and group with ls -l.

</details>

</details>

**Done when:** the independent `PATRONI_CONFIG_OWNER_SET` validator passes and the required learner-run check is observed.

## 155. Protect the Patroni configuration on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Configure · 30 of 30**

Set up the launchers, service definition, and identity of each member.

Restrict the credential-bearing YAML to the postgres service account.

**Your turn:** Apply the same owner-only mode to this member’s configuration.

```bash
sudo chmod 0600 /etc/patroni/patroni.yml
```

**Prove it worked**

```bash
sudo stat -c '%A %U %G' /etc/patroni/patroni.yml
```

Look for: -rw------- postgres postgres

<details>
<summary>Full explanation</summary>

The file contains database credentials, so only the postgres owner may read or change it.

chmod 0600 grants read and write access only to the file owner and removes all group and other access.

stat prints only the symbolic mode, owner and group. -rw------- proves mode 0600, and the final fields prove Patroni still owns the file.

Expected result: The file mode is 0600 and its owner remains postgres:postgres.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why is this file stricter than a public certificate?

</details>

<details>
<summary>hint</summary>

It contains database passwords.

</details>

<details>
<summary>stronger hint</summary>

Mode 0600 appears as -rw-------.

</details>

<details>
<summary>solution</summary>

Run the displayed chmod command, then verify the symbolic mode with ls -l.

</details>

</details>

**Done when:** the independent `PATRONI_CONFIG_SECURE` validator passes and the required learner-run check is observed.

## 156. Bootstrap the first Patroni leader

**Work on:** `pg-ha-1` as `ec2-user`

**Patroni setup → Start · 1 of 3**

Start the leader, then bring in the two replicas one at a time.

Start Patroni on pg-ha-1 and inspect the service status.

```bash
sudo systemctl enable --now patroni
```

**Think first · optional:** What does active (running) establish?

- The service process is running
- The node is definitely the leader
- Both replicas have replayed every transaction

**Prove it worked**

```bash
systemctl status patroni --no-pager
```

Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)

<details>
<summary>Compare your prediction with the check</summary>

Read Loaded and Active in the service status.

If it is enabled and active, systemd has started the service and will start it at boot.

If it is failed or inactive, inspect the service error before continuing.

Service status alone does not identify a leader or prove replication. The registered cluster validator checks this step’s required role state.

This reflection does not mark the step complete.

</details>

<details>
<summary>Full explanation</summary>

Starting one member first prevents three empty nodes from racing to initialize one scope.

Enable Patroni for boot and start only pg-ha-1; Patroni initializes PostgreSQL with checksums and writes cluster state to etcd.

systemctl status shows whether the unit is enabled (starts at boot) and active (running now). Both words must be there.

Expected result: pg-ha-1 becomes one running leader before either replica starts.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Why start only one node first?

</details>

<details>
<summary>hint</summary>

The cluster has no existing leader or initialized data yet.

</details>

<details>
<summary>stronger hint</summary>

Use patronictl list to confirm exactly one running leader.

</details>

<details>
<summary>solution</summary>

Start Patroni on pg-ha-1 and wait for the leader validator before continuing.

</details>

</details>

**Done when:** the independent `PATRONI_LEADER_BOOTSTRAPPED` validator passes and the required learner-run check is observed.

## 157. Join pg-ha-2 as the first replica

**Work on:** `pg-ha-2` as `ec2-user`

**Patroni setup → Start · 2 of 3**

Start the leader, then bring in the two replicas one at a time.

Start pg-ha-2 and watch it join the established cluster.

```bash
sudo systemctl enable --now patroni
```

**Prove it worked**

```bash
systemctl status patroni --no-pager
```

Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)

<details>
<summary>Full explanation</summary>

The member should discover the established leader and clone it instead of initializing another cluster.

Start Patroni on pg-ha-2 only after the leader and pg-ha-2 configuration validators pass.

systemctl status shows whether the unit is enabled (starts at boot) and active (running now). Both words must be there.

Expected result: pg-ha-2 joins as a streaming replica while pg-ha-1 remains leader.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

Which role should pg-ha-2 report?

</details>

<details>
<summary>hint</summary>

It must not report Leader.

</details>

<details>
<summary>stronger hint</summary>

Require one leader and one streaming replica before adding pg-ha-3.

</details>

<details>
<summary>solution</summary>

Start Patroni on pg-ha-2 and require PATRONI_REPLICA_2_JOINED.

</details>

</details>

**Done when:** the independent `PATRONI_REPLICA_2_JOINED` validator passes and the required learner-run check is observed.

## 158. Join pg-ha-3 as the second replica

**Work on:** `pg-ha-3` as `ec2-user`

**Patroni setup → Start · 3 of 3**

Start the leader, then bring in the two replicas one at a time.

Start Patroni on pg-ha-3 and inspect the service status.

```bash
sudo systemctl enable --now patroni
```

**Think first · optional:** What does active (running) establish?

- The service process is running
- The node is definitely the leader
- Both replicas have replayed every transaction

**Prove it worked**

```bash
systemctl status patroni --no-pager
```

Look for: Loaded: loaded (... ; enabled ...) and Active: active (running)

<details>
<summary>Compare your prediction with the check</summary>

Read Loaded and Active in the service status.

If it is enabled and active, systemd has started the service and will start it at boot.

If it is failed or inactive, inspect the service error before continuing.

Service status alone does not identify a leader or prove replication. The registered cluster validator checks this step’s required role state.

This reflection does not mark the step complete.

</details>

<details>
<summary>Full explanation</summary>

The final member restores the intended two-replica redundancy.

Start Patroni on pg-ha-3 after the first replica is already streaming.

systemctl status shows whether the unit is enabled (starts at boot) and active (running now). Both words must be there.

Expected result: The cluster reports one leader and two streaming replicas on one timeline.

</details>

<details>
<summary>Need a hint?</summary>

<details>
<summary>question</summary>

What complete topology must now appear?

</details>

<details>
<summary>hint</summary>

One leader plus two replicas.

</details>

<details>
<summary>stronger hint</summary>

Both replicas must report streaming.

</details>

<details>
<summary>solution</summary>

Start Patroni on pg-ha-3 and require PATRONI_REPLICA_3_JOINED.

</details>

</details>

**Done when:** the independent `PATRONI_REPLICA_3_JOINED` validator passes and the required learner-run check is observed.

## 159. Copy the pinned HAProxy binary into place

**Work on:** `db-router-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why use the staged binary?

Run this one action:

```bash
sudo cp /opt/suta/artifacts/haproxy-3.2.22 /usr/local/sbin/haproxy
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/sbin/haproxy. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/sbin/haproxy now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why use the staged binary?
2. Hint: Its digest and version were fixed before handoff.
3. Stronger hint: Install it at /usr/local/sbin/haproxy.
4. Solution: Run the displayed install command and require HAPROXY_INSTALLED.

**Done when:** the independent `HAPROXY_COPIED` validator passes.

## 160. Make the pinned HAProxy binary runnable

**Work on:** `db-router-1` as `ec2-user`

The writer router needs the reviewed immutable HAProxy build staged by the platform team.

**Predict first:** Why use the staged binary?

Run this one action:

```bash
sudo chmod 0755 /usr/local/sbin/haproxy
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** The permission listing for /usr/local/sbin/haproxy starts with -rwxr-xr-x. The independent validator also enforces the pinned HAProxy version 3.2.22.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why use the staged binary?
2. Hint: Its digest and version were fixed before handoff.
3. Stronger hint: Install it at /usr/local/sbin/haproxy.
4. Solution: Run the displayed install command and require HAPROXY_INSTALLED.

**Done when:** the independent `HAPROXY_INSTALLED` validator passes.

## 161. Create the /etc/haproxy directory

**Work on:** `db-router-1` as `ec2-user`

Create /etc/haproxy before setting its ownership and permissions.

**Predict first:** Who should own routing policy?

Run this one action:

```bash
sudo mkdir -p /etc/haproxy
```

**What the command means:** sudo mkdir -p creates /etc/haproxy (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and /etc/haproxy exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should own routing policy?
2. Hint: It is system configuration, not application data.
3. Stronger hint: Use root:root ownership.
4. Solution: Create the directory and require HAPROXY_DIR_CREATED.

**Done when:** the independent `HAPROXY_DIR_DIRS_MADE` validator passes.

## 162. Give root ownership of the /etc/haproxy directory

**Work on:** `db-router-1` as `ec2-user`

The root account owns /etc/haproxy so the intended process can use this location.

**Predict first:** Who should own routing policy?

Run this one action:

```bash
sudo chown -R root:root /etc/haproxy
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** /etc/haproxy is owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should own routing policy?
2. Hint: It is system configuration, not application data.
3. Stronger hint: Use root:root ownership.
4. Solution: Create the directory and require HAPROXY_DIR_CREATED.

**Done when:** the independent `HAPROXY_DIR_DIRS_OWNED` validator passes.

## 163. Set permissions on the /etc/haproxy directory

**Work on:** `db-router-1` as `ec2-user`

The router needs a root-owned location for its reviewed writer-routing policy.

**Predict first:** Who should own routing policy?

Run this one action:

```bash
sudo chmod 0755 /etc/haproxy
```

**What the command means:** chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

**Expected result:** The directory is root-owned with mode 0755.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should own routing policy?
2. Hint: It is system configuration, not application data.
3. Stronger hint: Use root:root ownership.
4. Solution: Create the directory and require HAPROXY_DIR_CREATED.

**Done when:** the independent `HAPROXY_DIR_CREATED` validator passes.

## 164. Copy the HAProxy systemd unit into place

**Work on:** `db-router-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why run HAProxy in foreground mode under systemd?

Run this one action:

```bash
sudo cp /opt/suta/handoff/haproxy/haproxy.service /etc/systemd/system/haproxy.service
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/haproxy.service. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/systemd/system/haproxy.service now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why run HAProxy in foreground mode under systemd?
2. Hint: systemd must supervise the real process.
3. Stronger hint: The unit uses -W -db and /etc/haproxy/haproxy.cfg.
4. Solution: Install the unit and require HAPROXY_UNIT_CREATED.

**Done when:** the independent `HAPROXY_UNIT_COPIED` validator passes.

## 165. Set permissions on the HAProxy systemd unit

**Work on:** `db-router-1` as `ec2-user`

A stable unit makes the writer router restartable and boot-persistent.

**Predict first:** Why run HAProxy in foreground mode under systemd?

Run this one action:

```bash
sudo chmod 0644 /etc/systemd/system/haproxy.service
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** systemd verifies the HAProxy unit.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why run HAProxy in foreground mode under systemd?
2. Hint: systemd must supervise the real process.
3. Stronger hint: The unit uses -W -db and /etc/haproxy/haproxy.cfg.
4. Solution: Install the unit and require HAPROXY_UNIT_CREATED.

**Done when:** the independent `HAPROXY_UNIT_CREATED` validator passes.

## 166. Reload systemd for HAProxy

**Work on:** `db-router-1` as `ec2-user`

systemd must reread the newly installed unit before it can start it.

**Predict first:** Should HAProxy start before its configuration exists?

Run this one action:

```bash
sudo systemctl daemon-reload
```

**What the command means:** Reload unit definitions without starting HAProxy.

**Expected result:** The unit is visible and HAProxy remains inactive.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Should HAProxy start before its configuration exists?
2. Hint: No; reload definitions only.
3. Stronger hint: The validator requires the service to remain inactive.
4. Solution: Reload systemd and require HAPROXY_SYSTEMD_RELOADED.

**Done when:** the independent `HAPROXY_SYSTEMD_RELOADED` validator passes.

## 167. Configure the HAProxy writer route

**Work on:** `db-router-1` as `ec2-user`

Mattermost needs one stable address that selects only Patroni's current primary.

**Predict first:** Which health path represents writer eligibility?

Run this one action:

```bash
sudo vi /etc/haproxy/haproxy.cfg
```

**What the command means:** Enter the supplied TCP frontend, three PostgreSQL backends and Patroni /primary HTTP health check.

Enter this exact haproxy content after SutaBot resolves only the registered role addresses and protected secret fields:

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
  server pg-ha-1 {{address:pg-ha-1}}:5432 check port 8008 inter 2s fall 2 rise 2
  server pg-ha-2 {{address:pg-ha-2}}:5432 check port 8008 inter 2s fall 2 rise 2
  server pg-ha-3 {{address:pg-ha-3}}:5432 check port 8008 inter 2s fall 2 rise 2
```

**Expected result:** HAProxy's parser accepts the file and exactly one healthy writer backend is eligible.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which health path represents writer eligibility?
2. Hint: Patroni exposes it on port 8008.
3. Stronger hint: Use GET /primary for every backend and send database traffic to port 5432.
4. Solution: Enter the supplied configuration, save it, and run the parser before starting HAProxy.

**Done when:** the independent `HAPROXY_WRITER_CONFIGURED` validator passes.

## 168. Start the writer endpoint

**Work on:** `db-router-1` as `ec2-user`

A valid file must still be loaded by a healthy service before applications can use it.

**Predict first:** What proves routing rather than only process health?

Run this one action:

```bash
sudo systemctl enable --now haproxy
```

**What the command means:** Enable and start HAProxy after the configuration parser and role-health validator pass.

**Expected result:** HAProxy listens on port 5432 and routes a rollback-only write check to the current primary.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What proves routing rather than only process health?
2. Hint: A database transaction through db-router-1 must reach a non-recovery server.
3. Stronger hint: The validator rolls the transaction back so it leaves no probe row.
4. Solution: Start HAProxy and require both service and rollback-only writer-route checks to pass.

**Done when:** the independent `HAPROXY_WRITER_STARTED` validator passes.

## 169. Create the Mattermost database login

On **pg-ha-1** as **ec2-user**.

The application needs its own least-privilege PostgreSQL identity instead of the superuser.

Run one action at a time. Prompt examples identify where to type; do not type the prompt.

If the change is already in place, open the postgres shell and psql using the first two actions, then run the displayed check and exit actions. If you are already at postgres=#, run the check there. You do not need to repeat the change. SutaBot still independently checks the server state.

1. Switch to the postgres user
Start in the Linux terminal on pg-ha-1, as ec2-user.
```bash
sudo -iu postgres
```
sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
The prompt should identify postgres: [postgres@pg-ha-1 ~]$.

2. Connect to PostgreSQL
Type this in the postgres Linux shell.
```bash
/opt/pgsql/bin/psql -h /var/run/postgresql -d postgres
```
The full path selects this lab’s psql program. -h selects the local socket directory; -d selects the postgres database.
Wait for postgres=#. You are now entering SQL or psql commands.

3. Create the application login
Type this at the postgres=# database prompt. Type only the command.
```sql
CREATE ROLE mattermost LOGIN;
```
Create the PostgreSQL role that Mattermost will use. LOGIN allows it to connect; it does not grant superuser privileges.
Look for CREATE ROLE. If the role already exists, inspect it with the next check.

4. Check the new role
On pg-ha-1, type this at the postgres=# database prompt. Type only the command.
```text
\du mattermost
```
List the mattermost database role and its attributes.
Find mattermost. It must not be a Superuser or show Cannot login.

5. Leave PostgreSQL
After reading the checks, type this at postgres=#.
```text
\q
```
Leave the database client and return to Linux.
You should see the postgres shell prompt again.

6. Return to your original user
Type this in the postgres Linux shell.
```bash
exit
```
Close the nested shell before the next lesson.
The prompt should identify ec2-user again.

Expected: PostgreSQL reports CREATE ROLE and the role has login but no superuser privileges.

Done when the independent MATTERMOST_DB_ROLE_CREATED check and the learner-run proof pass.

## 170. Set the protected Mattermost database password

On **pg-ha-1** as **ec2-user**.

SCRAM authentication requires a password while chat and logs must never contain it.

Run one action at a time. Prompt examples identify where to type; do not type the prompt.

If the change is already in place, open the postgres shell and psql using the first two actions, then run the displayed check and exit actions. If you are already at postgres=#, run the check there. You do not need to repeat the change. SutaBot still independently checks the server state.

1. Switch to the postgres user
Start in the Linux terminal on pg-ha-1, as ec2-user.
```bash
sudo -iu postgres
```
sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
The prompt should identify postgres: [postgres@pg-ha-1 ~]$.

2. Connect to PostgreSQL
Type this in the postgres Linux shell.
```bash
/opt/pgsql/bin/psql -h /var/run/postgresql -d postgres
```
The full path selects this lab’s psql program. -h selects the local socket directory; -d selects the postgres database.
Wait for postgres=#. You are now entering SQL or psql commands.

3. Start the password change
Type this at the postgres=# database prompt. Type only the command.
```text
\password mattermost
```
psql securely prompts for a new password without placing it in your SQL command or shell history.
Wait for Enter new password for user "mattermost":. The next two inputs will be hidden.

4. Enter the generated password
At the first password prompt, enter the value from Load protected password. Never paste it into Chat.
The terminal hides password input. No stars or letters appearing is normal.
Press Enter once. Wait for Enter it again:.

5. Enter the same password again
At Enter it again:, enter the same protected value.
The terminal hides password input. No stars or letters appearing is normal.
Press Enter. Wait for postgres=# before running the check. If it reports a mismatch, start the password action again.

6. Check that the role has a SCRAM password
On pg-ha-1, type this at the postgres=# database prompt. Type only the command.
```sql
select rolname, rolpassword like 'SCRAM-SHA-256%' as scram from pg_authid where rolname = 'mattermost';
```
Return the role name and a boolean indicating SCRAM storage. The query does not display the password or its stored hash.
Find mattermost and t under scram. t means true.

7. Leave PostgreSQL
After reading the checks, type this at postgres=#.
```text
\q
```
Leave the database client and return to Linux.
You should see the postgres shell prompt again.

8. Return to your original user
Type this in the postgres Linux shell.
```bash
exit
```
Close the nested shell before the next lesson.
The prompt should identify ec2-user again.

Expected: The password is stored as a SCRAM verifier and no plaintext appears.

Done when the independent MATTERMOST_DB_PASSWORD_SET check and the learner-run proof pass.

## 171. Create the Mattermost database

On **pg-ha-1** as **ec2-user**.

Mattermost needs an isolated database owned by its application role.

Run one action at a time. Prompt examples identify where to type; do not type the prompt.

If the change is already in place, open the postgres shell and psql using the first two actions, then run the displayed check and exit actions. If you are already at postgres=#, run the check there. You do not need to repeat the change. SutaBot still independently checks the server state.

1. Switch to the postgres user
Start in the Linux terminal on pg-ha-1, as ec2-user.
```bash
sudo -iu postgres
```
sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
The prompt should identify postgres: [postgres@pg-ha-1 ~]$.

2. Connect to PostgreSQL
Type this in the postgres Linux shell.
```bash
/opt/pgsql/bin/psql -h /var/run/postgresql -d postgres
```
The full path selects this lab’s psql program. -h selects the local socket directory; -d selects the postgres database.
Wait for postgres=#. You are now entering SQL or psql commands.

3. Create the database only when it is missing
Type this at the postgres=# database prompt. Type only the command.
```sql
SELECT 'CREATE DATABASE mattermost OWNER mattermost' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'mattermost') \gexec
```
The query asks PostgreSQL whether the database is missing. \gexec runs CREATE DATABASE only when the query returns it, so retrying this lesson is safe.
Look for CREATE DATABASE when it was created. No returned row means it already exists; continue to the ownership step.

4. Set the application database owner
Type this at the postgres=# database prompt. Type only the command.
```sql
ALTER DATABASE mattermost OWNER TO mattermost;
```
Set the owner even when the database was created earlier without the OWNER clause.
Look for ALTER DATABASE.

5. Check the database owner
On pg-ha-1, type this at the postgres=# database prompt. Type only the command.
```text
\l mattermost
```
List the mattermost database and its ownership.
Find mattermost in both the Name and Owner columns. If a pager opens, press q to return to postgres=#.

6. Leave PostgreSQL
After reading the checks, type this at postgres=#.
```text
\q
```
Leave the database client and return to Linux.
You should see the postgres shell prompt again.

7. Return to your original user
Type this in the postgres Linux shell.
```bash
exit
```
Close the nested shell before the next lesson.
The prompt should identify ec2-user again.

Expected: The database exists once with mattermost as owner, including after a safe retry.

Done when the independent MATTERMOST_DATABASE_CREATED check and the learner-run proof pass.

## 172. Create the Mattermost operating-system account

**Work on:** `mattermost-1` as `ec2-user`

The application process must not run as root.

**Predict first:** Does the service account need interactive login?

Run this one action:

```bash
sudo useradd --system --home-dir /opt/mattermost --shell /sbin/nologin mattermost
```

**What the command means:** Create a non-login system account whose home matches the application directory.

**Expected result:** The mattermost system account exists with nologin shell.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does the service account need interactive login?
2. Hint: No human signs in as this account.
3. Stronger hint: Use /sbin/nologin.
4. Solution: Create the account and require MATTERMOST_OS_USER_CREATED.

**Done when:** the independent `MATTERMOST_OS_USER_CREATED` validator passes.

## 173. Install the pinned Mattermost application

**Work on:** `mattermost-1` as `ec2-user`

The workload must use the reviewed version staged during handoff.

**Predict first:** Where does the archive place the application?

Run this one action:

```bash
sudo tar -xzf /opt/suta/artifacts/mattermost-team-11.10.1-linux-amd64.tar.gz -C /opt
```

**What the command means:** Extract the verified archive; its top-level mattermost directory becomes /opt/mattermost.

**Expected result:** The Mattermost 11.10.1 server binary exists under /opt/mattermost/bin.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Where does the archive place the application?
2. Hint: Its outer directory is named mattermost.
3. Stronger hint: Extract into /opt without strip-components.
4. Solution: Extract it and require MATTERMOST_INSTALLED.

**Done when:** the independent `MATTERMOST_INSTALLED` validator passes.

## 174. Remove shared write access from the Mattermost application

**Work on:** `mattermost-1` as `ec2-user`

An executable or its parent directory must not be writable by unrelated local accounts. The service account keeps its own write access to required runtime paths.

**Predict first:** Who could replace a program in a directory writable by everyone?

Run this one action:

```bash
sudo chmod -R go-w /opt/mattermost
```

**What the command means:** chmod changes permission bits. -R applies the change throughout /opt/mattermost. go-w removes write access for the group and everyone else, while preserving owner access, executable bits and more restrictive files such as mode 0600 configuration.

**Expected result:** The application root, bin and config directories and the executable have no group or other write bit. Mode 0777 entries become 0755; existing 0600 files and 0750 data directories keep their stricter modes.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who could replace a program in a directory writable by everyone?
2. Hint: The program and its parent directories both need protection.
3. Stronger hint: Remove group and other write access while preserving the owner permissions.
4. Solution: Run the displayed chmod action, then inspect the four listed paths.

**Done when:** the independent `MATTERMOST_TREE_SECURE` validator passes.

## 175. Create the /opt/mattermost/data directory

**Work on:** `mattermost-1` as `ec2-user`

Create /opt/mattermost/data before setting its ownership and permissions.

**Predict first:** Which account needs write access here?

Run this one action:

```bash
sudo mkdir -p /opt/mattermost/data
```

**What the command means:** sudo mkdir -p creates /opt/mattermost/data (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and /opt/mattermost/data exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account needs write access here?
2. Hint: Only the Mattermost service account.
3. Stronger hint: Create /opt/mattermost/data as mattermost:mattermost with mode 0750.
4. Solution: Run the registered install -d command and require MATTERMOST_DATA_DIR_CREATED.

**Done when:** the independent `MATTERMOST_DATA_DIR_DIRS_MADE` validator passes.

## 176. Give mattermost ownership of the /opt/mattermost/data directory

**Work on:** `mattermost-1` as `ec2-user`

The mattermost account owns /opt/mattermost/data so the intended process can use this location.

**Predict first:** Which account needs write access here?

Run this one action:

```bash
sudo chown -R mattermost:mattermost /opt/mattermost/data
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to mattermost, because a plain mkdir left them owned by root.

**Expected result:** /opt/mattermost/data is owned by mattermost.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account needs write access here?
2. Hint: Only the Mattermost service account.
3. Stronger hint: Create /opt/mattermost/data as mattermost:mattermost with mode 0750.
4. Solution: Run the registered install -d command and require MATTERMOST_DATA_DIR_CREATED.

**Done when:** the independent `MATTERMOST_DATA_DIR_DIRS_OWNED` validator passes.

## 177. Set permissions on the /opt/mattermost/data directory

**Work on:** `mattermost-1` as `ec2-user`

Mattermost needs a writable runtime-data directory owned only by its service account.

**Predict first:** Which account needs write access here?

Run this one action:

```bash
sudo chmod 0750 /opt/mattermost/data
```

**What the command means:** chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

**Expected result:** /opt/mattermost/data exists with mattermost ownership and mode 0750.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account needs write access here?
2. Hint: Only the Mattermost service account.
3. Stronger hint: Create /opt/mattermost/data as mattermost:mattermost with mode 0750.
4. Solution: Run the registered install -d command and require MATTERMOST_DATA_DIR_CREATED.

**Done when:** the independent `MATTERMOST_DATA_DIR_CREATED` validator passes.

## 178. Assign the Mattermost application tree

**Work on:** `mattermost-1` as `ec2-user`

The non-root service account must be able to read the installed application and write its runtime paths.

**Predict first:** Why not run the service as root?

Run this one action:

```bash
sudo chown -R mattermost:mattermost /opt/mattermost
```

**What the command means:** Assign the extracted tree to the dedicated service account without changing unrelated system paths.

**Expected result:** The Mattermost application tree is owned by mattermost.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why not run the service as root?
2. Hint: The application should have only the filesystem rights it needs.
3. Stronger hint: Change ownership only under /opt/mattermost.
4. Solution: Run the registered chown and require MATTERMOST_TREE_OWNED.

**Done when:** the independent `MATTERMOST_TREE_OWNED` validator passes.

## 179. Copy the Mattermost systemd unit into place

**Work on:** `mattermost-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which user should systemd run?

Run this one action:

```bash
sudo cp /opt/suta/handoff/mattermost/mattermost.service /etc/systemd/system/mattermost.service
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/mattermost.service. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/systemd/system/mattermost.service now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which user should systemd run?
2. Hint: The dedicated application account.
3. Stronger hint: User and Group must both be mattermost.
4. Solution: Install the unit and require MATTERMOST_UNIT_CREATED.

**Done when:** the independent `MATTERMOST_UNIT_COPIED` validator passes.

## 180. Set permissions on the Mattermost systemd unit

**Work on:** `mattermost-1` as `ec2-user`

The workload needs a supervised, boot-persistent service definition.

**Predict first:** Which user should systemd run?

Run this one action:

```bash
sudo chmod 0644 /etc/systemd/system/mattermost.service
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** systemd verifies the unit and its non-root identity.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which user should systemd run?
2. Hint: The dedicated application account.
3. Stronger hint: User and Group must both be mattermost.
4. Solution: Install the unit and require MATTERMOST_UNIT_CREATED.

**Done when:** the independent `MATTERMOST_UNIT_CREATED` validator passes.

## 181. Reload systemd for Mattermost

**Work on:** `mattermost-1` as `ec2-user`

systemd must discover the new unit while leaving the unconfigured application stopped.

**Predict first:** Why keep the service stopped?

Run this one action:

```bash
sudo systemctl daemon-reload
```

**What the command means:** Reload unit definitions without starting Mattermost.

**Expected result:** The unit is visible and Mattermost remains inactive.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why keep the service stopped?
2. Hint: Its database configuration is the next action.
3. Stronger hint: Reload only; do not enable or start yet.
4. Solution: Reload and require MATTERMOST_SYSTEMD_RELOADED.

**Done when:** the independent `MATTERMOST_SYSTEMD_RELOADED` validator passes.

## 182. Connect Mattermost to HAProxy

**Work on:** `mattermost-1` as `ec2-user`

The application must use the stable writer endpoint rather than a PostgreSQL node address.

**Predict first:** Which hostname must remain unchanged after a switchover?

Run this one action:

```bash
sudo vi /opt/mattermost/config/config.json
```

**What the command means:** Apply the supplied SQL and listen settings to the installed Mattermost configuration. The database password resolves through a protected field and is never rendered into chat.

Enter this exact json-patch content after SutaBot resolves only the registered role addresses and protected secret fields:

```text
{
  "SqlSettings": {
    "DriverName": "postgres",
    "DataSource": "postgres://mattermost:{{secret:mattermost_database}}@db-router-1:5432/mattermost?sslmode=disable&connect_timeout=10"
  },
  "ServiceSettings": {
    "ListenAddress": ":8065",
    "SiteURL": ""
  }
}
```

**Expected result:** The protected configuration targets db-router-1:5432 and remains readable only by the mattermost account.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which hostname must remain unchanged after a switchover?
2. Hint: Use the database router role.
3. Stronger hint: The data source must target db-router-1 port 5432 and database mattermost.
4. Solution: Apply the supplied settings through the protected credential field and require MATTERMOST_DATABASE_CONFIGURED.

**Done when:** the independent `MATTERMOST_DATABASE_CONFIGURED` validator passes.

## 183. Start and prove Mattermost

**Work on:** `mattermost-1` as `ec2-user`

The completed BUILD must prove the real application path, not only database processes.

**Predict first:** Which check exercises the whole application path?

Run this one action:

```bash
sudo systemctl enable --now mattermost
```

**What the command means:** Enable and start Mattermost; its startup migrations and health endpoint exercise the HAProxy-to-PostgreSQL path.

**Expected result:** Mattermost reports active, its system ping returns OK and database migrations complete through HAProxy.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which check exercises the whole application path?
2. Hint: Use Mattermost's system ping after the service starts.
3. Stronger hint: Also require the database route to remain db-router-1 and confirm migrated tables exist.
4. Solution: Start Mattermost, wait for readiness, then run the guided API ping and deterministic database-path validator.

**Done when:** the independent `MATTERMOST_WORKLOAD_STARTED` validator passes.

## BUILD complete

BUILD is complete only when every registered server validator passes in order and
Mattermost succeeds through the unchanged HAProxy writer endpoint. The learner's
commands—not SutaBot, chat text, or a reference configurator—must produce that state.

