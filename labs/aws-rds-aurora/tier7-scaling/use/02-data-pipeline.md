# Tier 7 - USE Exercise 02: Data Pipeline

**Exercise type:** Hands-on implementation
**Time:** 45 minutes
**Goal:** Build an end-to-end data pipeline: Aurora PostgreSQL -> Zero-ETL -> Redshift, with automated S3 export of daily summaries.
**Prerequisites:** Build 03 and Build 04 completed. Aurora cluster with Zero-ETL enabled. Redshift Serverless workgroup running.

---

## Overview

You will build a pipeline that:
1. Stores operational order data in Aurora PostgreSQL.
2. Replicates it in near-real-time to Redshift via Zero-ETL.
3. Runs analytical queries in Redshift.
4. Exports a daily summary to S3 using `aws_s3.query_export_to_s3`.

---

## Part 1: Extend the Orders Schema

On your Aurora PostgreSQL cluster, add the tables needed for this exercise.

**Step 1.** Connect to your Aurora cluster and extend the schema:

```sql
-- Add a regions lookup table
CREATE TABLE regions (
  region_id   SERIAL PRIMARY KEY,
  region_name VARCHAR(50) NOT NULL,
  country     VARCHAR(50) NOT NULL
);

INSERT INTO regions (region_name, country) VALUES
  ('Northeast', 'US'),
  ('Southeast', 'US'),
  ('Midwest',   'US'),
  ('West',      'US'),
  ('UK',        'UK'),
  ('Germany',   'DE');

-- Add a dimension to orders
ALTER TABLE orders ADD COLUMN region_id INTEGER REFERENCES regions(region_id);

-- Populate region for existing orders
UPDATE orders SET region_id = (RANDOM() * 5 + 1)::INTEGER;
```

**Step 2.** Verify the schema:

```sql
SELECT r.region_name, COUNT(o.order_id) AS order_count
FROM orders o
JOIN regions r ON o.region_id = r.region_id
GROUP BY r.region_name
ORDER BY order_count DESC;
```

Write down the row counts per region. You will validate these appear in Redshift.

---

## Part 2: Validate Zero-ETL Replication

**Step 1.** Check that the new `regions` table replicated to Redshift.

If your Zero-ETL integration was created before you added the `regions` table, new tables added after integration creation need to be added to the integration:

In the console, go to **RDS > Zero-ETL integrations > aurora-to-redshift-lab > Edit** and add `regions` to the data filter if needed. Or via CLI:

```bash
aws rds modify-integration \
  --integration-identifier [INTEGRATION-ARN] \
  --data-filter 'include: *.orders, include: *.regions, include: *.customers' \
  --region [REGION]
```

**Step 2.** Query the `regions` table in Redshift:

```sql
-- In Redshift query editor
SELECT region_name, COUNT(*) AS orders
FROM orders o
JOIN regions r ON o.region_id = r.region_id
GROUP BY region_name
ORDER BY orders DESC;
```

The counts should match what you saw in Aurora.

**Step 3.** Insert a new order in Aurora and time how long it takes to appear in Redshift:

```sql
-- In Aurora
INSERT INTO orders (customer_id, product_sku, quantity, unit_price, status, region_id)
VALUES (1, 'SKU-PIPELINE-TEST', 1, 199.99, 'pending', 1)
RETURNING order_id;
```

Note the `order_id` returned. Now check Redshift every 30 seconds until the row appears:

```sql
-- In Redshift
SELECT order_id, product_sku, status FROM orders WHERE product_sku = 'SKU-PIPELINE-TEST';
```

Record the replication latency in seconds.

---

## Part 3: Analytical Queries in Redshift

Redshift is optimized for analytical queries that would be expensive in PostgreSQL. Run these queries in Redshift and compare how long they take to run the equivalent in Aurora.

**Query 1: Regional revenue by month**

```sql
SELECT
  r.region_name,
  DATE_TRUNC('month', o.created_at) AS month,
  COUNT(*) AS orders,
  SUM(o.unit_price * o.quantity) AS revenue,
  AVG(o.unit_price * o.quantity) AS avg_order_value
FROM orders o
JOIN regions r ON o.region_id = r.region_id
WHERE o.status = 'completed'
GROUP BY r.region_name, DATE_TRUNC('month', o.created_at)
ORDER BY month, revenue DESC;
```

**Query 2: Customer cohort analysis**

```sql
SELECT
  DATE_TRUNC('month', c.created_at) AS signup_cohort,
  COUNT(DISTINCT c.customer_id) AS customers,
  COUNT(DISTINCT o.order_id) AS total_orders,
  ROUND(COUNT(DISTINCT o.order_id)::DECIMAL / COUNT(DISTINCT c.customer_id), 2) AS orders_per_customer
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY DATE_TRUNC('month', c.created_at)
ORDER BY signup_cohort;
```

**Query 3: Top products by revenue**

```sql
SELECT
  product_sku,
  COUNT(*) AS order_count,
  SUM(unit_price * quantity) AS total_revenue,
  RANK() OVER (ORDER BY SUM(unit_price * quantity) DESC) AS revenue_rank
FROM orders
WHERE status = 'completed'
GROUP BY product_sku
ORDER BY revenue_rank
LIMIT 20;
```

Record the execution time for each query. These are the kinds of queries that would strain Aurora under concurrent user load.

---

## Part 4: Automated S3 Export from Aurora

You will create a PostgreSQL function that generates a daily summary and exports it to S3.

**Step 1.** Ensure the `aws_s3` extension is installed (from Build 04):

```sql
-- Verify extension is present
SELECT extname FROM pg_extension WHERE extname = 'aws_s3';
```

**Step 2.** Create the daily summary export function:

```sql
CREATE OR REPLACE FUNCTION export_daily_summary(export_date DATE DEFAULT CURRENT_DATE - 1)
RETURNS TEXT AS $$
DECLARE
  s3_key TEXT;
  result RECORD;
BEGIN
  s3_key := 'reports/daily/' || TO_CHAR(export_date, 'YYYY/MM/DD') || '/order_summary.csv';

  SELECT * INTO result FROM aws_s3.query_export_to_s3(
    format(
      'SELECT
        r.region_name,
        o.status,
        COUNT(*) AS order_count,
        SUM(o.unit_price * o.quantity) AS revenue,
        MIN(o.created_at) AS first_order,
        MAX(o.created_at) AS last_order
       FROM orders o
       JOIN regions r ON o.region_id = r.region_id
       WHERE o.created_at::DATE = %L
       GROUP BY r.region_name, o.status
       ORDER BY r.region_name, o.status',
      export_date
    ),
    aws_commons.create_s3_uri(
      '[YOUR-BUCKET-NAME]',
      s3_key,
      '[REGION]'
    ),
    options := 'FORMAT CSV, HEADER true'
  );

  RETURN format('Exported to s3://[YOUR-BUCKET-NAME]/%s: %s rows, %s files',
    s3_key, result.rows_uploaded, result.files_uploaded);
END;
$$ LANGUAGE plpgsql;
```

**Step 3.** Test the function:

```sql
SELECT export_daily_summary(CURRENT_DATE);
```

Expected output:
```
                              export_daily_summary
------------------------------------------------------------------------------------
 Exported to s3://[YOUR-BUCKET-NAME]/reports/daily/2024/03/15/order_summary.csv: 12 rows, 1 files
(1 row)
```

**Step 4.** Verify the file in S3:

```bash
aws s3 ls s3://[YOUR-BUCKET-NAME]/reports/daily/ --recursive --region [REGION]
```

**Step 5.** Download and inspect:

```bash
aws s3 cp \
  s3://[YOUR-BUCKET-NAME]/reports/daily/$(date +%Y/%m/%d)/order_summary.csv \
  /tmp/daily_summary.csv \
  --region [REGION]

cat /tmp/daily_summary.csv
```

---

## Part 5: Automate the Export with EventBridge

Set up a daily automated export using EventBridge Scheduler calling the function via Lambda.

**Step 1.** Create a Lambda function wrapper:

```bash
cat > /tmp/daily_export.py << 'EOF'
import boto3
import os

def handler(event, context):
    client = boto3.client('rds-data', region_name=os.environ['AWS_REGION'])

    response = client.execute_statement(
        resourceArn=os.environ['CLUSTER_ARN'],
        secretArn=os.environ['SECRET_ARN'],
        database='postgres',
        sql='SELECT export_daily_summary(CURRENT_DATE - 1)'
    )

    result = response['records'][0][0]['stringValue']
    print(f"Export result: {result}")
    return {'statusCode': 200, 'result': result}
EOF

zip /tmp/daily_export.zip /tmp/daily_export.py
```

**Step 2.** Deploy the Lambda function:

```bash
aws lambda create-function \
  --function-name aurora-daily-export \
  --runtime python3.12 \
  --role arn:aws:iam::[ACCOUNT-ID]:role/OrderNotifierLambdaRole \
  --handler daily_export.handler \
  --zip-file fileb:///tmp/daily_export.zip \
  --timeout 300 \
  --environment Variables='{
    CLUSTER_ARN="[YOUR-CLUSTER-ARN]",
    SECRET_ARN="[YOUR-SECRET-ARN]"
  }' \
  --region [REGION]
```

**Step 3.** Create the EventBridge schedule:

```bash
aws events put-rule \
  --name daily-aurora-export \
  --schedule-expression "cron(0 2 * * ? *)" \
  --state ENABLED \
  --region [REGION]
```

The cron expression `cron(0 2 * * ? *)` fires at 2:00 AM UTC every day.

```bash
aws events put-targets \
  --rule daily-aurora-export \
  --targets "Id=1,Arn=arn:aws:lambda:[REGION]:[ACCOUNT-ID]:function:aurora-daily-export" \
  --region [REGION]
```

---

## Validation Checklist

Before marking this exercise complete, verify:

- [ ] `regions` table exists in both Aurora and Redshift with the same data.
- [ ] A test order inserted in Aurora appeared in Redshift within 5 minutes.
- [ ] All three analytical queries ran successfully in Redshift.
- [ ] `export_daily_summary()` function exists and produces a CSV in S3.
- [ ] The S3 CSV has the correct columns and the data matches Aurora.
- [ ] EventBridge rule `daily-aurora-export` is in `ENABLED` state.

---

## Reflection Questions

1. The Zero-ETL integration replicates changes in near-real-time. If an analyst runs the Redshift queries during a peak Aurora write period, could they see inconsistent data? Why or why not?

2. The daily export runs at 2 AM UTC. If your application is used globally and writes happen 24/7, what does "yesterday's data" mean? How would you handle timezone-aware reporting?

3. You have 500,000 completed orders and the S3 export takes 8 minutes. A stakeholder wants hourly exports. What would you change about the approach?
