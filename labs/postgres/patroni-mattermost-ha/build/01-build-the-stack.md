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
- Run one command at a time. Do not combine steps with `&&`, pipes, or scripts.
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

**What the command means:** sha256sum calculates the archive fingerprint; compare it with the digest shown in the handoff manifest.

**Expected result:** One SHA-256 digest followed by the archive path.

**Safety:** This is a read-only observation.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which value proves the staged bytes are the approved bytes?
2. Hint: Look at the first field in the output.
3. Stronger hint: Compare it with /opt/suta/artifacts/SHA256SUMS.
4. Solution: Run sha256sum on the staged archive and stop if the digest differs.

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

## 8. Create the etcd-directories-1 directories

**Work on:** `dcs-1` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo mkdir -p /etc/etcd
```

**What the command means:** sudo mkdir -p creates /etc/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 9. Give root ownership of the etcd-directories-1 directories

**Work on:** `dcs-1` as `ec2-user`

The root service must own these directories to write into them.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo chown -R root:root /etc/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 10. Lock down the etcd-directories-1 directory permissions

**Work on:** `dcs-1` as `ec2-user`

Configuration and consensus data need explicit protected locations.

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

## 11. Create the etcd-data-directory-1 directories

**Work on:** `dcs-1` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo mkdir -p /var/lib/etcd
```

**What the command means:** sudo mkdir -p creates /var/lib/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 12. Give root ownership of the etcd-data-directory-1 directories

**Work on:** `dcs-1` as `ec2-user`

The root service must own these directories to write into them.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo chown -R root:root /var/lib/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 13. Lock down the etcd-data-directory-1 directory permissions

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

## 27. Create the etcd-directories-2 directories

**Work on:** `dcs-2` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo mkdir -p /etc/etcd
```

**What the command means:** sudo mkdir -p creates /etc/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 28. Give root ownership of the etcd-directories-2 directories

**Work on:** `dcs-2` as `ec2-user`

The root service must own these directories to write into them.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo chown -R root:root /etc/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 29. Lock down the etcd-directories-2 directory permissions

**Work on:** `dcs-2` as `ec2-user`

Configuration and consensus data need explicit protected locations.

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

## 30. Create the etcd-data-directory-2 directories

**Work on:** `dcs-2` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo mkdir -p /var/lib/etcd
```

**What the command means:** sudo mkdir -p creates /var/lib/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 31. Give root ownership of the etcd-data-directory-2 directories

**Work on:** `dcs-2` as `ec2-user`

The root service must own these directories to write into them.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo chown -R root:root /var/lib/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 32. Lock down the etcd-data-directory-2 directory permissions

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

## 46. Create the etcd-directories-3 directories

**Work on:** `dcs-3` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo mkdir -p /etc/etcd
```

**What the command means:** sudo mkdir -p creates /etc/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 47. Give root ownership of the etcd-directories-3 directories

**Work on:** `dcs-3` as `ec2-user`

The root service must own these directories to write into them.

**Predict first:** Who should be able to read the future member private key?

Run this one action:

```bash
sudo chown -R root:root /etc/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should be able to read the future member private key?
2. Hint: Only root needs access in this lab.
3. Stronger hint: Use mode 0700 for both directories.
4. Solution: Create /etc/etcd with root ownership and mode 0700.

**Done when:** the independent `ETCD_CONFIG_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 48. Lock down the etcd-directories-3 directory permissions

**Work on:** `dcs-3` as `ec2-user`

Configuration and consensus data need explicit protected locations.

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

## 49. Create the etcd-data-directory-3 directories

**Work on:** `dcs-3` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo mkdir -p /var/lib/etcd
```

**What the command means:** sudo mkdir -p creates /var/lib/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_MADE` validator passes.

## 50. Give root ownership of the etcd-data-directory-3 directories

**Work on:** `dcs-3` as `ec2-user`

The root service must own these directories to write into them.

**Predict first:** Why separate configuration from consensus data?

Run this one action:

```bash
sudo chown -R root:root /var/lib/etcd
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why separate configuration from consensus data?
2. Hint: They have different lifecycle and recovery responsibilities.
3. Stronger hint: Create /var/lib/etcd with root ownership and 0700.
4. Solution: Run the registered install -d command and require ETCD_DATA_DIRECTORY_SECURE.

**Done when:** the independent `ETCD_DATA_DIRECTORY_SECURE_DIRS_OWNED` validator passes.

## 51. Lock down the etcd-data-directory-3 directory permissions

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

## 78. Create the patroni-directories-1 directories

**Work on:** `pg-ha-1` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Which account runs Patroni?

Run this one action:

```bash
sudo mkdir -p /opt/patroni /etc/patroni
```

**What the command means:** sudo mkdir -p creates /opt/patroni /etc/patroni (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account runs Patroni?
2. Hint: Use the same postgres OS account that owns PostgreSQL.
3. Stronger hint: Both /opt/patroni and /etc/patroni need postgres ownership.
4. Solution: Run the displayed command and require PATRONI_DIRS_CREATED.

**Done when:** the independent `PATRONI_DIRS_DIRS_MADE` validator passes.

## 79. Give postgres ownership of the patroni-directories-1 directories

**Work on:** `pg-ha-1` as `ec2-user`

The postgres service must own these directories to write into them.

**Predict first:** Which account runs Patroni?

Run this one action:

```bash
sudo chown -R postgres:postgres /opt/patroni /etc/patroni
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by postgres.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account runs Patroni?
2. Hint: Use the same postgres OS account that owns PostgreSQL.
3. Stronger hint: Both /opt/patroni and /etc/patroni need postgres ownership.
4. Solution: Run the displayed command and require PATRONI_DIRS_CREATED.

**Done when:** the independent `PATRONI_DIRS_DIRS_OWNED` validator passes.

## 80. Lock down the patroni-directories-1 directory permissions

**Work on:** `pg-ha-1` as `ec2-user`

Patroni software and protected configuration need explicit postgres-owned locations.

**Predict first:** Which account runs Patroni?

Run this one action:

```bash
sudo chmod 0750 /opt/patroni /etc/patroni
```

**What the command means:** chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

**Expected result:** Both directories exist with postgres ownership and mode 0750.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account runs Patroni?
2. Hint: Use the same postgres OS account that owns PostgreSQL.
3. Stronger hint: Both /opt/patroni and /etc/patroni need postgres ownership.
4. Solution: Run the displayed command and require PATRONI_DIRS_CREATED.

**Done when:** the independent `PATRONI_DIRS_CREATED` validator passes.

## 81. Create the postgresql-socket-directory-1 directories

**Work on:** `pg-ha-1` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Is this directory permanent database storage?

Run this one action:

```bash
sudo mkdir -p /var/run/postgresql
```

**What the command means:** sudo mkdir -p creates /var/run/postgresql (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Is this directory permanent database storage?
2. Hint: It holds runtime socket files, not table data.
3. Stronger hint: The path is /var/run/postgresql.
4. Solution: Create the directory and require PATRONI_SOCKET_DIR_CREATED.

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_MADE` validator passes.

## 82. Give postgres ownership of the postgresql-socket-directory-1 directories

**Work on:** `pg-ha-1` as `ec2-user`

The postgres service must own these directories to write into them.

**Predict first:** Is this directory permanent database storage?

Run this one action:

```bash
sudo chown -R postgres:postgres /var/run/postgresql
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by postgres.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Is this directory permanent database storage?
2. Hint: It holds runtime socket files, not table data.
3. Stronger hint: The path is /var/run/postgresql.
4. Solution: Create the directory and require PATRONI_SOCKET_DIR_CREATED.

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_OWNED` validator passes.

## 83. Lock down the postgresql-socket-directory-1 directory permissions

**Work on:** `pg-ha-1` as `ec2-user`

Local clients and Patroni need a writable runtime location for the Unix socket.

**Predict first:** Is this directory permanent database storage?

Run this one action:

```bash
sudo chmod 0755 /var/run/postgresql
```

**What the command means:** chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

**Expected result:** /var/run/postgresql exists with postgres ownership.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Is this directory permanent database storage?
2. Hint: It holds runtime socket files, not table data.
3. Stronger hint: The path is /var/run/postgresql.
4. Solution: Create the directory and require PATRONI_SOCKET_DIR_CREATED.

**Done when:** the independent `PATRONI_SOCKET_DIR_CREATED` validator passes.

## 84. Install Patroni on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

Each PostgreSQL node needs the same pinned Patroni runtime.

**Predict first:** Why install the same version on all members?

Run this one action:

```bash
sudo tar -xzf /opt/suta/artifacts/patroni-4.1.4-python39-centos9-amd64.tar.gz -C /opt/patroni --strip-components=1
```

**What the command means:** tar extracts the verified Patroni runtime into the prepared directory and removes the archive's outer folder.

**Expected result:** Patroni 4.1.4 Python modules exist under /opt/patroni.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why install the same version on all members?
2. Hint: Cluster behavior must not depend on mixed Patroni code.
3. Stronger hint: The locked version is 4.1.4.
4. Solution: Extract the staged archive and require PATRONI_SOFTWARE_INSTALLED.

**Done when:** the independent `PATRONI_SOFTWARE_INSTALLED` validator passes.

## 85. Copy the etcd CA certificate on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Does a CA certificate contain the CA private key?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/ca.crt /etc/patroni/etcd-ca.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-ca.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/patroni/etcd-ca.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does a CA certificate contain the CA private key?
2. Hint: A .crt file is public verification material.
3. Stronger hint: The destination is /etc/patroni/etcd-ca.crt.
4. Solution: Install the CA certificate and require PATRONI_CA_INSTALLED.

**Done when:** the independent `PATRONI_CA_COPIED` validator passes.

## 86. Set permissions on the etcd CA certificate on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

The permissions decide who may read this file before ownership is handed to postgres.

**Predict first:** Does a CA certificate contain the CA private key?

Run this one action:

```bash
sudo chmod 0644 /etc/patroni/etcd-ca.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Expected result:** /etc/patroni/etcd-ca.crt now has mode 644.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does a CA certificate contain the CA private key?
2. Hint: A .crt file is public verification material.
3. Stronger hint: The destination is /etc/patroni/etcd-ca.crt.
4. Solution: Install the CA certificate and require PATRONI_CA_INSTALLED.

**Done when:** the independent `PATRONI_CA_MODE_SET` validator passes.

## 87. Give postgres ownership of the etcd CA certificate on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

Patroni must verify that it is talking to the assigned etcd cluster.

**Predict first:** Does a CA certificate contain the CA private key?

Run this one action:

```bash
sudo chown postgres:postgres /etc/patroni/etcd-ca.crt
```

**What the command means:** chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Expected result:** The CA certificate is readable by Patroni and contains no private key.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does a CA certificate contain the CA private key?
2. Hint: A .crt file is public verification material.
3. Stronger hint: The destination is /etc/patroni/etcd-ca.crt.
4. Solution: Install the CA certificate and require PATRONI_CA_INSTALLED.

**Done when:** the independent `PATRONI_CA_INSTALLED` validator passes.

## 88. Copy Patroni's etcd client certificate on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which side presents this certificate?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/client.crt /etc/patroni/etcd-client.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/patroni/etcd-client.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which side presents this certificate?
2. Hint: Patroni is the client of etcd.
3. Stronger hint: This is public identity material; the private key is handled next.
4. Solution: Install it and require PATRONI_CLIENT_CERT_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_CERT_COPIED` validator passes.

## 89. Set permissions on Patroni's etcd client certificate on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

The permissions decide who may read this file before ownership is handed to postgres.

**Predict first:** Which side presents this certificate?

Run this one action:

```bash
sudo chmod 0644 /etc/patroni/etcd-client.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Expected result:** /etc/patroni/etcd-client.crt now has mode 644.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which side presents this certificate?
2. Hint: Patroni is the client of etcd.
3. Stronger hint: This is public identity material; the private key is handled next.
4. Solution: Install it and require PATRONI_CLIENT_CERT_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_CERT_MODE_SET` validator passes.

## 90. Give postgres ownership of Patroni's etcd client certificate on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

etcd mutual TLS also verifies Patroni's client identity.

**Predict first:** Which side presents this certificate?

Run this one action:

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.crt
```

**What the command means:** chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Expected result:** The signed client certificate is postgres-owned and mode 0644.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which side presents this certificate?
2. Hint: Patroni is the client of etcd.
3. Stronger hint: This is public identity material; the private key is handled next.
4. Solution: Install it and require PATRONI_CLIENT_CERT_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_CERT_INSTALLED` validator passes.

## 91. Copy Patroni's protected etcd client key on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why is this file more restricted than the certificate?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/client.key /etc/patroni/etcd-client.key
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.key. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/patroni/etcd-client.key now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why is this file more restricted than the certificate?
2. Hint: Anyone holding the private key can impersonate the client.
3. Stronger hint: Use mode 0600 and never run cat on it.
4. Solution: Install it and require PATRONI_CLIENT_KEY_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_KEY_COPIED` validator passes.

## 92. Set permissions on Patroni's protected etcd client key on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

The permissions decide who may read this file before ownership is handed to postgres.

**Predict first:** Why is this file more restricted than the certificate?

Run this one action:

```bash
sudo chmod 0600 /etc/patroni/etcd-client.key
```

**What the command means:** chmod 0600 sets the file's permissions to 600 (owner read/write, group/others read - or owner-only for a private key).

**Expected result:** /etc/patroni/etcd-client.key now has mode 600.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why is this file more restricted than the certificate?
2. Hint: Anyone holding the private key can impersonate the client.
3. Stronger hint: Use mode 0600 and never run cat on it.
4. Solution: Install it and require PATRONI_CLIENT_KEY_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_KEY_MODE_SET` validator passes.

## 93. Give postgres ownership of Patroni's protected etcd client key on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

The private key proves possession of the client identity and must not be exposed.

**Predict first:** Why is this file more restricted than the certificate?

Run this one action:

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.key
```

**What the command means:** chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Expected result:** The command shows no key material and the destination mode is 0600.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why is this file more restricted than the certificate?
2. Hint: Anyone holding the private key can impersonate the client.
3. Stronger hint: Use mode 0600 and never run cat on it.
4. Solution: Install it and require PATRONI_CLIENT_KEY_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_KEY_INSTALLED` validator passes.

## 94. Copy the Patroni launcher on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why use a wrapper instead of a floating pip command?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/patroni /usr/local/bin/patroni
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patroni. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/patroni now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why use a wrapper instead of a floating pip command?
2. Hint: It binds systemd to the pinned runtime path.
3. Stronger hint: The destination is /usr/local/bin/patroni.
4. Solution: Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONI_WRAPPER_COPIED` validator passes.

## 95. Make the Patroni launcher on pg-ha-1 runnable

**Work on:** `pg-ha-1` as `ec2-user`

The pinned Python runtime needs one stable command path for systemd.

**Predict first:** Why use a wrapper instead of a floating pip command?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/patroni
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** /usr/local/bin/patroni is executable and reports Patroni 4.1.4.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why use a wrapper instead of a floating pip command?
2. Hint: It binds systemd to the pinned runtime path.
3. Stronger hint: The destination is /usr/local/bin/patroni.
4. Solution: Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONI_WRAPPER_INSTALLED` validator passes.

## 96. Copy the patronictl launcher on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which tool runs the service and which tool operates the cluster?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/patronictl /usr/local/bin/patronictl
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patronictl. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/patronictl now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which tool runs the service and which tool operates the cluster?
2. Hint: patroni runs; patronictl controls and inspects.
3. Stronger hint: The operator command ends in ctl.
4. Solution: Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONICTL_WRAPPER_COPIED` validator passes.

## 97. Make the patronictl launcher on pg-ha-1 runnable

**Work on:** `pg-ha-1` as `ec2-user`

Operators need a stable absolute path for cluster inspection and planned operations.

**Predict first:** Which tool runs the service and which tool operates the cluster?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/patronictl
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** /usr/local/bin/patronictl is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which tool runs the service and which tool operates the cluster?
2. Hint: patroni runs; patronictl controls and inspects.
3. Stronger hint: The operator command ends in ctl.
4. Solution: Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONICTL_WRAPPER_INSTALLED` validator passes.

## 98. Copy the Patroni systemd unit on pg-ha-1 into place

**Work on:** `pg-ha-1` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which process should systemd start?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/patroni.service /etc/systemd/system/patroni.service
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/patroni.service. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/systemd/system/patroni.service now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which process should systemd start?
2. Hint: Patroni owns PostgreSQL startup in this cluster.
3. Stronger hint: ExecStart must call /usr/local/bin/patroni.
4. Solution: Install the unit and require PATRONI_UNIT_CREATED.

**Done when:** the independent `PATRONI_UNIT_COPIED` validator passes.

## 99. Set permissions on the Patroni systemd unit on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

systemd must run Patroni—not postgres directly—as the owner of the PostgreSQL lifecycle.

**Predict first:** Which process should systemd start?

Run this one action:

```bash
sudo chmod 0644 /etc/systemd/system/patroni.service
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The unit parses, names the postgres user and starts Patroni with /etc/patroni/patroni.yml.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which process should systemd start?
2. Hint: Patroni owns PostgreSQL startup in this cluster.
3. Stronger hint: ExecStart must call /usr/local/bin/patroni.
4. Solution: Install the unit and require PATRONI_UNIT_CREATED.

**Done when:** the independent `PATRONI_UNIT_CREATED` validator passes.

## 100. Reload systemd on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

systemd does not use a newly installed unit until its manager configuration is reloaded.

**Predict first:** Does daemon-reload start Patroni?

Run this one action:

```bash
sudo systemctl daemon-reload
```

**What the command means:** daemon-reload asks systemd to reread unit files without starting Patroni.

**Expected result:** The command returns to the prompt and Patroni remains inactive.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does daemon-reload start Patroni?
2. Hint: It rereads definitions only.
3. Stronger hint: The service must stay inactive until its ordered start step.
4. Solution: Reload systemd and require PATRONI_SYSTEMD_RELOADED.

**Done when:** the independent `PATRONI_SYSTEMD_RELOADED` validator passes.

## 101. Configure Patroni on pg-ha-1

**Work on:** `pg-ha-1` as `ec2-user`

The first Patroni member defines the cluster scope, DCS transport, bootstrap rules and local PostgreSQL identity.

**Predict first:** Which fields identify this cluster and this member?

Run this one action:

```bash
sudo vi /etc/patroni/patroni.yml
```

**What the command means:** Enter the role-resolved pg-ha-1 YAML supplied for this step. Secret tokens are inserted through the protected field and are never rendered into chat.

Enter this exact yaml content after SutaBot resolves only the registered role addresses and protected secret fields:

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

**Expected result:** The saved configuration passes YAML, secret-permission and Patroni contract validation.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which fields identify this cluster and this member?
2. Hint: Find scope and name near the top.
3. Stronger hint: Confirm HTTPS etcd endpoints, /opt/pgsql/data, checksums, slots, rewind and SCRAM rules.
4. Solution: Enter the supplied pg-ha-1 configuration and save; the validator checks structure without exposing passwords.

**Done when:** the independent `PATRONI_MEMBER_1_CONFIGURED` validator passes.

## 102. Create the patroni-directories-2 directories

**Work on:** `pg-ha-2` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Which account runs Patroni?

Run this one action:

```bash
sudo mkdir -p /opt/patroni /etc/patroni
```

**What the command means:** sudo mkdir -p creates /opt/patroni /etc/patroni (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account runs Patroni?
2. Hint: Use the same postgres OS account that owns PostgreSQL.
3. Stronger hint: Both /opt/patroni and /etc/patroni need postgres ownership.
4. Solution: Run the displayed command and require PATRONI_DIRS_CREATED.

**Done when:** the independent `PATRONI_DIRS_DIRS_MADE` validator passes.

## 103. Give postgres ownership of the patroni-directories-2 directories

**Work on:** `pg-ha-2` as `ec2-user`

The postgres service must own these directories to write into them.

**Predict first:** Which account runs Patroni?

Run this one action:

```bash
sudo chown -R postgres:postgres /opt/patroni /etc/patroni
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by postgres.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account runs Patroni?
2. Hint: Use the same postgres OS account that owns PostgreSQL.
3. Stronger hint: Both /opt/patroni and /etc/patroni need postgres ownership.
4. Solution: Run the displayed command and require PATRONI_DIRS_CREATED.

**Done when:** the independent `PATRONI_DIRS_DIRS_OWNED` validator passes.

## 104. Lock down the patroni-directories-2 directory permissions

**Work on:** `pg-ha-2` as `ec2-user`

Patroni software and protected configuration need explicit postgres-owned locations.

**Predict first:** Which account runs Patroni?

Run this one action:

```bash
sudo chmod 0750 /opt/patroni /etc/patroni
```

**What the command means:** chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

**Expected result:** Both directories exist with postgres ownership and mode 0750.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account runs Patroni?
2. Hint: Use the same postgres OS account that owns PostgreSQL.
3. Stronger hint: Both /opt/patroni and /etc/patroni need postgres ownership.
4. Solution: Run the displayed command and require PATRONI_DIRS_CREATED.

**Done when:** the independent `PATRONI_DIRS_CREATED` validator passes.

## 105. Create the postgresql-socket-directory-2 directories

**Work on:** `pg-ha-2` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Is this directory permanent database storage?

Run this one action:

```bash
sudo mkdir -p /var/run/postgresql
```

**What the command means:** sudo mkdir -p creates /var/run/postgresql (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Is this directory permanent database storage?
2. Hint: It holds runtime socket files, not table data.
3. Stronger hint: The path is /var/run/postgresql.
4. Solution: Create the directory and require PATRONI_SOCKET_DIR_CREATED.

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_MADE` validator passes.

## 106. Give postgres ownership of the postgresql-socket-directory-2 directories

**Work on:** `pg-ha-2` as `ec2-user`

The postgres service must own these directories to write into them.

**Predict first:** Is this directory permanent database storage?

Run this one action:

```bash
sudo chown -R postgres:postgres /var/run/postgresql
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by postgres.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Is this directory permanent database storage?
2. Hint: It holds runtime socket files, not table data.
3. Stronger hint: The path is /var/run/postgresql.
4. Solution: Create the directory and require PATRONI_SOCKET_DIR_CREATED.

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_OWNED` validator passes.

## 107. Lock down the postgresql-socket-directory-2 directory permissions

**Work on:** `pg-ha-2` as `ec2-user`

Local clients and Patroni need a writable runtime location for the Unix socket.

**Predict first:** Is this directory permanent database storage?

Run this one action:

```bash
sudo chmod 0755 /var/run/postgresql
```

**What the command means:** chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

**Expected result:** /var/run/postgresql exists with postgres ownership.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Is this directory permanent database storage?
2. Hint: It holds runtime socket files, not table data.
3. Stronger hint: The path is /var/run/postgresql.
4. Solution: Create the directory and require PATRONI_SOCKET_DIR_CREATED.

**Done when:** the independent `PATRONI_SOCKET_DIR_CREATED` validator passes.

## 108. Install Patroni on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

Each PostgreSQL node needs the same pinned Patroni runtime.

**Predict first:** Why install the same version on all members?

Run this one action:

```bash
sudo tar -xzf /opt/suta/artifacts/patroni-4.1.4-python39-centos9-amd64.tar.gz -C /opt/patroni --strip-components=1
```

**What the command means:** tar extracts the verified Patroni runtime into the prepared directory and removes the archive's outer folder.

**Expected result:** Patroni 4.1.4 Python modules exist under /opt/patroni.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why install the same version on all members?
2. Hint: Cluster behavior must not depend on mixed Patroni code.
3. Stronger hint: The locked version is 4.1.4.
4. Solution: Extract the staged archive and require PATRONI_SOFTWARE_INSTALLED.

**Done when:** the independent `PATRONI_SOFTWARE_INSTALLED` validator passes.

## 109. Copy the etcd CA certificate on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Does a CA certificate contain the CA private key?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/ca.crt /etc/patroni/etcd-ca.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-ca.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/patroni/etcd-ca.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does a CA certificate contain the CA private key?
2. Hint: A .crt file is public verification material.
3. Stronger hint: The destination is /etc/patroni/etcd-ca.crt.
4. Solution: Install the CA certificate and require PATRONI_CA_INSTALLED.

**Done when:** the independent `PATRONI_CA_COPIED` validator passes.

## 110. Set permissions on the etcd CA certificate on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

The permissions decide who may read this file before ownership is handed to postgres.

**Predict first:** Does a CA certificate contain the CA private key?

Run this one action:

```bash
sudo chmod 0644 /etc/patroni/etcd-ca.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Expected result:** /etc/patroni/etcd-ca.crt now has mode 644.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does a CA certificate contain the CA private key?
2. Hint: A .crt file is public verification material.
3. Stronger hint: The destination is /etc/patroni/etcd-ca.crt.
4. Solution: Install the CA certificate and require PATRONI_CA_INSTALLED.

**Done when:** the independent `PATRONI_CA_MODE_SET` validator passes.

## 111. Give postgres ownership of the etcd CA certificate on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

Patroni must verify that it is talking to the assigned etcd cluster.

**Predict first:** Does a CA certificate contain the CA private key?

Run this one action:

```bash
sudo chown postgres:postgres /etc/patroni/etcd-ca.crt
```

**What the command means:** chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Expected result:** The CA certificate is readable by Patroni and contains no private key.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does a CA certificate contain the CA private key?
2. Hint: A .crt file is public verification material.
3. Stronger hint: The destination is /etc/patroni/etcd-ca.crt.
4. Solution: Install the CA certificate and require PATRONI_CA_INSTALLED.

**Done when:** the independent `PATRONI_CA_INSTALLED` validator passes.

## 112. Copy Patroni's etcd client certificate on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which side presents this certificate?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/client.crt /etc/patroni/etcd-client.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/patroni/etcd-client.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which side presents this certificate?
2. Hint: Patroni is the client of etcd.
3. Stronger hint: This is public identity material; the private key is handled next.
4. Solution: Install it and require PATRONI_CLIENT_CERT_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_CERT_COPIED` validator passes.

## 113. Set permissions on Patroni's etcd client certificate on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

The permissions decide who may read this file before ownership is handed to postgres.

**Predict first:** Which side presents this certificate?

Run this one action:

```bash
sudo chmod 0644 /etc/patroni/etcd-client.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Expected result:** /etc/patroni/etcd-client.crt now has mode 644.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which side presents this certificate?
2. Hint: Patroni is the client of etcd.
3. Stronger hint: This is public identity material; the private key is handled next.
4. Solution: Install it and require PATRONI_CLIENT_CERT_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_CERT_MODE_SET` validator passes.

## 114. Give postgres ownership of Patroni's etcd client certificate on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

etcd mutual TLS also verifies Patroni's client identity.

**Predict first:** Which side presents this certificate?

Run this one action:

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.crt
```

**What the command means:** chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Expected result:** The signed client certificate is postgres-owned and mode 0644.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which side presents this certificate?
2. Hint: Patroni is the client of etcd.
3. Stronger hint: This is public identity material; the private key is handled next.
4. Solution: Install it and require PATRONI_CLIENT_CERT_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_CERT_INSTALLED` validator passes.

## 115. Copy Patroni's protected etcd client key on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why is this file more restricted than the certificate?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/client.key /etc/patroni/etcd-client.key
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.key. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/patroni/etcd-client.key now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why is this file more restricted than the certificate?
2. Hint: Anyone holding the private key can impersonate the client.
3. Stronger hint: Use mode 0600 and never run cat on it.
4. Solution: Install it and require PATRONI_CLIENT_KEY_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_KEY_COPIED` validator passes.

## 116. Set permissions on Patroni's protected etcd client key on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

The permissions decide who may read this file before ownership is handed to postgres.

**Predict first:** Why is this file more restricted than the certificate?

Run this one action:

```bash
sudo chmod 0600 /etc/patroni/etcd-client.key
```

**What the command means:** chmod 0600 sets the file's permissions to 600 (owner read/write, group/others read - or owner-only for a private key).

**Expected result:** /etc/patroni/etcd-client.key now has mode 600.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why is this file more restricted than the certificate?
2. Hint: Anyone holding the private key can impersonate the client.
3. Stronger hint: Use mode 0600 and never run cat on it.
4. Solution: Install it and require PATRONI_CLIENT_KEY_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_KEY_MODE_SET` validator passes.

## 117. Give postgres ownership of Patroni's protected etcd client key on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

The private key proves possession of the client identity and must not be exposed.

**Predict first:** Why is this file more restricted than the certificate?

Run this one action:

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.key
```

**What the command means:** chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Expected result:** The command shows no key material and the destination mode is 0600.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why is this file more restricted than the certificate?
2. Hint: Anyone holding the private key can impersonate the client.
3. Stronger hint: Use mode 0600 and never run cat on it.
4. Solution: Install it and require PATRONI_CLIENT_KEY_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_KEY_INSTALLED` validator passes.

## 118. Copy the Patroni launcher on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why use a wrapper instead of a floating pip command?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/patroni /usr/local/bin/patroni
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patroni. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/patroni now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why use a wrapper instead of a floating pip command?
2. Hint: It binds systemd to the pinned runtime path.
3. Stronger hint: The destination is /usr/local/bin/patroni.
4. Solution: Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONI_WRAPPER_COPIED` validator passes.

## 119. Make the Patroni launcher on pg-ha-2 runnable

**Work on:** `pg-ha-2` as `ec2-user`

The pinned Python runtime needs one stable command path for systemd.

**Predict first:** Why use a wrapper instead of a floating pip command?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/patroni
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** /usr/local/bin/patroni is executable and reports Patroni 4.1.4.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why use a wrapper instead of a floating pip command?
2. Hint: It binds systemd to the pinned runtime path.
3. Stronger hint: The destination is /usr/local/bin/patroni.
4. Solution: Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONI_WRAPPER_INSTALLED` validator passes.

## 120. Copy the patronictl launcher on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which tool runs the service and which tool operates the cluster?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/patronictl /usr/local/bin/patronictl
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patronictl. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/patronictl now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which tool runs the service and which tool operates the cluster?
2. Hint: patroni runs; patronictl controls and inspects.
3. Stronger hint: The operator command ends in ctl.
4. Solution: Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONICTL_WRAPPER_COPIED` validator passes.

## 121. Make the patronictl launcher on pg-ha-2 runnable

**Work on:** `pg-ha-2` as `ec2-user`

Operators need a stable absolute path for cluster inspection and planned operations.

**Predict first:** Which tool runs the service and which tool operates the cluster?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/patronictl
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** /usr/local/bin/patronictl is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which tool runs the service and which tool operates the cluster?
2. Hint: patroni runs; patronictl controls and inspects.
3. Stronger hint: The operator command ends in ctl.
4. Solution: Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONICTL_WRAPPER_INSTALLED` validator passes.

## 122. Copy the Patroni systemd unit on pg-ha-2 into place

**Work on:** `pg-ha-2` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which process should systemd start?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/patroni.service /etc/systemd/system/patroni.service
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/patroni.service. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/systemd/system/patroni.service now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which process should systemd start?
2. Hint: Patroni owns PostgreSQL startup in this cluster.
3. Stronger hint: ExecStart must call /usr/local/bin/patroni.
4. Solution: Install the unit and require PATRONI_UNIT_CREATED.

**Done when:** the independent `PATRONI_UNIT_COPIED` validator passes.

## 123. Set permissions on the Patroni systemd unit on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

systemd must run Patroni—not postgres directly—as the owner of the PostgreSQL lifecycle.

**Predict first:** Which process should systemd start?

Run this one action:

```bash
sudo chmod 0644 /etc/systemd/system/patroni.service
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The unit parses, names the postgres user and starts Patroni with /etc/patroni/patroni.yml.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which process should systemd start?
2. Hint: Patroni owns PostgreSQL startup in this cluster.
3. Stronger hint: ExecStart must call /usr/local/bin/patroni.
4. Solution: Install the unit and require PATRONI_UNIT_CREATED.

**Done when:** the independent `PATRONI_UNIT_CREATED` validator passes.

## 124. Reload systemd on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

systemd does not use a newly installed unit until its manager configuration is reloaded.

**Predict first:** Does daemon-reload start Patroni?

Run this one action:

```bash
sudo systemctl daemon-reload
```

**What the command means:** daemon-reload asks systemd to reread unit files without starting Patroni.

**Expected result:** The command returns to the prompt and Patroni remains inactive.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does daemon-reload start Patroni?
2. Hint: It rereads definitions only.
3. Stronger hint: The service must stay inactive until its ordered start step.
4. Solution: Reload systemd and require PATRONI_SYSTEMD_RELOADED.

**Done when:** the independent `PATRONI_SYSTEMD_RELOADED` validator passes.

## 125. Configure Patroni on pg-ha-2

**Work on:** `pg-ha-2` as `ec2-user`

The first replica shares the cluster contract but has its own member identity and addresses.

**Predict first:** Which values distinguish pg-ha-2?

Run this one action:

```bash
sudo vi /etc/patroni/patroni.yml
```

**What the command means:** Enter the supplied pg-ha-2 YAML. Protected secrets resolve outside chat.

Enter this exact yaml content after SutaBot resolves only the registered role addresses and protected secret fields:

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

**Expected result:** The file names pg-ha-2 and passes the Patroni contract validator.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which values distinguish pg-ha-2?
2. Hint: Inspect name, REST address and PostgreSQL address.
3. Stronger hint: Keep scope, etcd endpoints, credentials and recovery policy unchanged.
4. Solution: Enter the supplied YAML and require PATRONI_MEMBER_2_CONFIGURED.

**Done when:** the independent `PATRONI_MEMBER_2_CONFIGURED` validator passes.

## 126. Create the patroni-directories-3 directories

**Work on:** `pg-ha-3` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Which account runs Patroni?

Run this one action:

```bash
sudo mkdir -p /opt/patroni /etc/patroni
```

**What the command means:** sudo mkdir -p creates /opt/patroni /etc/patroni (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account runs Patroni?
2. Hint: Use the same postgres OS account that owns PostgreSQL.
3. Stronger hint: Both /opt/patroni and /etc/patroni need postgres ownership.
4. Solution: Run the displayed command and require PATRONI_DIRS_CREATED.

**Done when:** the independent `PATRONI_DIRS_DIRS_MADE` validator passes.

## 127. Give postgres ownership of the patroni-directories-3 directories

**Work on:** `pg-ha-3` as `ec2-user`

The postgres service must own these directories to write into them.

**Predict first:** Which account runs Patroni?

Run this one action:

```bash
sudo chown -R postgres:postgres /opt/patroni /etc/patroni
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by postgres.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account runs Patroni?
2. Hint: Use the same postgres OS account that owns PostgreSQL.
3. Stronger hint: Both /opt/patroni and /etc/patroni need postgres ownership.
4. Solution: Run the displayed command and require PATRONI_DIRS_CREATED.

**Done when:** the independent `PATRONI_DIRS_DIRS_OWNED` validator passes.

## 128. Lock down the patroni-directories-3 directory permissions

**Work on:** `pg-ha-3` as `ec2-user`

Patroni software and protected configuration need explicit postgres-owned locations.

**Predict first:** Which account runs Patroni?

Run this one action:

```bash
sudo chmod 0750 /opt/patroni /etc/patroni
```

**What the command means:** chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

**Expected result:** Both directories exist with postgres ownership and mode 0750.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account runs Patroni?
2. Hint: Use the same postgres OS account that owns PostgreSQL.
3. Stronger hint: Both /opt/patroni and /etc/patroni need postgres ownership.
4. Solution: Run the displayed command and require PATRONI_DIRS_CREATED.

**Done when:** the independent `PATRONI_DIRS_CREATED` validator passes.

## 129. Create the postgresql-socket-directory-3 directories

**Work on:** `pg-ha-3` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Is this directory permanent database storage?

Run this one action:

```bash
sudo mkdir -p /var/run/postgresql
```

**What the command means:** sudo mkdir -p creates /var/run/postgresql (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Is this directory permanent database storage?
2. Hint: It holds runtime socket files, not table data.
3. Stronger hint: The path is /var/run/postgresql.
4. Solution: Create the directory and require PATRONI_SOCKET_DIR_CREATED.

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_MADE` validator passes.

## 130. Give postgres ownership of the postgresql-socket-directory-3 directories

**Work on:** `pg-ha-3` as `ec2-user`

The postgres service must own these directories to write into them.

**Predict first:** Is this directory permanent database storage?

Run this one action:

```bash
sudo chown -R postgres:postgres /var/run/postgresql
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by postgres.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Is this directory permanent database storage?
2. Hint: It holds runtime socket files, not table data.
3. Stronger hint: The path is /var/run/postgresql.
4. Solution: Create the directory and require PATRONI_SOCKET_DIR_CREATED.

**Done when:** the independent `PATRONI_SOCKET_DIR_DIRS_OWNED` validator passes.

## 131. Lock down the postgresql-socket-directory-3 directory permissions

**Work on:** `pg-ha-3` as `ec2-user`

Local clients and Patroni need a writable runtime location for the Unix socket.

**Predict first:** Is this directory permanent database storage?

Run this one action:

```bash
sudo chmod 0755 /var/run/postgresql
```

**What the command means:** chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

**Expected result:** /var/run/postgresql exists with postgres ownership.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Is this directory permanent database storage?
2. Hint: It holds runtime socket files, not table data.
3. Stronger hint: The path is /var/run/postgresql.
4. Solution: Create the directory and require PATRONI_SOCKET_DIR_CREATED.

**Done when:** the independent `PATRONI_SOCKET_DIR_CREATED` validator passes.

## 132. Install Patroni on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

Each PostgreSQL node needs the same pinned Patroni runtime.

**Predict first:** Why install the same version on all members?

Run this one action:

```bash
sudo tar -xzf /opt/suta/artifacts/patroni-4.1.4-python39-centos9-amd64.tar.gz -C /opt/patroni --strip-components=1
```

**What the command means:** tar extracts the verified Patroni runtime into the prepared directory and removes the archive's outer folder.

**Expected result:** Patroni 4.1.4 Python modules exist under /opt/patroni.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why install the same version on all members?
2. Hint: Cluster behavior must not depend on mixed Patroni code.
3. Stronger hint: The locked version is 4.1.4.
4. Solution: Extract the staged archive and require PATRONI_SOFTWARE_INSTALLED.

**Done when:** the independent `PATRONI_SOFTWARE_INSTALLED` validator passes.

## 133. Copy the etcd CA certificate on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Does a CA certificate contain the CA private key?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/ca.crt /etc/patroni/etcd-ca.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-ca.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/patroni/etcd-ca.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does a CA certificate contain the CA private key?
2. Hint: A .crt file is public verification material.
3. Stronger hint: The destination is /etc/patroni/etcd-ca.crt.
4. Solution: Install the CA certificate and require PATRONI_CA_INSTALLED.

**Done when:** the independent `PATRONI_CA_COPIED` validator passes.

## 134. Set permissions on the etcd CA certificate on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

The permissions decide who may read this file before ownership is handed to postgres.

**Predict first:** Does a CA certificate contain the CA private key?

Run this one action:

```bash
sudo chmod 0644 /etc/patroni/etcd-ca.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Expected result:** /etc/patroni/etcd-ca.crt now has mode 644.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does a CA certificate contain the CA private key?
2. Hint: A .crt file is public verification material.
3. Stronger hint: The destination is /etc/patroni/etcd-ca.crt.
4. Solution: Install the CA certificate and require PATRONI_CA_INSTALLED.

**Done when:** the independent `PATRONI_CA_MODE_SET` validator passes.

## 135. Give postgres ownership of the etcd CA certificate on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

Patroni must verify that it is talking to the assigned etcd cluster.

**Predict first:** Does a CA certificate contain the CA private key?

Run this one action:

```bash
sudo chown postgres:postgres /etc/patroni/etcd-ca.crt
```

**What the command means:** chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Expected result:** The CA certificate is readable by Patroni and contains no private key.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does a CA certificate contain the CA private key?
2. Hint: A .crt file is public verification material.
3. Stronger hint: The destination is /etc/patroni/etcd-ca.crt.
4. Solution: Install the CA certificate and require PATRONI_CA_INSTALLED.

**Done when:** the independent `PATRONI_CA_INSTALLED` validator passes.

## 136. Copy Patroni's etcd client certificate on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which side presents this certificate?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/client.crt /etc/patroni/etcd-client.crt
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.crt. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/patroni/etcd-client.crt now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which side presents this certificate?
2. Hint: Patroni is the client of etcd.
3. Stronger hint: This is public identity material; the private key is handled next.
4. Solution: Install it and require PATRONI_CLIENT_CERT_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_CERT_COPIED` validator passes.

## 137. Set permissions on Patroni's etcd client certificate on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

The permissions decide who may read this file before ownership is handed to postgres.

**Predict first:** Which side presents this certificate?

Run this one action:

```bash
sudo chmod 0644 /etc/patroni/etcd-client.crt
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Expected result:** /etc/patroni/etcd-client.crt now has mode 644.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which side presents this certificate?
2. Hint: Patroni is the client of etcd.
3. Stronger hint: This is public identity material; the private key is handled next.
4. Solution: Install it and require PATRONI_CLIENT_CERT_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_CERT_MODE_SET` validator passes.

## 138. Give postgres ownership of Patroni's etcd client certificate on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

etcd mutual TLS also verifies Patroni's client identity.

**Predict first:** Which side presents this certificate?

Run this one action:

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.crt
```

**What the command means:** chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Expected result:** The signed client certificate is postgres-owned and mode 0644.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which side presents this certificate?
2. Hint: Patroni is the client of etcd.
3. Stronger hint: This is public identity material; the private key is handled next.
4. Solution: Install it and require PATRONI_CLIENT_CERT_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_CERT_INSTALLED` validator passes.

## 139. Copy Patroni's protected etcd client key on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why is this file more restricted than the certificate?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/client.key /etc/patroni/etcd-client.key
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.key. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/patroni/etcd-client.key now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why is this file more restricted than the certificate?
2. Hint: Anyone holding the private key can impersonate the client.
3. Stronger hint: Use mode 0600 and never run cat on it.
4. Solution: Install it and require PATRONI_CLIENT_KEY_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_KEY_COPIED` validator passes.

## 140. Set permissions on Patroni's protected etcd client key on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

The permissions decide who may read this file before ownership is handed to postgres.

**Predict first:** Why is this file more restricted than the certificate?

Run this one action:

```bash
sudo chmod 0600 /etc/patroni/etcd-client.key
```

**What the command means:** chmod 0600 sets the file's permissions to 600 (owner read/write, group/others read - or owner-only for a private key).

**Expected result:** /etc/patroni/etcd-client.key now has mode 600.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why is this file more restricted than the certificate?
2. Hint: Anyone holding the private key can impersonate the client.
3. Stronger hint: Use mode 0600 and never run cat on it.
4. Solution: Install it and require PATRONI_CLIENT_KEY_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_KEY_MODE_SET` validator passes.

## 141. Give postgres ownership of Patroni's protected etcd client key on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

The private key proves possession of the client identity and must not be exposed.

**Predict first:** Why is this file more restricted than the certificate?

Run this one action:

```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.key
```

**What the command means:** chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Expected result:** The command shows no key material and the destination mode is 0600.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why is this file more restricted than the certificate?
2. Hint: Anyone holding the private key can impersonate the client.
3. Stronger hint: Use mode 0600 and never run cat on it.
4. Solution: Install it and require PATRONI_CLIENT_KEY_INSTALLED.

**Done when:** the independent `PATRONI_CLIENT_KEY_INSTALLED` validator passes.

## 142. Copy the Patroni launcher on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Why use a wrapper instead of a floating pip command?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/patroni /usr/local/bin/patroni
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patroni. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/patroni now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why use a wrapper instead of a floating pip command?
2. Hint: It binds systemd to the pinned runtime path.
3. Stronger hint: The destination is /usr/local/bin/patroni.
4. Solution: Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONI_WRAPPER_COPIED` validator passes.

## 143. Make the Patroni launcher on pg-ha-3 runnable

**Work on:** `pg-ha-3` as `ec2-user`

The pinned Python runtime needs one stable command path for systemd.

**Predict first:** Why use a wrapper instead of a floating pip command?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/patroni
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** /usr/local/bin/patroni is executable and reports Patroni 4.1.4.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why use a wrapper instead of a floating pip command?
2. Hint: It binds systemd to the pinned runtime path.
3. Stronger hint: The destination is /usr/local/bin/patroni.
4. Solution: Install the wrapper and require PATRONI_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONI_WRAPPER_INSTALLED` validator passes.

## 144. Copy the patronictl launcher on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which tool runs the service and which tool operates the cluster?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/patronictl /usr/local/bin/patronictl
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patronictl. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /usr/local/bin/patronictl now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which tool runs the service and which tool operates the cluster?
2. Hint: patroni runs; patronictl controls and inspects.
3. Stronger hint: The operator command ends in ctl.
4. Solution: Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONICTL_WRAPPER_COPIED` validator passes.

## 145. Make the patronictl launcher on pg-ha-3 runnable

**Work on:** `pg-ha-3` as `ec2-user`

Operators need a stable absolute path for cluster inspection and planned operations.

**Predict first:** Which tool runs the service and which tool operates the cluster?

Run this one action:

```bash
sudo chmod 0755 /usr/local/bin/patronictl
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** /usr/local/bin/patronictl is executable.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which tool runs the service and which tool operates the cluster?
2. Hint: patroni runs; patronictl controls and inspects.
3. Stronger hint: The operator command ends in ctl.
4. Solution: Install the wrapper and require PATRONICTL_WRAPPER_INSTALLED.

**Done when:** the independent `PATRONICTL_WRAPPER_INSTALLED` validator passes.

## 146. Copy the Patroni systemd unit on pg-ha-3 into place

**Work on:** `pg-ha-3` as `ec2-user`

Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.

**Predict first:** Which process should systemd start?

Run this one action:

```bash
sudo cp /opt/suta/handoff/patroni/patroni.service /etc/systemd/system/patroni.service
```

**What the command means:** sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/patroni.service. It does not set the file's permissions - the next step does that.

**Expected result:** The command returns to the prompt and /etc/systemd/system/patroni.service now exists.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which process should systemd start?
2. Hint: Patroni owns PostgreSQL startup in this cluster.
3. Stronger hint: ExecStart must call /usr/local/bin/patroni.
4. Solution: Install the unit and require PATRONI_UNIT_CREATED.

**Done when:** the independent `PATRONI_UNIT_COPIED` validator passes.

## 147. Set permissions on the Patroni systemd unit on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

systemd must run Patroni—not postgres directly—as the owner of the PostgreSQL lifecycle.

**Predict first:** Which process should systemd start?

Run this one action:

```bash
sudo chmod 0644 /etc/systemd/system/patroni.service
```

**What the command means:** chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Expected result:** The unit parses, names the postgres user and starts Patroni with /etc/patroni/patroni.yml.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which process should systemd start?
2. Hint: Patroni owns PostgreSQL startup in this cluster.
3. Stronger hint: ExecStart must call /usr/local/bin/patroni.
4. Solution: Install the unit and require PATRONI_UNIT_CREATED.

**Done when:** the independent `PATRONI_UNIT_CREATED` validator passes.

## 148. Reload systemd on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

systemd does not use a newly installed unit until its manager configuration is reloaded.

**Predict first:** Does daemon-reload start Patroni?

Run this one action:

```bash
sudo systemctl daemon-reload
```

**What the command means:** daemon-reload asks systemd to reread unit files without starting Patroni.

**Expected result:** The command returns to the prompt and Patroni remains inactive.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Does daemon-reload start Patroni?
2. Hint: It rereads definitions only.
3. Stronger hint: The service must stay inactive until its ordered start step.
4. Solution: Reload systemd and require PATRONI_SYSTEMD_RELOADED.

**Done when:** the independent `PATRONI_SYSTEMD_RELOADED` validator passes.

## 149. Configure Patroni on pg-ha-3

**Work on:** `pg-ha-3` as `ec2-user`

The second replica completes the topology with a unique member identity.

**Predict first:** What makes these files members of one cluster?

Run this one action:

```bash
sudo vi /etc/patroni/patroni.yml
```

**What the command means:** Enter the supplied pg-ha-3 YAML using the same protected cluster credentials.

Enter this exact yaml content after SutaBot resolves only the registered role addresses and protected secret fields:

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

**Expected result:** The file names pg-ha-3 and passes the Patroni contract validator.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What makes these files members of one cluster?
2. Hint: They share scope, DCS endpoints and authentication.
3. Stronger hint: Only member identity and local addresses differ.
4. Solution: Enter the supplied YAML and require PATRONI_MEMBER_3_CONFIGURED.

**Done when:** the independent `PATRONI_MEMBER_3_CONFIGURED` validator passes.

## 150. Bootstrap the first Patroni leader

**Work on:** `pg-ha-1` as `ec2-user`

Starting one member first prevents three empty nodes from racing to initialize one scope.

**Predict first:** Why start only one node first?

Run this one action:

```bash
sudo systemctl enable --now patroni
```

**What the command means:** Enable Patroni for boot and start only pg-ha-1; Patroni initializes PostgreSQL with checksums and writes cluster state to etcd.

**Expected result:** pg-ha-1 becomes one running leader before either replica starts.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why start only one node first?
2. Hint: The cluster has no existing leader or initialized data yet.
3. Stronger hint: Use patronictl list to confirm exactly one running leader.
4. Solution: Start Patroni on pg-ha-1 and wait for the leader validator before continuing.

**Done when:** the independent `PATRONI_LEADER_BOOTSTRAPPED` validator passes.

## 151. Join pg-ha-2 as the first replica

**Work on:** `pg-ha-2` as `ec2-user`

The member should discover the established leader and clone it instead of initializing another cluster.

**Predict first:** Which role should pg-ha-2 report?

Run this one action:

```bash
sudo systemctl enable --now patroni
```

**What the command means:** Start Patroni on pg-ha-2 only after the leader and pg-ha-2 configuration validators pass.

**Expected result:** pg-ha-2 joins as a streaming replica while pg-ha-1 remains leader.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which role should pg-ha-2 report?
2. Hint: It must not report Leader.
3. Stronger hint: Require one leader and one streaming replica before adding pg-ha-3.
4. Solution: Start Patroni on pg-ha-2 and require PATRONI_REPLICA_2_JOINED.

**Done when:** the independent `PATRONI_REPLICA_2_JOINED` validator passes.

## 152. Join pg-ha-3 as the second replica

**Work on:** `pg-ha-3` as `ec2-user`

The final member restores the intended two-replica redundancy.

**Predict first:** What complete topology must now appear?

Run this one action:

```bash
sudo systemctl enable --now patroni
```

**What the command means:** Start Patroni on pg-ha-3 after the first replica is already streaming.

**Expected result:** The cluster reports one leader and two streaming replicas on one timeline.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: What complete topology must now appear?
2. Hint: One leader plus two replicas.
3. Stronger hint: Both replicas must report streaming.
4. Solution: Start Patroni on pg-ha-3 and require PATRONI_REPLICA_3_JOINED.

**Done when:** the independent `PATRONI_REPLICA_3_JOINED` validator passes.

## 153. Copy the pinned HAProxy binary into place

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

## 154. Make the pinned HAProxy binary runnable

**Work on:** `db-router-1` as `ec2-user`

The writer router needs the reviewed immutable HAProxy build staged by the platform team.

**Predict first:** Why use the staged binary?

Run this one action:

```bash
sudo chmod 0755 /usr/local/sbin/haproxy
```

**What the command means:** chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Expected result:** HAProxy reports version 3.2.22.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why use the staged binary?
2. Hint: Its digest and version were fixed before handoff.
3. Stronger hint: Install it at /usr/local/sbin/haproxy.
4. Solution: Run the displayed install command and require HAPROXY_INSTALLED.

**Done when:** the independent `HAPROXY_INSTALLED` validator passes.

## 155. Create the haproxy-directory directories

**Work on:** `db-router-1` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Who should own routing policy?

Run this one action:

```bash
sudo mkdir -p /etc/haproxy
```

**What the command means:** sudo mkdir -p creates /etc/haproxy (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should own routing policy?
2. Hint: It is system configuration, not application data.
3. Stronger hint: Use root:root ownership.
4. Solution: Create the directory and require HAPROXY_DIR_CREATED.

**Done when:** the independent `HAPROXY_DIR_DIRS_MADE` validator passes.

## 156. Give root ownership of the haproxy-directory directories

**Work on:** `db-router-1` as `ec2-user`

The root service must own these directories to write into them.

**Predict first:** Who should own routing policy?

Run this one action:

```bash
sudo chown -R root:root /etc/haproxy
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by root.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should own routing policy?
2. Hint: It is system configuration, not application data.
3. Stronger hint: Use root:root ownership.
4. Solution: Create the directory and require HAPROXY_DIR_CREATED.

**Done when:** the independent `HAPROXY_DIR_DIRS_OWNED` validator passes.

## 157. Lock down the haproxy-directory directory permissions

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

## 158. Copy the HAProxy systemd unit into place

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

## 159. Set permissions on the HAProxy systemd unit

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

## 160. Reload systemd for HAProxy

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

## 161. Configure the HAProxy writer route

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

## 162. Start the writer endpoint

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

## 163. Create the Mattermost database login

**Work on:** `pg-ha-1` as `ec2-user`

The application needs its own least-privilege PostgreSQL identity instead of the superuser.

**Predict first:** Why not let Mattermost connect as postgres?

Run this one action:

```bash
sudo -u postgres /opt/pgsql/bin/psql -h /var/run/postgresql -d postgres -c "CREATE ROLE mattermost LOGIN"
```

**What the command means:** Connect locally as postgres and create only the named login role; its protected password is assigned in the next step.

**Expected result:** PostgreSQL reports CREATE ROLE and the role has login but no superuser privileges.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Why not let Mattermost connect as postgres?
2. Hint: Applications should not receive cluster-administrator rights.
3. Stronger hint: Create a LOGIN role named mattermost.
4. Solution: Create the role and require MATTERMOST_DB_ROLE_CREATED.

**Done when:** the independent `MATTERMOST_DB_ROLE_CREATED` validator passes.

## 164. Set the protected Mattermost database password

**Work on:** `pg-ha-1` as `ec2-user`

SCRAM authentication requires a password while chat and logs must never contain it.

**Predict first:** Where should the plaintext password appear?

Run this one action:

```bash
sudo -u postgres /opt/pgsql/bin/psql -h /var/run/postgresql -d postgres -c "\password mattermost"
```

**What the command means:** Open PostgreSQL's protected password prompt for the mattermost role; SutaBot supplies the session secret through the masked terminal control, never chat.

**Expected result:** The password is stored as a SCRAM verifier and no plaintext appears.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Where should the plaintext password appear?
2. Hint: Nowhere in chat, command history or logs.
3. Stronger hint: Use the masked protected-secret terminal prompt.
4. Solution: Complete the protected prompt and require MATTERMOST_DB_PASSWORD_SET.

**Done when:** the independent `MATTERMOST_DB_PASSWORD_SET` validator passes.

## 165. Create the Mattermost database

**Work on:** `pg-ha-1` as `ec2-user`

Mattermost needs an isolated database owned by its application role.

**Predict first:** Who should own the application database?

Run this one action:

```bash
sudo -u postgres /opt/pgsql/bin/createdb -h /var/run/postgresql -O mattermost mattermost
```

**What the command means:** Create database mattermost and assign ownership to role mattermost.

**Expected result:** The database exists once with mattermost as owner.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Who should own the application database?
2. Hint: Use the dedicated application role.
3. Stronger hint: Both role and database are named mattermost.
4. Solution: Create the database and require MATTERMOST_DATABASE_CREATED.

**Done when:** the independent `MATTERMOST_DATABASE_CREATED` validator passes.

## 166. Create the Mattermost operating-system account

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

## 167. Install the pinned Mattermost application

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

## 168. Create the mattermost-data-directory directories

**Work on:** `mattermost-1` as `ec2-user`

Creating the empty directories first keeps each action clear; ownership and permissions come next.

**Predict first:** Which account needs write access here?

Run this one action:

```bash
sudo mkdir -p /opt/mattermost/data
```

**What the command means:** sudo mkdir -p creates /opt/mattermost/data (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Expected result:** The command returns to the prompt and the directories exist.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account needs write access here?
2. Hint: Only the Mattermost service account.
3. Stronger hint: Create /opt/mattermost/data as mattermost:mattermost with mode 0750.
4. Solution: Run the registered install -d command and require MATTERMOST_DATA_DIR_CREATED.

**Done when:** the independent `MATTERMOST_DATA_DIR_DIRS_MADE` validator passes.

## 169. Give mattermost ownership of the mattermost-data-directory directories

**Work on:** `mattermost-1` as `ec2-user`

The mattermost service must own these directories to write into them.

**Predict first:** Which account needs write access here?

Run this one action:

```bash
sudo chown -R mattermost:mattermost /opt/mattermost/data
```

**What the command means:** chown -R sets the owner and group of the directories (and their contents) to mattermost, because a plain mkdir left them owned by root.

**Expected result:** The directories are now owned by mattermost.

**Safety:** This changes the assigned lab role. The registered validator and reset contract bound the change.

If you are stuck, ask SutaBot for help. It will reveal help in this order:

1. Question: Which account needs write access here?
2. Hint: Only the Mattermost service account.
3. Stronger hint: Create /opt/mattermost/data as mattermost:mattermost with mode 0750.
4. Solution: Run the registered install -d command and require MATTERMOST_DATA_DIR_CREATED.

**Done when:** the independent `MATTERMOST_DATA_DIR_DIRS_OWNED` validator passes.

## 170. Lock down the mattermost-data-directory directory permissions

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

## 171. Assign the Mattermost application tree

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

## 172. Copy the Mattermost systemd unit into place

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

## 173. Set permissions on the Mattermost systemd unit

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

## 174. Reload systemd for Mattermost

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

## 175. Connect Mattermost to HAProxy

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

## 176. Start and prove Mattermost

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

