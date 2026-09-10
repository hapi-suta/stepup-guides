# Observe failure and recovery

[Classroom home](README.md) · [Previous: planned switchover](07-switchover.md) · [Read logs](08-troubleshooting.md)

Run these exercises only on the assigned practice cluster. Complete one exercise, recover all three members, and verify the app before starting the next one.

## Before each experiment

1. Open the app. Post a message identifying the experiment and reload it.
2. Keep that browser open. Attempt another message during the disruption and note any error or delay.
3. In a surviving PostgreSQL server's terminal, switch to postgres:

```bash
sudo -iu postgres
```

```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```

Record the current **Leader**. Do not assume it is still pg-ha-1 after a previous exercise. Confirm the other two nodes are streaming.

```bash
exit
```

Record: old leader, new leader, time disruption began, first successful new app write, and whether the original message remains. A failed request can have an uncertain outcome; check for the message before blindly retrying it.

## Exercise A — PostgreSQL stops while Patroni remains running

**Target: the current Leader only. Start as ec2-user in its Linux terminal.**

```bash
sudo -iu postgres
```

```bash
/opt/pgsql/bin/pg_ctl -D /opt/pgsql/data stop -m immediate
```

This is an intentional database crash for the lab. Immediate shutdown skips a clean database shutdown; PostgreSQL must perform crash recovery. Patroni remains active and can restart it. Do not run this command on all three nodes.

```bash
exit
```

From the surviving observer terminal:

```bash
sudo -iu postgres
```

```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```

Repeat the list command while it recovers. A database crash does not necessarily cause a promotion: Patroni may restart the same writer before it needs to fail over. Record which outcome occurs.

```bash
exit
```

On the affected node, read the recovery sequence:

```bash
sudo journalctl -u patroni -n 80 --no-pager
```

**Finish:** one running leader, two streaming replicas, a new app message saves, and the earlier message survives a browser reload.

## Exercise B — the writer's entire server becomes unavailable

**Instructor action: use the AWS CLI session for the class account. Students observe from a different server.**

First identify the current leader again. Map that role to its EC2 instance ID in the instructor's inventory. Replace `WRITER_INSTANCE_ID` below with that exact ID.

```bash
aws sts get-caller-identity
```

Confirm this is the intended lab account.

```bash
aws ec2 describe-instances --region us-east-1 --instance-ids WRITER_INSTANCE_ID --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Tags:Tags}'
```

Confirm the role and ownership tags. Never select the control plane, router, app server or another student's instance.

```bash
aws ec2 stop-instances --region us-east-1 --instance-ids WRITER_INSTANCE_ID
```

Stopping the instance makes both Patroni and PostgreSQL unavailable. This is a whole-node availability exercise, not a network-partition or power-loss simulation.

On the surviving observer, switch to postgres and inspect membership:

```bash
sudo -iu postgres
```

```bash
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```

Repeat until a different node is Leader. Meanwhile, try saving messages in the app. Expect possible failed requests or delays during detection and reconnection; measure them.

```bash
exit
```

Once promotion and an app write have been observed, the instructor starts the original instance:

```bash
aws ec2 start-instances --region us-east-1 --instance-ids WRITER_INSTANCE_ID
```

Wait for the server to boot. Inspect membership again from the surviving observer. The returned node must rejoin as a streaming replica; do not manually initialize it or force it to become primary.

**Finish:** one running leader, two streaming replicas, app writes succeed through the unchanged router, and previously saved messages remain readable.

## Exercise C — stop the Patroni service

Identify the current leader again. On that server as ec2-user:

```bash
sudo systemctl stop patroni
```

This is a controlled service stop. With this unit, stopping Patroni also affects its managed PostgreSQL processes. It is not equivalent to killing only the Patroni process and leaving PostgreSQL running.

Observe membership from another node and try the app. Record whether leadership moves and how requests behave.

Restore the stopped service on the original node:

```bash
sudo systemctl start patroni
```

```bash
sudo journalctl -u patroni -n 80 --no-pager
```

Wait for all three members to recover before ending the exercise.

## Recheck the reader endpoint

On a PostgreSQL server as ec2-user:

```bash
/opt/pgsql/bin/psql -h db-router-1 -p 5433 -U mattermost -d mattermost
```

Enter the database password. At the database prompt:

```sql
SELECT inet_server_addr(), pg_is_in_recovery();
```

Expect a current standby and `t`. A promoted node must no longer be eligible for new reader connections.

```text
\q
```

## What these exercises prove

They demonstrate recovery for the specific failures you injected and the messages you checked. This asynchronous cluster does not guarantee zero data loss for every failure. A successful ping does not prove that writes work, and a successful write does not prove every earlier message survived. Check all three separately.
