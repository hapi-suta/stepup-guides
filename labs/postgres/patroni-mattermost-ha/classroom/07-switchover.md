# Practice a planned switchover

[Classroom home](README.md) · [Previous](06-verify.md) · [Next](08-troubleshooting.md)

## PART 3 — OPTIONAL PLANNED SWITCHOVER

Only proceed when all three members are healthy and pg-ha-1 is the current leader.
This interrupts existing database sessions; the application must reconnect.


## 21. Perform a planned Patroni switchover

**SERVER: pg-ha-1 | START AS: ec2-user in Linux**


Maintenance requires moving leadership without pretending an outage occurred.

Switch to the postgres user
Start in the Linux terminal on pg-ha-1, as ec2-user.

```bash
sudo -iu postgres
```


sudo selects another operating-system user. -i opens a login shell; -u postgres chooses the postgres account.
Expected: The prompt should identify postgres: [postgres@pg-ha-1 ~]$.

Move leadership to pg-ha-2
Type this in the postgres Linux shell.

```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml switchover --leader pg-ha-1 --candidate pg-ha-2 --force
```


Request a planned leadership change from pg-ha-1 to pg-ha-2. --force confirms the request without another question. Confirm the candidate is streaming before running it.
Expected: pg-ha-2 is leader, the former leader rejoins as streaming replica, and the application route is unchanged.

Check the cluster topology
On pg-ha-1, type this in the postgres Linux shell.

```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```


patronictl list shows the cluster from the DCS point of view: who leads, who streams, and each member's lag. A switchover is only done when the candidate is Leader and the old leader is back as a streaming Replica.
Expected: pg-ha-2 in the Leader role and every other member as Replica with state streaming

Return to your original user
Type this in the postgres Linux shell.

```bash
exit
```


Close the nested shell before the next lesson.
Expected: The prompt should identify ec2-user again.

Instructor: on mattermost-1, check the application again:

```bash
curl -fsS http://127.0.0.1:8065/api/v4/system/ping
```


Reload the browser, confirm the earlier message remains and post a second one.
The app database hostname must still be db-router-1. If you changed it to the new
leader manually, you have not demonstrated automatic routing.

### Checkpoint

- [ ] pg-ha-2 is Leader, the other nodes stream, and the app works through the same router endpoint.

[Classroom home](README.md) · [Previous](06-verify.md) · [Next](08-troubleshooting.md)
