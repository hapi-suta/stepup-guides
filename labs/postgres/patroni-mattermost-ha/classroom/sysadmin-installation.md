# Sysadmin: installation reference

[Classroom home](README.md)

This is an instructor reference, not the student lesson. It assumes the Suta artifacts, runtime dependencies, networking and certificates have already been supplied. It does not provision AWS or generate PKI. Skip actions that are already complete.

## SYSADMIN INSTALLATION ACTIONS



## 25. Verify the staged etcd archive

**SERVER: dcs-1 | START AS: ec2-user in Linux**


You must prove the software bytes are approved before installing them.


```bash
sha256sum /opt/suta/artifacts/etcd-v3.6.14-suta.2-linux-amd64.tar.gz
```


What happens: sha256sum calculates the archive fingerprint; compare it with the digest shown in the handoff manifest.

Expected: One SHA-256 digest followed by the archive path.


## 26. Copy the etcd server program into place

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/etcd /usr/local/bin/etcd
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcd. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/etcd
```


Look for: one line ending in /usr/local/bin/etcd with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/etcd now exists.


## 27. Make the etcd server program runnable

**SERVER: dcs-1 | START AS: ec2-user in Linux**


The etcd program runs one voting member of the distributed configuration store.


```bash
sudo chmod 0755 /usr/local/bin/etcd
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/etcd
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: The command returns to the prompt without an error and /usr/local/bin/etcd is executable.


## 28. Copy the etcdctl client program into place

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/etcdctl /usr/local/bin/etcdctl
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdctl. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/etcdctl
```


Look for: one line ending in /usr/local/bin/etcdctl with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/etcdctl now exists.


## 29. Make the etcdctl client program runnable

**SERVER: dcs-1 | START AS: ec2-user in Linux**


etcdctl sends authenticated health, membership and snapshot requests to etcd.


```bash
sudo chmod 0755 /usr/local/bin/etcdctl
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/etcdctl
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: The command returns to the prompt and /usr/local/bin/etcdctl is executable.


## 30. Copy the etcdutl recovery program into place

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/etcdutl /usr/local/bin/etcdutl
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdutl. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/etcdutl
```


Look for: one line ending in /usr/local/bin/etcdutl with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/etcdutl now exists.


## 31. Make the etcdutl recovery program runnable

**SERVER: dcs-1 | START AS: ec2-user in Linux**


etcdutl inspects and restores offline etcd data such as snapshots.


```bash
sudo chmod 0755 /usr/local/bin/etcdutl
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/etcdutl
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: The command returns to the prompt and /usr/local/bin/etcdutl is executable.


## 32. Create the etcd-directories-1 directories

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /etc/etcd
```


What happens: sudo mkdir -p creates /etc/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /etc/etcd
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 33. Give root ownership of the etcd-directories-1 directories

**SERVER: dcs-1 | START AS: ec2-user in Linux**


The root service must own these directories to write into them.


```bash
sudo chown -R root:root /etc/etcd
```


What happens: chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /etc/etcd
```


Look for: owner root and group root on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read root root.

Expected: The directories are now owned by root.


## 34. Lock down the etcd-directories-1 directory permissions

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Configuration and consensus data need explicit protected locations.


```bash
sudo chmod 0700 /etc/etcd
```


What happens: chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /etc/etcd
```


Look for: the first column reading drwx------
ls -ld shows the directory itself with its permission bits in the first column. Mode 0700 must appear as drwx------; anything else means the chmod did not apply.

Expected: The command returns without error and /etc/etcd is owned by root with mode 0700.


## 35. Create the etcd-data-directory-1 directories

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /var/lib/etcd
```


What happens: sudo mkdir -p creates /var/lib/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /var/lib/etcd
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 36. Give root ownership of the etcd-data-directory-1 directories

**SERVER: dcs-1 | START AS: ec2-user in Linux**


The root service must own these directories to write into them.


```bash
sudo chown -R root:root /var/lib/etcd
```


What happens: chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /var/lib/etcd
```


Look for: owner root and group root on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read root root.

Expected: The directories are now owned by root.


## 37. Lock down the etcd-data-directory-1 directory permissions

**SERVER: dcs-1 | START AS: ec2-user in Linux**


etcd must persist quorum state in a root-only directory that starts empty.


```bash
sudo chmod 0700 /var/lib/etcd
```


What happens: chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /var/lib/etcd
```


Look for: the first column reading drwx------
ls -ld shows the directory itself with its permission bits in the first column. Mode 0700 must appear as drwx------; anything else means the chmod did not apply.

Expected: The command returns without error and /var/lib/etcd remains empty, root-owned, and mode 0700.


## 38. Copy the role-bound TLS public certificate into place

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/etcd/member.crt /etc/etcd/member.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/etcd/member.crt
```


Look for: one line ending in /etc/etcd/member.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/etcd/member.crt now exists.


## 39. Set permissions on the role-bound TLS public certificate

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Peers need this signed public certificate to authenticate the member name and private address.


```bash
sudo chmod 0644 /etc/etcd/member.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
sudo ls -l /etc/etcd/member.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: The certificate is installed without printing its contents.


## 40. Copy the etcd trust anchor into place

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/etcd/ca.crt /etc/etcd/ca.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/ca.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/etcd/ca.crt
```


Look for: one line ending in /etc/etcd/ca.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/etcd/ca.crt now exists.


## 41. Set permissions on the etcd trust anchor

**SERVER: dcs-1 | START AS: ec2-user in Linux**


The member needs the lab CA certificate to verify certificates presented by clients and peers.


```bash
sudo chmod 0644 /etc/etcd/ca.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
sudo ls -l /etc/etcd/ca.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: The CA certificate is installed without exposing any private key.


## 42. Copy the role-bound TLS private key into place

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/etcd/member.key /etc/etcd/member.key
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.key. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/etcd/member.key
```


Look for: one line ending in /etc/etcd/member.key with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/etcd/member.key now exists.


## 43. Set permissions on the role-bound TLS private key

**SERVER: dcs-1 | START AS: ec2-user in Linux**


Mutual TLS must identify this member without exposing its private key.


```bash
sudo chmod 0600 /etc/etcd/member.key
```


What happens: chmod 0600 sets the file's permissions to 600 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
sudo ls -l /etc/etcd/member.key
```


Look for: the first column reading -rw-------
ls -l shows the file with its permission bits in the first column. Mode 0600 must appear as -rw-------; anything else means the chmod did not apply.

Expected: The command returns without displaying key material.


## 44. Copy the etcd server program into place

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/etcd /usr/local/bin/etcd
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcd. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/etcd
```


Look for: one line ending in /usr/local/bin/etcd with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/etcd now exists.


## 45. Make the etcd server program runnable

**SERVER: dcs-2 | START AS: ec2-user in Linux**


The etcd program runs one voting member of the distributed configuration store.


```bash
sudo chmod 0755 /usr/local/bin/etcd
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/etcd
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: The command returns to the prompt without an error and /usr/local/bin/etcd is executable.


## 46. Copy the etcdctl client program into place

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/etcdctl /usr/local/bin/etcdctl
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdctl. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/etcdctl
```


Look for: one line ending in /usr/local/bin/etcdctl with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/etcdctl now exists.


## 47. Make the etcdctl client program runnable

**SERVER: dcs-2 | START AS: ec2-user in Linux**


etcdctl sends authenticated health, membership and snapshot requests to etcd.


```bash
sudo chmod 0755 /usr/local/bin/etcdctl
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/etcdctl
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: The command returns to the prompt and /usr/local/bin/etcdctl is executable.


## 48. Copy the etcdutl recovery program into place

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/etcdutl /usr/local/bin/etcdutl
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdutl. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/etcdutl
```


Look for: one line ending in /usr/local/bin/etcdutl with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/etcdutl now exists.


## 49. Make the etcdutl recovery program runnable

**SERVER: dcs-2 | START AS: ec2-user in Linux**


etcdutl inspects and restores offline etcd data such as snapshots.


```bash
sudo chmod 0755 /usr/local/bin/etcdutl
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/etcdutl
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: The command returns to the prompt and /usr/local/bin/etcdutl is executable.


## 50. Create the etcd-directories-2 directories

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /etc/etcd
```


What happens: sudo mkdir -p creates /etc/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /etc/etcd
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 51. Give root ownership of the etcd-directories-2 directories

**SERVER: dcs-2 | START AS: ec2-user in Linux**


The root service must own these directories to write into them.


```bash
sudo chown -R root:root /etc/etcd
```


What happens: chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /etc/etcd
```


Look for: owner root and group root on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read root root.

Expected: The directories are now owned by root.


## 52. Lock down the etcd-directories-2 directory permissions

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Configuration and consensus data need explicit protected locations.


```bash
sudo chmod 0700 /etc/etcd
```


What happens: chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /etc/etcd
```


Look for: the first column reading drwx------
ls -ld shows the directory itself with its permission bits in the first column. Mode 0700 must appear as drwx------; anything else means the chmod did not apply.

Expected: The command returns without error and /etc/etcd is owned by root with mode 0700.


## 53. Create the etcd-data-directory-2 directories

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /var/lib/etcd
```


What happens: sudo mkdir -p creates /var/lib/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /var/lib/etcd
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 54. Give root ownership of the etcd-data-directory-2 directories

**SERVER: dcs-2 | START AS: ec2-user in Linux**


The root service must own these directories to write into them.


```bash
sudo chown -R root:root /var/lib/etcd
```


What happens: chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /var/lib/etcd
```


Look for: owner root and group root on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read root root.

Expected: The directories are now owned by root.


## 55. Lock down the etcd-data-directory-2 directory permissions

**SERVER: dcs-2 | START AS: ec2-user in Linux**


etcd must persist quorum state in a root-only directory that starts empty.


```bash
sudo chmod 0700 /var/lib/etcd
```


What happens: chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /var/lib/etcd
```


Look for: the first column reading drwx------
ls -ld shows the directory itself with its permission bits in the first column. Mode 0700 must appear as drwx------; anything else means the chmod did not apply.

Expected: The command returns without error and /var/lib/etcd remains empty, root-owned, and mode 0700.


## 56. Copy the role-bound TLS public certificate into place

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/etcd/member.crt /etc/etcd/member.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/etcd/member.crt
```


Look for: one line ending in /etc/etcd/member.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/etcd/member.crt now exists.


## 57. Set permissions on the role-bound TLS public certificate

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Peers need this signed public certificate to authenticate the member name and private address.


```bash
sudo chmod 0644 /etc/etcd/member.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
sudo ls -l /etc/etcd/member.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: The certificate is installed without printing its contents.


## 58. Copy the etcd trust anchor into place

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/etcd/ca.crt /etc/etcd/ca.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/ca.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/etcd/ca.crt
```


Look for: one line ending in /etc/etcd/ca.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/etcd/ca.crt now exists.


## 59. Set permissions on the etcd trust anchor

**SERVER: dcs-2 | START AS: ec2-user in Linux**


The member needs the lab CA certificate to verify certificates presented by clients and peers.


```bash
sudo chmod 0644 /etc/etcd/ca.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
sudo ls -l /etc/etcd/ca.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: The CA certificate is installed without exposing any private key.


## 60. Copy the role-bound TLS private key into place

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/etcd/member.key /etc/etcd/member.key
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.key. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/etcd/member.key
```


Look for: one line ending in /etc/etcd/member.key with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/etcd/member.key now exists.


## 61. Set permissions on the role-bound TLS private key

**SERVER: dcs-2 | START AS: ec2-user in Linux**


Mutual TLS must identify this member without exposing its private key.


```bash
sudo chmod 0600 /etc/etcd/member.key
```


What happens: chmod 0600 sets the file's permissions to 600 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
sudo ls -l /etc/etcd/member.key
```


Look for: the first column reading -rw-------
ls -l shows the file with its permission bits in the first column. Mode 0600 must appear as -rw-------; anything else means the chmod did not apply.

Expected: The command returns without displaying key material.


## 62. Copy the etcd server program into place

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/etcd /usr/local/bin/etcd
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcd. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/etcd
```


Look for: one line ending in /usr/local/bin/etcd with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/etcd now exists.


## 63. Make the etcd server program runnable

**SERVER: dcs-3 | START AS: ec2-user in Linux**


The etcd program runs one voting member of the distributed configuration store.


```bash
sudo chmod 0755 /usr/local/bin/etcd
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/etcd
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: The command returns to the prompt without an error and /usr/local/bin/etcd is executable.


## 64. Copy the etcdctl client program into place

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/etcdctl /usr/local/bin/etcdctl
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdctl. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/etcdctl
```


Look for: one line ending in /usr/local/bin/etcdctl with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/etcdctl now exists.


## 65. Make the etcdctl client program runnable

**SERVER: dcs-3 | START AS: ec2-user in Linux**


etcdctl sends authenticated health, membership and snapshot requests to etcd.


```bash
sudo chmod 0755 /usr/local/bin/etcdctl
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/etcdctl
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: The command returns to the prompt and /usr/local/bin/etcdctl is executable.


## 66. Copy the etcdutl recovery program into place

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/etcdutl /usr/local/bin/etcdutl
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/etcdutl. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/etcdutl
```


Look for: one line ending in /usr/local/bin/etcdutl with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/etcdutl now exists.


## 67. Make the etcdutl recovery program runnable

**SERVER: dcs-3 | START AS: ec2-user in Linux**


etcdutl inspects and restores offline etcd data such as snapshots.


```bash
sudo chmod 0755 /usr/local/bin/etcdutl
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/etcdutl
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: The command returns to the prompt and /usr/local/bin/etcdutl is executable.


## 68. Create the etcd-directories-3 directories

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /etc/etcd
```


What happens: sudo mkdir -p creates /etc/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /etc/etcd
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 69. Give root ownership of the etcd-directories-3 directories

**SERVER: dcs-3 | START AS: ec2-user in Linux**


The root service must own these directories to write into them.


```bash
sudo chown -R root:root /etc/etcd
```


What happens: chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /etc/etcd
```


Look for: owner root and group root on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read root root.

Expected: The directories are now owned by root.


## 70. Lock down the etcd-directories-3 directory permissions

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Configuration and consensus data need explicit protected locations.


```bash
sudo chmod 0700 /etc/etcd
```


What happens: chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /etc/etcd
```


Look for: the first column reading drwx------
ls -ld shows the directory itself with its permission bits in the first column. Mode 0700 must appear as drwx------; anything else means the chmod did not apply.

Expected: The command returns without error and /etc/etcd is owned by root with mode 0700.


## 71. Create the etcd-data-directory-3 directories

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /var/lib/etcd
```


What happens: sudo mkdir -p creates /var/lib/etcd (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /var/lib/etcd
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 72. Give root ownership of the etcd-data-directory-3 directories

**SERVER: dcs-3 | START AS: ec2-user in Linux**


The root service must own these directories to write into them.


```bash
sudo chown -R root:root /var/lib/etcd
```


What happens: chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /var/lib/etcd
```


Look for: owner root and group root on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read root root.

Expected: The directories are now owned by root.


## 73. Lock down the etcd-data-directory-3 directory permissions

**SERVER: dcs-3 | START AS: ec2-user in Linux**


etcd must persist quorum state in a root-only directory that starts empty.


```bash
sudo chmod 0700 /var/lib/etcd
```


What happens: chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /var/lib/etcd
```


Look for: the first column reading drwx------
ls -ld shows the directory itself with its permission bits in the first column. Mode 0700 must appear as drwx------; anything else means the chmod did not apply.

Expected: The command returns without error and /var/lib/etcd remains empty, root-owned, and mode 0700.


## 74. Copy the role-bound TLS public certificate into place

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/etcd/member.crt /etc/etcd/member.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/etcd/member.crt
```


Look for: one line ending in /etc/etcd/member.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/etcd/member.crt now exists.


## 75. Set permissions on the role-bound TLS public certificate

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Peers need this signed public certificate to authenticate the member name and private address.


```bash
sudo chmod 0644 /etc/etcd/member.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
sudo ls -l /etc/etcd/member.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: The certificate is installed without printing its contents.


## 76. Copy the etcd trust anchor into place

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/etcd/ca.crt /etc/etcd/ca.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/ca.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/etcd/ca.crt
```


Look for: one line ending in /etc/etcd/ca.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/etcd/ca.crt now exists.


## 77. Set permissions on the etcd trust anchor

**SERVER: dcs-3 | START AS: ec2-user in Linux**


The member needs the lab CA certificate to verify certificates presented by clients and peers.


```bash
sudo chmod 0644 /etc/etcd/ca.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
sudo ls -l /etc/etcd/ca.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: The CA certificate is installed without exposing any private key.


## 78. Copy the role-bound TLS private key into place

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/etcd/member.key /etc/etcd/member.key
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/etcd/member.key. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/etcd/member.key
```


Look for: one line ending in /etc/etcd/member.key with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/etcd/member.key now exists.


## 79. Set permissions on the role-bound TLS private key

**SERVER: dcs-3 | START AS: ec2-user in Linux**


Mutual TLS must identify this member without exposing its private key.


```bash
sudo chmod 0600 /etc/etcd/member.key
```


What happens: chmod 0600 sets the file's permissions to 600 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
sudo ls -l /etc/etcd/member.key
```


Look for: the first column reading -rw-------
ls -l shows the file with its permission bits in the first column. Mode 0600 must appear as -rw-------; anything else means the chmod did not apply.

Expected: The command returns without displaying key material.


## 80. Create the postgres operating-system account on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


PostgreSQL and Patroni must run as a dedicated account instead of root.


```bash
sudo useradd --system --home-dir /opt/pgsql --shell /bin/bash postgres
```


What happens: useradd creates a system account named postgres with /opt/pgsql as its home and bash for controlled administration.

**Check:**

```bash
id postgres
```


Look for: uid=... (postgres) gid=... (postgres)
id prints the numeric user id, group id and groups of an account. If the account did not get created, id says 'no such user'.

Expected: The command returns without error and the postgres account exists without a login password.


## 81. Install PostgreSQL on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Patroni manages PostgreSQL but does not replace the PostgreSQL server binaries.


```bash
sudo tar -xzf /opt/suta/artifacts/postgresql-16.15-centos9-amd64.tar.gz -C /
```


What happens: tar extracts the verified PostgreSQL filesystem archive beneath its approved absolute paths.

**Check:**

```bash
ls -l /opt/pgsql/bin/postgres
```


Look for: an executable file (-rwxr-xr-x) at /opt/pgsql/bin/postgres
tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected: The command returns without error and /opt/pgsql/bin/postgres exists.


## 82. Create the postgresql-layout-1 directories

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


What happens: sudo mkdir -p creates /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


Look for: 4 lines, one per directory, each starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 83. Give postgres ownership of the postgresql-layout-1 directories

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


The postgres service must own these directories to write into them.


```bash
sudo chown -R postgres:postgres /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


What happens: chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


Look for: owner postgres and group postgres on every line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected: The directories are now owned by postgres.


## 84. Lock down the postgresql-layout-1 directory permissions

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Data, WAL, backup and log paths have different operational purposes.


```bash
sudo chmod 0700 /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


What happens: chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


Look for: each line reading drwx------
ls -ld shows the directory itself with its permission bits in the first column. Mode 0700 must appear as drwx------; anything else means the chmod did not apply.

Expected: All four directories exist with postgres ownership and mode 0700; PGDATA remains uninitialized.


## 85. Create the postgres operating-system account on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Every PostgreSQL member uses the same dedicated operating-system identity.


```bash
sudo useradd --system --home-dir /opt/pgsql --shell /bin/bash postgres
```


What happens: Create the postgres system account on pg-ha-2 before extracting files owned by it.

**Check:**

```bash
id postgres
```


Look for: uid=... (postgres) gid=... (postgres)
id prints the numeric user id, group id and groups of an account. If the account did not get created, id says 'no such user'.

Expected: The postgres account exists on pg-ha-2.


## 86. Install PostgreSQL on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


A future replica needs the exact same PostgreSQL minor-version binaries as the leader.


```bash
sudo tar -xzf /opt/suta/artifacts/postgresql-16.15-centos9-amd64.tar.gz -C /
```


What happens: Extract the verified PostgreSQL archive into the approved filesystem paths on pg-ha-2.

**Check:**

```bash
ls -l /opt/pgsql/bin/postgres
```


Look for: an executable file (-rwxr-xr-x) at /opt/pgsql/bin/postgres
tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected: PostgreSQL 16.15 is installed without initializing a cluster.


## 87. Create the postgresql-layout-2 directories

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


What happens: sudo mkdir -p creates /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


Look for: 4 lines, one per directory, each starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 88. Give postgres ownership of the postgresql-layout-2 directories

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


The postgres service must own these directories to write into them.


```bash
sudo chown -R postgres:postgres /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


What happens: chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


Look for: owner postgres and group postgres on every line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected: The directories are now owned by postgres.


## 89. Lock down the postgresql-layout-2 directory permissions

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


The replica needs the same protected operational paths before it can clone.


```bash
sudo chmod 0700 /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


What happens: chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


Look for: each line reading drwx------
ls -ld shows the directory itself with its permission bits in the first column. Mode 0700 must appear as drwx------; anything else means the chmod did not apply.

Expected: All four directories exist and /opt/pgsql/data has no PG_VERSION.


## 90. Create the postgres operating-system account on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


The third database member also needs the dedicated least-privilege process identity.


```bash
sudo useradd --system --home-dir /opt/pgsql --shell /bin/bash postgres
```


What happens: Create the postgres system account on pg-ha-3.

**Check:**

```bash
id postgres
```


Look for: uid=... (postgres) gid=... (postgres)
id prints the numeric user id, group id and groups of an account. If the account did not get created, id says 'no such user'.

Expected: The postgres account exists on pg-ha-3.


## 91. Install PostgreSQL on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


The second replica must match the leader and first replica software version.


```bash
sudo tar -xzf /opt/suta/artifacts/postgresql-16.15-centos9-amd64.tar.gz -C /
```


What happens: Extract the same verified PostgreSQL archive on pg-ha-3.

**Check:**

```bash
ls -l /opt/pgsql/bin/postgres
```


Look for: an executable file (-rwxr-xr-x) at /opt/pgsql/bin/postgres
tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected: PostgreSQL 16.15 is installed without an initialized PGDATA.


## 92. Create the postgresql-layout-3 directories

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


What happens: sudo mkdir -p creates /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


Look for: 4 lines, one per directory, each starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 93. Give postgres ownership of the postgresql-layout-3 directories

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


The postgres service must own these directories to write into them.


```bash
sudo chown -R postgres:postgres /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


What happens: chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


Look for: owner postgres and group postgres on every line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected: The directories are now owned by postgres.


## 94. Lock down the postgresql-layout-3 directory permissions

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


The second replica needs the same protected layout and empty PGDATA.


```bash
sudo chmod 0700 /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


What happens: chmod 0700 sets the permissions to 700 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /opt/pgsql/data /opt/pgsql/wal /opt/pgsql/backup /opt/pgsql/log
```


Look for: each line reading drwx------
ls -ld shows the directory itself with its permission bits in the first column. Mode 0700 must appear as drwx------; anything else means the chmod did not apply.

Expected: All paths exist with postgres ownership and PG_VERSION is absent.


## 95. Create the patroni-directories-1 directories

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Create separate homes for Patroni’s software and configuration.


```bash
sudo mkdir -p /opt/patroni /etc/patroni
```


What happens: sudo mkdir -p creates /opt/patroni /etc/patroni (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /opt/patroni /etc/patroni
```


Look for: 2 lines, one per directory, each starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 96. Give postgres ownership of the patroni-directories-1 directories

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Give the postgres service account ownership of both locations.


```bash
sudo chown -R postgres:postgres /opt/patroni /etc/patroni
```


What happens: chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /opt/patroni /etc/patroni
```


Look for: owner postgres and group postgres on every line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected: The directories are now owned by postgres.


## 97. Lock down the patroni-directories-1 directory permissions

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Set who can enter and change Patroni’s directories.


```bash
sudo chmod 0750 /opt/patroni /etc/patroni
```


What happens: chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /opt/patroni /etc/patroni
```


Look for: each line reading drwxr-x---
ls -ld shows the directory itself with its permission bits in the first column. Mode 0750 must appear as drwxr-x---; anything else means the chmod did not apply.

Expected: Both directories exist with postgres ownership and mode 0750.


## 98. Create the postgresql-socket-directory-1 directories

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Create the directory for local PostgreSQL connections.


```bash
sudo mkdir -p /var/run/postgresql
```


What happens: sudo mkdir -p creates /var/run/postgresql (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /var/run/postgresql
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 99. Give postgres ownership of the postgresql-socket-directory-1 directories

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Let postgres own the directory where it creates its local socket.


```bash
sudo chown -R postgres:postgres /var/run/postgresql
```


What happens: chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /var/run/postgresql
```


Look for: owner postgres and group postgres on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected: The directories are now owned by postgres.


## 100. Lock down the postgresql-socket-directory-1 directory permissions

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Allow local clients to enter the socket directory.


```bash
sudo chmod 0755 /var/run/postgresql
```


What happens: chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /var/run/postgresql
```


Look for: the first column reading drwxr-xr-x
ls -ld shows the directory itself with its permission bits in the first column. Mode 0755 must appear as drwxr-xr-x; anything else means the chmod did not apply.

Expected: /var/run/postgresql exists with postgres ownership.


## 101. Install Patroni on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo tar -xzf /opt/suta/artifacts/patroni-4.1.4-python39-centos9-amd64.tar.gz -C /opt/patroni --strip-components=1
```


What happens: tar extracts the verified Patroni runtime into the prepared directory and removes the archive's outer folder.

**Check:**

```bash
sudo ls -l /opt/patroni/bin/patroni
```


Look for: an executable file (-rwxr-xr-x) at /opt/patroni/bin/patroni
tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected: Patroni 4.1.4 Python modules exist under /opt/patroni.


## 102. Copy the etcd CA certificate on pg-ha-1 into place

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Place the trust certificate Patroni will use to check etcd’s identity.


```bash
sudo cp /opt/suta/handoff/patroni/ca.crt /etc/patroni/etcd-ca.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-ca.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```


Look for: one line ending in /etc/patroni/etcd-ca.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/patroni/etcd-ca.crt now exists.


## 103. Set permissions on the etcd CA certificate on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Allow the trust certificate to be read while restricting writes.


```bash
sudo chmod 0644 /etc/patroni/etcd-ca.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: /etc/patroni/etcd-ca.crt now has mode 644.


## 104. Give postgres ownership of the etcd CA certificate on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo chown postgres:postgres /etc/patroni/etcd-ca.crt
```


What happens: chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```


Look for: owner postgres and group postgres on the line
ls -l shows the file with owner and group in columns three and four. It must read postgres postgres.

Expected: The CA certificate is readable by Patroni and contains no private key.


## 105. Copy Patroni's etcd client certificate on pg-ha-1 into place

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Place the certificate Patroni presents as its client identity.


```bash
sudo cp /opt/suta/handoff/patroni/client.crt /etc/patroni/etcd-client.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```


Look for: one line ending in /etc/patroni/etcd-client.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/patroni/etcd-client.crt now exists.


## 106. Set permissions on Patroni's etcd client certificate on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Set read access on the public client certificate.


```bash
sudo chmod 0644 /etc/patroni/etcd-client.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: /etc/patroni/etcd-client.crt now has mode 644.


## 107. Give postgres ownership of Patroni's etcd client certificate on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.crt
```


What happens: chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```


Look for: owner postgres and group postgres on the line
ls -l shows the file with owner and group in columns three and four. It must read postgres postgres.

Expected: The signed client certificate is postgres-owned and mode 0644.


## 108. Copy Patroni's protected etcd client key on pg-ha-1 into place

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Place the private key used with Patroni’s client certificate.


```bash
sudo cp /opt/suta/handoff/patroni/client.key /etc/patroni/etcd-client.key
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.key. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```


Look for: one line ending in /etc/patroni/etcd-client.key with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/patroni/etcd-client.key now exists.


## 109. Set permissions on Patroni's protected etcd client key on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Restrict the private key to its owner.


```bash
sudo chmod 0600 /etc/patroni/etcd-client.key
```


What happens: chmod 0600 sets the file's permissions to 600 (owner read/write, group/others read - or owner-only for a private key).

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```


Look for: the first column reading -rw-------
ls -l shows the file with its permission bits in the first column. Mode 0600 must appear as -rw-------; anything else means the chmod did not apply.

Expected: /etc/patroni/etcd-client.key now has mode 600.


## 110. Give postgres ownership of Patroni's protected etcd client key on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.key
```


What happens: chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```


Look for: owner postgres and group postgres on the line
ls -l shows the file with owner and group in columns three and four. It must read postgres postgres.

Expected: The command shows no key material and the destination mode is 0600.


## 111. Copy the Patroni launcher on pg-ha-1 into place

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Put the launcher for the Patroni manager in place.


```bash
sudo cp /opt/suta/handoff/patroni/patroni /usr/local/bin/patroni
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patroni. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/patroni
```


Look for: one line ending in /usr/local/bin/patroni with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/patroni now exists.


## 112. Make the Patroni launcher on pg-ha-1 runnable

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Make the launcher executable, then inspect its permissions.


```bash
sudo chmod 0755 /usr/local/bin/patroni
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/patroni
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: /usr/local/bin/patroni is executable and reports Patroni 4.1.4.


## 113. Copy the patronictl launcher on pg-ha-1 into place

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Install the launcher for the cluster administration tool.


```bash
sudo cp /opt/suta/handoff/patroni/patronictl /usr/local/bin/patronictl
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patronictl. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/patronictl
```


Look for: one line ending in /usr/local/bin/patronictl with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/patronictl now exists.


## 114. Make the patronictl launcher on pg-ha-1 runnable

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Make the launcher executable, then inspect its permissions.


```bash
sudo chmod 0755 /usr/local/bin/patronictl
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/patronictl
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: /usr/local/bin/patronictl is executable.


## 115. Copy the Patroni systemd unit on pg-ha-1 into place

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Give systemd the definition it needs to start Patroni.


```bash
sudo cp /opt/suta/handoff/patroni/patroni.service /etc/systemd/system/patroni.service
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/patroni.service. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /etc/systemd/system/patroni.service
```


Look for: one line ending in /etc/systemd/system/patroni.service with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/systemd/system/patroni.service now exists.


## 116. Set permissions on the Patroni systemd unit on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Set read access on the service definition.


```bash
sudo chmod 0644 /etc/systemd/system/patroni.service
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
ls -l /etc/systemd/system/patroni.service
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: The unit parses, names the postgres user and starts Patroni with /etc/patroni/patroni.yml.


## 117. Reload systemd on pg-ha-1

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Ask systemd to reread its service definitions.


```bash
sudo systemctl daemon-reload
```


What happens: daemon-reload asks systemd to reread unit files without starting Patroni.

**Check:**

```bash
systemctl cat patroni --no-pager
```


Look for: # /etc/systemd/system/patroni.service followed by [Unit]
Read the service definition. The first comment names the unit file being loaded.

Expected: The command returns to the prompt and Patroni remains inactive.


## 118. Create the patroni-directories-2 directories

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Create separate homes for Patroni’s software and configuration.


```bash
sudo mkdir -p /opt/patroni /etc/patroni
```


What happens: sudo mkdir -p creates /opt/patroni /etc/patroni (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /opt/patroni /etc/patroni
```


Look for: 2 lines, one per directory, each starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 119. Give postgres ownership of the patroni-directories-2 directories

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Give the postgres service account ownership of both locations.


```bash
sudo chown -R postgres:postgres /opt/patroni /etc/patroni
```


What happens: chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /opt/patroni /etc/patroni
```


Look for: owner postgres and group postgres on every line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected: The directories are now owned by postgres.


## 120. Lock down the patroni-directories-2 directory permissions

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Set who can enter and change Patroni’s directories.


```bash
sudo chmod 0750 /opt/patroni /etc/patroni
```


What happens: chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /opt/patroni /etc/patroni
```


Look for: each line reading drwxr-x---
ls -ld shows the directory itself with its permission bits in the first column. Mode 0750 must appear as drwxr-x---; anything else means the chmod did not apply.

Expected: Both directories exist with postgres ownership and mode 0750.


## 121. Create the postgresql-socket-directory-2 directories

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Create the directory for local PostgreSQL connections.


```bash
sudo mkdir -p /var/run/postgresql
```


What happens: sudo mkdir -p creates /var/run/postgresql (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /var/run/postgresql
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 122. Give postgres ownership of the postgresql-socket-directory-2 directories

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Let postgres own the directory where it creates its local socket.


```bash
sudo chown -R postgres:postgres /var/run/postgresql
```


What happens: chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /var/run/postgresql
```


Look for: owner postgres and group postgres on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected: The directories are now owned by postgres.


## 123. Lock down the postgresql-socket-directory-2 directory permissions

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Allow local clients to enter the socket directory.


```bash
sudo chmod 0755 /var/run/postgresql
```


What happens: chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /var/run/postgresql
```


Look for: the first column reading drwxr-xr-x
ls -ld shows the directory itself with its permission bits in the first column. Mode 0755 must appear as drwxr-xr-x; anything else means the chmod did not apply.

Expected: /var/run/postgresql exists with postgres ownership.


## 124. Install Patroni on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo tar -xzf /opt/suta/artifacts/patroni-4.1.4-python39-centos9-amd64.tar.gz -C /opt/patroni --strip-components=1
```


What happens: tar extracts the verified Patroni runtime into the prepared directory and removes the archive's outer folder.

**Check:**

```bash
sudo ls -l /opt/patroni/bin/patroni
```


Look for: an executable file (-rwxr-xr-x) at /opt/patroni/bin/patroni
tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected: Patroni 4.1.4 Python modules exist under /opt/patroni.


## 125. Copy the etcd CA certificate on pg-ha-2 into place

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Place the trust certificate Patroni will use to check etcd’s identity.


```bash
sudo cp /opt/suta/handoff/patroni/ca.crt /etc/patroni/etcd-ca.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-ca.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```


Look for: one line ending in /etc/patroni/etcd-ca.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/patroni/etcd-ca.crt now exists.


## 126. Set permissions on the etcd CA certificate on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Allow the trust certificate to be read while restricting writes.


```bash
sudo chmod 0644 /etc/patroni/etcd-ca.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: /etc/patroni/etcd-ca.crt now has mode 644.


## 127. Give postgres ownership of the etcd CA certificate on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo chown postgres:postgres /etc/patroni/etcd-ca.crt
```


What happens: chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```


Look for: owner postgres and group postgres on the line
ls -l shows the file with owner and group in columns three and four. It must read postgres postgres.

Expected: The CA certificate is readable by Patroni and contains no private key.


## 128. Copy Patroni's etcd client certificate on pg-ha-2 into place

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Place the certificate Patroni presents as its client identity.


```bash
sudo cp /opt/suta/handoff/patroni/client.crt /etc/patroni/etcd-client.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```


Look for: one line ending in /etc/patroni/etcd-client.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/patroni/etcd-client.crt now exists.


## 129. Set permissions on Patroni's etcd client certificate on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Set read access on the public client certificate.


```bash
sudo chmod 0644 /etc/patroni/etcd-client.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: /etc/patroni/etcd-client.crt now has mode 644.


## 130. Give postgres ownership of Patroni's etcd client certificate on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.crt
```


What happens: chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```


Look for: owner postgres and group postgres on the line
ls -l shows the file with owner and group in columns three and four. It must read postgres postgres.

Expected: The signed client certificate is postgres-owned and mode 0644.


## 131. Copy Patroni's protected etcd client key on pg-ha-2 into place

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Place the private key used with Patroni’s client certificate.


```bash
sudo cp /opt/suta/handoff/patroni/client.key /etc/patroni/etcd-client.key
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.key. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```


Look for: one line ending in /etc/patroni/etcd-client.key with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/patroni/etcd-client.key now exists.


## 132. Set permissions on Patroni's protected etcd client key on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Restrict the private key to its owner.


```bash
sudo chmod 0600 /etc/patroni/etcd-client.key
```


What happens: chmod 0600 sets the file's permissions to 600 (owner read/write, group/others read - or owner-only for a private key).

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```


Look for: the first column reading -rw-------
ls -l shows the file with its permission bits in the first column. Mode 0600 must appear as -rw-------; anything else means the chmod did not apply.

Expected: /etc/patroni/etcd-client.key now has mode 600.


## 133. Give postgres ownership of Patroni's protected etcd client key on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.key
```


What happens: chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```


Look for: owner postgres and group postgres on the line
ls -l shows the file with owner and group in columns three and four. It must read postgres postgres.

Expected: The command shows no key material and the destination mode is 0600.


## 134. Copy the Patroni launcher on pg-ha-2 into place

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Put the launcher for the Patroni manager in place.


```bash
sudo cp /opt/suta/handoff/patroni/patroni /usr/local/bin/patroni
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patroni. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/patroni
```


Look for: one line ending in /usr/local/bin/patroni with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/patroni now exists.


## 135. Make the Patroni launcher on pg-ha-2 runnable

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Make the launcher executable, then inspect its permissions.


```bash
sudo chmod 0755 /usr/local/bin/patroni
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/patroni
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: /usr/local/bin/patroni is executable and reports Patroni 4.1.4.


## 136. Copy the patronictl launcher on pg-ha-2 into place

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Install the launcher for the cluster administration tool.


```bash
sudo cp /opt/suta/handoff/patroni/patronictl /usr/local/bin/patronictl
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patronictl. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/patronictl
```


Look for: one line ending in /usr/local/bin/patronictl with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/patronictl now exists.


## 137. Make the patronictl launcher on pg-ha-2 runnable

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Make the launcher executable, then inspect its permissions.


```bash
sudo chmod 0755 /usr/local/bin/patronictl
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/patronictl
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: /usr/local/bin/patronictl is executable.


## 138. Copy the Patroni systemd unit on pg-ha-2 into place

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Give systemd the definition it needs to start Patroni.


```bash
sudo cp /opt/suta/handoff/patroni/patroni.service /etc/systemd/system/patroni.service
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/patroni.service. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /etc/systemd/system/patroni.service
```


Look for: one line ending in /etc/systemd/system/patroni.service with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/systemd/system/patroni.service now exists.


## 139. Set permissions on the Patroni systemd unit on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Set read access on the service definition.


```bash
sudo chmod 0644 /etc/systemd/system/patroni.service
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
ls -l /etc/systemd/system/patroni.service
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: The unit parses, names the postgres user and starts Patroni with /etc/patroni/patroni.yml.


## 140. Reload systemd on pg-ha-2

**SERVER: pg-ha-2 | START AS: ec2-user in Linux**


Ask systemd to reread its service definitions.


```bash
sudo systemctl daemon-reload
```


What happens: daemon-reload asks systemd to reread unit files without starting Patroni.

**Check:**

```bash
systemctl cat patroni --no-pager
```


Look for: # /etc/systemd/system/patroni.service followed by [Unit]
Read the service definition. The first comment names the unit file being loaded.

Expected: The command returns to the prompt and Patroni remains inactive.


## 141. Create the patroni-directories-3 directories

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Create separate homes for Patroni’s software and configuration.


```bash
sudo mkdir -p /opt/patroni /etc/patroni
```


What happens: sudo mkdir -p creates /opt/patroni /etc/patroni (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /opt/patroni /etc/patroni
```


Look for: 2 lines, one per directory, each starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 142. Give postgres ownership of the patroni-directories-3 directories

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Give the postgres service account ownership of both locations.


```bash
sudo chown -R postgres:postgres /opt/patroni /etc/patroni
```


What happens: chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /opt/patroni /etc/patroni
```


Look for: owner postgres and group postgres on every line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected: The directories are now owned by postgres.


## 143. Lock down the patroni-directories-3 directory permissions

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Set who can enter and change Patroni’s directories.


```bash
sudo chmod 0750 /opt/patroni /etc/patroni
```


What happens: chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /opt/patroni /etc/patroni
```


Look for: each line reading drwxr-x---
ls -ld shows the directory itself with its permission bits in the first column. Mode 0750 must appear as drwxr-x---; anything else means the chmod did not apply.

Expected: Both directories exist with postgres ownership and mode 0750.


## 144. Create the postgresql-socket-directory-3 directories

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Create the directory for local PostgreSQL connections.


```bash
sudo mkdir -p /var/run/postgresql
```


What happens: sudo mkdir -p creates /var/run/postgresql (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /var/run/postgresql
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 145. Give postgres ownership of the postgresql-socket-directory-3 directories

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Let postgres own the directory where it creates its local socket.


```bash
sudo chown -R postgres:postgres /var/run/postgresql
```


What happens: chown -R sets the owner and group of the directories (and their contents) to postgres, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /var/run/postgresql
```


Look for: owner postgres and group postgres on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read postgres postgres.

Expected: The directories are now owned by postgres.


## 146. Lock down the postgresql-socket-directory-3 directory permissions

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Allow local clients to enter the socket directory.


```bash
sudo chmod 0755 /var/run/postgresql
```


What happens: chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /var/run/postgresql
```


Look for: the first column reading drwxr-xr-x
ls -ld shows the directory itself with its permission bits in the first column. Mode 0755 must appear as drwxr-xr-x; anything else means the chmod did not apply.

Expected: /var/run/postgresql exists with postgres ownership.


## 147. Install Patroni on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo tar -xzf /opt/suta/artifacts/patroni-4.1.4-python39-centos9-amd64.tar.gz -C /opt/patroni --strip-components=1
```


What happens: tar extracts the verified Patroni runtime into the prepared directory and removes the archive's outer folder.

**Check:**

```bash
sudo ls -l /opt/patroni/bin/patroni
```


Look for: an executable file (-rwxr-xr-x) at /opt/patroni/bin/patroni
tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected: Patroni 4.1.4 Python modules exist under /opt/patroni.


## 148. Copy the etcd CA certificate on pg-ha-3 into place

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Place the trust certificate Patroni will use to check etcd’s identity.


```bash
sudo cp /opt/suta/handoff/patroni/ca.crt /etc/patroni/etcd-ca.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-ca.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```


Look for: one line ending in /etc/patroni/etcd-ca.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/patroni/etcd-ca.crt now exists.


## 149. Set permissions on the etcd CA certificate on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Allow the trust certificate to be read while restricting writes.


```bash
sudo chmod 0644 /etc/patroni/etcd-ca.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: /etc/patroni/etcd-ca.crt now has mode 644.


## 150. Give postgres ownership of the etcd CA certificate on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo chown postgres:postgres /etc/patroni/etcd-ca.crt
```


What happens: chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-ca.crt
```


Look for: owner postgres and group postgres on the line
ls -l shows the file with owner and group in columns three and four. It must read postgres postgres.

Expected: The CA certificate is readable by Patroni and contains no private key.


## 151. Copy Patroni's etcd client certificate on pg-ha-3 into place

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Place the certificate Patroni presents as its client identity.


```bash
sudo cp /opt/suta/handoff/patroni/client.crt /etc/patroni/etcd-client.crt
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.crt. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```


Look for: one line ending in /etc/patroni/etcd-client.crt with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/patroni/etcd-client.crt now exists.


## 152. Set permissions on Patroni's etcd client certificate on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Set read access on the public client certificate.


```bash
sudo chmod 0644 /etc/patroni/etcd-client.crt
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, group/others read - or owner-only for a private key).

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: /etc/patroni/etcd-client.crt now has mode 644.


## 153. Give postgres ownership of Patroni's etcd client certificate on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.crt
```


What happens: chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.crt
```


Look for: owner postgres and group postgres on the line
ls -l shows the file with owner and group in columns three and four. It must read postgres postgres.

Expected: The signed client certificate is postgres-owned and mode 0644.


## 154. Copy Patroni's protected etcd client key on pg-ha-3 into place

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Place the private key used with Patroni’s client certificate.


```bash
sudo cp /opt/suta/handoff/patroni/client.key /etc/patroni/etcd-client.key
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/patroni/etcd-client.key. It does not set the file's permissions - the next step does that.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```


Look for: one line ending in /etc/patroni/etcd-client.key with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/patroni/etcd-client.key now exists.


## 155. Set permissions on Patroni's protected etcd client key on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Restrict the private key to its owner.


```bash
sudo chmod 0600 /etc/patroni/etcd-client.key
```


What happens: chmod 0600 sets the file's permissions to 600 (owner read/write, group/others read - or owner-only for a private key).

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```


Look for: the first column reading -rw-------
ls -l shows the file with its permission bits in the first column. Mode 0600 must appear as -rw-------; anything else means the chmod did not apply.

Expected: /etc/patroni/etcd-client.key now has mode 600.


## 156. Give postgres ownership of Patroni's protected etcd client key on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Install the pinned Patroni runtime and inspect its entry point.


```bash
sudo chown postgres:postgres /etc/patroni/etcd-client.key
```


What happens: chown sets the file's owner and group to postgres so the service, which runs as postgres, can read it. A plain cp left it owned by root.

**Check:**

```bash
sudo ls -l /etc/patroni/etcd-client.key
```


Look for: owner postgres and group postgres on the line
ls -l shows the file with owner and group in columns three and four. It must read postgres postgres.

Expected: The command shows no key material and the destination mode is 0600.


## 157. Copy the Patroni launcher on pg-ha-3 into place

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Put the launcher for the Patroni manager in place.


```bash
sudo cp /opt/suta/handoff/patroni/patroni /usr/local/bin/patroni
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patroni. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/patroni
```


Look for: one line ending in /usr/local/bin/patroni with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/patroni now exists.


## 158. Make the Patroni launcher on pg-ha-3 runnable

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Make the launcher executable, then inspect its permissions.


```bash
sudo chmod 0755 /usr/local/bin/patroni
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/patroni
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: /usr/local/bin/patroni is executable and reports Patroni 4.1.4.


## 159. Copy the patronictl launcher on pg-ha-3 into place

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Install the launcher for the cluster administration tool.


```bash
sudo cp /opt/suta/handoff/patroni/patronictl /usr/local/bin/patronictl
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/bin/patronictl. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/bin/patronictl
```


Look for: one line ending in /usr/local/bin/patronictl with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/bin/patronictl now exists.


## 160. Make the patronictl launcher on pg-ha-3 runnable

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Make the launcher executable, then inspect its permissions.


```bash
sudo chmod 0755 /usr/local/bin/patronictl
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/bin/patronictl
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: /usr/local/bin/patronictl is executable.


## 161. Copy the Patroni systemd unit on pg-ha-3 into place

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Give systemd the definition it needs to start Patroni.


```bash
sudo cp /opt/suta/handoff/patroni/patroni.service /etc/systemd/system/patroni.service
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/patroni.service. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /etc/systemd/system/patroni.service
```


Look for: one line ending in /etc/systemd/system/patroni.service with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/systemd/system/patroni.service now exists.


## 162. Set permissions on the Patroni systemd unit on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Set read access on the service definition.


```bash
sudo chmod 0644 /etc/systemd/system/patroni.service
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
ls -l /etc/systemd/system/patroni.service
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: The unit parses, names the postgres user and starts Patroni with /etc/patroni/patroni.yml.


## 163. Reload systemd on pg-ha-3

**SERVER: pg-ha-3 | START AS: ec2-user in Linux**


Ask systemd to reread its service definitions.


```bash
sudo systemctl daemon-reload
```


What happens: daemon-reload asks systemd to reread unit files without starting Patroni.

**Check:**

```bash
systemctl cat patroni --no-pager
```


Look for: # /etc/systemd/system/patroni.service followed by [Unit]
Read the service definition. The first comment names the unit file being loaded.

Expected: The command returns to the prompt and Patroni remains inactive.


## 164. Copy the pinned HAProxy binary into place

**SERVER: db-router-1 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/artifacts/haproxy-3.2.22 /usr/local/sbin/haproxy
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /usr/local/sbin/haproxy. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /usr/local/sbin/haproxy
```


Look for: one line ending in /usr/local/sbin/haproxy with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /usr/local/sbin/haproxy now exists.


## 165. Make the pinned HAProxy binary runnable

**SERVER: db-router-1 | START AS: ec2-user in Linux**


The writer router needs the reviewed immutable HAProxy build staged by the platform team.


```bash
sudo chmod 0755 /usr/local/sbin/haproxy
```


What happens: chmod 0755 sets the file readable and executable by everyone and writable only by the owner (755), so the system can run it.

**Check:**

```bash
ls -l /usr/local/sbin/haproxy
```


Look for: the first column reading -rwxr-xr-x
ls -l shows the file with its permission bits in the first column. Mode 0755 must appear as -rwxr-xr-x; anything else means the chmod did not apply.

Expected: HAProxy reports version 3.2.22.


## 166. Create the haproxy-directory directories

**SERVER: db-router-1 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /etc/haproxy
```


What happens: sudo mkdir -p creates /etc/haproxy (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /etc/haproxy
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 167. Give root ownership of the haproxy-directory directories

**SERVER: db-router-1 | START AS: ec2-user in Linux**


The root service must own these directories to write into them.


```bash
sudo chown -R root:root /etc/haproxy
```


What happens: chown -R sets the owner and group of the directories (and their contents) to root, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /etc/haproxy
```


Look for: owner root and group root on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read root root.

Expected: The directories are now owned by root.


## 168. Lock down the haproxy-directory directory permissions

**SERVER: db-router-1 | START AS: ec2-user in Linux**


The router needs a root-owned location for its reviewed writer-routing policy.


```bash
sudo chmod 0755 /etc/haproxy
```


What happens: chmod 0755 sets the permissions to 755 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /etc/haproxy
```


Look for: the first column reading drwxr-xr-x
ls -ld shows the directory itself with its permission bits in the first column. Mode 0755 must appear as drwxr-xr-x; anything else means the chmod did not apply.

Expected: The directory is root-owned with mode 0755.


## 169. Copy the HAProxy systemd unit into place

**SERVER: db-router-1 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/haproxy/haproxy.service /etc/systemd/system/haproxy.service
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/haproxy.service. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /etc/systemd/system/haproxy.service
```


Look for: one line ending in /etc/systemd/system/haproxy.service with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/systemd/system/haproxy.service now exists.


## 170. Set permissions on the HAProxy systemd unit

**SERVER: db-router-1 | START AS: ec2-user in Linux**


A stable unit makes the writer router restartable and boot-persistent.


```bash
sudo chmod 0644 /etc/systemd/system/haproxy.service
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
ls -l /etc/systemd/system/haproxy.service
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: systemd verifies the HAProxy unit.


## 171. Reload systemd for HAProxy

**SERVER: db-router-1 | START AS: ec2-user in Linux**


systemd must reread the newly installed unit before it can start it.


```bash
sudo systemctl daemon-reload
```


What happens: Reload unit definitions without starting HAProxy.

**Check:**

```bash
systemctl cat haproxy --no-pager
```


Look for: # /etc/systemd/system/haproxy.service followed by [Unit]
Read the service definition. The first comment names the unit file being loaded.

Expected: The unit is visible and HAProxy remains inactive.


## 172. Create the Mattermost operating-system account

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


The application process must not run as root.


```bash
sudo useradd --system --home-dir /opt/mattermost --shell /sbin/nologin mattermost
```


What happens: Create a non-login system account whose home matches the application directory.

**Check:**

```bash
id mattermost
```


Look for: uid=... (mattermost) gid=... (mattermost)
id prints the numeric user id, group id and groups of an account. If the account did not get created, id says 'no such user'.

Expected: The mattermost system account exists with nologin shell.


## 173. Install the pinned Mattermost application

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


The workload must use the reviewed version staged during handoff.


```bash
sudo tar -xzf /opt/suta/artifacts/mattermost-team-11.10.1-linux-amd64.tar.gz -C /opt
```


What happens: Extract the verified archive; its top-level mattermost directory becomes /opt/mattermost.

**Check:**

```bash
ls -l /opt/mattermost/bin/mattermost
```


Look for: an executable file (-rwxr-xr-x) at /opt/mattermost/bin/mattermost
tar prints nothing on success, so you prove the extraction by looking for the binary it should have created. If ls says 'No such file', the archive went to the wrong place.

Expected: The Mattermost 11.10.1 server binary exists under /opt/mattermost/bin.


## 174. Create the mattermost-data-directory directories

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


Creating the empty directories first keeps each action clear; ownership and permissions come next.


```bash
sudo mkdir -p /opt/mattermost/data
```


What happens: sudo mkdir -p creates /opt/mattermost/data (and any missing parents). It does not set who owns them or their permissions - the next two steps do.

**Check:**

```bash
ls -ld /opt/mattermost/data
```


Look for: one line starting with d
ls -ld shows the directory entry itself instead of listing what is inside it. A line starting with d proves the directory exists; 'No such file or directory' means mkdir did not run where you think.

Expected: The command returns to the prompt and the directories exist.


## 175. Give mattermost ownership of the mattermost-data-directory directories

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


The mattermost service must own these directories to write into them.


```bash
sudo chown -R mattermost:mattermost /opt/mattermost/data
```


What happens: chown -R sets the owner and group of the directories (and their contents) to mattermost, because a plain mkdir left them owned by root.

**Check:**

```bash
ls -ld /opt/mattermost/data
```


Look for: owner mattermost and group mattermost on the line
ls -ld shows the directory itself with owner and group in columns three and four. After a recursive chown the top entry must already read mattermost mattermost.

Expected: The directories are now owned by mattermost.


## 176. Lock down the mattermost-data-directory directory permissions

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


Mattermost needs a writable runtime-data directory owned only by its service account.


```bash
sudo chmod 0750 /opt/mattermost/data
```


What happens: chmod 0750 sets the permissions to 750 (owner-only for a data directory), which the service requires.

**Check:**

```bash
ls -ld /opt/mattermost/data
```


Look for: the first column reading drwxr-x---
ls -ld shows the directory itself with its permission bits in the first column. Mode 0750 must appear as drwxr-x---; anything else means the chmod did not apply.

Expected: /opt/mattermost/data exists with mattermost ownership and mode 0750.


## 177. Assign the Mattermost application tree

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


The non-root service account must be able to read the installed application and write its runtime paths.


```bash
sudo chown -R mattermost:mattermost /opt/mattermost
```


What happens: Assign the extracted tree to the dedicated service account without changing unrelated system paths.

**Check:**

```bash
ls -l /opt/mattermost
```


Look for: owner mattermost and group mattermost on the line
ls -l shows the file with owner and group in columns three and four. After a recursive chown the top entry must already read mattermost mattermost.

Expected: The Mattermost application tree is owned by mattermost.


## 178. Copy the Mattermost systemd unit into place

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


Copying puts the file where the system expects it. Setting its permissions is a separate step so each action is clear.


```bash
sudo cp /opt/suta/handoff/mattermost/mattermost.service /etc/systemd/system/mattermost.service
```


What happens: sudo runs the copy with permission to write to that location. cp copies the file from the staged path to /etc/systemd/system/mattermost.service. It does not set the file's permissions - the next step does that.

**Check:**

```bash
ls -l /etc/systemd/system/mattermost.service
```


Look for: one line ending in /etc/systemd/system/mattermost.service with a size greater than 0
cp prints nothing on success, so prove the copy by listing the destination (sudo is needed when the directory is root-only). The size column must be greater than 0; 'No such file' means the copy landed somewhere else.

Expected: The command returns to the prompt and /etc/systemd/system/mattermost.service now exists.


## 179. Set permissions on the Mattermost systemd unit

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


The workload needs a supervised, boot-persistent service definition.


```bash
sudo chmod 0644 /etc/systemd/system/mattermost.service
```


What happens: chmod 0644 sets the file's permissions to 644 (owner read/write, others read - or owner-only for keys), which the service requires.

**Check:**

```bash
ls -l /etc/systemd/system/mattermost.service
```


Look for: the first column reading -rw-r--r--
ls -l shows the file with its permission bits in the first column. Mode 0644 must appear as -rw-r--r--; anything else means the chmod did not apply.

Expected: systemd verifies the unit and its non-root identity.


## 180. Reload systemd for Mattermost

**SERVER: mattermost-1 | START AS: ec2-user in Linux**


systemd must discover the new unit while leaving the unconfigured application stopped.


```bash
sudo systemctl daemon-reload
```


What happens: Reload unit definitions without starting Mattermost.

**Check:**

```bash
systemctl cat mattermost --no-pager
```


Look for: # /etc/systemd/system/mattermost.service followed by [Unit]
Read the service definition. The first comment names the unit file being loaded.

Expected: The unit is visible and Mattermost remains inactive.

END OF CLASS MANUAL

### Checkpoint

- [ ] Software and files are installed. The student still configures and starts the stack.

[Classroom home](README.md)
