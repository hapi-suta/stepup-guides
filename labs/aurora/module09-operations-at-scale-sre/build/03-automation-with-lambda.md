# BUILD 03: Automation with Lambda

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 60-75 minutes
**Level:** Intermediate

---

## Objective

Build Lambda functions that automate common DBA tasks for Aurora PostgreSQL: automated health checks, slow query detection, and connection monitoring. By the end of this guide, you will have three Lambda functions deployed and scheduled via EventBridge to run automatically.

---

## Prerequisites

- Aurora PostgreSQL cluster `devops-lab-cluster` running
- AWS CLI configured with appropriate permissions
- Python 3.12 runtime available in your region
- VPC with private subnets where Aurora runs

---

## Section 1: Create the IAM Role for Lambda

Lambda functions need an IAM role that grants permission to access RDS, CloudWatch, and VPC networking.

### 1.1 Create the Trust Policy

```bash
mkdir -p ~/sre-practice/lambda
```

```bash
vi ~/sre-practice/lambda/lambda-trust-policy.json
```

Add this content:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

Save and exit vi (`:wq`).

This trust policy allows the Lambda service to assume this role. Without it, Lambda cannot run with these permissions.

### 1.2 Create the IAM Role

```bash
aws iam create-role \
    --role-name devops-lab-lambda-dba-role \
    --assume-role-policy-document file://~/sre-practice/lambda/lambda-trust-policy.json \
    --description "Role for DBA automation Lambda functions"
```

Expected output (yours will differ):
```json
{
    "Role": {
        "RoleName": "devops-lab-lambda-dba-role",
        "Arn": "arn:aws:iam::123456789012:role/devops-lab-lambda-dba-role",
        ...
    }
}
```

Save the Role ARN - you will need it when creating Lambda functions.

### 1.3 Attach Required Policies

Attach the managed policies for CloudWatch Logs, VPC access, and RDS data API:

```bash
aws iam attach-role-policy \
    --role-name devops-lab-lambda-dba-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
```

The `AWSLambdaVPCAccessExecutionRole` policy grants Lambda permission to create network interfaces in your VPC (required to connect to Aurora) and write logs to CloudWatch.

```bash
aws iam attach-role-policy \
    --role-name devops-lab-lambda-dba-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess
```

This policy allows the Lambda function to describe RDS instances and clusters (for health check metadata).

### 1.4 Create a Custom Policy for CloudWatch Metrics

```bash
vi ~/sre-practice/lambda/cloudwatch-policy.json
```

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData",
                "cloudwatch:GetMetricStatistics",
                "sns:Publish"
            ],
            "Resource": "*"
        }
    ]
}
```

Save and exit vi (`:wq`).

```bash
aws iam put-role-policy \
    --role-name devops-lab-lambda-dba-role \
    --policy-name devops-lab-cloudwatch-publish \
    --policy-document file://~/sre-practice/lambda/cloudwatch-policy.json
```

The `put-role-policy` command creates an inline policy directly on the role. The `cloudwatch:PutMetricData` action allows Lambda to publish custom metrics. The `sns:Publish` action allows sending alert notifications.

---

## Section 2: Store Database Credentials in Secrets Manager

Never hardcode database passwords in Lambda function code. Use Secrets Manager instead.

### 2.1 Create the Secret

```bash
aws secretsmanager create-secret \
    --name devops-lab-cluster/dba-monitor \
    --description "Monitoring credentials for devops-lab-cluster" \
    --secret-string '{"username":"dba_monitor","password":"CHANGE_ME_TO_A_STRONG_PASSWORD","host":"devops-lab-cluster.cluster-xxxxxxxxxxxx.us-east-1.rds.amazonaws.com","port":"5432","dbname":"postgres"}'
```

Replace `CHANGE_ME_TO_A_STRONG_PASSWORD` with a strong password and update the host to your actual Aurora writer endpoint.

Expected output (yours will differ):
```json
{
    "ARN": "arn:aws:secretsmanager:us-east-1:123456789012:secret:devops-lab-cluster/dba-monitor-AbCdEf",
    "Name": "devops-lab-cluster/dba-monitor"
}
```

### 2.2 Grant Lambda Access to the Secret

```bash
vi ~/sre-practice/lambda/secrets-policy.json
```

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:devops-lab-cluster/dba-monitor-*"
        }
    ]
}
```

Replace the ARN with your actual secret ARN. The wildcard at the end matches the random suffix Secrets Manager appends.

Save and exit vi (`:wq`).

```bash
aws iam put-role-policy \
    --role-name devops-lab-lambda-dba-role \
    --policy-name devops-lab-secrets-access \
    --policy-document file://~/sre-practice/lambda/secrets-policy.json
```

### 2.3 Create the Monitoring User in Aurora

Connect to your Aurora writer endpoint:

```bash
psql -h devops-lab-cluster.cluster-xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

Create the monitoring user with read-only access:

```sql
CREATE USER dba_monitor WITH PASSWORD 'CHANGE_ME_TO_A_STRONG_PASSWORD';
GRANT pg_monitor TO dba_monitor;
GRANT USAGE ON SCHEMA public TO dba_monitor;
```

The `pg_monitor` role is a built-in PostgreSQL role that grants read access to monitoring views like `pg_stat_activity`, `pg_stat_statements`, and `pg_stat_database`.

Expected output:
```
CREATE ROLE
GRANT ROLE
GRANT
```

Exit psql:

```
\q
```

---

## Section 3: Build the Health Check Lambda

### 3.1 Create the Function Code

```bash
mkdir -p ~/sre-practice/lambda/health-check
```

```bash
vi ~/sre-practice/lambda/health-check/lambda_function.py
```

```python
"""
Aurora PostgreSQL Health Check Lambda
Runs every 5 minutes via EventBridge.
Publishes custom CloudWatch metrics for SLO tracking.
"""

import json
import os
import time
import boto3
import psycopg2

secrets_client = boto3.client('secretsmanager')
cloudwatch_client = boto3.client('cloudwatch')


def get_db_credentials():
    """Retrieve database credentials from Secrets Manager."""
    secret_name = os.environ['DB_SECRET_NAME']
    response = secrets_client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])


def check_availability(conn):
    """Run a simple query to verify the database is responsive."""
    start = time.time()
    cursor = conn.cursor()
    cursor.execute("SELECT 1;")
    cursor.fetchone()
    cursor.close()
    elapsed_ms = (time.time() - start) * 1000
    return True, elapsed_ms


def check_replication_lag(conn):
    """Check replication status from the writer's perspective."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            client_addr,
            state,
            sent_lsn,
            write_lsn,
            flush_lsn,
            replay_lsn,
            extract(epoch FROM now() - backend_start) AS connection_age_seconds
        FROM pg_stat_replication;
    """)
    rows = cursor.fetchall()
    cursor.close()
    return rows


def check_connection_count(conn):
    """Check current connection count and utilization."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            count(*) AS total_connections,
            count(*) FILTER (WHERE state = 'active') AS active_connections,
            count(*) FILTER (WHERE state = 'idle') AS idle_connections,
            count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_txn,
            current_setting('max_connections')::int AS max_connections
        FROM pg_stat_activity
        WHERE backend_type = 'client backend';
    """)
    row = cursor.fetchone()
    cursor.close()
    return {
        'total': row[0],
        'active': row[1],
        'idle': row[2],
        'idle_in_txn': row[3],
        'max_connections': row[4],
        'utilization_pct': round(row[0] / row[4] * 100, 1)
    }


def check_error_rate(conn):
    """Check transaction error rate from pg_stat_database."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            datname,
            xact_commit,
            xact_rollback,
            round(
                xact_rollback::numeric /
                NULLIF(xact_commit + xact_rollback, 0) * 100,
                4
            ) AS error_rate_pct
        FROM pg_stat_database
        WHERE datname NOT LIKE 'template%%'
          AND datname IS NOT NULL
          AND (xact_commit + xact_rollback) > 0;
    """)
    rows = cursor.fetchall()
    cursor.close()
    return rows


def publish_metrics(availability, latency_ms, connections, error_rates):
    """Publish custom CloudWatch metrics for SLO tracking."""
    cluster_name = os.environ.get('CLUSTER_NAME', 'devops-lab-cluster')
    metrics = [
        {
            'MetricName': 'HealthCheckAvailability',
            'Value': 1.0 if availability else 0.0,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'ClusterIdentifier', 'Value': cluster_name}
            ]
        },
        {
            'MetricName': 'HealthCheckLatency',
            'Value': latency_ms,
            'Unit': 'Milliseconds',
            'Dimensions': [
                {'Name': 'ClusterIdentifier', 'Value': cluster_name}
            ]
        },
        {
            'MetricName': 'ConnectionUtilization',
            'Value': connections['utilization_pct'],
            'Unit': 'Percent',
            'Dimensions': [
                {'Name': 'ClusterIdentifier', 'Value': cluster_name}
            ]
        }
    ]

    for db_name, _, _, error_rate in error_rates:
        if error_rate is not None:
            metrics.append({
                'MetricName': 'TransactionErrorRate',
                'Value': float(error_rate),
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'ClusterIdentifier', 'Value': cluster_name},
                    {'Name': 'DatabaseName', 'Value': db_name}
                ]
            })

    cloudwatch_client.put_metric_data(
        Namespace='DBA/Aurora',
        MetricData=metrics
    )


def lambda_handler(event, context):
    """Main handler - runs all health checks and publishes metrics."""
    creds = get_db_credentials()

    try:
        conn = psycopg2.connect(
            host=creds['host'],
            port=int(creds['port']),
            user=creds['username'],
            password=creds['password'],
            dbname=creds['dbname'],
            connect_timeout=5
        )
    except Exception as e:
        print(f"CONNECTION FAILED: {e}")
        cloudwatch_client.put_metric_data(
            Namespace='DBA/Aurora',
            MetricData=[{
                'MetricName': 'HealthCheckAvailability',
                'Value': 0.0,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'ClusterIdentifier',
                     'Value': os.environ.get('CLUSTER_NAME', 'devops-lab-cluster')}
                ]
            }]
        )
        return {'statusCode': 500, 'body': f'Connection failed: {e}'}

    try:
        available, latency_ms = check_availability(conn)
        connections = check_connection_count(conn)
        error_rates = check_error_rate(conn)
        replication = check_replication_lag(conn)

        publish_metrics(available, latency_ms, connections, error_rates)

        result = {
            'available': available,
            'latency_ms': round(latency_ms, 2),
            'connections': connections,
            'error_rates': [
                {'database': r[0], 'error_rate_pct': float(r[3]) if r[3] else 0}
                for r in error_rates
            ],
            'replication_slots': len(replication)
        }

        print(f"Health check result: {json.dumps(result, default=str)}")
        return {'statusCode': 200, 'body': json.dumps(result, default=str)}

    finally:
        conn.close()
```

Save and exit vi (`:wq`).

### 3.2 Create the Requirements File

```bash
vi ~/sre-practice/lambda/health-check/requirements.txt
```

```
psycopg2-binary==2.9.9
```

Save and exit vi (`:wq`).

### 3.3 Package the Lambda Function

Lambda requires a ZIP file containing your code and dependencies.

```bash
cd ~/sre-practice/lambda/health-check
```

```bash
pip install -r requirements.txt -t ./package
```

The `-t ./package` flag installs the dependencies into a local directory instead of system-wide.

```bash
cd package && zip -r ../health-check.zip . && cd ..
```

```bash
zip health-check.zip lambda_function.py
```

The first `zip` command adds the dependencies. The second adds your function code on top.

### 3.4 Get VPC Configuration

Lambda needs VPC subnet and security group IDs to connect to Aurora:

```bash
aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].{VpcSecurityGroups:VpcSecurityGroups[].VpcSecurityGroupId,Subnets:DBSubnetGroup}' \
    --output yaml
```

Note the security group ID and subnet IDs from the output.

### 3.5 Deploy the Lambda Function

Replace the placeholder values with your actual VPC configuration:

```bash
aws lambda create-function \
    --function-name devops-lab-health-check \
    --runtime python3.12 \
    --role arn:aws:iam::123456789012:role/devops-lab-lambda-dba-role \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://health-check.zip \
    --timeout 30 \
    --memory-size 256 \
    --vpc-config SubnetIds=subnet-xxxxxxxxx,subnet-yyyyyyyyy,SecurityGroupIds=sg-zzzzzzzzz \
    --environment "Variables={DB_SECRET_NAME=devops-lab-cluster/dba-monitor,CLUSTER_NAME=devops-lab-cluster}"
```

The flags:
- `--runtime python3.12` - the Python version for the execution environment.
- `--handler lambda_function.lambda_handler` - tells Lambda which file and function to invoke. Format is `filename.function_name`.
- `--timeout 30` - maximum execution time in seconds. Health checks should complete in under 10 seconds, but 30 seconds allows for slow connections.
- `--memory-size 256` - RAM in MB. 256 MB is sufficient for database queries.
- `--vpc-config` - places the Lambda function inside your VPC so it can reach Aurora's private endpoint.
- `--environment` - sets environment variables that the code reads at runtime.

Expected output (yours will differ):
```json
{
    "FunctionName": "devops-lab-health-check",
    "FunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:devops-lab-health-check",
    "Runtime": "python3.12",
    "State": "Pending",
    ...
}
```

### 3.6 Test the Function

```bash
aws lambda invoke \
    --function-name devops-lab-health-check \
    --payload '{}' \
    /tmp/health-check-response.json
```

```bash
cat /tmp/health-check-response.json
```

Expected output (yours will differ):
```json
{
    "statusCode": 200,
    "body": "{\"available\": true, \"latency_ms\": 3.45, \"connections\": {\"total\": 5, \"active\": 1, \"idle\": 4, \"idle_in_txn\": 0, \"max_connections\": 1600, \"utilization_pct\": 0.3}, ...}"
}
```

---

## Section 4: Build the Slow Query Detector Lambda

### 4.1 Create the Function Code

```bash
mkdir -p ~/sre-practice/lambda/slow-query-detector
```

```bash
vi ~/sre-practice/lambda/slow-query-detector/lambda_function.py
```

```python
"""
Aurora PostgreSQL Slow Query Detector Lambda
Runs every 15 minutes via EventBridge.
Identifies queries exceeding latency SLO thresholds.
"""

import json
import os
import boto3
import psycopg2

secrets_client = boto3.client('secretsmanager')
sns_client = boto3.client('sns')


def get_db_credentials():
    """Retrieve database credentials from Secrets Manager."""
    secret_name = os.environ['DB_SECRET_NAME']
    response = secrets_client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])


def find_slow_queries(conn, threshold_ms):
    """Find queries that exceed the latency threshold."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            queryid,
            left(query, 200) AS query_text,
            round(mean_exec_time::numeric, 2) AS avg_ms,
            round(max_exec_time::numeric, 2) AS max_ms,
            calls,
            round(total_exec_time::numeric, 2) AS total_ms
        FROM pg_stat_statements
        WHERE mean_exec_time > %s
          AND query NOT LIKE '%%pg_stat%%'
          AND calls > 10
        ORDER BY mean_exec_time DESC
        LIMIT 20;
    """, (threshold_ms,))
    columns = [desc[0] for desc in cursor.description]
    rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    cursor.close()
    return rows


def find_long_running_queries(conn, threshold_seconds):
    """Find currently running queries exceeding threshold."""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            pid,
            usename,
            datname,
            left(query, 200) AS query_text,
            state,
            round(extract(epoch FROM now() - query_start)::numeric, 1)
                AS running_seconds,
            wait_event_type,
            wait_event
        FROM pg_stat_activity
        WHERE state = 'active'
          AND query NOT LIKE '%%pg_stat%%'
          AND extract(epoch FROM now() - query_start) > %s
          AND backend_type = 'client backend'
        ORDER BY query_start ASC;
    """, (threshold_seconds,))
    columns = [desc[0] for desc in cursor.description]
    rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    cursor.close()
    return rows


def lambda_handler(event, context):
    """Main handler - detects slow queries and alerts if found."""
    creds = get_db_credentials()
    latency_threshold_ms = float(os.environ.get('LATENCY_THRESHOLD_MS', '100'))
    long_running_threshold_s = float(os.environ.get('LONG_RUNNING_THRESHOLD_S', '300'))

    conn = psycopg2.connect(
        host=creds['host'],
        port=int(creds['port']),
        user=creds['username'],
        password=creds['password'],
        dbname=creds['dbname'],
        connect_timeout=5
    )

    try:
        slow_queries = find_slow_queries(conn, latency_threshold_ms)
        long_running = find_long_running_queries(conn, long_running_threshold_s)

        result = {
            'slow_queries_count': len(slow_queries),
            'long_running_count': len(long_running),
            'slow_queries': slow_queries[:5],
            'long_running': long_running
        }

        if slow_queries or long_running:
            print(f"ALERT: {len(slow_queries)} slow queries, "
                  f"{len(long_running)} long-running queries found")

            sns_topic = os.environ.get('SNS_TOPIC_ARN')
            if sns_topic:
                message = (
                    f"Slow Query Alert - devops-lab-cluster\n\n"
                    f"Slow queries (avg > {latency_threshold_ms}ms): "
                    f"{len(slow_queries)}\n"
                    f"Long-running (> {long_running_threshold_s}s): "
                    f"{len(long_running)}\n\n"
                )
                for q in slow_queries[:5]:
                    message += (
                        f"  Query: {q['query_text'][:100]}\n"
                        f"  Avg: {q['avg_ms']}ms, Max: {q['max_ms']}ms, "
                        f"Calls: {q['calls']}\n\n"
                    )
                sns_client.publish(
                    TopicArn=sns_topic,
                    Subject=f"Slow Query Alert - devops-lab-cluster",
                    Message=message
                )
        else:
            print("No slow queries detected")

        print(f"Result: {json.dumps(result, default=str)}")
        return {'statusCode': 200, 'body': json.dumps(result, default=str)}

    finally:
        conn.close()
```

Save and exit vi (`:wq`).

### 4.2 Package and Deploy

```bash
cd ~/sre-practice/lambda/slow-query-detector
```

```bash
cp ../health-check/requirements.txt .
```

```bash
pip install -r requirements.txt -t ./package
```

```bash
cd package && zip -r ../slow-query-detector.zip . && cd ..
```

```bash
zip slow-query-detector.zip lambda_function.py
```

```bash
aws lambda create-function \
    --function-name devops-lab-slow-query-detector \
    --runtime python3.12 \
    --role arn:aws:iam::123456789012:role/devops-lab-lambda-dba-role \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://slow-query-detector.zip \
    --timeout 60 \
    --memory-size 256 \
    --vpc-config SubnetIds=subnet-xxxxxxxxx,subnet-yyyyyyyyy,SecurityGroupIds=sg-zzzzzzzzz \
    --environment "Variables={DB_SECRET_NAME=devops-lab-cluster/dba-monitor,LATENCY_THRESHOLD_MS=100,LONG_RUNNING_THRESHOLD_S=300}"
```

---

## Section 5: Schedule with EventBridge

### 5.1 Create the Health Check Schedule (Every 5 Minutes)

```bash
aws events put-rule \
    --name devops-lab-health-check-schedule \
    --schedule-expression "rate(5 minutes)" \
    --description "Run Aurora health check every 5 minutes" \
    --state ENABLED
```

The `rate(5 minutes)` expression runs the rule every 5 minutes. Other valid expressions include `rate(1 hour)`, `rate(1 day)`, or cron syntax like `cron(0/5 * * * ? *)`.

Expected output (yours will differ):
```json
{
    "RuleArn": "arn:aws:events:us-east-1:123456789012:rule/devops-lab-health-check-schedule"
}
```

### 5.2 Grant EventBridge Permission to Invoke Lambda

```bash
aws lambda add-permission \
    --function-name devops-lab-health-check \
    --statement-id EventBridgeHealthCheck \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:us-east-1:123456789012:rule/devops-lab-health-check-schedule
```

This permission allows the EventBridge rule to invoke your Lambda function. Without it, EventBridge will fail silently.

### 5.3 Add Lambda as the Target

```bash
aws events put-targets \
    --rule devops-lab-health-check-schedule \
    --targets "Id=1,Arn=arn:aws:lambda:us-east-1:123456789012:function:devops-lab-health-check"
```

### 5.4 Schedule the Slow Query Detector (Every 15 Minutes)

```bash
aws events put-rule \
    --name devops-lab-slow-query-schedule \
    --schedule-expression "rate(15 minutes)" \
    --description "Run slow query detection every 15 minutes" \
    --state ENABLED
```

```bash
aws lambda add-permission \
    --function-name devops-lab-slow-query-detector \
    --statement-id EventBridgeSlowQuery \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:us-east-1:123456789012:rule/devops-lab-slow-query-schedule
```

```bash
aws events put-targets \
    --rule devops-lab-slow-query-schedule \
    --targets "Id=1,Arn=arn:aws:lambda:us-east-1:123456789012:function:devops-lab-slow-query-detector"
```

### 5.5 Verify the Schedules

```bash
aws events list-rules \
    --name-prefix devops-lab \
    --query 'Rules[].{Name:Name,Schedule:ScheduleExpression,State:State}' \
    --output table
```

Expected output (yours will differ):
```
--------------------------------------------------------------
|                         ListRules                          |
+-----------+---------------------------------+--------------+
|   Name    |           Schedule              |    State     |
+-----------+---------------------------------+--------------+
| devops-..health-check-schedule  | rate(5 minutes)  | ENABLED |
| devops-..slow-query-schedule    | rate(15 minutes) | ENABLED |
+-----------+---------------------------------+--------------+
```

---

## Section 6: Verify Custom Metrics in CloudWatch

After the health check Lambda has run at least once, check for custom metrics:

```bash
aws cloudwatch list-metrics \
    --namespace DBA/Aurora \
    --query 'Metrics[].{Name:MetricName,Dimensions:Dimensions[].Value}' \
    --output table
```

Expected output (yours will differ):
```
-------------------------------------------------
|                  ListMetrics                  |
+---------------------------+-------------------+
|           Name            |   Dimensions      |
+---------------------------+-------------------+
| HealthCheckAvailability   | devops-lab-cluster|
| HealthCheckLatency        | devops-lab-cluster|
| ConnectionUtilization     | devops-lab-cluster|
| TransactionErrorRate      | devops-lab-cluster|
+---------------------------+-------------------+
```

Query a specific metric:

```bash
aws cloudwatch get-metric-statistics \
    --namespace DBA/Aurora \
    --metric-name HealthCheckLatency \
    --dimensions Name=ClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Average Maximum \
    --output table
```

---

## Section 7: Check Lambda Execution Logs

### 7.1 View Recent Log Events

```bash
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/devops-lab \
    --query 'logGroups[].logGroupName' \
    --output text
```

```bash
aws logs tail /aws/lambda/devops-lab-health-check --since 1h --format short
```

The `tail` subcommand shows recent log events. The `--since 1h` flag limits output to the last hour.

Expected output (yours will differ):
```
2026-06-09T10:05:00 START RequestId: abc-123
2026-06-09T10:05:02 Health check result: {"available": true, "latency_ms": 3.45, ...}
2026-06-09T10:05:02 END RequestId: abc-123
2026-06-09T10:05:02 REPORT RequestId: abc-123 Duration: 2045.23 ms ...
```

---

## Cleanup

To remove the Lambda functions, EventBridge rules, IAM role, and secret:

```bash
aws events remove-targets --rule devops-lab-health-check-schedule --ids 1
aws events remove-targets --rule devops-lab-slow-query-schedule --ids 1
aws events delete-rule --name devops-lab-health-check-schedule
aws events delete-rule --name devops-lab-slow-query-schedule
aws lambda delete-function --function-name devops-lab-health-check
aws lambda delete-function --function-name devops-lab-slow-query-detector
aws iam detach-role-policy --role-name devops-lab-lambda-dba-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
aws iam detach-role-policy --role-name devops-lab-lambda-dba-role --policy-arn arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess
aws iam delete-role-policy --role-name devops-lab-lambda-dba-role --policy-name devops-lab-cloudwatch-publish
aws iam delete-role-policy --role-name devops-lab-lambda-dba-role --policy-name devops-lab-secrets-access
aws iam delete-role --role-name devops-lab-lambda-dba-role
aws secretsmanager delete-secret --secret-id devops-lab-cluster/dba-monitor --force-delete-without-recovery
```

Run each command separately. Some may fail if resources were not created - that is expected.

---

## Summary

| What You Did | Why It Matters |
|-------------|---------------|
| Created IAM role with least-privilege policies | Lambda needs specific permissions - not admin access |
| Stored credentials in Secrets Manager | Never hardcode passwords in function code |
| Built health check Lambda | Automated SLI collection every 5 minutes |
| Built slow query detector Lambda | Proactive detection of latency SLO violations |
| Published custom CloudWatch metrics | SLO dashboard data from inside the database |
| Scheduled with EventBridge | Fully automated - no human intervention needed |
| Verified logs and metrics | Confirmed the automation pipeline works end-to-end |

**Next:** [BUILD 04 - Multi-Account Management](./04-multi-account-management.md)
