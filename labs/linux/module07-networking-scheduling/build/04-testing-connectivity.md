# Build 04: Testing Connectivity

You will learn how to test whether one machine can reach another. You will test
whether a specific port is open. You will also learn to tell "connection refused"
apart from "timed out". These two error messages point at completely different
problems. Knowing which one you have cuts your troubleshooting time in half.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. ping - Is the host reachable at all?

`ping` sends small test packets to a host and waits for a reply. It answers the
most basic question. Can this server reach that host on the network?

```bash
ping -c 4 8.8.8.8
```

- `ping` - send test packets
- `-c 4` - send 4 packets then stop (without `-c`, ping runs forever until you
  press `Ctrl+C`)
- `8.8.8.8` - a public Google DNS server, handy for testing internet reachability

```
Expected output (yours will differ):
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=115 time=1.42 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=115 time=1.39 ms
...
4 packets transmitted, 4 received, 0% packet loss, time 3005ms
```

`0% packet loss` means every packet got a reply. The host is reachable. If you
see `100% packet loss`, the host did not answer.

> **Concept - Ping Can Lie:** A good ping proves the network path works. But a
> failed ping does not always mean the host is down. Many servers and firewalls
> block ping (ICMP) on purpose while still taking real traffic on ports like
> 5432. So ping is a good first test. But never decide "the database is down"
> from a failed ping alone. Test the actual port instead.

---

## 2. nc -zv - Test a specific port

`nc` (netcat) tests whether a specific port on a host is open and taking
connections. This is the most useful connectivity test for a DBA. It tests the
exact port the database uses.

`nc` is not installed by default on a minimal CentOS Stream 9. Install it first:

```bash
sudo dnf install -y nmap-ncat
```

- `nmap-ncat` is the package that provides the `nc` command.

Test whether SSH is reachable on the loopback. Port 22 is always listening on
this server, so it makes a reliable "open port" example:

```bash
nc -zv 127.0.0.1 22
```

- `nc` - netcat, the network Swiss Army knife
- `-z` - zero-I/O mode: just check if the port is open, do not send data
- `-v` - verbose: print the result in plain words
- `127.0.0.1` - the host to test
- `22` - the port to test

```
Expected output (yours will differ):
Ncat: Version 7.92 ( https://nmap.org/ncat )
Ncat: Connected to 127.0.0.1:22.
Ncat: 0 bytes sent, 0 bytes received in 0.01 seconds.
```

`Connected to 127.0.0.1:22` means the port is open and something is listening.
That "something" is the SSH daemon. Once PostgreSQL is installed and running, the
same command against port `5432` returns the same `Connected` result.

Now test a port that is not open to see the failure. PostgreSQL is not installed
yet, so port `5432` is a good example of a closed port:

```bash
nc -zv 127.0.0.1 5432
```

```
Expected output (yours will differ):
Ncat: Version 7.92 ( https://nmap.org/ncat )
Ncat: Connection refused.
```

`Connection refused` means the host answered, but nothing is listening on that
port.

> **DBA Context - Test From the Client Side:** The real power of `nc` shows when
> you run it from the client machine that cannot connect. Say the app server runs
> `nc -zv db-server 5432` and gets "Connected". Then the network and firewall are
> fine, and the problem is inside PostgreSQL (auth or config). If it gets
> "refused" or "timed out", the problem is the network path or the database
> server. This one test tells you which side to investigate.

---

## 3. connection refused vs timed out - The most important distinction

The two failure messages mean very different things. Memorize this.

### Connection refused

The target host is up and reachable. But nothing is listening on that port. (Or
the firewall is actively rejecting it.) The reply comes back fast.

Causes to check:

- PostgreSQL is not running
- PostgreSQL is listening on `127.0.0.1` only, not on a reachable address
- The firewall is set to reject (not drop) the port

### Connection timed out

No reply came back at all. The packets vanished into nothing. This takes several
seconds. The client waits and retries before it gives up.

Causes to check:

- The firewall is dropping the packets silently (a common firewall default)
- A security group or network ACL is blocking the port (common in AWS)
- The host is down or the IP is wrong
- There is no network route to the host

> **DBA Context - The Fast Diagnosis:** "Refused" means you reached the server,
> but the door was shut in your face. Look at the database and its local
> firewall. "Timed out" means your knock was never answered. Look at the network,
> security groups, and routing between the machines. In AWS, "timed out" almost
> always points at a security group that does not allow port 5432. Knowing which
> message you have tells you where to look before you touch anything.

---

## 4. curl - Test an HTTP or full endpoint

`curl` makes a real request to a service. For databases you mostly use `nc`. But
`curl` is key for testing HTTP-based services. Think monitoring endpoints, health
checks, and cloud metadata.

Test the AWS instance metadata service (a handy internal endpoint):

```bash
curl -s http://169.254.169.254/latest/meta-data/local-ipv4
```

- `curl` - make a request to a URL
- `-s` - silent: hide the progress meter
- The URL is the AWS metadata service, which returns the instance's private IP

```
Expected output (yours will differ):
10.0.1.50
```

To test whether a web service is responding and see just the status code:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:80
```

- `-o /dev/null` - throw away the page body
- `-w "%{http_code}\n"` - print only the HTTP status code, then a newline

```
Expected output (yours will differ):
000
```

A code of `000` here means nothing is listening on port 80. That is expected on a
plain database server. A `200` would mean a healthy web response.

> **DBA Context - Health Checks:** Cloud load balancers and monitoring tools use
> HTTP health checks. Say PostgreSQL sits behind a proxy like PgBouncer, or a
> connection pooler that shows an HTTP status page. Then `curl` is how you confirm
> the health endpoint is alive. It is also how you test that a metrics exporter
> (for Prometheus) is responding.

---

## 5. A practical connectivity workflow

Put the tools in order. When someone reports "the app cannot connect to the
database", run these from the client side, in this order.

1. `ping db-server` - is the host reachable on the network at all?
2. `nc -zv db-server 5432` - is the database port open?
3. Read the result:
   - **Connected** - network and firewall are fine, investigate PostgreSQL auth
   - **Refused** - reached the host, but the port is closed; check the service
     and local firewall on the database server
   - **Timed out** - never reached the port; check security groups, network ACLs,
     and routing

This three-step flow turns a vague complaint into one clear place to look.

> **DBA Context - Work the Layers:** Solve networking problems layer by layer,
> from the outside in. First confirm the host is reachable. Then the port. Then
> the database itself. Jumping straight to `postgresql.conf` when the real
> problem is a security group wastes hours. Test connectivity first.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Use `ping -c 4` to test whether a host is reachable
- [ ] Explain why a failed ping does not prove the database is down
- [ ] Use `nc -zv host port` to test whether a specific port is open
- [ ] Explain the difference between "connection refused" and "connection timed out"
- [ ] List the likely causes of each failure message
- [ ] Use `curl` to test an HTTP endpoint and read the status code
- [ ] Describe the three-step connectivity workflow for a "cannot connect" report
