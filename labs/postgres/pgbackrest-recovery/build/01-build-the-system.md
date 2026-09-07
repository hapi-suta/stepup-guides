# Build and prove a recoverable database

HA001 owner release. Authored actions and registered runtime checks passed on the AWS qualification lab. Independent student learning validation remains separate.

## Identify pg-primary

Select the named terminal before changing a server.

On pg-primary as ec2-user.

### Identify pg-primary

Use the Linux terminal.

```bash
hostname
```

hostname prints this machine’s assigned name.

pg-primary

## Inspect the operating system

Use the CentOS Stream9 procedure that was tested for this project.

On pg-primary as ec2-user.

### Inspect the operating system

Use the Linux terminal.

```bash
cat /etc/centos-release
```

Read the installed operating-system release.

CentOS Stream release9.

## Preserve the original hosts file

Keep a rollback copy before adding the four assigned private names.

On pg-primary as ec2-user.

### Preserve the original hosts file

Use the Linux terminal.

```bash
sudo cp /etc/hosts /etc/hosts.before-pgbackrest
```

cp preserves the existing contents in a separately named file.

The backup file exists.

### Check

```bash
sudo ls -l /etc/hosts.before-pgbackrest
```

The backup file exists.

## Resolve the assigned private hostnames

Service traffic stays on the assigned private addresses. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Resolve the assigned private hostnames

Use the Linux terminal.

```bash
sudo vi /etc/hosts
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/hosts.

### File contents

```text
127.0.0.1 localhost localhost.localdomain
::1 localhost localhost.localdomain
{{address:pg-primary}} pg-primary
{{address:pg-standby}} pg-standby
{{address:backup-1}} backup-1
{{address:nfs-1}} nfs-1
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/hosts
```

The exact file path is present. The following service checks establish whether its settings work.

## Resolve the primary IPv4 hostname

Verify the hostname resolves before configuring remote services.

On pg-primary as ec2-user.

### Resolve the primary IPv4 hostname

Use the Linux terminal.

```bash
getent ahostsv4 pg-primary
```

getent ahostsv4 asks the system resolver for IPv4 addresses. An IPv6-only hostname result would not prove the private IPv4 assignment.

The assigned private IPv4 address for pg-primary appears.

## Install repository-management prerequisites

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On pg-primary as ec2-user.

### Install repository-management prerequisites

Use the Linux terminal.

```bash
sudo dnf -y install epel-release dnf-plugins-core
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
rpm -q epel-release dnf-plugins-core
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Enable the CentOS CRB repository

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On pg-primary as ec2-user.

### Enable the CentOS CRB repository

Use the Linux terminal.

```bash
sudo dnf config-manager --set-enabled crb
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
dnf repolist --enabled
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Install the PostgreSQL package repository

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On pg-primary as ec2-user.

### Install the PostgreSQL package repository

Use the Linux terminal.

```bash
sudo dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
rpm -q pgdg-redhat-repo
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Disable the distribution PostgreSQL module

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On pg-primary as ec2-user.

### Disable the distribution PostgreSQL module

Use the Linux terminal.

```bash
sudo dnf -qy module disable postgresql
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
sudo dnf -C module list postgresql
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Install the pinned database and backup tools

Install the tested pgBackRest2.59.1 and PostgreSQL16.15 versions.

On pg-primary as ec2-user.

### Install the pinned database and backup tools

Use the Linux terminal.

```bash
sudo dnf -y install pgbackrest-2.59.1 nfs-utils openssh-clients policycoreutils-python-utils time postgresql16-server-16.15 postgresql16-16.15
```

The version suffixes pin the requested application packages. Supporting operating-system packages come from the configured CentOS repositories.

Installation finishes successfully.

### Check

```bash
pgbackrest version
```

pgBackRest 2.59.1

## Check the PostgreSQL version

Confirm which PostgreSQL binary the lab will use.

On pg-primary as ec2-user.

### Check the PostgreSQL version

Use the Linux terminal.

```bash
/usr/pgsql-16/bin/postgres --version
```

The full path selects the PGDG16 installation.

postgres (PostgreSQL) 16.15

## Check the package-created postgres account

The PostgreSQL package creates its own operating-system account.

On pg-primary as ec2-user.

### Check the package-created postgres account

Use the Linux terminal.

```bash
id postgres
```

id shows the account’s numeric UID/GID and group memberships.

The postgres UID and primary GID are26.

## Identify pg-standby

Select the named terminal before changing a server.

On pg-standby as ec2-user.

### Identify pg-standby

Use the Linux terminal.

```bash
hostname
```

hostname prints this machine’s assigned name.

pg-standby

## Inspect the operating system

Use the CentOS Stream9 procedure that was tested for this project.

On pg-standby as ec2-user.

### Inspect the operating system

Use the Linux terminal.

```bash
cat /etc/centos-release
```

Read the installed operating-system release.

CentOS Stream release9.

## Preserve the original hosts file

Keep a rollback copy before adding the four assigned private names.

On pg-standby as ec2-user.

### Preserve the original hosts file

Use the Linux terminal.

```bash
sudo cp /etc/hosts /etc/hosts.before-pgbackrest
```

cp preserves the existing contents in a separately named file.

The backup file exists.

### Check

```bash
sudo ls -l /etc/hosts.before-pgbackrest
```

The backup file exists.

## Resolve the assigned private hostnames

Service traffic stays on the assigned private addresses. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-standby as ec2-user.

### Resolve the assigned private hostnames

Use the Linux terminal.

```bash
sudo vi /etc/hosts
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/hosts.

### File contents

```text
127.0.0.1 localhost localhost.localdomain
::1 localhost localhost.localdomain
{{address:pg-primary}} pg-primary
{{address:pg-standby}} pg-standby
{{address:backup-1}} backup-1
{{address:nfs-1}} nfs-1
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/hosts
```

The exact file path is present. The following service checks establish whether its settings work.

## Resolve the primary IPv4 hostname

Verify the hostname resolves before configuring remote services.

On pg-standby as ec2-user.

### Resolve the primary IPv4 hostname

Use the Linux terminal.

```bash
getent ahostsv4 pg-primary
```

getent ahostsv4 asks the system resolver for IPv4 addresses. An IPv6-only hostname result would not prove the private IPv4 assignment.

The assigned private IPv4 address for pg-primary appears.

## Install repository-management prerequisites

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On pg-standby as ec2-user.

### Install repository-management prerequisites

Use the Linux terminal.

```bash
sudo dnf -y install epel-release dnf-plugins-core
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
rpm -q epel-release dnf-plugins-core
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Enable the CentOS CRB repository

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On pg-standby as ec2-user.

### Enable the CentOS CRB repository

Use the Linux terminal.

```bash
sudo dnf config-manager --set-enabled crb
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
dnf repolist --enabled
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Install the PostgreSQL package repository

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On pg-standby as ec2-user.

### Install the PostgreSQL package repository

Use the Linux terminal.

```bash
sudo dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
rpm -q pgdg-redhat-repo
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Disable the distribution PostgreSQL module

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On pg-standby as ec2-user.

### Disable the distribution PostgreSQL module

Use the Linux terminal.

```bash
sudo dnf -qy module disable postgresql
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
sudo dnf -C module list postgresql
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Install the pinned database and backup tools

Install the tested pgBackRest2.59.1 and PostgreSQL16.15 versions.

On pg-standby as ec2-user.

### Install the pinned database and backup tools

Use the Linux terminal.

```bash
sudo dnf -y install pgbackrest-2.59.1 nfs-utils openssh-clients policycoreutils-python-utils time postgresql16-server-16.15 postgresql16-16.15
```

The version suffixes pin the requested application packages. Supporting operating-system packages come from the configured CentOS repositories.

Installation finishes successfully.

### Check

```bash
pgbackrest version
```

pgBackRest 2.59.1

## Check the PostgreSQL version

Confirm which PostgreSQL binary the lab will use.

On pg-standby as ec2-user.

### Check the PostgreSQL version

Use the Linux terminal.

```bash
/usr/pgsql-16/bin/postgres --version
```

The full path selects the PGDG16 installation.

postgres (PostgreSQL) 16.15

## Check the package-created postgres account

The PostgreSQL package creates its own operating-system account.

On pg-standby as ec2-user.

### Check the package-created postgres account

Use the Linux terminal.

```bash
id postgres
```

id shows the account’s numeric UID/GID and group memberships.

The postgres UID and primary GID are26.

## Identify backup-1

Select the named terminal before changing a server.

On backup-1 as ec2-user.

### Identify backup-1

Use the Linux terminal.

```bash
hostname
```

hostname prints this machine’s assigned name.

backup-1

## Inspect the operating system

Use the CentOS Stream9 procedure that was tested for this project.

On backup-1 as ec2-user.

### Inspect the operating system

Use the Linux terminal.

```bash
cat /etc/centos-release
```

Read the installed operating-system release.

CentOS Stream release9.

## Preserve the original hosts file

Keep a rollback copy before adding the four assigned private names.

On backup-1 as ec2-user.

### Preserve the original hosts file

Use the Linux terminal.

```bash
sudo cp /etc/hosts /etc/hosts.before-pgbackrest
```

cp preserves the existing contents in a separately named file.

The backup file exists.

### Check

```bash
sudo ls -l /etc/hosts.before-pgbackrest
```

The backup file exists.

## Resolve the assigned private hostnames

Service traffic stays on the assigned private addresses. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Resolve the assigned private hostnames

Use the Linux terminal.

```bash
sudo vi /etc/hosts
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/hosts.

### File contents

```text
127.0.0.1 localhost localhost.localdomain
::1 localhost localhost.localdomain
{{address:pg-primary}} pg-primary
{{address:pg-standby}} pg-standby
{{address:backup-1}} backup-1
{{address:nfs-1}} nfs-1
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/hosts
```

The exact file path is present. The following service checks establish whether its settings work.

## Resolve the primary IPv4 hostname

Verify the hostname resolves before configuring remote services.

On backup-1 as ec2-user.

### Resolve the primary IPv4 hostname

Use the Linux terminal.

```bash
getent ahostsv4 pg-primary
```

getent ahostsv4 asks the system resolver for IPv4 addresses. An IPv6-only hostname result would not prove the private IPv4 assignment.

The assigned private IPv4 address for pg-primary appears.

## Install repository-management prerequisites

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On backup-1 as ec2-user.

### Install repository-management prerequisites

Use the Linux terminal.

```bash
sudo dnf -y install epel-release dnf-plugins-core
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
rpm -q epel-release dnf-plugins-core
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Enable the CentOS CRB repository

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On backup-1 as ec2-user.

### Enable the CentOS CRB repository

Use the Linux terminal.

```bash
sudo dnf config-manager --set-enabled crb
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
dnf repolist --enabled
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Install the PostgreSQL package repository

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On backup-1 as ec2-user.

### Install the PostgreSQL package repository

Use the Linux terminal.

```bash
sudo dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
rpm -q pgdg-redhat-repo
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Disable the distribution PostgreSQL module

Prepare the package sources used by the tested PostgreSQL16 and pgBackRest installation.

On backup-1 as ec2-user.

### Disable the distribution PostgreSQL module

Use the Linux terminal.

```bash
sudo dnf -qy module disable postgresql
```

Run this one package-management action, then inspect the separate result. It does not initialize PostgreSQL.

The package or repository state matches this action.

### Check

```bash
sudo dnf -C module list postgresql
```

Find the named package/repository, or the disabled PostgreSQL module state.

## Install the pinned database and backup tools

Install the tested pgBackRest2.59.1 version on the backup server.

On backup-1 as ec2-user.

### Install the pinned database and backup tools

Use the Linux terminal.

```bash
sudo dnf -y install pgbackrest-2.59.1 nfs-utils openssh-clients policycoreutils-python-utils time
```

The version suffixes pin the requested application packages. Supporting operating-system packages come from the configured CentOS repositories.

Installation finishes successfully.

### Check

```bash
pgbackrest version
```

pgBackRest 2.59.1

## Identify nfs-1

Select the named terminal before changing a server.

On nfs-1 as ec2-user.

### Identify nfs-1

Use the Linux terminal.

```bash
hostname
```

hostname prints this machine’s assigned name.

nfs-1

## Inspect the operating system

Use the CentOS Stream9 procedure that was tested for this project.

On nfs-1 as ec2-user.

### Inspect the operating system

Use the Linux terminal.

```bash
cat /etc/centos-release
```

Read the installed operating-system release.

CentOS Stream release9.

## Preserve the original hosts file

Keep a rollback copy before adding the four assigned private names.

On nfs-1 as ec2-user.

### Preserve the original hosts file

Use the Linux terminal.

```bash
sudo cp /etc/hosts /etc/hosts.before-pgbackrest
```

cp preserves the existing contents in a separately named file.

The backup file exists.

### Check

```bash
sudo ls -l /etc/hosts.before-pgbackrest
```

The backup file exists.

## Resolve the assigned private hostnames

Service traffic stays on the assigned private addresses. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On nfs-1 as ec2-user.

### Resolve the assigned private hostnames

Use the Linux terminal.

```bash
sudo vi /etc/hosts
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/hosts.

### File contents

```text
127.0.0.1 localhost localhost.localdomain
::1 localhost localhost.localdomain
{{address:pg-primary}} pg-primary
{{address:pg-standby}} pg-standby
{{address:backup-1}} backup-1
{{address:nfs-1}} nfs-1
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/hosts
```

The exact file path is present. The following service checks establish whether its settings work.

## Resolve the primary IPv4 hostname

Verify the hostname resolves before configuring remote services.

On nfs-1 as ec2-user.

### Resolve the primary IPv4 hostname

Use the Linux terminal.

```bash
getent ahostsv4 pg-primary
```

getent ahostsv4 asks the system resolver for IPv4 addresses. An IPv6-only hostname result would not prove the private IPv4 assignment.

The assigned private IPv4 address for pg-primary appears.

## Install the NFS server tools

NFS and SELinux tools are prerequisites for the repository server.

On nfs-1 as ec2-user.

### Install the NFS server tools

Use the Linux terminal.

```bash
sudo dnf -y install nfs-utils policycoreutils-python-utils
```

dnf installs the named packages and resolves their dependencies.

Installation finishes successfully.

### Check

```bash
rpm -q nfs-utils policycoreutils-python-utils
```

Installation finishes successfully.

## Create the pgbackrest group

NFS uses numeric ownership, so the repository owner must have the same IDs on both ends.

On backup-1 as ec2-user.

### Create the pgbackrest group

Use the Linux terminal.

```bash
sudo groupadd -g 2001 pgbackrest
```

groupadd -g selects the required numeric GID. If the group already exists, inspect it and proceed only if the ID matches; do not delete an existing account.

The group has GID2001.

### Check

```bash
getent group pgbackrest
```

The group has GID2001.

## Create the pgbackrest account

Use a login-capable account on the backup server and non-login ownership accounts on NFS.

On backup-1 as ec2-user.

### Create the pgbackrest account

Use the Linux terminal.

```bash
sudo useradd -u 2001 -g pgbackrest -d /home/pgbackrest -m -s /bin/bash pgbackrest
```

-u sets UID, -g chooses the group. -M and nologin avoid a login home on the NFS server; -m creates the backup account’s own home.

The pgbackrest account has UID and GID2001.

### Check

```bash
id pgbackrest
```

The pgbackrest account has UID and GID2001.

## Create the postgres group

NFS uses numeric ownership, so the repository owner must have the same IDs on both ends.

On nfs-1 as ec2-user.

### Create the postgres group

Use the Linux terminal.

```bash
sudo groupadd -g 26 postgres
```

groupadd -g selects the required numeric GID. If the group already exists, inspect it and proceed only if the ID matches; do not delete an existing account.

The group has GID26.

### Check

```bash
getent group postgres
```

The group has GID26.

## Create the postgres account

Use a login-capable account on the backup server and non-login ownership accounts on NFS.

On nfs-1 as ec2-user.

### Create the postgres account

Use the Linux terminal.

```bash
sudo useradd -u 26 -g postgres -M -s /sbin/nologin postgres
```

-u sets UID, -g chooses the group. -M and nologin avoid a login home on the NFS server; -m creates the backup account’s own home.

The postgres account has UID and GID26.

### Check

```bash
id postgres
```

The postgres account has UID and GID26.

## Create the pgbackrest group

NFS uses numeric ownership, so the repository owner must have the same IDs on both ends.

On nfs-1 as ec2-user.

### Create the pgbackrest group

Use the Linux terminal.

```bash
sudo groupadd -g 2001 pgbackrest
```

groupadd -g selects the required numeric GID. If the group already exists, inspect it and proceed only if the ID matches; do not delete an existing account.

The group has GID2001.

### Check

```bash
getent group pgbackrest
```

The group has GID2001.

## Create the pgbackrest account

Use a login-capable account on the backup server and non-login ownership accounts on NFS.

On nfs-1 as ec2-user.

### Create the pgbackrest account

Use the Linux terminal.

```bash
sudo useradd -u 2001 -g pgbackrest -M -s /sbin/nologin pgbackrest
```

-u sets UID, -g chooses the group. -M and nologin avoid a login home on the NFS server; -m creates the backup account’s own home.

The pgbackrest account has UID and GID2001.

### Check

```bash
id pgbackrest
```

The pgbackrest account has UID and GID2001.

## Set the backup home security label

SELinux must recognize the service home before SSH uses it.

On backup-1 as ec2-user.

### Set the backup home security label

Use the Linux terminal.

```bash
sudo restorecon -RF /home/pgbackrest
```

Restore the expected home-directory labels without disabling SELinux.

The home has its expected SELinux label.

### Check

```bash
sudo ls -ldZ /home/pgbackrest
```

The home has its expected SELinux label.

## Prepare the postgres SSH directory

Keep this service account’s SSH identity and trust files in its own home directory.

On pg-primary as ec2-user.

### Prepare the postgres SSH directory

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/.ssh
```

install -d creates a directory. -m 700 restricts it to the owner, while -o and -g choose the service user and group. It does not generate a key or grant remote access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh
```

postgres:postgres 700 /var/lib/pgsql/.ssh

## Copy service SSH private key

Place the assigned service SSH private key where this service will look for it.

On pg-primary as ec2-user.

### Copy service SSH private key

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/id_ed25519 /var/lib/pgsql/.ssh/id_ed25519
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/id_ed25519
```

The last field names /var/lib/pgsql/.ssh/id_ed25519. Ownership and permissions are set in the next two cards.

## Give postgres ownership of service SSH private key

The postgres account must own this file before it can use the protected material.

On pg-primary as ec2-user.

### Give postgres ownership of service SSH private key

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/.ssh/id_ed25519
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/id_ed25519
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to service SSH private key

Only postgres should read or change this service file.

On pg-primary as ec2-user.

### Restrict access to service SSH private key

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/.ssh/id_ed25519
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/id_ed25519
```

postgres:postgres 600 /var/lib/pgsql/.ssh/id_ed25519. The file contents remain hidden.

## Copy allowed incoming service keys

Place the assigned allowed incoming service keys where this service will look for it.

On pg-primary as ec2-user.

### Copy allowed incoming service keys

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/authorized_keys /var/lib/pgsql/.ssh/authorized_keys
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/authorized_keys
```

The last field names /var/lib/pgsql/.ssh/authorized_keys. Ownership and permissions are set in the next two cards.

## Give postgres ownership of allowed incoming service keys

The postgres account must own this file before it can use the protected material.

On pg-primary as ec2-user.

### Give postgres ownership of allowed incoming service keys

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/.ssh/authorized_keys
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/authorized_keys
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to allowed incoming service keys

Only postgres should read or change this service file.

On pg-primary as ec2-user.

### Restrict access to allowed incoming service keys

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/.ssh/authorized_keys
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/authorized_keys
```

postgres:postgres 600 /var/lib/pgsql/.ssh/authorized_keys. The file contents remain hidden.

## Copy verified server identities

Place the assigned verified server identities where this service will look for it.

On pg-primary as ec2-user.

### Copy verified server identities

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/known_hosts /var/lib/pgsql/.ssh/known_hosts
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/known_hosts
```

The last field names /var/lib/pgsql/.ssh/known_hosts. Ownership and permissions are set in the next two cards.

## Give postgres ownership of verified server identities

The postgres account must own this file before it can use the protected material.

On pg-primary as ec2-user.

### Give postgres ownership of verified server identities

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/.ssh/known_hosts
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/known_hosts
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to verified server identities

Only postgres should read or change this service file.

On pg-primary as ec2-user.

### Restrict access to verified server identities

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/.ssh/known_hosts
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/known_hosts
```

postgres:postgres 600 /var/lib/pgsql/.ssh/known_hosts. The file contents remain hidden.

## Copy strict SSH client settings

Place the assigned strict SSH client settings where this service will look for it.

On pg-primary as ec2-user.

### Copy strict SSH client settings

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/ssh_config /var/lib/pgsql/.ssh/config
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/config
```

The last field names /var/lib/pgsql/.ssh/config. Ownership and permissions are set in the next two cards.

## Give postgres ownership of strict SSH client settings

The postgres account must own this file before it can use the protected material.

On pg-primary as ec2-user.

### Give postgres ownership of strict SSH client settings

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/.ssh/config
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/config
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to strict SSH client settings

Only postgres should read or change this service file.

On pg-primary as ec2-user.

### Restrict access to strict SSH client settings

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/.ssh/config
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/config
```

postgres:postgres 600 /var/lib/pgsql/.ssh/config. The file contents remain hidden.

## Restore the SSH security labels

SELinux checks the file label as well as Linux owner and permission bits.

On pg-primary as ec2-user.

### Restore the SSH security labels

Use the Linux terminal.

```bash
sudo restorecon -RF /var/lib/pgsql/.ssh
```

restorecon reapplies this system’s expected SELinux labels. -R visits the directory contents and -F resets the full label. SELinux stays enforcing.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo ls -ldZ /var/lib/pgsql/.ssh
```

The SSH directory has the service owner, restrictive permissions and an ssh_home_t SELinux type.

## Prepare the postgres SSH directory

Keep this service account’s SSH identity and trust files in its own home directory.

On pg-standby as ec2-user.

### Prepare the postgres SSH directory

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/.ssh
```

install -d creates a directory. -m 700 restricts it to the owner, while -o and -g choose the service user and group. It does not generate a key or grant remote access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh
```

postgres:postgres 700 /var/lib/pgsql/.ssh

## Copy service SSH private key

Place the assigned service SSH private key where this service will look for it.

On pg-standby as ec2-user.

### Copy service SSH private key

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/id_ed25519 /var/lib/pgsql/.ssh/id_ed25519
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/id_ed25519
```

The last field names /var/lib/pgsql/.ssh/id_ed25519. Ownership and permissions are set in the next two cards.

## Give postgres ownership of service SSH private key

The postgres account must own this file before it can use the protected material.

On pg-standby as ec2-user.

### Give postgres ownership of service SSH private key

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/.ssh/id_ed25519
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/id_ed25519
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to service SSH private key

Only postgres should read or change this service file.

On pg-standby as ec2-user.

### Restrict access to service SSH private key

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/.ssh/id_ed25519
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/id_ed25519
```

postgres:postgres 600 /var/lib/pgsql/.ssh/id_ed25519. The file contents remain hidden.

## Copy allowed incoming service keys

Place the assigned allowed incoming service keys where this service will look for it.

On pg-standby as ec2-user.

### Copy allowed incoming service keys

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/authorized_keys /var/lib/pgsql/.ssh/authorized_keys
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/authorized_keys
```

The last field names /var/lib/pgsql/.ssh/authorized_keys. Ownership and permissions are set in the next two cards.

## Give postgres ownership of allowed incoming service keys

The postgres account must own this file before it can use the protected material.

On pg-standby as ec2-user.

### Give postgres ownership of allowed incoming service keys

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/.ssh/authorized_keys
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/authorized_keys
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to allowed incoming service keys

Only postgres should read or change this service file.

On pg-standby as ec2-user.

### Restrict access to allowed incoming service keys

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/.ssh/authorized_keys
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/authorized_keys
```

postgres:postgres 600 /var/lib/pgsql/.ssh/authorized_keys. The file contents remain hidden.

## Copy verified server identities

Place the assigned verified server identities where this service will look for it.

On pg-standby as ec2-user.

### Copy verified server identities

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/known_hosts /var/lib/pgsql/.ssh/known_hosts
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/known_hosts
```

The last field names /var/lib/pgsql/.ssh/known_hosts. Ownership and permissions are set in the next two cards.

## Give postgres ownership of verified server identities

The postgres account must own this file before it can use the protected material.

On pg-standby as ec2-user.

### Give postgres ownership of verified server identities

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/.ssh/known_hosts
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/known_hosts
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to verified server identities

Only postgres should read or change this service file.

On pg-standby as ec2-user.

### Restrict access to verified server identities

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/.ssh/known_hosts
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/known_hosts
```

postgres:postgres 600 /var/lib/pgsql/.ssh/known_hosts. The file contents remain hidden.

## Copy strict SSH client settings

Place the assigned strict SSH client settings where this service will look for it.

On pg-standby as ec2-user.

### Copy strict SSH client settings

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/ssh_config /var/lib/pgsql/.ssh/config
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/config
```

The last field names /var/lib/pgsql/.ssh/config. Ownership and permissions are set in the next two cards.

## Give postgres ownership of strict SSH client settings

The postgres account must own this file before it can use the protected material.

On pg-standby as ec2-user.

### Give postgres ownership of strict SSH client settings

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/.ssh/config
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/config
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to strict SSH client settings

Only postgres should read or change this service file.

On pg-standby as ec2-user.

### Restrict access to strict SSH client settings

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/.ssh/config
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.ssh/config
```

postgres:postgres 600 /var/lib/pgsql/.ssh/config. The file contents remain hidden.

## Restore the SSH security labels

SELinux checks the file label as well as Linux owner and permission bits.

On pg-standby as ec2-user.

### Restore the SSH security labels

Use the Linux terminal.

```bash
sudo restorecon -RF /var/lib/pgsql/.ssh
```

restorecon reapplies this system’s expected SELinux labels. -R visits the directory contents and -F resets the full label. SELinux stays enforcing.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo ls -ldZ /var/lib/pgsql/.ssh
```

The SSH directory has the service owner, restrictive permissions and an ssh_home_t SELinux type.

## Prepare the pgbackrest SSH directory

Keep this service account’s SSH identity and trust files in its own home directory.

On backup-1 as ec2-user.

### Prepare the pgbackrest SSH directory

Use the Linux terminal.

```bash
sudo install -d -m 700 -o pgbackrest -g pgbackrest /home/pgbackrest/.ssh
```

install -d creates a directory. -m 700 restricts it to the owner, while -o and -g choose the service user and group. It does not generate a key or grant remote access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh
```

pgbackrest:pgbackrest 700 /home/pgbackrest/.ssh

## Copy service SSH private key

Place the assigned service SSH private key where this service will look for it.

On backup-1 as ec2-user.

### Copy service SSH private key

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/id_ed25519 /home/pgbackrest/.ssh/id_ed25519
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/id_ed25519
```

The last field names /home/pgbackrest/.ssh/id_ed25519. Ownership and permissions are set in the next two cards.

## Give pgbackrest ownership of service SSH private key

The pgbackrest account must own this file before it can use the protected material.

On backup-1 as ec2-user.

### Give pgbackrest ownership of service SSH private key

Use the Linux terminal.

```bash
sudo chown pgbackrest:pgbackrest /home/pgbackrest/.ssh/id_ed25519
```

chown sets the owner and group to pgbackrest. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/id_ed25519
```

pgbackrest:pgbackrest in the first field, followed by the permissions and exact path.

## Restrict access to service SSH private key

Only pgbackrest should read or change this service file.

On backup-1 as ec2-user.

### Restrict access to service SSH private key

Use the Linux terminal.

```bash
sudo chmod 600 /home/pgbackrest/.ssh/id_ed25519
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/id_ed25519
```

pgbackrest:pgbackrest 600 /home/pgbackrest/.ssh/id_ed25519. The file contents remain hidden.

## Copy allowed incoming service keys

Place the assigned allowed incoming service keys where this service will look for it.

On backup-1 as ec2-user.

### Copy allowed incoming service keys

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/authorized_keys /home/pgbackrest/.ssh/authorized_keys
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/authorized_keys
```

The last field names /home/pgbackrest/.ssh/authorized_keys. Ownership and permissions are set in the next two cards.

## Give pgbackrest ownership of allowed incoming service keys

The pgbackrest account must own this file before it can use the protected material.

On backup-1 as ec2-user.

### Give pgbackrest ownership of allowed incoming service keys

Use the Linux terminal.

```bash
sudo chown pgbackrest:pgbackrest /home/pgbackrest/.ssh/authorized_keys
```

chown sets the owner and group to pgbackrest. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/authorized_keys
```

pgbackrest:pgbackrest in the first field, followed by the permissions and exact path.

## Restrict access to allowed incoming service keys

Only pgbackrest should read or change this service file.

On backup-1 as ec2-user.

### Restrict access to allowed incoming service keys

Use the Linux terminal.

```bash
sudo chmod 600 /home/pgbackrest/.ssh/authorized_keys
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/authorized_keys
```

pgbackrest:pgbackrest 600 /home/pgbackrest/.ssh/authorized_keys. The file contents remain hidden.

## Copy verified server identities

Place the assigned verified server identities where this service will look for it.

On backup-1 as ec2-user.

### Copy verified server identities

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/known_hosts /home/pgbackrest/.ssh/known_hosts
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/known_hosts
```

The last field names /home/pgbackrest/.ssh/known_hosts. Ownership and permissions are set in the next two cards.

## Give pgbackrest ownership of verified server identities

The pgbackrest account must own this file before it can use the protected material.

On backup-1 as ec2-user.

### Give pgbackrest ownership of verified server identities

Use the Linux terminal.

```bash
sudo chown pgbackrest:pgbackrest /home/pgbackrest/.ssh/known_hosts
```

chown sets the owner and group to pgbackrest. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/known_hosts
```

pgbackrest:pgbackrest in the first field, followed by the permissions and exact path.

## Restrict access to verified server identities

Only pgbackrest should read or change this service file.

On backup-1 as ec2-user.

### Restrict access to verified server identities

Use the Linux terminal.

```bash
sudo chmod 600 /home/pgbackrest/.ssh/known_hosts
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/known_hosts
```

pgbackrest:pgbackrest 600 /home/pgbackrest/.ssh/known_hosts. The file contents remain hidden.

## Copy strict SSH client settings

Place the assigned strict SSH client settings where this service will look for it.

On backup-1 as ec2-user.

### Copy strict SSH client settings

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/ssh_config /home/pgbackrest/.ssh/config
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/config
```

The last field names /home/pgbackrest/.ssh/config. Ownership and permissions are set in the next two cards.

## Give pgbackrest ownership of strict SSH client settings

The pgbackrest account must own this file before it can use the protected material.

On backup-1 as ec2-user.

### Give pgbackrest ownership of strict SSH client settings

Use the Linux terminal.

```bash
sudo chown pgbackrest:pgbackrest /home/pgbackrest/.ssh/config
```

chown sets the owner and group to pgbackrest. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/config
```

pgbackrest:pgbackrest in the first field, followed by the permissions and exact path.

## Restrict access to strict SSH client settings

Only pgbackrest should read or change this service file.

On backup-1 as ec2-user.

### Restrict access to strict SSH client settings

Use the Linux terminal.

```bash
sudo chmod 600 /home/pgbackrest/.ssh/config
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /home/pgbackrest/.ssh/config
```

pgbackrest:pgbackrest 600 /home/pgbackrest/.ssh/config. The file contents remain hidden.

## Restore the SSH security labels

SELinux checks the file label as well as Linux owner and permission bits.

On backup-1 as ec2-user.

### Restore the SSH security labels

Use the Linux terminal.

```bash
sudo restorecon -RF /home/pgbackrest/.ssh
```

restorecon reapplies this system’s expected SELinux labels. -R visits the directory contents and -F resets the full label. SELinux stays enforcing.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo ls -ldZ /home/pgbackrest/.ssh
```

The SSH directory has the service owner, restrictive permissions and an ssh_home_t SELinux type.

## Prepare pgBackRest log and spool directories

The executing account needs local log and spool directories.

On pg-primary as ec2-user.

### Prepare pgBackRest log and spool directories

Use the Linux terminal.

```bash
sudo install -d -m 750 -o postgres -g postgres /var/log/pgbackrest /var/spool/pgbackrest
```

install -d creates these two related working directories with the intended owner and permissions.

Both directories belong to postgres with mode750.

### Check

```bash
sudo ls -ld /var/log/pgbackrest /var/spool/pgbackrest
```

Both directories belong to postgres with mode750.

## Create the pgBackRest configuration directory

Keep system configuration in the path pgBackRest expects.

On pg-primary as ec2-user.

### Create the pgBackRest configuration directory

Use the Linux terminal.

```bash
sudo install -d -m 755 /etc/pgbackrest
```

Create the directory without writing any repository settings yet.

/etc/pgbackrest exists.

### Check

```bash
ls -ld /etc/pgbackrest
```

/etc/pgbackrest exists.

## Prepare pgBackRest log and spool directories

The executing account needs local log and spool directories.

On pg-standby as ec2-user.

### Prepare pgBackRest log and spool directories

Use the Linux terminal.

```bash
sudo install -d -m 750 -o postgres -g postgres /var/log/pgbackrest /var/spool/pgbackrest
```

install -d creates these two related working directories with the intended owner and permissions.

Both directories belong to postgres with mode750.

### Check

```bash
sudo ls -ld /var/log/pgbackrest /var/spool/pgbackrest
```

Both directories belong to postgres with mode750.

## Create the pgBackRest configuration directory

Keep system configuration in the path pgBackRest expects.

On pg-standby as ec2-user.

### Create the pgBackRest configuration directory

Use the Linux terminal.

```bash
sudo install -d -m 755 /etc/pgbackrest
```

Create the directory without writing any repository settings yet.

/etc/pgbackrest exists.

### Check

```bash
ls -ld /etc/pgbackrest
```

/etc/pgbackrest exists.

## Prepare pgBackRest log and spool directories

The executing account needs local log and spool directories.

On backup-1 as ec2-user.

### Prepare pgBackRest log and spool directories

Use the Linux terminal.

```bash
sudo install -d -m 750 -o pgbackrest -g pgbackrest /var/log/pgbackrest /var/spool/pgbackrest
```

install -d creates these two related working directories with the intended owner and permissions.

Both directories belong to pgbackrest with mode750.

### Check

```bash
sudo ls -ld /var/log/pgbackrest /var/spool/pgbackrest
```

Both directories belong to pgbackrest with mode750.

## Create the pgBackRest configuration directory

Keep system configuration in the path pgBackRest expects.

On backup-1 as ec2-user.

### Create the pgBackRest configuration directory

Use the Linux terminal.

```bash
sudo install -d -m 755 /etc/pgbackrest
```

Create the directory without writing any repository settings yet.

/etc/pgbackrest exists.

### Check

```bash
ls -ld /etc/pgbackrest
```

/etc/pgbackrest exists.

## Create the repository parent directory

The two repository namespaces share a parent without sharing their owner.

On nfs-1 as ec2-user.

### Create the repository parent directory

Use the Linux terminal.

```bash
sudo install -d -m 755 /srv/pgbackrest
```

Create a root-owned parent directory.

/srv/pgbackrest exists.

### Check

```bash
ls -ld /srv/pgbackrest
```

/srv/pgbackrest exists.

## Create the direct repository directory

NFS maps the matching numeric service UID to this directory owner.

On nfs-1 as ec2-user.

### Create the direct repository directory

Use the Linux terminal.

```bash
sudo install -d -m 750 -o postgres -g postgres /srv/pgbackrest/direct
```

Create the repository directory and restrict it to its service account and group.

The direct directory belongs to postgres.

### Check

```bash
stat -c "%u:%g %a %n" /srv/pgbackrest/direct
```

The direct directory belongs to postgres.

## Create the server repository directory

NFS maps the matching numeric service UID to this directory owner.

On nfs-1 as ec2-user.

### Create the server repository directory

Use the Linux terminal.

```bash
sudo install -d -m 750 -o pgbackrest -g pgbackrest /srv/pgbackrest/server
```

Create the repository directory and restrict it to its service account and group.

The server directory belongs to pgbackrest.

### Check

```bash
stat -c "%u:%g %a %n" /srv/pgbackrest/server
```

The server directory belongs to pgbackrest.

## Allow only the two assigned NFS clients

Export each directory only to its assigned client. root_squash prevents client root from becoming repository root. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On nfs-1 as ec2-user.

### Allow only the two assigned NFS clients

Use the Linux terminal.

```bash
sudo vi /etc/exports.d/pgbackrest.exports
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/exports.d/pgbackrest.exports.

### File contents

```text
/srv/pgbackrest/direct {{address:pg-primary}}(rw,sync,root_squash,no_subtree_check)
/srv/pgbackrest/server {{address:backup-1}}(rw,sync,root_squash,no_subtree_check)
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/exports.d/pgbackrest.exports
```

The exact file path is present. The following service checks establish whether its settings work.

## Use NFSv4 without NFSv3 or UDP

Match the private TCP2049 network rule and the tested NFSv4 layout. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On nfs-1 as ec2-user.

### Use NFSv4 without NFSv3 or UDP

Use the Linux terminal.

```bash
sudo vi /etc/nfs.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/nfs.conf.

### File contents

```text
[nfsd]
vers3=n
vers4=y
udp=n
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/nfs.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Enable NFS at boot

The repository service must return after a reboot.

On nfs-1 as ec2-user.

### Enable NFS at boot

Use the Linux terminal.

```bash
sudo systemctl enable nfs-server
```

enable configures boot startup; it does not itself start the service.

The unit is enabled.

### Check

```bash
systemctl is-enabled nfs-server
```

The unit is enabled.

## Start the NFS server

Start serving the configured repository exports.

On nfs-1 as ec2-user.

### Start the NFS server

Use the Linux terminal.

```bash
sudo systemctl start nfs-server
```

start activates the service now.

The service is active.

### Check

```bash
systemctl is-active nfs-server
```

The service is active.

## Apply the export definitions

Make the two export definitions active.

On nfs-1 as ec2-user.

### Apply the export definitions

Use the Linux terminal.

```bash
sudo exportfs -rav
```

exportfs reloads the exports and reports each one.

Both intended exports are listed.

### Check

```bash
sudo exportfs -v
```

Each path names its single assigned client and includes root_squash and sync.

## Prepare the client repository parent

Keep the underlying mount layout owned by root.

On pg-primary as ec2-user.

### Prepare the client repository parent

Use the Linux terminal.

```bash
sudo install -d -m 755 -o root -g root /var/lib/pgbackrest
```

Create the parent with directory traversal access.

The parent is root-owned.

### Check

```bash
ls -ld /var/lib/pgbackrest
```

The parent is root-owned.

## Protect the unmounted directory

A missing NFS mount must not silently turn a backup into a local-disk backup.

On pg-primary as ec2-user.

### Protect the unmounted directory

Use the Linux terminal.

```bash
sudo install -d -m 555 -o root -g root /var/lib/pgbackrest/direct
```

Mode555 makes the underlying directory non-writable to the service user. The mounted export has its own permissions.

Before mounting, the directory is root:root with mode555.

### Check

```bash
stat -c "%U:%G %a %n" /var/lib/pgbackrest/direct
```

Before mounting, the directory is root:root with mode555.

## Add the persistent direct mount

Mount this repository after networking is available. hard retries protect NFS write semantics; the systemd mount timeout bounds initial mounting. Keep every existing line. Move to the end of the file and append only the supplied entry.

On pg-primary as ec2-user.

### Add the persistent direct mount

Use the Linux terminal.

```bash
sudo vi /etc/fstab
```

vi opens this exact file. Keep every existing line. Move to the end of the file and append only the supplied entry. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/fstab.

### File contents

```text
{{address:nfs-1}}:/srv/pgbackrest/direct /var/lib/pgbackrest/direct nfs4 vers=4.2,hard,timeo=600,retrans=2,_netdev,x-systemd.mount-timeout=60s 0 0
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/fstab
```

The exact file path is present. The following service checks establish whether its settings work.

## Reload the mount definitions

systemd generates mount units from fstab.

On pg-primary as ec2-user.

### Reload the mount definitions

Use the Linux terminal.

```bash
sudo systemctl daemon-reload
```

Reload those definitions after saving the new entry.

The command returns without error.

### Check

```bash
systemctl --failed --no-pager
```

Investigate any failed mount unit before continuing.

## Mount the direct NFS repository

Attach the remote export before pgBackRest writes any files.

On pg-primary as ec2-user.

### Mount the direct NFS repository

Use the Linux terminal.

```bash
sudo mount /var/lib/pgbackrest/direct
```

mount reads the matching fstab entry for this destination.

The NFS export is mounted.

### Check

```bash
findmnt -T /var/lib/pgbackrest/direct -o SOURCE,TARGET,FSTYPE,OPTIONS
```

The source is nfs-1’s assigned export, the target is /var/lib/pgbackrest/direct, and the filesystem is NFSv4.

## Prove the service account can write to NFS

The process that runs the backup must be able to create a file on the mounted export.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Create a small write probe

Type this in the postgres Linux shell on pg-primary.

```bash
touch /var/lib/pgbackrest/direct/.service-write-proof
```

Create an empty file as the service account.

The prompt returns without a permission error.

### Inspect the probe

Type this in the postgres Linux shell on pg-primary.

```bash
stat -c "%u:%g %a %n" /var/lib/pgbackrest/direct/.service-write-proof
```

Show the numeric ownership that NFS uses.

The file has the service UID/GID and resides under the mounted path.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Prepare the client repository parent

Keep the underlying mount layout owned by root.

On backup-1 as ec2-user.

### Prepare the client repository parent

Use the Linux terminal.

```bash
sudo install -d -m 755 -o root -g root /var/lib/pgbackrest
```

Create the parent with directory traversal access.

The parent is root-owned.

### Check

```bash
ls -ld /var/lib/pgbackrest
```

The parent is root-owned.

## Protect the unmounted directory

A missing NFS mount must not silently turn a backup into a local-disk backup.

On backup-1 as ec2-user.

### Protect the unmounted directory

Use the Linux terminal.

```bash
sudo install -d -m 555 -o root -g root /var/lib/pgbackrest/server
```

Mode555 makes the underlying directory non-writable to the service user. The mounted export has its own permissions.

Before mounting, the directory is root:root with mode555.

### Check

```bash
stat -c "%U:%G %a %n" /var/lib/pgbackrest/server
```

Before mounting, the directory is root:root with mode555.

## Add the persistent server mount

Mount this repository after networking is available. hard retries protect NFS write semantics; the systemd mount timeout bounds initial mounting. Keep every existing line. Move to the end of the file and append only the supplied entry.

On backup-1 as ec2-user.

### Add the persistent server mount

Use the Linux terminal.

```bash
sudo vi /etc/fstab
```

vi opens this exact file. Keep every existing line. Move to the end of the file and append only the supplied entry. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/fstab.

### File contents

```text
{{address:nfs-1}}:/srv/pgbackrest/server /var/lib/pgbackrest/server nfs4 vers=4.2,hard,timeo=600,retrans=2,_netdev,x-systemd.mount-timeout=60s 0 0
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/fstab
```

The exact file path is present. The following service checks establish whether its settings work.

## Reload the mount definitions

systemd generates mount units from fstab.

On backup-1 as ec2-user.

### Reload the mount definitions

Use the Linux terminal.

```bash
sudo systemctl daemon-reload
```

Reload those definitions after saving the new entry.

The command returns without error.

### Check

```bash
systemctl --failed --no-pager
```

Investigate any failed mount unit before continuing.

## Mount the server NFS repository

Attach the remote export before pgBackRest writes any files.

On backup-1 as ec2-user.

### Mount the server NFS repository

Use the Linux terminal.

```bash
sudo mount /var/lib/pgbackrest/server
```

mount reads the matching fstab entry for this destination.

The NFS export is mounted.

### Check

```bash
findmnt -T /var/lib/pgbackrest/server -o SOURCE,TARGET,FSTYPE,OPTIONS
```

The source is nfs-1’s assigned export, the target is /var/lib/pgbackrest/server, and the filesystem is NFSv4.

## Prove the service account can write to NFS

The process that runs the backup must be able to create a file on the mounted export.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Create a small write probe

Type this in the pgbackrest Linux shell on backup-1.

```bash
touch /var/lib/pgbackrest/server/.service-write-proof
```

Create an empty file as the service account.

The prompt returns without a permission error.

### Inspect the probe

Type this in the pgbackrest Linux shell on backup-1.

```bash
stat -c "%u:%g %a %n" /var/lib/pgbackrest/server/.service-write-proof
```

Show the numeric ownership that NFS uses.

The file has the service UID/GID and resides under the mounted path.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Initialize the PostgreSQL primary

Create a new database only in the empty assigned data directory.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Initialize PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/initdb -D /var/lib/pgsql/16/data --data-checksums --auth-local=peer --auth-host=scram-sha-256
```

initdb creates the cluster, enables data checksums, uses local peer authentication and selects SCRAM for host authentication. Do not run it against an existing cluster.

Initialization completes successfully.

### Inspect the cluster control data

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_controldata /var/lib/pgsql/16/data
```

Read the cluster identity and checksum version without starting it.

The control data is readable and the data-page checksum version is1.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Copy PostgreSQL TLS private key

Place the assigned PostgreSQL TLS private key where this service will look for it.

On pg-primary as ec2-user.

### Copy PostgreSQL TLS private key

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/server.key /var/lib/pgsql/16/data/server.key
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/server.key
```

The last field names /var/lib/pgsql/16/data/server.key. Ownership and permissions are set in the next two cards.

## Give postgres ownership of PostgreSQL TLS private key

The postgres account must own this file before it can use the protected material.

On pg-primary as ec2-user.

### Give postgres ownership of PostgreSQL TLS private key

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/16/data/server.key
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/server.key
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to PostgreSQL TLS private key

Only postgres should read or change this service file.

On pg-primary as ec2-user.

### Restrict access to PostgreSQL TLS private key

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/16/data/server.key
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/server.key
```

postgres:postgres 600 /var/lib/pgsql/16/data/server.key. The file contents remain hidden.

## Copy PostgreSQL server certificate

Place the assigned PostgreSQL server certificate where this service will look for it.

On pg-primary as ec2-user.

### Copy PostgreSQL server certificate

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/server.crt /var/lib/pgsql/16/data/server.crt
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/server.crt
```

The last field names /var/lib/pgsql/16/data/server.crt. Ownership and permissions are set in the next two cards.

## Give postgres ownership of PostgreSQL server certificate

The postgres account must own this file before it can use the protected material.

On pg-primary as ec2-user.

### Give postgres ownership of PostgreSQL server certificate

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/16/data/server.crt
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/server.crt
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to PostgreSQL server certificate

Only postgres should read or change this service file.

On pg-primary as ec2-user.

### Restrict access to PostgreSQL server certificate

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/16/data/server.crt
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/server.crt
```

postgres:postgres 600 /var/lib/pgsql/16/data/server.crt. The file contents remain hidden.

## Copy trusted replication certificate

Place the assigned trusted replication certificate where this service will look for it.

On pg-standby as ec2-user.

### Copy trusted replication certificate

Use the Linux terminal.

```bash
sudo cp /opt/suta/handoff/pgbackrest-trust/root.crt /var/lib/pgsql/root.crt
```

cp copies one staged file to the displayed destination. sudo permits reading the root-protected handoff. This action does not print the file contents.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/root.crt
```

The last field names /var/lib/pgsql/root.crt. Ownership and permissions are set in the next two cards.

## Give postgres ownership of trusted replication certificate

The postgres account must own this file before it can use the protected material.

On pg-standby as ec2-user.

### Give postgres ownership of trusted replication certificate

Use the Linux terminal.

```bash
sudo chown postgres:postgres /var/lib/pgsql/root.crt
```

chown sets the owner and group to postgres. It does not change the contents or grant other users access.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/root.crt
```

postgres:postgres in the first field, followed by the permissions and exact path.

## Restrict access to trusted replication certificate

Only postgres should read or change this service file.

On pg-standby as ec2-user.

### Restrict access to trusted replication certificate

Use the Linux terminal.

```bash
sudo chmod 600 /var/lib/pgsql/root.crt
```

chmod 600 grants the owner read and write access and removes group and other-user access. For the private SSH key this also satisfies OpenSSH permission checks.

The command returns to your ec2-user prompt without an error. Run the separate check below.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/root.crt
```

postgres:postgres 600 /var/lib/pgsql/root.crt. The file contents remain hidden.

## Configure the primary database

Set the tested data path, WAL capacity, replication limits, TLS and logging. Archiving stays off until both repository stanzas exist. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Configure the primary database

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/16/data/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/16/data/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/16/data'
listen_addresses = '*'
port = 5432
unix_socket_directories = '/var/run/postgresql'
wal_level = replica
max_wal_senders = 5
max_replication_slots = 5
wal_keep_size = '128MB'
max_slot_wal_keep_size = '512MB'
hot_standby = on
archive_mode = off
archive_command = 'pgbackrest --stanza=academy archive-push %p'
archive_timeout = 60
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
password_encryption = 'scram-sha-256'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql.log'
log_line_prefix = '%m [%p] '
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Allow only the standby replication connection

Allow the replicator account from the assigned standby only, with TLS and SCRAM. Local postgres administration uses peer authentication. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Allow only the standby replication connection

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/16/data/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/16/data/pg_hba.conf.

### File contents

```text
local all postgres peer
local all all peer
hostssl replication replicator {{address:pg-standby}}/32 scram-sha-256
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Enable the primary service

The service must be enabled for boot and started for current connections.

On pg-primary as ec2-user.

### Enable the primary service

Use the Linux terminal.

```bash
sudo systemctl enable postgresql-16
```

systemctl enable configures boot startup.

The service is enabled.

### Check

```bash
systemctl is-enabled postgresql-16
```

The service is enabled.

## Start the primary service

The service must be enabled for boot and started for current connections.

On pg-primary as ec2-user.

### Start the primary service

Use the Linux terminal.

```bash
sudo systemctl start postgresql-16
```

systemctl start starts the database now.

The service is active.

### Check

```bash
systemctl is-active postgresql-16
```

The service is active.

## Check the data directory and checksums

Prove which database this session reached before changing its contents.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Read the data directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the active server’s data-directory setting.

/var/lib/pgsql/16/data

### Read checksum status

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_checksums;
```

Read whether data-page checksums are enabled.

on

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Create a replication-only database login

Give the standby a limited account instead of a superuser password.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Create the replicator role

Type this at postgres=#. Do not type the prompt itself.

```sql
CREATE ROLE replicator WITH LOGIN REPLICATION;
```

LOGIN allows authentication; REPLICATION allows the replication protocol. This does not grant superuser privileges.

CREATE ROLE

### Inspect the role

Type this at postgres=#. Do not type the prompt itself.

```text
\du replicator
```

List the role attributes without displaying a credential.

replicator has the Replication attribute and is not a superuser.

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Set the protected replication password

Set the generated password through psql’s hidden-input flow.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Start the password change

Type this at postgres=#. Do not type the prompt itself.

```text
\password replicator
```

psql prompts without placing the plaintext in a SQL statement or shell history.

Wait for Enter new password for user "replicator":.

### Enter the protected password

Use the current step’s Load protected password control. Enter it only at the hidden terminal prompt.

Nothing appearing while you type is normal.

Wait for Enter it again:.

### Repeat the same protected password

Use the current step’s Load protected password control. Enter it only at the hidden terminal prompt.

Nothing appearing while you type is normal.

Wait for postgres=# before checking the role.

### Check SCRAM storage

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT rolname, rolpassword LIKE 'SCRAM-SHA-256%' AS scram FROM pg_authid WHERE rolname = 'replicator';
```

Read only a boolean about the stored verifier, never its value.

replicator appears with scram=t.

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Create the backup practice data

Use a small known dataset so restores can be checked against exact records.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Create the proof table

Type this at postgres=#. Do not type the prompt itself.

```sql
CREATE TABLE academy_proof (id integer PRIMARY KEY, event text NOT NULL);
```

The primary key makes duplicate or missing markers detectable.

CREATE TABLE

### Insert the baseline marker

Type this at postgres=#. Do not type the prompt itself.

```sql
INSERT INTO academy_proof VALUES (1, 'baseline');
```

This record must exist in the first full restore.

INSERT 0 1

### Create a repeatable backup payload

Type this at postgres=#. Do not type the prompt itself.

```sql
CREATE TABLE academy_payload AS SELECT i AS id, repeat(md5(i::text),128) AS payload FROM generate_series(1,10000) i;
```

Create ten thousand deterministic rows for backup and restore exercises. This is a small synthetic workload.

SELECT 10000

### Inspect the marker

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Read the actual baseline record.

One row: id1, event baseline.

### Count the payload

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_payload;
```

Check the known dataset size.

10000

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Create a private file before entering its contents

Prepare an empty file with restrictive permissions before entering the protected value.

On pg-standby as ec2-user.

### Create a private file before entering its contents

Use the Linux terminal.

```bash
sudo install -m 600 -o postgres -g postgres /dev/null /var/lib/pgsql/.pgpass
```

install copies the empty /dev/null input to this new file and sets its owner and mode. Use this once during initial setup.

The new file belongs to the service user with mode600.

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.pgpass
```

postgres:postgres 600 /var/lib/pgsql/.pgpass

## Store the standby’s replication credential

Use the same generated replication password. The passfile lets the replica reconnect without putting a password in its connection string. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-standby as ec2-user.

### Store the standby’s replication credential

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/.pgpass
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/.pgpass.

### File contents

```text
pg-primary:5432:replication:replicator:{{secret:replication}}
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/.pgpass
```

The exact file path is present. The following service checks establish whether its settings work.

## Seed the standby from the primary

Copy the database through the replication protocol with verified server identity.

On pg-standby as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-standby, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-standby.

### Take the base backup

Type this in the postgres Linux shell on pg-standby.

```bash
/usr/pgsql-16/bin/pg_basebackup --dbname="host=pg-primary user=replicator application_name=pg-standby sslmode=verify-full sslrootcert=/var/lib/pgsql/root.crt passfile=/var/lib/pgsql/.pgpass" -D /var/lib/pgsql/16/data -R -X stream -C -S academy_standby --checkpoint=fast --progress
```

The connection uses the protected passfile and verifies pg-primary’s certificate. -R writes standby settings, -X streams required WAL, and -C/-S create the named physical replication slot. The destination must be empty.

The base backup finishes successfully.

### Check standby mode

Type this in the postgres Linux shell on pg-standby.

```bash
ls -l /var/lib/pgsql/16/data/standby.signal
```

This marker tells PostgreSQL to start as a standby. It does not prove that streaming works yet.

standby.signal exists.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Enable the standby service

Start the seeded standby and enable its normal boot behavior.

On pg-standby as ec2-user.

### Enable the standby service

Use the Linux terminal.

```bash
sudo systemctl enable postgresql-16
```

This service operation acts on pg-standby only.

The service is enabled.

### Check

```bash
systemctl is-enabled postgresql-16
```

The service is enabled.

## Start the standby service

Start the seeded standby and enable its normal boot behavior.

On pg-standby as ec2-user.

### Start the standby service

Use the Linux terminal.

```bash
sudo systemctl start postgresql-16
```

This service operation acts on pg-standby only.

The service is active.

### Check

```bash
systemctl is-active postgresql-16
```

The service is active.

## Prove streaming and TLS from the primary

Separate replication state from transport security.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Inspect the sender

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT application_name,state,sync_state FROM pg_stat_replication;
```

Read the connected standby’s replication state.

pg-standby is streaming with sync_state=async.

### Inspect transport security

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT r.application_name,s.ssl,s.version FROM pg_stat_replication r JOIN pg_stat_ssl s USING(pid);
```

Correlate the replication process with its TLS connection.

pg-standby has ssl=t and a TLS version.

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Prove the standby role and replicated records

A streaming connection alone does not prove the expected business records are present.

On pg-standby as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-standby, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-standby.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-standby.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Check recovery mode

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_is_in_recovery();
```

A physical standby remains in recovery.

t

### Inspect the baseline

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Read the record created on the primary.

id1, event baseline.

### Count replicated payload

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_payload;
```

Check the full known dataset reached the standby.

10000

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write pgbackrest.conf on pg-primary

The direct backup profile includes local primary and remote standby with a local repository. The primary archive profile includes remote repositories without remote database hosts. The backup server profile coordinates both database hosts with its local NFS mount. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write pgbackrest.conf on pg-primary

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/pgbackrest.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/16/data
[global]
process-max=2
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=zst
repo1-path=/var/lib/pgbackrest/direct
repo1-retention-full=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
repo2-retention-full=2
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign the profile to its service user

The executing account must own and read the profile.

On pg-primary as ec2-user.

### Assign the profile to its service user

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
```

chown changes owner and group, not the configuration contents.

The file belongs to postgres.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The file belongs to postgres.

## Restrict the profile permissions

Limit configuration access to the service owner and group.

On pg-primary as ec2-user.

### Restrict the profile permissions

Use the Linux terminal.

```bash
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
```

Mode640 gives owner read/write and group read access.

The mode is640.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The mode is640.

## Write direct.conf on pg-primary

The direct backup profile includes local primary and remote standby with a local repository. The primary archive profile includes remote repositories without remote database hosts. The backup server profile coordinates both database hosts with its local NFS mount. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write direct.conf on pg-primary

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/direct.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/direct.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/16/data
pg2-host=pg-standby
pg2-host-user=postgres
pg2-path=/var/lib/pgsql/16/data
[global]
process-max=2
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=zst
backup-standby=y
repo1-path=/var/lib/pgbackrest/direct
repo1-retention-full=2
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/direct.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign the profile to its service user

The executing account must own and read the profile.

On pg-primary as ec2-user.

### Assign the profile to its service user

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/direct.conf
```

chown changes owner and group, not the configuration contents.

The file belongs to postgres.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/direct.conf
```

The file belongs to postgres.

## Restrict the profile permissions

Limit configuration access to the service owner and group.

On pg-primary as ec2-user.

### Restrict the profile permissions

Use the Linux terminal.

```bash
sudo chmod 640 /etc/pgbackrest/direct.conf
```

Mode640 gives owner read/write and group read access.

The mode is640.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/direct.conf
```

The mode is640.

## Write pgbackrest.conf on pg-standby

The direct backup profile includes local primary and remote standby with a local repository. The primary archive profile includes remote repositories without remote database hosts. The backup server profile coordinates both database hosts with its local NFS mount. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-standby as ec2-user.

### Write pgbackrest.conf on pg-standby

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/pgbackrest.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/16/data
[global]
process-max=2
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=zst
repo1-host=pg-primary
repo1-host-user=postgres
repo1-path=/var/lib/pgbackrest/direct
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign the profile to its service user

The executing account must own and read the profile.

On pg-standby as ec2-user.

### Assign the profile to its service user

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
```

chown changes owner and group, not the configuration contents.

The file belongs to postgres.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The file belongs to postgres.

## Restrict the profile permissions

Limit configuration access to the service owner and group.

On pg-standby as ec2-user.

### Restrict the profile permissions

Use the Linux terminal.

```bash
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
```

Mode640 gives owner read/write and group read access.

The mode is640.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The mode is640.

## Write pgbackrest.conf on backup-1

The direct backup profile includes local primary and remote standby with a local repository. The primary archive profile includes remote repositories without remote database hosts. The backup server profile coordinates both database hosts with its local NFS mount. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Write pgbackrest.conf on backup-1

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/pgbackrest.conf.

### File contents

```text
[academy]
pg1-host=pg-primary
pg1-host-user=postgres
pg1-path=/var/lib/pgsql/16/data
pg2-host=pg-standby
pg2-host-user=postgres
pg2-path=/var/lib/pgsql/16/data
[global]
process-max=2
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=zst
backup-standby=y
repo2-path=/var/lib/pgbackrest/server
repo2-retention-full=2
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign the profile to its service user

The executing account must own and read the profile.

On backup-1 as ec2-user.

### Assign the profile to its service user

Use the Linux terminal.

```bash
sudo chown pgbackrest:pgbackrest /etc/pgbackrest/pgbackrest.conf
```

chown changes owner and group, not the configuration contents.

The file belongs to pgbackrest.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The file belongs to pgbackrest.

## Restrict the profile permissions

Limit configuration access to the service owner and group.

On backup-1 as ec2-user.

### Restrict the profile permissions

Use the Linux terminal.

```bash
sudo chmod 640 /etc/pgbackrest/pgbackrest.conf
```

Mode640 gives owner read/write and group read access.

The mode is640.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The mode is640.

## Create the direct stanza

Initialize repository metadata for the academy database identity.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Create the stanza

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/direct.conf --stanza=academy stanza-create
```

stanza-create initializes the configured repositories. It does not accept --repo and does not take a backup.

The stanza-create command completes successfully.

### Inspect stanza metadata

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/direct.conf --stanza=academy info
```

Inspect the initialized stanza. A no-valid-backups status is expected before the first backup.

academy appears, with no completed backup yet.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Create the server stanza

Initialize repository metadata for the academy database identity.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Create the stanza

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy stanza-create
```

stanza-create initializes the configured repositories. It does not accept --repo and does not take a backup.

The stanza-create command completes successfully.

### Inspect stanza metadata

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy info
```

Inspect the initialized stanza. A no-valid-backups status is expected before the first backup.

academy appears, with no completed backup yet.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Enable WAL archiving after creating the stanzas

Change archive_mode to on. PostgreSQL invokes archive_command for completed WAL segments; pgBackRest routes them to the configured repositories. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Enable WAL archiving after creating the stanzas

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/16/data/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/16/data/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/16/data'
listen_addresses = '*'
port = 5432
unix_socket_directories = '/var/run/postgresql'
wal_level = replica
max_wal_senders = 5
max_replication_slots = 5
wal_keep_size = '128MB'
max_slot_wal_keep_size = '512MB'
hot_standby = on
archive_mode = on
archive_command = 'pgbackrest --stanza=academy archive-push %p'
archive_timeout = 60
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
password_encryption = 'scram-sha-256'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql.log'
log_line_prefix = '%m [%p] '
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/16/data/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Restart PostgreSQL for archive_mode

archive_mode requires a server restart. A configuration-file edit alone does not activate it.

On pg-primary as ec2-user.

### Restart PostgreSQL for archive_mode

Use the Linux terminal.

```bash
sudo systemctl restart postgresql-16
```

Restart the primary and let the standby reconnect.

The service becomes active.

### Check

```bash
systemctl is-active postgresql-16
```

The service becomes active.

## Read the active archive mode

Read the server’s active setting after restart.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres.

Wait for postgres=#. You are now entering SQL or psql commands.

### Read the active archive mode

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW archive_mode;
```

Read the server’s active setting after restart.

on

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Prove WAL reaches the direct repository

Exercise archive delivery before relying on a backup.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Check the stanza

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy check
```

check validates configuration and required WAL delivery. Read each repository result. It does not accept --repo.

The check completes successfully and names the WAL archived to the configured repositories.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Prove WAL reaches the server repository

Exercise archive delivery before relying on a backup.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Check the stanza

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy check
```

check validates configuration and required WAL delivery. Read each repository result. It does not accept --repo.

The check completes successfully and names the WAL archived to the configured repositories.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Take a full standby backup directly to NFS

Take a full backup using the explicit executing role and repository.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Run the backup

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/direct.conf --stanza=academy --repo=1 --type=full --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --stanza=academy --repo=1 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new full backup is recorded for academy.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Take a full standby backup from the backup server

Take a full backup using the explicit executing role and repository.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 --type=full --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=2 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new full backup is recorded for academy.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated direct restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated direct restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-direct-repo1.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-direct-repo1.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-direct-repo1
[global]
log-level-console=info
process-max=2
repo1-path=/var/lib/pgbackrest/direct
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-direct-repo1.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-direct-repo1.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-direct-repo1.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-direct-repo1
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-direct-repo1
```

Only . and .. appear.

## Restore the direct backup

A successful backup becomes useful only after its data can be recovered.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Restore the files

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/restore-direct-repo1.conf --stanza=academy --repo=1 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-direct-repo1/PG_VERSION
```

Read the restored cluster’s major version. File presence does not establish recovery success.

16

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Separate the restored server from the live source

A copied postgresql.conf can still name the original data directory. Set the isolated directory and port before starting the restored copy. This copy accepts only local lab connections. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Separate the restored server from the live source

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-direct-repo1/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-direct-repo1/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-direct-repo1'
port = 55433
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-direct-repo1/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-direct-repo1/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-direct-repo1/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-direct-repo1/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated direct recovery

Start recovery and then check readiness independently.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Start the restored server

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-direct-repo1 -l /var/lib/pgsql/restore-direct-repo1/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55433
```

Check the isolated port, not live port 5432. Recovery may initially report rejecting connections. Wait a few seconds and run this same check again until it accepts connections. If rejection persists, inspect startup.log before proceeding. Readiness still does not prove the recovered records.

Continue only when the isolated port reports accepting connections.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Accept the recovered direct data

Check location, recovery state and exact records before accepting this restore.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55433
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55433.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-direct-repo1

### Confirm recovery completed

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_is_in_recovery();
```

Check whether the restored server has finished recovery.

f

### Inspect the known records

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Compare the restored rows with the backup point.

The baseline row is present as the only marker row.

### Count the payload

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_payload;
```

Check the full known dataset.

10000

### Confirm archiving stays off

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW archive_mode;
```

The isolated copy must not compete with the source archiver.

off

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-direct-repo1 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-direct-repo1/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated server restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated server restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-server-repo2.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-server-repo2.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-server-repo2
[global]
log-level-console=info
process-max=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-server-repo2.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-server-repo2.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-server-repo2.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-server-repo2
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-server-repo2
```

Only . and .. appear.

## Restore the server backup

A successful backup becomes useful only after its data can be recovered.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Restore the files

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/restore-server-repo2.conf --stanza=academy --repo=2 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-server-repo2/PG_VERSION
```

Read the restored cluster’s major version. File presence does not establish recovery success.

16

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Separate the restored server from the live source

A copied postgresql.conf can still name the original data directory. Set the isolated directory and port before starting the restored copy. This copy accepts only local lab connections. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Separate the restored server from the live source

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-server-repo2/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-server-repo2/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-server-repo2'
port = 55434
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-server-repo2/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-server-repo2/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-server-repo2/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-server-repo2/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated server recovery

Start recovery and then check readiness independently.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Start the restored server

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-server-repo2 -l /var/lib/pgsql/restore-server-repo2/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55434
```

Check the isolated port, not live port 5432. Recovery may initially report rejecting connections. Wait a few seconds and run this same check again until it accepts connections. If rejection persists, inspect startup.log before proceeding. Readiness still does not prove the recovered records.

Continue only when the isolated port reports accepting connections.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Accept the recovered server data

Check location, recovery state and exact records before accepting this restore.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55434
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55434.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-server-repo2

### Confirm recovery completed

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_is_in_recovery();
```

Check whether the restored server has finished recovery.

f

### Inspect the known records

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Compare the restored rows with the backup point.

The baseline row is present as the only marker row.

### Count the payload

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_payload;
```

Check the full known dataset.

10000

### Confirm archiving stays off

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW archive_mode;
```

The isolated copy must not compete with the source archiver.

off

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-server-repo2 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-server-repo2/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Read the assigned S3 repository identity

Terraform creates the private encrypted versioned bucket and scoped IAM access. Use this assignment’s bucket and prefix only.

On backup-1 as ec2-user.

### Read the assigned S3 repository identity

Use the Linux terminal.

```bash
cat /opt/suta/handoff/pgbackrest-s3.json
```

Read the nonsecret bucket, region and prefix staged by server management. Temporary role credentials remain outside Guide content.

The handoff names this project/run, its private bucket, us-east-1 and the assigned pgbackrest prefix.

## Add repo3 on pg-primary

Retain both NFS repositories and add S3. Only backup-1 has the scoped S3 instance role: key-type=auto obtains its temporary credentials. On pg-primary, repo3-host and repo3-host-user send repository operations through backup-1 over verified service SSH. Do not paste AWS access keys into the file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Add repo3 on pg-primary

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/pgbackrest.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/16/data
[global]
process-max=2
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=zst
repo1-path=/var/lib/pgbackrest/direct
repo1-retention-full=2
repo2-host=backup-1
repo2-host-user=pgbackrest
repo2-path=/var/lib/pgbackrest/server
repo2-retention-full=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
repo3-host=backup-1
repo3-host-user=pgbackrest
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Add repo3 on backup-1

Retain both NFS repositories and add S3. Only backup-1 has the scoped S3 instance role: key-type=auto obtains its temporary credentials. On pg-primary, repo3-host and repo3-host-user send repository operations through backup-1 over verified service SSH. Do not paste AWS access keys into the file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On backup-1 as ec2-user.

### Add repo3 on backup-1

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/pgbackrest.conf.

### File contents

```text
[academy]
pg1-host=pg-primary
pg1-host-user=postgres
pg1-path=/var/lib/pgsql/16/data
pg2-host=pg-standby
pg2-host-user=postgres
pg2-path=/var/lib/pgsql/16/data
[global]
process-max=2
start-fast=y
archive-timeout=60
log-level-console=info
log-level-file=detail
compress-type=zst
backup-standby=y
repo2-path=/var/lib/pgbackrest/server
repo2-retention-full=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/pgbackrest.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Initialize the S3 stanza

Initialize the newly configured repository without selecting an unsupported --repo option.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Create the configured stanzas

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy stanza-create
```

Existing stanzas are checked and the new S3 stanza is initialized.

The command completes successfully.

### Check WAL delivery

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy check
```

Check every configured repository and read the repo3 result.

WAL reaches S3 successfully.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Take a full standby backup to S3

Take a full backup using the explicit executing role and repository.

On backup-1 as ec2-user.

### Switch to the pgbackrest user

Start in the Linux terminal on backup-1, as ec2-user.

```bash
sudo -iu pgbackrest
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying pgbackrest on backup-1.

### Run the backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=3 --type=full --backup-standby=y --log-level-console=detail backup
```

The repository number chooses the destination. The type chooses the backup chain. backup-standby=y requires a standby and waits for its replay while the primary coordinates consistency.

The command completes successfully. For standby backups, the detail output names backup file pg-standby and the replay wait.

### Inspect the recorded backup

Type this in the pgbackrest Linux shell on backup-1.

```bash
pgbackrest --stanza=academy --repo=3 info
```

Read the actual recorded type, label, timestamps, sizes and WAL range. This does not yet prove restoration.

A new full backup is recorded for academy.

### Return to ec2-user

Type this in the pgbackrest Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Write the isolated s3 restore profile

The restore profile points at a separate data directory. Keep the live source path out of this profile. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Write the isolated s3 restore profile

Use the Linux terminal.

```bash
sudo vi /etc/pgbackrest/restore-s3-repo3.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /etc/pgbackrest/restore-s3-repo3.conf.

### File contents

```text
[academy]
pg1-path=/var/lib/pgsql/restore-s3-repo3
[global]
log-level-console=info
process-max=2
repo3-type=s3
repo3-path={{s3_prefix}}
repo3-s3-bucket={{s3_bucket}}
repo3-s3-endpoint=s3.us-east-1.amazonaws.com
repo3-s3-region=us-east-1
repo3-s3-key-type=auto
repo3-retention-full=2
repo3-host=backup-1
repo3-host-user=pgbackrest
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-s3-repo3.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Assign restore-profile ownership

postgres runs this restore.

On pg-primary as ec2-user.

### Assign restore-profile ownership

Use the Linux terminal.

```bash
sudo chown postgres:postgres /etc/pgbackrest/restore-s3-repo3.conf
```

Set the file’s owner and group.

postgres owns the profile.

### Check

```bash
sudo stat -c "%U:%G %a %n" /etc/pgbackrest/restore-s3-repo3.conf
```

postgres owns the profile.

## Prepare the isolated restore destination

Use a new empty directory for this exercise. Never restore over the running source.

On pg-primary as ec2-user.

### Prepare the isolated restore destination

Use the Linux terminal.

```bash
sudo install -d -m 700 -o postgres -g postgres /var/lib/pgsql/restore-s3-repo3
```

Create the destination with postgres ownership and private permissions. If a prior drill exists here, preserve it under a new name before restarting this exercise.

The new destination is empty.

### Check

```bash
sudo ls -la /var/lib/pgsql/restore-s3-repo3
```

Only . and .. appear.

## Restore the s3 backup

A successful backup becomes useful only after its data can be recovered.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Restore the files

Type this in the postgres Linux shell on pg-primary.

```bash
pgbackrest --config=/etc/pgbackrest/restore-s3-repo3.conf --stanza=academy --repo=3 --archive-mode=off --type=immediate --target-action=promote restore
```

Restore the latest backup selected by this exercise and replay its required WAL to its first consistent point. Inspect info before restoring; use the backup just created by this exercise. Archiving is disabled for the isolated copy.

The restore command completes. PostgreSQL has not started yet.

### Inspect the restored version file

Type this in the postgres Linux shell on pg-primary.

```bash
cat /var/lib/pgsql/restore-s3-repo3/PG_VERSION
```

Read the restored cluster’s major version. File presence does not establish recovery success.

16

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Separate the restored server from the live source

A copied postgresql.conf can still name the original data directory. Set the isolated directory and port before starting the restored copy. This copy accepts only local lab connections. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Separate the restored server from the live source

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-s3-repo3/postgresql.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-s3-repo3/postgresql.conf.

### File contents

```text
data_directory = '/var/lib/pgsql/restore-s3-repo3'
port = 55435
listen_addresses = '127.0.0.1'
unix_socket_directories = '/var/run/postgresql'
archive_mode = off
hot_standby = off
ssl = off
logging_collector = off
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-s3-repo3/postgresql.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Limit access to the isolated restore

Allow only the local postgres account to inspect the isolated recovery. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents.

On pg-primary as ec2-user.

### Limit access to the isolated restore

Use the Linux terminal.

```bash
sudo vi /var/lib/pgsql/restore-s3-repo3/pg_hba.conf
```

vi opens this exact file. Use the supplied complete contents for this file. In vi, press Escape, type :%d and Enter to clear the existing buffer, then press i and paste the contents. After editing, press Escape, type :wq and press Enter to save and return to Linux.

The editor closes and the file is saved at /var/lib/pgsql/restore-s3-repo3/pg_hba.conf.

### File contents

```text
local all postgres peer
```

### Check

```bash
sudo stat -c "%U:%G %a %n" /var/lib/pgsql/restore-s3-repo3/pg_hba.conf
```

The exact file path is present. The following service checks establish whether its settings work.

## Start the isolated s3 recovery

Start recovery and then check readiness independently.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Start the restored server

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-s3-repo3 -l /var/lib/pgsql/restore-s3-repo3/startup.log -t 40 -w start
```

Use the isolated data directory and retain its recovery startup log.

The server starts or explains why recovery failed.

### Check connection readiness

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_isready -h /var/run/postgresql -p 55435
```

Check the isolated port, not live port 5432. Recovery may initially report rejecting connections. Wait a few seconds and run this same check again until it accepts connections. If rejection persists, inspect startup.log before proceeding. Readiness still does not prove the recovered records.

Continue only when the isolated port reports accepting connections.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Accept the recovered s3 data

Check location, recovery state and exact records before accepting this restore.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Connect to PostgreSQL

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/psql -X -h /var/run/postgresql -d postgres -p 55435
```

The path selects the PostgreSQL16 client. -X ignores personal startup files, -h selects the local socket, -d selects postgres, and -p selects the isolated restore on port55435.

Wait for postgres=#. You are now entering SQL or psql commands.

### Confirm the isolated directory

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW data_directory;
```

Read the directory of the connected server.

/var/lib/pgsql/restore-s3-repo3

### Confirm recovery completed

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT pg_is_in_recovery();
```

Check whether the restored server has finished recovery.

f

### Inspect the known records

Type this at postgres=#. Do not type the prompt itself.

```sql
TABLE academy_proof;
```

Compare the restored rows with the backup point.

The baseline row is present as the only marker row.

### Count the payload

Type this at postgres=#. Do not type the prompt itself.

```sql
SELECT count(*) FROM academy_payload;
```

Check the full known dataset.

10000

### Confirm archiving stays off

Type this at postgres=#. Do not type the prompt itself.

```sql
SHOW archive_mode;
```

The isolated copy must not compete with the source archiver.

off

### Leave PostgreSQL

After reading the result, type this at postgres=#.

```text
\q
```

Close the database client.

You return to the postgres Linux shell.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.

## Stop the accepted isolated restore

Free the isolated port after recording the result; retain the data and startup log.

On pg-primary as ec2-user.

### Switch to the postgres user

Start in the Linux terminal on pg-primary, as ec2-user.

```bash
sudo -iu postgres
```

sudo -i opens a login shell. -u selects the operating-system account that owns this work.

Wait for a shell prompt identifying postgres on pg-primary.

### Stop the isolated copy

Type this in the postgres Linux shell on pg-primary.

```bash
/usr/pgsql-16/bin/pg_ctl -D /var/lib/pgsql/restore-s3-repo3 -m fast -w stop
```

Stop only the restored copy at this directory.

The isolated server stops.

### Read its last startup messages

Type this in the postgres Linux shell on pg-primary.

```bash
tail -n 20 /var/lib/pgsql/restore-s3-repo3/startup.log
```

Read timestamps and process IDs. A readiness probe during recovery may have logged FATAL for that rejected connection. Compare it with the later recovery-complete, ready and clean-shutdown messages and the accepted SQL data; severity alone does not describe the current outcome.

The isolated server reports shutdown after accepted recovery; the source remains a separate service.

### Return to ec2-user

Type this in the postgres Linux shell.

```bash
exit
```

Close the nested service-account shell.

The prompt identifies ec2-user again.
