# Tier 7 - Scaling, Integration, and Modern Patterns
## Guide 04: Lambda from RDS PostgreSQL and S3 Import/Export

**Objective:** Configure an Aurora PostgreSQL cluster to invoke AWS Lambda functions directly from database triggers, then use the aws_s3 extension to import CSV data from S3 and export query results back to S3.
**Time:** 40 minutes
**Prerequisites:** An Aurora PostgreSQL cluster. An S3 bucket. Basic understanding of IAM roles and AWS Lambda.
**Infrastructure:** You will create a small Lambda function and IAM roles. Both are effectively free at lab scale.

---

## Part A: Calling Lambda from RDS PostgreSQL

### A1. Understand the Flow

Aurora PostgreSQL can call Lambda functions using the `aws_lambda` extension. The call travels:

```
PostgreSQL trigger or function
  -> aws_lambda extension
    -> IAM role attached to the RDS cluster
      -> Lambda function
        -> returns result (if synchronous)
```

This enables you to push database events out to external systems without polling. A row inserted in PostgreSQL can trigger a notification, an API call, a workflow - without any application-layer code watching for changes.

### A2. Create the IAM Role for RDS to Call Lambda

The RDS cluster needs an IAM role that permits calling Lambda.

**Step 1.** Create the trust policy document:

```bash
cat > /tmp/rds-lambda-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```

This trust policy allows the RDS service to assume the role. The `Principal` `rds.amazonaws.com` grants RDS permission to call `sts:AssumeRole` to get credentials for the role.

**Step 2.** Create the IAM role:

```bash
aws iam create-role \
  --role-name RDSLambdaInvokeRole \
  --assume-role-policy-document file:///tmp/rds-lambda-trust-policy.json
```

Note the `Arn` from the output. You will attach this role to your RDS cluster.

**Step 3.** Create the permission policy:

```bash
cat > /tmp/rds-lambda-invoke-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": "*"
    }
  ]
}
EOF
```

In production, restrict `Resource` to the specific Lambda function ARNs. The wildcard `*` is used here for lab simplicity.

**Step 4.** Attach the policy to the role:

```bash
aws iam put-role-policy \
  --role-name RDSLambdaInvokeRole \
  --policy-name InvokeLambdaPolicy \
  --policy-document file:///tmp/rds-lambda-invoke-policy.json
```

**Step 5.** Associate the role with your Aurora cluster:

```bash
aws rds add-role-to-db-cluster \
  --db-cluster-identifier [YOUR-AURORA-CLUSTER] \
  --role-arn arn:aws:iam::[ACCOUNT-ID]:role/RDSLambdaInvokeRole \
  --feature-name Lambda \
  --region [REGION]
```

The `--feature-name Lambda` flag registers the role specifically for the Lambda integration feature.

**Step 6.** Verify the role is associated:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier [YOUR-AURORA-CLUSTER] \
  --region [REGION] \
  --query 'DBClusters[0].AssociatedRoles'
```

Expected output:
```json
[
    {
        "RoleArn": "arn:aws:iam::[ACCOUNT-ID]:role/RDSLambdaInvokeRole",
        "Status": "ACTIVE",
        "FeatureName": "Lambda"
    }
]
```

The `Status` must be `ACTIVE` before you can use the integration. It takes 1-2 minutes after adding the role.

### Console: Create the IAM Role for RDS to Call Lambda

If you prefer to use the AWS Console instead of the CLI, follow these steps to create the `RDSLambdaInvokeRole`.

1. Open the AWS Console at [https://console.aws.amazon.com](https://console.aws.amazon.com) and sign in.
2. In the top search bar, type `IAM` and click **IAM** under Services.
3. In the left sidebar, click **Roles**.
4. Click the orange **Create role** button in the top right.
5. On the **Select trusted entity** page:
   - Under **Trusted entity type**, select **AWS service**.
   - Scroll down to the **Use case** dropdown. In the search box type `RDS`, then select **RDS - Add Role to Database**.
   - Click **Next**.
6. On the **Add permissions** page, click **Next** (you will add an inline policy in a moment).
7. On the **Name, review, and create** page:
   - In the **Role name** field, type `RDSLambdaInvokeRole`.
   - Click **Create role**.

   You should land back on the **Roles** list. You will see `RDSLambdaInvokeRole` in the table.

8. Click **RDSLambdaInvokeRole** to open it.
9. Click the **Add permissions** dropdown, then choose **Create inline policy**.
10. Click the **JSON** tab (top right of the policy editor).
11. Replace the existing text with:
    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "lambda:InvokeFunction",
          "Resource": "*"
        }
      ]
    }
    ```
12. Click **Next**.
13. In the **Policy name** field, type `InvokeLambdaPolicy`.
14. Click **Create policy**.

    You should see `InvokeLambdaPolicy` listed under the **Permissions policies** tab of the role.

15. Copy the **ARN** shown at the top of the role detail page (it looks like `arn:aws:iam::[ACCOUNT-ID]:role/RDSLambdaInvokeRole`). You will need this to attach the role to your Aurora cluster.

To attach the role to your Aurora cluster via the Console:

1. In the top search bar, type `RDS` and click **RDS** under Services.
2. In the left sidebar, click **Databases**.
3. Click your Aurora **cluster** name (not a reader/writer instance - the cluster row).
4. Click the **Connectivity & security** tab.
5. Scroll down to the **Manage IAM roles** section.
6. Under **Add IAM roles to this cluster**, open the **Choose a role** dropdown and select **RDSLambdaInvokeRole**.
7. Open the **Choose a feature** dropdown and select **Lambda**.
8. Click **Add role**.

   The role will appear in the table with a **Status** of **Pending**. Refresh after 1-2 minutes until it shows **Active**.

### A3. Create the Lambda Function

This Lambda function receives an order event from PostgreSQL and logs it (simulating a notification system).

**Step 1.** Create the function code:

```bash
cat > /tmp/order_notifier.py << 'EOF'
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info(f"Order event received: {json.dumps(event)}")

    order_id = event.get("order_id")
    status = event.get("status")
    customer_id = event.get("customer_id")

    # In production, this would send an email, push to SQS, call an API, etc.
    message = f"Order {order_id} for customer {customer_id} moved to status: {status}"
    logger.info(message)

    return {
        "statusCode": 200,
        "message": message
    }
EOF

zip /tmp/order_notifier.zip /tmp/order_notifier.py
```

**Step 2.** Create an IAM role for the Lambda function itself:

```bash
cat > /tmp/lambda-trust-policy.json << 'EOF'
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
EOF

aws iam create-role \
  --role-name OrderNotifierLambdaRole \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json

aws iam attach-role-policy \
  --role-name OrderNotifierLambdaRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

The `AWSLambdaBasicExecutionRole` managed policy gives Lambda permission to write logs to CloudWatch. It is the minimum required role for any Lambda function.

**Step 3.** Deploy the Lambda function:

```bash
aws lambda create-function \
  --function-name order-status-notifier \
  --runtime python3.12 \
  --role arn:aws:iam::[ACCOUNT-ID]:role/OrderNotifierLambdaRole \
  --handler order_notifier.handler \
  --zip-file fileb:///tmp/order_notifier.zip \
  --timeout 10 \
  --region [REGION]
```

The `--handler order_notifier.handler` tells Lambda to call the `handler` function inside the `order_notifier.py` file. The `--timeout 10` sets a 10-second execution limit.

Note the `FunctionArn` from the output.

### Console: Create the IAM Role for Lambda and Deploy the Function

Use these steps if you prefer the AWS Console over the CLI for creating the Lambda execution role and the function itself.

**Part 1: Create the Lambda execution role**

1. Open the AWS Console at [https://console.aws.amazon.com](https://console.aws.amazon.com) and sign in.
2. In the top search bar, type `IAM` and click **IAM** under Services.
3. In the left sidebar, click **Roles**.
4. Click the orange **Create role** button.
5. On the **Select trusted entity** page:
   - Under **Trusted entity type**, select **AWS service**.
   - Under **Use case**, select **Lambda**.
   - Click **Next**.
6. On the **Add permissions** page, in the search box type `AWSLambdaBasicExecutionRole`.
7. Check the box next to **AWSLambdaBasicExecutionRole** (it is listed under AWS managed policies).
8. Click **Next**.
9. In the **Role name** field, type `OrderNotifierLambdaRole`.
10. Click **Create role**.

    You should land back on the **Roles** list. You will see `OrderNotifierLambdaRole` in the table.

**Part 2: Create the Lambda function**

1. In the top search bar, type `Lambda` and click **Lambda** under Services.
2. In the left sidebar, click **Functions**.
3. Click the orange **Create function** button in the top right.
4. On the **Create function** page:
   - Select **Author from scratch** (should already be selected).
   - In the **Function name** field, type `order-status-notifier`.
   - In the **Runtime** dropdown, select **Python 3.12**.
   - Leave **Architecture** as `x86_64`.
5. Under **Permissions**, expand **Change default execution role**.
   - Select **Use an existing role**.
   - In the **Existing role** dropdown, choose **OrderNotifierLambdaRole**.
6. Click **Create function**.

   You will land on the function detail page. You will see a **Code source** panel at the bottom.

7. In the **Code source** panel, click on `lambda_function.py` in the file tree on the left to open it.
8. Replace the entire contents of the file with the Python code from Step 1 of the CLI section above (the `order_notifier.py` content). Change the first line of the handler definition to match: the handler is `lambda_function.handler` in the console by default, so rename the function from `handler` to `handler` - no change needed, but make sure the function name matches `lambda_function.handler`.
9. Click **Deploy** (the button above the code editor).

   You should see a green banner: **Successfully updated the function order-status-notifier.**

10. Scroll up to the top of the function page and copy the **Function ARN** (it looks like `arn:aws:lambda:[REGION]:[ACCOUNT-ID]:function:order-status-notifier`). You will need this for the PostgreSQL trigger.

**Part 3: Update the handler (important)**

By default the console sets the handler to `lambda_function.lambda_handler`. You need to update it to match the code you pasted.

1. Click the **Configuration** tab (next to **Code**).
2. In the left menu, click **General configuration**.
3. Click **Edit**.
4. In the **Handler** field, change the value to `lambda_function.handler`.
5. Click **Save**.

### A4. Install the aws_lambda Extension and Create the Trigger

Connect to your Aurora PostgreSQL database.

**Step 1.** Install the extension:

```sql
CREATE EXTENSION IF NOT EXISTS aws_lambda CASCADE;
```

The `CASCADE` flag automatically installs dependencies (`aws_commons` extension).

**Step 2.** Create a trigger function that calls Lambda:

```sql
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
  payload JSON;
  response JSON;
BEGIN
  -- Build the payload to send to Lambda
  payload := json_build_object(
    'order_id',    NEW.order_id,
    'customer_id', NEW.customer_id,
    'status',      NEW.status,
    'old_status',  OLD.status,
    'updated_at',  NOW()
  );

  -- Call Lambda asynchronously (Event invocation type = fire and forget)
  SELECT payload INTO response
  FROM aws_lambda.invoke(
    aws_commons.create_lambda_function_arn(
      'order-status-notifier',
      '[REGION]'
    ),
    payload,
    'Event'   -- 'Event' = async, 'RequestResponse' = sync
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

The `'Event'` invocation type fires the Lambda call and returns immediately without waiting for the Lambda function to complete. This is important: synchronous Lambda calls (`'RequestResponse'`) block the PostgreSQL transaction and can cause timeout issues if Lambda is slow.

**Step 3.** Create the trigger:

```sql
CREATE TRIGGER order_status_change_trigger
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION notify_order_status_change();
```

The `WHEN (OLD.status IS DISTINCT FROM NEW.status)` condition fires the trigger only when the status column actually changes. Without this condition, any UPDATE to the orders row (even unrelated columns) would trigger the Lambda call.

**Step 4.** Test the trigger:

```sql
UPDATE orders SET status = 'shipped' WHERE order_id = 1;
```

**Step 5.** Check Lambda logs in CloudWatch:

```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/order-status-notifier \
  --start-time $(date -d '5 minutes ago' +%s000) \
  --filter-pattern "Order event received" \
  --region [REGION]
```

The `--filter-pattern` flag searches log events matching the string. The `--start-time` is in milliseconds since epoch.

### Console: View Lambda Function Logs in CloudWatch

After triggering the Lambda function with the SQL `UPDATE` command, use these steps to confirm your function ran and see its log output.

1. Open the AWS Console at [https://console.aws.amazon.com](https://console.aws.amazon.com) and sign in.
2. In the top search bar, type `Lambda` and click **Lambda** under Services.
3. In the left sidebar, click **Functions**.
4. Click **order-status-notifier** in the function list.
5. Click the **Monitor** tab (it sits between **Code** and **Configuration**).
6. You will see a set of graphs: **Invocations**, **Duration**, **Error count**, and others. The **Invocations** graph should show at least one spike after you ran the `UPDATE` statement.
7. To read the actual log lines, click the **View CloudWatch logs** button in the top right of the **Monitor** tab.

   This opens CloudWatch Logs and takes you directly to the log group `/aws/lambda/order-status-notifier`.

8. Under **Log streams**, you will see one or more rows. Each row is one Lambda container's log output. Click the most recent row (the top row, with the most recent **Last event time**).

9. You will see log entries. Look for lines that contain:
   - `Order event received:` followed by the JSON payload.
   - `Order [ID] for customer [ID] moved to status: shipped`

   These lines confirm the trigger fired and Lambda received the payload from PostgreSQL.

10. To filter across all streams, go back one level (click `/aws/lambda/order-status-notifier` in the breadcrumb at the top).
11. Click **Search log group** in the top right.
12. In the **Filter events** box, type `Order event received` and press Enter.
13. You will see all matching log lines across all Lambda invocations, with their timestamp.

---

## Part B: S3 Import and Export Using aws_s3

### B1. Create the IAM Role for S3 Access

**Step 1.** Create the trust policy (same as before, for RDS):

```bash
cat > /tmp/rds-s3-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name RDSS3AccessRole \
  --assume-role-policy-document file:///tmp/rds-s3-trust-policy.json
```

**Step 2.** Create the S3 policy:

```bash
cat > /tmp/rds-s3-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::[YOUR-BUCKET-NAME]",
        "arn:aws:s3:::[YOUR-BUCKET-NAME]/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::[YOUR-BUCKET-NAME]/*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name RDSS3AccessRole \
  --policy-name S3ReadWritePolicy \
  --policy-document file:///tmp/rds-s3-policy.json
```

**Step 3.** Associate the role with your Aurora cluster:

```bash
aws rds add-role-to-db-cluster \
  --db-cluster-identifier [YOUR-AURORA-CLUSTER] \
  --role-arn arn:aws:iam::[ACCOUNT-ID]:role/RDSS3AccessRole \
  --feature-name s3Import \
  --region [REGION]
```

For S3 export, add a second association with `--feature-name s3Export`:

```bash
aws rds add-role-to-db-cluster \
  --db-cluster-identifier [YOUR-AURORA-CLUSTER] \
  --role-arn arn:aws:iam::[ACCOUNT-ID]:role/RDSS3AccessRole \
  --feature-name s3Export \
  --region [REGION]
```

### B2. Install the aws_s3 Extension

Connect to your database:

```sql
CREATE EXTENSION IF NOT EXISTS aws_s3 CASCADE;
```

### B3. Import CSV Data from S3

**Step 1.** Create a sample CSV and upload it to S3:

```bash
cat > /tmp/new_customers.csv << 'EOF'
email,country
new_customer_1@example.com,US
new_customer_2@example.com,DE
new_customer_3@example.com,FR
new_customer_4@example.com,JP
new_customer_5@example.com,AU
EOF

aws s3 cp /tmp/new_customers.csv s3://[YOUR-BUCKET-NAME]/imports/new_customers.csv \
  --region [REGION]
```

**Step 2.** Import the CSV from S3 into PostgreSQL:

```sql
SELECT aws_s3.table_import_from_s3(
  'customers',                    -- target table name
  'email,country',                -- column list (must match CSV columns)
  '(FORMAT CSV, HEADER true)',    -- COPY options
  aws_commons.create_s3_uri(
    '[YOUR-BUCKET-NAME]',         -- bucket name
    'imports/new_customers.csv',  -- object key
    '[REGION]'                    -- region
  )
);
```

The first argument is the table name. The second is a comma-separated column list matching the CSV header. The third argument is passed directly to PostgreSQL's `COPY FROM` command - `FORMAT CSV` means parse as CSV, `HEADER true` means skip the first row.

Expected output:
```
 table_import_from_s3
----------------------
 5
(1 row)
```

The number returned is the count of rows imported. Verify:

```sql
SELECT * FROM customers ORDER BY customer_id DESC LIMIT 5;
```

### B4. Export Query Results to S3

```sql
SELECT aws_s3.query_export_to_s3(
  'SELECT order_id, customer_id, status, unit_price * quantity AS total
   FROM orders
   WHERE status = ''completed''
   ORDER BY order_id',
  aws_commons.create_s3_uri(
    '[YOUR-BUCKET-NAME]',
    'exports/completed_orders.csv',
    '[REGION]'
  ),
  options := 'FORMAT CSV, HEADER true'
);
```

The first argument is the query to run. The result rows are streamed directly to the S3 object. The `options` parameter controls the output format.

Expected output:
```
            query_export_to_s3
-------------------------------------------
 (2487,2487,0)
(1 row)
```

The three numbers are: rows uploaded, files created, and bytes uploaded. Verify the export:

```bash
aws s3 ls s3://[YOUR-BUCKET-NAME]/exports/ --region [REGION]
aws s3 cp s3://[YOUR-BUCKET-NAME]/exports/completed_orders.csv - --region [REGION] | head -5
```

### B5. Import a Large File Using Parallel Processing

For large CSVs, split the file into parts and import in parallel using multiple connections. PostgreSQL's COPY is single-threaded per statement, but running multiple imports concurrently speeds up large loads.

**Split a large file:**

```bash
# Split a large CSV into 100,000-row chunks
split -l 100000 large_data.csv chunk_
# Upload all chunks to S3
for f in chunk_*; do
  aws s3 cp "$f" "s3://[YOUR-BUCKET-NAME]/imports/$f.csv" --region [REGION]
done
```

**Import all chunks in parallel from psql:**

```sql
-- Run these in separate sessions or using psql's \parallel mode

-- Session 1:
SELECT aws_s3.table_import_from_s3('orders', 'customer_id,product_sku,quantity,unit_price,status',
  '(FORMAT CSV)', aws_commons.create_s3_uri('[BUCKET]', 'imports/chunk_aa.csv', '[REGION]'));

-- Session 2:
SELECT aws_s3.table_import_from_s3('orders', 'customer_id,product_sku,quantity,unit_price,status',
  '(FORMAT CSV)', aws_commons.create_s3_uri('[BUCKET]', 'imports/chunk_ab.csv', '[REGION]'));
```

---

## Summary

What you did in this lab:

- Created an IAM role allowing RDS to invoke Lambda functions.
- Deployed a Python Lambda function that receives order events.
- Installed the `aws_lambda` extension and created a PostgreSQL trigger that calls Lambda asynchronously on status changes.
- Created an IAM role for S3 access and associated it with the Aurora cluster.
- Installed the `aws_s3` extension.
- Imported a CSV from S3 into a PostgreSQL table using `table_import_from_s3`.
- Exported query results to S3 using `query_export_to_s3`.

**Key things to remember:**
- Use asynchronous Lambda invocation (`'Event'`) from triggers. Synchronous calls block the transaction.
- The IAM role must be in `ACTIVE` status before the extensions work. Check `describe-db-clusters AssociatedRoles`.
- S3 import uses PostgreSQL's `COPY FROM` under the hood. The options string accepts any valid `COPY` option.
- Tables without a primary key can still be imported to via S3 - the `aws_s3` import does not require a primary key.
- Large S3 imports: split files and run parallel sessions for better throughput.
