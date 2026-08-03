# BUILD 06: Runbook Automation

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 60-75 minutes
**Level:** Intermediate

---

## Objective

Automate common incident response runbooks using AWS Systems Manager (SSM), Lambda, and EventBridge. By the end of this guide, you will have automated responses for three incident types: connection storms, storage exhaustion alerts, and replication lag spikes.

---

## Prerequisites

- Aurora PostgreSQL cluster `devops-lab-cluster` running
- AWS CLI configured with appropriate permissions
- Lambda IAM role from BUILD 03 (`devops-lab-lambda-dba-role`)
- Secrets Manager secret from BUILD 03 (`devops-lab-cluster/dba-monitor`)

---

## Section 1: The Runbook Automation Pattern

Manual runbooks are the starting point. Once a runbook is proven through repeated use, automate it. The automation pattern is:

```
CloudWatch Alarm fires
    |
    v
EventBridge Rule matches the alarm
    |
    v
Lambda function executes the runbook steps
    |
    v
SNS notification sent to on-call DBA
    |
    v
Results logged to CloudWatch Logs
```

The DBA still reviews the results. Automation handles the first 5 minutes of diagnosis so the on-call engineer wakes up to an analysis, not a raw alert.

---

## Section 2: Create the SNS Topic for Notifications

### 2.1 Create the Topic

```bash
aws sns create-topic \
    --name devops-lab-dba-alerts \
    --tags Key=Environment,Value=production Key=Team,Value=platform
```

Expected output (yours will differ):
```json
{
    "TopicArn": "arn:aws:sns:us-east-1:123456789012:devops-lab-dba-alerts"
}
```

Save the TopicArn - you will use it in the Lambda functions.

### 2.2 Subscribe to the Topic

```bash
aws sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:123456789012:devops-lab-dba-alerts \
    --protocol email \
    --notification-endpoint your-email@example.com
```

Replace `your-email@example.com` with your actual email address.

You will receive a confirmation email. Click the confirmation link before the subscription becomes active.

---

## Section 3: Runbook 1 - Connection Storm Response

A connection storm happens when the application opens more connections than the database can handle. Common causes: missing connection pooler, application restart reconnect flood, or a connection leak.

### 3.1 Create the Lambda Function

```bash
mkdir -p ~/sre-practice/lambda/connection-storm
```

```bash
vi ~/sre-practice/lambda/connection-storm/lambda_function.py
```

```python
"""
Connection Storm Runbook Automation
Triggered by CloudWatch alarm when DatabaseConnections exceeds threshold.
Actions:
1. Diagnose connection sources
2. Identify idle-in-transaction sessions
3. Kill sessions exceeding idle timeout
4. Send detailed report to DBA team
"""

import json
import os
import boto3
import psycopg2

secrets_client = boto3.client('secretsmanager')
sns_client = boto3.client('sns')
cloudwatch_client = boto3.client('cloudwatch')


def get_db_credentials():
    """Retrieve database credentials from Secrets Manager."""
    secret_name = os.environ['DB_SECRET_NAME']
    response = secrets_client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])


def diagnose_connections(conn):
    """Get connection breakdown by source, state, and user."""
    cursor = conn.cursor()

    # Connection count by state
    cursor.execute("""
        SELECT
            state,
            count(*) AS count
        FROM pg_stat_activity
        WHERE backend_type = 'client backend'
        GROUP BY state
        ORDER BY count DESC;
    """)
    by_state = cursor.fetchall()

    # Connection count by user
    cursor.execute("""
        SELECT
            usename,
            count(*) AS count
        FROM pg_stat_activity
        WHERE backend_type = 'client backend'
        GROUP BY usename
        ORDER BY count DESC
        LIMIT 10;
    """)
    by_user = cursor.fetchall()

    # Connection count by client address
    cursor.execute("""
        SELECT
            client_addr,
            count(*) AS count
        FROM pg_stat_activity
        WHERE backend_type = 'client backend'
          AND client_addr IS NOT NULL
        GROUP BY client_addr
        ORDER BY count DESC
        LIMIT 10;
    """)
    by_client = cursor.fetchall()

    # Idle-in-transaction sessions older than 5 minutes
    cursor.execute("""
        SELECT
            pid,
            usename,
            datname,
            client_addr,
            state,
            left(query, 100) AS query,
            round(extract(epoch FROM now() - state_change)::numeric, 0)
                AS idle_seconds
        FROM pg_stat_activity
        WHERE state = 'idle in transaction'
          AND extract(epoch FROM now() - state_change) > 300
          AND backend_type = 'client backend'
        ORDER BY state_change ASC;
    """)
    idle_in_txn = cursor.fetchall()

    # Max connections setting
    cursor.execute("SELECT current_setting('max_connections')::int;")
    max_conn = cursor.fetchone()[0]

    cursor.close()
    return {
        'by_state': by_state,
        'by_user': by_user,
        'by_client': by_client,
        'idle_in_txn': idle_in_txn,
        'max_connections': max_conn
    }


def kill_idle_in_transaction(conn, max_idle_seconds=300):
    """Terminate sessions that have been idle in transaction too long."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            pg_terminate_backend(pid),
            pid,
            usename,
            datname,
            round(extract(epoch FROM now() - state_change)::numeric, 0)
                AS idle_seconds
        FROM pg_stat_activity
        WHERE state = 'idle in transaction'
          AND extract(epoch FROM now() - state_change) > %s
          AND backend_type = 'client backend'
          AND pid != pg_backend_pid();
    """, (max_idle_seconds,))
    killed = cursor.fetchall()
    conn.commit()
    cursor.close()
    return killed


def build_report(diagnosis, killed_sessions):
    """Build a human-readable incident report."""
    total_connections = sum(count for _, count in diagnosis['by_state'])
    utilization = round(total_connections / diagnosis['max_connections'] * 100, 1)

    report = []
    report.append("CONNECTION STORM RUNBOOK - AUTOMATED DIAGNOSIS")
    report.append("=" * 50)
    report.append("")
    report.append(f"Total connections: {total_connections} / "
                  f"{diagnosis['max_connections']} ({utilization}%)")
    report.append("")

    report.append("CONNECTIONS BY STATE:")
    for state, count in diagnosis['by_state']:
        report.append(f"  {state or 'NULL'}: {count}")

    report.append("")
    report.append("TOP USERS:")
    for user, count in diagnosis['by_user']:
        report.append(f"  {user}: {count}")

    report.append("")
    report.append("TOP CLIENT ADDRESSES:")
    for addr, count in diagnosis['by_client']:
        report.append(f"  {addr}: {count}")

    if killed_sessions:
        report.append("")
        report.append(f"AUTOMATED ACTION: Terminated {len(killed_sessions)} "
                      "idle-in-transaction sessions (> 5 minutes)")
        for _, pid, user, db, idle_s in killed_sessions:
            report.append(f"  PID {pid}: user={user}, db={db}, "
                          f"idle={idle_s}s")
    else:
        report.append("")
        report.append("AUTOMATED ACTION: No idle-in-transaction sessions "
                      "to terminate")

    if utilization > 80:
        report.append("")
        report.append("RECOMMENDATION: Connection utilization is critical. "
                      "Consider adding a connection pooler (PgBouncer/RDS Proxy).")

    return "\n".join(report)


def lambda_handler(event, context):
    """Main handler - triggered by CloudWatch alarm via EventBridge."""
    print(f"Connection storm runbook triggered. Event: {json.dumps(event)}")

    creds = get_db_credentials()
    conn = psycopg2.connect(
        host=creds['host'],
        port=int(creds['port']),
        user=creds['username'],
        password=creds['password'],
        dbname=creds['dbname'],
        connect_timeout=5
    )

    try:
        diagnosis = diagnose_connections(conn)
        killed = kill_idle_in_transaction(conn, max_idle_seconds=300)
        report = build_report(diagnosis, killed)

        print(report)

        sns_topic = os.environ.get('SNS_TOPIC_ARN')
        if sns_topic:
            sns_client.publish(
                TopicArn=sns_topic,
                Subject="Connection Storm Alert - devops-lab-cluster",
                Message=report
            )

        # Publish custom metric for tracking
        total = sum(count for _, count in diagnosis['by_state'])
        cloudwatch_client.put_metric_data(
            Namespace='DBA/Aurora',
            MetricData=[{
                'MetricName': 'ConnectionStormKilled',
                'Value': len(killed),
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'ClusterIdentifier',
                     'Value': 'devops-lab-cluster'}
                ]
            }]
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'total_connections': total,
                'killed_sessions': len(killed),
                'utilization_pct': round(
                    total / diagnosis['max_connections'] * 100, 1)
            })
        }

    finally:
        conn.close()
```

Save and exit vi (`:wq`).

### 3.2 Package and Deploy

```bash
cd ~/sre-practice/lambda/connection-storm
```

```bash
cp ../health-check/requirements.txt .
```

```bash
pip install -r requirements.txt -t ./package
```

```bash
cd package && zip -r ../connection-storm.zip . && cd ..
```

```bash
zip connection-storm.zip lambda_function.py
```

```bash
aws lambda create-function \
    --function-name devops-lab-connection-storm \
    --runtime python3.12 \
    --role arn:aws:iam::123456789012:role/devops-lab-lambda-dba-role \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://connection-storm.zip \
    --timeout 60 \
    --memory-size 256 \
    --vpc-config SubnetIds=subnet-xxxxxxxxx,subnet-yyyyyyyyy,SecurityGroupIds=sg-zzzzzzzzz \
    --environment "Variables={DB_SECRET_NAME=devops-lab-cluster/dba-monitor,SNS_TOPIC_ARN=arn:aws:sns:us-east-1:123456789012:devops-lab-dba-alerts}"
```

Replace the subnet IDs, security group ID, and SNS topic ARN with your actual values.

### 3.3 Create the CloudWatch Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "devops-lab-connection-storm" \
    --alarm-description "Connection count exceeds 80% of max_connections" \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --statistic Maximum \
    --period 60 \
    --threshold 1280 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --treat-missing-data notBreaching
```

The `--threshold 1280` assumes `max_connections` is 1600 (default for db.r6g.large). 80% of 1600 = 1280. Adjust this based on your instance class.

### 3.4 Create the EventBridge Rule

```bash
aws events put-rule \
    --name devops-lab-connection-storm-trigger \
    --event-pattern '{
        "source": ["aws.cloudwatch"],
        "detail-type": ["CloudWatch Alarm State Change"],
        "detail": {
            "alarmName": ["devops-lab-connection-storm"],
            "state": {
                "value": ["ALARM"]
            }
        }
    }' \
    --description "Trigger connection storm runbook when alarm fires" \
    --state ENABLED
```

The `event-pattern` matches CloudWatch alarm state changes. The rule only fires when the alarm transitions to the ALARM state.

```bash
aws lambda add-permission \
    --function-name devops-lab-connection-storm \
    --statement-id EventBridgeConnectionStorm \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:us-east-1:123456789012:rule/devops-lab-connection-storm-trigger
```

```bash
aws events put-targets \
    --rule devops-lab-connection-storm-trigger \
    --targets "Id=1,Arn=arn:aws:lambda:us-east-1:123456789012:function:devops-lab-connection-storm"
```

---

## Section 4: Runbook 2 - Storage Exhaustion Alert

### 4.1 Create the Lambda Function

```bash
mkdir -p ~/sre-practice/lambda/storage-alert
```

```bash
vi ~/sre-practice/lambda/storage-alert/lambda_function.py
```

```python
"""
Storage Exhaustion Runbook Automation
Triggered when FreeStorageSpace drops below threshold.
Actions:
1. Check current storage usage
2. Identify largest tables and bloat
3. Check for inactive replication slots
4. Send diagnostic report
"""

import json
import os
import boto3
import psycopg2

secrets_client = boto3.client('secretsmanager')
sns_client = boto3.client('sns')


def get_db_credentials():
    secret_name = os.environ['DB_SECRET_NAME']
    response = secrets_client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])


def check_table_sizes(conn):
    """Get the largest tables by total size."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            schemaname || '.' || tablename AS table_name,
            pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename))
                AS total_size,
            pg_total_relation_size(schemaname || '.' || tablename) AS size_bytes
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
        LIMIT 10;
    """)
    rows = cursor.fetchall()
    cursor.close()
    return rows


def check_bloat(conn):
    """Estimate table bloat."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            schemaname || '.' || relname AS table_name,
            n_dead_tup AS dead_tuples,
            n_live_tup AS live_tuples,
            CASE
                WHEN n_live_tup > 0
                THEN round(n_dead_tup::numeric / n_live_tup * 100, 1)
                ELSE 0
            END AS dead_pct,
            last_autovacuum
        FROM pg_stat_user_tables
        WHERE n_dead_tup > 10000
        ORDER BY n_dead_tup DESC
        LIMIT 10;
    """)
    rows = cursor.fetchall()
    cursor.close()
    return rows


def check_replication_slots(conn):
    """Check for inactive replication slots retaining WAL."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            slot_name,
            slot_type,
            active,
            pg_size_pretty(
                pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
            ) AS retained_wal
        FROM pg_replication_slots
        ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC;
    """)
    rows = cursor.fetchall()
    cursor.close()
    return rows


def lambda_handler(event, context):
    """Main handler - diagnose storage exhaustion."""
    print(f"Storage alert runbook triggered. Event: {json.dumps(event)}")

    creds = get_db_credentials()
    conn = psycopg2.connect(
        host=creds['host'],
        port=int(creds['port']),
        user=creds['username'],
        password=creds['password'],
        dbname=creds['dbname'],
        connect_timeout=5
    )

    try:
        tables = check_table_sizes(conn)
        bloat = check_bloat(conn)
        slots = check_replication_slots(conn)

        report = []
        report.append("STORAGE EXHAUSTION RUNBOOK - AUTOMATED DIAGNOSIS")
        report.append("=" * 50)

        report.append("")
        report.append("LARGEST TABLES:")
        for name, size, _ in tables:
            report.append(f"  {name}: {size}")

        if bloat:
            report.append("")
            report.append("TABLES WITH HIGH BLOAT (> 10,000 dead tuples):")
            for name, dead, live, pct, last_vac in bloat:
                report.append(f"  {name}: {dead} dead tuples ({pct}%), "
                              f"last vacuum: {last_vac}")

        if slots:
            report.append("")
            report.append("REPLICATION SLOTS:")
            for name, stype, active, wal in slots:
                status = "ACTIVE" if active else "INACTIVE"
                report.append(f"  {name} ({stype}): {status}, "
                              f"retained WAL: {wal}")
                if not active:
                    report.append(f"    WARNING: Inactive slot retaining WAL. "
                                  f"Consider dropping if consumer is gone.")

        report.append("")
        report.append("RECOMMENDED ACTIONS:")
        report.append("  1. VACUUM tables with high bloat")
        report.append("  2. Drop inactive replication slots")
        report.append("  3. Archive or delete old data")
        report.append("  4. If Aurora - storage auto-scales, "
                      "but check for WAL retention from inactive slots")

        report_text = "\n".join(report)
        print(report_text)

        sns_topic = os.environ.get('SNS_TOPIC_ARN')
        if sns_topic:
            sns_client.publish(
                TopicArn=sns_topic,
                Subject="Storage Alert - devops-lab-cluster",
                Message=report_text
            )

        return {'statusCode': 200, 'body': 'Diagnosis complete'}

    finally:
        conn.close()
```

Save and exit vi (`:wq`).

### 4.2 Package and Deploy

```bash
cd ~/sre-practice/lambda/storage-alert
```

```bash
cp ../health-check/requirements.txt .
```

```bash
pip install -r requirements.txt -t ./package
```

```bash
cd package && zip -r ../storage-alert.zip . && cd ..
```

```bash
zip storage-alert.zip lambda_function.py
```

```bash
aws lambda create-function \
    --function-name devops-lab-storage-alert \
    --runtime python3.12 \
    --role arn:aws:iam::123456789012:role/devops-lab-lambda-dba-role \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://storage-alert.zip \
    --timeout 60 \
    --memory-size 256 \
    --vpc-config SubnetIds=subnet-xxxxxxxxx,subnet-yyyyyyyyy,SecurityGroupIds=sg-zzzzzzzzz \
    --environment "Variables={DB_SECRET_NAME=devops-lab-cluster/dba-monitor,SNS_TOPIC_ARN=arn:aws:sns:us-east-1:123456789012:devops-lab-dba-alerts}"
```

---

## Section 5: Runbook 3 - Replication Lag Response

### 5.1 Create the Lambda Function

```bash
mkdir -p ~/sre-practice/lambda/replication-lag
```

```bash
vi ~/sre-practice/lambda/replication-lag/lambda_function.py
```

```python
"""
Replication Lag Runbook Automation
Triggered when AuroraReplicaLag exceeds threshold.
Actions:
1. Check for long-running transactions on writer
2. Check write throughput
3. Check reader instance status
4. Send diagnostic report
"""

import json
import os
import boto3
import psycopg2
from datetime import datetime, timedelta

secrets_client = boto3.client('secretsmanager')
sns_client = boto3.client('sns')
rds_client = boto3.client('rds')
cloudwatch_client = boto3.client('cloudwatch')


def get_db_credentials():
    secret_name = os.environ['DB_SECRET_NAME']
    response = secrets_client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])


def check_long_transactions(conn):
    """Find transactions that have been open too long."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            pid,
            usename,
            datname,
            state,
            left(query, 150) AS query,
            round(extract(epoch FROM now() - xact_start)::numeric, 0)
                AS txn_age_seconds,
            wait_event_type,
            wait_event
        FROM pg_stat_activity
        WHERE xact_start IS NOT NULL
          AND extract(epoch FROM now() - xact_start) > 60
          AND backend_type = 'client backend'
          AND pid != pg_backend_pid()
        ORDER BY xact_start ASC;
    """)
    rows = cursor.fetchall()
    cursor.close()
    return rows


def check_write_throughput(cluster_name):
    """Check recent write IOPS from CloudWatch."""
    now = datetime.utcnow()
    response = cloudwatch_client.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='VolumeWriteIOPs',
        Dimensions=[
            {'Name': 'DBClusterIdentifier', 'Value': cluster_name}
        ],
        StartTime=now - timedelta(minutes=30),
        EndTime=now,
        Period=300,
        Statistics=['Average', 'Maximum']
    )
    return response.get('Datapoints', [])


def check_reader_status(cluster_name):
    """Check the status of reader instances."""
    response = rds_client.describe_db_clusters(
        DBClusterIdentifier=cluster_name
    )
    cluster = response['DBClusters'][0]

    readers = []
    for member in cluster.get('DBClusterMembers', []):
        if not member['IsClusterWriter']:
            inst = rds_client.describe_db_instances(
                DBInstanceIdentifier=member['DBInstanceIdentifier']
            )
            db_inst = inst['DBInstances'][0]
            readers.append({
                'instance': member['DBInstanceIdentifier'],
                'status': db_inst['DBInstanceStatus'],
                'az': db_inst['AvailabilityZone'],
                'class': db_inst['DBInstanceClass']
            })

    return readers


def lambda_handler(event, context):
    """Main handler - diagnose replication lag."""
    print(f"Replication lag runbook triggered. Event: {json.dumps(event)}")

    cluster_name = os.environ.get('CLUSTER_NAME', 'devops-lab-cluster')
    creds = get_db_credentials()

    conn = psycopg2.connect(
        host=creds['host'],
        port=int(creds['port']),
        user=creds['username'],
        password=creds['password'],
        dbname=creds['dbname'],
        connect_timeout=5
    )

    try:
        long_txns = check_long_transactions(conn)
        write_iops = check_write_throughput(cluster_name)
        readers = check_reader_status(cluster_name)

        report = []
        report.append("REPLICATION LAG RUNBOOK - AUTOMATED DIAGNOSIS")
        report.append("=" * 50)

        report.append("")
        report.append("READER INSTANCES:")
        for r in readers:
            report.append(f"  {r['instance']}: {r['status']} "
                          f"({r['class']}, {r['az']})")

        if long_txns:
            report.append("")
            report.append(f"LONG-RUNNING TRANSACTIONS ({len(long_txns)} found):")
            report.append("  (Long transactions block replay on readers)")
            for pid, user, db, state, query, age, wetype, we in long_txns:
                report.append(f"  PID {pid}: user={user}, db={db}, "
                              f"age={age}s, state={state}")
                report.append(f"    Query: {query}")
                if wetype:
                    report.append(f"    Wait: {wetype}/{we}")
        else:
            report.append("")
            report.append("LONG-RUNNING TRANSACTIONS: None found")

        if write_iops:
            report.append("")
            report.append("WRITE IOPS (last 30 minutes):")
            for dp in sorted(write_iops, key=lambda x: x['Timestamp']):
                report.append(f"  {dp['Timestamp']}: avg={dp.get('Average', 'N/A')}, "
                              f"max={dp.get('Maximum', 'N/A')}")

        report.append("")
        report.append("RECOMMENDED ACTIONS:")
        if long_txns:
            report.append("  1. Investigate long-running transactions - "
                          "they block reader replay")
            report.append("  2. Consider terminating transactions > 10 minutes")
        report.append("  3. Check if readers need larger instance class")
        report.append("  4. Review write workload - batch jobs can cause "
                      "temporary lag spikes")

        report_text = "\n".join(report)
        print(report_text)

        sns_topic = os.environ.get('SNS_TOPIC_ARN')
        if sns_topic:
            sns_client.publish(
                TopicArn=sns_topic,
                Subject="Replication Lag Alert - devops-lab-cluster",
                Message=report_text
            )

        return {'statusCode': 200, 'body': 'Diagnosis complete'}

    finally:
        conn.close()
```

Save and exit vi (`:wq`).

### 5.2 Package and Deploy

```bash
cd ~/sre-practice/lambda/replication-lag
```

```bash
cp ../health-check/requirements.txt .
```

```bash
pip install -r requirements.txt -t ./package
```

```bash
cd package && zip -r ../replication-lag.zip . && cd ..
```

```bash
zip replication-lag.zip lambda_function.py
```

```bash
aws lambda create-function \
    --function-name devops-lab-replication-lag \
    --runtime python3.12 \
    --role arn:aws:iam::123456789012:role/devops-lab-lambda-dba-role \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://replication-lag.zip \
    --timeout 60 \
    --memory-size 256 \
    --vpc-config SubnetIds=subnet-xxxxxxxxx,subnet-yyyyyyyyy,SecurityGroupIds=sg-zzzzzzzzz \
    --environment "Variables={DB_SECRET_NAME=devops-lab-cluster/dba-monitor,CLUSTER_NAME=devops-lab-cluster,SNS_TOPIC_ARN=arn:aws:sns:us-east-1:123456789012:devops-lab-dba-alerts}"
```

---

## Section 6: Wire Up All EventBridge Rules

### 6.1 Storage Alert Rule

Create the CloudWatch alarm first:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "devops-lab-storage-warning" \
    --alarm-description "Storage usage exceeding 85% threshold" \
    --namespace AWS/RDS \
    --metric-name FreeStorageSpace \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --statistic Minimum \
    --period 300 \
    --threshold 5368709120 \
    --comparison-operator LessThanThreshold \
    --evaluation-periods 2 \
    --treat-missing-data notBreaching
```

The `--threshold 5368709120` is 5 GB in bytes. Adjust based on your total storage.

Create the EventBridge rule:

```bash
aws events put-rule \
    --name devops-lab-storage-alert-trigger \
    --event-pattern '{
        "source": ["aws.cloudwatch"],
        "detail-type": ["CloudWatch Alarm State Change"],
        "detail": {
            "alarmName": ["devops-lab-storage-warning"],
            "state": {"value": ["ALARM"]}
        }
    }' \
    --state ENABLED
```

```bash
aws lambda add-permission \
    --function-name devops-lab-storage-alert \
    --statement-id EventBridgeStorage \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:us-east-1:123456789012:rule/devops-lab-storage-alert-trigger
```

```bash
aws events put-targets \
    --rule devops-lab-storage-alert-trigger \
    --targets "Id=1,Arn=arn:aws:lambda:us-east-1:123456789012:function:devops-lab-storage-alert"
```

### 6.2 Replication Lag Rule

```bash
aws events put-rule \
    --name devops-lab-replication-lag-trigger \
    --event-pattern '{
        "source": ["aws.cloudwatch"],
        "detail-type": ["CloudWatch Alarm State Change"],
        "detail": {
            "alarmName": ["devops-lab-cluster-replication-lag"],
            "state": {"value": ["ALARM"]}
        }
    }' \
    --state ENABLED
```

```bash
aws lambda add-permission \
    --function-name devops-lab-replication-lag \
    --statement-id EventBridgeRepLag \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:us-east-1:123456789012:rule/devops-lab-replication-lag-trigger
```

```bash
aws events put-targets \
    --rule devops-lab-replication-lag-trigger \
    --targets "Id=1,Arn=arn:aws:lambda:us-east-1:123456789012:function:devops-lab-replication-lag"
```

---

## Section 7: Test the Automation Pipeline

### 7.1 Test Each Lambda Manually

```bash
aws lambda invoke \
    --function-name devops-lab-connection-storm \
    --payload '{"source": "manual-test"}' \
    /tmp/conn-storm-result.json
```

```bash
cat /tmp/conn-storm-result.json
```

```bash
aws lambda invoke \
    --function-name devops-lab-storage-alert \
    --payload '{"source": "manual-test"}' \
    /tmp/storage-result.json
```

```bash
cat /tmp/storage-result.json
```

```bash
aws lambda invoke \
    --function-name devops-lab-replication-lag \
    --payload '{"source": "manual-test"}' \
    /tmp/rep-lag-result.json
```

```bash
cat /tmp/rep-lag-result.json
```

### 7.2 Verify All Rules

```bash
aws events list-rules \
    --name-prefix devops-lab \
    --query 'Rules[].{Name:Name,State:State}' \
    --output table
```

Expected output (yours will differ):
```
------------------------------------------------------
|                      ListRules                     |
+---------------------------------------------+------+
|                    Name                     | State |
+---------------------------------------------+------+
| devops-lab-connection-storm-trigger         | ENABLED |
| devops-lab-health-check-schedule            | ENABLED |
| devops-lab-replication-lag-trigger          | ENABLED |
| devops-lab-slow-query-schedule              | ENABLED |
| devops-lab-storage-alert-trigger            | ENABLED |
+---------------------------------------------+------+
```

---

## Cleanup

To remove all runbook automation resources:

```bash
aws events remove-targets --rule devops-lab-connection-storm-trigger --ids 1
aws events remove-targets --rule devops-lab-storage-alert-trigger --ids 1
aws events remove-targets --rule devops-lab-replication-lag-trigger --ids 1
aws events delete-rule --name devops-lab-connection-storm-trigger
aws events delete-rule --name devops-lab-storage-alert-trigger
aws events delete-rule --name devops-lab-replication-lag-trigger
aws lambda delete-function --function-name devops-lab-connection-storm
aws lambda delete-function --function-name devops-lab-storage-alert
aws lambda delete-function --function-name devops-lab-replication-lag
aws cloudwatch delete-alarms --alarm-names devops-lab-connection-storm devops-lab-storage-warning
aws sns delete-topic --topic-arn arn:aws:sns:us-east-1:123456789012:devops-lab-dba-alerts
```

---

## Summary

| What You Did | Why It Matters |
|-------------|---------------|
| Created SNS topic for alerts | Centralized notification channel for all runbook outputs |
| Built connection storm runbook | Automated diagnosis + kill idle-in-txn sessions |
| Built storage exhaustion runbook | Automated identification of bloat and inactive slots |
| Built replication lag runbook | Automated detection of long transactions blocking replay |
| Wired CloudWatch alarms to EventBridge | Alarm fires - Lambda runs - DBA gets a report |
| Tested the full pipeline | Verified end-to-end: alarm to Lambda to SNS |

The on-call DBA now wakes up to a diagnostic report, not a raw alert. This reduces MTTR by front-loading the investigation that would otherwise happen manually at 2 AM.

**Next:** [USE 01 - SLO Design Exercise](../use/01-slo-design-exercise.md)
