# Build 01: IP Addresses and Hostnames

You will learn how to find your server's IP addresses. You will see how it routes
traffic. You will also check and set its hostname. Knowing where your server sits
on the network is the first step in solving any "the app cannot connect to the
database" problem.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. What is an IP address?

Every server on a network has one or more IP addresses. An IP address is like a
street address. It tells other machines where to send data. A database no one can
reach is useless. So a DBA needs to know exactly which addresses their server
answers on.

You will see two kinds all the time:

- **Private IP** - used inside a network (for example `10.0.1.50`). AWS gives every instance a private IP. Other machines in the same network use it to reach the server
- **Public IP** - reachable from the internet. Not every server has one

> **Concept - localhost and 127.0.0.1:** Every Linux server also has a special
> address called the loopback: `127.0.0.1`, also named `localhost`. It always
> points back to the same machine. When PostgreSQL listens on `127.0.0.1`, only
> programs on that same server can connect. This matters a lot for databases. You
> will see it again in the next guide.

---

## 2. ip addr - Show your addresses

The `ip addr` command lists every network interface and its addresses.

```bash
ip addr
```

- `ip` - the modern Linux networking command (it replaced the older `ifconfig`)
- `addr` - the subcommand that shows address information

```
Expected output (yours will differ):
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    inet 127.0.0.1/8 scope host lo
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq state UP group default qlen 1000
    link/ether 02:70:70:f4:3f:75 brd ff:ff:ff:ff:ff:ff
    inet 172.31.6.0/20 brd 172.31.15.255 scope global dynamic noprefixroute eth0
       valid_lft 3537sec preferred_lft 3537sec
    ...
```

Read this output carefully:

- `lo` is the loopback interface. Its address is always `127.0.0.1`
- `eth0` is the real network interface. Its address here is `172.31.6.0` - that is your server's private IP (your interface may instead be named `ens5` or `enX0` depending on the instance type)
- `/20` is the subnet mask in shorthand. It describes how big the local network is

To see just the addresses without the extra detail:

```bash
ip -brief addr
```

The `-brief` flag prints one short line per interface. It is much easier to scan.

```
Expected output (yours will differ):
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0             UP             172.31.6.0/20 fe80::70:70ff:fef4:3f75/64
```

---

## 3. ip route - How traffic leaves the server

The `ip route` command shows the routing table - the rules that decide where
outgoing traffic goes.

```bash
ip route
```

```
Expected output (yours will differ):
default via 172.31.0.1 dev eth0 proto dhcp src 172.31.6.0 metric 100
172.31.0.0/20 dev eth0 proto kernel scope link src 172.31.6.0 metric 100
```

- The `default via 172.31.0.1` line is the **default gateway** - traffic to any
  address not on the local network goes here first. This is your door to the
  rest of the network and the internet
- The second line says traffic for the `172.31.0.0/20` network stays local and
  does not need the gateway

> **DBA Context - No Route, No Connection:** If a server has no default gateway,
> it can talk to machines on its own subnet. But it cannot reach anything beyond
> it. This often causes "the backup cannot upload to S3" or "replication cannot
> reach the primary". The route is missing. `ip route` is one of the first things
> to check.

---

## 4. hostname - Your server's name

The `hostname` command prints the server's name.

```bash
hostname
```

```
Expected output (yours will differ):
ip-172-31-6-0.ec2.internal
```

A fresh AWS instance is named after its private IP by default. To see the fully
qualified domain name (the short name plus its domain):

```bash
hostname -f
```

The `-f` flag means "fully qualified". If no domain is set, it returns the same
short name.

```
Expected output (yours will differ):
ip-172-31-6-0.ec2.internal
```

To see the server's IP addresses through the hostname tool:

```bash
hostname -I
```

The `-I` flag (capital i) prints all IP addresses assigned to the server,
separated by spaces. This is a quick way to get just the addresses.

```
Expected output (yours will differ):
172.31.6.0
```

---

## 5. hostnamectl - The full picture and how to change the name

`hostnamectl` shows detailed system identity information and is the correct way
to change the hostname permanently on CentOS.

```bash
hostnamectl
```

```
Expected output (yours will differ):
 Static hostname: ip-172-31-15-74.ec2.internal
       Icon name: computer-vm
         Chassis: vm
      Machine ID: ec27b476a7cb1ab2aa8ccd896132b0cb
         Boot ID: 5a4a0724775d42e49f227e84f831ecc7
  Virtualization: amazon
Operating System: CentOS Stream 9
          Kernel: Linux 5.14.0-721.el9.x86_64
    Architecture: x86-64
    ...
```

To change the hostname, use `set-hostname`. This needs `sudo` because it changes
a system-wide setting:

```bash
sudo hostnamectl set-hostname pg-primary
```

- `sudo` - run as administrator, required to change system identity
- `set-hostname pg-primary` - set the static hostname to `pg-primary`

Nothing prints on success. Confirm the change:

```bash
hostname
```

```
Expected output (yours will differ):
pg-primary
```

Your shell prompt will show the new name the next time you log in.

> **DBA Context - Hostnames in Replication:** In a PostgreSQL replication setup
> you often call servers by name (`pg-primary`, `pg-standby`) instead of by IP.
> That is because IPs can change. Clear, consistent hostnames make setup and
> troubleshooting much easier. You will set hostnames like this when you build a
> replication lab later in the course.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain the difference between a private IP, a public IP, and `127.0.0.1`
- [ ] Run `ip addr` and identify the loopback and the real interface
- [ ] Use `ip -brief addr` for a quick summary
- [ ] Run `ip route` and identify the default gateway
- [ ] Run `hostname` and `hostname -I` to see the name and addresses
- [ ] Run `hostnamectl` to see the full system identity
- [ ] Change the hostname with `sudo hostnamectl set-hostname`
